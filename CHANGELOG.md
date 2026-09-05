# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versionamento em [semver](https://semver.org): a versão do pool vive em
`package.json`, a de cada ferramenta em `metadata.version` no `SKILL.md`
dela — ver a seção "Versões" do [README](README.md). Cada versão do pool
vira uma tag git (`vX.Y.Z`).

## [0.4.0] - 2026-09-05

### Alterado

- README reorganizado em **Objetivo**, **Instalação** e **Ferramentas**; o
  pool passa a se posicionar explicitamente como a formalização de um
  workflow de Spec-Driven Development (SDD), com uma ferramenta por etapa.
- Seção "Ferramentas" passa a explicar, para cada uma, por que ela existe,
  quando usar e por que usar — não só o que faz.
- Convenção do README de cada ferramenta (descrição, atribuição quando
  adaptada de terceiro, como usar) documentada no README raiz e aplicada ao
  `ms-codereview`.

Pool e `ms-codereview` vão a 0.4.0 — mudança só de documentação, sem
alteração de comportamento do instalador ou da skill.

## [0.3.0] - 2026-09-03

### Adicionado

- Instalador pergunta **onde instalar** (global em `~/.claude/skills/`, ou
  local em `./.claude/skills/`) e **qual tracker de tickets** usar,
  escrevendo o `.env` sozinho com as variáveis do tracker escolhido.
- `--global`, `--local`, `--dir`, `--provider` respondem sem prompt; fora de
  terminal (CI, pipe) o instalador nunca pergunta.
- Cada ferramenta declara seus trackers em `credentials.json`, sem o
  instalador precisar conhecer tracker nenhum.

## [0.2.0] - 2026-09-03

### Adicionado

- Backup automático da instalação anterior quando ela tiver mudanças feitas
  pelo usuário: um manifesto de hashes (`.ms-ai-tools.json`) grava como cada
  arquivo saiu do pacote, e a atualização compara com a cópia instalada
  antes de substituir o diretório.
- `--no-backup` desliga o comportamento; o `.env` fica sempre fora do
  backup.

## [0.1.0] - 2026-09-03

### Adicionado

- Pool `ms-ai-tools` criado, com a skill `ms-codereview` (revisão de PR de
  terceiros cruzando ticket, descrição do PR e diff) instalável por
  `npx github:marcelosartor/ms-ai-tools`.
- Versionamento independente do pool e de cada ferramenta, refletido em
  `--version`, `--list` e no relatório de instalação (`v0.1.0 → v0.2.0`).
- Credenciais e dependências (`jq`, verificado por sha256) fora da pasta da
  skill, para sobreviver a atualizações que substituem o diretório inteiro.
