;;; ivy-cscope.el --- cscope with the interface of ivy -*- lexical-binding: t; -*-

;; Copyright (C) 2019 Fan Yang

;; Author: Fan Yang <Fan_Yang@sjtu.edu.cn>
;; Created: 31 Dec 2019
;; Homepage: https://github.com/Raphus-cucullatus/ivy-cscope.el
;; Keywords: languages c convenience tools matching
;; Version: prerelease

;; This file is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; For a full copy of the GNU General Public License
;; see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package provides yet another interface for Cscope in Emacs.
;;
;; It uses ivy (a completion tool, https://github.com/abo-abo/swiper)
;; to display and select the cscope jump candidates.  It also uses ivy
;; actions to perform rich actions (e.g. open other window, open while
;; not focus) on the jump candidates.
;;
;; It provides
;; - `ivy-cscope-find-xxx': 9 functions each for cscope's menu
;;   (e.g. symbol, definition, assignment, calling, ...).
;; - `ivy-cscope-find-definition-at-point': find the definition
;;   of the symbol at point.
;; - `ivy-cscope-pop-mark': jump back to the location before the
;;   last ivy-cscope-xxxx jump."
;; - `ivy-cscope-command-map': a keymap of all the commands
;;   above.
;;
;; Example:
;;
;; Bind the key map:
;;     (define-key c-mode-base-map (kbd "C-c j c") ivy-cscope-command-map)
;;
;; For quick access:
;;     (define-key c-mode-base-map (kbd "M-.") 'ivy-cscope-find-definition-at-point)
;;     (define-key c-mode-base-map (kbd "M-,") 'ivy-cscope-pop-mark)
;;     (define-key c-mode-base-map [M-mouse-1] 'ivy-cscope-find-definition-at-point)
;;     (define-key c-mode-base-map [M-S-mouse-1] 'ivy-cscope-pop-mark)
;;
;; Get familiar with ivy actions:
;; 1. Press "C-c j c c" (or "M-x ivy-cscope-find-caller").
;; 2. Insert "put_user_pages" to find functions calling "put_user_pages".
;; 3. A completion list shows up, like
;;
;;     (1/3) Result:
;;     drivers/infiniband/core/umem_odp.c ...
;;     fs/io_uring.c ...
;;     mm/gup.c ...
;; 4. He can move to the second line and press "M-o" to trigger ivy actions.
;;    A list of actions are shown, for example, open the result in other window,
;;    open the result in other window without focus, ....
;; 
;; Other Emacs cscope packages:
;; - xcscope.el: https://github.com/dkogan/xcscope.el


(require 'projectile)
(require 'ivy)
(require 'pulse)

(defgroup ivy-cscope nil
  "Cscope with the interface of ivy."
  :group 'tools)

(defcustom ivy-cscope-menu-alist '((symbol	.	0)
				   (definition	.	1)
				   (callee	.	2)
				   (caller	.	3)
				   (text	.	4)
				   (pattern	.	6)
				   (file	.	7)
				   (includer	.	8)
				   (assignment	.	9))
  "The mapping of cscope menu and index.  

The index will be fed to the option \"-Lnum\"."
  :type '(alist :key-type symbol :value-type integer))

(defcustom ivy-cscope-program "cscope"
  "The program name (or path) of cscope."
  :type 'string)

(defcustom ivy-cscope-option-extra '("-k" "-q")
  "Extra options when running cscope."
  :type '(repeat string))

(defcustom ivy-cscope-marker-ring-length 10
  "The length of the jumping history."
  :type 'integer)

(defvar ivy-cscope-marker-ring
  (make-ring ivy-cscope-marker-ring-length))

(defun ivy-cscope--get-root-dir ()
  "Returns project root dir if a project is detected,
or `default-directory' otherwise."
  (or (projectile-project-root) default-directory))

(defun ivy-cscope--do-search (menu query)
  "Search QUERY in MENU.

Returns cscope output if success, nil otherwise.  If error, the
output is appended to a buffer named \"*ivy-cscope error*\".

See `ivy-cscope-menu-alist' for possible menu items."
  (let ((default-directory (ivy-cscope--get-root-dir))
	(menu-idx (alist-get menu ivy-cscope-menu-alist)))
    (with-temp-buffer
      (if (= 0
	     (apply 'process-file ivy-cscope-program nil t nil
		    (format "-L%d" menu-idx)
		    query
		    ivy-cscope-option-extra))
	  (buffer-string)
	(append-to-buffer (get-buffer-create "*ivy-cscope error*")
			  (point-min) (point-max))
	nil))))

(defun ivy-cscope--parse-cscope-entry (entry)
  "Parse an entry of newline-split cscope output into a list of

    file path, function name, line number, line content.

Returns nil if error."
  (if (string-match
       "^\\([^ \t]+\\)[ \t]+\\([^ \t]+\\)[ \t]+\\([0-9]+\\)[ \t]+\\(.*\\)"
       entry)
      (let ((path (substring entry (match-beginning 1) (match-end 1)))
	    (func (substring entry (match-beginning 2) (match-end 2)))
	    (lnum (substring entry (match-beginning 3) (match-end 3)))
	    (line (substring entry (match-beginning 4) (match-end 4))))
	(list
	 (if (file-name-absolute-p path)
	     (concat (file-remote-p default-directory) path)
	   (concat (ivy-cscope--get-root-dir) path))
	 func
	 (string-to-number lnum)
	 line))
    nil))

(defun ivy-cscope--mark-current-position ()
  "Push current position into `ivy-cscope-marker-ring'."
  (ring-insert-at-beginning ivy-cscope-marker-ring
			    (cons (current-buffer) (point))))

(defun ivy-cscope--pulse-momentarily ()
  "Give a visual pulse on the current line"
  (pcase-let ((`(,beg . ,end)
               (save-excursion
                 (or (back-to-indentation)
                     (if (eolp)
			 (cons (line-beginning-position) (1+ (point)))
                       (cons (point) (line-end-position)))))))
    (pulse-momentary-highlight-region beg end 'next-error)))

(defun ivy-cscope--jump-to (method filename linum)
  (ivy-cscope--mark-current-position)
  (funcall method filename)
  (goto-char (point-min))
  (forward-line (1- linum))
  (ivy-cscope--pulse-momentarily))

(defun ivy-cscope--select-entry (entry)
  (let ((ent (ivy-cscope--parse-cscope-entry entry)))
    (when ent
      (ivy-cscope--jump-to 'find-file (nth 0 ent) (nth 2 ent)))))

(defun ivy-cscope--select-entry-other-window (entry)
  (let ((ent (ivy-cscope--parse-cscope-entry entry)))
    (when ent
      (ivy-cscope--jump-to 'find-file-other-window (nth 0 ent) (nth 2 ent)))))

(defun ivy-cscope--select-entry-other-window-not-focus (entry)
  (let ((ent (ivy-cscope--parse-cscope-entry entry)))
    (when ent
      (ivy-cscope--mark-current-position)
      (with-ivy-window
	(save-excursion
	  (ivy-cscope--jump-to 'find-file-other-window (nth 0 ent) (nth 2 ent)))))))

(defun ivy-cscope--select-entry-other-frame (entry)
  (let ((ent (ivy-cscope--parse-cscope-entry entry)))
    (when ent
      (ivy-cscope--jump-to 'find-file-other-frame (nth 0 ent) (nth 2 ent)))))

(defun ivy-cscope--find (menu query &optional disable-fast-select)
  (let ((result (ivy-cscope--do-search menu query)))
    (if (not result)
	(message "Error, see buffer *ivy-cscope error*")
      (let ((col (split-string result "\n" t)))
	(if (and (not disable-fast-select) (= (length col) 1))
	    (ivy-cscope--select-entry (car col))
	  (ivy-read "Result: "
		    col
		    :require-match t
		    :action 'ivy-cscope--select-entry
		    :caller 'ivy-cscope--find))))))

(ivy-set-actions
 'ivy-cscope--find
 '(("j" ivy-cscope--select-entry-other-window "other window")
   ("s" ivy-cscope--select-entry-other-window-not-focus "show")
   ("F" ivy-cscope--select-entry-other-frame "other frame")))

;;;###autoload
(defun ivy-cscope-pop-mark ()
  "Jump back to the location before the last ivy-cscope jump."
  (interactive)
  (when (not (ring-empty-p ivy-cscope-marker-ring))
    (let* ((m (ring-remove ivy-cscope-marker-ring))
	   (buf (car m))
	   (pos (cdr m)))
      (switch-to-buffer buf)
      (goto-char pos)
      (ivy-cscope--pulse-momentarily))))

;;;###autoload
(defun ivy-cscope-find-symbol (query)
  (interactive "sFind symbol: ")
  (ivy-cscope--find 'symbol query t))

;;;###autoload
(defun ivy-cscope-find-definition (query)
  (interactive "sFind definition: ")
  (ivy-cscope--find 'definition query t))

;;;###autoload
(defun ivy-cscope-find-definition-at-point ()
  "Find definition of the symbol at point."
  (interactive)
  (let ((sym (symbol-name (symbol-at-point))))
    (if (string-empty-p sym)
	(message "No symbol at point")
      (ivy-cscope--find 'definition sym nil))))

;;;###autoload
(defun ivy-cscope-find-callee (query)
  (interactive "sFind callee of: ")
  (ivy-cscope--find 'callee query t))

;;;###autoload
(defun ivy-cscope-find-caller (query)
  (interactive "sFind caller of: ")
  (ivy-cscope--find 'caller query t))

;;;###autoload
(defun ivy-cscope-find-text (query)
  (interactive "sSearch text: ")
  (ivy-cscope--find 'text query t))

;;;###autoload
(defun ivy-cscope-find-pattern (query)
  (interactive "sSearch for pattern: ")
  (ivy-cscope--find 'pattern query t))

;;;###autoload
(defun ivy-cscope-find-file (query)
  (interactive "sFind file: ")
  (ivy-cscope--find 'file query t))

;;;###autoload
(defun ivy-cscope-find-includer (query)
  (interactive "sFind files including: ")
  (ivy-cscope--find 'includer query t))

;;;###autoload
(defun ivy-cscope-find-assignment (query)
  (interactive "sFind assignment: ")
  (ivy-cscope--find 'assignment query t))

;;;###autoload
(defvar ivy-cscope-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "s") 'ivy-cscope-find-symbol)
    (define-key map (kbd "d") 'ivy-cscope-find-definition)
    (define-key map (kbd ".") 'ivy-cscope-find-definition-at-point)
    (define-key map (kbd ",") 'ivy-cscope-pop-mark)
    (define-key map (kbd "C") 'ivy-cscope-find-callee)
    (define-key map (kbd "c") 'ivy-cscope-find-caller)
    (define-key map (kbd "t") 'ivy-cscope-find-text)
    (define-key map (kbd "e") 'ivy-cscope-find-pattern)
    (define-key map (kbd "f") 'ivy-cscope-find-file)
    (define-key map (kbd "i") 'ivy-cscope-find-includer)
    (define-key map (kbd "=") 'ivy-cscope-find-assignment)
    map)
  "Keymap for ivy-cscope command.")

(provide 'ivy-cscope)
