;;; completion.el -*- lexical-binding: t; -*-
;; Fuzzy finding (telescope) + in-buffer completion (cmp).

;; vertico + orderless + marginalia + consult = telescope
(use-package vertico
  :init (vertico-mode 1)
  :config
  (setq vertico-cycle t
        vertico-count 15)
  ;; telescope picker nav: C-j/C-k move, like nvim mappings
  (define-key vertico-map (kbd "C-j") #'vertico-next)
  (define-key vertico-map (kbd "C-k") #'vertico-previous)
  ;; nvim M-q: send picker results to an editable (wgrep) buffer
  (define-key vertico-map (kbd "M-q") #'embark-export))

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
  ;; telescope file_ignore_patterns (skip binaries/images/.git)
  (setq consult-ripgrep-args
        (concat "rg --null --line-buffered --color=never --max-columns=1000 "
                "--path-separator / --smart-case --no-heading --with-filename "
                "--line-number --hidden -g !.git -g !*.{png,jpg,jpeg,webp,pdf,ico,odt,xlsx}")
        consult-fd-args
        '("fd" "--full-path" "--color=never" "--hidden" "-E" ".git"
          "-E" "*.{png,jpg,jpeg,webp,pdf,ico,odt,xlsx}")))

;; embark = telescope actions / send-to-quickfix
(use-package embark
  :bind (("C-." . embark-act)
         ("M-." . embark-dwim)))
(use-package embark-consult
  :after (embark consult)
  :hook (embark-collect-mode . consult-preview-at-point-mode))

;; corfu + cape = nvim-cmp
(use-package corfu
  :init (global-corfu-mode 1)
  :config
  (setq corfu-auto t
        corfu-auto-delay 0.1
        corfu-auto-prefix 1
        corfu-cycle t
        corfu-count 12                 ; nvim pumheight
        corfu-preselect 'first
        corfu-popupinfo-delay '(0.3 . 0.1))
  (corfu-popupinfo-mode 1)
  ;; <C-Space> complete, <C-e> abort, <CR> confirm (nvim cmp mappings)
  (define-key corfu-map (kbd "C-SPC") #'completion-at-point)
  (define-key corfu-map (kbd "C-e")   #'corfu-quit)
  (define-key corfu-map (kbd "RET")   #'corfu-insert))

(use-package nerd-icons-corfu
  :after corfu
  :config (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package cape
  :init
  (add-hook 'completion-at-point-functions #'cape-file)
  (add-hook 'completion-at-point-functions #'cape-dabbrev)
  (add-hook 'completion-at-point-functions #'cape-keyword))

;; cmp_luasnip -> snippets show up in the corfu popup
(use-package yasnippet-capf
  :after cape
  :init (add-hook 'completion-at-point-functions #'yasnippet-capf))

;; github/copilot.vim -> copilot.el. nvim: <C-a> accept, no tab map.
;; SETUP ONCE: M-x copilot-install-server  then  M-x copilot-login.
;; The prog-mode auto-on hook is commented until the server exists, because
;; copilot-mode errors at startup otherwise. After login, uncomment it.
(use-package copilot
  :vc (:url "https://github.com/copilot-emacs/copilot.el" :rev :newest)
  :commands (copilot-mode copilot-login copilot-install-server)
  ;; :hook (prog-mode . copilot-mode)
  :init
  (with-eval-after-load 'evil
    (evil-define-key 'insert 'global (kbd "C-a") #'copilot-accept-completion)))

(provide 'completion)
;;; completion.el ends here
