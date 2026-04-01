(asdf:defsystem #:dnsbbs
  :description "A BBS system hidden in DNS TXT records"
  :version     "0.1.0"
  :license     "MIT"
  :depends-on  (#:usocket #:babel #:cl-base64 #:local-time)
  :serial      t
  :components  ((:file "package")
                (:file "encoding")
                (:file "dns")
                (:file "storage")
                (:file "handlers")
                (:file "router")
                (:file "server")
                (:file "main")))
