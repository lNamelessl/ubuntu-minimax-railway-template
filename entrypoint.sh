#!/bin/bash
# Boot sequence for the Ubuntu + mcode SSH workstation.
# 1. sshd host keys + runtime dir
# 2. Seed /home/dev on first boot (volume may start empty)
# 3. authorized_keys from SSH_PUBLIC_KEY (key-only auth)
# 4. Export mcode runtime vars into /etc/environment (SSH sessions get them via pam_env)
# 5. BYOK bootstrap: mcode provider add when MCODE_PROVIDER_API_KEY is present (idempotent)
# 6. healthz stub on $PORT + sshd in foreground
set -euo pipefail

log() { echo "[entrypoint] $(date -u +%H:%M:%S) $*"; }

export PORT="${PORT:-8000}"
MCODE_PROVIDER_NAME="${MCODE_PROVIDER_NAME:-mm}"
MCODE_BASE_URL="${MCODE_BASE_URL:-https://api.minimax.io/anthropic}"
MCODE_MODEL="${MCODE_MODEL:-MiniMax-M3}"

# --- 1. sshd setup -----------------------------------------------------------
mkdir -p /run/sshd
if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
    log "generating SSH host keys"
    ssh-keygen -A
fi

# --- 2. Seed home volume (first boot only) -----------------------------------
if [ ! -e /home/dev/.railway-seeded ]; then
    log "seeding /home/dev (first boot)"
    cp -a /etc/skel/. /home/dev/ 2>/dev/null || true
    mkdir -p /home/dev/projects /home/dev/.ssh
    # Keep mcode sessions/config and shell history on the persistent volume.
    touch /home/dev/.bash_history /home/dev/.railway-seeded
    chown -R dev:dev /home/dev
fi
mkdir -p /home/dev/.ssh /home/dev/projects
chown dev:dev /home/dev/.ssh /home/dev/projects

# --- 3. authorized_keys from env (key-only auth) ------------------------------
if [ -n "${SSH_PUBLIC_KEY:-}" ]; then
    printf '%s\n' "$SSH_PUBLIC_KEY" > /home/dev/.ssh/authorized_keys
    log "authorized_keys installed from SSH_PUBLIC_KEY (${SSH_PUBLIC_KEY%% *}, fingerprint below)"
    ssh-keygen -lf /home/dev/.ssh/authorized_keys 2>/dev/null || true
else
    : > /home/dev/.ssh/authorized_keys
    log "WARN: SSH_PUBLIC_KEY not set — SSH login is locked until you add your public key"
    log "      (Variables -> SSH_PUBLIC_KEY = \"\$(cat ~/.ssh/id_ed25519.pub)\" -> restart)"
fi
chmod 700 /home/dev/.ssh
chmod 600 /home/dev/.ssh/authorized_keys
chown dev:dev /home/dev/.ssh /home/dev/.ssh/authorized_keys

# --- 4. Runtime env for SSH login sessions (sshd does not inherit container env)
{
    echo "MCODE_MODEL=${MCODE_MODEL}"
    echo "MCODE_PROVIDER_NAME=${MCODE_PROVIDER_NAME}"
    if [ -n "${MCODE_PROVIDER_API_KEY:-}" ]; then
        echo "MCODE_PROVIDER_API_KEY=${MCODE_PROVIDER_API_KEY}"
    fi
} > /etc/environment
chmod 600 /etc/environment

# --- 5. BYOK bootstrap (idempotent) -------------------------------------------
# The provider config stores the *name* of the env var (--api-key-env), not the
# key itself, so rotating MCODE_PROVIDER_API_KEY needs no config change.
provider_configured() {
    [ -f /home/dev/.minimax/config.yaml ] \
        && grep -q "name: ${MCODE_PROVIDER_NAME}\b" /home/dev/.minimax/config.yaml
}

if [ -n "${MCODE_PROVIDER_API_KEY:-}" ]; then
    if provider_configured; then
        log "mcode provider '${MCODE_PROVIDER_NAME}' already configured — skipping"
    else
        log "configuring mcode provider '${MCODE_PROVIDER_NAME}' -> ${MCODE_BASE_URL} (${MCODE_MODEL})"
        if runuser -u dev -- /usr/bin/env HOME=/home/dev \
            /usr/bin/mcode provider add \
                --name "$MCODE_PROVIDER_NAME" \
                --base-url "$MCODE_BASE_URL" \
                --api-format anthropic-messages \
                --model "$MCODE_MODEL" \
                --api-key-env MCODE_PROVIDER_API_KEY \
                --use; then
            log "provider configured and set active"
        else
            log "WARN: mcode provider add failed (exit $?) — agent still installed;"
            log "      run it manually after SSH: mcode provider add --help"
        fi
    fi
else
    log "MCODE_PROVIDER_API_KEY not set — agent installed, no provider configured (healthy)"
    log "      add your key (Variables -> MCODE_PROVIDER_API_KEY) and restart, or run"
    log "      'mcode provider add' interactively after SSH (see README)"
fi

# --- 6. Launch healthz + sshd -------------------------------------------------
log "starting healthz on :${PORT} and sshd on :22"
node /opt/healthz/server.js &
HEALTH_PID=$!
/usr/sbin/sshd -D -e &
SSHD_PID=$!

shutdown() {
    kill "$HEALTH_PID" "$SSHD_PID" 2>/dev/null || true
    exit 0
}
trap shutdown TERM INT

set +e
wait -n
STATUS=$?
set -e
log "a required process exited (status ${STATUS}) — shutting down for restart"
shutdown
