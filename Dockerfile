FROM clfoundation/sbcl:latest

# Install Quicklisp
RUN curl -fsSL https://beta.quicklisp.org/quicklisp.lisp -o /tmp/quicklisp.lisp && \
    sbcl --non-interactive \
         --load /tmp/quicklisp.lisp \
         --eval '(quicklisp-quickstart:install :path "/root/quicklisp/")' \
    rm /tmp/quicklisp.lisp

WORKDIR /app
COPY . .

RUN ln -s /app /root/quicklisp/local-projects/dnsbbs

EXPOSE 31337/udp

CMD ["sbcl", "--load", "loader.lisp"]
