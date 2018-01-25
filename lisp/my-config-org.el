(use-package org
  :ensure org-plus-contrib
  :config
  (defun my-turn-on-org-present ()
    (org-present-big)
    (org-display-inline-images))
  (defun my-turn-off-org-present ()
    (org-present-small)
    (org-remove-inline-images))
  (use-package org-present
    :ensure t
    :config
    (add-hook 'org-present-mode-hook 'my-turn-off-org-present)
    (add-hook 'org-present-mode-quit-hook 'my-turn-off-org-present))
  (use-package ob-tangle)
  (use-package ob-clojure
    :config
    (setq org-babel-clojure-backend 'cider))
  (use-package ob-J)
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((lisp . t)
     (emacs-lisp . t)
     (clojure . t)
     (java . t)
     (J . t)))
  (use-package epresent :ensure t)
  (add-hook 'org-mode-hook 'visual-line-mode))

(provide 'my-config-org)
