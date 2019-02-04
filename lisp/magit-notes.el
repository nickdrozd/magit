;;; magit-notes.el --- notes support  -*- lexical-binding: t -*-

;; Copyright (C) 2010-2019  The Magit Project Contributors
;;
;; You should have received a copy of the AUTHORS.md file which
;; lists all contributors.  If not, see http://magit.vc/authors.

;; Author: Jonas Bernoulli <jonas@bernoul.li>
;; Maintainer: Jonas Bernoulli <jonas@bernoul.li>

;; Magit is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; Magit is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Magit.  If not, see http://www.gnu.org/licenses.

;;; Commentary:

;; This library implements support for `git-notes'.

;;; Code:

(require 'magit)

;;; Commands

;;;###autoload (autoload 'magit-notes "magit" nil t)
(define-transient-command magit-notes ()
  "Edit notes attached to commits."
  :man-page "git-notes"
  ["Configure local settings"
   ("c" magit-core.notesRef)
   ("d" magit-notes.displayRef)]
  ["Configure global settings"
   ("C" magit-global-core.notesRef)
   ("D" magit-global-notes.displayRef)]
  ["Arguments for prune"
   :if-not magit-notes-merging-p
   ("-n" "Dry run" ("-n" "--dry-run"))]
  ["Arguments for edit and remove"
   :if-not magit-notes-merging-p
   (magit-notes:--ref)]
  ["Arguments for merge"
   :if-not magit-notes-merging-p
   (magit-notes:--strategy)]
  ["Actions"
   :if-not magit-notes-merging-p
   ("T" "Edit"         magit-notes-edit)
   ("r" "Remove"       magit-notes-remove)
   ("m" "Merge"        magit-notes-merge)
   ("p" "Prune"        magit-notes-prune)]
  ["Actions"
   :if magit-notes-merging-p
   ("c" "Commit merge" magit-notes-merge-commit)
   ("a" "Abort merge"  magit-notes-merge-abort)])

(defun magit-notes-merging-p ()
  (let ((dir (magit-git-dir "NOTES_MERGE_WORKTREE")))
    (and (file-directory-p dir)
         (directory-files dir nil "^[^.]"))))

(define-infix-argument magit-core.notesRef ()
  :class 'magit--git-variable
  :variable "core.notesRef"
  :reader 'magit-notes-read-ref
  :prompt "Set local core.notesRef")

(define-infix-argument magit-notes.displayRef ()
  :class 'magit--git-variable
  :variable "notes.displayRef"
  :multi-value t
  :reader 'magit-notes-read-refs
  :prompt "Set local notes.displayRef")

(define-infix-argument magit-global-core.notesRef ()
  :class 'magit--git-variable
  :variable "core.notesRef"
  :reader 'magit-notes-read-ref
  :prompt "Set global core.notesRef")

(define-infix-argument magit-global-notes.displayRef ()
  :class 'magit--git-variable
  :variable "notes.displayRef"
  :multi-value t
  :reader 'magit-notes-read-refs
  :prompt "Set global notes.displayRef")

(define-infix-argument magit-notes:--ref ()
  :description "Merge strategy"
  :class 'transient-option
  :key "=r"
  :argument "--ref="
  :reader 'magit-notes-read-ref)

(define-infix-argument magit-notes:--strategy ()
  :description "Merge strategy"
  :class 'transient-option
  :key "=s"
  :shortarg "-s"
  :argument "--strategy="
  :choices '("manual" "ours" "theirs" "union" "cat_sort_uniq"))

(defun magit-notes-edit (commit &optional ref)
  "Edit the note attached to COMMIT.
REF is the notes ref used to store the notes.

Interactively or when optional REF is nil use the value of Git
variable `core.notesRef' or \"refs/notes/commits\" if that is
undefined."
  (interactive (magit-notes-read-args "Edit notes"))
  (magit-run-git-with-editor "notes" (and ref (concat "--ref=" ref))
                             "edit" commit))

(defun magit-notes-remove (commit &optional ref)
  "Remove the note attached to COMMIT.
REF is the notes ref from which the note is removed.

Interactively or when optional REF is nil use the value of Git
variable `core.notesRef' or \"refs/notes/commits\" if that is
undefined."
  (interactive (magit-notes-read-args "Remove notes"))
  (magit-run-git-with-editor "notes" (and ref (concat "--ref=" ref))
                             "remove" commit))

(defun magit-notes-merge (ref)
  "Merge the notes ref REF into the current notes ref.

The current notes ref is the value of Git variable
`core.notesRef' or \"refs/notes/commits\" if that is undefined.

When there are conflicts, then they have to be resolved in the
temporary worktree \".git/NOTES_MERGE_WORKTREE\".  When
done use `magit-notes-merge-commit' to finish.  To abort
use `magit-notes-merge-abort'."
  (interactive (list (magit-read-string-ns "Merge reference")))
  (magit-run-git-with-editor "notes" "merge" ref))

(defun magit-notes-merge-commit ()
  "Commit the current notes ref merge.
Also see `magit-notes-merge'."
  (interactive)
  (magit-run-git-with-editor "notes" "merge" "--commit"))

(defun magit-notes-merge-abort ()
  "Abort the current notes ref merge.
Also see `magit-notes-merge'."
  (interactive)
  (magit-run-git-with-editor "notes" "merge" "--abort"))

(defun magit-notes-prune (&optional dry-run)
  "Remove notes about unreachable commits."
  (interactive (list (and (member "--dry-run" (transient-args 'magit-notes)) t)))
  (when dry-run
    (magit-process-buffer))
  (magit-run-git-with-editor "notes" "prune" (and dry-run "--dry-run")))

;;; Readers

(defun magit-notes-read-ref (prompt _initial-input history)
  (--when-let (magit-completing-read
               prompt (magit-list-notes-refnames) nil nil
               (--when-let (magit-get "core.notesRef")
                 (if (string-prefix-p "refs/notes/" it)
                     (substring it 11)
                   it))
               history)
    (if (string-prefix-p "refs/" it)
        it
      (concat "refs/notes/" it))))

(defun magit-notes-read-refs (prompt)
  (mapcar (lambda (ref)
            (if (string-prefix-p "refs/" ref)
                ref
              (concat "refs/notes/" ref)))
          (completing-read-multiple
           (concat prompt ": ")
           (magit-list-notes-refnames) nil nil
           (mapconcat (lambda (ref)
                        (if (string-prefix-p "refs/notes/" ref)
                            (substring ref 11)
                          ref))
                      (magit-get-all "notes.displayRef")
                      ","))))

(defun magit-notes-read-args (prompt)
 (list (magit-read-branch-or-commit prompt (magit-stash-at-point))
       (--when-let (--first (string-match "^--ref=\\(.+\\)" it)
                            (transient-args 'magit-notes))
         (match-string 1 it))))

;;; _
(provide 'magit-notes)
;;; magit-notes.el ends here
