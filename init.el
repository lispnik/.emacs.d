;; -*- lexical-binding: t; indent-tabs-mode: nil -*-

;; NOTE: lsp-mode plists mode (LSP_USE_PLISTS) is intentionally OFF. Enabling it
;; broke textDocument/documentSymbol with jdtls (empty/erroring imenu and
;; lsp-treemacs structure). Hash-table mode is the known-good default. If you
;; revisit plists, set the env here AND rebuild every lsp-* package with it set.

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

(defun my/claude-code-disable-animation (_buf _dir)
  "Env addition that turns off claude-code's spinner animation.
A named function (not an anonymous lambda) so it can be removed from
`claude-code-process-environment-functions' later if needed."
  (list "CLAUDE_CODE_DISABLE_ANIMATION=1"))

(defun my/claude-code-buffers-menu (&optional _items)
  "Return live Claude buffers as menu items, for an easymenu `:filter'.

Labels come from `claude-code--buffer-display-name' (`project:instance
\(directory)'), which reads better here than the raw `*claude:...*'
buffer name.  They are still passed through `menu-bar-update-buffers-1',
the helper that builds the global Buffers menu, so the trailing status
flags match it: `*' modified, `%' read-only, per `buffers-menu-show-status'.

The Buffers menu's middle-truncation is deliberately not applied: it is
tuned for bare buffer names and would gut the `name (directory)' form.
Directories are already abbreviated to `~/...' by `claude-code--buffer-name'."
  (if-let* ((buffers (claude-code--find-all-claude-buffers)))
      (mapcar
       (lambda (buf)
         (vector (car (menu-bar-update-buffers-1
                       (cons buf (claude-code--buffer-display-name buf))))
                 (lambda ()
                   (interactive)
                   (claude-code--switch-to-selected-buffer buf))
                 :help (buffer-name buf)))
       buffers)
    (list (vector "No Claude Buffers" #'ignore :enable nil))))

(use-package claude-code
    :straight (:type git :host github :repo "stevemolitor/claude-code.el")
    :demand t
    :custom
    (claude-code-program "claude-personal")
    (claude-code-terminal-backend 'ghostel)
    ;; (claude-code-terminal-backend 'eat)
    ;; (claude-code-terminal-backend 'vterm)
    :config
    ;; Bound here rather than via `:bind-keymap', which exists to defer loading.
    (keymap-global-set "C-c c" claude-code-command-map)

    ;; claude-code.el has a transient (C-c c m) but no menu-bar entry.  Mirror
    ;; the transient's groups into a "Claude" menu.  Passing nil as the keymap
    ;; only defines the menu; `define-key-after' below is what installs it, and
    ;; is what lets us place it *among* the standard menus (right after Tools,
    ;; before Help) instead of appended past Help.
    (easy-menu-define my/claude-code-menu nil
      "Menu for Claude Code."
      '("Claude"
        ["Start Claude" claude-code
         :help "Start Claude in the current project"]
        ["Start Claude (sandbox)" claude-code-sandbox
         :help "Start Claude in a sandboxed environment"]
        ["Start in Directory..." claude-code-start-in-directory
         :help "Prompt for a directory and start Claude there"]
        ["Continue Conversation" claude-code-continue
         :help "Continue the most recent conversation"]
        ["Resume Session..." claude-code-resume
         :help "Pick a past session to resume"]
        ["New Instance" claude-code-new-instance
         :help "Start an additional Claude instance"]
        "---"
        ["Send Command..." claude-code-send-command
         :help "Prompt for a command and send it to Claude"]
        ["Send Command with Context..." claude-code-send-command-with-context
         :help "Send a command along with the current file and line"]
        ["Send Region or Buffer" claude-code-send-region
         :help "Send the active region, or the whole buffer"]
        ["Send Buffer File" claude-code-send-buffer-file
         :help "Send the file backing the current buffer"]
        ["Paste Image from Clipboard" claude-code-yank-media
         :help "Yank an image from the clipboard into Claude"]
        ["Fix Error at Point" claude-code-fix-error-at-point
         :help "Ask Claude to fix the flycheck/flymake error at point"]
        ["Fork Conversation" claude-code-fork
         :help "Branch the conversation from an earlier point"]
        ["Slash Commands..." claude-code-slash-commands
         :help "Browse Claude's slash commands"]
        "---"
        ["Toggle Claude Window" claude-code-toggle
         :help "Show or hide the Claude window"]
        ["Switch to Claude Buffer" claude-code-switch-to-buffer
         :help "Select the Claude buffer for this project"]
        ["Select from All Claude Buffers" claude-code-select-buffer
         :help "Pick among every running Claude buffer"]
        ("Claude Buffers" :filter my/claude-code-buffers-menu)
        ["Toggle Read-Only Mode" claude-code-toggle-read-only-mode
         :help "Toggle read-only mode in the Claude buffer"]
        ["Cycle Claude Mode" claude-code-cycle-mode
         :help "Cycle Claude's permission mode"]
        "---"
        ("Quick Responses"
         ["Send <return>" claude-code-send-return]
         ["Send <escape>" claude-code-send-escape]
         ["Send \"1\"" claude-code-send-1]
         ["Send \"2\"" claude-code-send-2]
         ["Send \"3\"" claude-code-send-3])
        "---"
        ["Transient Menu" claude-code-transient
         :help "Open the full transient command menu"]
        ["Kill Claude" claude-code-kill
         :help "Kill the Claude instance for this project"]
        ["Kill All Instances" claude-code-kill-all
         :help "Kill every running Claude instance"]))

    ;; Install into the global menu bar between Tools and Help.  `help-menu' is
    ;; in `menu-bar-final-items', so it stays pinned last regardless.
    (define-key-after global-map [menu-bar claude]
      (easy-menu-binding my/claude-code-menu "Claude")
      'tools)

    (add-hook 'claude-code-process-environment-functions #'monet-start-server-function)
    (add-hook 'claude-code-process-environment-functions #'my/claude-code-disable-animation)
    (monet-mode 1))

;; (use-package agent-shell
;;     :ensure t
;;     :ensure-system-package
;;     ((claude . "brew install claude-code")
;;      (claude-agent-acp . "npm install -g @agentclientprotocol/claude-agent-acp")))

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
  (lsp-idle-delay 0.5)
  ;; Do NOT let lsp-mode's own file watchers run on large Java trees -- each
  ;; watched dir costs a file descriptor and macOS's default `ulimit -n' is
  ;; low, so big projects hit "running out of file descriptors" (which also
  ;; breaks the jdtls connection). jdtls watches the workspace itself, so
  ;; disabling lsp's watchers is safe. Raise `ulimit -n' if you want them back.
  (lsp-enable-file-watchers nil)
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

;; emacs-lsp-booster was disabled: it broke textDocument/documentSymbol
;; (empty imenu / lsp-treemacs structure) with jdtls. plists is also off now
;; (see top of file). See git history for the booster wiring if revisiting.

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
    (add-to-list 'major-mode-remap-alist '(java-mode . java-ts-mode)))

  (add-to-list 'treesit-language-source-alist
               '(python "https://github.com/tree-sitter/tree-sitter-python"))
  (unless (treesit-language-available-p 'python)
    (message "Installing tree-sitter grammar for Python...")
    (ignore-errors (treesit-install-language-grammar 'python)))
  (when (treesit-language-available-p 'python)
    (add-to-list 'major-mode-remap-alist '(python-mode . python-ts-mode))))

;; --- Python: basedpyright (types/nav) + ruff (lint/format) via lsp-mode -----
;; basedpyright is a maintained Pyright fork; it does type-checking, completion,
;; hover, go-to-def and inlay hints but no style-lint or formatting -- ruff
;; (below) fills that in as an lsp add-on server. The hook `require's lsp-pyright
;; so its client is registered before `lsp-deferred' connects; that's why Python
;; is started here rather than via lsp-mode's own :hook (as Java is).
;; Install the server once outside Emacs:  uv tool install basedpyright
(use-package lsp-pyright
  :custom
  (lsp-pyright-langserver-command "basedpyright")
  :hook ((python-mode python-ts-mode)
         . (lambda () (require 'lsp-pyright) (lsp-deferred))))

;; ruff's lsp client ships inside lsp-mode; it registers `:add-on? t' so it runs
;; alongside basedpyright rather than replacing it. Diagnostics flow through
;; flycheck automatically, and `lsp-format-buffer' routes to ruff (the only
;; Python server here that advertises formatting).
;; Install once outside Emacs:  brew install ruff   (needs >= 0.5.3 for `server')
(use-package lsp-ruff
  :straight nil                         ; part of lsp-mode
  :after lsp-mode
  :custom
  (lsp-ruff-server-command '("ruff" "server")))

;; Auto-detect the project's Python interpreter (.venv / poetry / pipenv / conda)
;; and point basedpyright, ruff and flycheck at it buffer-locally, so they
;; resolve the project's dependencies instead of system Python. Runs early
;; (depth -10) so the executables are set before lsp starts.
(use-package pet
  :config
  (add-hook 'python-base-mode-hook #'pet-mode -10))

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

;; Reliable "Structure" dock -- a persistent side panel of the current file's
;; symbols, backed by imenu (which uses lsp's documentSymbol). It auto-refreshes
;; and follows point, unlike the flaky lsp-treemacs-symbols tree (C-c t o).
;; `C-c t i' toggles it.
(use-package imenu-list
  :bind ("C-c t i" . imenu-list-smart-toggle)
  :custom
  (imenu-list-focus-after-activation t)
  (imenu-list-auto-resize t)
  (imenu-list-position 'right))

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
         (jars (when (file-directory-p lombok-dir)
                 (directory-files-recursively
                  lombok-dir
                  "lombok\\(-[0-9]+\\.[0-9]+\\.[0-9]+\\)?\\.jar$")))
         ;; Pick the highest version by numeric comparison, not string order:
         ;; a lexicographic sort ranks 1.18.9 above 1.18.30.
         (jar (car (sort jars
                         :key (lambda (f)
                                (if (string-match "lombok-\\([0-9.]+\\)\\.jar\\'" f)
                                    (match-string 1 f)
                                  "0"))
                         :lessp (lambda (a b) (version< b a))))))
    (when jar
      (add-to-list 'lsp-java-vmargs (format "-javaagent:%s" jar) t))))

;; Spring Boot LS (boot-ls) disabled -- not doing Spring right now. lsp-mode
;; auto-loads lsp-java-boot (it's in lsp-client-packages), so rather than
;; removing it we turn its client off; boot-ls then never attaches a second
;; server to Java buffers. For Spring work, set this back to t and re-add the
;; `lsp-java-boot-lens-mode' hooks.
(use-package lsp-java-boot
  :straight nil
  :after lsp-java
  :custom (lsp-java-boot-enabled nil))

;; Reformat Java buffers with jdtls on save (IDE-style "reformat on save").
;; Organize-imports on save is already handled by lsp-java-save-actions.
;; Set `my/java-format-on-save' to nil (or remove the hook) to disable.
(defvar my/java-format-on-save t
  "When non-nil, run `lsp-format-buffer' on Java buffers on an explicit save.")

;; Format only on an *explicit* save command. `auto-save-visited-mode' saves
;; file buffers from an idle timer, which runs outside the command loop, so
;; `this-command' is not a save command then -- this keeps the timer's auto-save
;; writing the file without reformatting mid-edit every few seconds, while
;; C-x C-s / C-x s / C-x C-w still reformat.
(defun my/explicit-save-p ()
  "Non-nil when the current save came from an interactive save command."
  (memq this-command '(save-buffer save-some-buffers write-file)))

(defun my/java-format-before-save ()
  "Format the current Java buffer via lsp on an explicit save."
  (when (and my/java-format-on-save
             (my/explicit-save-p)
             (bound-and-true-p lsp-mode)
             (derived-mode-p 'java-mode 'java-ts-mode))
    (ignore-errors (lsp-format-buffer))))

(add-hook 'before-save-hook #'my/java-format-before-save)

;; Reformat Python buffers with ruff on an explicit save, using the same
;; `my/explicit-save-p' gate as Java so `auto-save-visited-mode's idle-timer
;; saves write the file without reformatting mid-edit. `lsp-format-buffer'
;; routes to ruff (basedpyright doesn't format). Set `my/python-format-on-save'
;; to nil per project via .dir-locals.el to disable.
(defvar my/python-format-on-save t
  "When non-nil, run `lsp-format-buffer' (ruff) on Python buffers on an explicit save.")

(defun my/python-format-before-save ()
  "Format the current Python buffer via lsp/ruff on an explicit save."
  (when (and my/python-format-on-save
             (my/explicit-save-p)
             (bound-and-true-p lsp-mode)
             (derived-mode-p 'python-mode 'python-ts-mode))
    (ignore-errors (lsp-format-buffer))))

(add-hook 'before-save-hook #'my/python-format-before-save)

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
          (cons 'my/java-format-on-save #'booleanp)
          (cons 'my/python-format-on-save #'booleanp)
          ;; Per-project Python interpreter override (e.g. a venv), when `pet'
          ;; can't autodetect it.
          (cons 'lsp-pyright-python-executable-cmd #'stringp)
          ;; Swift: pin the Xcode scheme/destination so the build commands
          ;; never prompt, and opt a project out of format-on-save.
          (cons 'my/swift-format-on-save #'booleanp)
          (cons 'my/swift-xcode-scheme #'stringp)
          (cons 'my/swift-xcode-destination #'stringp)
          (cons 'my/swift-xcode-configuration #'stringp)))
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

;; Python debugging through the same dap-mode UI/bindings (<f5>, C-c d ...).
;; `M-x dap-debug' offers Python launch/attach templates. Needs debugpy in the
;; active venv:  pip install debugpy
(use-package dap-python
  :straight nil                         ; part of dap-mode
  :after dap-mode
  :custom (dap-python-debugger 'debugpy)
  :config (require 'dap-python))

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

(use-package ghostel
  :custom
  (ghostel-module-auto-install 'download))

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

;; --- Swift ----------------------------------------------------------------
;; Two shapes of Swift project, one set of keys.  C-c C-b / C-c C-r / C-c C-t
;; look at the project root and dispatch:
;;
;;   * SwiftPM (Package.swift) -- no per-project setup. sourcekit-lsp reads the
;;     manifest itself, and the keys shell out to `swift build|run|test'.
;;   * Xcode (.xcodeproj / .xcworkspace) -- sourcekit-lsp cannot read an Xcode
;;     project, so it needs a buildServer.json at the root telling it how to
;;     recover each file's compiler flags.  `C-c C-x s' writes one with
;;     xcode-build-server; run it once per project, and again after adding
;;     files or changing build settings, or the new files get no completion.
;;     The keys then drive xcodebuild against a scheme and a destination.
;;
;; Scheme and destination are asked for once per project per session and
;; remembered; a prefix argument (C-u) on any of the commands re-asks, and
;; .dir-locals.el can pin them (see `my/swift-xcode-scheme' below).
;;
;; Tools are resolved with `xcrun --find' rather than taken from /usr/bin, so
;; `xcode-select' switches the language server and formatter along with the
;; compiler.  sourcekit-lsp and swift-format ship inside Xcode; the Xcode-project
;; half also wants  brew install xcode-build-server.

(defun my/swift-toolchain-tool (name)
  "Absolute path to NAME in the active Xcode toolchain, or nil if absent.
`xcrun --find' resolves against whichever Xcode `xcode-select' points at,
so switching Xcode switches the tool instead of pinning the stub in /usr/bin."
  (let ((path (string-trim
               (shell-command-to-string
                (concat "xcrun --find " (shell-quote-argument name) " 2>/dev/null")))))
    (and (not (string-empty-p path))
         (file-executable-p path)
         path)))

(defun my/swift-project-find (dir)
  "Recognise a SwiftPM package or Xcode project at or above DIR.
Without this, project.el falls back to version control, so a package that
is not a git checkout looks rootless and both `my/swift-project-root' and
lsp-mode's root guess land on the source subdirectory that happens to hold
the file -- which puts the wrong folder in the lsp session and leaves
sourcekit-lsp without the manifest it needs."
  (let ((root (locate-dominating-file
               dir (lambda (d)
                     (or (file-exists-p (expand-file-name "Package.swift" d))
                         (file-exists-p (expand-file-name "buildServer.json" d))
                         (directory-files d nil "\\.xc\\(odeproj\\|workspace\\)\\'" t))))))
    (when root
      (cons 'transient (expand-file-name root)))))

;; Ahead of the VC backend, so a Swift package inside a larger git repo still
;; roots at its own Package.swift rather than the repository top.
(add-hook 'project-find-functions #'my/swift-project-find -10)

(defun my/swift-project-root ()
  "Best guess at the current Swift project's root directory."
  (or (ignore-errors (and (fboundp 'lsp-workspace-root) (lsp-workspace-root)))
      (ignore-errors (project-root (project-current)))
      default-directory))

(use-package swift-mode
  :mode "\\.swift\\'"
  :interpreter "swift"
  ;; `require' the client before connecting, same reason as lsp-pyright above.
  :hook (swift-mode . (lambda () (require 'lsp-sourcekit) (lsp-deferred)))
  :bind (:map swift-mode-map
              ("C-c C-b"   . my/swift-build)     ; swift build | xcodebuild build
              ("C-c C-r"   . my/swift-run)       ; swift run   | build + launch
              ("C-c C-t"   . my/swift-test)      ; swift test  | xcodebuild test
              ("C-c C-d"   . my/swift-debug)     ; codelldb on a built binary
              ("C-c C-x s" . my/swift-xcode-setup)     ; write buildServer.json
              ("C-c C-x d" . my/swift-xcode-forget)))  ; drop scheme/destination

;; sourcekit-lsp, from the active toolchain.  It reads Package.swift directly
;; for SwiftPM packages and buildServer.json for Xcode projects, so the same
;; client covers both.
(use-package lsp-sourcekit
  :after lsp-mode
  :custom
  (lsp-sourcekit-executable (or (my/swift-toolchain-tool "sourcekit-lsp")
                                "sourcekit-lsp")))

;; --- Swift formatting ------------------------------------------------------
;; swift-format ships in the Xcode toolchain.  sourcekit-lsp does not advertise
;; textDocument/formatting, so this pipes the buffer through the binary rather
;; than going via `lsp-format-buffer' the way Java and Python do.  It honours a
;; .swift-format JSON config found by the tool's own search from the file's
;; directory upward.  Set `my/swift-format-on-save' to nil per project in
;; .dir-locals.el to disable.
(defvar my/swift-format-on-save t
  "When non-nil, run swift-format on Swift buffers on an explicit save.")

(defun my/swift-format-buffer ()
  "Reformat the current buffer with swift-format, preserving point.
`replace-buffer-contents' splices in only what actually changed, so point,
the mark and any markers survive.  On a formatter error the buffer is left
untouched and the diagnostic is reported, so a syntax error mid-edit cannot
eat your text."
  (interactive)
  (let ((bin (my/swift-toolchain-tool "swift-format")))
    (if (not bin)
        (message "swift-format not found in the active Xcode toolchain")
      (let ((out (generate-new-buffer " *swift-format*"))
            (err (make-temp-file "swift-format" nil ".err")))
        (unwind-protect
            (if (zerop (call-process-region (point-min) (point-max) bin
                                            nil (list out err) nil
                                            "format" "-"))
                (replace-buffer-contents out)
              (message "swift-format failed: %s"
                       (string-trim (with-temp-buffer
                                      (insert-file-contents err)
                                      (buffer-string)))))
          (kill-buffer out)
          (delete-file err))))))

(defun my/swift-format-before-save ()
  "Format the current Swift buffer on an explicit save."
  (when (and my/swift-format-on-save
             (my/explicit-save-p)
             (derived-mode-p 'swift-mode))
    (my/swift-format-buffer)))

(add-hook 'before-save-hook #'my/swift-format-before-save)

;; --- Xcode project plumbing ------------------------------------------------
(defvar my/swift-xcode-scheme nil
  "Xcode scheme the Swift build commands should use.
nil means ask once and remember for the session; pin it per project in
.dir-locals.el to skip the prompt entirely.")

(defvar my/swift-xcode-destination nil
  "xcodebuild -destination string, e.g. \"platform=macOS\".
nil means ask once and remember for the session.")

(defvar my/swift-xcode-configuration "Debug"
  "xcodebuild -configuration used by the build, test and run commands.")

(defvar my/swift-xcode-choices (make-hash-table :test #'equal)
  "Session cache of (SCHEME . DESTINATION) already chosen, keyed by project root.")

(defun my/swift-xcode-container (&optional root)
  "The .xcworkspace or .xcodeproj at ROOT, preferring the workspace.
Returns nil when ROOT holds neither -- which is how the commands below
tell a SwiftPM package from an Xcode project."
  (let* ((root (or root (my/swift-project-root)))
         (pick (lambda (ext)
                 (car (directory-files root t (concat "\\." ext "\\'") t)))))
    (or (funcall pick "xcworkspace") (funcall pick "xcodeproj"))))

(defun my/swift-xcode-flag (container)
  "The xcodebuild selector flag for CONTAINER: -workspace or -project."
  (if (string-suffix-p ".xcworkspace" container) "-workspace" "-project"))

(defun my/swift--json (command opener)
  "Run COMMAND and parse its output as JSON starting at the first OPENER char.
xcodebuild and simctl both prepend warnings to their JSON, so the text
before the opening brace/bracket is discarded rather than parsed."
  (let* ((out (shell-command-to-string command))
         (start (string-search opener out)))
    (and start (ignore-errors
                 (json-parse-string (substring out start) :object-type 'alist)))))

(defun my/swift-xcode-schemes (container)
  "List of scheme names defined in CONTAINER."
  (let ((data (my/swift--json
               (format "xcodebuild -list -json %s %s 2>/dev/null"
                       (my/swift-xcode-flag container)
                       (shell-quote-argument container))
               "{")))
    (append (or (alist-get 'schemes (alist-get 'workspace data))
                (alist-get 'schemes (alist-get 'project data)))
            nil)))

(defun my/swift-runtime-label (id)
  "Human-readable label for CoreSimulator runtime identifier ID.
\"com.apple.CoreSimulator.SimRuntime.iOS-26-5\" becomes \"iOS 26.5\"."
  (let ((tail (car (last (split-string id "\\.")))))
    (if (string-match "\\`\\([A-Za-z]+\\)-\\(.*\\)\\'" tail)
        (concat (match-string 1 tail) " "
                (replace-regexp-in-string "-" "." (match-string 2 tail)))
      tail)))

(defun my/swift-simulators ()
  "Alist of (LABEL . UDID) for every available simulator."
  (let ((data (my/swift--json
               "xcrun simctl list devices available -j 2>/dev/null" "{"))
        (result nil))
    (dolist (runtime (alist-get 'devices data) (nreverse result))
      (let ((label (my/swift-runtime-label (symbol-name (car runtime)))))
        (seq-doseq (dev (cdr runtime))
          (push (cons (format "%s -- %s" (alist-get 'name dev) label)
                      (alist-get 'udid dev))
                result))))))

(defun my/swift-xcode-scheme-for (root container &optional force)
  "Scheme to build for CONTAINER under ROOT, asked once and remembered.
Non-nil FORCE re-asks even when a choice is already recorded."
  (or (and (not force) my/swift-xcode-scheme)
      (and (not force) (car (gethash root my/swift-xcode-choices)))
      (let* ((schemes (my/swift-xcode-schemes container))
             (scheme (completing-read "Xcode scheme: " schemes nil
                                      (and schemes t) nil nil (car schemes))))
        (puthash root (cons scheme (cdr (gethash root my/swift-xcode-choices)))
                 my/swift-xcode-choices)
        scheme)))

(defun my/swift-xcode-destination-for (root &optional force)
  "xcodebuild -destination for ROOT, asked once and remembered.
Offers the Mac plus every booted-or-bootable simulator."
  (or (and (not force) my/swift-xcode-destination)
      (and (not force) (cdr (gethash root my/swift-xcode-choices)))
      (let* ((sims (my/swift-simulators))
             (pick (completing-read "Destination: "
                                    (cons "My Mac" (mapcar #'car sims)) nil t))
             (dest (if (equal pick "My Mac")
                       "platform=macOS"
                     (format "platform=iOS Simulator,id=%s"
                             (cdr (assoc pick sims))))))
        (puthash root (cons (car (gethash root my/swift-xcode-choices)) dest)
                 my/swift-xcode-choices)
        dest)))

(defun my/swift-xcode-forget ()
  "Forget this project's remembered Xcode scheme and destination."
  (interactive)
  (remhash (my/swift-project-root) my/swift-xcode-choices)
  (message "Swift: scheme and destination will be asked again"))

(defun my/swift-xcode-args (container scheme destination)
  "Common xcodebuild arguments selecting CONTAINER, SCHEME and DESTINATION."
  (format "%s %s -scheme %s -destination %s -configuration %s"
          (my/swift-xcode-flag container)
          (shell-quote-argument container)
          (shell-quote-argument scheme)
          (shell-quote-argument destination)
          (shell-quote-argument my/swift-xcode-configuration)))

(defun my/swift-xcode-setting (var)
  "Shell snippet pulling build setting VAR out of \"$S\"."
  (format "printf '%%s\\n' \"$S\" | awk -F' = ' '$1 ~ /%s$/ {print $2; exit}'" var))

;; --- Commands: SwiftPM and Xcode, dispatched on the project shape ----------
(defun my/swift-compile (command)
  "Run COMMAND at the Swift project root through `compile'."
  (let ((default-directory (my/swift-project-root)))
    (compile command)))

(defun my/swift-xcode-action (action force)
  "Run xcodebuild ACTION (\"build\" or \"test\") on the current Xcode project."
  (let* ((root (my/swift-project-root))
         (container (my/swift-xcode-container root))
         (scheme (my/swift-xcode-scheme-for root container force))
         (dest (my/swift-xcode-destination-for root force)))
    (my/swift-compile
     (format "xcodebuild %s %s"
             (my/swift-xcode-args container scheme dest) action))))

(defun my/swift-build (&optional force)
  "Build the current Swift project.
Runs xcodebuild when the root holds an .xcodeproj/.xcworkspace, and
`swift build' otherwise.  With prefix FORCE, re-ask scheme and destination."
  (interactive "P")
  (if (my/swift-xcode-container)
      (my/swift-xcode-action "build" force)
    (my/swift-compile "swift build")))

(defun my/swift-test (&optional force)
  "Run the current Swift project's tests.
xcodebuild test for an Xcode project, `swift test' for a SwiftPM package."
  (interactive "P")
  (if (my/swift-xcode-container)
      (my/swift-xcode-action "test" force)
    (my/swift-compile "swift test")))

(defun my/swift-run (&optional force)
  "Build and run the current Swift project.
For a SwiftPM package this is `swift run'.  For an Xcode project it builds
the scheme, then either launches the .app on the chosen simulator (booting
it and bringing Simulator.app forward first) or runs the Mac binary, with
the app's stdout piped into the compilation buffer."
  (interactive "P")
  (let* ((root (my/swift-project-root))
         (container (my/swift-xcode-container root)))
    (if (not container)
        (my/swift-compile "swift run")
      (let* ((scheme (my/swift-xcode-scheme-for root container force))
             (dest (my/swift-xcode-destination-for root force))
             (args (my/swift-xcode-args container scheme dest))
             (udid (and (string-match "id=\\([0-9A-Fa-f-]+\\)" dest)
                        (match-string 1 dest))))
        (my/swift-compile
         (string-join
          (append
           (list "set -e"
                 (format "xcodebuild %s build" args)
                 (format "S=$(xcodebuild %s -showBuildSettings)" args)
                 (format "D=$(%s)" (my/swift-xcode-setting "BUILT_PRODUCTS_DIR"))
                 (format "N=$(%s)" (my/swift-xcode-setting "FULL_PRODUCT_NAME"))
                 ;; A destination the scheme does not support makes xcodebuild
                 ;; print its valid destinations and emit no settings; without
                 ;; this guard the install below would be handed "/" and fail
                 ;; with a far less obvious message.
                 (concat "[ -n \"$D\" ] && [ -n \"$N\" ] || "
                         "{ echo 'swift: no build settings -- is the destination"
                         " valid for this scheme?' >&2; exit 1; }"))
           (if udid
               (list (format "B=$(%s)"
                             (my/swift-xcode-setting "PRODUCT_BUNDLE_IDENTIFIER"))
                     (format "xcrun simctl boot %s 2>/dev/null || true" udid)
                     "open -a Simulator"
                     (format "xcrun simctl install %s \"$D/$N\"" udid)
                     (format "xcrun simctl launch --console-pty %s \"$B\"" udid))
             (list "case \"$N\" in"
                   "  *.app) \"$D/$N/Contents/MacOS/$(basename \"$N\" .app)\" ;;"
                   "  *) \"$D/$N\" ;;"
                   "esac")))
          "\n"))))))

(defun my/swift-xcode-setup (&optional force)
  "Write buildServer.json at the project root so sourcekit-lsp reads this
Xcode project.  Without it the server has no compiler flags for files in an
.xcodeproj and completion/navigation stay empty.  Re-run after adding files
or changing build settings.  With prefix FORCE, re-ask for the scheme."
  (interactive "P")
  (let* ((root (my/swift-project-root))
         (container (or (my/swift-xcode-container root)
                        (user-error "No .xcodeproj or .xcworkspace under %s" root))))
    (unless (executable-find "xcode-build-server")
      (user-error "xcode-build-server not found -- brew install xcode-build-server"))
    (my/swift-compile
     (format "xcode-build-server config %s %s -scheme %s"
             (my/swift-xcode-flag container)
             (shell-quote-argument container)
             (shell-quote-argument
              (my/swift-xcode-scheme-for root container force))))))

;; Swift debugging reuses the codelldb adapter already installed for Zig.
;; SwiftPM puts debug binaries in .build/debug; for an Xcode project, point the
;; prompt at the .app's binary under DerivedData (or the built-products dir that
;; `my/swift-run' prints).  Simulator processes need Xcode's own debugger, so
;; this covers Mac and SwiftPM executables.
(with-eval-after-load 'dap-codelldb
  (dap-register-debug-template
   "Swift :: codelldb launch"
   (list :type "lldb"
         :request "launch"
         :name "Swift :: codelldb launch"
         :program "${workspaceFolder}/.build/debug/"
         :cwd "${workspaceFolder}")))

(defun my/swift-debug (program)
  "Debug a compiled Swift PROGRAM with codelldb.
Build first so debug info exists; completion defaults to the SwiftPM
.build/debug directory."
  (interactive
   (list (read-file-name
          "Swift executable to debug: "
          (expand-file-name ".build/debug/" (my/swift-project-root)))))
  (require 'dap-codelldb)
  (dap-debug (list :type "lldb"
                   :request "launch"
                   :name "Swift :: Debug"
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
  (sly-enable-evaluate-in-emacs t)
  ;; Never let sly.el's load-time check evict SLIME from `lisp-mode-hook' (or
  ;; prompt about it): `my/cl-switch-backend' below owns that hook.
  (sly-replace-slime nil)
  ;; Fuzzy symbol completion + REPL input history that survives restarts.
  (sly-complete-symbol-function 'sly-flex-completions)
  (sly-mrepl-history-file-name (locate-user-emacs-file "sly-mrepl-history"))
  ;; Enable extra contribs (installed below) on top of the default sly-fancy.
  (sly-contribs '(sly-fancy
;;                  sly-quicklisp        ; sly-quickload systems from the REPL
                  sly-asdf             ; load/reload/test ASDF systems
                  sly-macrostep        ; step through macroexpansions
                  sly-repl-ansi-color)); ANSI colours in the REPL (CIEL)
  ;; company completion in Lisp buffers and the REPL (sly provides capf).
  :hook ((lisp-mode . company-mode)
         (sly-mrepl-mode . company-mode)))

;; The contrib packages named in `sly-contribs' above -- installed here so
;; they're on `load-path' when sly requires them at connect time. `:after sly'
;; keeps them from dragging sly in at startup.
;; sly-quicklisp is intentionally not enabled (it's commented out of
;; `sly-contribs' above), so it isn't installed here either. Re-add the
;; contrib line and uncomment this to bring back REPL `sly-quickload'.
;; (use-package sly-quicklisp :after sly)
(use-package sly-asdf :after sly)
(use-package sly-macrostep :after sly)
(use-package sly-repl-ansi-color :after sly)

;;; ---------------------------------------------------------------------------
;;; SLIME, installed beside SLY -- with exactly one of them active at a time.
;;;
;;; They cannot both be on.  Each hangs a minor mode off `lisp-mode-hook'
;;; (`sly-editing-mode' / `slime-lisp-mode-hook'), and both of those minor modes
;;; bind M-., M-,, C-c C-c, C-c C-k, C-c C-l ... in their own keymap.  With both
;;; hooks installed, whichever minor mode was enabled last shadows the other, so
;;; the keys in a .lisp buffer would silently talk to the wrong backend.
;;;
;;; The rule here is therefore: `lisp-mode-hook' carries exactly one of the two
;;; entries, and `my/cl-switch-backend' is the only thing that moves it.
;;;
;;; Two load-time behaviours are why the switcher is more than a pair of
;;; add-hook/remove-hook calls:
;;;
;;;   * The last form in slime.el unconditionally appends
;;;     `slime-lisp-mode-hook' to `lisp-mode-hook'.  So *any* load of SLIME --
;;;     including an incidental one -- needs a cleanup pass after it.
;;;   * The last form in sly.el looks for `slime-lisp-mode-hook' in
;;;     `lisp-mode-hook' and, per `sly-replace-slime', either prompts to evict
;;;     SLIME or warns.  Pinning that to nil (in the SLY block above) and
;;;     loading SLY only while SLIME's hook is absent takes its silent branch.
;;;
;;; Caveat: switching does not kill a running connection.  A live SLY REPL keeps
;;; working as a buffer; it just stops owning the keys in your source files.
;;; The switcher tells you when it leaves one behind.
;;; ---------------------------------------------------------------------------

(use-package slime
  :defer t
  :custom
  ;; The same three implementations as the SLY block, so either backend can
  ;; start whichever Lisp you want.
  (slime-lisp-implementations
   `((sbcl ("sbcl" "--dynamic-space-size" "4Gb") :coding-system utf-8-unix)
     (clisp ("clisp" "-q") :coding-system utf-8-unix)
     (ciel ("sbcl" "--core" ,(expand-file-name "~/Quicklisp/local-projects/CIEL/ciel-core") "--eval" "(in-package :ciel-user)"))))
  (slime-default-lisp 'sbcl)
  ;; Mirrors of the SLY settings: fuzzy completion, REPL history across restarts.
  (slime-complete-symbol-function 'slime-fuzzy-complete-symbol)
  (slime-repl-history-file (locate-user-emacs-file "slime-history.eld"))
  ;; SLIME ships its contribs in-tree, so unlike SLY's these need no extra
  ;; packages -- `slime-company' being the one exception, installed below.
  ;; `slime-quicklisp' is left out to match the SLY block's choice.
  (slime-contribs '(slime-fancy      ; repl, autodoc, inspector, fuzzy, ...
                    slime-asdf       ; load/reload/test ASDF systems
                    slime-macrostep  ; step through macroexpansions
                    slime-media      ; inline images in the REPL (im:display)
                    slime-company))  ; company backend (package below)
  :hook (slime-repl-mode . company-mode))

;; SLIME's company glue is a separate package (SLY just provides a capf).  It
;; has to be on `load-path' before `slime-setup' requires `slime-company' as a
;; contrib -- naming it here is enough, since straight installs at init time.
(use-package slime-company
  :after slime
  :custom (slime-company-completion 'fuzzy))


;;; --- The switch ------------------------------------------------------------

(defvar my/cl-backend 'sly
  "The active Common Lisp backend: `sly' or `slime'.

The real state lives in `lisp-mode-hook' and in each Lisp buffer's minor
modes; this variable only records it.  Change it with
\\[my/cl-switch-backend] rather than by hand.  Its value here is the
backend armed at startup.")

(defconst my/cl--hook-entry
  '((sly . sly-editing-mode)
    (slime . slime-lisp-mode-hook))
  "The `lisp-mode-hook' entry each backend installs.")

(defun my/cl--other (backend)
  "The backend that is not BACKEND."
  (if (eq backend 'sly) 'slime 'sly))

(defun my/cl--connected-p (backend)
  "Non-nil if BACKEND has a live Lisp connection right now."
  (pcase backend
    ('sly (and (fboundp 'sly-connected-p) (sly-connected-p)))
    ('slime (and (fboundp 'slime-connected-p) (slime-connected-p)))))

(defun my/cl--set-buffer-backend (backend)
  "In the current Lisp buffer, switch BACKEND on and the other one off."
  (pcase (my/cl--other backend)
    ;; `sly-editing-mode's body runs `(sly-mode 1)' unconditionally -- on
    ;; disable as well as on enable -- so `sly-mode' has to be turned off
    ;; *after* it, not before, or it comes straight back on.
    ('sly (when (bound-and-true-p sly-editing-mode) (sly-editing-mode -1))
          (when (bound-and-true-p sly-mode) (sly-mode -1)))
    ('slime (when (bound-and-true-p slime-mode) (slime-mode -1))))
  ;; Each of these also sets `lisp-indent-function' to its backend's flavour.
  (pcase backend
    ('sly (sly-editing-mode 1))
    ('slime (slime-lisp-mode-hook))))

(defun my/cl-switch-backend (backend)
  "Give BACKEND (`sly' or `slime') ownership of Lisp editing, disabling the other.

Moves the entry on `lisp-mode-hook', then fixes up every `lisp-mode'
buffer that is already open.  Running connections and REPL buffers are
left alone: they keep working, they just stop owning the keys in your
source buffers."
  (interactive
   (list (intern (completing-read
                  (format "Common Lisp backend (currently %s): " my/cl-backend)
                  '("sly" "slime") nil t nil nil
                  (symbol-name (my/cl--other my/cl-backend))))))
  (let ((other (my/cl--other backend)))
    ;; Load order is deliberate -- see the commentary above.
    (pcase backend
      ('sly (remove-hook 'lisp-mode-hook 'slime-lisp-mode-hook)
            (require 'sly))
      ('slime (require 'slime)            ; re-adds SLIME's hook, undone below
              (slime-setup)))             ; loads the contribs
    (remove-hook 'lisp-mode-hook (alist-get other my/cl--hook-entry))
    (add-hook 'lisp-mode-hook (alist-get backend my/cl--hook-entry))
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (when (derived-mode-p 'lisp-mode)
          (my/cl--set-buffer-backend backend))))
    (setq my/cl-backend backend)
    (message "Common Lisp backend: %s%s" backend
             (if (my/cl--connected-p other)
                 (format " (a %s connection is still live)" other)
               ""))))

(defun my/cl-repl ()
  "Start a REPL with whichever backend is active."
  (interactive)
  (call-interactively (if (eq my/cl-backend 'sly) #'sly #'slime)))

(keymap-global-set "C-c L L" #'my/cl-switch-backend)
(keymap-global-set "C-c L r" #'my/cl-repl)

;; Both packages' autoloads push their own entry onto `lisp-mode-hook' at
;; startup, so arm `my/cl-backend' before any Lisp buffer can open.  Choosing
;; SLY stays lazy, since `sly-editing-mode' is autoloaded.  Choosing SLIME does
;; load SLIME now: `slime-lisp-mode-hook' carries no autoload cookie, so
;; straight's generated autoloads do not cover it and the hook would otherwise
;; be void the first time you opened a .lisp file.
(if (eq my/cl-backend 'sly)
    (progn (remove-hook 'lisp-mode-hook 'slime-lisp-mode-hook)
           (add-hook 'lisp-mode-hook 'sly-editing-mode))
  (my/cl-switch-backend my/cl-backend))


;; Structural Lisp editing (slurp/barf/splice) that coexists with
;; electric-pair, unlike paredit. Covers CL buffers, elisp, and the REPL.
;; Bindings live under a `C-c s' (sexp) prefix because the classic paredit
;; keys (C-), C-(, M-[) don't transmit in most terminals.
(use-package puni
  :hook ((lisp-mode emacs-lisp-mode lisp-interaction-mode
          sly-mrepl-mode slime-repl-mode)
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

;; Highlight every occurrence of the symbol under point (auto, after a short
;; idle) and let you pin sticky highlights on several symbols at once. Great
;; in Lisp, where highlighting is textual -- no LSP/semantic tokens for CL.
;; The nav/edit ops live under a `C-c h' (highlight) prefix rather than the
;; package's default M-n/M-p, which are REPL history in `sly-mrepl'. Once you
;; pin a symbol with `C-c h h', single keys (n/p/i/...) also work transiently
;; while point sits on it, via symbol-overlay's own overlay keymap.
(use-package symbol-overlay
  :diminish
  :hook ((lisp-mode emacs-lisp-mode lisp-interaction-mode
          sly-mrepl-mode slime-repl-mode)
         . symbol-overlay-mode)
  :custom-face
  ;; The auto (idle) highlight uses `symbol-overlay-default-face', which by
  ;; default inherits `highlight' (and even `lazy-highlight' is too faint on a
  ;; near-black ef-dark background). Use an explicit high-contrast bg with a
  ;; light fg + bold so the symbol under point is unmistakable. Set via
  ;; :custom-face so it lands in the `user' theme and isn't clobbered by
  ;; `ef-themes-select'. NOTE: this is now a fixed colour -- if you switch to a
  ;; *light* theme, change the bg (e.g. a pale colour) or go back to
  ;; `:inherit lazy-highlight' for theme-adaptivity.
  (symbol-overlay-default-face
   ((t (:background "#7b4bab" :foreground "#ffffff" :weight bold))))
  :bind (:map symbol-overlay-mode-map
              ("C-c h h" . symbol-overlay-put)          ; toggle a sticky highlight
              ("C-c h n" . symbol-overlay-jump-next)
              ("C-c h p" . symbol-overlay-jump-prev)
              ("C-c h r" . symbol-overlay-rename)       ; rename all in buffer
              ("C-c h R" . symbol-overlay-remove-all)))

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

;; Markdown editing. Without this package .md files open in text/fundamental
;; mode and the visual-fill-column hook below never fires.
(use-package markdown-mode
  :mode ("\\.md\\'" "\\.markdown\\'"))

(use-package visual-fill-column
  :custom
  (visual-fill-column-width 80)
  (fill-column 80)
  :hook (markdown-mode . (lambda ()
                           (visual-line-mode 1)
                           (visual-fill-column-mode 1))))


;;; --- Local packages --------------------------------------------------------
;;; ~/.emacs.d/site-lisp holds hand-written libraries that are not on any
;;; archive, so they are loaded by path rather than by straight.el.

(add-to-list 'load-path (expand-file-name (locate-user-emacs-file "site-lisp")))

;; Objective-C selector documentation, out of a local SQLite index of Apple's
;; API reference (built by ~/.emacs.d/objc-docs/build.py from the same DocC
;; JSON that developer.apple.com and Dash both use).  Useful from .lisp buffers
;; too, where selectors appear as strings: point inside
;; "webView:didFinishNavigation:" and hit C-c o.  C-c O searches every abstract.
(use-package objc-tools
  :straight nil
  :commands (objc-tools-lookup-selector objc-tools-search objc-tools-build
             objc-tools-browse-selector objc-tools-open-in-dash
             objc-tools-show-headers)
  :bind (("C-c o" . objc-tools-lookup-selector)
         ("C-c O" . objc-tools-search)))

;; ARM64 assembly (GNU as on Linux, clang on macOS).  `.s' and `.S' files only
;; ever mean arm64 here; C-c C-c assembles, Flymake reports assembler errors.
;;
;; asm-lsp (`cargo install asm-lsp') adds hover docs for every A64 instruction,
;; completion and label navigation.  Its global config,
;; ~/Library/Application Support/asm-lsp/.asm-lsp.toml, selects gas + arm64.
;; lsp-asm builds its client from `lsp-asm-active-modes' when it loads, so the
;; mode must be in that list beforehand -- hence :init, not after-load.
(use-package arm64-asm
  :straight nil
  :mode ("\\.[sS]\\'" . arm64-asm-mode)
  :hook (arm64-asm-mode . lsp-deferred)
  :init
  (add-to-list 'exec-path (expand-file-name "~/.cargo/bin"))
  (setq lsp-asm-active-modes
        '(asm-mode fasm-mode masm-mode nasm-mode gas-mode arm64-asm-mode))
  (with-eval-after-load 'lsp-mode
    (add-to-list 'lsp-language-id-configuration '(arm64-asm-mode . "asm"))))

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
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




















