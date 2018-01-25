(use-package lua-mode
  :ensure t
  :mode ("\\.lua\\'" . lua-mode)
  :interpreter ("lua" . lua-mode)
  :config
  (use-package company-lua
    :ensure t)
  (use-package flymake-lua
    :ensure t
    :config
    (add-hook 'lua-mode-hook 'flymake-lua-load)))

(provide 'my-config-lua)
