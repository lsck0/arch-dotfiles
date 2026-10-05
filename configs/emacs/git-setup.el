;;; git-setup.el --- git -*- lexical-binding: t; -*-

(use-package magit
  :commands (magit-status magit-dispatch magit-file-dispatch)
  :config
  (setq magit-display-buffer-function
        #'magit-display-buffer-same-window-except-diff-v1
        magit-diff-refine-hunk 'all))

(use-package diff-hl
  :hook ((dired-mode         . diff-hl-dired-mode)
         (magit-pre-refresh  . diff-hl-magit-pre-refresh)
         (magit-post-refresh . diff-hl-magit-post-refresh))
  :config
  (global-diff-hl-mode 1)
  (diff-hl-flydiff-mode 1))               ; update without saving

(defun my/smerge-maybe-enable ()
  "Turn on `smerge-mode' if the buffer contains conflict markers."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^<<<<<<< " nil t)
      (smerge-mode 1))))

(add-hook 'find-file-hook #'my/smerge-maybe-enable)

;;;; worktrees (git-worktree.nvim) ----------------------------------------------

(defun my/git-lines (&rest args)
  "Output lines of git ARGS in `default-directory'; a failure is a `user-error' carrying git's message."
  (with-temp-buffer
    (unless (eq 0 (apply #'process-file "git" nil t nil args))
      (user-error "git %s: %s" (car args) (string-trim (buffer-string))))
    (split-string (buffer-string) "\n" t)))

(defun my/worktrees ()
  "Worktrees of the current repo as plists (:path :branch :bare), the main one or the bare repo first."
  (let (out)
    (dolist (line (my/git-lines "worktree" "list" "--porcelain"))
      (cond ((string-prefix-p "worktree " line)
             (push (list :path (file-name-as-directory (substring line 9))) out))
            ((string-prefix-p "branch refs/heads/" line)
             (setcar out (plist-put (car out) :branch (substring line 18))))
            ((equal line "bare")
             (setcar out (plist-put (car out) :bare t)))))
    (nreverse out)))

(defun my/worktree-dir (worktrees slug)
  "Where the worktree SLUG goes: the directory most linked WORKTREES share (ties: the shallower one), else
<repo>/branches/ beside a .bare layout, inside a plain bare repo, or ~/.worktrees/<repo>/ as scripts/wtree.sh does.
`git worktree add <path>' resolves relative to the current checkout, which nested ~/projects/probe/master/uwu."
  (let ((count (make-hash-table :test #'equal))
        best)
    (dolist (wt (cdr worktrees))
      (let ((parent (file-name-directory (directory-file-name (plist-get wt :path)))))
        (puthash parent (1+ (gethash parent count 0)) count)
        (when (or (not best)
                  (> (gethash parent count) (gethash best count))
                  (and (= (gethash parent count) (gethash best count)) (< (length parent) (length best))))
          (setq best parent))))
    (let* ((main (directory-file-name (plist-get (car worktrees) :path)))
           (name (file-name-nondirectory main)))
      (expand-file-name slug (cond (best)
                                   ((not (plist-get (car worktrees) :bare))
                                    (expand-file-name name "~/.worktrees/"))
                                   ((equal name ".bare") (expand-file-name "branches" (file-name-directory main)))
                                   (t main))))))

(defun my/worktree-switch ()
  "nvim SPC g f: pick a worktree of this repo and move there."
  (interactive)
  (let* ((items (mapcar (lambda (wt)
                          (cons (format "%s  %s" (or (plist-get wt :branch) "detached")
                                        (abbreviate-file-name (plist-get wt :path)))
                                (plist-get wt :path)))
                        (seq-remove (lambda (wt) (plist-get wt :bare)) (my/worktrees))))
         (pick (completing-read "Worktrees: " items nil t)))
    (my/project-open (cdr (assoc pick items)))))

(defun my/worktree--branches ()
  "Local and origin branch names, deduplicated; origin/HEAD left out."
  (delete-dups
   (delete "HEAD"
           (mapcar (lambda (ref) (replace-regexp-in-string "\\`refs/\\(heads\\|remotes/origin\\)/" "" ref))
                   (my/git-lines "for-each-ref" "--format=%(refname)" "refs/heads" "refs/remotes/origin")))))

