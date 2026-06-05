;;; init.el --- vim-first, from-scratch Emacs -*- lexical-binding: t; -*-
;; Feature modules live next to this file and load in the order listed below.
;; Add one: drop the file, add it to the list.

(require 'package)
(setq package-archives
      '(("gnu"    . "https://elpa.gnu.org/packages/")
        ("nongnu" . "https://elpa.nongnu.org/nongnu/")
        ("melpa"  . "https://melpa.org/packages/")))
(package-initialize)
(unless package-archive-contents
  (package-refresh-contents))

(require 'use-package)
(setq use-package-always-ensure t)

;; Modules, in load order.
(dolist (m '("core"
             "ui"
             "evil-setup"
             "completion"
             "files-setup"
             "git-setup"
             "lang"
             "tools"
             "keys"))
  (load (expand-file-name m user-emacs-directory) nil t))

;; Machine-written `customize' settings, kept out of the modules.
(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file nil t))

;; early-init.el cranked GC up for a fast startup; restore sane runtime values.
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 64 1024 1024)
                  gc-cons-percentage 0.1)))

