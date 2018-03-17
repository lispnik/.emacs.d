(use-package ivy
  :ensure t
  :config
  (use-package counsel
    :ensure t
    :bind (("M-x" . counsel-M-x))
    :config
    (counsel-mode 1))
  (ivy-mode 1)
  (setq ivy-use-virtual-buffers t)
  (setq enable-recursive-minibuffers t))
	     
(provide 'my-config-ivy)
