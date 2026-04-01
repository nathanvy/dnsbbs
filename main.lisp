(in-package #:dnsbbs)

;;;; Entry point.

(defun main ()
  "Create the in-memory store, seed default topics, and start the server."
  (let ((store (make-memory-store)))
    (create-topic store "misc" "General discussion")
    (create-topic store "dev" "Development discussion")
    (run-server store :port 31337)))
