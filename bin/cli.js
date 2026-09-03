#!/usr/bin/env node
'use strict';

// Instalador do pool ms-ai-tools.
//
//   npx github:marcelosartor/ms-ai-tools              # instala todas
//   npx github:marcelosartor/ms-ai-tools ms-codereview
//   npx github:marcelosartor/ms-ai-tools --list
//
// Uma ferramenta é qualquer pasta da raiz do pacote que contenha um SKILL.md.
// A instalação copia a pasta para o diretório de skills escolhido:
//
//   global  ~/.claude/skills      vale em todos os seus projetos
//   local   ./.claude/skills      só no diretório corrente; pode ser comitado
//
// Sem --global/--local, e havendo terminal, o instalador pergunta. Fora de
// terminal (CI, pipe) nunca pergunta: assume global, para não travar.
//
// Credenciais nunca são copiadas do repositório nem tocadas pela atualização:
// vivem em ~/.config/ms-ai-tools/.env (ou $MS_AI_TOOLS_CONFIG_DIR), fora do
// diretório da skill, justamente para sobreviver a toda reinstalação.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { findJq, installJq, which, JQ_VERSION } = require('./deps.js');

const ROOT = path.resolve(__dirname, '..');
const GLOBAL_SKILLS = path.join(os.homedir(), '.claude', 'skills');
const LOCAL_SKILLS = path.join(process.cwd(), '.claude', 'skills');

// Resolvido em runtime (pode vir de flag ou de pergunta); começa no padrão
// para que --help e --version tenham o que mostrar antes de qualquer escolha.
let SKILLS_DIR = process.env.CLAUDE_SKILLS_DIR || GLOBAL_SKILLS;

const CONFIG_DIR =
  process.env.MS_AI_TOOLS_CONFIG_DIR ||
  path.join(
    process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'),
    'ms-ai-tools'
  );
const CONFIG_ENV = path.join(CONFIG_DIR, '.env');
const BIN_DIR = path.join(CONFIG_DIR, 'bin');
const BACKUP_DIR = path.join(CONFIG_DIR, 'backups');

// Manifesto gravado dentro da skill a cada instalação: guarda o hash de cada
// arquivo como ele saiu do pacote. É o que permite distinguir "o usuário
// editou este arquivo" de "a versão nova mudou este arquivo" — comparar a
// cópia instalada com o pacote novo não separa os dois casos.
const MANIFEST = '.ms-ai-tools.json';
const IGNORADOS = new Set(['.env', MANIFEST]);

const interativo = () => process.stdin.isTTY && process.stdout.isTTY;

// Uma única interface para todas as perguntas: abrir uma por pergunta faz a
// primeira consumir o que já estava no buffer do stdin, e a seguinte recebe
// EOF. Fechada no fim, em fecharPerguntas().
let _rl = null;
function linha() {
  if (!_rl) {
    _rl = require('node:readline/promises').createInterface({
      input: process.stdin,
      output: process.stdout,
    });
  }
  return _rl;
}
function fecharPerguntas() {
  if (_rl) _rl.close();
  _rl = null;
}

async function pergunta(titulo, opcoes) {
  console.log(`\n${titulo}`);
  opcoes.forEach((o, i) => {
    console.log(`  ${i + 1}) ${o.label}${o.nota ? `  — ${o.nota}` : ''}`);
  });
  for (;;) {
    let r;
    try {
      r = await linha().question(`Escolha [1-${opcoes.length}] (1): `);
    } catch {
      // stdin acabou (Ctrl+D, entrada redirecionada): fica no padrão
      console.log('\n  (sem resposta — usando a opção 1)');
      return opcoes[0];
    }
    const i = Number(r.trim() || '1');
    if (Number.isInteger(i) && i >= 1 && i <= opcoes.length) return opcoes[i - 1];
    console.log('  opção inválida');
  }
}

const isDir = (p) => fs.existsSync(p) && fs.statSync(p).isDirectory();
const isFile = (p) => fs.existsSync(p) && fs.statSync(p).isFile();

const POOL_VERSION = require('../package.json').version;

