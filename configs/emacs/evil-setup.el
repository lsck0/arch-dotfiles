;;; evil-setup.el -*- lexical-binding: t; -*-
;; Vim motions, window panels, text objects.

(use-package evil
  :init
  (setq evil-want-keybinding nil
        evil-want-integration t
        evil-want-C-u-scroll t
        evil-want-C-i-jump t
        evil-want-Y-yank-to-eol t
        evil-undo-system 'undo-redo
        evil-search-module 'evil-search
        evil-ex-search-case 'smart
        evil-split-window-below t
        evil-vsplit-window-right t
        evil-respect-visual-line-mode t)
  :config
  (evil-mode 1)
  ;; C-c exits insert (nvim mapping)
  (define-key evil-insert-state-map (kbd "C-c") 'evil-normal-state)
  ;; <Esc> clears search highlight (nvim <Esc> -> nohlsearch)
  (define-key evil-normal-state-map (kbd "<escape>") 'evil-ex-nohighlight)
  ;; jump commands recenter (nvim: C-d/C-u/n/N zz)
  (dolist (cmd '(evil-scroll-down evil-scroll-up
                 evil-search-next evil-search-previous
                 evil-goto-line))
    (advice-add cmd :after (lambda (&rest _) (recenter))))
  ;; window resize on C-h/j/k/l (nvim smart-splits); guarded + 5-col step so a
  ;; single window doesn't spam "No resizable window" errors
  (defun my/resize (fn n) (lambda () (interactive) (ignore-errors (funcall fn n))))
  (define-key evil-normal-state-map (kbd "C-h") (my/resize #'shrink-window-horizontally 5))
  (define-key evil-normal-state-map (kbd "C-l") (my/resize #'enlarge-window-horizontally 5))
  (define-key evil-normal-state-map (kbd "C-j") (my/resize #'shrink-window 3))
  (define-key evil-normal-state-map (kbd "C-k") (my/resize #'enlarge-window 3)))

(use-package evil-collection
  :after evil
  :config
  (evil-collection-init))

;; mini.surround -> add ea / delete ed / replace er (nvim mappings, kept 1:1).
;; evil-surround's own operators (ys/ds/cs) also stay live underneath; the
;; e-prefix bindings just mirror the nvim muscle-memory. ea is an operator:
;; `ea iw )` surrounds inner-word with parens; ed reads the pair to delete; er
;; reads old then new pair.
(use-package evil-surround
  :after evil
  :config
  (global-evil-surround-mode 1)
  (evil-define-key 'normal evil-surround-mode-map
    "ea" 'evil-surround-region   ; add (operator + motion + char)
    "ed" 'evil-surround-delete   ; delete pair
    "er" 'evil-surround-change)  ; replace pair
  (evil-define-key 'visual evil-surround-mode-map
    "ea" 'evil-surround-region)) ; add around selection

;; gcc / gc commenting (nvim <leader>x maps to gcc; leader binding in keys.el)
(use-package evil-commentary
  :after evil
  :config (evil-commentary-mode 1))

;; leap.nvim clever-s -> evil-snipe s/S, 2-char motion that repeats with s/S
(use-package evil-snipe
  :after evil
  :init (setq evil-snipe-scope 'visible
              evil-snipe-repeat-scope 'whole-visible
              evil-snipe-smart-case t)
  :config
  (evil-snipe-mode 1)
  (evil-snipe-override-mode 1))

;; vim-visual-multi -> evil-mc
(use-package evil-mc
  :after evil
  :config
  (global-evil-mc-mode 1)
  ;; free C-n/C-p/C-t for flymake/quickfix nav (matches nvim cnext); multicursor
  ;; driven by gr* map instead (grm all, grn/grp next/prev, grh here, grq quit)
  (dolist (k '("C-n" "C-p" "C-t" "M-n" "M-p"))
    (define-key evil-mc-key-map (kbd k) nil)))

;; mini.move -> move lines/regions. drag-stuff's keymap is empty until
;; drag-stuff-define-keys runs, so without it the global mode is a no-op.
(use-package drag-stuff
  :after evil
  :config
  (drag-stuff-define-keys)        ; M-<up/down/left/right> move line/region
  (drag-stuff-global-mode 1))

;; mini.align
(use-package evil-lion
  :after evil
  :config (evil-lion-mode 1))

;; evil-goggles (Doom): flash the region on yank/delete/change/paste. Extends
;; the nvim TextYankPost highlight-on-yank to all edit operators.
(use-package evil-goggles
  :after evil
  :config
  (setq evil-goggles-duration 0.1
        evil-goggles-pulse t)
  (evil-goggles-mode 1)
  (evil-goggles-use-diff-faces))

(provide 'evil-setup)
;;; evil-setup.el ends here
