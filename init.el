;; -*- lexical-binding: t; indent-tabs-mode: nil -*-

;; Make lsp-mode use plists instead of hash-tables for server payloads -- a
;; real throughput win on large projects (less consing / GC on every message).
;; Must be set before lsp-mode is byte-compiled. After adding this, run once:
;;   M-x straight-rebuild-package RET lsp-mode RET   (also lsp-ui, lsp-java,
;;   lsp-treemacs, dap-mode) then restart Emacs.
(setenv "LSP_USE_PLISTS" "true")

(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name
        "straight/repos/straight.el/bootstrap.el"
        (or (bound-and-true-p straight-base-dir)
            user-emacs-directory)))
      (bootstrap-version 7))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(straight-use-package 'use-package)
(setq straight-use-package-by-default t)

;; Spaces, not tabs, everywhere (modes that require tabs, e.g. makefile-mode,
;; force it on themselves). Replaces the per-mode indent-tabs-mode hooks.
(setq-default indent-tabs-mode nil)

(use-package diminish)

;; Keep ~/.emacs.d tidy: relocate package state into var/ and etc/. Loaded
;; eagerly and early so it redirects paths (recentf, savehist/history, lsp
;; session, project list, ...) before those packages set them.
(use-package no-littering
  :config
  (setq auto-save-file-name-transforms
        `((".*" ,(no-littering-expand-var-file-name "auto-save/") t))))

(use-package exec-path-from-shell
  :if (or (memq window-system '(mac ns x))
          (daemonp))
  :config
  (exec-path-from-shell-initialize))

(use-package which-key
  :config (which-key-mode)
  :diminish)

;; Nerd Font icons used across treemacs, completion, dired, etc. In a terminal
;; these render only if your terminal's font is a Nerd Font. One-time (for GUI
;; frames / to fetch the font file): M-x nerd-icons-install-fonts.
(use-package nerd-icons)

;; Colour theme (Protesilaos' ef-themes -- accessible, great in a terminal).
;; Try others live with M-x ef-themes-select.
(use-package ef-themes
  :config
  (load-theme 'ef-dark :no-confirm))

(use-package monet
  :straight (:type git :host github :repo "stevemolitor/monet"))

(use-package claude-code
    :straight (:type git :host github :repo "stevemolitor/claude-code.el")
    :bind-keymap ("C-c c" . claude-code-command-map)
    :config
    (setq claude-code-terminal-backend 'eat)
    ;; (setq claude-code-terminal-backend 'vterm)
    (add-hook 'claude-code-process-environment-functions #'monet-start-server-function)
    (add-hook 'claude-code-process-environment-functions
              (lambda (_buf _dir) '("CLAUDE_CODE_DISABLE_ANIMATION=1")))
    (monet-mode 1))

(use-package flycheck)

;; yasnippet is required for jdtls method-argument completion to expand
;; placeholders (e.g. completing a method call fills in argument stubs you
;; can tab through), just like an IDE.
(use-package yasnippet
  :diminish yas-minor-mode
  :hook ((lsp-mode . yas-minor-mode)
         (prog-mode . yas-minor-mode))
  :config (yas-reload-all))

(use-package yasnippet-snippets
  :after yasnippet)

(use-package company
  :hook ((emacs-lisp-mode . company-mode)
         (lsp-mode . company-mode))
  :custom
  (company-minimum-prefix-length 1)
  (company-idle-delay 0.1)
  (company-tooltip-align-annotations t)
  (company-tooltip-limit 15)
  (company-show-quick-access t))

(use-package company-quickhelp
  :config (company-quickhelp-mode))

;; --- IntelliJ-style "Search Everywhere" / command palette -----------------
;; Vertico (minibuffer UI) + Orderless (fuzzy) + Marginalia (annotations) +
;; Consult (commands) + Embark (actions) + consult-lsp (workspace class/symbol
;; search via jdtls). `company' still handles in-buffer completion; this is
;; the minibuffer / navigation half (Go to Class, Find in Path, Recent, ...).

;; Persist minibuffer history so frequently-used commands/candidates sort first.
(use-package savehist
  :straight nil
  :init (savehist-mode 1))

(use-package vertico
  :init (vertico-mode 1)
  :custom
  (vertico-cycle t)
  (vertico-count 15))

;; Space-separated fuzzy matching, like IntelliJ's typo-tolerant search.
(use-package orderless
  :custom
  (completion-styles '(orderless basic))
  (completion-category-defaults nil)
  (completion-category-overrides '((file (styles basic partial-completion)))))

;; Rich annotations next to candidates (file sizes, docstrings, key bindings).
(use-package marginalia
  :init (marginalia-mode 1))

;; Type/kind icons next to minibuffer candidates (files, commands, symbols...).
(use-package nerd-icons-completion
  :after (marginalia nerd-icons)
  :config
  (nerd-icons-completion-mode)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

(use-package consult
  :bind (("C-x b"   . consult-buffer)      ;; buffers + recent files + bookmarks
         ("C-x C-r" . consult-recent-file) ;; Recent Files (IntelliJ Cmd-E)
         ("C-s"     . consult-line)        ;; find in current file (Cmd-F)
         ("M-y"     . consult-yank-pop)
         ("M-g g"   . consult-goto-line)
         ("M-g i"   . consult-imenu)       ;; current-file structure outline
         ("M-s r"   . consult-ripgrep)     ;; Find in Path (Cmd-Shift-F, needs rg)
         ("M-s f"   . consult-find))
  :custom
  (consult-narrow-key "<"))

;; Right-click-style action menu on whatever candidate/thing is at point;
;; `prefix-help-command' turns C-c/C-x prefixes into a searchable palette.
(use-package embark
  :bind (("C-."   . embark-act)
         ("C-h B" . embark-bindings))
  :custom
  (prefix-help-command #'embark-prefix-help-command))

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;; The Java payoff: workspace-wide class/symbol search backed by jdtls.
(use-package consult-lsp
  :after (consult lsp-mode)
  :bind (("M-o"   . consult-lsp-symbols)      ;; Go to Class/Symbol (Cmd-O)
         ("M-s d" . consult-lsp-diagnostics)) ;; all workspace diagnostics
  :config
  (with-eval-after-load 'lsp-mode
    (define-key lsp-mode-map [remap xref-find-apropos] #'consult-lsp-symbols)))

;; gc-cons-threshold and read-process-output-max are set in early-init.el.
(use-package lsp-mode
  :init
  (setq lsp-keymap-prefix "C-c l")
  :hook ((java-mode . lsp)
         (java-ts-mode . lsp)
         (lsp-mode . lsp-enable-which-key-integration)
         (lsp-mode . lsp-headerline-breadcrumb-mode)
         (lsp-mode . lsp-lens-mode))
  :commands lsp
  :custom
  ;; Performance: JDT on a large Maven/Gradle tree emits a lot of file-watch
  ;; requests; raise the threshold so lsp doesn't nag, and keep watchers on.
  (lsp-idle-delay 0.5)
  (lsp-file-watch-threshold 10000)
  (lsp-enable-file-watchers t)
  ;; IDE-grade UX niceties.
  (lsp-enable-snippet t)
  (lsp-lens-enable t)
  (lsp-signature-auto-activate t)
  (lsp-signature-render-documentation t)
  (lsp-completion-show-detail t)
  (lsp-completion-show-kind t)
  (lsp-semantic-tokens-enable t)
  ;; Inlay hints, capability-aware: lsp enables them only for servers that
  ;; advertise textDocument/inlayHint (forcing lsp-inlay-hints-mode via a hook
  ;; errors on servers that don't support it).
  (lsp-inlay-hint-enable t)
  (lsp-eldoc-render-all nil)
  (lsp-eldoc-enable-hover t)
  (lsp-modeline-code-actions-enable t)
  (lsp-modeline-diagnostics-enable t)
  (lsp-diagnostics-provider :flycheck)
  (lsp-headerline-breadcrumb-enable t)
  (lsp-enable-indentation t)
  (lsp-enable-on-type-formatting t)
  :config
  ;; C-c l d -> full documentation for the symbol at point (works in a TTY).
  (define-key lsp-command-map "d" #'lsp-describe-thing-at-point))

;; --- emacs-lsp-booster ----------------------------------------------------
;; Wrap LSP servers with the emacs-lsp-booster binary, which turns server JSON
;; into pre-parsed elisp bytecode -- a big throughput win. Requires the binary
;; on PATH AND plists (LSP_USE_PLISTS, set in early-init; run
;; `straight-rebuild-package lsp-mode' once to activate it). No-op otherwise.
(defun lsp-booster--advice-json-parse (old-fn &rest args)
  "Try to parse bytecode from emacs-lsp-booster instead of JSON."
  (or (when (equal (following-char) ?#)
        (let ((bytecode (read (current-buffer))))
          (when (byte-code-function-p bytecode)
            (funcall bytecode))))
      (apply old-fn args)))
(advice-add (if (progn (require 'json) (fboundp 'json-parse-buffer))
                'json-parse-buffer
              'json-read)
            :around #'lsp-booster--advice-json-parse)

(defun lsp-booster--advice-final-command (old-fn cmd &optional test?)
  "Prepend the emacs-lsp-booster command to the resolved LSP CMD."
  (let ((orig-result (funcall old-fn cmd test?)))
    (if (and (not test?)
             (not (file-remote-p default-directory))
             (bound-and-true-p lsp-use-plists)
             (not (functionp 'json-rpc-connection))
             (executable-find "emacs-lsp-booster"))
        (progn
          (when-let ((command-from-exec-path (executable-find (car orig-result))))
            (setcar orig-result command-from-exec-path))
          (message "Using emacs-lsp-booster for %s!" orig-result)
          (cons "emacs-lsp-booster" orig-result))
      orig-result)))
(advice-add 'lsp-resolve-final-command :around #'lsp-booster--advice-final-command)

(use-package lsp-ui
  :hook (lsp-mode . lsp-ui-mode)
  :custom
  ;; The doc popup is a child frame -> GUI only. In `emacs -nw' it silently
  ;; no-ops, so only enable it when running graphically. In the terminal,
  ;; docs come from eldoc (echo area) + `lsp-describe-thing-at-point' instead.
  (lsp-ui-doc-enable (display-graphic-p))
  (lsp-ui-doc-position 'at-point)
  (lsp-ui-doc-show-with-mouse t)
  (lsp-ui-doc-show-with-cursor t)
  (lsp-ui-doc-delay 0.2)
  (lsp-ui-sideline-enable t)
  (lsp-ui-sideline-show-diagnostics t)
  (lsp-ui-sideline-show-code-actions t)
  (lsp-ui-sideline-show-hover nil)
  (lsp-ui-peek-enable t)
  (lsp-ui-peek-show-directory t)
  :bind (:map lsp-ui-mode-map
              ([remap xref-find-definitions] . lsp-ui-peek-find-definitions)
              ([remap xref-find-references] . lsp-ui-peek-find-references)))

;; Terminal-friendly "hover": as point rests on a symbol, eldoc shows its
;; signature / short doc in the echo area at the bottom. Allow a few lines,
;; and prefer the dedicated doc buffer (`M-x eldoc-doc-buffer') for more.
(use-package eldoc
  :straight nil
  :diminish
  :custom
  (eldoc-idle-delay 0.3)
  (eldoc-echo-area-use-multiline-p 3)
  (eldoc-echo-area-prefer-doc-buffer t))

;; camelCase-aware motion: M-f/M-b/M-d stop at getUserName -> get|User|Name.
(use-package subword
  :straight nil
  :diminish
  :hook (prog-mode . subword-mode))

;; Auto-insert the closing ) } ] " etc.
(use-package elec-pair
  :straight nil
  :hook (prog-mode . electric-pair-local-mode))

;; Colour-code nested parens/brackets/braces by depth for readability.
(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

;; Grow the region semantically (word -> expr -> statement -> block); repeat
;; C-= to expand, C-- (or C-M-=) to contract. IntelliJ's Ctrl-W.
(use-package expand-region
  :bind (("C-=" . er/expand-region)
         ("C-M-=" . er/contract-region)))

;; Move the current line or region up/down (IDE Alt-Shift-Up/Down).
(use-package move-text
  :bind (("M-<up>"   . move-text-up)
         ("M-<down>" . move-text-down)))

;; Code folding: collapse methods/classes/imports. `lsp-origami' feeds it the
;; server's real fold ranges so folds line up with Java structure.
(use-package origami
  :hook (prog-mode . origami-mode)
  :bind (:map origami-mode-map
              ("C-c z z" . origami-toggle-node)
              ("C-c z a" . origami-toggle-all-nodes)
              ("C-c z o" . origami-open-node)
              ("C-c z c" . origami-close-node)))

(use-package lsp-origami
  :after (lsp-mode origami)
  :hook (lsp-after-open . lsp-origami-try-enable))

;; Richer, faster highlighting + structural navigation for Java. Installs the
;; grammar on first run (needs a C compiler; macOS clang is fine), then remaps
;; java-mode -> java-ts-mode, whose hook starts lsp just like java-mode.
(use-package treesit
  :straight nil
  :config
  (add-to-list 'treesit-language-source-alist
               '(java "https://github.com/tree-sitter/tree-sitter-java"))
  (unless (treesit-language-available-p 'java)
    (message "Installing tree-sitter grammar for Java...")
    (ignore-errors (treesit-install-language-grammar 'java)))
  (when (treesit-language-available-p 'java)
    (add-to-list 'major-mode-remap-alist '(java-mode . java-ts-mode))))

(defun my/open-java-project (dir)
  "Open DIR as a Java project in one shot.
Register DIR with the lsp session so jdtls treats it as a workspace,
add it to the Treemacs sidebar, and drop you in a dired buffer at the
root.  Opening any .java file from there starts the language server."
  (interactive "DOpen Java project (root dir): ")
  (let ((root (expand-file-name (file-name-as-directory dir))))
    (when (fboundp 'lsp-workspace-folders-add)
      (lsp-workspace-folders-add root))
    (require 'treemacs)
    (ignore-errors
      (treemacs-add-project-to-workspace
       root (file-name-nondirectory (directory-file-name root))))
    (dired root)
    (save-selected-window
      (treemacs-select-window))))

;; IDE-style project sidebar. `C-c t t' toggles it; `C-c t f' reveals the
;; current file in the tree; `C-c t p' opens a whole project (lsp + tree +
;; dired). Add/remove projects in the tree with `C-c C-p a'.
(use-package treemacs
  :bind (("C-c t t" . treemacs)
         ("C-c t f" . treemacs-find-file)
         ("C-c t s" . treemacs-select-window)
         ("C-c t p" . my/open-java-project)
         ("<f6>"    . treemacs))
  :custom
  (treemacs-width 35)
  (treemacs-follow-after-init t)
  :config
  (treemacs-follow-mode 1)
  (treemacs-filewatch-mode 1))

(use-package treemacs-magit
  :after (treemacs magit))

;; LSP-aware trees layered on treemacs: file outline, Java package/dependency
;; browser, and a workspace-wide diagnostics list.
(use-package lsp-treemacs
  :after (lsp-mode treemacs)
  :bind (("C-c t o" . lsp-treemacs-symbols)
         ("C-c t d" . lsp-treemacs-java-deps-list)
         ("C-c t e" . lsp-treemacs-errors-list))
  :commands (lsp-treemacs-errors-list
             lsp-treemacs-symbols
             lsp-treemacs-java-deps-list)
  :config (lsp-treemacs-sync-mode 1))

;; File-type icons in the Treemacs sidebar (IntelliJ-style project tree).
(use-package treemacs-nerd-icons
  :after (treemacs nerd-icons)
  :config (treemacs-load-theme "nerd-icons"))

(use-package lsp-java
  :after lsp-mode
  :custom
  (lsp-java-vmargs '("-XX:+UseParallelGC"
                     "-XX:GCTimeRatio=4"
                     "-XX:AdaptiveSizePolicyWeight=90"
                     "-Dsun.zip.disableMemoryMapping=true"
                     "-Xmx4G"
                     "-Xms512m"))
  ;; Code lenses like IntelliJ's usage/impl gutter markers.
  (lsp-java-references-code-lens-enabled t)
  (lsp-java-implementations-code-lens-enabled t)
  ;; Build & imports.
  (lsp-java-autobuild-enabled t)
  (lsp-java-import-maven-enabled t)
  (lsp-java-import-gradle-enabled t)
  (lsp-java-save-actions-organize-imports t)
  (lsp-java-import-gradle-wrapper-enabled t)
  ;; Completion behaves like an IDE: guesses args, sorts by usage,
  ;; and collapses long import lists into star imports past a threshold.
  (lsp-java-completion-guess-method-arguments t)
  (lsp-java-completion-enabled t)
  (lsp-java-completion-import-order ["java" "javax" "com" "org"])
  (lsp-java-members-sort-order ["Type" "Field" "Method" "Constructor"])
  (lsp-java-signature-help-enabled t)
  ;; Default Eclipse formatter profile, resolved relative to this config dir so
  ;; it works from wherever the repo is checked out. A project opts in by
  ;; setting `lsp-java-format-settings-profile' (e.g. "GoogleStyle") in its
  ;; .dir-locals.el; projects that don't keep jdtls' built-in formatting.
  (lsp-java-format-settings-url
   (expand-file-name "eclipse-java-google-style.xml" user-emacs-directory))
  ;; Decompile library sources you don't have jars for (F3 into JDK/deps).
  (lsp-java-content-provider-preferred "fernflower")
  ;; Code generation (getters/setters, hashCode/equals, toString).
  (lsp-java-code-generation-use-blocks t)
  (lsp-java-code-generation-generate-comments t)
  (lsp-java-code-generation-to-string-template
   "${object.className} [${member.name()}=${member.value}, ${otherMembers}]")
  (lsp-java-code-generation-hash-code-equals-use-java7objects t)
  (lsp-java-code-generation-to-string-code-style "STRING_BUILDER")
  :config
  ;; Point jdtls at the JDKs you have installed so it can build against the
  ;; right release. Adjust paths/versions to match your machine; the first
  ;; entry marked :default is used for projects that don't pin a version.
  (setq lsp-java-configuration-runtimes
        (seq-filter
         (lambda (rt) (file-directory-p (plist-get rt :path)))
         '((:name "JavaSE-21"
                  :path "/Users/mkennedy/Library/Java/JavaVirtualMachines/corretto-21.0.11/Contents/Home"
                  :default t)
           (:name "JavaSE-11"
                  :path "/Users/mkennedy/Library/Java/JavaVirtualMachines/corretto-11.0.31/Contents/Home")
           (:name "JavaSE-13"
                  :path "/Users/mkennedy/Library/Java/JavaVirtualMachines/azul-13.0.14/Contents/Home")
           (:name "JavaSE-19"
                  :path "/Users/mkennedy/Library/Java/JavaVirtualMachines/corretto-19.0.2/Contents/Home")
           (:name "JavaSE-23"
                  :path "/Users/mkennedy/Library/Java/JavaVirtualMachines/openjdk-23.0.2/Contents/Home")
           (:name "JavaSE-1.8"
                  :path "/Users/mkennedy/Library/Java/JavaVirtualMachines/corretto-1.8.0_462/Contents/Home"))))
  ;; Lombok: attach the annotation-processing agent to jdtls so generated
  ;; methods (getters, builders, @Slf4j log, etc.) resolve without errors.
  (let* ((lombok-dir (expand-file-name "~/.m2/repository/org/projectlombok/lombok/"))
         (jar (when (file-directory-p lombok-dir)
                (car (sort (directory-files-recursively
                            lombok-dir
                            "lombok\\(-[0-9]+\\.[0-9]+\\.[0-9]+\\)?\\.jar$")
                           :reverse t)))))
    (when jar
      (add-to-list 'lsp-java-vmargs (format "-javaagent:%s" jar) t))))

;; Spring Boot lenses (run/refactor mapping endpoints, property completion).
(use-package lsp-java-boot
  :straight nil
  :after lsp-java
  :hook ((java-mode . lsp-java-boot-lens-mode)
         (java-ts-mode . lsp-java-boot-lens-mode)))

;; Reformat Java buffers with jdtls on save (IDE-style "reformat on save").
;; Organize-imports on save is already handled by lsp-java-save-actions.
;; Set `my/java-format-on-save' to nil (or remove the hook) to disable.
(defvar my/java-format-on-save t
  "When non-nil, run `lsp-format-buffer' on Java buffers before saving.")

(defun my/java-format-before-save ()
  "Format the current Java buffer via lsp when saving."
  (when (and my/java-format-on-save
             (bound-and-true-p lsp-mode)
             (derived-mode-p 'java-mode 'java-ts-mode))
    (ignore-errors (lsp-format-buffer))))

(add-hook 'before-save-hook #'my/java-format-before-save)

;; --- Per-project configuration via .dir-locals.el -------------------------
;; Mark the Java/LSP settings you'd most often pin per repo as *safe* local
;; variables, so a project's .dir-locals.el can set them without the
;; "unsafe local variable" prompt on every visit. Each entry is (VAR . PRED):
;; the value is only accepted silently if PRED returns non-nil for it.
(dolist (spec
         (list
          ;; list of "-Xmx6G"-style strings
          (cons 'lsp-java-vmargs
                (lambda (v) (and (listp v) (seq-every-p #'stringp v))))
          (cons 'lsp-java-import-gradle-jvm-arguments
                (lambda (v) (and (listp v) (seq-every-p #'stringp v))))
          ;; runtimes: a list OR vector of plists
          (cons 'lsp-java-configuration-runtimes
                (lambda (v) (or (listp v) (vectorp v))))
          ;; Eclipse formatter profile (finishes the format-on-save story)
          (cons 'lsp-java-format-settings-url #'stringp)
          (cons 'lsp-java-format-settings-profile #'stringp)
          (cons 'lsp-java-import-gradle-java-home #'stringp)
          (cons 'lsp-java-java-path #'stringp)
          (cons 'lsp-java-format-enabled #'booleanp)
          (cons 'lsp-java-save-actions-organize-imports #'booleanp)
          (cons 'lsp-file-watch-threshold #'integerp)
          (cons 'my/java-format-on-save #'booleanp)))
  (put (car spec) 'safe-local-variable (cdr spec)))

;; Server-launch settings (lsp-java-vmargs, lsp-java-configuration-runtimes)
;; are read when jdtls starts; after changing them in .dir-locals.el, run
;; M-x lsp-workspace-restart for the new values to take effect. Most other
;; lsp-java settings are pushed to the running server on change.
;;
;; Example .dir-locals.el at a project root:
;;
;;   ((java-mode
;;     . ((lsp-java-configuration-runtimes
;;         . [(:name "JavaSE-21"
;;             :path "/Users/mkennedy/Library/Java/JavaVirtualMachines/corretto-21.0.11/Contents/Home"
;;             :default t)])
;;        (lsp-java-vmargs . ("-XX:+UseParallelGC" "-Xmx6G"))
;;        ;; formatter XML is set globally; just pick a profile from it:
;;        (lsp-java-format-settings-profile . "GoogleStyle")
;;        (my/java-format-on-save . t)))
;;    (java-ts-mode
;;     . ((lsp-java-format-settings-profile . "GoogleStyle"))))

(use-package dap-mode
  :after lsp-mode
  :bind
  (:map dap-mode-map
        ("<f5>"    . dap-debug)
        ("<f9>"    . dap-continue)
        ("<f7>"    . dap-step-in)
        ("S-<f8>"  . dap-step-out)
        ("<f8>"    . dap-next)
        ("<f10>"   . dap-next)
        ("C-<f9>"  . dap-breakpoint-toggle)
        ("C-c d b" . dap-breakpoint-toggle)
        ("C-c d r" . dap-debug-recent)
        ("C-c d l" . dap-debug-last)
        ("C-c d d" . dap-debug)
        ("C-c d h" . dap-hydra)
        ("C-c d e" . dap-debug-edit-template)
        ;; Run / debug the test under point or the whole class (IntelliJ's
        ;; green run/debug gutter arrows).
        ("C-c d t m" . dap-java-run-test-method)
        ("C-c d t c" . dap-java-run-test-class)
        ("C-c d t M" . dap-java-debug-test-method)
        ("C-c d t C" . dap-java-debug-test-class))
  :custom
  (dap-auto-configure-features '(sessions locals breakpoints expressions tooltip))
  :config
  (dap-auto-configure-mode 1)
  (require 'dap-java))

;; dap-java gives you IntelliJ-style local run/debug plus remote attach.
;; Use `dap-java-debug' / `dap-java-run-test-method' for local work, and the
;; registered template below (M-x dap-debug -> "Java Attach (remote 5005)")
;; to attach to a JVM started with:
;;   -agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005
;; Hot-code-replace is on by default, so edits recompile into the live JVM.
(use-package dap-java
  :straight nil
  :after (dap-mode lsp-java)
  :config
  (dap-register-debug-template
   "Java Attach (remote 5005)"
   (list :type "java"
         :request "attach"
         :hostName "localhost"
         :port 5005
         :name "Java Attach (remote 5005)"))
  (dap-register-debug-template
   "Java Attach (remote, prompt)"
   (list :type "java"
         :request "attach"
         :hostName "localhost"
         :port nil
         :name "Java Attach (remote, prompt)")))

(use-package magit)

(use-package diff-hl
  :after magit
  :hook (magit-post-refresh . diff-hl-magit-post-refresh)
  :config (global-diff-hl-mode))

;; Refresh buffers when files change on disk (git pull, build output, etc.).
(use-package autorevert
  :straight nil
  :diminish auto-revert-mode
  :custom (global-auto-revert-non-file-buffers t)
  :config (global-auto-revert-mode 1))

;; Undo/redo window layouts with C-c <left> / C-c <right> -- handy after the
;; debugger rearranges your windows.
(use-package winner
  :straight nil
  :config (winner-mode 1))

;; Jump/swap windows by letter (M-O uppercase avoids clashing with M-o).
(use-package ace-window
  :bind (("C-x o" . ace-window)
         ("M-O"   . ace-window))
  :custom (aw-scope 'frame))

;; Jump to any visible location by typing a couple of chars (IntelliJ AceJump).
(use-package avy
  :bind (("C-;"   . avy-goto-char-timer)  ; type chars, then a hint letter
         ("M-g c" . avy-goto-char)
         ("M-g w" . avy-goto-word-1)
         ("M-g a" . avy-goto-line)))

;; Richer *Help* buffers, wired onto the standard describe-* keys.
(use-package helpful
  :bind (([remap describe-function] . helpful-callable)
         ([remap describe-variable] . helpful-variable)
         ([remap describe-key]      . helpful-key)
         ([remap describe-command]  . helpful-command)
         ("C-h C-." . helpful-at-point)))

;; Fuzzy list of all diagnostics in the buffer/project (companion to
;; lsp-treemacs-errors-list and M-s d).
(use-package consult-flycheck
  :after (consult flycheck)
  :bind ("M-g f" . consult-flycheck))

(use-package editorconfig
  :straight nil
  :config (editorconfig-mode 1))

(use-package desktop
  :straight nil
  :custom
  (desktop-auto-save-timeout 30)
  (desktop-load-locked-desktop 'check-pid)
  (desktop-save t)
  :config (desktop-save-mode 1))

(use-package xt-mouse
  :straight nil
  :config (xterm-mouse-mode 1))

;; Send kills/copies to the system clipboard from a TTY via OSC-52, so yank in
;; Emacs -nw syncs with macOS (and works over SSH). Needs a terminal that
;; allows clipboard access (e.g. iTerm2's "allow clipboard access" setting).
(use-package clipetty
  :diminish
  :hook (after-init . global-clipetty-mode))

(straight-use-package
 '(eat :type git
       :host codeberg
       :repo "akib/emacs-eat"
       :files ("*.el" ("term" "term/*.el") "*.texi"
               "*.ti" ("terminfo/e" "terminfo/e/*")
               ("terminfo/65" "terminfo/65/*")
               ("integration" "integration/*")
               (:exclude ".dir-locals.el" "*-tests.el"))))

(use-package vterm)

(use-package julia-snail
  :hook (julia-mode . julia-snail-mode))

;; --- Zig ------------------------------------------------------------------
;; zig + zls are installed; lsp-mode ships the zls client (lsp-zig), so Zig
;; plugs into the same lsp/company/treemacs/eldoc stack as Java. `zig fmt'
;; formats on save; ZLS gives completion, diagnostics, inlay hints, and
;; build-on-save. (Debugging would need a codelldb/lldb-dap adapter installed.)
(use-package zig-mode
  :mode ("\\.zig\\'" "\\.zon\\'")
  :hook (zig-mode . lsp)
  :custom
  (zig-format-on-save t)                 ; canonical `zig fmt' on save
  :bind (:map zig-mode-map
              ("C-c C-b" . zig-compile)      ; zig build
              ("C-c C-r" . zig-run)          ; zig run
              ("C-c C-t" . zig-test-buffer)  ; zig test <file>
              ("C-c C-d" . my/zig-debug)))   ; debug a built exe with codelldb

;; ZLS settings -- the client ships inside lsp-mode as lsp-zig.el.
(use-package lsp-zig
  :straight nil
  :after lsp-mode
  :custom
  (lsp-zig-zls-executable "zls")             ; use the zls on PATH
  (lsp-zig-enable-inlay-hints t)
  (lsp-zig-inlay-hints-show-parameter-name t)
  (lsp-zig-inlay-hints-show-variable-type-hints t)
  (lsp-zig-enable-build-on-save t)           ; diagnostics from `zig build'
  (lsp-zig-enable-argument-placeholders t)
  (lsp-zls-enable-snippets t))

;; Zig debugging via codelldb (installed under ~/.emacs.d/.extension). codelldb
;; registers itself as dap's "lldb" provider; the template below is a starting
;; point (edit :program via `dap-debug-edit-template'), and `my/zig-debug'
;; prompts for a built executable and launches it under the debugger.
(use-package dap-codelldb
  :straight nil
  :after dap-mode
  :config
  (dap-register-debug-template
   "Zig :: codelldb launch"
   (list :type "lldb"
         :request "launch"
         :name "Zig :: codelldb launch"
         :program "${workspaceFolder}/zig-out/bin/"
         :cwd "${workspaceFolder}")))

(defun my/zig-debug (program)
  "Debug a compiled Zig PROGRAM with codelldb.
Build first (`zig build' in Debug mode emits debug info); completion
defaults to the project's zig-out/bin directory."
  (interactive
   (list (read-file-name
          "Zig executable to debug: "
          (expand-file-name
           "zig-out/bin/"
           (or (ignore-errors (and (fboundp 'lsp-workspace-root) (lsp-workspace-root)))
               (ignore-errors (project-root (project-current)))
               default-directory)))))
  (require 'dap-codelldb)
  (dap-debug (list :type "lldb"
                   :request "launch"
                   :name "Zig :: Debug"
                   :program (expand-file-name program)
                   :cwd (file-name-directory (expand-file-name program))
                   :args [])))

(use-package sly
  :custom
  (sly-lisp-implementations
   `((sbcl ("sbcl" "--dynamic-space-size" "4Gb") :coding-system utf-8-unix)
     (clisp ("clisp" "-q") :coding-system utf-8-unix)
     (ciel ("sbcl" "--core" ,(expand-file-name "~/Quicklisp/local-projects/CIEL/ciel-core") "--eval" "(in-package :ciel-user)"))))
  (sly-default-lisp 'sbcl)
  (sly-db-focus-debugger 'always)
  ;; Fuzzy symbol completion + REPL input history that survives restarts.
  (sly-complete-symbol-function 'sly-flex-completions)
  (sly-mrepl-history-file-name (no-littering-expand-var-file-name "sly-mrepl-history"))
  ;; Enable extra contribs (installed below) on top of the default sly-fancy.
  (sly-contribs '(sly-fancy
                  sly-quicklisp        ; sly-quickload systems from the REPL
                  sly-asdf             ; load/reload/test ASDF systems
                  sly-macrostep        ; step through macroexpansions
                  sly-repl-ansi-color)); ANSI colours in the REPL (CIEL)
  ;; company completion in Lisp buffers and the REPL (sly provides capf).
  :hook ((lisp-mode . company-mode)
         (sly-mrepl-mode . company-mode)))

;; The contrib packages named in `sly-contribs' above -- installed here so
;; they're on `load-path' when sly requires them at connect time. `:after sly'
;; keeps them from dragging sly in at startup.
(use-package sly-quicklisp :after sly)
(use-package sly-asdf :after sly)
(use-package sly-macrostep :after sly)
(use-package sly-repl-ansi-color :after sly)

;; Structural Lisp editing (slurp/barf/splice) that coexists with
;; electric-pair, unlike paredit. Covers CL buffers, elisp, and the REPL.
;; Bindings live under a `C-c s' (sexp) prefix because the classic paredit
;; keys (C-), C-(, M-[) don't transmit in most terminals.
(use-package puni
  :hook ((lisp-mode emacs-lisp-mode lisp-interaction-mode sly-mrepl-mode)
         . puni-mode)
  :bind (:map puni-mode-map
              ;; slurp / barf -- the paren char shows the direction
              ("C-c s )" . puni-slurp-forward)
              ("C-c s }" . puni-barf-forward)
              ("C-c s (" . puni-slurp-backward)
              ("C-c s {" . puni-barf-backward)
              ;; wrap the next sexp
              ("C-c s w" . puni-wrap-round)
              ("C-c s [" . puni-wrap-square)
              ("C-c s c" . puni-wrap-curly)
              ("M-("     . puni-wrap-round)
              ;; restructure
              ("C-c s u" . puni-splice)      ; unwrap: drop surrounding delims
              ("C-c s r" . puni-raise)       ; replace parent with this sexp
              ("C-c s t" . puni-transpose)
              ("C-c s v" . puni-convolute)))

(auto-save-visited-mode 1)

(defun my/dired-mode-swiftsensors-hook ()
  (when-let*  ((default-directory default-directory)
               (tramp (file-remote-p default-directory 'method))
               (host (file-remote-p default-directory 'host)))
    (cond ((string-prefix-p "swiftsensors-dev" host)
           (face-remap-add-relative
            'default :background "#1C261C"))
          ((string-prefix-p "swiftsensors-prod" host)
            (face-remap-add-relative
            'default :background "#472B2B")))))

(use-package dired
  :straight nil
  :hook ((dired-mode . hl-line-mode)
         (dired-mode . my/dired-mode-swiftsensors-hook)))

;; File-type icons in dired listings.
(use-package nerd-icons-dired
  :after nerd-icons
  :diminish
  :hook (dired-mode . nerd-icons-dired-mode))

(use-package visual-fill-column
  :custom
  (visual-fill-column-width 80)
  (fill-column 80)
  :hook (markdown-mode . (lambda ()
                           (visual-line-mode 1)
                           (visual-fill-column-mode 1))))


(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(claude-code-program "claude-personal")
 '(diff-hl-draw-borders nil)
 '(fringe-mode '(nil . 0) nil (fringe))
 '(ignored-local-variable-values
   '((Syntax . COMMON-LISP)
     (Package SERIES :use "COMMON-LISP" :colon-mode :external)
     (syntax . ANSI-COMMON-LISP) (Package . USOCKET) (Syntax . ANSI-Common-lisp)
     (Base . 10)))
 '(tool-bar-mode nil)
 '(use-short-answers t))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
(put 'dired-find-alternate-file 'disabled nil)




















