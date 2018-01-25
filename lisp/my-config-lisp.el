(use-package sly-autoloads
  :ensure sly
  :config
  (use-package sly-named-readtables :ensure t)
  (use-package sly-macrostep :ensure t)
  (use-package sly-quicklisp :ensure t)
  (use-package sly-company
    :ensure t
    :config
    (add-hook 'sly-mode-hook 'sly-company-mode)
    (add-hook 'company-backends 'sly-company))
  ;;  (use-package sly-mrepl)
  (setq sly-lisp-implementations
        '((roswell ("ros" "run"))
          (ecl ("ros" "-L" "ecl" "run"))
          (sbcl ("ros" "-L" "sbcl" "run"))
          (ccl-bin ("ros" "-L" "ccl-bin" "run")))
        sly-auto-start 'always
        sly-default-lisp 'roswell)
  ;; (require 'sly-mrepl)
  (add-to-list 'sp-lisp-modes 'sly-mrepl-mode)
  (add-hook 'sly-mrepl-mode-hook 'smartparens-strict-mode)
  (add-hook 'lisp-mode-hook 'smartparens-strict-mode)
  (add-hook 'lisp-mode-hook 'show-smartparens-mode)
  ;; (add-hook 'sly-mrepl-mode-hook 'company-mode)
  ;; (eval-after-load "sly-mrepl"
  ;;   (define-key sly-mrepl-mode-map (kbd "TAB") 'company-complete-common-or-cycle))

  (use-package adjust-parens
    :ensure t
    :config
    (add-hook 'sly-mode-hook #'adjust-parens-mode)))

(provide 'my-config-lisp)