// A versão de uma skill vive em metadata.version do SKILL.md. O frontmatter
// não tem campo `version` — chave desconhecida é erro nos caminhos de
// distribuição da claude.ai e da API —, e `metadata` é o mapa livre que a
// especificação reserva justamente para dado de catálogo como este.
//
// Parser deliberadamente pequeno: só o que basta para achar metadata.version,
// para o instalador não carregar uma dependência de YAML.
function skillVersion(skillMd) {
  if (!isFile(skillMd)) return null;
  const fm = /^---\r?\n([\s\S]*?)\r?\n---/.exec(fs.readFileSync(skillMd, 'utf8'));
  if (!fm) return null;
  const linhas = fm[1].split(/\r?\n/);
  const i = linhas.findIndex((l) => /^metadata:\s*$/.test(l));
  if (i === -1) return null;
  for (const l of linhas.slice(i + 1)) {
    if (/^\S/.test(l)) break; // saiu do bloco indentado
    const m = /^\s+version:\s*["']?([^"'\s]+)["']?\s*$/.exec(l);
    if (m) return m[1];
  }
  return null;
}

const versionOf = (dir) => skillVersion(path.join(dir, 'SKILL.md'));
const rotulo = (v) => (v ? `v${v}` : 'sem versão');

function discover() {
  return fs
    .readdirSync(ROOT, { withFileTypes: true })
    .filter((e) => e.isDirectory() && isFile(path.join(ROOT, e.name, 'SKILL.md')))
    .map((e) => e.name)
    .sort();
}

function usage() {
  console.log(`
ms-ai-tools v${POOL_VERSION} — instala as ferramentas do pool como skills do Claude Code

  npx github:marcelosartor/ms-ai-tools                 instala todas
  npx github:marcelosartor/ms-ai-tools <ferramenta>…   instala só as indicadas
  npx github:marcelosartor/ms-ai-tools --list          o que existe e o que já está instalado
  npx github:marcelosartor/ms-ai-tools --doctor        confere as dependências
  npx github:marcelosartor/ms-ai-tools --deps          só instala as dependências
  npx github:marcelosartor/ms-ai-tools --version       versão do pool e de cada ferramenta

Escopo (sem nenhum destes, e havendo terminal, o instalador pergunta)
  --global     instala em ~/.claude/skills — vale em todos os seus projetos
  --local      instala em ./.claude/skills — só no diretório corrente
  --dir <path> instala num diretório específico

Opções
  --provider <id>  tracker a preparar no .env (ex.: clickup, jira-cloud); "none" pula
  --no-deps        não baixa nada; só copia as skills
  --no-backup      não guarda cópia da instalação anterior antes de substituir

Destino das skills   ${SKILLS_DIR}   ($CLAUDE_SKILLS_DIR muda)
Credenciais          ${CONFIG_ENV}   ($MS_AI_TOOLS_CONFIG_DIR muda)
Dependências         ${BIN_DIR}      (idem)
`.trim());
}

function list() {
  const tools = discover();
  if (tools.length === 0) return console.log(`nenhuma ferramenta encontrada em ${ROOT}`);
  console.log(`ms-ai-tools v${POOL_VERSION} — destino: ${SKILLS_DIR}\n`);
  for (const t of tools) {
    const disp = versionOf(path.join(ROOT, t));
    const inst = isDir(path.join(SKILLS_DIR, t)) ? versionOf(path.join(SKILLS_DIR, t)) : undefined;
    let estado;
    if (inst === undefined) estado = 'não instalada';
    else if (inst === disp) estado = `instalada, ${rotulo(inst)}`;
    else estado = `instalada ${rotulo(inst)} → atualiza para ${rotulo(disp)}`;
    console.log(`  ${t.padEnd(20)} ${rotulo(disp).padEnd(12)} ${estado}`);
  }
}

// Reportado, nunca bloqueante: a skill instala mesmo sem as dependências, e
// avisar aqui é melhor que falhar na primeira revisão.
function doctor() {
  const jq = findJq(BIN_DIR);
  const linha = (ok, bin, para, extra) =>
    console.log(`  ${ok ? '✓' : '✗'} ${bin.padEnd(6)} ${para}${extra ? `  — ${extra}` : ''}`);

  const faltando = [];
  console.log('estado das dependências:');
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

// Cada ferramenta declara suas credenciais em credentials.json, para o
// instalador não precisar conhecer os trackers de ninguém.
function credentialSpec(tool) {
  const f = path.join(ROOT, tool, 'credentials.json');
  if (!isFile(f)) return null;
  try {
    return JSON.parse(fs.readFileSync(f, 'utf8'));
  } catch {
    return null;
  }
}

// Chave comentada conta como já declarada. Sem isso, uma variável opcional
// que o usuário deixou comentada seria reescrita a cada execução, e o .env
// acumularia o mesmo bloco repetido.
function envAtual() {
  if (!isFile(CONFIG_ENV)) return {};
  const out = {};
  for (const l of fs.readFileSync(CONFIG_ENV, 'utf8').split(/\r?\n/)) {
    const m = /^\s*#?\s*([A-Z0-9_]+)\s*=\s*(.*)$/.exec(l);
    if (m) out[m[1]] = m[2];
  }
  return out;
}

// Acrescenta ao .env só as chaves que ainda não existem. Valor já preenchido
// nunca é sobrescrito: o instalador não tem como saber se o que está lá é
// melhor que o placeholder que ele traria.
function seedCredentials(opcao) {
  const existentes = envAtual();
  const faltando = Object.entries({ ...opcao.vars, ...(opcao.opcionais || {}) }).filter(
    ([k]) => existentes[k] === undefined
  );

  if (faltando.length === 0) {
    console.log(`  ✓ ${opcao.label}: credenciais já presentes em ${CONFIG_ENV}`);
    return;
  }

  fs.mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 });
  const novo = isFile(CONFIG_ENV);
  const bloco = [
    '',
    `# ---------- ${opcao.label} ----------`,
    ...(opcao.onde ? [`# ${opcao.onde}`] : []),
    ...Object.entries(opcao.vars)
      .filter(([k]) => existentes[k] === undefined)
      .map(([k, v]) => `${k}=${v}`),
    ...Object.entries(opcao.opcionais || {})
      .filter(([k]) => existentes[k] === undefined)
      .map(([k, v]) => `# ${k}=${v}`),
    '',
  ].join('\n');

  fs.appendFileSync(CONFIG_ENV, (novo ? '' : '# Credenciais do pool ms-ai-tools.\n') + bloco);
  fs.chmodSync(CONFIG_ENV, 0o600);
  console.log(`  ✓ ${opcao.label}: ${faltando.length} variável(is) escritas em ${CONFIG_ENV}`);
  console.log(`      edite o arquivo e substitua os valores de exemplo${opcao.onde ? ` (${opcao.onde})` : ''}`);
}

function hashes(dir, base = dir, out = new Map()) {
  if (!isDir(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (IGNORADOS.has(e.name)) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) hashes(p, base, out);
    else if (e.isFile()) {
      out.set(
        path.relative(base, p).split(path.sep).join('/'),
        crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex')
      );
    }
  }
  return out;
}

function writeManifest(dest, version) {
  fs.writeFileSync(
    path.join(dest, MANIFEST),
    JSON.stringify(
      { version: version || null, installedAt: new Date().toISOString(), files: Object.fromEntries(hashes(dest)) },
      null,
      2
    )
  );
}

// O que há na cópia instalada que não veio do pacote. Sem manifesto (instalação
// feita à mão ou por uma versão antiga do instalador) não dá para classificar:
// devolve `conhecido: false` e quem chama guarda cópia por precaução.
function localChanges(src, dest) {
  const atual = hashes(dest);
  const mf = path.join(dest, MANIFEST);

  if (!isFile(mf)) {
    const doPacote = hashes(src);
    const difere = [...atual].some(([r, h]) => doPacote.get(r) !== h) || atual.size !== doPacote.size;
    return { conhecido: false, difere, modificados: [], adicionados: [] };
  }

  let files;
  try {
    files = JSON.parse(fs.readFileSync(mf, 'utf8')).files || {};
  } catch {
    return { conhecido: false, difere: true, modificados: [], adicionados: [] };
  }

  const modificados = [...atual].filter(([r, h]) => files[r] !== undefined && files[r] !== h).map(([r]) => r);
  const adicionados = [...atual].filter(([r]) => files[r] === undefined).map(([r]) => r);
  return { conhecido: true, difere: modificados.length + adicionados.length > 0, modificados, adicionados };
}

function backupInstall(tool, dest, version) {
  const carimbo = new Date().toISOString().replace(/[:.]/g, '-').replace(/Z$/, '');
  const alvo = path.join(BACKUP_DIR, `${tool}-v${version || 'sem-versao'}-${carimbo}`);
  fs.mkdirSync(BACKUP_DIR, { recursive: true, mode: 0o700 });
  // o .env fica de fora: já é resgatado para o diretório de configuração, e
  // não há por que espalhar credencial por dentro dos backups
  fs.cpSync(dest, alvo, { recursive: true, filter: (p) => path.basename(p) !== '.env' });
  return alvo;
}

function relatarMudancas(mudancas, backup) {
  const amostra = (rotulo, lista) => {
    if (!lista.length) return;
    const mostra = lista.slice(0, 5).join(', ');
    const resto = lista.length > 5 ? `, +${lista.length - 5}` : '';
    console.log(`        ${rotulo} ${mostra}${resto}`);
  };
  if (mudancas.conhecido) {
    const n = mudancas.modificados.length + mudancas.adicionados.length;
    console.log(`      ${n} arquivo(s) alterado(s) por você na cópia instalada — guardados em`);
  } else {
    console.log('      a cópia instalada difere do pacote e não tem manifesto para classificar —');
    console.log('      guardada por precaução em');
  }
  console.log(`      ${backup}`);
  amostra('editados:', mudancas.modificados);
  amostra('seus:    ', mudancas.adicionados);
}

