FROM clfoundation/sbcl:latest

# Install Quicklisp
RUN curl -fsSL https://beta.quicklisp.org/quicklisp.lisp -o /tmp/quicklisp.lisp && \
    sbcl --non-interactive \
         --load /tmp/quicklisp.lisp \
         --eval '(quicklisp-quickstart:install :path "/root/quicklisp/")' \
         --eval '(ql:add-to-init-file)' && \
    rm /tmp/quicklisp.lisp

WORKDIR /app
COPY . .

# Symlink project into Quicklisp local-projects, load deps, and build executable
RUN ln -s /app /root/quicklisp/local-projects/dnsbbs && \
    sbcl --non-interactive \
         --eval '(ql:quickload :dnsbbs)' \
         --eval "(sb-ext:save-lisp-and-die \"/app/dnsbbs\" :toplevel #'dnsbbs:main :executable t)"

EXPOSE 31337/udp

CMD ["/app/dnsbbs"]
