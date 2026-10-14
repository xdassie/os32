FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    nasm \
    llvm \
    lld \
    gcc \
    gcc-multilib \
    libc6-dev-i386 \
    musl-tools \
    grub-pc-bin \
    grub-common \
    mtools \
    xorriso \
    syslinux \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain nightly
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

COPY targets/i686-unknown-none.json /rust-target.json
RUN rustup component add rust-src
