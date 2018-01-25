(use-package haskell-mode
  :ensure t
  :config
  (use-package intero
    :ensure t
    :config
    (add-hook 'haskell-mode-hook 'intero-mode)))

(provide 'my-config-haskell)
