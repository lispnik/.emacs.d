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

(use-package exec-path-from-shell
  :straight t
  :if (or (memq window-system '(mac ns x))
	  (daemonp))
  :config
  (exec-path-from-shell-initialize))

(use-package diminish :straight t)

(use-package which-key
  :config (which-key-mode)
  :diminish)

(use-package company
  :straight t
  :config
  (global-company-mode))

(use-package company-quickhelp
  :straight t)

(use-package sly
  :straight t
  :after (company)
  :custom
  (sly-lisp-implementations
   `((sbcl ("sbcl" "--dynamic-space-size" "4Gb") :coding-system utf-8-unix)
     (clisp ("clisp" "-q") :coding-system utf-8-unix)
     (ciel ("sbcl" "--core" ,(expand-file-name "~/Quicklisp/local-projects/CIEL/ciel-core") "--eval" "(in-package :ciel-user)"))))
  (sly-default-lisp 'sbcl)
  (sly-db-focus-debugger 'always))

(use-package clojure-mode :straight t)
(use-package cider :straight t)

(add-to-list 'load-path "/Users/mkennedy/Library/Application Support/SuperCollider/downloaded-quarks/scel/el")
(setq exec-path (append exec-path '("/Applications/SuperCollider.app/Contents/MacOS/")))

(require 'sclang)

;; (use-package clojure-mode
;;   :straight t)

;; (use-package cider
;;   :straight t
;;   :config (setq cider-repl-display-help-banner nil))

(use-package magit
  :straight t
  :config
  (setq magit-define-global-key-bindings 'recommended))

(use-package docker
  :straight t)

(straight-use-package
 '(eat :type git
       :host codeberg
       :repo "akib/emacs-eat"
       :files ("*.el" ("term" "term/*.el") "*.texi"
               "*.ti" ("terminfo/e" "terminfo/e/*")
               ("terminfo/65" "terminfo/65/*")
               ("integration" "integration/*")
               (:exclude ".dir-locals.el" "*-tests.el"))))

(use-package verb
  :straight t)

(use-package org
  :mode ("\\.org\\'" . org-mode)
  :config (define-key org-mode-map (kbd "C-c C-r") verb-command-map))

(use-package vterm
  :straight t)

(use-package julia-snail
  :straight t
  :custom (julia-snail-terminal-type :vterm)
  :hook (julia-mode . julia-snail-mode))

;; (use-package nano
;;   :straight (:type git :host github :repo "rougier/nano-emacs"))

;; (use-package ivy
;;   :straight t
;;   :config 
;;   (ivy-mode)
;;   (setopt ivy-use-virtual-buffers t)
;;   (setopt enable-recursive-minibuffers t)
;;   :diminish)

(use-package projectile
  :straight t
  :config
  (setopt projectile-project-search-path '(("~/Projects/" . 1)))
  (define-key projectile-mode-map (kbd "s-p") 'projectile-command-map)
  (projectile-mode))

(use-package lsp-mode
  :straight t
  :hook ((lsp-mode . lsp-enable-which-key-integration))
  :config
  (setq lsp-enable-file-watchers nil
        lsp-headerline-breadcrumb-enable nil)
  ;; Performance tweaks, see
  ;; https://github.com/emacs-lsp/lsp-mode#performance
  (setq gc-cons-threshold 100000000)
  (setq read-process-output-max (* 1024 1024)) ;; 1mb
  (setq lsp-idle-delay 0.500))

(use-package lsp-java
  :straight t
  :config
  (add-hook 'java-mode-hook 'lsp)
  (setq lsp-java-vmargs
        '("-noverify"
          "-Xmx4G"
          "-XX:+UseG1GC"
          "-XX:+UseStringDeduplication"
          "-javaagent:/Users/mkennedy/.m2/repository/org/projectlombok/lombok/1.18.36/lombok-1.18.36.jar")
        lsp-java-java-path "/usr/lib/jvm/java-21-openjdk/bin/java"

        ;; Don't organise imports on save
        lsp-java-save-action-organize-imports nil

        ;; Don't format my source code (I use Maven for enforcing my
        ;; coding style)
        lsp-java-format-enabled nil))

(use-package dap-mode
  :straight t
  :after lsp-mode
  :config (dap-auto-configure-mode))

(use-package dap-java :ensure nil)

(use-package lsp-ui
  :straight t)

(use-package shell-maker
  :straight (:type git :host github :repo "xenodium/shell-maker"))

(use-package chatgpt-shell
  :straight (:type git :host github :repo "xenodium/chatgpt-shell"))

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(ns-alternate-modifier 'meta)
 '(ns-command-modifier 'super)
 '(tool-bar-mode nil))
(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:family "JetBrains Mono" :foundry "nil" :slant normal :weight regular :height 130 :width normal)))))
