# Ubuntu + MiniMax Code — SSH Coding Workstation

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/ubuntu-minimax-template)

A persistent Ubuntu 24.04 SSH workstation with **MiniMax's `mcode` coding agent preinstalled** — bring your own MiniMax API key, SSH in from anywhere, and put the agent to work on real projects. Everything under the home directory lives on a persistent volume: your code, the agent's configuration, sessions, and shell history all survive restarts and redeploys.

## What you get

- **Ubuntu 24.04** (glibc — required by mcode) with OpenSSH: key-only auth, password and root login disabled
- **mcode** (MiniMax Code CLI, MIT, pinned at 0.5.4) on Node.js 22.x, installed globally — TUI plus headless `mcode exec` for scripts and CI
- **Non-root `dev` user** with passwordless sudo, `zsh`, `git`, `python3` + venv, `build-essential`, `ripgrep`, `jq`, `vim`
- **Persistent volume** at `/home/dev` — `~/projects`, `~/.minimax` (agent config + sessions), shell history
- **BYOK bootstrap**: set `MCODE_PROVIDER_API_KEY` and the agent is configured against MiniMax's Anthropic-compatible endpoint automatically at first boot (idempotent — changing the key later re-provisions on restart)
- **Health endpoint** `/healthz` on `$PORT` reporting sshd + mcode status as JSON (Railway healthchecks are HTTP-only; the stub watches the SSH daemon for you)

## Deploy-form variables

| Variable | What to enter |
|---|---|
| `PORT` | **8000** (the healthz stub port; keep the default from the docs) |

That is the only prompt. Your SSH key and API key are added after deploy (below) — nothing sensitive is baked into the template.

## Post-deploy setup (2 minutes)

1. **Add your SSH public key** — in your new project, open the service -> Variables -> add `SSH_PUBLIC_KEY` with the one-line contents of your `~/.ssh/id_ed25519.pub` (generate with `ssh-keygen -t ed25519` if needed). The service redeploys and installs it into `/home/dev/.ssh/authorized_keys`.
2. **SSH in** — the template provisions a TCP proxy for SSH. Its host and port are visible in Variables as `RAILWAY_TCP_PROXY_DOMAIN` and `RAILWAY_TCP_PROXY_PORT`:
   `ssh dev@$RAILWAY_TCP_PROXY_DOMAIN -p $RAILWAY_TCP_PROXY_PORT`
3. **Add your MiniMax API key** — Variables -> `MCODE_PROVIDER_API_KEY` (subscription key from platform.minimax.io) -> restart. The boot script configures and activates provider `mm` against `https://api.minimax.io/anthropic` with model `MiniMax-M3` (override with `MCODE_MODEL`: M2.7, M2.5, M2.1, M2 are also available). Or skip the variable and run `mcode provider add` interactively inside the box.
4. **Put the agent to work**:
   `mcode exec --permission full "write hello.py that prints hello world, then run it"`

## Cost

Roughly **$5–10/month** on Railway for the workstation (service + 5 GB volume, usage-based), plus your MiniMax Coding Plan or API usage. A full agent round-trip costs fractions of a cent.

# Deploy and Host

## About Hosting

One Railway service (Dockerfile build from the public repo), one persistent volume mounted at `/home/dev`, one Railway-provided HTTP domain routed to the healthz stub on `PORT` 8000, and one TCP proxy routed to sshd on port 22 for public SSH access. SSH host keys regenerate per redeploy (a one-time `known_hosts` update is expected); everything in the home volume persists. The service runs ~$5–10/mo at hobby scale plus your own MiniMax plan or API spend.

## Why Deploy

Hand-rolling this on a VPS means installing and hardening sshd, managing host keys, keeping a Node 22 runtime alive, and babysitting a box you pay for even when idle. This template ships it as one click: key-only SSH enforced by default, the mcode agent pinned and preinstalled, the home directory persistent across redeploys, and a health endpoint Railway can actually probe (HTTP) even though the real workload is SSH (TCP). Scale the service up or let it sleep — Railway handles the rest.

## Common Use Cases

- A personal cloud dev box for MiniMax's coding agent — drive `mcode` from a laptop, tablet, or phone SSH client
- Scripted/CI agent runs: `mcode exec` headless round-trips against your persistent `~/projects`
- BYOK agent workspaces for a team: one template deploy per member, each with their own key and volume
- A scratch Linux environment with compilers, Python, ripgrep, and git that never loses your files
- Long-running agent tasks in `tmux` that survive your laptop going offline

## Dependencies for

No external services are required — a single self-contained service plus its volume.

### Deployment Dependencies

- Railway template variables: `PORT` (enter 8000)
- Post-deploy service variables you supply: `SSH_PUBLIC_KEY` (your OpenSSH public key line), optionally `MCODE_PROVIDER_API_KEY` (MiniMax subscription key from platform.minimax.io), optionally `MCODE_MODEL` (default `MiniMax-M3`)
- An SSH client locally; MiniMax plan or API credits for agent usage
