FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    nasm \
    llvm \
    lld \
    grub-pc-bin \
    grub-common \
    mtools \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
