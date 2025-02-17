(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name
        "straight/repos/straight.el/bootstrap.el"
        (or (bound-and-true-p straight-base-dir)
            user-emacs-directory)))
      (bootstrap-version 7))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/radian-software/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(straight-use-package 'use-package)

(use-package diminish
  :straight t)

(use-package which-key
  :straight t
  :config (which-key-mode)
  :diminish)

(use-package slime
  :straight t
  :config
  (setq slime-lisp-implementations
	'((sbcl ("sbcl") :coding-system utf-8-unix)
	  (clisp ("clisp" "-q") :coding-system utf-8-unix)))
  :diminish slime-autodoc-mode)

(setq inferior-lisp-program "sbcl")

(use-package magit
  :straight t
  :config
  (setq magit-define-global-key-bindings 'recommended))

(use-package docker
  :straight t)

(use-package eat
  :straight t)

(use-package exec-path-from-shell
  :straight t
  :config 
  (when (or (memq window-system '(mac ns x))
	    (daemonp))
    (exec-path-from-shell-initialize)))

(setq inhibit-startup-message t
      inhibit-startup-screen t)
