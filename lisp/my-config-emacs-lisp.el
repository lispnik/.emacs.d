(use-package eval-sexp-fu
  :ensure t)

(use-package elisp-slime-nav
  :ensure t)

(use-package aggressive-indent
  :ensure t)

(use-package macrostep
  :ensure t)

(use-package elisp-mode
  :after (smartparens elisp-slime-nav macrostep aggressive-indent)
  :bind (:map emacs-lisp-mode-map
              ("C-c C-c" . eval-defun)
              ("C-c e" . macrostep-expand))
  :config
  (add-hook 'emacs-lisp-mode-hook 'smartparens-strict-mode)
  (add-hook 'emacs-lisp-mode-hook 'company-mode)
  (add-hook 'emacs-lisp-mode-hook 'turn-on-elisp-slime-nav-mode)
  (add-hook 'emacs-lisp-mode-hook 'aggressive-indent-mode)
  (add-hook 'emacs-lisp-mode-hook 'turn-on-eval-sexp-fu-flash-mode)
  (add-hook 'emacs-lisp-mode-hook 'show-smartparens-mode))

(use-package ielm
  :after (smartparens elisp-slime-nav)
  :config
  (add-hook 'ielm-mode-hook 'smartparens-strict-mode)
  (add-hook 'ielm-mode-hook 'company-mode)
  (add-hook 'ielm-mode-hook 'turn-on-elisp-slime-nav-mode)
  (add-hook 'ielm-mode-hook 'show-smartparens-mode))

(use-package adjust-parens
  :ensure t
  :config
  (add-hook 'emacs-lisp-mode-hook #'adjust-parens-mode))


(provide 'my-config-emacs-lisp)
