;;; evil-setup.el --- vim emulation -*- lexical-binding: t; -*-

(use-package evil
  :init
  (setq evil-want-keybinding nil          ; evil-collection owns the rest
        evil-want-integration t
        evil-want-C-u-scroll t
        evil-want-C-i-jump t
        evil-want-Y-yank-to-eol t
        evil-undo-system 'undo-redo
        evil-search-module 'evil-search
        evil-ex-search-case 'smart
        evil-split-window-below t         ; nvim: splitbelow
        evil-vsplit-window-right t        ; nvim: splitright
        evil-respect-visual-line-mode t)
  :config
  (evil-mode 1)
  ;; jump commands recenter, like nvim's zz maps
  (dolist (cmd '(evil-scroll-down evil-scroll-up
                 evil-search-next evil-search-previous
                 evil-goto-line))
    (advice-add cmd :after (lambda (&rest _) (recenter)))))

;; vim bindings in dired, magit, compilation, ...
(use-package evil-collection
  :after evil
  :config (evil-collection-init))

(use-package evil-surround
  :after evil
  :config (global-evil-surround-mode 1))

(use-package evil-commentary
  :after evil
  :config (evil-commentary-mode 1))

;; vim-visual-multi: M-d selects the word and adds the next match, keys.el binds it
(use-package evil-multiedit
  :after evil
  :commands (evil-multiedit-match-symbol-and-next evil-multiedit-match-and-next))

(provide 'evil-setup)
;;; evil-setup.el ends here
