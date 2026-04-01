(in-package #:dnsbbs)

;;;; QNAME routing: strip the zone suffix, then pattern-match remaining labels.

;;; Hard-coded authoritative zone (left-to-right label order).
(defparameter +zone+ '("bbs" "stackgho" "st"))

(defun strip-zone (labels zone)
  "If LABELS ends with ZONE (case-insensitively), return the prefix labels.
  Otherwise return NIL."
  (let ((llen (length labels))
        (zlen (length zone)))
    (when (>= llen zlen)
      (let ((suffix (nthcdr (- llen zlen) labels)))
        (when (every #'string-equal suffix zone)
          (subseq labels 0 (- llen zlen)))))))

(defun parse-int-or-nil (string)
  "Parse STRING as a non-negative integer, returning NIL on failure."
  (handler-case (parse-integer string)
    (error () nil)))

(defun match-route (labels)
  "Pattern-match stripped QNAME labels to a (values keyword plist) dispatch pair."
  (let ((n (length labels)))
    (cond
      ;; index.ZONE  →  :index page=1
      ((and (= n 1) (string-equal (first labels) "index"))
       (values :index (list :page 1)))

      ;; index.<page>.ZONE  →  :index page=N
      ((and (= n 2) (string-equal (first labels) "index"))
       (let ((page (parse-int-or-nil (second labels))))
         (if (and page (> page 0))
             (values :index (list :page page))
             (values :nxdomain nil))))

      ;; meta.<topic>.ZONE
      ((and (= n 2) (string-equal (first labels) "meta"))
       (values :meta (list :topic (string-downcase (second labels)))))

      ;; msg.<id>.<topic>.ZONE
      ((and (= n 3) (string-equal (first labels) "msg"))
       (let ((id (parse-int-or-nil (second labels))))
         (if (and id (> id 0))
             (values :msg (list :id    id
                                :topic (string-downcase (third labels))
                                :page  1))
             (values :nxdomain nil))))

      ;; msg.<id>.<page>.<topic>.ZONE
      ((and (= n 4) (string-equal (first labels) "msg"))
       (let ((id   (parse-int-or-nil (second labels)))
             (page (parse-int-or-nil (third labels))))
         (if (and id (> id 0) page (> page 0))
             (values :msg (list :id    id
                                :topic (string-downcase (fourth labels))
                                :page  page))
             (values :nxdomain nil))))

      ;; post.<payload>.<topic>.ZONE  →  single-chunk post
      ((and (= n 3) (string-equal (first labels) "post"))
       (values :post-single (list :payload (second labels)
                                  :topic   (string-downcase (third labels)))))

      ;; post.<payload>.<seq>.<topic>.ZONE  →  multi-chunk post
      ((and (= n 4) (string-equal (first labels) "post"))
       (values :post-chunk (list :payload (second labels)
                                 :seq     (third labels)
                                 :topic   (string-downcase (fourth labels)))))

      ;; wtf.ZONE  →  :wtf (help)
      ((and (= n 1) (string-equal (first labels) "wtf"))
       (values :wtf nil))

      (t (values :nxdomain nil)))))

(defun route-query (qname-labels)
  "Top-level router.  Returns (values keyword plist) where keyword is one of:
  :index :meta :msg :post-single :post-chunk :wtf :nxdomain"
  (let ((stripped (strip-zone qname-labels +zone+)))
    (if stripped
        (match-route stripped)
        (values :nxdomain nil))))
