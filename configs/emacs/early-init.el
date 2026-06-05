;;; early-init.el -*- lexical-binding: t; -*-

(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

(setq package-enable-at-startup nil)

(setq default-frame-alist
      '((tool-bar-lines . 0)
        (menu-bar-lines . 0)
        (vertical-scroll-bars . nil)
        (horizontal-scroll-bars . nil)
        (internal-border-width . 8)
        (font . "0xProto Nerd Font-22")))
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