(defun my/worktree-create (branch)
  "nvim SPC g c / :Worktree: switch to BRANCH's worktree, creating it (and the branch, tracking origin) first."
  (interactive (list (string-trim (completing-read "Worktree branch (new name creates it): "
                                                   (my/worktree--branches)))))
  (when (string-empty-p branch) (user-error "No branch given"))
  (let* ((worktrees (my/worktrees))
         (existing (seq-find (lambda (wt) (equal (plist-get wt :branch) branch)) worktrees)))
    (if existing
        (my/project-open (plist-get existing :path))
      ;; slashes flattened like clones-sdd-repos.sh's slug_of, so feat/x is one directory, not two
      (let ((dir (my/worktree-dir worktrees (replace-regexp-in-string "/" "-" branch))))
        (cond ((ignore-errors (my/git-lines "show-ref" "--verify" "--quiet" (concat "refs/heads/" branch)) t)
               (my/git-lines "worktree" "add" dir branch))
              ((ignore-errors (my/git-lines "show-ref" "--verify" "--quiet" (concat "refs/remotes/origin/" branch)) t)
               (my/git-lines "worktree" "add" "--track" "-b" branch dir (concat "origin/" branch)))
              (t (my/git-lines "worktree" "add" "-b" branch dir)))
        (message "worktree: %s" (abbreviate-file-name dir))
        (my/project-open (file-name-as-directory dir))))))

;;;; github (octo.nvim) -----------------------------------------------------------

;; octo lists issues and PRs inside nvim; here the same keys open the GitHub pages, gh resolves the repo

(defun my/gh-repo ()
  "(URL . OWNER/NAME) of the current repo on GitHub."
  (let ((out (split-string (shell-command-to-string
                            "gh repo view --json url,nameWithOwner --jq '.url + \" \" + .nameWithOwner'"))))
    (unless (and (= (length out) 2) (string-prefix-p "https://" (car out)))
      (user-error "gh: %s" (string-join out " ")))
    (cons (car out) (cadr out))))

(defun my/gh-org ()
  "Org from the private per-repo identity (.identity/env), never hardcoded."
  (let ((org (getenv "OCTO_DEFAULT_ORG")))
    (if (and org (not (string-empty-p org))) org (user-error "set OCTO_DEFAULT_ORG in .identity/env"))))

(defun my/gh-search (query &optional type)
  "Open a GitHub search for QUERY, restricted to TYPE (issues, pullrequests, repositories)."
  (browse-url (format "https://github.com/search?q=%s%s" (url-hexify-string query)
                      (if type (concat "&type=" type) ""))))

(dolist (page '("issues" "pulls" "discussions"))
  (defalias (intern (format "my/gh-%s" page))
    (lambda () (interactive) (browse-url (concat (car (my/gh-repo)) "/" page)))
    (format "nvim Octo %s list: the repo's %s page." page page)))

(defun my/gh-notifications ()
  "nvim Octo notification list."
  (interactive)
  (browse-url "https://github.com/notifications"))

(defun my/gh-search-repo (query)
  "nvim SPC o s: search QUERY in the current repo."
  (interactive "sSearch GitHub: ")
  (my/gh-search (format "repo:%s %s" (cdr (my/gh-repo)) query)))

(defun my/gh-org-repos ()
  "nvim SPC o R: the org's repositories."
  (interactive)
  (browse-url (format "https://github.com/orgs/%s/repositories" (my/gh-org))))

(defun my/gh-org-issues ()
  "nvim SPC o I: open issues across the org."
  (interactive)
  (my/gh-search (format "org:%s is:issue is:open sort:updated-desc" (my/gh-org)) "issues"))

(defun my/gh-org-pulls ()
  "nvim SPC o P: open PRs across the org."
  (interactive)
  (my/gh-search (format "org:%s is:pr is:open sort:updated-desc" (my/gh-org)) "pullrequests"))

(defun my/gh-org-search (query)
  "nvim SPC o O: search the org, prefilled with org:<org>."
  (interactive (list (read-string "Search org: " (format "org:%s " (my/gh-org)))))
  (my/gh-search query "repositories"))

(provide 'git-setup)
;;; git-setup.el ends here
