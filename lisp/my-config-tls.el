(require 'cl)

;; this is some whacked shit...

;; https://glyph.twistedmatrix.com/2015/11/editor-malware.html

(let ((trustfile (expand-file-name "cacert.pem" user-emacs-directory)))
  (setq tls-program
        (list
         (format "gnutls-cli%s --x509cafile %s -p %%p %%h"
                 (if (eq window-system 'w32) ".exe" "") trustfile)))
  (setq gnutls-verify-error t)
  (setq gnutls-trustfiles (list trustfile)))

;; test if it's checked
(let ((bad-hosts
       (loop for bad
             in `("https://wrong.host.badssl.com/"
                  "https://self-signed.badssl.com/")
             if (condition-case e
                    (url-retrieve
                     bad (lambda (retrieved) t))
                  (error nil))
             collect bad)))
  (if bad-hosts
      (error (format "tls misconfigured; retrieved %s ok"
                     bad-hosts))
    (url-retrieve "https://badssl.com"
                  (lambda (retrieved) t))))

(provide 'my-config-tls)
