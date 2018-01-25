(use-package smartparens
  :ensure t
  :config
  (use-package smartparens-config)
  (sp-use-paredit-bindings))

(use-package magit
  :after (ido)
  :ensure t
  :bind (("C-x g" . magit-status)
         ("C-x M-g" . magit-dispatch-popup)))

(use-package diff-hl
  :ensure t
  :after (dired magit)
  :config
  (global-diff-hl-mode 1)
  (add-hook 'dired-mode-hook 'diff-hl-dired-mode)
  (add-hook 'magit-post-refresh-hook 'diff-hl-magit-post-refresh)
  ;; diff-hl-draw-borders doesn't work well with various monospace fonts because the line spacing
  ;; can result in non-continuous borders, so disable it here
  (setq diff-hl-draw-borders nil))

(use-package yasnippet
  :ensure t)

(use-package dockerfile-mode
  :ensure t
  :mode "Dockerfile.*\\'")

(provide 'my-config-prog)
