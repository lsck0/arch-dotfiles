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

  (setq dired-listing-switches "-l --almost-all --human-readable --group-directories-first"
        dired-dwim-target t                         ; other window = default target
        dired-recursive-copies 'always
        dired-recursive-deletes 'top
        dired-kill-when-opening-new-dired-buffer t  ; no buffer pileup
        delete-by-moving-to-trash t)

  (dirvish-side-follow-mode 1)

  (defun my/dirvish-side-resizable ()
    (when-let* ((dv (dirvish-curr))
                ((eq (dv-type dv) 'side)))
      ;; not (setf (dv-size-fixed dv) ...): :config is expanded before dirvish loads, when that
      ;; accessor's setter is still unknown and becomes a call to the void `(setf dv-size-fixed)'
      (setf (cl-struct-slot-value 'dirvish 'size-fixed dv) nil)
      (setq-local window-size-fixed nil)))
  (add-hook 'dirvish-setup-hook #'my/dirvish-side-resizable))

;; sidebar at startup, focus stays in the main window
(add-hook 'emacs-startup-hook
          (lambda ()
            (when (display-graphic-p)
              (save-selected-window (dirvish-side)))))

(provide 'files-setup)
;;; files-setup.el ends here
