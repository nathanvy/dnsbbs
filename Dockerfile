FROM clfoundation/sbcl:latest
ARG QUICKLISP_ADD_TO_INIT_FILE=true

WORKDIR /app
COPY . /app

RUN set -x; \
  /usr/local/bin/install-quicklisp

RUN ln -s /app /root/quicklisp/local-projects/dnsbbs

EXPOSE 31337/udp

CMD ["sbcl", "--load", "loader.lisp"]
