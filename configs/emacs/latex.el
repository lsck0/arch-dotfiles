;;; latex.el --- AUCTeX + texlab -*- lexical-binding: t; -*-

(use-package auctex
  :defer t
  :config
  (setq TeX-auto-save t
        TeX-parse-self t
        TeX-source-correlate-start-server t
        TeX-view-program-selection '((output-pdf "Zathura"))
        TeX-clean-confirm nil))

(use-package reftex
  :ensure nil
  :hook ((LaTeX-mode . reftex-mode)
         (LaTeX-mode . TeX-source-correlate-mode))
  :config (setq reftex-plug-into-AUCTeX t))

(add-hook 'LaTeX-mode-hook (lambda () (setq indent-tabs-mode t)))

;; vimtex localleader maps
(defun my/latex-keys ()
  (evil-define-key 'normal 'local
    "\\ll" #'TeX-command-master
    "\\lk" #'TeX-kill-job
    "\\lv" #'TeX-view
    "\\le" #'TeX-next-error
    "\\lt" #'reftex-toc))
(add-hook 'LaTeX-mode-hook #'my/latex-keys)

(provide 'latex)
;;; latex.el ends here
