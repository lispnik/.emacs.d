;; -*- lexical-binding: t; indent-tabs-mode: nil -*-

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

(use-package diminish)

(use-package exec-path-from-shell
  :if (or (memq window-system '(mac ns x))
          (daemonp))
  :config
  (exec-path-from-shell-initialize))

(use-package which-key
  :config (which-key-mode)
  :diminish)

(use-package monet
  :straight (:type git :host github :repo "stevemolitor/monet"))

(use-package claude-code
    :straight (:type git :host github :repo "stevemolitor/claude-code.el")
    :bind-keymap ("C-c c" . claude-code-command-map)
    :config
    (setq claude-code-terminal-backend 'eat)
    (add-hook 'claude-code-process-environment-functions #'monet-start-server-function)
    (add-hook 'claude-code-process-environment-functions
              (lambda (_buf _dir) '("CLAUDE_CODE_DISABLE_ANIMATION=1")))
    (monet-mode 1))

(use-package flycheck)

(use-package company
  :hook ((emacs-lisp-mode . company-mode)
         (lsp-mode . company-mode)))

(use-package company-quickhelp
  :config (company-quickhelp-mode))

(setq read-process-output-max (* 1024 1024)
      gc-cons-threshold (* 100 1024 1024))

(use-package lsp-mode
  :init
  (setq lsp-keymap-prefix "C-c l")
  :hook ((java-mode . lsp)
         (lsp-mode . lsp-enable-which-key-integration)
         (lsp-mode . lsp-inlay-hints-mode)
         (lsp-mode . lsp-headerline-breadcrumb-mode))
  :commands lsp
  :config
  (add-to-list 'lsp-language-id-configuration '(tcl-mode . "tcl"))
  (add-to-list 'lsp-language-id-configuration '(perl-mode . "pls"))
  (lsp-register-client
   (make-lsp-client :new-connection (lsp-stdio-connection "/Users/mkennedy/Projects/lsp/lsp.tcl")
                    :activation-fn (lsp-activate-on "tcl")
                    :server-id 'lsptcl))
  (lsp-register-client
   (make-lsp-client :new-connection (lsp-stdio-connection "/Users/mkennedy/Projects/perl5/bin/pls")
                    :activation-fn (lsp-activate-on "perl")
                    :server-id 'lsppls)))

(use-package lsp-ui
  :hook (lsp-mode . lsp-ui-mode)
  :custom
  (lsp-ui-doc-enable t)
  (lsp-ui-doc-position 'at-point)
  (lsp-ui-sideline-enable t)
  (lsp-ui-sideline-show-diagnostics t)
  (lsp-ui-sideline-show-code-actions t)
  (lsp-ui-peek-enable t))

(use-package lsp-treemacs)

(use-package lsp-java
  :custom
  (lsp-java-vmargs '("-XX:+UseParallelGC"
                     "-XX:GCTimeRatio=4"
                     "-XX:AdaptiveSizePolicyWeight=90"
                     "-Dsun.zip.disableMemoryMapping=true"
                     "-Xmx4G"
                     "-Xms512m"))
  (lsp-java-references-code-lens-enabled t)
  (lsp-java-implementations-code-lens-enabled t)
  (lsp-java-save-actions-organize-imports t)
  (lsp-java-completion-guess-method-arguments t)
  :config
  (let* ((lombok-dir (expand-file-name "~/.m2/repository/org/projectlombok/lombok/"))
         (jar (when (file-directory-p lombok-dir)
                (car (sort (directory-files-recursively
                            lombok-dir
                            "lombok\\(-[0-9]+\\.[0-9]+\\.[0-9]+\\)?\\.jar$")
                           :reverse t)))))
    (when jar
      (add-to-list 'lsp-java-vmargs (format "-javaagent:%s" jar) t))))

;; (use-package lsp-java-boot
;;   :straight t
;;   :ensure nil
;;   :hook ((lsp-mode . lsp-lens-mode)
;;          (java-mode . lsp-java-boot-lens-mode)))

(use-package dap-mode
  :straight t 
  :after lsp-mode
  :bind
  (:map dap-mode-map
        ("<f9>" . dap-continue)
        ("<f7>" . dap-step-in)
        ("<f8>" . dap-next))
  :config (dap-auto-configure-mode))

;; (use-package dap-java
;;   :ensure nil)

(use-package magit)

(use-package diff-hl
  :after magit
  :hook ((magit-post-refresh-hook . diff-hl-magit-post-refresh))
  :config (global-diff-hl-mode))

(use-package editorconfig
  :ensure nil
  :config (editorconfig-mode 1))

(use-package desktop
  :ensure nil
  :custom
  (desktop-auto-save-timeout 30)
  (desktop-load-locked-desktop 'check-pid)
  (desktop-save t)
  :config (desktop-save-mode 1))

(use-package xt-mouse
  :ensure nil
  :config (xterm-mouse-mode 1))

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

(use-package elisp-mode
  :straight nil
  :hook ((emacs-lisp-mode lisp-interaction-mode) . (lambda () (setq indent-tabs-mode nil))))

(use-package lisp-mode
  :straight nil
  :hook (lisp-mode . (lambda () (setq indent-tabs-mode nil))))

(use-package sly
  :custom
  (sly-lisp-implementations
   `((sbcl ("sbcl" "--dynamic-space-size" "4Gb") :coding-system utf-8-unix)
     (clisp ("clisp" "-q") :coding-system utf-8-unix)
     (ciel ("sbcl" "--core" ,(expand-file-name "~/Quicklisp/local-projects/CIEL/ciel-core") "--eval" "(in-package :ciel-user)"))))
  (sly-default-lisp 'sbcl)
  (sly-db-focus-debugger 'always)
  :hook (sly-mrepl-mode . (lambda () (setq indent-tabs-mode nil))))

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
 '(diff-hl-draw-borders nil)
 '(fringe-mode '(nil . 0) nil (fringe))
 '(ignored-local-variable-values
   '((Syntax . COMMON-LISP)
     (Package SERIES :use "COMMON-LISP" :colon-mode :external)
     (syntax . ANSI-COMMON-LISP) (Package . USOCKET)
     (Syntax . ANSI-Common-lisp) (Base . 10)))
 '(tool-bar-mode nil)
 '(use-short-answers t))

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 ;; '(default ((t (:family "JetBrains Mono NL" :foundry "nil" :slant normal :weight regular :height 130 :width normal))))
 )
(put 'dired-find-alternate-file 'disabled nil)
