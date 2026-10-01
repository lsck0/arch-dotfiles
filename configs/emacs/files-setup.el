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

  ;; -v: version sort puts dotfiles first and file2 before file10; it compares bytes, so capitals sort before lowercase
  (setq dired-listing-switches "-l --almost-all --human-readable --group-directories-first -v"
        dired-dwim-target t                         ; other window = default target
        dired-recursive-copies 'always
        dired-recursive-deletes 'top
        dired-kill-when-opening-new-dired-buffer t  ; no buffer pileup
        delete-by-moving-to-trash t)

  (dirvish-side-follow-mode 1)

  (defun my/dirvish-side-resizable ()
    (when-let* ((dv (dirvish-curr))
                ((eq (dv-type dv) 'side)))
      ;; :config is macroexpanded before dirvish loads, so nothing here may need the struct at
      ;; expansion time: `(setf (dv-size-fixed dv) ...)' becomes a call to the void
      ;; `(setf dv-size-fixed)', and `cl-struct-slot-value' inlines `(cl-typep dv 'dirvish)',
      ;; which falls back to calling the `dirvish' command on DV. Resolve the slot at runtime.
      (setf (aref dv (cl-struct-slot-offset 'dirvish 'size-fixed)) nil)
      (setq-local window-size-fixed nil)))
  (add-hook 'dirvish-setup-hook #'my/dirvish-side-resizable))

;; sidebar at startup, focus stays in the main window
(add-hook 'emacs-startup-hook
          (lambda ()
            (when (display-graphic-p)
              (save-selected-window (dirvish-side)))))

(provide 'files-setup)
;;; files-setup.el ends here
