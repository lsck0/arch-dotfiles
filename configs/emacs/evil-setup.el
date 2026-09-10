;;; evil-setup.el --- vim emulation -*- lexical-binding: t; -*-
;; Behaviour only. Every keybinding lives in keys.el, like nvim mappings.lua.

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
  ;; jump commands recenter (nvim: C-d/C-u/n/N followed by zz)
  (dolist (cmd '(evil-scroll-down evil-scroll-up
                 evil-search-next evil-search-previous
                 evil-goto-line))
    (advice-add cmd :after (lambda (&rest _) (recenter)))))

;; sane vim bindings in every non-editing buffer (dired, magit, compilation…)
(use-package evil-collection
  :after evil
  :config (evil-collection-init))

;; mini.surround
(use-package evil-surround
  :after evil
  :config (global-evil-surround-mode 1))

;; gcc / gc commenting
(use-package evil-commentary
  :after evil
  :config (evil-commentary-mode 1))

(provide 'evil-setup)
;;; evil-setup.el ends here
