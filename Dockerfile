FROM python:3.10-alpine

# if omitted, the versions are determined from the git tags
ARG TOR_BRANCH=0.4.8.14
ARG TOR_COMMIT_HASH=5d040a975df7a060d0fa6b491cbfd5de2667543b
ARG TORSOCKS_BRANCH=v2.4.0
ARG TORSOCKS_COMMIT_HASH=afe9dea542a8b495dbbbbe5e4b98a33cde06729b
ARG NPROC

ENV HOME=/var/lib/tor
ENV POETRY_VIRTUALENVS_CREATE=false

# Upgrade base image
RUN set -ex && apk --update --no-cache upgrade

# Install build and final dependencies
RUN apk add --update --no-cache git bind-tools cargo zstd-dev xz-dev libc-dev libevent-dev openssl-dev gnupg gcc make automake ca-certificates autoconf musl-dev coreutils libffi-dev zlib-dev libevent openssl libtool && \
    pip3 install --upgrade pip poetry

RUN mkdir -p /usr/local/src/ /var/lib/tor/ && \
    git clone --branch tor-$TOR_BRANCH https://gitlab.torproject.org/tpo/core/tor.git/ /usr/local/src/tor && \
    cd /usr/local/src/tor && \
    test `git rev-parse HEAD` = ${TOR_COMMIT_HASH} || exit 1 && \
    ./autogen.sh && \
    ./configure \
    --disable-asciidoc \
    --sysconfdir=/etc \
    --disable-unittests && \
    make -j${NPROC:-$(nproc)} && make -j${NPROC:-$(nproc)} install && \
    cd .. && \
    rm -rf tor

RUN git clone --branch $TORSOCKS_BRANCH https://gitlab.torproject.org/tpo/core/torsocks.git/ /usr/local/src/torsocks && \
    cd /usr/local/src/torsocks && \
    test `git rev-parse HEAD` = ${TORSOCKS_COMMIT_HASH} || exit 1 && \
    ./autogen.sh && \
    ./configure && \
    make -j${NPROC:-$(nproc)} && make -j${NPROC:-$(nproc)} install && \
    cd .. && \
    rm -rf torsocks

RUN mkdir -p /etc/tor/

COPY pyproject.toml /usr/local/src/onions/

RUN cd /usr/local/src/onions && \
    poetry install --only main --no-root

COPY onions /usr/local/src/onions/onions
COPY poetry.lock /usr/local/src/onions/
RUN  cd /usr/local/src/onions && \
    poetry install --only main

# Cleanup packages that are not needed after build
RUN apk del git gcc make automake autoconf musl-dev libtool xz-dev libc-dev libevent-dev openssl-dev gnupg cargo coreutils libffi-dev

RUN mkdir -p ${HOME}/.tor && \
    addgroup -S -g 107 tor && \
    adduser -S -G tor -u 104 -H -h ${HOME} tor

COPY assets/entrypoint-config.yml /
COPY assets/torrc /var/local/tor/torrc.tpl
COPY assets/vanguards.conf.tpl /var/local/tor/vanguards.conf.tpl

ENV VANGUARDS_CONFIG=/etc/tor/vanguards.conf

VOLUME ["/var/lib/tor/hidden_service/"]

ENTRYPOINT ["pyentrypoint"]

CMD ["tor"]
