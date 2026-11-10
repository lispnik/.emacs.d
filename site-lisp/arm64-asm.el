;;; arm64-asm.el --- Major mode for AArch64 (ARM64) assembly -*- lexical-binding: t; -*-

;; Author: Matthew Kennedy
;; Keywords: languages, asm, arm64, aarch64
;; Package-Requires: ((emacs "29.1"))

;;; Commentary:

;; A major mode for ARM64 assembly as written for the GNU assembler on Linux
;; and for Apple's clang assembler on macOS.  It understands both dialects:
;;
;;   Linux (GNU as):       //, /* */ comments; `;' separates statements;
;;                         :lo12:, :got:, :got_lo12: relocation operators;
;;                         .L-prefixed local labels.
;;   macOS (clang/Mach-O): //, /* */ and `;' comments; @PAGE, @PAGEOFF,
;;                         @GOTPAGE ... relocation operators; L-prefixed
;;                         local labels; leading underscore on C symbols.
;;
;; Whether `;' starts a comment is controlled by
;; `arm64-asm-semicolon-comments', which defaults to t on macOS only.
;;
;; Features:
;;
;;   - Syntax highlighting for mnemonics (branches stand out), directives,
;;     labels (global vs. local), registers (general purpose, SIMD/FP with
;;     arrangement specifiers, SVE, system registers), immediates,
;;     relocation operators, shift/extend operators, condition codes,
;;     macro arguments and C preprocessor lines (for .S files).
;;   - Indentation: labels and preprocessor lines at column 0, instructions
;;     and directives at `arm64-asm-indent-offset'; comment-only lines
;;     follow their neighbours.  Typing `:' after a label reindents it.
;;   - Eldoc: a one-line syntax summary for the instruction or directive on
;;     the current line.
;;   - Imenu and beginning/end-of-defun for global labels (functions).
;;   - `C-c C-c' assembles the file with `compile'; a Flymake backend
;;     reports assembler errors as you type.
;;
;; Usage:
;;
;;   (require 'arm64-asm)
;;   (add-to-list 'auto-mode-alist '("\\.[sS]\\'" . arm64-asm-mode))

;;; Code:

(require 'rx)
(require 'subr-x)

(defgroup arm64-asm nil
  "Major mode for AArch64 assembly."
  :group 'languages
  :prefix "arm64-asm-")

(defcustom arm64-asm-indent-offset 8
  "Column at which instructions and directives are indented."
  :type 'integer)

(defcustom arm64-asm-semicolon-comments (eq system-type 'darwin)
  "Non-nil means `;' starts a comment (Apple's assembler).
With GNU as on Linux, `;' separates statements on one line instead.
Takes effect when the mode is (re)started in a buffer."
  :type 'boolean)

(defcustom arm64-asm-local-label-regexp
  (if (eq system-type 'darwin)
      (rx bos (or ".L" "L" "ltmp" "lCPI" (+ digit)))
    (rx bos (or ".L" (+ digit))))
  "Regexp matching labels that are local, i.e. not functions.
Matched against the label name.  Local labels are highlighted
differently and are skipped by defun navigation."
  :type 'regexp)

(defcustom arm64-asm-assembler
  (cond ((eq system-type 'darwin) "clang -arch arm64")
        ((string-match-p "\\`aarch64" system-configuration) "cc")
        ((executable-find "aarch64-linux-gnu-gcc") "aarch64-linux-gnu-gcc")
        (t "cc"))
  "Compiler driver used to assemble files.
It is run as a C compiler driver (with -c, -x, -o), so a cross gcc
such as \"aarch64-linux-gnu-gcc\" works, and so does \"clang -arch
arm64\" or \"clang --target=aarch64-linux-gnu\"."
  :type 'string)

(defcustom arm64-asm-extra-flags nil
  "Extra flags passed to `arm64-asm-assembler', e.g. (\"-march=armv8.5-a\")."
  :type '(repeat string))


;;; Faces

(defface arm64-asm-mnemonic-face
  '((t :inherit font-lock-keyword-face))
  "Face for instruction mnemonics.")

(defface arm64-asm-branch-face
  '((t :inherit font-lock-keyword-face :weight bold))
  "Face for branch, call and return mnemonics.")

(defface arm64-asm-directive-face
  '((t :inherit font-lock-builtin-face))
  "Face for assembler directives such as .text and .globl.")

(defface arm64-asm-label-face
  '((t :inherit font-lock-function-name-face))
  "Face for global label definitions.")

(defface arm64-asm-local-label-face
  '((t :inherit font-lock-constant-face))
  "Face for local label definitions and numeric label references.")

(defface arm64-asm-register-face
  '((t :inherit font-lock-variable-name-face))
  "Face for register names.")

(defface arm64-asm-immediate-face
  '((t :inherit font-lock-constant-face))
  "Face for immediates and numbers.")

(defface arm64-asm-reloc-face
  '((t :inherit font-lock-type-face))
  "Face for relocation operators: :lo12:, @PAGEOFF and friends.")

(defface arm64-asm-operator-face
  '((t :inherit font-lock-builtin-face))
  "Face for shift/extend operators and condition-code operands.")


;;; Regexps

(defconst arm64-asm--label-re
  (rx line-start (* blank)
      (group (or (seq (any alpha "_.$\\") (* (any alnum "_.$\\@()")))
                 (+ digit)))
      ":" (not (any ":")))
  "Regexp matching a label definition; group 1 is the name.
The trailing char excludes `::'; the line must have something after
the colon, so callers match against the line plus a newline.")

(defconst arm64-asm--label-prefix-re
  (rx line-start (* blank)
      (* (or (seq (any alpha "_.$\\") (* (any alnum "_.$\\@()")))
             (+ digit))
         ":" (* blank)))
  "Regexp matching any labels at the start of a line.")

(defconst arm64-asm--branch-mnemonics
  '("b" "bl" "br" "blr" "ret" "cbz" "cbnz" "tbz" "tbnz" "eret"
    "braa" "brab" "braaz" "brabz" "blraa" "blrab" "blraaz" "blrabz"
    "retaa" "retab" "eretaa" "eretab"))

(defconst arm64-asm--condition-codes
  '("eq" "ne" "cs" "hs" "cc" "lo" "mi" "pl" "vs" "vc"
    "hi" "ls" "ge" "lt" "gt" "le" "al" "nv"))

(defconst arm64-asm--shift-operators
  '("lsl" "lsr" "asr" "ror" "msl"
    "uxtb" "uxth" "uxtw" "uxtx" "sxtb" "sxth" "sxtw" "sxtx"
    "mul" "vl"))

(defconst arm64-asm--register-re
  (let ((n (rx (or (seq (? (any "12")) digit) (seq "3" (any "01"))))))
    (rx-to-string
     `(seq symbol-start
           (or
            ;; General purpose.
            (seq (any "xw") (regexp ,n))
            "sp" "wsp" "xzr" "wzr" "lr" "fp" "ip0" "ip1" "pc"
            ;; SIMD/FP scalar and vector, with optional arrangement.
            (seq (any "vqdshb") (regexp ,n)
                 (? "." (* digit) (any "bhsdq")))
            ;; SVE vectors and predicates.
            (seq "z" (regexp ,n) (? "." (any "bhsdq")))
            (seq (or "p" "pn") (or digit (seq "1" (any "0-5")))
                 (? "." (any "bhsdq")))
            ;; SME.
            (seq "za" (? (regexp ,n)) (? (any "hv")) (? "." (any "bhsdq")))
            ;; System registers.
            "nzcv" "daif" "fpcr" "fpsr" "currentel" "spsel" "pan" "uao"
            "dit" "ssbs" "tco"
            (seq (+ (any alnum "_")) "_el" (any "0-3")))
           symbol-end)
     t))
  "Regexp matching a register name.")

(defconst arm64-asm--number-re
  (rx (or (seq "#" (? (any "-+"))
               (or (seq "0" (any "xX") (+ hex))
                   (seq "0" (any "bB") (+ (any "01")))
                   (seq (+ digit) (? "." (* digit))
                        (? (any "eE") (? (any "-+")) (+ digit)))))
          (seq symbol-start (? "-")
               (or (seq "0" (any "xX") (+ hex))
                   (seq "0" (any "bB") (+ (any "01")))
                   (+ digit))
               symbol-end)))
  "Regexp matching immediates and numeric literals.")

(defconst arm64-asm--mnemonic-re
  (concat arm64-asm--label-prefix-re
          (rx (group (any alpha) (* (any alnum "_")) (? "." (+ (any alnum "_"))))
              (or blank eol)))
  "Regexp matching a mnemonic (or macro call) at instruction position.")

(defconst arm64-asm--directive-re
  (concat arm64-asm--label-prefix-re
          (rx (group "." (any alpha "_") (* (any alnum "_")))
              (or blank eol)))
  "Regexp matching a directive at instruction position.")

(defun arm64-asm--branch-mnemonic-p (name)
  "Return non-nil if NAME is a branch, call or return mnemonic."
  (let ((name (downcase name)))
    (or (member name arm64-asm--branch-mnemonics)
        (string-match-p (rx bos (or "b" "bc") "." (+ alpha) eos) name))))

(defun arm64-asm--match-mnemonic (limit)
  "Font-lock matcher for mnemonics up to LIMIT.
Sets match data group 1 to the mnemonic and group 2 to whether it is
a branch, so the two can be highlighted differently."
  (let (found)
    (while (and (not found)
                (re-search-forward arm64-asm--mnemonic-re limit t))
      (unless (nth 8 (save-excursion (syntax-ppss (match-beginning 1))))
        (setq found t)))
    found))

(defun arm64-asm--mnemonic-face ()
  "Face for the mnemonic in match group 1."
  (if (arm64-asm--branch-mnemonic-p (match-string 1))
      'arm64-asm-branch-face
    'arm64-asm-mnemonic-face))

(defun arm64-asm--label-face ()
  "Face for the label in match group 1."
  (if (let ((case-fold-search nil))
        (string-match-p arm64-asm-local-label-regexp (match-string 1)))
      'arm64-asm-local-label-face
    'arm64-asm-label-face))

(defconst arm64-asm-font-lock-keywords
  `(;; C preprocessor (for .S files).
    (,(rx line-start (* blank) "#" (* blank) (+ alpha) symbol-end)
     . font-lock-preprocessor-face)
    ;; Label definitions.
    (,(rx line-start (* blank)
          (group (or (seq (any alpha "_.$\\") (* (any alnum "_.$\\@()")))
                     (+ digit)))
          ":" (or (not (any ":")) eol))
     1 (arm64-asm--label-face))
    ;; Directives.
    (,arm64-asm--directive-re 1 'arm64-asm-directive-face)
    ;; Mnemonics.
    (arm64-asm--match-mnemonic 1 (arm64-asm--mnemonic-face))
    ;; A second statement after `;' (GNU as).  Where `;' is a comment the
    ;; text is already fontified as one, so this does nothing.
    (,(rx ";" (* blank)
          (group (any alpha) (* (any alnum "_")) (? "." (+ (any alnum "_"))))
          (or blank eol))
     1 (arm64-asm--mnemonic-face))
    ;; Relocation operators.
    (,(rx (or (seq ":" (+ (any alnum "_")) ":")
              (seq "@" (or "PAGEOFF" "PAGE" "GOTPAGEOFF" "GOTPAGE"
                           "TLVPPAGEOFF" "TLVPPAGE" "GOT" "TLVP"
                           "PLT" "GOTPCREL"))))
     . 'arm64-asm-reloc-face)
    ;; Registers.
    (,arm64-asm--register-re . 'arm64-asm-register-face)
    ;; Shift/extend operators after a comma.
    (,(rx-to-string `(seq "," (* blank)
                          (group (or ,@arm64-asm--shift-operators))
                          symbol-end)
                    t)
     1 'arm64-asm-operator-face)
    ;; Condition-code operands (csel, ccmp, cset ...).
    (,(rx-to-string `(seq "," (* blank)
                          (group (or ,@arm64-asm--condition-codes))
                          (* blank) (or eol "/" ";" "//"))
                    t)
     1 'arm64-asm-operator-face)
    ;; Numeric local label references: 1b, 2f.
    (,(rx symbol-start (+ digit) (any "bf") symbol-end)
     . 'arm64-asm-local-label-face)
    ;; Immediates and numbers.
    (,arm64-asm--number-re . 'arm64-asm-immediate-face)
    ;; Macro arguments: \name.
    (,(rx "\\" (any alpha "_") (* (any alnum "_")))
     . font-lock-variable-name-face))
  "Font-lock keywords for `arm64-asm-mode'.")


;;; Syntax

(defvar arm64-asm-mode-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?/ ". 124b" st)
    (modify-syntax-entry ?* ". 23" st)
    (modify-syntax-entry ?\n "> b" st)
    (modify-syntax-entry ?\; "." st)
    (modify-syntax-entry ?_ "_" st)
    (modify-syntax-entry ?. "_" st)
    (modify-syntax-entry ?$ "_" st)
    (modify-syntax-entry ?# "." st)
    (modify-syntax-entry ?@ "." st)
    (modify-syntax-entry ?: "." st)
    (modify-syntax-entry ?! "." st)
    (modify-syntax-entry ?= "." st)
    (modify-syntax-entry ?' "." st)
    (modify-syntax-entry ?\" "\"" st)
    (modify-syntax-entry ?\\ "\\" st)
    st)
  "Syntax table for `arm64-asm-mode'.")


;;; Indentation

(defun arm64-asm--comment-line-p ()
  "Non-nil if the line at point holds only a comment."
  (save-excursion
    (back-to-indentation)
    (looking-at-p (if arm64-asm-semicolon-comments
                      (rx (or "//" "/*" ";"))
                    (rx (or "//" "/*"))))))

(defun arm64-asm--line-kind ()
  "Classify the line at point.
Returns one of `blank', `in-comment', `comment', `preproc', `label'
or `code'."
  (save-excursion
    (back-to-indentation)
    (cond ((nth 4 (syntax-ppss)) 'in-comment)
          ((eolp) 'blank)
          ((arm64-asm--comment-line-p) 'comment)
          ((looking-at-p (rx "#" (* blank) alpha)) 'preproc)
          ((let ((line (concat (buffer-substring (line-beginning-position)
                                                 (line-end-position))
                               "\n")))
             (string-match-p arm64-asm--label-re line))
           'label)
          (t 'code))))

(defun arm64-asm--comment-indent ()
  "Indentation for a comment-only line.
A comment attached to the line above follows it; otherwise it sits at
column 0 when it introduces a label (or the file's end), and at the
instruction column when it introduces code."
  (let ((prev (save-excursion
                (when (zerop (forward-line -1))
                  (cons (arm64-asm--line-kind) (current-indentation))))))
    (pcase (car prev)
      ('nil 0)                          ; first line of the file
      ((or 'code 'label) arm64-asm-indent-offset)
      ('comment (cdr prev))
      (_
       (save-excursion
         (let (kind)
           (while (and (zerop (forward-line 1))
                       (not (eobp))
                       (memq (setq kind (arm64-asm--line-kind))
                             '(blank comment in-comment)))
             (setq kind nil))
           (if (eq kind 'code) arm64-asm-indent-offset 0)))))))

(defun arm64-asm--calculate-indent ()
  "Return the column the current line should be indented to, or nil."
  (pcase (arm64-asm--line-kind)
    ('in-comment nil)
    ('blank nil)
    ((or 'preproc 'label) 0)
    ('comment (arm64-asm--comment-indent))
    (_ arm64-asm-indent-offset)))

(defun arm64-asm-indent-line ()
  "Indent the current line as AArch64 assembly."
  (interactive)
  (let ((col (or (arm64-asm--calculate-indent)
                 (and (eq (arm64-asm--line-kind) 'blank)
                      arm64-asm-indent-offset))))
    (when col
      (if (<= (current-column) (current-indentation))
          (indent-line-to col)
        (save-excursion (indent-line-to col))))))


;;; Navigation and imenu

(defun arm64-asm--defun-re ()
  "Regexp matching a global (non-local) label definition line."
  (rx line-start (group (any alpha "_$") (* (any alnum "_.$"))) ":"))

(defun arm64-asm--global-label-at-match-p ()
  "Non-nil if the label in match group 1 is global."
  (let ((case-fold-search nil))
    (not (string-match-p arm64-asm-local-label-regexp (match-string 1)))))

(defun arm64-asm-beginning-of-defun (&optional arg)
  "Move to the start of the ARGth preceding function label."
  (setq arg (or arg 1))
  (let ((re (arm64-asm--defun-re))
        (found nil))
    (if (> arg 0)
        (dotimes (_ arg)
          (setq found nil)
          (while (and (not found) (re-search-backward re nil 'move))
            (setq found (arm64-asm--global-label-at-match-p))))
      (dotimes (_ (- arg))
        (setq found nil)
        (end-of-line)
        (while (and (not found) (re-search-forward re nil 'move))
          (setq found (arm64-asm--global-label-at-match-p)))
        (when found (beginning-of-line))))
    found))

(defun arm64-asm-end-of-defun ()
  "Move to the end of the function at point: just before the next one."
  (if (arm64-asm-beginning-of-defun -1)
      (skip-chars-backward " \t\n")
    (goto-char (point-max)))
  (forward-line 1))

(defun arm64-asm--imenu-create-index ()
  "Imenu index: functions, local labels and macros."
  (let (funcs locals macros)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward
              (rx line-start (* blank)
                  (group (any alpha "_.$") (* (any alnum "_.$"))) ":")
              nil t)
        (unless (nth 8 (syntax-ppss))
          (push (cons (match-string-no-properties 1) (match-beginning 1))
                (if (arm64-asm--global-label-at-match-p) funcs locals))))
      (goto-char (point-min))
      (while (re-search-forward
              (rx line-start (* blank) ".macro" (+ blank)
                  (group (+ (any alnum "_.$"))))
              nil t)
        (push (cons (match-string-no-properties 1) (match-beginning 1))
              macros)))
    (append (nreverse funcs)
            (and locals (list (cons "Local labels" (nreverse locals))))
            (and macros (list (cons "Macros" (nreverse macros)))))))


;;; Eldoc

(defconst arm64-asm--instruction-docs
  #s(hash-table
     test equal
     data
     (;; Arithmetic.
      "add" "ADD Xd, Xn, Xm{, shift #n} | Xd, Xn, #imm{, lsl #12} -- add"
      "adds" "ADDS Xd, Xn, <Xm|#imm> -- add, set flags"
      "sub" "SUB Xd, Xn, Xm{, shift #n} | Xd, Xn, #imm{, lsl #12} -- subtract"
      "subs" "SUBS Xd, Xn, <Xm|#imm> -- subtract, set flags"
      "adc" "ADC Xd, Xn, Xm -- add with carry"
      "adcs" "ADCS Xd, Xn, Xm -- add with carry, set flags"
      "sbc" "SBC Xd, Xn, Xm -- subtract with carry"
      "sbcs" "SBCS Xd, Xn, Xm -- subtract with carry, set flags"
      "neg" "NEG Xd, Xm{, shift #n} -- negate (SUB Xd, XZR, Xm)"
      "negs" "NEGS Xd, Xm -- negate, set flags"
      "ngc" "NGC Xd, Xm -- negate with carry"
      "cmp" "CMP Xn, <Xm|#imm> -- compare (SUBS XZR, Xn, ...)"
      "cmn" "CMN Xn, <Xm|#imm> -- compare negative (ADDS XZR, Xn, ...)"
      "mul" "MUL Xd, Xn, Xm -- multiply (low 64 bits)"
      "madd" "MADD Xd, Xn, Xm, Xa -- Xd = Xa + Xn*Xm"
      "msub" "MSUB Xd, Xn, Xm, Xa -- Xd = Xa - Xn*Xm"
      "mneg" "MNEG Xd, Xn, Xm -- Xd = -(Xn*Xm)"
      "smull" "SMULL Xd, Wn, Wm -- signed 32x32->64 multiply"
      "umull" "UMULL Xd, Wn, Wm -- unsigned 32x32->64 multiply"
      "smaddl" "SMADDL Xd, Wn, Wm, Xa -- signed multiply-add long"
      "umaddl" "UMADDL Xd, Wn, Wm, Xa -- unsigned multiply-add long"
      "smulh" "SMULH Xd, Xn, Xm -- signed multiply, high 64 bits"
      "umulh" "UMULH Xd, Xn, Xm -- unsigned multiply, high 64 bits"
      "sdiv" "SDIV Xd, Xn, Xm -- signed divide (x/0 = 0)"
      "udiv" "UDIV Xd, Xn, Xm -- unsigned divide (x/0 = 0)"
      ;; Logical and bit manipulation.
      "and" "AND Xd, Xn, <Xm{, shift #n}|#bitmask> -- bitwise and"
      "ands" "ANDS Xd, Xn, <Xm|#bitmask> -- bitwise and, set flags"
      "orr" "ORR Xd, Xn, <Xm{, shift #n}|#bitmask> -- bitwise or"
      "eor" "EOR Xd, Xn, <Xm{, shift #n}|#bitmask> -- bitwise exclusive or"
      "bic" "BIC Xd, Xn, Xm{, shift #n} -- bit clear (Xn & ~Xm)"
      "bics" "BICS Xd, Xn, Xm -- bit clear, set flags"
      "orn" "ORN Xd, Xn, Xm{, shift #n} -- or not (Xn | ~Xm)"
      "eon" "EON Xd, Xn, Xm{, shift #n} -- exclusive or not"
      "mvn" "MVN Xd, Xm{, shift #n} -- bitwise not"
      "tst" "TST Xn, <Xm|#bitmask> -- test bits (ANDS XZR, ...)"
      "lsl" "LSL Xd, Xn, <Xm|#n> -- logical shift left"
      "lsr" "LSR Xd, Xn, <Xm|#n> -- logical shift right"
      "asr" "ASR Xd, Xn, <Xm|#n> -- arithmetic shift right"
      "ror" "ROR Xd, Xn, <Xm|#n> -- rotate right"
      "clz" "CLZ Xd, Xn -- count leading zeros"
      "cls" "CLS Xd, Xn -- count leading sign bits"
      "ctz" "CTZ Xd, Xn -- count trailing zeros (FEAT_CSSC)"
      "cnt" "CNT Xd, Xn | Vd.8B, Vn.8B -- population count"
      "rbit" "RBIT Xd, Xn -- reverse bits"
      "rev" "REV Xd, Xn -- reverse bytes"
      "rev16" "REV16 Xd, Xn -- reverse bytes in each halfword"
      "rev32" "REV32 Xd, Xn -- reverse bytes in each word"
      "abs" "ABS Xd, Xn -- absolute value (FEAT_CSSC)"
      "smax" "SMAX Xd, Xn, <Xm|#imm> -- signed maximum (FEAT_CSSC)"
      "smin" "SMIN Xd, Xn, <Xm|#imm> -- signed minimum (FEAT_CSSC)"
      "umax" "UMAX Xd, Xn, <Xm|#imm> -- unsigned maximum (FEAT_CSSC)"
      "umin" "UMIN Xd, Xn, <Xm|#imm> -- unsigned minimum (FEAT_CSSC)"
      ;; Bitfield.
      "bfi" "BFI Xd, Xn, #lsb, #width -- bitfield insert"
      "bfxil" "BFXIL Xd, Xn, #lsb, #width -- bitfield extract and insert low"
      "bfc" "BFC Xd, #lsb, #width -- bitfield clear"
      "ubfx" "UBFX Xd, Xn, #lsb, #width -- unsigned bitfield extract"
      "sbfx" "SBFX Xd, Xn, #lsb, #width -- signed bitfield extract"
      "ubfiz" "UBFIZ Xd, Xn, #lsb, #width -- unsigned bitfield insert in zero"
      "sbfiz" "SBFIZ Xd, Xn, #lsb, #width -- signed bitfield insert in zero"
      "bfm" "BFM Xd, Xn, #immr, #imms -- bitfield move"
      "ubfm" "UBFM Xd, Xn, #immr, #imms -- unsigned bitfield move"
      "sbfm" "SBFM Xd, Xn, #immr, #imms -- signed bitfield move"
      "extr" "EXTR Xd, Xn, Xm, #lsb -- extract register from pair"
      "sxtb" "SXTB Xd, Wn -- sign-extend byte"
      "sxth" "SXTH Xd, Wn -- sign-extend halfword"
      "sxtw" "SXTW Xd, Wn -- sign-extend word"
      "uxtb" "UXTB Wd, Wn -- zero-extend byte"
      "uxth" "UXTH Wd, Wn -- zero-extend halfword"
      ;; Moves.
      "mov" "MOV Xd, <Xn|#imm> -- move register or immediate"
      "movz" "MOVZ Xd, #imm16{, lsl #s} -- move wide with zero"
      "movk" "MOVK Xd, #imm16{, lsl #s} -- move wide with keep"
      "movn" "MOVN Xd, #imm16{, lsl #s} -- move wide with not"
      "adr" "ADR Xd, label -- PC-relative address (+/-1MB)"
      "adrp" "ADRP Xd, label@PAGE | label -- PC-relative 4KB page address (+/-4GB)"
      ;; Conditional.
      "csel" "CSEL Xd, Xn, Xm, cond -- Xd = cond ? Xn : Xm"
      "csinc" "CSINC Xd, Xn, Xm, cond -- Xd = cond ? Xn : Xm+1"
      "csinv" "CSINV Xd, Xn, Xm, cond -- Xd = cond ? Xn : ~Xm"
      "csneg" "CSNEG Xd, Xn, Xm, cond -- Xd = cond ? Xn : -Xm"
      "cset" "CSET Xd, cond -- Xd = cond ? 1 : 0"
      "csetm" "CSETM Xd, cond -- Xd = cond ? -1 : 0"
      "cinc" "CINC Xd, Xn, cond -- Xd = cond ? Xn+1 : Xn"
      "cinv" "CINV Xd, Xn, cond -- Xd = cond ? ~Xn : Xn"
      "cneg" "CNEG Xd, Xn, cond -- Xd = cond ? -Xn : Xn"
      "ccmp" "CCMP Xn, <Xm|#imm5>, #nzcv, cond -- conditional compare"
      "ccmn" "CCMN Xn, <Xm|#imm5>, #nzcv, cond -- conditional compare negative"
      ;; Branches.
      "b" "B label -- branch (+/-128MB)"
      "b.cond" "B.cond label -- conditional branch (+/-1MB)"
      "bc.cond" "BC.cond label -- conditional branch, consistent hint (FEAT_HBC)"
      "bl" "BL label -- branch with link (call); return address in LR"
      "br" "BR Xn -- branch to register"
      "blr" "BLR Xn -- branch with link to register (indirect call)"
      "ret" "RET {Xn} -- return (to LR by default)"
      "cbz" "CBZ Xt, label -- branch if zero (+/-1MB)"
      "cbnz" "CBNZ Xt, label -- branch if not zero (+/-1MB)"
      "tbz" "TBZ Xt, #bit, label -- branch if bit is zero (+/-32KB)"
      "tbnz" "TBNZ Xt, #bit, label -- branch if bit is not zero (+/-32KB)"
      "braa" "BRAA Xn, Xm -- branch to register, authenticate with key A"
      "blraa" "BLRAA Xn, Xm -- call register, authenticate with key A"
      "retaa" "RETAA -- return, authenticate LR with key A and SP"
      "retab" "RETAB -- return, authenticate LR with key B and SP"
      ;; Loads and stores.
      "ldr" "LDR Xt, [Xn{, #off}] | [Xn, #off]! | [Xn], #off | [Xn, Xm{, ext}] | label | =imm -- load register"
      "ldrb" "LDRB Wt, [Xn{, #off}] -- load byte, zero-extend"
      "ldrh" "LDRH Wt, [Xn{, #off}] -- load halfword, zero-extend"
      "ldrsb" "LDRSB Xt, [Xn{, #off}] -- load byte, sign-extend"
      "ldrsh" "LDRSH Xt, [Xn{, #off}] -- load halfword, sign-extend"
      "ldrsw" "LDRSW Xt, [Xn{, #off}] -- load word, sign-extend"
      "ldur" "LDUR Xt, [Xn{, #simm9}] -- load register, unscaled offset"
      "ldp" "LDP Xt1, Xt2, [Xn{, #off}] | [Xn, #off]! | [Xn], #off -- load pair"
      "ldpsw" "LDPSW Xt1, Xt2, [Xn{, #off}] -- load pair of words, sign-extend"
      "str" "STR Xt, [Xn{, #off}] | [Xn, #off]! | [Xn], #off | [Xn, Xm{, ext}] -- store register"
      "strb" "STRB Wt, [Xn{, #off}] -- store byte"
      "strh" "STRH Wt, [Xn{, #off}] -- store halfword"
      "stur" "STUR Xt, [Xn{, #simm9}] -- store register, unscaled offset"
      "stp" "STP Xt1, Xt2, [Xn{, #off}] | [Xn, #off]! | [Xn], #off -- store pair"
      "ldnp" "LDNP Xt1, Xt2, [Xn{, #off}] -- load pair, non-temporal"
      "stnp" "STNP Xt1, Xt2, [Xn{, #off}] -- store pair, non-temporal"
      "ldar" "LDAR Xt, [Xn] -- load-acquire"
      "stlr" "STLR Xt, [Xn] -- store-release"
      "ldapr" "LDAPR Xt, [Xn] -- load-acquire RCpc"
      "ldxr" "LDXR Xt, [Xn] -- load exclusive"
      "stxr" "STXR Ws, Xt, [Xn] -- store exclusive; Ws = 0 on success"
      "ldaxr" "LDAXR Xt, [Xn] -- load-acquire exclusive"
      "stlxr" "STLXR Ws, Xt, [Xn] -- store-release exclusive; Ws = 0 on success"
      "ldxp" "LDXP Xt1, Xt2, [Xn] -- load exclusive pair"
      "stxp" "STXP Ws, Xt1, Xt2, [Xn] -- store exclusive pair"
      "clrex" "CLREX -- clear exclusive monitor"
      "cas" "CAS Xs, Xt, [Xn] -- compare and swap (LSE; casa/casl/casal for ordering)"
      "casal" "CASAL Xs, Xt, [Xn] -- compare and swap, acquire+release"
      "swp" "SWP Xs, Xt, [Xn] -- swap (LSE)"
      "swpal" "SWPAL Xs, Xt, [Xn] -- swap, acquire+release"
      "ldadd" "LDADD Xs, Xt, [Xn] -- atomic add, Xt = old (LSE)"
      "ldaddal" "LDADDAL Xs, Xt, [Xn] -- atomic add, acquire+release"
      "stadd" "STADD Xs, [Xn] -- atomic add, no result (LSE)"
      "ldclr" "LDCLR Xs, Xt, [Xn] -- atomic bit clear (LSE)"
      "ldset" "LDSET Xs, Xt, [Xn] -- atomic bit set (LSE)"
      "ldeor" "LDEOR Xs, Xt, [Xn] -- atomic exclusive or (LSE)"
      "prfm" "PRFM <pldl1keep|pstl1keep|...>, [Xn{, #off}] -- prefetch memory"
      ;; System.
      "nop" "NOP -- no operation"
      "svc" "SVC #imm16 -- supervisor call (Linux: #0, nr in X8; macOS: #0x80, nr in X16)"
      "hvc" "HVC #imm16 -- hypervisor call"
      "smc" "SMC #imm16 -- secure monitor call"
      "brk" "BRK #imm16 -- breakpoint"
      "hlt" "HLT #imm16 -- halt (external debug)"
      "udf" "UDF #imm16 -- permanently undefined"
      "mrs" "MRS Xt, sysreg -- read system register"
      "msr" "MSR sysreg, Xt | pstatefield, #imm -- write system register"
      "dmb" "DMB <ish|ishld|ishst|sy|...> -- data memory barrier"
      "dsb" "DSB <ish|ishld|ishst|sy|...> -- data synchronization barrier"
      "isb" "ISB -- instruction synchronization barrier"
      "yield" "YIELD -- hint: spin-wait loop"
      "wfe" "WFE -- wait for event"
      "wfi" "WFI -- wait for interrupt"
      "sev" "SEV -- send event"
      "sevl" "SEVL -- send event local"
      "dc" "DC <civac|cvac|cvau|zva|...>, Xt -- data cache maintenance"
      "ic" "IC <ivau|iallu|ialluis>, {Xt} -- instruction cache maintenance"
      "tlbi" "TLBI op{, Xt} -- TLB invalidate"
      "at" "AT op, Xt -- address translate"
      "hint" "HINT #imm -- hint instruction"
      "bti" "BTI {c|j|jc} -- branch target identification landing pad"
      "pacia" "PACIA Xd, Xn -- sign pointer with key A, modifier Xn"
      "paciasp" "PACIASP -- sign LR with key A, modifier SP"
      "pacibsp" "PACIBSP -- sign LR with key B, modifier SP (arm64e)"
      "autia" "AUTIA Xd, Xn -- authenticate pointer with key A"
      "autiasp" "AUTIASP -- authenticate LR with key A, modifier SP"
      "autibsp" "AUTIBSP -- authenticate LR with key B, modifier SP (arm64e)"
      "xpaci" "XPACI Xd -- strip pointer authentication code"
      "xpaclri" "XPACLRI -- strip PAC from LR"
      ;; Floating point.
      "fmov" "FMOV <Dd|Sd|Hd>, <Dn|Xn|#imm> -- floating-point move"
      "fadd" "FADD Dd, Dn, Dm | Vd.T, Vn.T, Vm.T -- floating-point add"
      "fsub" "FSUB Dd, Dn, Dm -- floating-point subtract"
      "fmul" "FMUL Dd, Dn, Dm{[i]} -- floating-point multiply"
      "fdiv" "FDIV Dd, Dn, Dm -- floating-point divide"
      "fmadd" "FMADD Dd, Dn, Dm, Da -- Dd = Da + Dn*Dm (fused)"
      "fmsub" "FMSUB Dd, Dn, Dm, Da -- Dd = Da - Dn*Dm (fused)"
      "fnmadd" "FNMADD Dd, Dn, Dm, Da -- Dd = -Da - Dn*Dm (fused)"
      "fnmul" "FNMUL Dd, Dn, Dm -- Dd = -(Dn*Dm)"
      "fneg" "FNEG Dd, Dn -- floating-point negate"
      "fabs" "FABS Dd, Dn -- floating-point absolute value"
      "fsqrt" "FSQRT Dd, Dn -- floating-point square root"
      "fmax" "FMAX Dd, Dn, Dm -- floating-point maximum"
      "fmin" "FMIN Dd, Dn, Dm -- floating-point minimum"
      "fmaxnm" "FMAXNM Dd, Dn, Dm -- maximum number (NaN-ignoring)"
      "fminnm" "FMINNM Dd, Dn, Dm -- minimum number (NaN-ignoring)"
      "fcmp" "FCMP Dn, <Dm|#0.0> -- floating-point compare, set NZCV"
      "fcmpe" "FCMPE Dn, <Dm|#0.0> -- compare, signal on any NaN"
      "fccmp" "FCCMP Dn, Dm, #nzcv, cond -- floating-point conditional compare"
      "fcsel" "FCSEL Dd, Dn, Dm, cond -- floating-point conditional select"
      "fcvt" "FCVT Dd, Sn -- convert precision"
      "fcvtzs" "FCVTZS Xd, Dn{, #fbits} -- float to signed int, toward zero"
      "fcvtzu" "FCVTZU Xd, Dn{, #fbits} -- float to unsigned int, toward zero"
      "fcvtns" "FCVTNS Xd, Dn -- float to signed int, to nearest even"
      "fcvtms" "FCVTMS Xd, Dn -- float to signed int, toward -inf"
      "fcvtps" "FCVTPS Xd, Dn -- float to signed int, toward +inf"
      "fcvtas" "FCVTAS Xd, Dn -- float to signed int, to nearest away"
      "scvtf" "SCVTF Dd, Xn{, #fbits} -- signed int to float"
      "ucvtf" "UCVTF Dd, Xn{, #fbits} -- unsigned int to float"
      "frintn" "FRINTN Dd, Dn -- round to nearest even"
      "frintz" "FRINTZ Dd, Dn -- round toward zero"
      "frintm" "FRINTM Dd, Dn -- round toward -inf (floor)"
      "frintp" "FRINTP Dd, Dn -- round toward +inf (ceil)"
      "frinta" "FRINTA Dd, Dn -- round to nearest, ties away"
      "frintx" "FRINTX Dd, Dn -- round using FPCR mode, signal inexact"
      ;; SIMD (Advanced SIMD / NEON).
      "ld1" "LD1 {Vt.T, ...}, [Xn]{, #off|Xm} -- load multiple single-element structures"
      "ld2" "LD2 {Vt.T, Vt2.T}, [Xn] -- load 2-element structures, de-interleave"
      "ld3" "LD3 {Vt.T - Vt3.T}, [Xn] -- load 3-element structures, de-interleave"
      "ld4" "LD4 {Vt.T - Vt4.T}, [Xn] -- load 4-element structures, de-interleave"
      "ld1r" "LD1R {Vt.T}, [Xn] -- load one element, replicate to all lanes"
      "st1" "ST1 {Vt.T, ...}, [Xn]{, #off|Xm} -- store multiple single-element structures"
      "st2" "ST2 {Vt.T, Vt2.T}, [Xn] -- interleave and store 2-element structures"
      "st3" "ST3 {Vt.T - Vt3.T}, [Xn] -- interleave and store 3-element structures"
      "st4" "ST4 {Vt.T - Vt4.T}, [Xn] -- interleave and store 4-element structures"
      "dup" "DUP Vd.T, <Xn|Vn.Ts[i]> -- duplicate to all lanes"
      "ins" "INS Vd.Ts[i], <Xn|Vn.Ts[j]> -- insert element"
      "umov" "UMOV Wd, Vn.Ts[i] -- move element to GP register, zero-extend"
      "smov" "SMOV Xd, Vn.Ts[i] -- move element to GP register, sign-extend"
      "movi" "MOVI Vd.T, #imm{, lsl #s} -- move immediate to vector"
      "mvni" "MVNI Vd.T, #imm{, lsl #s} -- move inverted immediate"
      "addv" "ADDV Vd, Vn.T -- add across vector"
      "addp" "ADDP Vd.T, Vn.T, Vm.T -- add pairwise"
      "uaddlv" "UADDLV Vd, Vn.T -- unsigned add long across vector"
      "umaxv" "UMAXV Vd, Vn.T -- unsigned maximum across vector"
      "uminv" "UMINV Vd, Vn.T -- unsigned minimum across vector"
      "cmeq" "CMEQ Vd.T, Vn.T, <Vm.T|#0> -- compare equal, lanes -> all ones/zeros"
      "cmgt" "CMGT Vd.T, Vn.T, <Vm.T|#0> -- compare signed greater than"
      "cmhi" "CMHI Vd.T, Vn.T, Vm.T -- compare unsigned higher"
      "cmhs" "CMHS Vd.T, Vn.T, Vm.T -- compare unsigned higher or same"
      "bsl" "BSL Vd.16B, Vn.16B, Vm.16B -- bitwise select by Vd"
      "bit" "BIT Vd.16B, Vn.16B, Vm.16B -- bitwise insert if true"
      "bif" "BIF Vd.16B, Vn.16B, Vm.16B -- bitwise insert if false"
      "tbl" "TBL Vd.T, {Vn.16B, ...}, Vm.T -- table lookup (out of range -> 0)"
      "tbx" "TBX Vd.T, {Vn.16B, ...}, Vm.T -- table lookup (out of range -> unchanged)"
      "ext" "EXT Vd.T, Vn.T, Vm.T, #idx -- extract vector from pair"
      "zip1" "ZIP1 Vd.T, Vn.T, Vm.T -- interleave low halves"
      "zip2" "ZIP2 Vd.T, Vn.T, Vm.T -- interleave high halves"
      "uzp1" "UZP1 Vd.T, Vn.T, Vm.T -- de-interleave even elements"
      "uzp2" "UZP2 Vd.T, Vn.T, Vm.T -- de-interleave odd elements"
      "trn1" "TRN1 Vd.T, Vn.T, Vm.T -- transpose even elements"
      "trn2" "TRN2 Vd.T, Vn.T, Vm.T -- transpose odd elements"
      "xtn" "XTN Vd.Tb, Vn.Ta -- narrow (truncate)"
      "sqxtn" "SQXTN Vd.Tb, Vn.Ta -- signed saturating narrow"
      "uqxtn" "UQXTN Vd.Tb, Vn.Ta -- unsigned saturating narrow"
      "shrn" "SHRN Vd.Tb, Vn.Ta, #n -- shift right and narrow"
      "ushll" "USHLL Vd.Ta, Vn.Tb, #n -- unsigned shift left long"
      "sshll" "SSHLL Vd.Ta, Vn.Tb, #n -- signed shift left long"
      "uxtl" "UXTL Vd.Ta, Vn.Tb -- unsigned extend long"
      "sxtl" "SXTL Vd.Ta, Vn.Tb -- signed extend long"
      "ushr" "USHR Vd.T, Vn.T, #n -- unsigned shift right"
      "sshr" "SSHR Vd.T, Vn.T, #n -- signed shift right"
      "shl" "SHL Vd.T, Vn.T, #n -- shift left"
      "mla" "MLA Vd.T, Vn.T, Vm.T -- multiply-accumulate"
      "mls" "MLS Vd.T, Vn.T, Vm.T -- multiply-subtract"
      "fmla" "FMLA Vd.T, Vn.T, Vm.T{[i]} -- fused multiply-accumulate"
      "fmls" "FMLS Vd.T, Vn.T, Vm.T{[i]} -- fused multiply-subtract"
      "uabd" "UABD Vd.T, Vn.T, Vm.T -- unsigned absolute difference"
      "sabd" "SABD Vd.T, Vn.T, Vm.T -- signed absolute difference"
      "uqadd" "UQADD Vd.T, Vn.T, Vm.T -- unsigned saturating add"
      "sqadd" "SQADD Vd.T, Vn.T, Vm.T -- signed saturating add"
      "uqsub" "UQSUB Vd.T, Vn.T, Vm.T -- unsigned saturating subtract"
      "sqsub" "SQSUB Vd.T, Vn.T, Vm.T -- signed saturating subtract"
      "not" "NOT Vd.T, Vn.T -- bitwise not (vector)"
      "aese" "AESE Vd.16B, Vn.16B -- AES single round encryption"
      "aesmc" "AESMC Vd.16B, Vn.16B -- AES mix columns"
      "aesd" "AESD Vd.16B, Vn.16B -- AES single round decryption"
      "aesimc" "AESIMC Vd.16B, Vn.16B -- AES inverse mix columns"
      "pmull" "PMULL Vd.1Q, Vn.1D, Vm.1D -- polynomial multiply long"
      "crc32b" "CRC32B Wd, Wn, Wm -- CRC-32 of a byte"
      "crc32x" "CRC32X Wd, Wn, Xm -- CRC-32 of a doubleword"
      "crc32cb" "CRC32CB Wd, Wn, Wm -- CRC-32C of a byte"
      "crc32cx" "CRC32CX Wd, Wn, Xm -- CRC-32C of a doubleword"))
  "One-line summaries of common A64 instructions, keyed by mnemonic.")

(defconst arm64-asm--directive-docs
  #s(hash-table
     test equal
     data
     (".text" ".text -- switch to the code section"
      ".data" ".data -- switch to the initialized data section"
      ".bss" ".bss -- switch to the zero-initialized data section"
      ".section" ".section name{, \"flags\", @type} (ELF) | segname,sectname (Mach-O)"
      ".globl" ".globl sym -- make sym visible to the linker"
      ".global" ".global sym -- make sym visible to the linker"
      ".extern" ".extern sym -- declare an external symbol (ignored by GNU as)"
      ".private_extern" ".private_extern sym -- global but hidden outside the linkage unit (Mach-O)"
      ".hidden" ".hidden sym -- global but hidden outside the shared object (ELF)"
      ".weak" ".weak sym -- weak symbol"
      ".local" ".local sym -- local symbol (ELF)"
      ".type" ".type sym, %function | %object -- ELF symbol type"
      ".size" ".size sym, . - sym -- ELF symbol size"
      ".align" ".align n -- align to 2^n bytes (ARM targets)"
      ".p2align" ".p2align n{, fill{, max}} -- align to 2^n bytes"
      ".balign" ".balign n{, fill{, max}} -- align to n bytes"
      ".byte" ".byte expr, ... -- emit 8-bit values"
      ".hword" ".hword expr, ... -- emit 16-bit values"
      ".short" ".short expr, ... -- emit 16-bit values"
      ".word" ".word expr, ... -- emit 32-bit values"
      ".long" ".long expr, ... -- emit 32-bit values"
      ".int" ".int expr, ... -- emit 32-bit values"
      ".quad" ".quad expr, ... -- emit 64-bit values"
      ".xword" ".xword expr, ... -- emit 64-bit values"
      ".dword" ".dword expr, ... -- emit 64-bit values"
      ".float" ".float f, ... -- emit single-precision floats"
      ".double" ".double f, ... -- emit double-precision floats"
      ".ascii" ".ascii \"str\" -- emit string, no terminator"
      ".asciz" ".asciz \"str\" -- emit NUL-terminated string"
      ".string" ".string \"str\" -- emit NUL-terminated string"
      ".zero" ".zero n -- emit n zero bytes"
      ".space" ".space n{, fill} -- emit n bytes"
      ".skip" ".skip n{, fill} -- emit n bytes"
      ".fill" ".fill repeat{, size{, value}} -- emit repeated values"
      ".comm" ".comm sym, size{, align} -- common symbol"
      ".lcomm" ".lcomm sym, size{, align} -- local common symbol"
      ".zerofill" ".zerofill seg, sect, sym, size{, align} -- zero-filled storage (Mach-O)"
      ".equ" ".equ sym, expr -- define a constant"
      ".set" ".set sym, expr -- define a constant"
      ".equiv" ".equiv sym, expr -- define a constant, error if already defined"
      ".req" "name .req reg -- register alias"
      ".unreq" ".unreq name -- remove a register alias"
      ".macro" ".macro name arg1{=default}, arg2:req, ... -- begin macro; args as \\arg"
      ".endm" ".endm -- end macro"
      ".exitm" ".exitm -- exit macro early"
      ".rept" ".rept n -- repeat block n times, until .endr"
      ".irp" ".irp sym, v1, v2, ... -- repeat block for each value, until .endr"
      ".endr" ".endr -- end .rept/.irp block"
      ".if" ".if expr -- conditional assembly"
      ".ifdef" ".ifdef sym -- assemble if sym is defined"
      ".ifndef" ".ifndef sym -- assemble if sym is not defined"
      ".else" ".else"
      ".elseif" ".elseif expr"
      ".endif" ".endif"
      ".include" ".include \"file\" -- include an assembly file"
      ".arch" ".arch armv8.x-a{+ext} -- set the target architecture"
      ".arch_extension" ".arch_extension ext -- enable an architecture extension"
      ".cpu" ".cpu name{+ext} -- set the target CPU"
      ".inst" ".inst expr -- emit an instruction encoding"
      ".ltorg" ".ltorg -- emit the literal pool here"
      ".pool" ".pool -- emit the literal pool here"
      ".cfi_startproc" ".cfi_startproc -- begin a function's unwind info"
      ".cfi_endproc" ".cfi_endproc -- end a function's unwind info"
      ".cfi_def_cfa" ".cfi_def_cfa reg, off -- CFA = reg + off"
      ".cfi_def_cfa_offset" ".cfi_def_cfa_offset off -- CFA = current reg + off"
      ".cfi_def_cfa_register" ".cfi_def_cfa_register reg -- CFA now computed from reg"
      ".cfi_offset" ".cfi_offset reg, off -- reg saved at CFA + off"
      ".cfi_restore" ".cfi_restore reg -- reg restored to its initial value"
      ".cfi_remember_state" ".cfi_remember_state -- push the current unwind rules"
      ".cfi_restore_state" ".cfi_restore_state -- pop unwind rules"
      ".subsections_via_symbols" ".subsections_via_symbols -- allow dead-stripping per symbol (Mach-O)"
      ".build_version" ".build_version macos, major, minor -- minimum OS version (Mach-O)"
      ".loh" ".loh kind label1, label2 -- linker optimization hint (Mach-O)"
      ".file" ".file \"name\" -- source file name for debug info"
      ".loc" ".loc file line col -- source position for debug info"
      ".ident" ".ident \"str\" -- identification string"))
  "One-line summaries of common assembler directives.")

(defun arm64-asm--mnemonic-on-line ()
  "Return the mnemonic or directive on the current line, or nil."
  (save-excursion
    (beginning-of-line)
    (when (and (not (memq (arm64-asm--line-kind) '(comment in-comment)))
               (or (looking-at arm64-asm--directive-re)
                   (looking-at arm64-asm--mnemonic-re)))
      (downcase (match-string-no-properties 1)))))

(defun arm64-asm--doc-for (name)
  "Return the doc string for mnemonic or directive NAME."
  (cond ((string-prefix-p "." name)
         (gethash name arm64-asm--directive-docs))
        ((gethash name arm64-asm--instruction-docs))
        ((string-match (rx bos (group (or "b" "bc")) "." (group (+ alpha)) eos)
                       name)
         (concat (gethash (concat (match-string 1 name) ".cond")
                          arm64-asm--instruction-docs)
                 "  [" (match-string 2 name) ": "
                 (arm64-asm--condition-doc (match-string 2 name)) "]"))))

(defun arm64-asm--condition-doc (cc)
  "Describe condition code CC."
  (pcase cc
    ("eq" "equal, Z=1") ("ne" "not equal, Z=0")
    ((or "cs" "hs") "carry set / unsigned >=, C=1")
    ((or "cc" "lo") "carry clear / unsigned <, C=0")
    ("mi" "negative, N=1") ("pl" "positive or zero, N=0")
    ("vs" "overflow, V=1") ("vc" "no overflow, V=0")
    ("hi" "unsigned >, C=1 && Z=0") ("ls" "unsigned <=, C=0 || Z=1")
    ("ge" "signed >=, N=V") ("lt" "signed <, N!=V")
    ("gt" "signed >, Z=0 && N=V") ("le" "signed <=, Z=1 || N!=V")
    ("al" "always") ("nv" "always")
    (_ "unknown condition")))

(defun arm64-asm-eldoc-function (callback &rest _)
  "Eldoc backend: describe the instruction on the current line via CALLBACK."
  (when-let* ((name (arm64-asm--mnemonic-on-line))
              (doc (arm64-asm--doc-for name)))
    (funcall callback doc
             :thing name
             :face (if (string-prefix-p "." name)
                       'arm64-asm-directive-face
                     'arm64-asm-mnemonic-face))))


;;; Assembling

(defun arm64-asm--language ()
  "The -x language for the current buffer: .S files go through cpp."
  (if (and buffer-file-name
           (string-suffix-p ".S" buffer-file-name))
      "assembler-with-cpp"
    "assembler"))

(defun arm64-asm--compile-command ()
  "Default `compile-command' for the current buffer."
  (when buffer-file-name
    (let ((file (file-name-nondirectory buffer-file-name)))
      (string-join
       (append (list arm64-asm-assembler)
               arm64-asm-extra-flags
               (list "-c" (shell-quote-argument file)
                     "-o" (shell-quote-argument
                           (concat (file-name-sans-extension file) ".o"))))
       " "))))

(defun arm64-asm-assemble ()
  "Assemble the current file with `compile'."
  (interactive)
  (let ((compile-command (or (arm64-asm--compile-command) compile-command)))
    (call-interactively #'compile)))


;;; Flymake

(defvar-local arm64-asm--flymake-proc nil
  "The running Flymake assembler process, if any.")

(defun arm64-asm-flymake (report-fn &rest _)
  "Flymake backend: assemble the buffer and report diagnostics to REPORT-FN."
  (when (process-live-p arm64-asm--flymake-proc)
    (kill-process arm64-asm--flymake-proc))
  (let* ((source (current-buffer))
         (dir (if buffer-file-name
                  (file-name-directory buffer-file-name)
                default-directory))
         (command (append (split-string-shell-command arm64-asm-assembler)
                          arm64-asm-extra-flags
                          (list "-x" (arm64-asm--language)
                                "-I" (expand-file-name dir)
                                "-c" "-o" null-device "-"))))
    (save-restriction
      (widen)
      (setq arm64-asm--flymake-proc
            (make-process
             :name "arm64-asm-flymake"
             :noquery t
             :connection-type 'pipe
             :buffer (generate-new-buffer " *arm64-asm-flymake*")
             :command command
             :sentinel
             (lambda (proc _event)
               (when (memq (process-status proc) '(exit signal))
                 (unwind-protect
                     (if (with-current-buffer source
                           (eq proc arm64-asm--flymake-proc))
                         (funcall report-fn
                                  (arm64-asm--flymake-parse
                                   (process-buffer proc) source))
                       (flymake-log :warning "Canceling obsolete check %s"
                                    proc))
                   (kill-buffer (process-buffer proc)))))))
      (process-send-region arm64-asm--flymake-proc (point-min) (point-max))
      (process-send-eof arm64-asm--flymake-proc))))

(defun arm64-asm--flymake-parse (output source)
  "Parse assembler diagnostics in buffer OUTPUT for buffer SOURCE.
Understands clang (\"<stdin>:L:C: error: msg\") and GNU as
\(\"{standard input}:L: Error: msg\") formats."
  (let (diags)
    (with-current-buffer output
      (goto-char (point-min))
      (while (re-search-forward
              (rx line-start (or "<stdin>" "{standard input}" "-")
                  ":" (group (+ digit))
                  (? ":" (group (+ digit)))
                  ":" (* blank)
                  (group (or "error" "Error" "fatal error"
                             "warning" "Warning" "note"))
                  ":" (* blank) (group (* nonl)))
              nil t)
        (let* ((line (string-to-number (match-string 1)))
               (col (and (match-string 2) (string-to-number (match-string 2))))
               (kind (downcase (match-string 3)))
               (msg (match-string 4))
               (region (flymake-diag-region source line col)))
          (when region
            (push (flymake-make-diagnostic
                   source (car region) (cdr region)
                   (pcase kind
                     ((or "error" "fatal error") :error)
                     ("warning" :warning)
                     (_ :note))
                   msg)
                  diags)))))
    (nreverse diags)))


;;; Mode

(defvar-keymap arm64-asm-mode-map
  :doc "Keymap for `arm64-asm-mode'."
  "C-c C-c" #'arm64-asm-assemble)

;;;###autoload
(define-derived-mode arm64-asm-mode prog-mode "ARM64-Asm"
  "Major mode for editing AArch64 assembly (GNU as and Apple clang).

Labels and preprocessor lines indent to column 0; instructions and
directives to `arm64-asm-indent-offset'.  `;' is a comment on macOS
and a statement separator on Linux; see `arm64-asm-semicolon-comments'.

\\{arm64-asm-mode-map}"
  ;; Per-buffer syntax table so `;' can follow the dialect.
  (set-syntax-table (copy-syntax-table arm64-asm-mode-syntax-table))
  (when arm64-asm-semicolon-comments
    (modify-syntax-entry ?\; "< b"))

  (setq-local comment-start "// ")
  (setq-local comment-end "")
  (setq-local comment-start-skip
              (if arm64-asm-semicolon-comments
                  (rx (or (+ "/") (seq "/" (+ "*")) (+ ";")) (* blank))
                (rx (or (+ "/") (seq "/" (+ "*"))) (* blank))))
  (setq-local comment-column 40)

  (setq-local font-lock-defaults
              '(arm64-asm-font-lock-keywords nil t))

  (setq-local indent-line-function #'arm64-asm-indent-line)
  (setq-local tab-width arm64-asm-indent-offset)
  (setq-local electric-indent-chars
              (append '(?:) electric-indent-chars))

  (setq-local beginning-of-defun-function #'arm64-asm-beginning-of-defun)
  (setq-local end-of-defun-function #'arm64-asm-end-of-defun)
  (setq-local imenu-create-index-function #'arm64-asm--imenu-create-index)

  (add-hook 'eldoc-documentation-functions #'arm64-asm-eldoc-function nil t)
  (add-hook 'flymake-diagnostic-functions #'arm64-asm-flymake nil t)

  (when-let* ((cmd (arm64-asm--compile-command)))
    (setq-local compile-command cmd)))

(provide 'arm64-asm)
;;; arm64-asm.el ends here
