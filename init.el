(add-to-list 'load-path "~/.emacs.d/lisp/")

(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
(unless (window-system) (menu-bar-mode -1))
(scroll-bar-mode -1)
(fringe-mode '(nil . 0))

(setq package-archives
      '(("melpa" . "https://melpa.org/packages/")
        ("gnu" . "https://elpa.gnu.org/packages/")
        ("org" . "https://orgmode.org/elpa/")))

(setq tls-checktrust t)
(setq gnutls-verify-error t)

(package-initialize)

(unless (package-installed-p 'use-package)
  (package-refresh-contents)
  (package-install 'use-package))

(setq use-package-verbose t
      messages-buffer-max-lines 10000)

(use-package s :ensure t)
(use-package dash :ensure t)

(require 'cl)

;; (require 'my-config-tls)
(require 'my-config-emacs)
(require 'my-config-eshell)
;; (require 'my-config-ido)
(require 'my-config-helm)
(require 'my-config-prog)
(require 'my-config-emacs-lisp)
(require 'my-config-c++)
(require 'my-config-clojure)
(require 'my-config-lisp)
(require 'my-config-haskell)
(require 'my-config-lua)
(require 'my-config-org)
(require 'my-config-rust)
(require 'my-config-markdown)
(require 'my-config-restclient)
;; (require 'my-config-julia)
;; (require 'my-config-firacode)
(require 'my-config-etherium)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(custom-safe-themes
   (quote
    ("3e335d794ed3030fefd0dbd7ff2d3555e29481fe4bbb0106ea11c660d6001767" default)))
 '(package-selected-packages
   (quote
    (helm-projectile helm-ag helm-descbinds helm recentf-ext sly-company sly-quicklisp sly-macrostep sly-named-readtables sly helm-config zop-to-char which-key use-package solidity-mode smex smartparens restclient-test racer platformio-mode org-present org-plus-contrib minimal-theme markdown-mode magit macrostep lua-mode julia-shell irony-eldoc intero ggtags flymake-solidity flycheck-rust flycheck-irony exec-path-from-shell epresent elisp-slime-nav dockerfile-mode dired-quick-sort dired-atool diff-hl company-restclient company-quickhelp company-irony clj-refactor cider-eval-sexp-fu cargo anzu aggressive-indent adjust-parens)))
 '(tool-bar-mode nil))

(require 'my-config-theme)

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 )
(put 'erase-buffer 'disabled nil)
