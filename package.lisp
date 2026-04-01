(defpackage #:dnsbbs
  (:use #:common-lisp)
  (:export
   ;; encoding
   #:base32-encode
   #:base32-decode
   #:b64-encode
   #:b64-decode
   ;; dns
   #:dns-parse-error
   #:dns-header
   #:dns-header-id
   #:dns-question
   #:dns-question-qname
   #:dns-question-qtype
   #:dns-question-qclass
   #:dns-request
   #:dns-request-header
   #:dns-request-question
   #:parse-dns-request
   #:build-dns-response
   #:format-txt-chunks
   #:+rcode-noerror+
   #:+rcode-nxdomain+
   #:+rcode-servfail+
   #:+rcode-notimp+
   ;; storage
   #:storage-error
   #:topic
   #:make-topic
   #:topic-name
   #:topic-desc
   #:topic-messages
   #:message
   #:make-message
   #:message-id
   #:message-author
   #:message-timestamp
   #:message-body
   #:list-topics
   #:get-topic
   #:create-topic
   #:get-message
   #:post-message
   #:topic-latest-id
   #:memory-store
   #:make-memory-store
   ;; router
   #:+zone+
   #:route-query
   ;; handlers
   #:handle-index
   #:handle-meta
   #:handle-msg
   #:handle-post-single
   #:handle-post-chunk
   ;; server
   #:dispatch
   #:run-server
   ;; main
   #:main))
