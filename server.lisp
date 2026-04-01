(in-package #:dnsbbs)

;;;; Reactor server: single-threaded UDP event loop using usocket.

(defun log-msg (fmt &rest args)
  (apply #'format *error-output*
         (concatenate 'string "~&[dnsbbs] " fmt "~%")
         args)
  (force-output *error-output*))

(defun ip-to-string (addr)
  "Convert a usocket IP address (vector or string) to a dotted-decimal string."
  (etypecase addr
    (string addr)
    (vector (format nil "~{~A~^.~}" (coerce addr 'list)))))

(defun dispatch (request store client-ip)
  "Route REQUEST to the appropriate handler and return a DNS response byte vector.
  CLIENT-IP is a string used as a key for multi-chunk post session state."
  (let* ((q      (dns-request-question request))
         (qtype  (dns-question-qtype q))
         (qclass (dns-question-qclass q))
         (qname  (dns-question-qname q)))
    ;; Only handle TXT (16) IN (1) queries.
    (unless (and (= qtype 16) (= qclass 1))
      (return-from dispatch
        (build-dns-response request nil +rcode-notimp+)))
    (handler-case
        (multiple-value-bind (handler args)
            (route-query qname)
          (let ((result
                 (case handler
                   (:nxdomain  :nxdomain)
                   (:index
                    (handle-index store (getf args :page)))
                   (:meta
                    (handle-meta store (getf args :topic)))
                   (:msg
                    (handle-msg store
                                (getf args :topic)
                                (getf args :id)
                                (getf args :page)))
                   (:post-single
                    (handle-post-single store
                                        (getf args :topic)
                                        client-ip
                                        (getf args :payload)))
                   (:post-chunk
                    (handle-post-chunk store
                                       (getf args :topic)
                                       client-ip
                                       (getf args :payload)
                                       (getf args :seq)))
                   (t :nxdomain))))
            (if (eq result :nxdomain)
                (build-dns-response request nil +rcode-nxdomain+)
                (build-dns-response request result +rcode-noerror+))))
      (error (e)
        (log-msg "SERVFAIL dispatching ~{~A~^.~}: ~A" qname e)
        (build-dns-response request nil +rcode-servfail+)))))

(defun run-server (store &key (port 5353))
  "Start the UDP DNS server on PORT (default 5353).
  Blocks indefinitely, processing one datagram at a time."
  (log-msg "Starting DNSBBS on UDP port ~A (zone: ~{~A~^.~})" port +zone+)
  (let* ((socket (usocket:socket-connect
                  nil nil
                  :protocol   :datagram
                  :local-host "0.0.0.0"
                  :local-port port
                  :element-type '(unsigned-byte 8)))
         (recv-buf (make-array 512 :element-type '(unsigned-byte 8))))
    (unwind-protect
         (loop
           ;; Wait up to 1 second for a datagram to arrive.
           (when (usocket:wait-for-input socket :timeout 1 :ready-only t)
             (handler-case
                 (multiple-value-bind (buf len remote-host remote-port)
                     (usocket:socket-receive socket recv-buf 512)
                   (declare (ignore buf))
                   (when (and len (> len 0))
                     (let* ((packet    (subseq recv-buf 0 len))
                            (client-ip (ip-to-string remote-host))
                            (request   (parse-dns-request packet))
                            (response  (dispatch request store client-ip)))
                       (usocket:socket-send socket response (length response)
                                            :host remote-host
                                            :port remote-port))))
               (dns-parse-error (e)
                 (log-msg "Malformed DNS packet from client: ~A" e))
               (error (e)
                 (log-msg "Unhandled error in receive loop: ~A" e)))))
      (usocket:socket-close socket)
      (log-msg "Server stopped."))))
