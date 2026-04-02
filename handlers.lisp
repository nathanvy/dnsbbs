(in-package #:dnsbbs)

;;;; Query handlers.
;;;;
;;;; Each handler returns either:
;;;;   - a list of strings (the TXT answer strings), or
;;;;   - :nxdomain (causes the server to return NXDOMAIN).

;;; Chunk buffer for multi-part posts.
;;; Key:   (list client-ip-string topic-name)
;;; Value: plist (:chunks <list-of-base32-strings> :created-at <universal-time>)

(defparameter *chunk-buffer*
  (make-hash-table :test #'equal))

(defun expire-chunk-buffers ()
  "Remove chunk buffer entries older than 60 seconds."
  (let ((cutoff (- (get-universal-time) 60))
        (stale  '()))
    (maphash (lambda (k v)
               (when (< (getf v :created-at) cutoff)
                 (push k stale)))
             *chunk-buffer*)
    (dolist (k stale)
      (remhash k *chunk-buffer*))))

;;; Read handlers

(defun handle-index (store page)
  "Return a paginated topic list as a single TXT string.
  Format: \"t=foo,bar,baz\" with \",next=N\" appended when more pages exist."
  (let* ((all-topics (sort (list-topics store) #'string<))
         (total      (length all-topics))
         (per-page   10)
         (start      (min (* (1- page) per-page) total))
         (end        (min (+ start per-page) total))
         (page-items (subseq all-topics start end))
         (has-more   (< end total))
         (result     (format nil "t=~{~A~^,~}" page-items)))
    (when has-more
      (setf result (concatenate 'string result
                                (format nil ",next=~A" (1+ page)))))
    (list result)))

(defun handle-meta (store topic-name)
  "Return topic metadata as a TXT string, or :nxdomain if the topic is unknown."
  (let ((topic (get-topic store topic-name)))
    (if topic
        (let ((latest (topic-latest-id store topic-name)))
          (list (format nil "desc=~A;latest=~A"
                        (topic-desc topic)
                        (or latest 0))))
        :nxdomain)))

(defun handle-msg (store topic-name id page)
  "Return message content as a list of TXT strings, or :nxdomain.
  PAGE is 1-indexed: page 1 returns chunks starting from the beginning,
  page N skips the first N-1 chunks (for very large messages)."
  (let ((msg (get-message store topic-name id)))
    (if msg
        (let* ((body-b64 (b64-encode (message-body msg)))
               (ts       (local-time:format-timestring
                          nil (message-timestamp msg)))
               (prev-id  (when (> id 1)
                           (when (get-message store topic-name (1- id))
                             (1- id))))
               (full-str (format nil "author=~A;ts=~A;body=~A~@[;next=~A~]"
                                 (message-author msg)
                                 ts
                                 body-b64
                                 prev-id))
               (all-chunks (format-txt-chunks full-str))
               (remaining  (nthcdr (1- page) all-chunks)))
          (or remaining (list "")))
        :nxdomain)))

;;; Write handlers

(defun split-post-payload (decoded-bytes)
  "Split decoded bytes into (values author body).
  If bytes contain '|' (0x7C), split on first occurrence: left=author, right=body.
  Otherwise: author=\"anon\", body=entire string."
  (let* ((str      (babel:octets-to-string decoded-bytes :encoding :utf-8))
         (pipe-pos (position #\| str)))
    (if pipe-pos
        (values (subseq str 0 pipe-pos)
                (subseq str (1+ pipe-pos)))
        (values "anon" str))))

(defun handle-post-single (store topic-name client-ip payload-b32)
  "Handle a single-chunk post (no seq number).
  Returns \"ok;id=N\" on success, or :nxdomain if the topic doesn't exist."
  (declare (ignore client-ip))
  (handler-case
      (multiple-value-bind (author body)
          (split-post-payload (base32-decode payload-b32))
        (let ((id (post-message store topic-name author body)))
          (list (format nil "ok;id=~A" id))))
    (storage-error ()
      :nxdomain)))

(defun handle-post-chunk (store topic-name client-ip payload-b32 seq)
  "Handle one chunk of a multi-part post.
  SEQ is either a numeric string (\"0\", \"1\", ...) or \"end\".
  On intermediate chunks: accumulates and returns \"ok;seq=N\".
  On \"end\": concatenates all chunks, decodes, posts, returns \"ok;id=N\"."
  (expire-chunk-buffers)
  (let* ((key   (list client-ip topic-name))
         (entry (gethash key *chunk-buffer*))
         (now   (get-universal-time)))
    (if (string-equal seq "end")
        ;; Final chunk: assemble, decode, post.
        (let* ((prior   (if entry (getf entry :chunks) '()))
               (all-b32 (apply #'concatenate 'string
                               (append prior (list payload-b32)))))
          (remhash key *chunk-buffer*)
          (handler-case
              (multiple-value-bind (author body)
                  (split-post-payload (base32-decode all-b32))
                (let ((id (post-message store topic-name author body)))
                  (list (format nil "ok;id=~A" id))))
            (storage-error ()
              :nxdomain)))
        ;; Intermediate chunk: accumulate.
        (let ((updated-chunks (append (if entry (getf entry :chunks) '())
                                      (list payload-b32))))
          (setf (gethash key *chunk-buffer*)
                (list :chunks     updated-chunks
                      :created-at (if entry
                                      (getf entry :created-at)
                                      now)))
          (list (format nil "ok;seq=~A" seq))))))

;;; Help handler

(defun handle-wtf ()
  "Return help text as multiple TXT strings, one per TXT record."
  (list
   "Topics: dig TXT index.bbs.stackgho.st"
   "Info: dig TXT meta.<topic>.bbs.stackgho.st"
   "Read: dig TXT msg.<id>.<topic>.bbs.stackgho.st"
   "Read pg: dig TXT msg.<id>.<page>.<topic>.bbs.stackgho.st"
   "Post: dig TXT post.<b32(msg)>.<topic>.bbs.stackgho.st"
   "Post long: post.<b32-chunk>.<seq>.<topic>.bbs.stackgho.st, seq=0,1,...,end"))
