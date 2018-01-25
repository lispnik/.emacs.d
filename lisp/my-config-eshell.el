(use-package eshell
    :ensure t
    :config
    (setq eshell-banner-message ""
          eshell-highlight-prompt nil)
    (setq eshell-prompt-function
          (lambda ()
            (let ((eshell-path (eshell/pwd)))
              (labels
                  ((parse-git (output)
                     (--map (cons (-second-item it) (-third-item it))
                            (-filter 'identity 
                                     (--map (s-match "^# branch\\.\\(head\\|upstream\\|ab\\) \\(.*\\)$" it)
                                            (split-string output "\n" t)))))
                   (build-prompt-up-down (up down)
                     (s-concat " ↑" (substring up 1) "↓" (substring down 1) ""))
                   (build-prompt (alist)
                     (s-concat
                      (propertize (abbreviate-file-name eshell-path) 'face `(:weight bold))
                      (propertize (if alist (s-concat " " (cdr (assoc "head" alist)) "") "") 'face `(:weight bold :foreground "magenta"))
                      (propertize (if (and alist (assoc "ab" alist))
                                      (let ((up-down (s-split " " (cdr (assoc "ab" alist)))))
                                        (build-prompt-up-down (-first-item up-down) (-second-item up-down)))
                                    "")
                                  'face `(:weight bold :foreground "magenta"))
                      (propertize (if (= (user-uid) 0) " # " " $ ") 'face `(:weight bold)))))
                (-> (shell-command-to-string "git status --porcelain=v2 -b")
                    parse-git
                    build-prompt))))))

(provide 'my-config-eshell)


;; Local Variables:
;; lisp-indent-function: common-lisp-indent-function
;; End:
