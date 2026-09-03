#!/usr/bin/env node
'use strict';

// Instalador do pool ms-ai-tools.
//
//   npx github:marcelosartor/ms-ai-tools              # instala todas
//   npx github:marcelosartor/ms-ai-tools ms-codereview
//   npx github:marcelosartor/ms-ai-tools --list
//
// Uma ferramenta é qualquer pasta da raiz do pacote que contenha um SKILL.md.
// A instalação copia a pasta para ~/.claude/skills/ (ou $CLAUDE_SKILLS_DIR).
//
// Credenciais nunca são copiadas do repositório nem tocadas pela atualização:
// vivem em ~/.config/ms-ai-tools/.env (ou $MS_AI_TOOLS_CONFIG_DIR), fora do
// diretório da skill, justamente para sobreviver a toda reinstalação.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { findJq, installJq, which, JQ_VERSION } = require('./deps.js');

const ROOT = path.resolve(__dirname, '..');
const SKILLS_DIR =
  process.env.CLAUDE_SKILLS_DIR || path.join(os.homedir(), '.claude', 'skills');
const CONFIG_DIR =
  process.env.MS_AI_TOOLS_CONFIG_DIR ||
  path.join(
    process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'),
    'ms-ai-tools'
  );
const CONFIG_ENV = path.join(CONFIG_DIR, '.env');
const BIN_DIR = path.join(CONFIG_DIR, 'bin');

const isDir = (p) => fs.existsSync(p) && fs.statSync(p).isDirectory();
const isFile = (p) => fs.existsSync(p) && fs.statSync(p).isFile();

function discover() {
  return fs
    .readdirSync(ROOT, { withFileTypes: true })
    .filter((e) => e.isDirectory() && isFile(path.join(ROOT, e.name, 'SKILL.md')))
    .map((e) => e.name)
    .sort();
}

function usage() {
  console.log(`
ms-ai-tools — instala as ferramentas do pool como skills do Claude Code

  npx github:marcelosartor/ms-ai-tools                 instala todas
  npx github:marcelosartor/ms-ai-tools <ferramenta>…   instala só as indicadas
  npx github:marcelosartor/ms-ai-tools --list          o que existe e o que já está instalado
  npx github:marcelosartor/ms-ai-tools --doctor        confere as dependências
  npx github:marcelosartor/ms-ai-tools --deps          só instala as dependências

Opções
  --no-deps    não baixa nada; só copia as skills

Destino das skills   ${SKILLS_DIR}   ($CLAUDE_SKILLS_DIR muda)
Credenciais          ${CONFIG_ENV}   ($MS_AI_TOOLS_CONFIG_DIR muda)
Dependências         ${BIN_DIR}      (idem)
`.trim());
}

function list() {
  const tools = discover();
  if (tools.length === 0) return console.log(`nenhuma ferramenta encontrada em ${ROOT}`);
  console.log(`ferramentas do pool (destino: ${SKILLS_DIR}):`);
  for (const t of tools) {
    const state = isDir(path.join(SKILLS_DIR, t)) ? 'instalada' : 'não instalada';
    console.log(`  ${t.padEnd(20)} ${state}`);
  }
}

// Reportado, nunca bloqueante: a skill instala mesmo sem as dependências, e
// avisar aqui é melhor que falhar na primeira revisão.
function doctor() {
  const jq = findJq(BIN_DIR);
  const linha = (ok, bin, para, extra) =>
    console.log(`  ${ok ? '✓' : '✗'} ${bin.padEnd(6)} ${para}${extra ? `  — ${extra}` : ''}`);

  const faltando = [];
  console.log('dependências:');
  linha(!!jq, 'jq', 'processar as respostas das APIs', jq && `${jq.source}: ${jq.path}`);
  if (!jq) faltando.push(['jq', 'roda --deps, ou instale pelo sistema (sudo apt install jq)']);

  for (const [bin, para, como] of [
    ['curl', 'falar com o tracker', 'sudo apt install curl  |  já vem no macOS'],
    ['gh', 'ler o PR do GitHub', 'https://cli.github.com — depois: gh auth login'],
  ]) {
    const achado = which(bin);
    linha(!!achado, bin, para, achado);
    if (!achado) faltando.push([bin, como]);
  }

  if (faltando.length) {
    console.log('\nfaltando:');
    for (const [bin, como] of faltando) console.log(`  ${bin}: ${como}`);
  }
  return faltando.length === 0;
}

