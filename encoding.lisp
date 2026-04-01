(in-package #:dnsbbs)

;;;; Base32 (RFC 4648) — used for QNAME payload chunks.
;;;; DNS labels are case-insensitive, so base32 (A-Z2-7) is the right choice.

(defparameter +base32-alphabet+ "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

(defparameter +base32-decode-table+
  (let ((table (make-array 256 :element-type '(signed-byte 8) :initial-element -1)))
    (loop for i from 0 below (length +base32-alphabet+)
          for upper = (char +base32-alphabet+ i)
          for lower = (char (string-downcase (string upper)) 0)
          do (setf (aref table (char-code upper)) i)
             (setf (aref table (char-code lower)) i))
    table))

(defun base32-encode (bytes)
  "Encode a (vector (unsigned-byte 8)) to a base32 string (no '=' padding)."
  (let ((out (make-array (* 2 (length bytes))
                         :element-type 'character
                         :fill-pointer 0
                         :adjustable t))
        (bits 0)
        (bit-count 0))
    (loop for byte across bytes do
          (setf bits (logior (ash bits 8) byte))
          (incf bit-count 8)
          (loop while (>= bit-count 5) do
                (decf bit-count 5)
                (vector-push-extend
                 (char +base32-alphabet+ (ldb (byte 5 bit-count) bits))
                 out)))
    (when (> bit-count 0)
      (vector-push-extend
       (char +base32-alphabet+
             (ash (ldb (byte bit-count 0) bits) (- 5 bit-count)))
       out))
    (coerce out 'string)))

(defun base32-decode (string)
  "Decode a base32 string (case-insensitive, no padding required) to a byte vector."
  (let ((out (make-array (length string)
                         :element-type '(unsigned-byte 8)
                         :fill-pointer 0
                         :adjustable t))
        (bits 0)
        (bit-count 0))
    (loop for ch across string
          for val = (aref +base32-decode-table+ (char-code ch))
          do (when (= val -1)
               (error "Invalid base32 character: ~S" ch))
             (setf bits (logior (ash bits 5) val))
             (incf bit-count 5)
             (when (>= bit-count 8)
               (decf bit-count 8)
               (vector-push-extend (ldb (byte 8 bit-count) bits) out)))
    (coerce out '(vector (unsigned-byte 8)))))

;;;; Base64 — used for message body in TXT responses.

(defun b64-encode (string)
  "UTF-8 encode STRING then base64-encode to a string."
  (cl-base64:usb8-array-to-base64-string
   (babel:string-to-octets string :encoding :utf-8)))

(defun b64-decode (string)
  "Base64-decode STRING then UTF-8 decode to a string."
  (babel:octets-to-string
   (cl-base64:base64-string-to-usb8-array string)
   :encoding :utf-8))
