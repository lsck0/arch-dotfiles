;;; latex.el --- AUCTeX + texlab -*- lexical-binding: t; -*-

(use-package auctex
  :defer t
  :config
  (setq TeX-auto-save t
        TeX-parse-self t
        TeX-source-correlate-start-server t
        TeX-view-program-selection '((output-pdf "Sioyek"))
        ;; the builtin entry adds --inverse-search emacsclient, which overrides prefs_user.config's synctex-edit.sh
        TeX-view-program-list '(("Sioyek" ("sioyek --nofocus %o" (mode-io-correlate " --forward-search-file \"%b\" --forward-search-line %n"))
                                 "sioyek"))
        TeX-clean-confirm nil))

(defun my/latex-view-after-build (_pdf)
  "vimtex: forward search after every successful build, so the pdf follows the line just edited."
  (when (and (boundp 'TeX-command-buffer) (buffer-live-p TeX-command-buffer))
    (with-current-buffer TeX-command-buffer (TeX-view))))

(add-hook 'TeX-after-compilation-finished-functions #'my/latex-view-after-build)

(use-package reftex
  :ensure nil
  :hook ((LaTeX-mode . reftex-mode)
         (LaTeX-mode . TeX-source-correlate-mode))
  :config (setq reftex-plug-into-AUCTeX t))

(add-hook 'LaTeX-mode-hook (lambda () (setq indent-tabs-mode t)))

;;;; math autosnippets (latex_snippets.lua, snippetType = "autosnippet") ---------

(defconst my/latex-auto-snippets
  '(("//"  "\\frac{" p "}{" p "}")
    ("->"  "\\to ")
    ("!="  "\\neq ")
    ("sq"  "\\sqrt{" p "}")
    ("sum" "\\sum_{" (p "i=1") "}^{" (p "n") "}")
    ("int" "\\int_{" p "}^{" p "}"))
  "Triggers that expand as soon as they are typed inside math, each followed by its tempel template.")

(defun my/latex-auto-expand ()
  "Expand a math autosnippet trigger just typed, or turn a letter plus digit into a subscript."
  (let ((case-fold-search nil))
    (cl-loop for (trigger . template) in my/latex-auto-snippets
             when (and (looking-back (regexp-quote trigger) (- (point) (length trigger)))
                       ;; typing \sum, \sqrt, \int must not expand inside the command name
                       (not (and (string-match-p "\\`[[:alpha:]]" trigger)
                                 (looking-back (concat "\\\\[[:alpha:]]*" trigger) (line-beginning-position))))
                       (texmathp))
             return (progn (delete-char (- (length trigger)))
                           (tempel-insert template))
             finally (when-let* (((looking-back "\\(?:^\\|[^\\[:alpha:]]\\)[[:alpha:]]\\([0-9]\\)" (- (point) 3)))
                                 (digit (match-string 1)) ; before texmathp, which clobbers the match data
                                 ((texmathp)))
                       (delete-char -1)
                       (insert "_{" digit "}")))))

(defun my/latex-auto-snippets-enable ()
  (add-hook 'post-self-insert-hook #'my/latex-auto-expand nil t))
(add-hook 'LaTeX-mode-hook #'my/latex-auto-snippets-enable)

;;;; math preview (nabla.nvim) --------------------------------------------------

(defun my/math-preview ()
  "nvim SPC l p: render the formula at point."
  (interactive)
  (if (derived-mode-p 'LaTeX-mode 'latex-mode)
      (preview-at-point)
    (user-error "Math preview needs a LaTeX buffer")))

;;;; keys -----------------------------------------------------------------------

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
