# Use latest support Python version with an Alpine base
FROM python:3.10-alpine

# Set necessary args for building
# If omitted, the versions are determined from the git tags
ARG TOR_BRANCH=0.4.8.14
ARG TOR_COMMIT_HASH=5d040a975df7a060d0fa6b491cbfd5de2667543b
ARG TORSOCKS_BRANCH=main
ARG TORSOCKS_COMMIT_HASH=37b6e5b2671783224fe84f8e115577bd6810a007
ARG NPROC

ENV HOME=/var/lib/tor
ENV POETRY_VIRTUALENVS_CREATE=false

# Upgrade base image
RUN apk --update --no-cache upgrade

# Install build and final dependencies
RUN apk add --update --no-cache \
    autoconf \
    automake \
    bind-tools \
    ca-certificates \
    cargo \
    coreutils \
    gcc \
    git \
    gnupg \
    libc-dev \
    libevent \
    libevent-dev \
    libffi-dev \
    libtool \
    linux-headers \
    make \
    musl-dev \
    openssl \
    openssl-dev \
    xz-dev \
    zstd-dev \
    zlib-dev \
    && pip3 install --upgrade pip poetry

    # Compile Tor binaries from source
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

# Compile Torsocks binaries from source
RUN git clone --branch $TORSOCKS_BRANCH https://gitlab.torproject.org/tpo/core/torsocks.git/ /usr/local/src/torsocks && \
    cd /usr/local/src/torsocks && \
    test `git rev-parse HEAD` = ${TORSOCKS_COMMIT_HASH} || exit 1 && \
    ./autogen.sh && \
    ./configure --disable-unittests && \
    make -j${NPROC:-$(nproc)} && make -j${NPROC:-$(nproc)} install && \
    cd .. && \
    rm -rf torsocks

RUN mkdir -p /etc/tor/

COPY pyproject.toml /usr/local/src/onions/

# Build and install `onions` tool
RUN cd /usr/local/src/onions && \
    poetry install --only main --no-root
COPY onions /usr/local/src/onions/onions
COPY poetry.lock /usr/local/src/onions/
RUN  cd /usr/local/src/onions && \
    poetry install --only main

# Cleanup packages that are not needed after build
RUN apk del \
    autoconf \
    automake \
    cargo \
    coreutils \
    gcc \
    git \
    gnupg \
    libc-dev \
    libevent-dev \
    libffi-dev \
    libtool \
    linux-headers \
    make \
    musl-dev \
    openssl-dev \
    xz-dev

# Create non-root user and home directories
RUN mkdir -p ${HOME}/.tor && \
    addgroup -S -g 107 tor && \
    adduser -S -G tor -u 104 -H -h ${HOME} tor

# Copy necessary configuration files from source
COPY assets/entrypoint-config.yml /
COPY assets/torrc /var/local/tor/torrc.tpl
COPY assets/vanguards.conf.tpl /var/local/tor/vanguards.conf.tpl

ENV VANGUARDS_CONFIG=/etc/tor/vanguards.conf

# Expose hidden_service directory for easy key backups
VOLUME ["/var/lib/tor/hidden_service/"]

ENTRYPOINT ["pyentrypoint"]

CMD ["tor"]
