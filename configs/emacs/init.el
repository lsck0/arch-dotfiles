;;; init.el --- vim-first Emacs, from scratch -*- lexical-binding: t; -*-
;;
;; A deliberately small mirror of the nvim + tmux setup, kept working as a
;; fallback for when that one breaks. Scope: evil, file browser, top and bottom
;; bar, treesitter, LSP, terminal, compile, fuzzy finding, git. Nothing else.
;;
;; Feature modules live next to this file and load in the order below.
;; Add one: drop the file in, add it to the list.

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

;; Machine-written `customize' state (gitignored). This has to happen *before*
;; the modules load: installing a package writes `package-selected-packages',
;; and while `custom-file' is still nil that write lands in this file instead.
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
             "tools"         ; terminal, compile, windows
             "keys"))        ; all keybindings          (nvim mappings.lua)
  (load (expand-file-name m user-emacs-directory) nil t))

;; early-init.el cranked GC up for a fast startup; restore sane runtime values.
(add-hook 'emacs-startup-hook
          (lambda ()
            (setq gc-cons-threshold (* 64 1024 1024)
                  gc-cons-percentage 0.1)))

;;; init.el ends here
