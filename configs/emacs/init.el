;;; init.el --- vim-first Emacs, from scratch -*- lexical-binding: t; -*-

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

(setq custom-file (expand-file-name "custom.el" user-emacs-directory))
(when (file-exists-p custom-file)
  (load custom-file nil t))

;; Modules, in load order. keys.el is last: it binds what the others define.
(dolist (m '("core"          ; editor defaults          (nvim options.lua)
             "ui"            ; theme, top/bottom bar
             "evil-setup"    ; vim emulation
             "completion"    ; fuzzy finding + completion
             "files-setup"   ; file browser
             "git-setup"     ; magit, diff markers
             "lang"          ; treesitter, LSP, formatting
             "latex"         ; AUCTeX + reftex + zathura
             "tools"         ; terminal, compile, windows
             "keys"))        ; all keybindings          (nvim mappings.lua)
  (load (expand-file-name m user-emacs-directory) nil t))

;; early-init.el cranked GC up for a fast startup; restore sane runtime values.
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 64 1024 1024)
                  gc-cons-percentage 0.1)))

;;; init.el ends here
