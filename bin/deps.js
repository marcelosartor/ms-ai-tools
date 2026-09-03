'use strict';

// Instalação das dependências externas das ferramentas do pool.
//
// Hoje só o jq. Ele é um binário estático, sem bibliotecas, então baixar o
// release oficial é mais previsível que depender do gerenciador de pacotes
// do sistema — que varia por distro e costuma exigir sudo.
//
// Todo download é conferido contra o sha256 publicado pelo projeto e fixado
// aqui. Hash que não bate é erro, nunca aviso: binário não verificado não
// chega ao disco.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const JQ_VERSION = '1.8.2';
const JQ_BASE = `https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}`;

// sha256sum.txt de jq-1.8.2. Atualizar junto com JQ_VERSION.
const JQ_ASSETS = {
  'linux-x64': ['jq-linux-amd64', 'b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f'],
  'linux-arm64': ['jq-linux-arm64', '8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309'],
  'darwin-x64': ['jq-macos-amd64', 'e94b266e3c26690550006abe63152b782280f4e14374accdf04cbde844f00bc0'],
  'darwin-arm64': ['jq-macos-arm64', '2d75340ba57a4b4b4c8708a21c2dc8e958a48aaa8bba13b27f77f6e4c0eca07e'],
  'win32-x64': ['jq-windows-amd64.exe', 'a6fc67fedaf9128a3309a1e2ebb8b986aeccf70122ee46d2cb4849e423f0c627'],
};

function platformKey() {
  return `${process.platform}-${process.arch}`;
}

function which(bin) {
  try {
    const out = execFileSync(process.platform === 'win32' ? 'where' : 'which', [bin], {
      stdio: ['ignore', 'pipe', 'ignore'],
    });
    return out.toString().split('\n')[0].trim() || null;
  } catch {
    return null;
  }
}

// Procura primeiro no bin do pool: é o que a skill põe na frente do PATH.
function findJq(binDir) {
  const local = path.join(binDir, process.platform === 'win32' ? 'jq.exe' : 'jq');
  if (fs.existsSync(local)) return { path: local, source: 'pool' };
  const system = which('jq');
  if (system) return { path: system, source: 'sistema' };
  return null;
}

async function download(url) {
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok) throw new Error(`HTTP ${res.status} em ${url}`);
  return Buffer.from(await res.arrayBuffer());
}

async function installJq(binDir, log = console.log) {
  const key = platformKey();
  const asset = JQ_ASSETS[key];
  if (!asset) {
    throw new Error(
      `sem binário de jq pré-compilado para ${key}; instale pelo gerenciador de pacotes (ex.: sudo apt install jq)`
    );
  }

  const [name, expected] = asset;
  const url = `${JQ_BASE}/${name}`;
  log(`  baixando jq ${JQ_VERSION} (${name})…`);

  const buf = await download(url);
  const got = crypto.createHash('sha256').update(buf).digest('hex');
  if (got !== expected) {
    throw new Error(
      `sha256 do jq não confere — esperado ${expected}, obtido ${got}. Nada foi gravado.`
    );
  }

  fs.mkdirSync(binDir, { recursive: true });
  const dest = path.join(binDir, process.platform === 'win32' ? 'jq.exe' : 'jq');
  // grava em arquivo temporário e renomeia: um Ctrl-C no meio não deixa um
  // jq truncado e executável para trás
  const tmp = `${dest}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, buf, { mode: 0o755 });
  fs.renameSync(tmp, dest);

  // o binário responde? um download íntegro ainda pode não rodar (libc,
  // arquitetura emulada, noexec no filesystem)
  try {
    const v = execFileSync(dest, ['--version'], { stdio: ['ignore', 'pipe', 'ignore'] })
      .toString()
      .trim();
    log(`  ✓ jq instalado em ${dest} (${v}, sha256 conferido)`);
  } catch {
    throw new Error(`jq foi gravado em ${dest} mas não executou; instale pelo sistema`);
  }
  return dest;
}

module.exports = { JQ_VERSION, findJq, installJq, which, platformKey, JQ_ASSETS };
