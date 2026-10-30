;;; -*- lexical-binding: t; -*-
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

(setq package-enable-at-startup nil)

(defvar my/font-family "Kode Mono")
(defvar my/font-size 13)
(load (expand-file-name "wal/emacs-font" (or (getenv "XDG_CACHE_HOME") "~/.cache")) t t)

(setq default-frame-alist
      `((tool-bar-lines . 0)
        (menu-bar-lines . 0)
        (vertical-scroll-bars . nil)
        (horizontal-scroll-bars . nil)
        (internal-border-width . 8)
        (font . ,(format "%s-%d" my/font-family my/font-size))))
(load (expand-file-name "wal/emacs-frame" (or (getenv "XDG_CACHE_HOME") "~/.cache")) t t)
(setq tool-bar-mode nil
      menu-bar-mode nil
      scroll-bar-mode nil
      frame-inhibit-implied-resize t)

(setq inhibit-startup-screen t
      inhibit-startup-echo-area-message user-login-name
      initial-scratch-message nil
      native-comp-async-report-warnings-errors 'silent)

(setq warning-minimum-level :error
      warning-minimum-log-level :error
      byte-compile-warnings '(not docstrings free-vars unresolved noruntime
                                  make-local obsolete))

(provide 'early-init)
