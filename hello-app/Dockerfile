# Warms the same OS packages and compiler toolchain the session's
# compiled-language service needs. Same base image and the same apt-get
# install lines as the real thing (so Docker's build cache carries over on
# the day and that download-and-install step is already done); the source
# compiled here is a throwaway three-line placeholder, not the real program.

FROM debian:bookworm-slim AS build

RUN apt-get update \
    && apt-get install -y --no-install-recommends gnucobol3 libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY hello.cob .
RUN mkdir -p out && cobc -x -fstatic-call -o out/hello hello.cob


FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends lighttpd libcob4 libpq5 curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/www/html/cgi-bin /var/lib/tut-work \
    && chown www-data:www-data /var/lib/tut-work \
    && chmod 700 /var/lib/tut-work

COPY --from=build /build/out/hello /usr/local/bin/hello
CMD ["sh", "-c", "/usr/local/bin/hello; echo ARCH=$(uname -m)"]
