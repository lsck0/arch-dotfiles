;;; latex.el --- AUCTeX + texlab -*- lexical-binding: t; -*-

(use-package auctex
  :defer t
  :config
  (setq TeX-auto-save t
        TeX-parse-self t
        TeX-source-correlate-start-server t
        TeX-view-program-selection '((output-pdf "Zathura"))
        TeX-clean-confirm nil))

;; reftex (builtin): labels/citations browser, vimtex's table of contents
;; synctex forward/backward search with zathura (vimtex default viewer)
(use-package reftex
  :ensure nil
  :hook ((LaTeX-mode . reftex-mode)
         (LaTeX-mode . TeX-source-correlate-mode))
  :config (setq reftex-plug-into-AUCTeX t))

;; after/ftplugin/latex.lua: set noexpandtab
(add-hook 'LaTeX-mode-hook (lambda () (setq indent-tabs-mode t)))

;; vimtex localleader maps (`\`): compile/view/errors/toc. AUCTeX's C-c C-c family stays live too.
(defun my/latex-keys ()
  (evil-define-key 'normal 'local
    "\\ll" #'TeX-command-master          ; vimtex \ll: compile
    "\\lk" #'TeX-kill-job                ; vimtex \lk: stop
    "\\lv" #'TeX-view                     ; vimtex \lv: view
    "\\le" #'TeX-next-error               ; vimtex \le: errors
    "\\lt" #'reftex-toc))                 ; vimtex \lt: toc
(add-hook 'LaTeX-mode-hook #'my/latex-keys)

(provide 'latex)
;;; latex.el ends here
