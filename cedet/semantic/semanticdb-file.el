;;; semanticdb-file.el --- Save a semanticdb to a cache file.

;;; Copyright (C) 2000, 2001, 2002, 2003, 2004, 2005, 2007, 2008 Eric M. Ludlam

;; Author: Eric M. Ludlam <zappo@gnu.org>
;; Keywords: tags
;; X-RCS: $Id: semanticdb-file.el,v 1.39 2008/12/10 22:11:10 zappo Exp $

;; This file is not part of GNU Emacs.

;; Semanticdb is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; This software is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.
;; 
;;; Commentary:
;;
;; A set of semanticdb classes for persistently saving caches on disk.
;;

(require 'inversion)
(require 'semantic)
(require 'semanticdb)
(require 'cedet-files)

(defvar semanticdb-file-version semantic-version
  "Version of semanticdb we are writing files to disk with.")
(defvar semanticdb-file-incompatible-version "1.4"
  "Version of semanticdb we are not reverse compatible with.")

;;; Settings
;;
;;;###autoload
(defcustom semanticdb-default-file-name "semantic.cache"
  "*File name of the semantic tag cache."
  :group 'semanticdb
  :type 'string)

;;;###autoload
(defcustom semanticdb-default-save-directory (expand-file-name "~/.semanticdb")
  "*Directory name where semantic cache files are stored.
If this value is nil, files are saved in the current directory.  If the value
is a valid directory, then it overrides `semanticdb-default-file-name' and
stores caches in a coded file name in this directory."
  :group 'semanticdb
  :type '(choice :tag "Default-Directory"
                 :menu-tag "Default-Directory"
                 (const :tag "Use current directory" :value nil)
                 (directory)))

;;;###autoload
(defcustom semanticdb-persistent-path '(always)
  "*List of valid paths that semanticdb will cache tags to.
When `global-semanticdb-minor-mode' is active, tag lists will
be saved to disk when Emacs exits.  Not all directories will have
tags that should be saved.
The value should be a list of valid paths.  A path can be a string,
indicating a directory in which to save a variable.  An element in the
list can also be a symbol.  Valid symbols are `never', which will
disable any saving anywhere, `always', which enables saving
everywhere, or `project', which enables saving in any directory that
passes a list of predicates in `semanticdb-project-predicate-functions'."
  :group 'semanticdb
  :type nil)

(defcustom semanticdb-save-database-hooks nil
  "*Hooks run after a database is saved.
Each function is called with one argument, the object representing
the database recently written."
  :group 'semanticdb
  :type 'hook)

(defvar semanticdb-dir-sep-char (if (boundp 'directory-sep-char)
				    (symbol-value 'directory-sep-char)
				  ?/)
  "Character used for directory separation.
Obsoleted in some versions of Emacs.  Needed in others.
NOTE: This should get deleted from semantic soon.")

(defun semanticdb-fix-pathname (dir)
  "If DIR is broken, fix it.
Force DIR to end with a /.
Note: Same as `file-name-as-directory'.
NOTE: This should get deleted from semantic soon."
  (file-name-as-directory dir))
;; I didn't initially know about the above fcn.  Keep the below as a
;; reference.  Delete it someday once I've proven everything is the same.
;;  (if (not (= semanticdb-dir-sep-char (aref path (1- (length path)))))
;;      (concat path (list semanticdb-dir-sep-char))
;;    path))

;;; Classes
;;
;;;###autoload
(defclass semanticdb-project-database-file (semanticdb-project-database
					    eieio-persistent)
  ((file-header-line :initform ";; SEMANTICDB Tags save file")
   (do-backups :initform nil)
   (semantic-tag-version :initarg :semantic-tag-version
			 :initform "1.4"
			 :documentation
			 "The version of the tags saved.
The default value is 1.4.  In semantic 1.4 there was no versioning, so
when those files are loaded, this becomes the version number.
To save the version number, we must hand-set this version string.")
   (semanticdb-version :initarg :semanticdb-version
		       :initform "1.4"
		       :documentation
		       "The version of the object system saved.
The default value is 1.4.  In semantic 1.4, there was no versioning,
so when those files are loaded, this becomes the version number.
To save the version number, we must hand-set this version string.")
   )
  "Database of file tables saved to disk.")

;;; Code:
;;
(defmethod semanticdb-create-database :STATIC ((dbc semanticdb-project-database-file)
					       directory)
  "Create a new semantic database for DIRECTORY and return it.
If a database for DIRECTORY has already been loaded, return it.
If a database for DIRECTORY exists, then load that database, and return it.
If DIRECTORY doesn't exist, create a new one."
  ;; Make sure this is fully expanded so we don't get duplicates.
  (setq directory (file-truename directory))
  (let* ((fn (semanticdb-cache-filename dbc directory))
	 (db (or (semanticdb-file-loaded-p fn)
		 (if (file-exists-p fn)
		     (progn
		       (semanticdb-load-database fn))))))
    (unless db
      (setq db (make-instance
		dbc  ; Create the database requested.  Perhaps
		(concat (file-name-nondirectory
			 (directory-file-name
			  directory))
			"/")
		:file fn :tables nil
		:semantic-tag-version semantic-version
		:semanticdb-version semanticdb-file-version)))
    ;; Set this up here.   We can't put it in the constructor because it
    ;; would be saved, and we want DB files to be portable.
    (oset db reference-directory directory)
    db))

;;; File IO
(defun semanticdb-load-database (filename)
  "Load the database FILENAME."
  (condition-case foo
      (let* ((r (eieio-persistent-read filename))
	     (c (semanticdb-get-database-tables r))
	     (tv (oref r semantic-tag-version))
	     (fv (oref r semanticdb-version))
	     )
	;; Restore the parent-db connection
	(while c
	  (oset (car c) parent-db r)
	  (setq c (cdr c)))
	(if (not (inversion-test 'semanticdb-file fv))
	    (when (inversion-test 'semantic-tag tv)
	      ;; Incompatible version.  Flush tables.
	      (semanticdb-flush-database-tables r)
	      ;; Reset the version to new version.
	      (oset r semantic-tag-version semantic-tag-version)
	      ;; Warn user
	      (message "Semanticdb file is old.  Starting over for %s"
		       filename)
	      )
	  ;; Version is not ok.  Flush whole system
	  (message "semanticdb file is old.  Starting over for %s"
		   filename)
	  ;; This database is so old, we need to replace it.
	  ;; We also need to delete it from the instance tracker.
	  (delete-instance r)
	  (setq r nil))
	r)
    (error (message "Cache Error: [%s] %s, Restart" 
		    filename foo)
	   nil)))

;;;###autoload
(defun semanticdb-file-loaded-p (filename)
  "Return the project belonging to FILENAME if it was already loaded."
  (eieio-instance-tracker-find filename 'file 'semanticdb-database-list))

(defmethod semanticdb-file-directory-exists-p ((DB semanticdb-project-database-file)
					       &optional supress-questions)
  "Does the directory the database DB needs to write to exist?
If SUPRESS-QUESTIONS, then do not ask to create the directory."
  (let ((dest (file-name-directory (oref DB file)))
	)
    (cond ((null dest)
	   ;; @TODO - If it was never set up... what should we do ?
	   nil)
	  ((file-exists-p dest) t)
	  (supress-questions nil)
	  ((y-or-n-p (format "Create directory %s for SemanticDB? "
			     dest))
	   (make-directory dest t)
	   t)
	  (t nil))
    ))

(defmethod semanticdb-save-db ((DB semanticdb-project-database-file)
			       &optional
			       supress-questions)
  "Write out the database DB to its file.
If DB is not specified, then use the current database."
  (let ((objname (oref DB file)))
    (when (and (semanticdb-live-p DB)
	       (semanticdb-file-directory-exists-p DB supress-questions)
	       (semanticdb-write-directory-p DB)
	       (semanticdb-dirty-p DB))
      ;;(message "Saving tag summary for %s..." objname)
      (condition-case foo
	  (eieio-persistent-save (or DB semanticdb-current-database))
	(file-error		    ; System error saving?  Ignore it.
	 (message "%S: %s" foo objname))
	(error
	 (cond
	  ((and (listp foo)
		(stringp (nth 1 foo))
		(string-match "write[- ]protected" (nth 1 foo)))
	   (message (nth 1 foo)))
	  ((and (listp foo)
		(stringp (nth 1 foo))
		(string-match "no such directory" (nth 1 foo)))
	   (message (nth 1 foo)))
	  (t
	   ;; @todo - It should ask if we are not called from a hook.
	   ;;         How?
	   (if (or supress-questions
		   (y-or-n-p (format "Skip Error: %S ?" (car (cdr foo)))))
	       (message "Save Error: %S: %s" (car (cdr foo))
			objname)
	     (error "%S" (car (cdr foo))))))))
      (run-hook-with-args 'semanticdb-save-database-hooks
			  (or DB semanticdb-current-database))
      ;;(message "Saving tag summary for %s...done" objname)
      )
    ))

;;;###autoload
(defmethod semanticdb-live-p ((obj semanticdb-project-database))
  "Return non-nil if the file associated with OBJ is live.
Live databases are objects associated with existing directories."
  (and (slot-boundp obj 'reference-directory)
       (file-exists-p (oref obj reference-directory))))

(defmethod semanticdb-live-p ((obj semanticdb-table))
  "Return non-nil if the file associated with OBJ is live.
Live files are either buffers in Emacs, or files existing on the filesystem."
  (let ((full-filename (semanticdb-full-filename obj)))
    (or (find-buffer-visiting full-filename)
	(file-exists-p full-filename))))

(defmethod object-write ((obj semanticdb-table))
  "When writing a table, we have to make sure we deoverlay it first.
Restore the overlays after writting.
Argument OBJ is the object to write."
  (when (semanticdb-live-p obj)
    (when (semanticdb-in-buffer-p obj)
      (save-excursion
	(set-buffer (semanticdb-in-buffer-p obj))

	;; Make sure all our tag lists are up to date.
	(semantic-fetch-tags)

	;; Try to get an accurate unmatched syntax table.
	(when (and (boundp semantic-show-unmatched-syntax-mode)
		   semantic-show-unmatched-syntax-mode)
	  ;; Only do this if the user runs unmatched syntax
	  ;; mode display enties.
	  (oset obj unmatched-syntax
		(semantic-show-unmatched-lex-tokens-fetch))
	  )
		       
	;; Make sure pointmax is up to date
	(oset obj pointmax (point-max))
	))

    ;; Make sure that the file size and other attributes are
    ;; up to date.
    (let ((fattr (file-attributes (semanticdb-full-filename obj))))
      (oset obj fsize (nth 7 fattr))
      (oset obj lastmodtime (nth 5 fattr))
      )
    
    ;; Do it!
    (call-next-method)

    ;; Clear the dirty bit.
    (oset obj dirty nil)
    ))

;;; State queries
;;
(defmethod semanticdb-write-directory-p ((obj semanticdb-project-database-file))
  "Return non-nil if OBJ should be written to disk.
Uses `semanticdb-persistent-path' to determine the return value."
  (let ((path semanticdb-persistent-path))
    (catch 'found
      (while path
	(cond ((stringp (car path))
	       (if (string= (oref obj reference-directory) (car path))
		   (throw 'found t)))
	      ((eq (car path) 'project)
	       ;; @TODO - EDE causes us to go in here and disable
	       ;; the old default 'always save' setting.
	       ;;
	       ;; With new default 'always' should I care?
	       (if semanticdb-project-predicate-functions
		   (if (run-hook-with-args-until-success
			'semanticdb-project-predicate-functions
			(oref obj reference-directory))
		       (throw 'found t))
		 ;; If the mode is 'project, and there are no project
		 ;; modes, then just always save the file.  If users
		 ;; wish to restrict the search, modify
		 ;; `semanticdb-persistent-path' to include desired paths.
		 (if (= (length semanticdb-persistent-path) 1)
		     (throw 'found t))
		 ))
	      ((eq (car path) 'never)
	       (throw 'found nil))
	      ((eq (car path) 'always)
	       (throw 'found t))
	      (t (error "Invalid path %S" (car path))))
	(setq path (cdr path)))
      (call-next-method))
    ))

;;; Filename manipulation
;;
(defmethod semanticdb-file-table ((obj semanticdb-project-database-file) filename)
  "From OBJ, return FILENAME's associated table object."
  ;; Cheater option.  In this case, we always have files directly
  ;; under ourselves.  The main project type may not.
  (object-assoc (file-name-nondirectory filename) 'file (oref obj tables)))

(defmethod semanticdb-file-name-non-directory :STATIC
  ((dbclass semanticdb-project-database-file))
  "Return the file name DBCLASS will use.
File name excludes any directory part."
  semanticdb-default-file-name)

(defmethod semanticdb-file-name-directory :STATIC
  ((dbclass semanticdb-project-database-file) directory)
  "Return the relative directory to where DBCLASS will save its cache file.
The returned path is related to DIRECTORY."
  (if semanticdb-default-save-directory
      (let ((file (cedet-directory-name-to-file-name directory)))
        ;; Now create a filename for the cache file in
        ;; ;`semanticdb-default-save-directory'.
	(expand-file-name 
	 file (file-name-as-directory semanticdb-default-save-directory)))
    directory))

(defmethod semanticdb-cache-filename :STATIC
  ((dbclass semanticdb-project-database-file) path)
  "For DBCLASS, return a file to a cache file belonging to PATH.
This could be a cache file in the current directory, or an encoded file
name in a secondary directory."
  ;; Use concat and not expand-file-name, because the dir part
  ;; may include some of the file name.
  (concat (semanticdb-file-name-directory dbclass path)
	  (semanticdb-file-name-non-directory dbclass)))

;;;###autoload
(defmethod semanticdb-full-filename ((obj semanticdb-project-database-file))
  "Fetch the full filename that OBJ refers to."
  (oref obj file))

;;; Compatibility
;;
;; replace-regexp-in-string is in subr.el in Emacs 21.  Provide
;; here for compatibility.

(if (not (fboundp 'replace-regexp-in-string))

(defun replace-regexp-in-string (regexp rep string &optional
					fixedcase literal subexp start)
  "Replace all matches for REGEXP with REP in STRING.

Return a new string containing the replacements.

Optional arguments FIXEDCASE, LITERAL and SUBEXP are like the
arguments with the same names of function `replace-match'.  If START
is non-nil, start replacements at that index in STRING.

REP is either a string used as the NEWTEXT arg of `replace-match' or a
function.  If it is a function it is applied to each match to generate
the replacement passed to `replace-match'; the match-data at this
point are such that match 0 is the function's argument.

To replace only the first match (if any), make REGEXP match up to \\'
and replace a sub-expression, e.g.
  (replace-regexp-in-string \"\\(foo\\).*\\'\" \"bar\" \" foo foo\" nil nil 1)
    => \" bar foo\""

  ;; To avoid excessive consing from multiple matches in long strings,
  ;; don't just call `replace-match' continually.  Walk down the
  ;; string looking for matches of REGEXP and building up a (reversed)
  ;; list MATCHES.  This comprises segments of STRING which weren't
  ;; matched interspersed with replacements for segments that were.
  ;; [For a `large' number of replacements it's more efficient to
  ;; operate in a temporary buffer; we can't tell from the function's
  ;; args whether to choose the buffer-based implementation, though it
  ;; might be reasonable to do so for long enough STRING.]
  (let ((l (length string))
	(start (or start 0))
	matches str mb me)
    (save-match-data
      (while (and (< start l) (string-match regexp string start))
	(setq mb (match-beginning 0)
	      me (match-end 0))
	;; If we matched the empty string, make sure we advance by one char
	(when (= me mb) (setq me (min l (1+ mb))))
	;; Generate a replacement for the matched substring.
	;; Operate only on the substring to minimize string consing.
	;; Set up match data for the substring for replacement;
	;; presumably this is likely to be faster than munging the
	;; match data directly in Lisp.
	(string-match regexp (setq str (substring string mb me)))
	(setq matches
	      (cons (replace-match (if (stringp rep)
				       rep
				     (funcall rep (match-string 0 str)))
				   fixedcase literal str subexp)
		    (cons (substring string start mb) ; unmatched prefix
			  matches)))
	(setq start me))
      ;; Reconstruct a string from the pieces.
      (setq matches (cons (substring string start l) matches)) ; leftover
      (apply #'concat (nreverse matches)))))

)

(provide 'semanticdb-file)

;;; semanticdb-file.el ends here
