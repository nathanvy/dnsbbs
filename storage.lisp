(in-package #:dnsbbs)

;;;; Storage layer: generic protocol + in-memory backend.
;;;;
;;;; To add a new backend (e.g. Postgres), implement all defgenerics
;;;; against your own store struct.

;;; Condition

(define-condition storage-error (error)
  ((message :initarg :message :reader storage-error-message))
  (:report (lambda (c s)
             (format s "Storage error: ~A" (storage-error-message c)))))

;;; Domain structs

(defstruct topic
  name
  desc
  (messages (make-array 0 :element-type t :adjustable t :fill-pointer 0))
  (next-id  1))

(defstruct message
  id
  author
  timestamp   ; local-time timestamp
  body)

;;; Storage protocol

(defgeneric list-topics (store)
  (:documentation "Return a fresh list of topic-name strings."))

(defgeneric get-topic (store name)
  (:documentation "Return the topic struct for NAME, or NIL if not found."))

(defgeneric create-topic (store name desc)
  (:documentation "Create and return a new topic. Signals STORAGE-ERROR if NAME already exists."))

(defgeneric get-message (store topic-name id)
  (:documentation "Return the message struct with the given integer ID in TOPIC-NAME, or NIL."))

(defgeneric post-message (store topic-name author body)
  (:documentation "Append a message to TOPIC-NAME. Returns the new integer message ID.
  Signals STORAGE-ERROR if the topic does not exist."))

(defgeneric topic-latest-id (store topic-name)
  (:documentation "Return the ID of the most recent message in TOPIC-NAME, or NIL if empty/missing."))

;;; In-memory backend

(defstruct (memory-store (:constructor %make-memory-store (topics-table)))
  topics-table)   ; hash-table: string -> topic

(defun make-memory-store ()
  "Create a fresh in-memory store."
  (%make-memory-store (make-hash-table :test #'equal)))

(defparameter *max-messages-per-topic* 10000)

(defmethod list-topics ((store memory-store))
  (let ((names '()))
    (maphash (lambda (k v) (declare (ignore v)) (push k names))
             (memory-store-topics-table store))
    names))

(defmethod get-topic ((store memory-store) name)
  (gethash name (memory-store-topics-table store)))

(defmethod create-topic ((store memory-store) name desc)
  (let ((table (memory-store-topics-table store)))
    (when (gethash name table)
      (error 'storage-error
             :message (format nil "Topic already exists: ~A" name)))
    (let ((topic (make-topic :name name :desc desc)))
      (setf (gethash name table) topic)
      topic)))

(defmethod get-message ((store memory-store) topic-name id)
  (let ((topic (gethash topic-name (memory-store-topics-table store))))
    (when topic
      ;; Messages are stored in a 0-indexed vector; IDs start at 1.
      (let ((idx (1- id)))
        (when (and (>= idx 0) (< idx (length (topic-messages topic))))
          (aref (topic-messages topic) idx))))))

(defmethod post-message ((store memory-store) topic-name author body)
  (let ((topic (gethash topic-name (memory-store-topics-table store))))
    (unless topic
      (error 'storage-error
             :message (format nil "Topic not found: ~A" topic-name)))
    (when (>= (length (topic-messages topic)) *max-messages-per-topic*)
      (error 'storage-error
             :message (format nil "Topic ~A is full" topic-name)))
    (let* ((id  (topic-next-id topic))
           (msg (make-message :id        id
                              :author    author
                              :timestamp (local-time:now)
                              :body      body)))
      (vector-push-extend msg (topic-messages topic))
      (incf (topic-next-id topic))
      id)))

(defmethod topic-latest-id ((store memory-store) topic-name)
  (let ((topic (gethash topic-name (memory-store-topics-table store))))
    (when (and topic (> (length (topic-messages topic)) 0))
      (1- (topic-next-id topic)))))
