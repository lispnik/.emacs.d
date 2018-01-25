(use-package rust-mode
  :ensure t
  :config
  (use-package cargo
    :ensure t
    :config
    (add-hook 'rust-mode-hook 'cargo-minor-mode))
  (use-package racer
    :ensure t
    :config
    (add-hook 'rust-mode-hook 'racer-mode)
    (add-hook 'racer-mode-hook 'eldoc-mode))
  (use-package flycheck-rust
    :ensure t
    :config
    (add-hook 'flycheck-mode-hook 'flycheck-rust-setup)
    (add-hook 'rust-mode-hook 'flycheck-mode)))

;; ;; TODO
;; ;; bind racer-describe
;; ;; bind company-complete
;; ;; rust rls?

(provide 'my-config-rust)
