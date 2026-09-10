;;; early-init.el --- pre-GUI setup -*- lexical-binding: t; -*-
;; Runs before the package system and the first frame. Keep it cheap.

;; Crank GC for startup; init.el restores sane values on emacs-startup-hook.
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

(setq package-enable-at-startup nil)

;; Font lives here so the first frame is drawn at the right size (no reflow
;; flicker). ui.el reuses these for the fixed/variable-pitch faces.
;; h16 matches nvim `set.guifont = "0xProto Nerd Font:h16"`.
(defvar my/font-family "0xProto Nerd Font")
(defvar my/font-size 16)

(setq default-frame-alist
      `((tool-bar-lines . 0)
        (menu-bar-lines . 0)
        (vertical-scroll-bars . nil)
        (horizontal-scroll-bars . nil)
        (internal-border-width . 8)
        (font . ,(format "%s-%d" my/font-family my/font-size))))
(setq tool-bar-mode nil
      menu-bar-mode nil
      scroll-bar-mode nil
      frame-inhibit-implied-resize t)

(setq inhibit-startup-screen t
      inhibit-startup-echo-area-message user-login-name
      initial-scratch-message nil
      native-comp-async-report-warnings-errors 'silent)

;; don't pop *Warnings* for benign byte/native-compile noise from packages
(setq warning-minimum-level :error
      warning-minimum-log-level :error
      byte-compile-warnings '(not docstrings free-vars unresolved noruntime
                                  lexical make-local obsolete))

(provide 'early-init)
;;; early-init.el ends here
