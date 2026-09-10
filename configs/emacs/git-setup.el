;;; git-setup.el --- git -*- lexical-binding: t; -*-
;; magit = fugitive + lazygit (tmux C-q g).  diff-hl = gitsigns.

;; transient is not declared here: Emacs 31 bundles a version magit accepts,
;; and package.el pulls a newer one as a magit dependency if that ever changes.
(use-package magit
  :commands (magit-status magit-dispatch magit-file-dispatch)
  :config
  (setq magit-display-buffer-function
        #'magit-display-buffer-same-window-except-diff-v1
        magit-diff-refine-hunk 'all))

;; gitsigns -> live diff markers in the fringe
(use-package diff-hl
  :hook ((dired-mode         . diff-hl-dired-mode)
         (magit-pre-refresh  . diff-hl-magit-pre-refresh)
         (magit-post-refresh . diff-hl-magit-post-refresh))
  :config
  (global-diff-hl-mode 1)
  (diff-hl-flydiff-mode 1))               ; update without saving

;; git-conflict.nvim -> built-in smerge, auto-enabled when markers are present
(defun my/smerge-maybe-enable ()
  "Turn on `smerge-mode' if the buffer contains conflict markers."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^<<<<<<< " nil t)
      (smerge-mode 1))))

(add-hook 'find-file-hook #'my/smerge-maybe-enable)

(provide 'git-setup)
;;; git-setup.el ends here
