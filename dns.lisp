(in-package #:dnsbbs)

;;;; DNS wire format: parsing requests and building TXT responses.
;;;; Implements a subset of RFC 1035 sufficient for a UDP TXT-only server.

;;; Conditions

(define-condition dns-parse-error (error)
  ((message :initarg :message :reader dns-parse-error-message))
  (:report (lambda (c s)
             (format s "DNS parse error: ~A" (dns-parse-error-message c)))))

;;; RCODE constants

(defconstant +rcode-noerror+  0)
(defconstant +rcode-servfail+ 2)
(defconstant +rcode-nxdomain+ 3)
(defconstant +rcode-notimp+   4)

;;; Structs

(defstruct dns-header
  id qr opcode aa tc rd ra rcode qdcount ancount)

(defstruct dns-question
  qname   ; list of label strings, left-to-right
  qtype
  qclass)

(defstruct dns-request
  header
  question
  raw)    ; original bytes, not currently used but useful for debugging

;;; Low-level byte helpers

(defun u16-be (buf offset)
  (logior (ash (aref buf offset) 8)
          (aref buf (1+ offset))))

(defun write-u16-be (val)
  (vector (ldb (byte 8 8) val)
          (ldb (byte 8 0) val)))

(defun write-u32-be (val)
  (vector (ldb (byte 8 24) val)
          (ldb (byte 8 16) val)
          (ldb (byte 8  8) val)
          (ldb (byte 8  0) val)))

(defun concat-bytes (&rest seqs)
  "Concatenate byte vectors/arrays into a single (vector (unsigned-byte 8))."
  (let* ((total (reduce #'+ seqs :key #'length :initial-value 0))
         (out   (make-array total :element-type '(unsigned-byte 8)))
         (pos   0))
    (dolist (s seqs out)
      (loop for b across s do
            (setf (aref out pos) b)
            (incf pos)))))

;;; Parsing

(defun parse-dns-header (buf offset)
  "Parse the 12-byte DNS header. Returns (values dns-header new-offset)."
  (when (< (length buf) (+ offset 12))
    (error 'dns-parse-error :message "Buffer too short for DNS header"))
  (let* ((id      (u16-be buf offset))
         (flags   (u16-be buf (+ offset 2)))
         (qdcount (u16-be buf (+ offset 4)))
         (ancount (u16-be buf (+ offset 6))))
    (values
     (make-dns-header
      :id      id
      :qr      (ldb (byte 1 15) flags)
      :opcode  (ldb (byte 4 11) flags)
      :aa      (ldb (byte 1 10) flags)
      :tc      (ldb (byte 1  9) flags)
      :rd      (ldb (byte 1  8) flags)
      :ra      (ldb (byte 1  7) flags)
      :rcode   (ldb (byte 4  0) flags)
      :qdcount qdcount
      :ancount ancount)
     (+ offset 12))))

(defun parse-qname (buf offset)
  "Parse a DNS QNAME (length-prefixed labels). Returns (values label-list new-offset).
  Pointer compression is not supported (not needed for client queries)."
  (let ((labels '())
        (pos offset))
    (loop
      (when (>= pos (length buf))
        (error 'dns-parse-error :message "QNAME extends past buffer end"))
      (let ((len (aref buf pos)))
        (incf pos)
        (when (= len 0) (return))
        (when (= (logand len #xc0) #xc0)
          (error 'dns-parse-error :message "QNAME pointer compression not supported"))
        (when (> (+ pos len) (length buf))
          (error 'dns-parse-error :message "QNAME label extends past buffer end"))
        (push (babel:octets-to-string buf :start pos :end (+ pos len) :encoding :ascii)
              labels)
        (incf pos len)))
    (values (nreverse labels) pos)))

(defun parse-dns-question (buf offset)
  "Parse the question section. Returns (values dns-question new-offset)."
  (multiple-value-bind (qname pos)
      (parse-qname buf offset)
    (when (< (length buf) (+ pos 4))
      (error 'dns-parse-error :message "Buffer too short for QTYPE/QCLASS"))
    (values
     (make-dns-question
      :qname  qname
      :qtype  (u16-be buf pos)
      :qclass (u16-be buf (+ pos 2)))
     (+ pos 4))))

(defun parse-dns-request (buf)
  "Top-level entry: parse a raw UDP payload into a dns-request.
  Signals dns-parse-error on malformed input."
  (multiple-value-bind (header q-offset)
      (parse-dns-header buf 0)
    (multiple-value-bind (question _)
        (parse-dns-question buf q-offset)
      (declare (ignore _))
      (make-dns-request :header header :question question :raw buf))))

;;; Response building

(defun encode-qname (labels)
  "Encode a list of label strings into DNS wire-format QNAME bytes."
  (let ((out (make-array 64 :element-type '(unsigned-byte 8)
                            :fill-pointer 0 :adjustable t)))
    (dolist (label labels)
      (let ((bytes (babel:string-to-octets label :encoding :ascii)))
        (vector-push-extend (length bytes) out)
        (loop for b across bytes do (vector-push-extend b out))))
    (vector-push-extend 0 out)
    (coerce out '(vector (unsigned-byte 8)))))

(defun format-txt-chunks (value-string)
  "Split VALUE-STRING into a list of strings, each whose UTF-8 encoding is ≤ 255 bytes.
  Splits on UTF-8 character boundaries."
  (let ((bytes (babel:string-to-octets value-string :encoding :utf-8)))
    (if (<= (length bytes) 255)
        (list value-string)
        (let ((chunks '())
              (start  0)
              (total  (length bytes)))
          (loop while (< start total) do
                (let ((end (min (+ start 255) total)))
                  ;; Back up to a valid UTF-8 start byte (not a continuation byte 10xxxxxx)
                  (loop while (and (> end start)
                                   (= (logand (aref bytes (1- end)) #xc0) #x80))
                        do (decf end))
                  (push (babel:octets-to-string bytes :start start :end end
                                                      :encoding :utf-8)
                        chunks)
                  (setf start end)))
          (nreverse chunks)))))

(defun encode-txt-rdata (string)
  "Encode a single string as TXT RDATA: a 1-byte length prefix followed by UTF-8 bytes.
  The string must encode to ≤ 255 bytes in UTF-8."
  (let ((bytes (babel:string-to-octets string :encoding :utf-8)))
    (when (> (length bytes) 255)
      (error "TXT string segment too long (~A bytes)" (length bytes)))
    (concat-bytes (vector (length bytes)) bytes)))

(defun encode-rr (qname-labels qtype qclass ttl rdata-bytes)
  "Encode a single DNS resource record in wire format."
  (concat-bytes
   (encode-qname qname-labels)
   (write-u16-be qtype)
   (write-u16-be qclass)
   (write-u32-be ttl)
   (write-u16-be (length rdata-bytes))
   rdata-bytes))

(defun build-dns-response (request txt-strings rcode)
  "Build a complete DNS UDP response byte vector.

  TXT-STRINGS is a list of strings (each ≤ 255 UTF-8 bytes), one per answer RR.
  RCODE is one of the +rcode-*+ constants.

  Enforces the 512-byte UDP limit: if adding an RR would exceed 512 bytes,
  it is dropped and TC=1 is set in the response header."
  (let* ((hdr  (dns-request-header request))
         (q    (dns-request-question request))
         ;; Question section bytes (re-encoded verbatim)
         (qname-enc    (encode-qname (dns-question-qname q)))
         (question-enc (concat-bytes qname-enc
                                     (write-u16-be (dns-question-qtype q))
                                     (write-u16-be (dns-question-qclass q))))
         ;; Budget: 512 total - 12 header - question section
         (budget    (- 512 12 (length question-enc)))
         (tc        0)
         (used      0)
         (answer-rrs '()))
    ;; Build and accumulate answer RRs for NOERROR responses
    (when (= rcode +rcode-noerror+)
      (dolist (s txt-strings)
        (let* ((rdata (encode-txt-rdata s))
               (rr    (encode-rr (dns-question-qname q)
                                 16 1 0   ; TXT IN TTL=0
                                 rdata))
               (rr-len (length rr)))
          (if (<= (+ used rr-len) budget)
              (progn (push rr answer-rrs) (incf used rr-len))
              (progn (setf tc 1) (return))))))
    (setf answer-rrs (nreverse answer-rrs))
    ;; Flags: QR=1 AA=1 TC=tc RCODE=rcode
    (let* ((flags (logior #x8400          ; QR=1 AA=1
                          (ash tc 9)
                          rcode))
           (header-bytes
            (concat-bytes
             (write-u16-be (dns-header-id hdr))
             (write-u16-be flags)
             (write-u16-be 1)                       ; QDCOUNT
             (write-u16-be (length answer-rrs))     ; ANCOUNT
             (write-u16-be 0)                       ; NSCOUNT
             (write-u16-be 0))))                    ; ARCOUNT
      (apply #'concat-bytes header-bytes question-enc answer-rrs))))