// O jq é a única dependência que dá para resolver aqui: binário estático,
// release oficial, sha256 fixado. curl e gh ficam a cargo do sistema — um já
// vem em toda parte, o outro precisa de login de qualquer forma.
async function ensureDeps() {
  const jq = findJq(BIN_DIR);
  if (jq) {
    console.log(`  ✓ jq já disponível (${jq.source}: ${jq.path})`);
    return true;
  }
  try {
    await installJq(BIN_DIR);
    return true;
  } catch (err) {
    console.error(`  ✗ jq: ${err.message}`);
    return false;
  }
}

// A instalação substitui o diretório da skill inteiro, então um .env que
// esteja lá dentro seria perdido. Ele é salvo antes, sempre — no destino
// definitivo se ainda não houver credencial lá, senão ao lado dela, com nome
// próprio. Nunca sobrescreve uma credencial existente nem descarta a antiga.
function rescueEnv(tool, installedEnv) {
  if (!isFile(installedEnv)) return null;
  fs.mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 });

  const dest = isFile(CONFIG_ENV)
    ? path.join(CONFIG_DIR, `.env.da-skill-${tool}`)
    : CONFIG_ENV;

  fs.copyFileSync(installedEnv, dest);
  fs.chmodSync(dest, 0o600);
  return dest;
}

function chmodScripts(dir) {
  if (!isDir(dir)) return;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) chmodScripts(p);
    else if (e.name.endsWith('.sh')) fs.chmodSync(p, 0o755);
  }
}

function installOne(tool) {
  const src = path.join(ROOT, tool);
  const dest = path.join(SKILLS_DIR, tool);

  if (!isFile(path.join(src, 'SKILL.md'))) {
    console.error(`  ✗ ${tool}: ferramenta desconhecida (rode --list)`);
    return false;
  }

  const rescued = rescueEnv(tool, path.join(dest, '.env'));

  fs.mkdirSync(SKILLS_DIR, { recursive: true });
  fs.rmSync(dest, { recursive: true, force: true });
  fs.cpSync(src, dest, {
    recursive: true,
    // credencial nunca viaja no pacote
    filter: (s) => path.basename(s) !== '.env',
  });
  chmodScripts(path.join(dest, 'scripts'));

  console.log(`  ✓ ${tool} → ${dest}`);
  if (rescued === CONFIG_ENV) {
    console.log(`      credenciais movidas da skill para ${rescued}`);
  } else if (rescued) {
    console.log(`      já havia credencial em ${CONFIG_ENV};`);
    console.log(`      a que estava na skill foi guardada em ${rescued} — confira e apague`);
  }
  return true;
}

async function install(tools, comDeps) {
  console.log(`instalando em ${SKILLS_DIR}:`);
  let ok = true;
  for (const t of tools) ok = installOne(t) && ok;

  const semCredencial =
    !isFile(CONFIG_ENV) &&
    tools.some((t) => isFile(path.join(ROOT, t, '.env.example')));

  console.log('\ndependências:');
  if (comDeps) {
    ok = (await ensureDeps()) && ok;
  } else {
    console.log('  (--no-deps: nada foi baixado)');
  }

  console.log();
  if (semCredencial) {
    console.log('configure as credenciais:');
    console.log(`  mkdir -p ${CONFIG_DIR}`);
    for (const t of tools) {
      const ex = path.join(SKILLS_DIR, t, '.env.example');
      if (isFile(ex)) console.log(`  cp ${ex} ${CONFIG_ENV}`);
    }
    console.log(`  # edite ${CONFIG_ENV}`);
    console.log();
  }
  doctor();
  console.log('\nverifique com /skills numa sessão do Claude Code.');
  return ok;
}

async function main() {
  const args = process.argv.slice(2);

  if (args.includes('-h') || args.includes('--help')) return usage();
  if (args.includes('-l') || args.includes('--list')) return list();
  if (args.includes('--doctor')) return process.exit(doctor() ? 0 : 1);
  if (args.includes('--deps')) {
    console.log('dependências:');
    return process.exit((await ensureDeps()) ? 0 : 1);
  }

  const comDeps = !args.includes('--no-deps');
  const rest = args.filter((a) => a !== '--no-deps');

  const unknownFlag = rest.find((a) => a.startsWith('-'));
  if (unknownFlag) {
    console.error(`opção desconhecida: ${unknownFlag}\n`);
    usage();
    return process.exit(2);
  }

  const tools = rest.length ? rest : discover();
  if (tools.length === 0) {
    console.error(`nenhuma ferramenta encontrada em ${ROOT}`);
    return process.exit(1);
  }
  process.exit((await install(tools, comDeps)) ? 0 : 1);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
