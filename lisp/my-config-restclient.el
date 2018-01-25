(use-package restclient
  :ensure t
  :config
  (use-package company-restclient
    :ensure t)
  (use-package restclient-test
    :ensure t))

(provide 'my-config-restclient)
