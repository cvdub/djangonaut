;;; djangonaut.el --- Emacs minor mode for Django  -*- lexical-binding: t; -*-

;; Copyright (C) 2018 by Artem Malyshev

;; Author: Artem Malyshev <proofit404@gmail.com>
;; URL: https://github.com/proofit404/djangonaut
;; Version: 0.0.1
;; Package-Requires: ((emacs "24") (pythonic "0.1.0") (dash "2.13.0") (s "1.12.0") (f "0.20.0"))

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program. If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; See the README for more details.

;;; Code:

(require 'pythonic)
(require 'json)
(require 'dash)
(require 's)
(require 'f)

(defvar djangonaut-get-project-root-code "
from __future__ import print_function
from importlib import import_module
from os import environ
from os.path import dirname

settings_module = environ['DJANGO_SETTINGS_MODULE']
package_name = settings_module.split('.', 1)[0]
package = import_module(package_name)
project_root = dirname(dirname(package.__file__))
print(project_root, end='')
")

(defvar djangonaut-get-commands-code "
from __future__ import print_function

from django.apps import apps
from django.conf import settings
apps.populate(settings.INSTALLED_APPS)

from django.core.management import get_commands
print('\\n'.join(get_commands().keys()))
")

(defvar djangonaut-get-app-paths-code "
from __future__ import print_function
from json import dumps

from django.apps import apps
from django.conf import settings
apps.populate(settings.INSTALLED_APPS)

paths = {app.label: app.path for app in apps.get_app_configs()}
print(dumps(paths), end='')
")

(defvar djangonaut-get-models-code "
from __future__ import print_function
from inspect import findsource, getfile
from json import dumps

from django.apps import apps
from django.conf import settings
apps.populate(settings.INSTALLED_APPS)

models = {model.__name__: [getfile(model), findsource(model)[1]] for model in apps.get_models()}
print(dumps(models), end='')
")

(defvar djangonaut-get-signal-receivers-code "
from __future__ import print_function

from django.apps import apps
from django.conf import settings
apps.populate(settings.INSTALLED_APPS)

from gc import get_objects
from inspect import findsource, getfile
from json import dumps
from weakref import ReferenceType

from django.dispatch.dispatcher import Signal

receivers = {}
for obj in get_objects():
    if isinstance(obj, Signal):
        for lookup_key, receiver in obj.receivers:
            if isinstance(receiver, ReferenceType):
                receiver = receiver()
                if receiver is None:
                    continue
            receivers[receiver.__name__] = [getfile(receiver), findsource(receiver)[1]]

print(dumps(receivers), end='')
")

(defun djangonaut-get-project-root ()
  (with-output-to-string
    (with-current-buffer
        standard-output
      (call-pythonic :buffer standard-output
                     :args (list "-c" djangonaut-get-project-root-code)))))

(defun djangonaut-get-commands ()
  (split-string
   (with-output-to-string
     (with-current-buffer
         standard-output
       (call-pythonic :buffer standard-output
                      :args (list "-c" djangonaut-get-commands-code)
                      :cwd (djangonaut-get-project-root))))
   nil t))

(defun djangonaut-get-app-paths ()
  (json-read-from-string
   (with-output-to-string
     (with-current-buffer
         standard-output
       (call-pythonic :buffer standard-output
                      :args (list "-c" djangonaut-get-app-paths-code)
                      :cwd (djangonaut-get-project-root))))))

(defun djangonaut-get-models ()
  (json-read-from-string
   (with-output-to-string
     (with-current-buffer
         standard-output
       (call-pythonic :buffer standard-output
                      :args (list "-c" djangonaut-get-models-code)
                      :cwd (djangonaut-get-project-root))))))

(defun djangonaut-get-signal-receivers ()
  (json-read-from-string
   (with-output-to-string
     (with-current-buffer
         standard-output
       (call-pythonic :buffer standard-output
                      :args (list "-c" djangonaut-get-signal-receivers-code)
                      :cwd (djangonaut-get-project-root))))))

(defun djangonaut-management-command (&rest command)
  (interactive (split-string (completing-read "Command: " (djangonaut-get-commands) nil nil) " " t))
  (start-pythonic :process "djangonaut"
                  :buffer "*Django*"
                  :args (append (list "-m" "django") command)
                  :cwd (djangonaut-get-project-root))
  (pop-to-buffer "*Django*"))

(defun djangonaut-find-model ()
  (interactive)
  (let* ((models (djangonaut-get-models))
         (model (intern (completing-read "Model: " (mapcar 'symbol-name (mapcar 'car models)) nil t)))
         (code (cdr (assoc model models)))
         (filename (elt code 0))
         (lineno (elt code 1)))
    (when (pythonic-remote-p)
      (setq filename (concat (pythonic-tramp-connection) filename)))
    (find-file filename)
    (goto-char (point-min))
    (forward-line lineno)))

(defun djangonaut-find-signal-receivers ()
  (interactive)
  (let* ((receivers (djangonaut-get-signal-receivers))
         (receiver (intern (completing-read "Receiver: " (mapcar 'symbol-name (mapcar 'car receivers)) nil t)))
         (code (cdr (assoc receiver receivers)))
         (filename (elt code 0))
         (lineno (elt code 1)))
    (when (pythonic-remote-p)
      (setq filename (concat (pythonic-tramp-connection) filename)))
    (find-file filename)
    (goto-char (point-min))
    (forward-line lineno)))

(defvar djangonaut-mode-map
  (let ((map (make-keymap)))
    (define-key map (kbd "C-c r !") 'djangonaut-management-command)
    (define-key map (kbd "C-c r m") 'djangonaut-find-model)
    (define-key map (kbd "C-c r r") 'djangonaut-find-signal-receivers)
    map))

(defvar djangonaut-mode-lighter " Django")

;;;###autoload
(define-minor-mode djangonaut-mode
  ""
  :lighter djangonaut-mode-lighter
  :keymap djangonaut-mode-map)

;;;###autoload
(define-globalized-minor-mode global-djangonaut-mode djangonaut-mode
  (lambda ()
    (ignore-errors
      (-when-let* ((project-root (djangonaut-get-project-root))
                   (directory (pythonic-file-name default-directory))
                   (in-project (or (f-same? project-root directory)
                                   (f-ancestor-of? project-root directory))))
        (djangonaut-mode 1)))))

(provide 'djangonaut)

;;; djangonaut.el ends here
