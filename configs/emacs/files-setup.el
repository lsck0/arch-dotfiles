;;; files-setup.el --- file browser -*- lexical-binding: t; -*-

(use-package dirvish
  :init (dirvish-override-dired-mode 1)
  :config
  (setq dirvish-attributes '(nerd-icons file-size collapse subtree-state vc-state git-msg)
        dirvish-use-header-line 'global
        dirvish-mode-line-format '(:left (sort symlink) :right (omit yank index))
        dirvish-side-width 30
        dirvish-side-window-parameters '((no-delete-other-windows . t))
        dirvish-quick-access-entries
        '(("h" "~/"                              "home")
          ("p" "~/projects/"                     "projects")
          ("c" "~/projects/arch-dotfiles/configs/" "configs")))

  ;; dired defaults, shared by dirvish
  (setq dired-listing-switches "-l --almost-all --human-readable --group-directories-first"
        dired-dwim-target t                        ; other window = default target
        dired-recursive-copies 'always
        dired-recursive-deletes 'top
        dired-kill-when-opening-new-dired-buffer t  ; no buffer pileup
        delete-by-moving-to-trash t)

  ;; the sidebar tracks the buffer you are editing (neo-tree follow)
  (dirvish-side-follow-mode 1)

  ; ; Make the sidebar resizable.
  (defun my/dirvish-side-resizable ()
    (when-let* ((dv (dirvish-curr))
                ((eq (dv-type dv) 'side)))
      (setf (dv-size-fixed dv) nil)
      (setq-local window-size-fixed nil)))
  (add-hook 'dirvish-setup-hook #'my/dirvish-side-resizable))

(provide 'files-setup)
;;; files-setup.el ends here
