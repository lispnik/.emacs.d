(use-package irony
  ;; note: needs cmake, clang, libclang-dev installed
  :ensure t
  :config
  (add-hook 'c++-mode-hook 'irony-mode)
  (add-hook 'c-mode-hook 'irony-mode)
  (add-hook 'irony-mode-hook 'irony-cdb-autosetup-compile-options))

(use-package company-irony
  :ensure t)

(use-package eldoc
  :config
  (use-package irony-eldoc
    :ensure t
    :config
    (add-hook 'irony-mode-hook 'irony-eldoc)))

(use-package flycheck-irony
  :ensure t
  :config
  (add-hook 'c++-mode-hook 'flycheck-irony-setup)
  (add-hook 'c-mode-hook 'flycheck-irony-setup))

(use-package platformio-mode
  :after (company irony)
  :ensure t
  :config
  (add-to-list 'company-backends 'company-irony)
  (add-hook 'c++-mode-hook 'platformio-conditionally-enable))

(use-package ggtags
  ;; note: needs gnu global
  :ensure t)

(provide 'my-config-c++)
