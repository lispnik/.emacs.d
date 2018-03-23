(defun my-repl-mode ()
  (face-remap-add-relative 'default :background "#ffffdd"))

(setq inhibit-startup-screen t
      inhibit-startup-echo-area-message (user-login-name)
      ring-bell-function 'ignore
      blink-matching-paren nil)

(fset 'yes-or-no-p 'y-or-n-p)

(when (eq window-system 'ns)
  (setq ns-command-modifier 'meta
        ns-alternate-modifier 'super))

(setq-default indent-tabs-mode nil
              tab-width 4
              fill-column 100)

(use-package diminish :ensure t)

(use-package which-key
  :ensure t
  :diminish which-key-mode
  :config
  (which-key-mode 1))

(use-package anzu
  :ensure t
  :diminish anzu
  :bind (("M-%" . anzu-query-replace)
         ("C-M-%" . anzu-query-replace-regexp))
  :config
  (global-anzu-mode))

(use-package zop-to-char
  :ensure t
  :bind (("M-z" . zop-to-char)))

(use-package desktop
  :config
  (desktop-save-mode 1))

(use-package company
  :ensure t
  :config
  (use-package company-quickhelp
    :ensure t
    :config
    (company-quickhelp-mode 1)))

(use-package smex
  :ensure t
  :config
  (smex-initialize)
  (global-set-key (kbd "M-x") 'smex)
  (global-set-key (kbd "M-X") 'smex-major-mode-commands))

(use-package projectile
  :ensure t
  :config
  (setq projectile-mode-line
        '(:eval
          (if
              (file-remote-p default-directory)
              " Projectile"
            (format " %s"
                    (projectile-project-name)))))
  (projectile-global-mode))

(use-package ediff
  :config
  (setq ediff-window-setup-function 'ediff-setup-windows-plain))

(use-package flycheck
  :ensure t
  :config
  (define-key flycheck-mode-map (kbd "M-n") 'flycheck-next-error)
  (define-key flycheck-mode-map (kbd "M-p") 'flycheck-previous-error))

(use-package ispell
  :config
  (setq ispell-program-name "aspell"
        ispell-extra-args '("--sug-mode=ultra")))

(use-package exec-path-from-shell
  :if (memq window-system '(mac ns))
  :ensure t
  :config
  (exec-path-from-shell-initialize))

(use-package shell
  :config
  (add-hook 'shell-mode-hook 'my-repl-mode))

(use-package eshell
  :config
  (add-hook 'eshell-mode-hook 'my-repl-mode))

(use-package dired
  :config
  (add-hook 'dired-mode-hook 'hl-line-mode)
  (use-package dired-x
    :config
    (add-hook 'dired-mode-hook 'dired-omit-mode)
    
    (when (eq system-type 'windows-nt)
      (setq dired-omit-files "^\\.?#\\|^\\.$\\|^\\.\\.$\\|^ntuser.*\\|NTUSER.*"))))

(use-package with-editor
  :ensure t
  :config
  (add-hook 'shell-mode-hook 'with-editor-export-editor)
  (add-hook 'term-exec-hook 'with-editor-export-editor)
  (add-hook 'eshell-mode-hook 'with-editor-export-editor))

(use-package dired-atool
  :ensure t
  :bind (:map dired-mode-map
              ("z" . dired-atool-do-unpack)
              ("Z" . dired-atool-do-pack)))

(use-package dired-quick-sort
  :ensure t
  :config
  (dired-quick-sort-setup))

(use-package dired-x
  :bind (:map dired-mode-map
              ("M-o" . dired-omit-mode))
  :config
  (add-hook 'dired-mode-hook 'dired-omit-mode))

(use-package projectile-ripgrep
  :ensure t
  :config
  (define-key projectile-command-map (kbd "s r") 'projectile-ripgrep))

(provide 'my-config-emacs)
