# syntax=docker/dockerfile:1

FROM docker.io/library/debian:13-slim

ARG S6_OVERLAY_VERSION=3.2.3.2
ARG S6_URL=https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}

LABEL org.opencontainers.image.source="https://github.com/alexdelprete/pbs-docker"
LABEL org.opencontainers.image.description="Proxmox Backup Server from the official Proxmox trixie packages, supervised by s6-overlay"
LABEL org.opencontainers.image.licenses="MIT"

# s6-overlay, checksums pinned to the release assets
ADD --checksum=sha256:5379750ed30a84bbd2e2dd74847ba6b5bd29cd0b2e3ea2ec58049b57eb2eda12 \
    ${S6_URL}/s6-overlay-noarch.tar.xz /tmp/
ADD --checksum=sha256:e6befcc96a437a3831386ecfc51808c5d3e939dc5fe3c02ae9284599e8aa2408 \
    ${S6_URL}/s6-overlay-x86_64.tar.xz /tmp/
ADD --checksum=sha256:a215675c375aca9efecde3065df22b19fb8dcdc1362566931c6b5e778099a0fb \
    ${S6_URL}/s6-overlay-symlinks-noarch.tar.xz /tmp/
ADD --checksum=sha256:6251226709efc0c88800a8c140404d93b391e1b4051ef50fa0e8aac1fdcf738c \
    ${S6_URL}/s6-overlay-symlinks-arch.tar.xz /tmp/
ADD --checksum=sha256:7d94a01ca36db0f7659ab90301b6b7aff6d0fc786f2271873c9b77ac27f02921 \
    ${S6_URL}/syslogd-overlay-noarch.tar.xz /tmp/

RUN set -eu \
    && apt-get -qy update \
    && apt-get install -qy --no-install-recommends xz-utils \
    && for f in s6-overlay-noarch s6-overlay-x86_64 s6-overlay-symlinks-noarch s6-overlay-symlinks-arch syslogd-overlay-noarch; do \
         tar -C / -Jxpf "/tmp/${f}.tar.xz"; \
       done \
    && rm -f /tmp/*.tar.xz \
    && mkdir -p /etc/s6-overlay/user-bundles.d/user/contents.d \
    && mv /etc/s6-overlay/s6-rc.d/user/contents.d/* /etc/s6-overlay/user-bundles.d/user/contents.d/ \
    && rm -rf /etc/s6-overlay/s6-rc.d/user \
    && groupadd -r syslog && useradd -r -g syslog -s /usr/sbin/nologin syslog \
    && groupadd -r sysllog && useradd -r -g sysllog -s /usr/sbin/nologin sysllog

# Proxmox Backup Server, official repository
ADD --chmod=0644 \
    https://enterprise.proxmox.com/debian/proxmox-release-trixie.gpg \
    /usr/share/keyrings/proxmox-archive-keyring.gpg

COPY <<EOT /etc/apt/sources.list.d/proxmox.sources
Types: deb
URIs: http://download.proxmox.com/debian/pbs
Suites: trixie
Components: pbs-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOT

ARG DEBIAN_FRONTEND=noninteractive
RUN set -eu \
    && apt-get -qy update \
    && apt-get install -qy --no-install-recommends \
        curl \
        proxmox-archive-keyring \
        proxmox-backup-server \
        tzdata \
    && rm -f /etc/apt/sources.list.d/pbs-enterprise.sources \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man

COPY root/ /
RUN chmod +x /etc/s6-overlay/s6-rc.d/*/run

ENV TZ=Europe/Rome \
    S6_LOGGING=0 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_CMD_WAIT_FOR_SERVICES_MAXTIME=120000 \
    S6_KILL_GRACETIME=5000

EXPOSE 8007

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD curl -kfsS -o /dev/null https://127.0.0.1:8007/ || exit 1

ENTRYPOINT ["/init"]
