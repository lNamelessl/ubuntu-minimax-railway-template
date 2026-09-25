// healthz stub: Railway healthchecks are HTTP-only, but this container's real
// workload is sshd (TCP 22). This tiny server on $PORT reports both.
'use strict';
const http = require('http');
const net = require('net');
const { execFileSync } = require('child_process');

const PORT = parseInt(process.env.PORT || '8000', 10);
let mcodeVersion;
let mcodeChecked = false;

function checkMcode() {
  if (!mcodeChecked) {
    mcodeChecked = true;
    try {
      mcodeVersion = execFileSync('mcode', ['--version'], {
        encoding: 'utf8',
        timeout: 30000,
        stdio: ['ignore', 'pipe', 'ignore'],
      }).trim();
    } catch (e) {
      mcodeVersion = null;
    }
  }
  return mcodeVersion;
}

function checkSshd() {
  return new Promise((resolve) => {
    const sock = net.connect({ host: '127.0.0.1', port: 22, timeout: 2000 });
    sock.on('connect', () => { sock.destroy(); resolve(true); });
    sock.on('error', () => resolve(false));
    sock.on('timeout', () => { sock.destroy(); resolve(false); });
  });
}

const server = http.createServer(async (req, res) => {
  const sshdUp = await checkSshd();
  const mv = checkMcode();
  const healthy = sshdUp && !!mv;
  const body = JSON.stringify(
    {
      status: healthy ? 'ok' : 'degraded',
      service: 'ubuntu-minimax-code',
      sshd: sshdUp ? 'up (port 22)' : 'down',
      mcode: mv || 'missing',
      providerEnvSet: !!process.env.MCODE_PROVIDER_API_KEY,
      sshKeySet: !!process.env.SSH_PUBLIC_KEY,
      model: process.env.MCODE_MODEL || null,
      time: new Date().toISOString(),
    },
    null,
    2,
  ) + '\n';
  res.writeHead(healthy ? 200 : 503, { 'Content-Type': 'application/json' });
  res.end(body);
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`[healthz] listening on 0.0.0.0:${PORT}`);
});
