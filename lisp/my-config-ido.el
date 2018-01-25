(use-package ido
  :ensure t
  :init (setq ido-enable-prefix nil
              ido-enable-flex-matching t
              ido-create-new-buffer 'always
              ido-use-filename-at-point 'guess
              ido-max-prospects 10
              ido-default-file-method 'selected-window
              ido-auto-merge-work-directories-length -1)
  :config
  (use-package ido-completing-read+
    :ensure t
    :config (ido-ubiquitous-mode 1))
  (use-package flx-ido
    :ensure t
    :config
    (flx-ido-mode 1))
  (ido-mode 1)
  (ido-everywhere t)
  (setq ido-use-faces nil))

(use-package recentf
  :ensure t
  :bind (("C-x f" . recentf-ido-find-file))
  :config
  (use-package recentf-ext
    :ensure t)
  ;; https://www.emacswiki.org/emacs/RecentFiles
  (defun recentf-ido-find-file ()
    "Find a recent file using Ido."
    (interactive)
    (let ((file (ido-completing-read "Recent file: " recentf-list nil t)))
      (when file
        (find-file file)))))

(provide 'my-config-ido)
