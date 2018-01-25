(use-package clojure-mode
  :after (company smartparens)
  :ensure t
  :config
  (setq nrepl-log-messages t
        cider-repl-use-pretty-printing t
        cider-repl-display-help-banner nil
        cider-inspector-page-size 1000
        cider-cljs-lein-repl "
(do 
    (use 'figwheel-sidecar.repl-api)
    (start-figwheel!)
  (cljs-repl))")

  (use-package cider
    :ensure t
    :bind (("C-c M-j" . cider-jack-in)
           ("C-c M-J" . cider-jack-in-clojurescript)
           ("C-c M-c" . cider-connect)
           :map cider-repl-mode-map
		   ("C-M-i" . company-complete-common-or-cycle)
		   :map cider-mode-map
		   ("C-M-i" . company-complete-common-or-cycle))
    :config
    (add-hook 'cider-mode-hook 'subword-mode)
    (add-hook 'cider-mode-hook 'eldoc-mode)
    (add-hook 'cider-repl-mode-hook 'subword-mode)
    (add-hook 'cider-repl-mode-hook 'eldoc-mode)
    (add-hook 'cider-repl-mode-hook 'my-repl-mode)
    (add-hook 'cider-repl-mode-hook 'smartparens-strict-mode)
    (add-hook 'cider-repl-mode-hook 'company-mode)
    (add-hook 'cider-repl-mode-hook 'show-smartparens-mode)
    (setq cider-use-overlays t))

  (use-package clj-refactor
    :ensure t
    :config
    (add-hook 'clojure-mode-hook 'clj-refactor-mode)
    (add-hook 'cider-repl-mode-hook 'clj-refactor-mode)
    (cljr-add-keybindings-with-prefix "C-c m"))

  (use-package cider-eval-sexp-fu :ensure t)

  (put-clojure-indent 'GET 2)
  (put-clojure-indent 'POST 2)
  (put-clojure-indent 'PUT 2)
  (put-clojure-indent 'DELETE 2)
  (put-clojure-indent 'PATCH 2)
  (put-clojure-indent 'context 2)

  (add-hook 'clojure-mode-hook 'subword-mode)
  (add-hook 'clojure-mode-hook 'aggressive-indent-mode)
  (add-hook 'clojure-mode-hook 'smartparens-strict-mode)
  (add-hook 'clojure-mode-hook 'company-mode)
  (add-hook 'clojure-mode-hook 'show-smartparens-mode)

  (sp-local-pair 'clojure-mode "#{" "}")
  (sp-local-pair 'clojure-mode "#(" ")")

  (use-package adjust-parens
    :ensure t
    :config
    (add-hook 'clojure-mode-hook #'adjust-parens-mode)))

(provide 'my-config-clojure)
