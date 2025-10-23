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

(use-package diminish :straight t)

(use-package exec-path-from-shell
  :straight t
  :if (or (memq window-system '(mac ns x))
          (daemonp))
  :config
  (exec-path-from-shell-initialize))

(use-package which-key
  :straight t
  :config (which-key-mode)
  :diminish)

(use-package flycheck :straight t)

(use-package company
  :straight t
  :hook ((emacs-lisp-mode . company-mode)))

(use-package company-quickhelp :straight t)

(use-package lsp-mode
  :straight t
  :init
  (setq lsp-keymap-prefix "C-c l")
  :hook ((java-mode . lsp)
         (lsp-mode . lsp-enable-which-key-integration))
  :commands lsp)

(use-package lsp-ui
  :straight t
  :commands lsp-ui-mode)

(use-package lsp-treemacs :straight t)

(use-package lsp-java
  :straight t
  :config
  (let ((jar (car (sort (directory-files-recursively
                         (expand-file-name "~/.m2/repository/org/projectlombok/lombok/")
                         ".*lombok\\(-[0-9]+.[0-9]+.[0-9]+\\)?.jar$")
                        :reverse t))))
    (if (and jar (file-exists-p jar))
        (add-to-list 'lsp-java-vmargs (format "-javaagent:%s" jar) t)
      (warn "Missing %s" jar))))

;; (use-package lsp-java-boot
;;   :ensure nil
;;   :hook ((lsp-mode . lsp-lens-mode)
;;       (java-mode . lsp-java-boot-lens-mode)))

(use-package dap-mode
  :straight t
  :after lsp-mode
  :bind
  (:map dap-mode-map
        ("<f9>" . dap-continue)
        ("<f7>" . dap-step-in)
        ("<f8>" . dap-next))
  :config (dap-auto-configure-mode))

(use-package dap-java :ensure nil)

(use-package magit :straight t)

(use-package editorconfig
  :ensure nil
  :config (editorconfig-mode 1))

(use-package desktop
  :ensure nil
  :config (desktop-save-mode 1))

(use-package simple
  :ensure nil
  :config (auto-save-mode))

(use-package xt-mouse
  :ensure nil
  :config (xterm-mouse-mode 1))

(use-package eat
  :straight t)

;; (use-package sly
;;   :straight t
;;   :after (company)
;;   :custom
;;   (sly-lisp-implementations
;;    `((sbcl ("sbcl" "--dynamic-space-size" "4Gb") :coding-system utf-8-unix)
;;      (clisp ("clisp" "-q") :coding-system utf-8-unix)
;;      (ciel ("sbcl" "--core" ,(expand-file-name "~/Quicklisp/local-projects/CIEL/ciel-core") "--eval" "(in-package :ciel-user)"))))
;;   (sly-default-lisp 'sbcl)
;;   (sly-db-focus-debugger 'always))
