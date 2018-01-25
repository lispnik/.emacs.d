(use-package minimal-light-theme
  :ensure minimal-theme
  :if (member window-system '(ns mac x))
  :config
  (load-theme 'minimal-light))

(provide 'my-config-theme)
