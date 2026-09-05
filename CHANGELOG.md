# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versionamento em [semver](https://semver.org): a versão do pool vive em
`package.json`, a de cada ferramenta em `metadata.version` no `SKILL.md`
dela — ver a seção "Versões" do [README](README.md). Cada versão do pool
vira uma tag git (`vX.Y.Z`).

## [Não lançado]

### Corrigido

- **`ms-codereview`: modo incremental.** A condição de entrada estava
  invertida; rebase ou force-push fazia o delta incluir commits da base que
  não são do PR; achado da rodada anterior não reancorava depois de novos
  commits deslocarem a linha. `fetch-context.sh` agora grava
  `previous_is_ancestor`, `previous_base_sha` e `base_moved`; sem
  `previous_is_ancestor: true` a skill não entra em modo incremental, e o
  relatório passa a gravar uma âncora (função/símbolo) por achado para
  reabri-lo no arquivo atual.

### Alterado

- **`ms-codereview`: `SKILL.md` quebrado em núcleo e referência.** Precedência,
  calibragem, barra de verificação, formato do relatório e veredito continuam
  no `SKILL.md`, palavra por palavra. O que só se usa em situação específica
  (PR mecânico, script de contexto com erro, re-review, rascunho de
  comentário, segunda passagem) foi para `reference/`, lido pelo passo que o
  cita — a revisão que rejeita cedo por falta de dados nunca chega a ler
  `comentario.md` nem `segunda-passagem.md`.

## [0.6.0] - 2026-09-05

Fecha o PRD de `docs/prd/ms-codereview-0.6.0.md` (local, não versionado):
sete melhorias sobre o `/code-review` nativo e ferramentas de mercado,
sem mudar o critério da skill.

### Adicionado

- **PR mecânico dispensa ticket.** `fetch-context.sh` classifica bump de
  dependência, formatação, rename e doc em `context-status.json`
  (`mechanical`/`mechanical_kind`) e pula ticket/`--spec-file` quando
  reconhece um — a própria mudança é a spec. `SKILL.md` ganha revisão
  reduzida por tipo.
- **Detecção determinística de checklist.** `scripts/detect-checklists.sh`
  decide, a partir do diff e de `checklists/index.json` (dado, não
  código), quais checklists carregar e grava o motivo em
  `raw/checklists.json`. Mesmo diff, mesmo conjunto, toda vez — antes
  dependia de julgamento na hora.
- **Refutador independente.** Todo `blocker:` que sobrevive à segunda
  passagem vai para um subagent à parte (`prompts/refute.md`), que não vê
  o relatório e tenta derrubar a afirmação. Achado refutado sai do
  relatório e vai para `temp/cr/<alvo>/refuted.md`; inconclusivo vira
  `dúvida:`.
- **Re-review incremental.** `fetch-context.sh` grava `head_sha`/`base_sha`
  e detecta `previous_report`/`previous_sha` (o `report-<sha7>.md` mais
  recente em `temp/cr/<alvo>/`); a skill grava um relatório por rodada e,
  na próxima, revisa só o delta e classifica cada achado anterior como
  resolvido, aberto ou novo, em vez de recomeçar do zero.
- **Review inline pronto para postar.** Junto do rascunho de comentário, a
  skill grava `temp/cr/<pr>/review-<sha7>.json` no formato de review do
  GitHub (`comments[]` com `path`/`line`/`body`); `scripts/post-review.sh
  <pr>` publica quando o usuário decidir, e recusa (exit `3`) se o PR
  mudou desde que o review foi escrito.
- **Roda o que for barato.** `scripts/run-checks.sh` roda typecheck e os
  testes que o diff tocou, num worktree isolado (nunca mexe no working
  tree do usuário, nunca roda `npm install` — reaproveita `node_modules`
  via symlink quando o diff não altera dependências). Teste e typecheck
  que falham viram `blocker:` no relatório; lint continua fora, coberto
  pela regra de não reportar o que o CI já cobre.
- **Passagem de segurança dedicada.** `detect-checklists.sh` aciona
  `security`/`security_why` em `raw/checklists.json` quando o diff toca
  caminho sensível (auth, sessão, token, cripto, upload, middleware...),
  um padrão de API perigosa (`eval`, `exec`, query interpolada,
  `innerHTML`, `child_process`, `jwt`/`bcrypt`/`crypto`...) ou ganha
  dependência nova; a skill despacha um subagent com `prompts/security.md`
  (lente OWASP restrita ao diff) antes de reportar.
- `ms-codereview/tests/run.sh`: primeiro harness de testes da skill —
  bash puro, fixtures de repositório git em diretório temporário, um
  arquivo `f<N>.sh` por feature acima.

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
