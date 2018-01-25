(use-package helm
  :ensure t
  :init
  (progn
    (require 'helm-config))
  :config
  (setq helm-split-window-inside-p t
        helm-buffers-fuzzy-matching t
        helm-recentf-fuzzy-matching t
        helm-move-to-line-cycle-in-source t
        helm-ff-search-library-in-sexp t
        helm-ff-file-name-history-use-recentf t)
  (global-set-key (kbd "C-h") 'helm-command-prefix)
  (global-unset-key (kbd "C-x c"))
  (define-key helm-command-map (kbd "o") 'helm-occur)
  (define-key helm-command-map (kbd "g") 'helm-do-grep)
  (define-key helm-command-map (kbd "<space>") 'helm-all-mark-rings)
  (define-key helm-map (kbd "<tab>") 'helm-execute-persistent-action)

  (use-package helm-descbinds :ensure t)
  (use-package helm-ag :ensure t)
  (use-package helm-eshell
    :config
    (setq helm-eshell-fuzzy-match t))

  (use-package helm-projectile
    :ensure t)

  (global-set-key (kbd "M-x") 'helm-M-x)
  (global-set-key (kbd "C-x C-m") 'helm-M-x)
  (global-set-key (kbd "M-y") 'helm-show-kill-ring)
  (global-set-key (kbd "C-x b") 'helm-mini)
  (global-set-key (kbd "C-x C-b") 'helm-buffers-list)
  (global-set-key (kbd "C-x C-f") 'helm-find-files)
  (global-set-key (kbd "C-h f") 'helm-apropos)
  (global-set-key (kbd "C-h r") 'helm-info-emacs)
  (global-set-key (kbd "C-h C-l") 'helm-locate-library)
  (global-set-key (kbd "C-c f") 'helm-recentf)

  (define-key minibuffer-local-map (kbd "C-c C-l") 'helm-minibuffer-history)
  (define-key isearch-mode-map (kbd "C-o") 'helm-occur-from-isearch)
  (define-key shell-mode-map (kbd "C-c C-l") 'helm-comint-input-ring)
  (add-hook 'eshell-mode-hook
            #'(lambda ()
                (substitute-key-definition 'eshell-list-history 'helm-eshell-history eshell-mode-map)))

  (substitute-key-definition 'find-tag 'helm-etags-select global-map)
  (setq projectile-completion-system 'helm)
  (helm-descbinds-mode)
  (helm-mode 1)
  (helm-projectile-on))

(provide 'my-config-helm)