function installOne(tool, comBackup) {
  const src = path.join(ROOT, tool);
  const dest = path.join(SKILLS_DIR, tool);

  if (!isFile(path.join(src, 'SKILL.md'))) {
    console.error(`  ✗ ${tool}: ferramenta desconhecida (rode --list)`);
    return false;
  }

  const anterior = isDir(dest) ? versionOf(dest) : undefined;

  // guardar antes de substituir: a instalação troca o diretório inteiro
  let backup = null;
  let mudancas = null;
  if (isDir(dest) && comBackup) {
    mudancas = localChanges(src, dest);
    if (mudancas.difere) backup = backupInstall(tool, dest, anterior);
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
  writeManifest(dest, versionOf(dest));

  const de = anterior === undefined ? null : anterior;
  const para = versionOf(dest);
  const transicao =
    de === null ? rotulo(para) : de === para ? `${rotulo(para)} (reinstalada)` : `${rotulo(de)} → ${rotulo(para)}`;
  console.log(`  ✓ ${tool.padEnd(20)} ${transicao}`);
  console.log(`      ${dest}`);
  if (backup) relatarMudancas(mudancas, backup);
  if (rescued === CONFIG_ENV) {
    console.log(`      credenciais movidas da skill para ${rescued}`);
  } else if (rescued) {
    console.log(`      já havia credencial em ${CONFIG_ENV};`);
    console.log(`      a que estava na skill foi guardada em ${rescued} — confira e apague`);
  }
  return true;
}

async function escolherDestino(opts) {
  if (opts.dir) return path.resolve(opts.dir);
  if (opts.local) return LOCAL_SKILLS;
  if (opts.global) return GLOBAL_SKILLS;
  if (process.env.CLAUDE_SKILLS_DIR) return process.env.CLAUDE_SKILLS_DIR;
  if (!interativo()) return GLOBAL_SKILLS;

  const r = await pergunta('Onde instalar?', [
    { label: `Global — ${GLOBAL_SKILLS}`, nota: 'vale em todos os seus projetos', dir: GLOBAL_SKILLS },
    { label: `Local  — ${LOCAL_SKILLS}`, nota: 'só neste diretório; pode ser comitado', dir: LOCAL_SKILLS },
  ]);
  return r.dir;
}

// Uma skill pessoal com o mesmo nome vence a de projeto, então instalar local
// tendo a global é trabalho perdido se ninguém avisar.
function avisarSombra(tools) {
  if (SKILLS_DIR === GLOBAL_SKILLS) return;
  const sombreadas = tools.filter((t) => isDir(path.join(GLOBAL_SKILLS, t)));
  if (sombreadas.length === 0) return;
  console.log(`\n  ! ${sombreadas.join(', ')} também está instalada em ${GLOBAL_SKILLS}.`);
  console.log('    A skill pessoal vence a de projeto — remova a global para esta valer.');
}

async function escolherProvider(tools, escolhido) {
  const specs = tools.map((t) => [t, credentialSpec(t)]).filter(([, c]) => c && c.opcoes?.length);
  if (specs.length === 0) return true;

  for (const [tool, spec] of specs) {
    let opcao;
    if (escolhido) {
      if (escolhido === 'none') return true;
      opcao = spec.opcoes.find((o) => o.id === escolhido);
      if (!opcao) {
        console.error(
          `  ✗ tracker desconhecido para ${tool}: ${escolhido} (use: ${spec.opcoes.map((o) => o.id).join(', ')})`
        );
        return false;
      }
    } else if (interativo()) {
      const r = await pergunta(spec.pergunta || `Credenciais de ${tool}:`, [
        ...spec.opcoes.map((o) => ({ label: o.label, nota: o.onde, opcao: o })),
        { label: 'Configuro depois', opcao: null },
      ]);
      opcao = r.opcao;
    }
    if (opcao) seedCredentials(opcao);
  }
  return true;
}

async function install(tools, comDeps, comBackup) {
  console.log(`ms-ai-tools v${POOL_VERSION} — instalando em ${SKILLS_DIR}:`);
  let ok = true;
  for (const t of tools) ok = installOne(t, comBackup) && ok;

  console.log('\ndependências:');
  if (comDeps) {
    ok = (await ensureDeps()) && ok;
  } else {
    console.log('  (--no-deps: nada foi baixado)');
  }

  console.log();
  doctor();
  return ok;
}

async function main() {
  const args = process.argv.slice(2);

  if (args.includes('-h') || args.includes('--help')) return usage();
  if (args.includes('-l') || args.includes('--list')) return list();
  if (args.includes('-v') || args.includes('--version')) {
    console.log(`ms-ai-tools ${POOL_VERSION}`);
    for (const t of discover()) console.log(`  ${t.padEnd(20)} ${rotulo(versionOf(path.join(ROOT, t)))}`);
    return;
  }
  if (args.includes('--doctor')) return process.exit(doctor() ? 0 : 1);
  if (args.includes('--deps')) {
    console.log('dependências:');
    return process.exit((await ensureDeps()) ? 0 : 1);
  }

  const comDeps = !args.includes('--no-deps');
  const comBackup = !args.includes('--no-backup');
  const opts = { global: args.includes('--global'), local: args.includes('--local') };

  const rest = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === '--no-deps' || a === '--no-backup' || a === '--global' || a === '--local') continue;
    if (a === '--dir') { opts.dir = args[++i]; continue; }
    if (a === '--provider') { opts.provider = args[++i]; continue; }
    rest.push(a);
  }

  if (opts.global && opts.local) {
    console.error('--global e --local se excluem');
    return process.exit(2);
  }
  if (opts.dir === undefined && args.includes('--dir')) {
    console.error('--dir precisa de um caminho');
    return process.exit(2);
  }

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
  SKILLS_DIR = await escolherDestino(opts);
  let ok = await install(tools, comDeps, comBackup);
  avisarSombra(tools);
  ok = (await escolherProvider(tools, opts.provider)) && ok;
  fecharPerguntas();
  console.log('\nverifique com /skills numa sessão do Claude Code.');
  process.exit(ok ? 0 : 1);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
