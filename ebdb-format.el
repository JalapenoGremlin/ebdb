;;; ebdb-format.el --- Formatting/exporting EBDB records  -*- lexical-binding: t; -*-

;; Copyright (C) 2016  Free Software Foundation, Inc.

;; Author: Eric Abrahamsen <eric@ericabrahamsen.net>

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This file contains code for take record objects and turning them
;; into text, somehow.  It provides the basic framework that is used
;; for creating the *EBDB* buffer as well as exporting to vcard,
;; latex, and html formats.

;;; Code:

(require 'ebdb)
;; qp = quoted-printable, might not end up needing this.
(require 'qp)

(defvar ebdb-formatter-tracker nil
  "Variable for holding all instantiated formatters.")

(defclass ebdb-formatter (eieio-named eieio-instance-tracker)
  ((tracking-symbol :initform ebdb-formatter-tracker)
   (coding-system
    :type symbol
    :initarg :coding-system
    :initform nil
    :documentation "The coding system for the formatted
    file/buffer/stream.")
   ;; TODO: Provide for "psuedo field classes" like 'primary-mail and
   ;; 'role-mail.
   (include
    :type list
    :initarg :include
    :initform nil
    :documentation "A list of field classes to include.  If both
    \"include\" and \"exclude\" are given, the \"exclude\" slot
    will be ignored.")
   (exclude
    :type list
    :initarg :exclude
    :initform '(ebdb-field-uuid ebdb-field-timestamp ebdb-field-creation-date)
    :documentation "A list of field classes to exclude.")
   (sort
    :type list
    :initarg :sort
    :initform '(ebdb-field-mail ebdb-field-phone ebdb-field-address "_" ebdb-field-notes))
   (primary
    :type boolean
    :initarg :primary
    :initform nil)
   (header
    :type list
    :initarg :header
    :initform  '((ebdb-record-person ebdb-field-role ebdb-field-image)
		 (ebdb-record-organization ebdb-field-domain ebdb-field-image))
    :documentation "A list of field classes which will be output
    in the header of the record, grouped by record class type.")
   (combine
    :type list
    :initarg :combine
    :initform '(ebdb-field-mail ebdb-field-phone)
    :documentation "A list of field classes which should be
    output with all instances grouped together.")
   (collapse
    :type list
    :initarg :collapse
    :initform nil
    :documentation "A list of field classes which should be
    \"collapsed\". What this means is up to the formatter, but it
    generally indicates that most of the field contents will
    hidden unless the user takes some action, such as clicking or
    hitting <TAB>.  (Currently unimplemented.)"))
  :abstract t
  :documentation "Abstract base class for EBDB formatters.
  Subclass this to produce real formatters.")

(eieio-oset-default 'ebdb-formatter 'coding-system buffer-file-coding-system)

(cl-defmethod ebdb-string ((fmt ebdb-formatter))
  (slot-value fmt 'object-name))

(defgeneric ebdb-fmt-header (fmt records)
  "Insert a string at the beginning of the list of records.")

(defgeneric ebdb-fmt-footer (fmt records)
  "Insert a string at the end of the list of records.")

(defgeneric ebdb-fmt-record (fmt record)
  "Handle the insertion of formatted RECORD.

This method collects all the fields to be output for RECORD,
groups them into header fields and body fields, and then calls
`ebdb-fmt-record-header' and `ebdb-fmt-record-body' with the two
lists, respectively.")

(defgeneric ebdb-fmt-record-header (fmt record fields)
  "Format a header for RECORD, using the fields in FIELDS.")

(defgeneric ebdb-fmt-record-body (fmt record fields)
  "Format the body of RECORD, using the fields in FIELDS.")

(defgeneric ebdb-fmt-collect-fields (fmt record &optional fields)
  "Return a list of RECORD's FIELDS to be formatted.

Each element of FIELDS is either a single field instance, or a
list of field instances.  Which fields are present, how they're
sorted, and how they're combined into lists is determined by the
\"exclude\" and \"sort\" slots of FMT.")

(defgeneric ebdb-fmt-process-fields (fmt record &optional fields))

(defgeneric ebdb-fmt-sort-fields (fmt record &optional fields))

;; Do we still need this now that formatters and specs are collapsed?
(defgeneric ebdb-fmt-compose-field (fmt field-cons record))

(defgeneric ebdb-fmt-field (fmt field style record)
  "Format FIELD value of RECORD.

This method only returns the string value of FIELD itself,
possibly with text properties attached.")

(defgeneric ebdb-fmt-field-label (fmt field-or-class style record)
  "Format a field label, using formatter FMT.

FIELD-OR-CLASS is a field class or a field instance, and STYLE is
a symbol indicating a style of some sort, such as 'compact or
'expanded.")

;;; Basic method implementations

(cl-defmethod ebdb-fmt-header (_fmt _records)
  "")

(cl-defmethod ebdb-fmt-footer (_fmt _records)
  "")

(cl-defmethod ebdb-fmt-compose-field ((fmt ebdb-formatter)
				      field-plist
				      (record ebdb-record))
  "Turn FIELD-PLIST into a list structure suitable for formatting.

The FIELD-PLIST structure is that returned by
`ebdb-fmt-collect-fields'.  It is a plist with three
keys: :class, :style, and :inst.

This function passes the class and field instances to FMT,
which formats them appropriately."
  (let* ((style (plist-get field-plist :style))
	 (inst (plist-get field-plist :inst))
	 (label (ebdb-fmt-field-label fmt
				      (if (= 1 (length inst))
					  (car inst)
				       (plist-get field-plist :class))
				      style
				      record)))
    (cons label
	  (mapconcat
	   (lambda (f)
	     (ebdb-fmt-field fmt f style record))
	   inst
	   ", "))))

(cl-defmethod ebdb-fmt-field-label ((fmt ebdb-formatter)
				    (cls (subclass ebdb-field))
				    _style
				    (record ebdb-record))
  (ebdb-field-readable-name cls))

(cl-defmethod ebdb-fmt-field-label ((fmt ebdb-formatter)
				    (field ebdb-field)
				    _style
				    (record ebdb-record))
  (ebdb-field-readable-name field))

(cl-defmethod ebdb-fmt-field-label ((fmt ebdb-formatter)
				    (field ebdb-field-labeled)
				    _style
				    (record ebdb-record))
  (eieio-object-name-string field))

(cl-defmethod ebdb-fmt-field-label ((fmt ebdb-formatter)
				    (field ebdb-field-labeled)
				    (style (eql compact))
				    (record ebdb-record))
  (ebdb-field-readable-name field))

(cl-defmethod ebdb-fmt-field ((fmt ebdb-formatter)
			      (field ebdb-field-labeled)
			      (style (eql compact))
			      (record ebdb-record))
  (format "(%s) %s"
	  (eieio-object-name-string field)
	  (ebdb-fmt-field fmt field 'oneline record)))

(cl-defmethod ebdb-fmt-field ((fmt ebdb-formatter)
			      (field ebdb-field)
			      (style (eql oneline))
			      (record ebdb-record))
  (car (split-string (ebdb-string field) "\n")))

(cl-defmethod ebdb-fmt-field ((fmt ebdb-formatter)
			      (field ebdb-field)
			      _style
			      (record ebdb-record))
  "The base implementation for FIELD simply returns the value of
  `ebdb-string'."
  (ebdb-string field))

(cl-defmethod ebdb-fmt-collect-fields ((fmt ebdb-formatter)
				       (record ebdb-record)
				       &optional field-list)
  (let (f-class)
    (with-slots (fields notes uuid creation-date timestamp) record
     (with-slots (exclude include) fmt
       (dolist (f (append fields (list notes uuid creation-date timestamp)))
	 (when f
	   (setq f-class (eieio-object-class-name f))
	   (when (if include
		     (ebdb-class-in-list-p f-class include)
		   (null (ebdb-class-in-list-p f-class exclude)))
	     (push f field-list))))
       field-list))))

(cl-defmethod ebdb-fmt-collect-fields ((fmt ebdb-formatter)
				       (record ebdb-record-entity)
				       &optional field-list)
  (with-slots (include exclude primary) fmt
    (with-slots (mail phone address) record
      (when (and mail
		 (if include
		     (memq 'ebdb-field-mail include)
		   (null (memq 'ebdb-field-mail exclude))))
	(if primary
	    (push (object-assoc 'primary 'priority mail) field-list)
	  (dolist (m mail)
	    (push m field-list))))
      (when (and phone
		 (if include
		     (memq 'ebdb-field-phone include)
		   (null (memq 'ebdb-field-phone exclude))))
	(dolist (p phone)
	  (push p field-list)))
      (when (and address
		 (if include
		     (memq 'ebdb-field-address include)
		   (null (memq 'ebdb-field-address exclude))))
	(dolist (a address)
	  (push a field-list)))
      (cl-call-next-method fmt record field-list))))

(cl-defmethod ebdb-fmt-collect-fields ((fmt ebdb-formatter)
				       (record ebdb-record-person)
				       &optional field-list)
  
  (with-slots (exclude include) fmt
    (with-slots (aka organizations relations) record
      (when (and aka
		 (if include
		     (memq 'ebdb-field-name include)
		   (null (memq 'ebdb-field-name exclude))))
	(dolist (n aka)
	  (push n field-list)))
      (when (and organizations
		 (if include
		     (memq 'ebdb-field-role include)
		   (null (memq 'ebdb-field-role exclude))))
	(dolist (r organizations)
	  (push r field-list)))
      (when (and relations
		 (if include
		     (memq 'ebdb-field-relation include)
		   (null (memq 'ebdb-field-relation exclude))))
	(dolist (r relations)
	  (push r field-list)))
      (cl-call-next-method fmt record field-list))))

(cl-defmethod ebdb-fmt-collect-fields ((fmt ebdb-formatter)
				       (record ebdb-record-organization)
				       &optional field-list)
  (with-slots (exclude include) fmt
    (when (and (slot-value record 'domain)
	       (if include
		   (memq 'ebdb-field-domain include)
		 (null (memq 'ebdb-field-domain exclude))))
      (push (slot-value record 'domain) field-list))
    (let ((roles (gethash (ebdb-record-uuid record) ebdb-org-hashtable)))
      (when (and roles
		 (if include
		     (memq 'ebdb-field-role include)
		   (null (memq 'ebdb-field-role exclude))))
	(dolist (r roles)
	  (push (cdr r) field-list)))
      (cl-call-next-method fmt record field-list))))

(cl-defmethod ebdb-fmt-sort-fields ((fmt ebdb-formatter)
				    (record ebdb-record)
				    field-list)
  (let ((sort (slot-value fmt 'sort))
	f acc outlist)
    (when sort
      (dolist (s sort)
	(if (symbolp s)
	    (progn
	      (setq class (cl--find-class s))
	      (while (setq f (pop field-list))
		(if (same-class-p f class)
		    (push f outlist)
		  (push f acc)))
	      (setq field-list acc
		    acc nil))
	  ;; We assume this is the "_" value.  Actually, anything
	  ;; would do as a catchall placeholder.
	  (dolist (fld field-list)
	    (setq class (eieio-object-class-name fld))
	    (unless (memq class sort)
	      ;; This isn't enough -- field still need to be grouped
	      ;; by field class.
	      (push fld outlist)))))
      (setq field-list (nreverse outlist)))
    field-list))

(cl-defmethod ebdb-fmt-process-fields ((fmt ebdb-formatter)
				       (record ebdb-record)
				       field-list)
  "Process FIELD-LIST for FMT.

At present that means handling the combine and collapse slots of
FMT.

This method assumes that fields in FIELD-LIST have already been
grouped by field class."
  (let (outlist cls f acc)
    (with-slots (combine collapse) fmt
      (when combine
	(while (setq f (pop field-list))
	  (setq cls (eieio-object-class-name f))
	  (if (null (ebdb-class-in-list-p cls combine))
	      (push f outlist)
	    (push f acc)
	    (while (and field-list (same-class-p (car field-list) (eieio-object-class f)))
	      (push (setq f (pop field-list)) acc))
	    (push `(:class ,cls :style compact :inst ,acc) outlist)
	    (setq acc nil)))
	(setq field-list (nreverse outlist)
	      outlist nil))
      (dolist (f field-list)
	(if (listp f)
	    (push f outlist)
	  (setq cls (eieio-object-class-name f))
	  (push (list :class cls
		      :inst (list f)
		      :style
		      (cond
		       ((ebdb-class-in-list-p cls collapse) 'collapse)
		       (t 'oneline)))
		outlist)))
      outlist)))

;;; Basic export routines

(defcustom ebdb-format-buffer-name "*EBDB Format*"
  "Default name of buffer in which to display formatted records."
  :type 'string
  :group 'ebdb-record-display)

(defun ebdb-prompt-for-formatter ()
  (interactive)
  (let ((collection
	 (mapcar
	  (lambda (formatter)
	    (cons (slot-value formatter 'object-name) formatter))
	  ebdb-formatter-tracker)))
    (cdr (assoc (completing-read "Use formatter: " collection)
		collection))))

;;;###autoload
(defun ebdb-format-to-tmp-buffer (&optional formatter records)
  (interactive
   (list (ebdb-prompt-for-formatter)
	 (ebdb-do-records)))
  (let ((buf (get-buffer-create ebdb-format-buffer-name))
	(fmt-coding (slot-value formatter 'coding-system)))
    (with-current-buffer buf
      (erase-buffer)
      (insert (ebdb-fmt-header formatter records))
      (dolist (r records)
	(insert (ebdb-fmt-record formatter r)))
      (insert (ebdb-fmt-footer formatter records))
      (set-buffer-file-coding-system fmt-coding))
    (pop-to-buffer buf)))

;;;###autoload
(defun ebdb-format-all-records (&optional formatter)
  (interactive
   (list (ebdb-prompt-for-formatter)))
  (ebdb-format-to-tmp-buffer formatter (ebdb-records)))

(provide 'ebdb-format)
;;; ebdb-format.el ends here
