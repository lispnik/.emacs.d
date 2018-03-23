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
;; (require 'my-config-helm)
(require 'my-config-ivy)
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
;; (require 'my-config-etherium)

(custom-set-variables
 ;; custom-set-variables was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(ansi-color-faces-vector
   [default bold shadow italic underline bold bold-italic bold])
 '(ansi-color-names-vector
   (vector "#424242" "#d54e53" "#b9ca4a" "#e7c547" "#7aa6da" "#c397d8" "#70c0b1" "#eaeaea"))
 '(beacon-color "#d54e53")
 '(custom-enabled-themes (quote (sanityinc-tomorrow-day)))
 '(custom-safe-themes
   (quote
    ("bb08c73af94ee74453c90422485b29e5643b73b05e8de029a6909af6a3fb3f58" "1b8d67b43ff1723960eb5e0cba512a2c7a2ad544ddb2533a90101fd1852b426e" "3e335d794ed3030fefd0dbd7ff2d3555e29481fe4bbb0106ea11c660d6001767" default)))
 '(fci-rule-color "#424242")
 '(flycheck-color-mode-line-face-to-color (quote mode-line-buffer-id))
 '(frame-background-mode (quote dark))
 '(package-selected-packages
   (quote
    (projectile-ripgrep ripgrep-projectile ripgrep elpy slime counsel ivy ivy-mode color-theme-sanityinc-tomorrow helm-projectile helm-ag helm-descbinds helm recentf-ext sly-company sly-quicklisp sly-macrostep sly-named-readtables sly helm-config zop-to-char which-key use-package solidity-mode smex smartparens restclient-test racer platformio-mode org-present org-plus-contrib minimal-theme markdown-mode magit macrostep lua-mode julia-shell irony-eldoc intero ggtags flymake-solidity flycheck-rust flycheck-irony exec-path-from-shell epresent elisp-slime-nav dockerfile-mode dired-quick-sort dired-atool diff-hl company-restclient company-quickhelp company-irony clj-refactor cider-eval-sexp-fu cargo anzu aggressive-indent adjust-parens)))
 '(tool-bar-mode nil)
 '(vc-annotate-background nil)
 '(vc-annotate-color-map
   (quote
    ((20 . "#d54e53")
     (40 . "#e78c45")
     (60 . "#e7c547")
     (80 . "#b9ca4a")
     (100 . "#70c0b1")
     (120 . "#7aa6da")
     (140 . "#c397d8")
     (160 . "#d54e53")
     (180 . "#e78c45")
     (200 . "#e7c547")
     (220 . "#b9ca4a")
     (240 . "#70c0b1")
     (260 . "#7aa6da")
     (280 . "#c397d8")
     (300 . "#d54e53")
     (320 . "#e78c45")
     (340 . "#e7c547")
     (360 . "#b9ca4a"))))
 '(vc-annotate-very-old-color nil))

(require 'my-config-theme)

(custom-set-faces
 ;; custom-set-faces was added by Custom.
 ;; If you edit it by hand, you could mess it up, so be careful.
 ;; Your init file should contain only one such instance.
 ;; If there is more than one, they won't work right.
 '(default ((t (:family "Fixedsys Excelsior 3.01" :foundry "outline" :slant normal :weight normal :height 120 :width normal)))))
(put 'erase-buffer 'disabled nil)
