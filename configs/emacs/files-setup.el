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

  ;; not `dirvish-side-follow-mode': it runs from `buffer-list-update-hook', which fires for any buffer that
  ;; merely becomes current -- a background process buffer, a `with-current-buffer' inside eglot or diff-hl --
  ;; and then re-roots the sidebar at that buffer's `default-directory'. Hence the jumping. Drive the follow
  ;; off the selected window instead, after a short debounce, so the tree only ever expands to the file
  ;; actually on screen, and re-roots only on a real project switch.
  (defvar my/dirvish-side-follow-timer nil)

  (defun my/dirvish-side-follow--now ()
    (setq my/dirvish-side-follow-timer nil)
    (when-let* ((win (ignore-errors (dirvish-side--session-visible-p)))
                (sel (selected-window))
                ((not (eq sel win)))
                ((not (window-minibuffer-p sel)))
                ((not (active-minibuffer-window)))
                (file (buffer-local-value 'buffer-file-name (window-buffer sel)))
                ((not (string-suffix-p "COMMIT_EDITMSG" file)))
                ((not (equal file (with-selected-window win (dirvish-prop :index))))))
      (let ((root (with-selected-window win (expand-file-name default-directory)))
            ;; a file outside the tree re-roots at its project, never at its own directory
            (project (with-current-buffer (window-buffer sel)
                       (or (dirvish--vc-root-dir) default-directory))))
        (with-selected-window win
          (let (buffer-list-update-hook window-buffer-change-functions)
            (unless (string-prefix-p root (expand-file-name file))
              (dirvish--find-entry 'find-alternate-file project)))
          (dirvish-winbuf-change-h win)
          (unwind-protect
              (if dirvish-side-auto-expand
                  (dirvish-subtree-expand-to file)
                (dired-goto-file file))
            (dirvish--redisplay))))))

  (defun my/dirvish-side-follow (&rest _)
    "Schedule a sidebar follow; coalesces the burst of hooks a window change fires."
    (unless my/dirvish-side-follow-timer
      (setq my/dirvish-side-follow-timer
            (run-with-idle-timer 0.1 nil #'my/dirvish-side-follow--now))))

  (remove-hook 'buffer-list-update-hook #'dirvish-side--auto-jump)
  (add-hook 'window-buffer-change-functions #'my/dirvish-side-follow)
  (add-hook 'window-selection-change-functions #'my/dirvish-side-follow)

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
