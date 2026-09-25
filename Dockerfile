# Ubuntu 24.04 SSH coding workstation with MiniMax's mcode agent preinstalled.
# glibc (Debian/Ubuntu) base — Alpine/musl is NOT supported by mcode.
FROM ubuntu:24.04

ARG NODE_MAJOR=22
ARG MCODE_VERSION=0.5.4

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    # Literal defaults live in the image so template deploys stay zero-prompt.
    # (Railway injects its own PORT at runtime; the healthz stub follows it.)
    PORT=8000 \
    MCODE_MODEL=MiniMax-M3 \
    MCODE_PROVIDER_NAME=mm \
    MCODE_BASE_URL=https://api.minimax.io/anthropic

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        gnupg \
        openssh-server \
        git \
        zsh \
        python3 \
        python3-venv \
        build-essential \
        ripgrep \
        jq \
        unzip \
        zip \
        vim \
        less \
        procps \
        sudo \
        tini \
    && rm -rf /var/lib/apt/lists/*

# Node.js 22.x (mcode requires >=22.19 <23 || >=24 <27) from NodeSource.
RUN curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" -o /tmp/nodesource_setup.sh \
    && bash /tmp/nodesource_setup.sh \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -f /tmp/nodesource_setup.sh \
    && node --version \
    && npm --version

# MiniMax Code CLI, pinned. Binary: mcode. Data dir: ~/.minimax.
RUN npm install -g "@minimax-ai/code@${MCODE_VERSION}" \
    && mcode --version

# Non-root dev user (uid 1000) with passwordless sudo (single-user workstation).
RUN useradd -m -s /bin/bash -u 1000 dev \
    && echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev \
    && chmod 0440 /etc/sudoers.d/dev \
    && mkdir -p /home/dev/projects /home/dev/.ssh \
    && chown -R dev:dev /home/dev

# sshd hardening: key-only auth, no root login. Ubuntu's sshd_config includes
# sshd_config.d/*.conf with first-value-wins precedence.
RUN mkdir -p /run/sshd /opt/healthz \
    && printf '%s\n' \
        'PubkeyAuthentication yes' \
        'PasswordAuthentication no' \
        'KbdInteractiveAuthentication no' \
        'ChallengeResponseAuthentication no' \
        'PermitRootLogin no' \
        'PermitEmptyPasswords no' \
        'X11Forwarding no' \
        'PrintMotd no' \
        'UsePAM yes' \
        'ClientAliveInterval 60' \
        'ClientAliveCountMax 3' \
        > /etc/ssh/sshd_config.d/60-railway-workstation.conf \
    # pam_loginuid cannot set the audit session id in unprivileged containers.
    && sed -i 's/^session\s\+required\s\+pam_loginuid\.so/session optional pam_loginuid.so/' /etc/pam.d/sshd

# Login banner shown over SSH.
COPY motd.txt /etc/motd

COPY healthz.js /opt/healthz/server.js
COPY entrypoint.sh /opt/entrypoint.sh
RUN chmod 0755 /opt/entrypoint.sh /opt/healthz/server.js

EXPOSE 22 8000

ENTRYPOINT ["/usr/bin/tini", "--", "/opt/entrypoint.sh"]
