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

### Adicionado

- **`ms-codereview`: checklists transversais `common`, `ci-infra` e
  `llm-integration`.** `common` (`always: true`) cobre o que nenhum
  checklist de stack vê (`.env.example`, contrato quebrado, TODO sem
  dono, i18n, licença) e carrega em todo PR. `ci-infra` cobre GitHub
  Actions, Dockerfile e infra como código (workflow malicioso via
  `pull_request_target`, segredo em log, imagem `latest`). `llm-
  integration` cobre prompt, saída do modelo, custo/latência e RAG —
  domínio do próprio pool.
- **`ms-codereview`: reforço dos checklists existentes.**
  `frontend-vue.md` ganha seções de acessibilidade e testes (não tinha
  nenhuma) e itens de reatividade/Pinia/formulário; `frontend-react.md`
  ganha itens de hooks, efeitos, rota e teste assíncrono;
  `database-postgres-pgvector.md` ganha migration sem lock longo (`NOT
  VALID`/`VALIDATE CONSTRAINT`, `lock_timeout`), soft-delete com índice
  parcial, `SET LOCAL` atrás de PgBouncer, e limite de dimensão do
  pgvector (`halfvec` acima de 2000).
- **`ms-codereview`: checklist `backend-node` (Express, Fastify, NestJS,
  Node puro).** Substitui `backend-node-nest.md` (assumia NestJS). Seção
  `Comum` cobre camadas, assincronia, banco e configuração para qualquer
  framework; `Express`, `Fastify`, `NestJS` e `NestJS sobre Fastify`
  aplicam pela variante detectada (`variants["backend-node"]`).
- **`ms-codereview`: leitores independentes e refutador que executa.**
  `prompts/reader.md` despacha três subagents em paralelo (lentes `spec`,
  `correcao`, `checklist`) sobre o mesmo diff, com acesso ao worktree de
  `--keep`; achados são mesclados (passo 6c), com marca `(2 leitores)`
  quando duas lentes concordam. PR acima de 400 linhas ganha um leitor
  `correcao` por diretório de primeiro nível; acima de 1500, revisão por
  amostragem com os grupos não cobertos listados. O refutador
  (`prompts/refute.md`) ganha `{{worktree}}` e pode escrever um teste de
  até 30 linhas para reproduzir o cenário — `evidencia` de um
  `CONFIRMADO` por execução começa com `executado:`; achado confirmado
  mas de efeito abaixo do limiar de bloqueio é rebaixado para
  `sugestão:`/`dúvida:` em vez de ficar `blocker:`. `run-checks.sh
  --prove-fix` roda o teste tocado contra o código da base (sem o fix):
  se passa nos dois lados, o teste não prova o bug e vira `sugestão:` no
  relatório.
- **`ms-codereview`: sinais baratos.** `raw/pr-comments.md` agora é lido —
  ponto já levantado por outro revisor e respondido não é reportado de
  novo. `gh pr checks` grava `raw/ci.json`/`raw/ci.md`; check vermelho é
  `blocker:` mesmo sem verificação local rodada. GitHub Issues entra como
  tracker (`scripts/providers/github.sh`, sem variável de `.env` — usa o
  `gh` autenticado), candidato só quando ClickUp/Jira não estão
  configurados. Achado com correção de 1–5 linhas sai como bloco
  ` ```suggestion``` ` commitável no comentário do PR. `post-review.sh`
  confere cada `comments[].line` contra os hunks do `gh pr diff` atual
  antes de postar — linha fora do diff recusa com exit `5`, nada
  parcial.
- **`ms-codereview`: segurança afinada.** Gatilhos de caminho e conteúdo
  trocados por versões de menor falso positivo (saem `**/*auth*` e
  `**/*token*`, genéricos demais); dependência nova cobre também
  `pom.xml`/`build.gradle*`/`libs.versions.toml`, não só `package.json`.
  `raw/advisories.md` consulta o GitHub Advisory Database para
  dependência nova ou alterada (nunca bloqueia a coleta). `prompts/
  security.md` ganha `{{achados_existentes}}` (não repetir achado do
  leitor principal), `{{advisories}}`, e as categorias configuração/open
  redirect/CSRF/prototype pollution/ReDoS/CI/mobile.
- **`ms-codereview`: `run-checks.sh` com baseline, monorepo e worktree
  vivo.** Agrupa arquivos tocados pelo `package.json` mais próximo (um
  pacote por manifesto, com seu próprio typecheck/lint/teste). Quando
  typecheck ou teste falha no head, compara com a `base_sha` num segundo
  worktree: erro ou teste que já falhava na base não vira `blocker:` do
  PR. `--keep` mantém o worktree do head vivo (para o refutador executar
  código depois); descoberta de teste passa a casar o caminho relativo
  importado, não o nome nu — `index.ts` não casa a suíte inteira. Projeto
  Java/Gradle/Maven sem `package.json` é detectado e registrado como
  "stack fora do Node" em vez de "sem script".
- **`ms-codereview`: detecção v2 de checklist.** `checklists/index.json`
  ganha `manifest` (casa por conteúdo do manifesto mais próximo, qualquer
  ecossistema — não só npm), `always` (checklist transversal, carrega
  sempre) e `variants` (diz quais seções de um checklist aplicar, sem
  mudar se ele carrega). `deps` agora usa o manifesto **mais próximo** de
  cada arquivo tocado em vez do `package.json` da raiz — monorepo sem
  manifesto na raiz passa a detectar corretamente.

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
