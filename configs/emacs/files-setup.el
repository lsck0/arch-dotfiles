;;; files-setup.el -*- lexical-binding: t; -*-
;; dired (dirvish, the oil.nvim feel) + treemacs file tree (neo-tree).

;; oil.nvim -> dirvish on top of dired
(use-package dirvish
  :init (dirvish-override-dired-mode 1)
  :config
  (setq dirvish-attributes '(nerd-icons file-size collapse subtree-state vc-state git-msg)
        dirvish-use-header-line 'global
        dirvish-mode-line-format '(:left (sort symlink) :right (omit yank index))
        dired-listing-switches "-l --almost-all --human-readable --group-directories-first")
  ;; vim-ish movement inside dired
  (with-eval-after-load 'evil
    (evil-define-key 'normal dired-mode-map
      (kbd "h") 'dired-up-directory
      (kbd "l") 'dired-find-file
      (kbd "q") 'quit-window)))

;; neo-tree -> treemacs
(use-package treemacs
  :defer t
  :config
  (setq treemacs-width 27
        treemacs-follow-after-init t
        treemacs-is-never-other-window t
        treemacs-no-png-images nil)
  (treemacs-follow-mode 1)
  (treemacs-filewatch-mode 1)
  (treemacs-git-mode 'deferred)
  (treemacs-hide-gitignored-files-mode 1))

(use-package treemacs-evil
  :after (treemacs evil))

(use-package treemacs-nerd-icons
  :after treemacs
  :config (treemacs-load-theme "nerd-icons"))

(use-package treemacs-magit
  :after (treemacs magit))

(provide 'files-setup)
;;; files-setup.el ends here
