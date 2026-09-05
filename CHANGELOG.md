# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versionamento em [semver](https://semver.org): a versão do pool vive em
`package.json`, a de cada ferramenta em `metadata.version` no `SKILL.md`
dela — ver a seção "Versões" do [README](README.md). Cada versão do pool
vira uma tag git (`vX.Y.Z`).

## [Não lançado]

### Adicionado

- `ms-codereview`: `fetch-context.sh` classifica PR mecânico (bump de
  dependência, formatação, rename, doc) em `context-status.json`
  (`mechanical`/`mechanical_kind`) e dispensa ticket/`--spec-file` quando
  reconhece um — a própria mudança é a spec. `SKILL.md` ganha revisão
  reduzida por tipo.
- `ms-codereview/tests/run.sh`: primeiro harness de testes da skill, bash
  puro, com os casos do PR mecânico.
- `ms-codereview`: review inline pronto para postar — junto do rascunho de
  comentário, a skill grava `temp/cr/<pr>/review-<sha7>.json` no formato
  de review do GitHub (`comments[]` com `path`/`line`/`body`);
  `scripts/post-review.sh <pr>` publica quando o usuário decidir, e
  recusa (exit `3`) se o PR mudou desde que o review foi escrito.
- `ms-codereview`: re-review incremental — `fetch-context.sh` grava
  `head_sha`/`base_sha` e detecta `previous_report`/`previous_sha` (o
  `report-<sha7>.md` mais recente em `temp/cr/<alvo>/`); a skill grava um
  relatório por rodada e, na próxima, revisa só o delta e classifica cada
  achado anterior como resolvido, aberto ou novo, em vez de recomeçar do
  zero.
- `ms-codereview`: refutador independente — todo `blocker:` que sobrevive
  à segunda passagem vai para um subagent à parte (`prompts/refute.md`),
  que não vê o relatório e tenta derrubar a afirmação. Achado refutado sai
  do relatório e vai para `temp/cr/<alvo>/refuted.md`; inconclusivo vira
  `dúvida:`.
- `ms-codereview`: detecção determinística de checklist —
  `scripts/detect-checklists.sh` decide, a partir do diff e de
  `checklists/index.json` (dado, não código), quais checklists carregar e
  grava o motivo em `raw/checklists.json`. Mesmo diff, mesmo conjunto,
  toda vez; antes dependia de julgamento na hora.

## [0.5.0] - 2026-09-05

### Adicionado

- `ms-codereview`: `--spec-file <caminho>` no `fetch-context.sh` usa um
  documento local (PRD, spec, ata) como contexto da revisão, para quem não
  tem ClickUp nem Jira. Só roda quando passado; sem descoberta automática
  de arquivo em diretório.
- `ms-codereview`: checklists `frontend-react.md` (React / Vite / Tailwind
  / shadcn) e `database-postgres-pgvector.md` (migration, schema, query,
  pgvector).

### Alterado

- `ms-codereview`: provider de tracker sem credencial configurada não é
  mais tentado na descoberta automática; sem nenhum configurado, o script
  sai `4` sem procurar id. `--provider` explícito continua sendo tentado.

Pool e `ms-codereview` vão a 0.5.0.

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
