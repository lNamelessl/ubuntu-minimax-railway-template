# Ubuntu + MiniMax Code — SSH Coding Workstation (Railway Template)

One-click Railway template for a **persistent Ubuntu 24.04 SSH workstation with MiniMax's `mcode` coding agent preinstalled** — bring your own MiniMax API key, SSH in from anywhere, and put the agent to work.

- **Ubuntu 24.04** (glibc — required by mcode; no Alpine/musl) + **OpenSSH**, key-only auth
- **mcode** (MiniMax Code CLI, `@minimax-ai/code`, MIT) pinned at `0.5.4`, Node.js 22.x (mcode requires 22.19+)
- **Persistent volume** on `/home/dev` — projects, `~/.minimax` config/sessions and shell history survive restarts and redeploys
- **BYOK bootstrap**: set `MCODE_PROVIDER_API_KEY` and the provider is configured automatically at boot; no key yet? The workstation is still healthy — configure interactively on first SSH
- **Health endpoint** `/healthz` on `$PORT` (JSON: sshd up? mcode present?) — Railway healthchecks are HTTP-only, so the stub watches sshd for you

## The 3-step flow

1. **Add your SSH public key** — Railway project -> your service -> Variables -> `SSH_PUBLIC_KEY` = the contents of your `~/.ssh/id_ed25519.pub` (the `ssh-ed25519 AAAA... comment` line). Generate one if needed:

   ```bash
   ssh-keygen -t ed25519 -C "railway-workstation"
   cat ~/.ssh/id_ed25519.pub   # paste this into SSH_PUBLIC_KEY
   ```

2. **(Optional, can be done later) Add your MiniMax API key** — Variables -> `MCODE_PROVIDER_API_KEY`. Get a subscription key at [platform.minimax.io](https://platform.minimax.io). Then restart the service. The boot script runs the BYOK config for you (idempotent — it never overwrites an existing provider).

3. **Deploy, then SSH in** — Railway gives the service a TCP proxy for SSH (host + port are visible in the service's Settings or as `RAILWAY_TCP_PROXY_DOMAIN` / `RAILWAY_TCP_PROXY_PORT` in Variables):

   ```bash
   ssh dev@<RAILWAY_TCP_PROXY_DOMAIN> -p <RAILWAY_TCP_PROXY_PORT>
   ```

First thing inside, sanity-check the agent:

```bash
mcode --version
mcode exec "write hello.py that prints hello world, then run it"
```

Headless `mcode exec` is perfect for scripts/CI; plain `mcode` opens the interactive TUI.

## Variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `SSH_PUBLIC_KEY` | for SSH access | empty | Public key(s), one per line, installed into `/home/dev/.ssh/authorized_keys` at boot. Password auth is disabled. |
| `MCODE_PROVIDER_API_KEY` | for agent use | empty | Your MiniMax subscription key. Present at boot -> provider `mm` is configured and activated automatically. Config stores the env-var *name*, so rotating the key needs no re-config — just change the variable. |
| `MCODE_MODEL` | no | `MiniMax-M3` | Model passed to the provider config. Alternatives: `MiniMax-M2.7`, `MiniMax-M2.5`, `MiniMax-M2.1`, `MiniMax-M2` (see [MiniMax models](https://platform.minimax.io/docs/guides/text-generation)). |
| `MCODE_PROVIDER_NAME` | no | `mm` | Name of the auto-created provider profile. |
| `MCODE_BASE_URL` | no | `https://api.minimax.io/anthropic` | Any Anthropic-compatible endpoint works (`anthropic-messages` format). Point it at a relay/self-hosted gateway if you like. |
| `PORT` | keep default | `8000` | healthz stub port (Railway routes its HTTP healthcheck here). |

## BYOK, two ways

**Automatic (recommended):** set `MCODE_PROVIDER_API_KEY` before/after deploy and restart. The entrypoint runs, as the `dev` user:

```bash
mcode provider add --name mm \
  --base-url https://api.minimax.io/anthropic \
  --api-format anthropic-messages --model MiniMax-M3 \
  --api-key-env MCODE_PROVIDER_API_KEY --use
```

**Interactive:** SSH in and run the same command yourself (or use `mcode`'s built-in MiniMax Coding Plan browser login). Provider config persists in `~/.minimax/config.yaml` on the volume.

## What's inside

- Base `ubuntu:24.04`, non-root `dev` user (uid 1000, passwordless sudo), `zsh`, `git`, `python3` (+ venv), `build-essential`, `ripgrep`, `jq`, `vim`
- Node.js 22.x from NodeSource; `@minimax-ai/code@0.5.4` installed globally (binary: `mcode`)
- sshd hardened via `sshd_config.d`: `PasswordAuthentication no`, `PermitRootLogin no`, pubkey only, client keepalives
- Entrypoint: seeds the empty volume on first boot, installs `authorized_keys` from `SSH_PUBLIC_KEY`, writes mcode runtime vars to `/etc/environment` (SSH sessions don't inherit container env), runs the idempotent provider bootstrap, then starts the healthz stub and `sshd -D`
- `/healthz` on `$PORT` returns 200 only when sshd accepts connections on 22 AND `mcode --version` runs

## Persistence notes

The volume mounts `/home/dev`. Everything under it — `~/projects`, `~/.minimax` (config, sessions, auth), shell history — survives restarts, redeploys and crashes. SSH **host keys** live outside the volume and are regenerated on redeploy, so expect a one-time `known_hosts` warning after infrastructure updates.

## Cost

Workstation: roughly **$5–10/month** on Railway (service + 5 GB volume, scales with usage). Agent usage: your MiniMax Coding Plan or API spend — a full `mcode exec` round-trip costs fractions of a cent on MiniMax's pricing.

## Troubleshooting

- **`Permission denied (publickey)`** — `SSH_PUBLIC_KEY` missing/wrong, or the service wasn't restarted after setting it. The key must be the *public* key line. Fingerprint shows in deploy logs at boot. Only the `dev` user is admitted; root login is refused.
- **`mcode: command not found` / wrong Node** — the image pins Node 22 and mcode 0.5.4; check `/healthz` shows the mcode version, and `mcode --version` inside the box.
- **Agent auth errors in `mcode`** — the provider wasn't configured: confirm `MCODE_PROVIDER_API_KEY` is set and restart, or run the `mcode provider add ...` command above interactively; check `mcode provider list` / `mcode provider test mm`.
- **Model not found / 404 from the API** — update `MCODE_MODEL` (MiniMax rotates model names; delete `~/.minimax/config.yaml` provider block or re-run `mcode provider add` with the new name after changing the variable).
- **Files vanished after redeploy** — make sure the volume is still attached to the service at `/home/dev`; data outside `/home/dev` (e.g. `/root`, `/tmp`) is ephemeral.
- **SSH connection drops** — keepalives are on (60s); long-running work belongs in `tmux`/`screen` (install with `sudo apt install tmux`).
- **Changed `MCODE_MODEL`/`MCODE_BASE_URL` but nothing happened** — provider config is applied once; re-run `mcode provider add ... --use` interactively to overwrite, or wipe `~/.minimax/config.yaml` and restart.

## Links

- mcode upstream: <https://github.com/MiniMax-AI/minimax-code> (MIT)
- npm: <https://www.npmjs.com/package/@minimax-ai/code>
- MiniMax platform / API keys: <https://platform.minimax.io>
- mcode quick start: <https://agent.minimax.io/docs/cli/quick-start>

## License

MIT — see [LICENSE](LICENSE). Upstream mcode is MIT (c) MiniMax-AI.
