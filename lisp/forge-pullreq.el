;;; forge-pullreq.el --- Pullreq support          -*- lexical-binding: t -*-

;; Copyright (C) 2018-2021  Jonas Bernoulli

;; Author: Jonas Bernoulli <jonas@bernoul.li>
;; Maintainer: Jonas Bernoulli <jonas@bernoul.li>

;; Forge is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; Forge is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Forge.  If not, see http://www.gnu.org/licenses.

;;; Code:

(require 'forge)
(require 'forge-post)
(require 'forge-topic)

;;; Classes

(defclass forge-pullreq (forge-topic)
  ((closql-table         :initform pullreq)
   (closql-primary-key   :initform id)
   (closql-order-by      :initform [(desc number)])
   (closql-foreign-key   :initform repository)
   (closql-class-prefix  :initform "forge-")
   (id                   :initarg :id)
   (repository           :initarg :repository)
   (number               :initarg :number)
   (state                :initarg :state)
   (author               :initarg :author)
   (title                :initarg :title)
   (created              :initarg :created)
   (updated              :initarg :updated)
   (closed               :initarg :closed)
   (merged               :initarg :merged)
   (unread-p             :initarg :unread-p :initform nil)
   (locked-p             :initarg :locked-p)
   (editable-p           :initarg :editable-p)
   (cross-repo-p         :initarg :cross-repo-p)
   (base-ref             :initarg :base-ref)
   (base-repo            :initarg :base-repo)
   (head-ref             :initarg :head-ref)
   (head-user            :initarg :head-user)
   (head-repo            :initarg :head-repo)
   (milestone            :initarg :milestone)
   (body                 :initarg :body)
   (assignees            :closql-table (pullreq-assignee assignee))
   (project-cards) ; projectsCards
   (commits)
   (edits) ; userContentEdits
   (labels               :closql-table (pullreq-label label))
   (participants)
   (posts                :closql-class forge-pullreq-post)
   (reactions)
   (review-requests      :closql-table (pullreq-review-request assignee))
   (reviews)
   (timeline)
   (marks                :closql-table (pullreq-mark mark))
   (note                 :initarg :note :initform nil)
   (versions             :closql-class forge-pullreq-version)
   ;; We don't use these fields:
   ;; includesCreatedEdit (huh?),
   ;; lastEditedAt (same as updatedAt?),
   ;; publishedAt (same as createdAt?),
   ;; activeLockReason, additions, authorAssociation, (baseRefName), baseRefOid,
   ;; bodyHTML, bodyText, canBeRebased, changedFiles, closed, createdViaEmail,
   ;; databaseId, deletions, editor, (headRefName), headRefOid, mergeCommit,
   ;; mergeStateStatus, mergeable, merged, mergedBy, permalink,
   ;; potentialMergeCommit,, reactionGroups, resourcePath, revertResourcePath,
   ;; revertUrl, url, viewer{*}
   ))

(defclass forge-pullreq-post (forge-post)
  ((closql-table         :initform pullreq-post)
   (closql-primary-key   :initform id)
   (closql-order-by      :initform [(asc number)])
   (closql-foreign-key   :initform pullreq)
   (closql-class-prefix  :initform "forge-pullreq-")
   (id                   :initarg :id)
   (pullreq              :initarg :pullreq)
   (number               :initarg :number)
   (author               :initarg :author)
   (created              :initarg :created)
   (updated              :initarg :updated)
   (body                 :initarg :body)
   (edits)
   (reactions)
   (thread-id            :initarg :thread-id)
   (diff-p               :initarg :diff-p)
   (resolved-by          :initarg :resolved-by)
   (reply-to             :initarg :reply-to)
   (head-ref             :initarg :head-ref)
   (commit-ref           :initarg :commit-ref)
   (base-ref             :initarg :base-ref)
   (path                 :initarg :path)
   (old-line             :initarg :old-line)
   (new-line             :initarg :new-line)
   ;; We don't use these fields:
   ;; includesCreatedEdit (huh?),
   ;; lastEditedAt (same as updatedAt?),
   ;; publishedAt (same as createdAt?),
   ;; pullRequest (same as issue),
   ;; repository (use .pullreq.project),
   ;; authorAssociation, bodyHTML, bodyText, createdViaEmail,
   ;; editor, id, reactionGroups, resourcePath, url, viewer{*}
   ))

(defclass forge-pullreq-version (forge-object)
  ((closql-table         :initform pullreq-version)
   (closql-primary-key   :initform id)
   (closql-order-by      :initform [(desc id)])
   (closql-foreign-key   :initform pullreq)
   (closql-class-prefix  :initform "forge-pullreq-")
   (id                   :initarg :id)
   (pullreq              :initarg :pullreq)
   (number               :initarg :number)
   (head-ref             :initarg :head-ref)
   (base-ref             :initarg :base-ref)))

;;; Query

(cl-defmethod forge-get-repository ((post forge-pullreq-post))
  (forge-get-repository (forge-get-pullreq post)))

(cl-defmethod forge-get-topic ((post forge-pullreq-post))
  (forge-get-pullreq post))

(cl-defmethod forge-get-pullreq ((repo forge-repository) number)
  (closql-get (forge-db)
              (forge--object-id 'forge-pullreq repo number)
              'forge-pullreq))

(cl-defmethod forge-get-pullreq ((number integer))
  (when-let ((repo (forge-get-repository t)))
    (forge-get-pullreq repo number)))

(cl-defmethod forge-get-pullreq ((id string))
  (closql-get (forge-db) id 'forge-pullreq))

(cl-defmethod forge-get-pullreq ((post forge-pullreq-post))
  (closql-get (forge-db)
              (oref post pullreq)
              'forge-pullreq))

(cl-defmethod forge-ls-pullreqs ((repo forge-repository) &optional type)
  (forge-ls-topics repo 'forge-pullreq type))

;;; Utilities

(defun forge-read-pullreq (prompt &optional type)
  (when (eq type t)
    (setq type (if current-prefix-arg nil 'open)))
  (let* ((default (forge-current-pullreq))
         (repo    (forge-get-repository (or default t)))
         (format  (lambda (topic)
                    (format "%s  %s"
                            (oref topic number)
                            (oref topic title))))
         (choices (forge-ls-pullreqs repo type))
         (choice  (magit-completing-read
                   prompt
                   (mapcar format choices)
                   nil nil nil nil
                   (and default
                        (funcall format default)))))
    (and (string-match "\\`\\([0-9]+\\)" choice)
         (string-to-number (match-string 1 choice)))))

(defun forge--pullreq-branch-internal (pullreq)
  (let ((branch (oref pullreq head-ref)))
    ;; It is invalid for a branch name to begin with a colon, yet
    ;; that is what Gitlab uses when a pull-request's source branch
    ;; has been deleted.  On Github this is simply nil in the same
    ;; situation.
    (and branch (not (string-prefix-p ":" branch)) branch)))

(defun forge--pullreq-branch-active (pullreq)
  (let* ((number (number-to-string (oref pullreq number)))
         (branch-n (format "pr-%s" number))
         (branch (forge--pullreq-branch-internal pullreq)))
    (or (and (magit-branch-p branch)
             (equal (magit-get "branch" branch "pullRequest") number)
             branch)
        (and (magit-branch-p branch-n)
             (equal (magit-get "branch" branch-n "pullRequest") number)
             branch-n))))

(defun forge--pullreq-branch-select (pullreq)
  (let* ((number (oref pullreq number))
         (branch-n (format "pr-%s" number))
         (branch (or (forge--pullreq-branch-internal pullreq)
                     branch-n)))
    (when (member branch '("master" "next" "maint"))
      (setq branch branch-n))
    (when (magit-branch-p branch)
      (if (equal branch branch-n)
          (unless (y-or-n-p (format "Reset existing branch %S? " branch))
            (user-error "Abort"))
        (pcase (read-char-choice
                (format "A branch named %S already exists.

This could be because you checked out this pull-request before,
in which case resetting might be the appropriate thing to do.

Or the contributor worked directly on their version of a branch
that also exists on the upstream, in which case you probably
should not reset because you would end up resetting your version.

Or you are trying to checkout a pull-request that you created
yourself, in which case you probably should not reset either.

  [r]eset existing %S branch
  [c]reate new \"pr-%s\" branch instead
  [a]bort" branch branch number) '(?r ?c ?a))
          (?r)
          (?c (setq branch branch-n)
              (when (magit-branch-p branch)
                (error "Oh no!  %S already exists too" branch)))
          (?a (user-error "Abort"))))
      (message ""))
    branch))

(defun forge--pullreq-ref (pullreq)
  (let ((ref (format "refs/pullreqs/%s" (oref pullreq number))))
    (and (magit-rev-verify ref) ref)))

(defun forge--pullreq-range (pullreq &optional endpoints)
  (when-let ((head (forge--pullreq-ref pullreq)))
    (concat (forge--get-remote) "/" (oref pullreq base-ref)
            (if endpoints "..." "..")
            head)))

(cl-defmethod forge-get-url ((pullreq forge-pullreq))
  (forge--format pullreq 'pullreq-url-format))

;;; Sections

(defun forge-current-pullreq ()
  (or (forge-pullreq-at-point)
      (and (derived-mode-p 'forge-topic-mode)
           (forge-pullreq-p forge-buffer-topic)
           forge-buffer-topic)
      (and (derived-mode-p 'forge-topic-list-mode)
           (let ((topic (forge-get-topic (tabulated-list-get-id))))
             (and (forge-pullreq-p topic)
                  topic)))))

(defun forge-pullreq-at-point ()
  (or (magit-section-value-if 'pullreq)
      (when-let ((post (magit-section-value-if 'post)))
        (cond ((forge-pullreq-p post)
               post)
              ((forge-pullreq-post-p post)
               (forge-get-pullreq post))))))

(defvar forge-pullreqs-section-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap magit-browse-thing] 'forge-browse-pullreqs)
    (define-key map [remap magit-visit-thing]  'forge-list-pullreqs)
    (define-key map (kbd "C-c C-n")            'forge-create-pullreq)
    map))

(defvar forge-pullreq-section-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap magit-browse-thing] 'forge-browse-pullreq)
    (define-key map [remap magit-visit-thing]  'forge-visit-pullreq)
    map))

(defvar forge-pullreq-diff-section-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap magit-browse-thing] 'forge-browse-pullreq)
    (define-key map [remap magit-visit-thing]  'forge-show-pullreq-diff)
    map))

(defun forge-insert-pullreqs ()
  "Insert a list of mostly recent and/or open pull-requests.
Also see option `forge-topic-list-limit'."
  (when forge-display-in-status-buffer
    (when-let ((repo (forge-get-repository nil)))
      (unless (oref repo sparse-p)
        (forge-insert-topics "Pull requests"
                             (forge-ls-recent-topics repo 'pullreq)
                             (forge--topic-type-prefix repo 'pullreq))))))

(defun forge--insert-pullreq-commits (pullreq)
  (when-let ((range (forge--pullreq-range pullreq)))
    (magit-insert-section-body
      (cl-letf (((symbol-function #'magit-cancel-section) (lambda ())))
        (magit-insert-log range magit-buffer-log-args)
        (magit-make-margin-overlay nil t)))))

(defun forge--filter-diff-posts-by-commit (posts commit)
  (cl-remove-if-not (lambda (post)
                      (with-slots (diff-p commit-ref) post
                        (and diff-p (string= commit-ref commit))))
                    posts))

(defun forge--filter-diff-posts-by-version (posts version)
  (let ((head (oref version head-ref))
        (base (oref version base-ref)))
    (cl-remove-if-not (lambda (post)
                        (with-slots (diff-p head-ref base-ref) post
                          (and diff-p
                               (string= head-ref head)
                               (string= base-ref base))))
                      posts)))

(defun forge-show-pullreq-diff ()
  (interactive)
  (pcase-let ((`(,version ,commit) (magit-section-value-if 'pullreq-diff)))
    (let ((topic forge-buffer-topic)
          (pullreq-buffer (current-buffer))
          (buf (if commit
                   (magit-revision-setup-buffer
                    commit (magit-show-commit--arguments) nil)
                 (with-slots (base-ref head-ref) version
                   (magit-diff-setup-buffer
                    (format "%s..%s" base-ref head-ref)
                    nil (magit-diff-arguments) nil)))))
      (with-current-buffer buf
        (setq forge--pullreq-version version)
        (setq forge--pullreq-commit commit)
        (setq forge--pullreq-buffer pullreq-buffer)
        (setq forge-buffer-topic topic)
        (add-hook 'magit-unwind-refresh-hook 'forge--pullreq-diff-refresh nil t)
        (magit-refresh)))))

(defun forge--insert-pullreq-diff-commits (version diff-commits diff-posts)
  (dolist (commit diff-commits)
    (pcase-let ((`(,id ,abbrev-id ,subject) commit))
      (magit-insert-section (pullreq-diff (list version id))
        (let ((posts (forge--filter-diff-posts-by-commit diff-posts id)))
          (insert (concat (propertize abbrev-id 'face 'magit-hash)
                          (format " %-50s " subject)
                          (when posts
                            (propertize (format "(%d comments)" (length posts))
                                        'face 'magit-section-heading)))
                "\n")))))
    (insert "\n"))

(defun forge--insert-pullreq-versions (pullreq)
  (let ((posts (oref pullreq posts))
        (versions (reverse (oref pullreq versions)))
        (count 0))
    (dolist (version versions)
      (with-slots (base-ref head-ref) version
        (cl-incf count)
        (let* ((diff-commits (magit-git-lines "log" "--format=(\"%H\" \"%h\" \"%s\")"
                                              (format "%s..%s" base-ref head-ref)))
               (diff-posts (forge--filter-diff-posts-by-version posts version))
               (comments-nbr (format "(%d comments) " (length diff-posts)))
               (hide (not (eq count (length versions)))))
          ;; all the version section are collapsed except for the latest version
          (magit-insert-section (pullreq-diff (list version) hide)
            (magit-insert-heading (concat (if (= count (length versions))
                                              "Latest Version:  "
                                            (format "Version %d:  " count))
                                          (when diff-posts comments-nbr)))
            (forge--insert-pullreq-diff-commits version
                                                (mapcar #'read diff-commits)
                                                diff-posts)))))))

(cl-defmethod forge--insert-topic-contents :after ((pullreq forge-pullreq)
                                                   _width _prefix)
  (unless (oref pullreq merged)
    (magit-insert-heading)
    (forge--insert-pullreq-commits pullreq)))

(cl-defmethod forge--format-topic-id ((pullreq forge-pullreq) &optional prefix)
  (propertize (format "%s%s"
                      (or prefix (forge--topic-type-prefix pullreq))
                      (oref pullreq number))
              'font-lock-face (if (oref pullreq merged)
                                  'forge-topic-merged
                                'forge-topic-unmerged)))

(cl-defmethod forge--topic-type-prefix ((pullreq forge-pullreq))
  (if (forge--childp (forge-get-repository pullreq) 'forge-gitlab-repository)
      "!"
    "#"))

(defun forge-insert-assigned-pullreqs ()
  "Insert a list of open pull-requests that are assigned to you."
  (when-let ((repo (forge-get-repository nil)))
    (unless (oref repo sparse-p)
      (forge-insert-topics "Assigned pull requests"
                           (forge--ls-assigned-pullreqs repo)
                           (forge--topic-type-prefix repo 'pullreq)))))

(defun forge--ls-assigned-pullreqs (repo)
  (mapcar (lambda (row)
            (closql--remake-instance 'forge-pullreq (forge-db) row))
          (forge-sql
           [:select $i1 :from pullreq
            :join pullreq_assignee :on (= pullreq_assignee:pullreq pullreq:id)
            :join assignee         :on (= pullreq_assignee:id      assignee:id)
            :where (and (= pullreq:repository $s2)
                        (= assignee:login     $s3)
                        (isnull pullreq:closed))
            :order-by [(desc updated)]]
           (vconcat (closql--table-columns (forge-db) 'pullreq t))
           (oref repo id)
           (ghub--username repo))))

(defun forge-insert-requested-reviews ()
  "Insert a list of pull-requests that are awaiting your review."
  (when-let ((repo (forge-get-repository nil)))
    (unless (oref repo sparse-p)
      (forge-insert-topics "Pull requests awaiting review"
                           (forge--ls-requested-reviews repo)
                           (forge--topic-type-prefix repo 'pullreq)))))

(defun forge--ls-requested-reviews (repo)
  (mapcar
   (lambda (row)
     (closql--remake-instance 'forge-pullreq (forge-db) row))
   (forge-sql
    [:select $i1 :from pullreq
     :join pullreq_review_request :on (= pullreq_review_request:pullreq pullreq:id)
     :join assignee               :on (= pullreq_review_request:id      assignee:id)
     :where (and (= pullreq:repository $s2)
                 (= assignee:login     $s3)
                 (isnull pullreq:closed))
     :order-by [(desc updated)]]
    (vconcat (closql--table-columns (forge-db) 'pullreq t))
    (oref repo id)
    (ghub--username repo))))

(defun forge-insert-authored-pullreqs ()
  "Insert a list of open pullreqs that are authored to you."
  (when-let ((repo (forge-get-repository nil)))
    (unless (oref repo sparse-p)
      (forge-insert-topics "Authored pullreqs"
                           (forge--ls-authored-pullreqs repo)
                           (forge--topic-type-prefix repo 'pullreq)))))

(defun forge--ls-authored-pullreqs (repo)
  (mapcar (lambda (row)
            (closql--remake-instance 'forge-pullreq (forge-db) row))
          (forge-sql
           [:select $i1 :from [pullreq]
            :where (and (= pullreq:repository $s2)
                        (= pullreq:author     $s3)
                        (isnull pullreq:closed))
            :order-by [(desc updated)]]
           (vconcat (closql--table-columns (forge-db) 'pullreq t))
           (oref repo id)
           (ghub--username repo))))

;;; _
(provide 'forge-pullreq)
;;; forge-pullreq.el ends here
