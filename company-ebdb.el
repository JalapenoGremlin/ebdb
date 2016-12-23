;;; company-ebdb.el --- company-mode completion backend for EBDB in message-mode

;; Copyright (C) 2013-2014, 2016  Free Software Foundation, Inc.

;; Author: Jan Tatarik <jan.tatarik@gmail.com>

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <http://www.gnu.org/licenses/>.

(require 'company)
(require 'cl-lib)

(declare-function ebdb-record-get-field "ebdb")
(declare-function ebdb-records "ebdb")
(declare-function ebdb-dwim-mail "ebdb-com")
(declare-function ebdb-search "ebdb-com")

(defgroup company-ebdb nil
  "Completion backend for EBDB."
  :group 'company)

(defcustom company-ebdb-modes '(message-mode)
  "Major modes in which `company-ebdb' may complete."
  :type '(repeat (symbol :tag "Major mode"))
  :package-version '(company . "0.8.8"))

(defun company-ebdb--candidates (arg)
  (cl-mapcan (lambda (record)
               (mapcar (lambda (mail) (ebdb-dwim-mail record mail))
                       (ebdb-record-get-field record 'mail)))
             (eval '(ebdb-search (ebdb-records) arg nil arg))))

;;;###autoload
(defun company-ebdb (command &optional arg &rest ignore)
  "`company-mode' completion backend for EBDB."
  (interactive (list 'interactive))
  (cl-case command
    (interactive (company-begin-backend 'company-ebdb))
    (prefix (and (memq major-mode company-ebdb-modes)
                 (featurep 'ebdb-com)
                 (looking-back "^\\(To\\|Cc\\|Bcc\\): *.*? *\\([^,;]*\\)"
                               (line-beginning-position))
                 (match-string-no-properties 2)))
    (candidates (company-ebdb--candidates arg))
    (sorted t)
    (no-cache t)))

(provide 'company-ebdb)
;;; company-ebdb.el ends here
