;;; git-setup.el -*- lexical-binding: t; -*-
;; magit (the "magick"), gitsigns, conflicts, time machine.

(use-package transient)

;; fugitive/magit
(use-package magit
  :commands (magit-status magit-dispatch)
  :config
  (setq magit-display-buffer-function #'magit-display-buffer-same-window-except-diff-v1))

;; forge: GitHub/GitLab issues + PRs inside magit. `@` in magit-status, or
;; M-x forge-pull. Needs a token in ~/.authinfo(.gpg) (see forge docs).
(use-package forge :after magit)

;; gitsigns -> diff-hl in the fringe, live
(use-package diff-hl
  :hook ((prog-mode . diff-hl-mode)
         (dired-mode . diff-hl-dired-mode)
         (magit-pre-refresh . diff-hl-magit-pre-refresh)
         (magit-post-refresh . diff-hl-magit-post-refresh))
  :config
  (global-diff-hl-mode 1)
  (diff-hl-flydiff-mode 1))

;; git-conflict.nvim
(use-package smerge-mode
  :ensure nil
  :hook (find-file . (lambda ()
                       (save-excursion
                         (goto-char (point-min))
                         (when (re-search-forward "^<<<<<<< " nil t)
                           (smerge-mode 1))))))

(use-package git-timemachine
  :commands git-timemachine)

(use-package git-modes)

(provide 'git-setup)
;;; git-setup.el ends here
