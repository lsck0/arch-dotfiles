;;; completion.el --- fuzzy finding + in-buffer completion -*- lexical-binding: t; -*-
;; vertico/consult/embark = telescope.  corfu/cape = nvim-cmp.
;; Keys live in keys.el.

;;;; minibuffer (telescope) -------------------------------------------------

(use-package vertico
  :init (vertico-mode 1)
  :config (setq vertico-cycle t
                vertico-count 15))

(use-package orderless
  :init
  (setq completion-styles '(orderless basic)
        completion-category-defaults nil
        completion-category-overrides '((file (styles partial-completion)))))

(use-package marginalia
  :init (marginalia-mode 1))

(use-package nerd-icons-completion
  :after marginalia
  :config
  (nerd-icons-completion-mode 1)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

(use-package consult
  :config
  (setq consult-narrow-key "<"
        register-preview-delay 0.5
        xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)
  ;; telescope file_ignore_patterns: skip .git and binaries
  (setq consult-ripgrep-args
        (concat "rg --null --line-buffered --color=never --max-columns=1000 "
                "--path-separator / --smart-case --no-heading --with-filename "
                "--line-number --hidden -g !.git "
                "-g !*.{png,jpg,jpeg,webp,pdf,ico,odt,xlsx}")
        consult-fd-args
        '("fd" "--full-path" "--color=never" "--hidden" "-E" ".git"
          "-E" "*.{png,jpg,jpeg,webp,pdf,ico,odt,xlsx}")))

;; telescope actions; embark-export + wgrep = spectre's "apply to all"
(use-package embark)

(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

(use-package wgrep
  :config (setq wgrep-auto-save-buffer t))

;;;; in-buffer (nvim-cmp) ---------------------------------------------------

(use-package corfu
  :init (global-corfu-mode 1)
  :config
  (setq corfu-auto t
        corfu-auto-delay 0.1
        corfu-auto-prefix 1
        corfu-cycle t
        corfu-count 12                    ; nvim pumheight
        corfu-preselect 'first
        corfu-popupinfo-delay '(0.3 . 0.1))
  (corfu-popupinfo-mode 1))

(use-package nerd-icons-corfu
  :after corfu
  :config (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

;; extra completion sources: filenames, buffer words, mode keywords
(use-package cape
  :init
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-keyword))

(provide 'completion)
;;; completion.el ends here
