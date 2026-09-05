# ms-codereview v0.6.0

## Descrição

Revisão de pull request de terceiros para o Claude Code: cruza o ticket, a
descrição do PR e o diff, e fecha com um veredito e um rascunho de
comentário pronto para colar.

Faz parte do pool [ms-ai-tools](../README.md), na etapa de revisão do
workflow de Spec-Driven Development. A versão da skill fica em
`metadata.version` no `SKILL.md`, e o instalador mostra a transição ao
atualizar.

A skill parte de um revisor externo — alguém que não escreveu o código e
muitas vezes não conhece o projeto a fundo. Por isso ela exige saber o que o
PR **deveria** fazer antes de julgar o que ele faz, e por isso é agnóstica a
projeto e a cliente: o que sabe do domínio vem do `CLAUDE.md` do repositório
revisado e do ticket, nunca de regra embutida aqui.

Ferramenta própria — não é adaptada de terceiro.

## O que ela faz de diferente

- **Não revisa às cegas.** Sem ticket nem descrição que explique o
  comportamento esperado, ela rejeita por falta de dados em vez de inferir a
  intenção a partir do código. Um PR que faz exatamente o que o código diz
  ainda pode ser a solução errada — e é justamente isso que ler o diff não
  enxerga.
- **Severidade calibrada.** Só bloqueia merge por erro de lógica, falha de
  segurança, perda ou vazamento de dado, e regressão de comportamento. Design
  discutível, nomenclatura e organização viram sugestão, não trava.
- **Veredito mecânico.** *Aprovar* / *Aprovar com ressalvas* / *Rejeitar* sai
  de uma tabela ancorada na severidade dos achados, não de impressão geral.
- **Três leitores independentes, não um só.** `spec`, `correção` e
  `checklist` leem o mesmo diff em paralelo, cada um só com sua lente —
  o que um não vê, o outro pode ver; achado que os dois encontram entra
  marcado `(2 leitores)`. PR grande (> 400 linhas) ainda ganha um leitor
  `correção` por diretório de primeiro nível.
- **Segunda passagem com refutador que executa código.** Antes de
  entregar, relê cada achado contra o código e descarta o que não se
  sustenta; todo `blocker:` ainda passa por um subagent à parte, que não
  viu o relatório, tem acesso ao worktree do PR e pode escrever um teste
  de até 30 linhas para tentar reproduzir o cenário em vez de só ler.
  Falso positivo em PR de terceiro custa a credibilidade de quem assina.
- **A alegação "o teste cobre o bug" é verificada.** Em correção de bug
  que vem com teste, a skill roda esse teste contra o código de antes do
  fix: se passa sem o fix, o teste não prova nada — vira sugestão, não
  fica só na palavra do autor.
- **Não posta nada.** Comentário e review só saem quando você mandar —
  inclusive o review inline pronto para postar (`review-<sha7>.json`),
  que `scripts/post-review.sh` recusa publicar se o PR mudou desde que
  foi escrito.
- **Re-review incremental.** Depois de o autor empurrar commits, a
  próxima rodada revisa só o delta e diz o que foi resolvido, o que
  continua aberto e o que é novo — não recomeça do zero.
- **Roda o que for barato.** Typecheck e os testes que o diff tocou rodam
  de verdade, num worktree isolado que nunca mexe no seu working tree e
  nunca instala dependência — falha vira `blocker:` verificado, não
  inferido pela leitura.
- **Passagem de segurança dedicada.** Diff que toca caminho sensível
  (auth, sessão, upload, middleware...), padrão de API perigosa, ou traz
  dependência nova aciona um subagent com lente OWASP restrita a este
  diff — além dos 3–4 itens de segurança de cada checklist de stack.

## Instalação

```bash
npx github:marcelosartor/ms-ai-tools ms-codereview
```

Ele pergunta onde instalar (global, em `~/.claude/skills/`, ou local, em
`./.claude/skills/` do diretório corrente) e qual tracker você usa, para já
preparar o `.env`. Para responder sem prompt:

```bash
npx github:marcelosartor/ms-ai-tools ms-codereview --local --provider jira-cloud
```

Quem clonou o repositório usa `./install.sh ms-codereview`, que chama o mesmo
instalador. Manualmente também funciona:

```bash
mkdir -p ~/.claude/skills && cp -r ms-codereview ~/.claude/skills/
```

Estrutura final:

```
~/.claude/skills/ms-codereview/
├── SKILL.md                    # núcleo do procedimento; carrega inteiro
├── reference/                   # detalhe de um passo específico; carrega só quando esse passo pede
│   ├── contexto.md               # passo 2, só se fetch-context.sh falhar ou o PR for mecânico
│   ├── re-review.md              # passo 2, só se houver relatório anterior
│   ├── comentario.md             # passo 10
│   └── segunda-passagem.md       # passo 11
├── README.md
├── .env.example
├── scripts/
│   ├── fetch-context.sh        # coleta PR + ticket
│   ├── detect-checklists.sh    # decide quais checklists carregar, pelo diff
│   ├── run-checks.sh           # typecheck + testes tocados, num worktree isolado
│   ├── post-review.sh          # publica o review inline — só a pedido do usuário
│   └── providers/
│       ├── clickup.sh
│       ├── jira.sh
│       └── github.sh          # sem variável de .env: usa o gh autenticado
├── prompts/
│   ├── reader.md                 # três leitores independentes (spec/correção/checklist), em paralelo
│   ├── refute.md                # subagent que tenta derrubar cada blocker
│   └── security.md              # subagent de segurança, só quando acionado
├── checklists/
│   ├── index.json               # regras de detecção (dado, não código)
│   ├── common.md                  # always: true — carrega em todo PR
│   ├── ci-infra.md                # workflow, Dockerfile, Terraform, k8s...
│   ├── llm-integration.md         # chamada a modelo, RAG, agente
│   ├── backend-node.md            # carregam só se o diff tocar na camada
│   ├── frontend-vue.md
│   ├── frontend-react.md
│   ├── database-postgres-pgvector.md  # grupo "database": desempate por level quando mais de um casa
│   ├── database-mssql.md
│   ├── database-sqlite-android.md
│   ├── database-mongodb.md
│   ├── android-kotlin.md          # Compose, Views, Room, Hilt por variante
│   └── java-spring.md             # JPA, Spring Security, WebFlux, mensageria por variante
└── tests/
    ├── run.sh                  # bash ms-codereview/tests/run.sh
    └── f*.sh                   # um arquivo por feature, carregados pelo run.sh

~/.config/ms-ai-tools/
├── .env                        # suas credenciais, fora da skill
└── bin/jq                      # dependência baixada pelo instalador
```

### Dependências

| Requisito | Para quê | Como |
|---|---|---|
| `jq` | processar as respostas das APIs (do PR, do ClickUp e do Jira) | **o instalador resolve** — baixa o binário oficial com sha256 conferido |
| `curl` | falar com o tracker | já vem na maioria dos sistemas |
| `gh` autenticado | ler o PR do GitHub | `gh auth login` |

O `jq` é um processador de JSON de linha de comando — nada a ver com Jira,
apesar do nome parecido. É necessário mesmo sem tracker nenhum, porque o
próprio PR chega do `gh` como JSON.

Se faltar, `npx github:marcelosartor/ms-ai-tools --deps` baixa a versão
verificada para `~/.config/ms-ai-tools/bin/`, que a skill põe na frente do
`PATH`. Um `jq` já instalado no sistema é usado como está.

Sem `gh`, a skill ainda revisa um range de refs (`main...HEAD`); só não lê o
PR.

Confira a instalação com `/skills` numa sessão do Claude Code. Se a skill não
aparecer, verifique se o `SKILL.md` está no lugar certo e se o frontmatter
começa na primeira linha do arquivo.

## Uso

```
/ms-codereview 1234          # número do PR
/ms-codereview main...HEAD   # range de refs
/ms-codereview               # branch atual contra a branch padrão
```

O nome do comando vem do nome da pasta, não do campo `name` do frontmatter.
Se renomear a pasta, o comando muda junto.

Como a skill tem `description`, o Claude também pode acioná-la sozinho quando
você pedir uma revisão em linguagem natural.

## Trackers

A skill busca o ticket quando a descrição do PR não deixa claro o que a
mudança deveria fazer. Configure só o tracker que você usa:

O instalador já escreve o bloco do tracker que você escolher. Para fazer à
mão, ou acrescentar um segundo tracker:

```bash
mkdir -p ~/.config/ms-ai-tools
cp ~/.claude/skills/ms-codereview/.env.example ~/.config/ms-ai-tools/.env
# edite e preencha o bloco do seu tracker
```

As credenciais ficam fora da pasta da skill porque a instalação substitui o
diretório inteiro — um `.env` lá dentro se perderia na atualização.
`MS_AI_TOOLS_CONFIG_DIR` muda o local. Um `.env` na raiz da skill continua
sendo lido e **vence** o compartilhado, para sobrepor um valor pontualmente.

| Tracker | Variáveis | Onde pegar |
|---|---|---|
| ClickUp | `CLICKUP_TOKEN` | Settings > Apps > API Token |
| ClickUp com id customizado (`DEV-123`) | `+ CLICKUP_TEAM_ID` | id do workspace na URL |
| Jira Cloud | `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN` | id.atlassian.com/manage-profile/security/api-tokens |
| Jira Server / Data Center | `JIRA_BASE_URL`, `JIRA_TOKEN` (PAT) | Perfil > Personal Access Tokens |
| GitHub Issues | nenhuma — usa o `gh` já autenticado | `gh auth login` |

O `.env` nunca é versionado, nunca entra no pacote npm, nunca é impresso no
relatório e nunca passa pela linha de comando — as credenciais vão para o `curl` por stdin, então não
aparecem em `ps`.

Sem credencial a skill ainda revisa PRs cuja descrição já explica o esperado
— mas rejeita por falta de dados os que não explicam. Provider sem
credencial nem é tentado na descoberta automática do tracker.

Sem tracker nenhum — ou quando o contexto vem de um documento de spec em vez
de ticket — `--spec-file <caminho>` aponta o arquivo a usar como contexto.
Só roda quando passado; não há busca automática em pasta de specs, ver
"Contexto coletado" abaixo.

### Como o tracker é escolhido

Pelo formato do id encontrado no corpo do PR ou no nome da branch:

| Encontrado | Vai para |
|---|---|
| `app.clickup.com/t/86ajrqjc7`, badge `ClickUp-86ajrqjc7-`, `feat/86ajrqjc7` | ClickUp |
| `.../browse/DEV-142`, `?selectedIssue=DEV-142`, `feat/DEV-142-corrige-saldo` | Jira |
| `Closes #123` do PR do GitHub, `#123`, `owner/repo#123`, branch `123-corrige-saldo` | GitHub Issues |

Prefixo de conventional commit não é confundido com chave de projeto:
`fix/123-ajuste` não vira `FIX-123`.

O único caso ambíguo é o id customizado do ClickUp (`DEV-123`), que tem a
mesma cara de uma chave do Jira e por isso cai no Jira por padrão. Se o seu
ClickUp usa esse formato, fixe `TRACKER_PROVIDER=clickup` no `.env`.

GitHub Issues entra em último na ordem de descoberta — só é candidato
automático se `gh` estiver autenticado e nenhum outro tracker tiver
credencial configurada, para não roubar id de quem já usa ClickUp ou
Jira.

Para forçar pontualmente, use `--provider` na chamada do script.

## Contexto coletado

`scripts/fetch-context.sh` é a parte determinística da revisão. A skill o
chama sozinha, mas ele roda à mão para depurar:

```bash
scripts/fetch-context.sh 158                    # PR + ticket descoberto sozinho
scripts/fetch-context.sh 158 --task DEV-142     # força o id do ticket
scripts/fetch-context.sh 158 --provider jira    # força o tracker
scripts/fetch-context.sh 158 --spec-file docs/specs/refund.md  # sem tracker: arquivo local
scripts/fetch-context.sh --help
```

`--spec-file` é o caminho para quem não usa ClickUp nem Jira: aponta um
arquivo (PRD, spec, ata de reunião — qualquer Markdown ou texto) para virar
o contexto da revisão, gravado no mesmo `raw/ticket.md` que um tracker
geraria. Só roda quando passado explicitamente — sem ele, a skill nem tenta
esse caminho — e não pode ser combinado com `--task`/`--provider`. Não há
descoberta automática de qual arquivo usar dentro de um diretório: o
casamento entre PR e documento é ambíguo sem uma convenção de nome
garantida, e adivinhar errado é pior que não ter contexto nenhum.

Grava em `temp/cr/<pr>/raw/`, dentro do repositório revisado:

| Arquivo | Conteúdo |
|---|---|
| `pr.json`, `pr-body.md`, `pr-files.tsv`, `pr-comments.md` | o PR |
| `ticket.md` | o ticket em Markdown — mesmo formato para todo tracker |
| `ticket.json`, `ticket-comments.json` | resposta crua da API |
| `context-status.json` | o que deu certo, o tracker usado, se o PR é mecânico, `head_sha`/`base_sha` do diff, `previous_report`/`previous_sha` da rodada anterior (se houver), `previous_is_ancestor` (se o sha anterior ainda é ancestral do head — `false`/`null` indica rebase ou force-push), `previous_base_sha`/`base_moved`, e o motivo do que faltou |
| `checklists.json` | quais checklists carregar e por quê (`load`/`why`), quais variantes de cada um casaram (`variants`), e se o diff aciona a passagem de segurança dedicada (`security`/`security_why`) — gerado sempre, independente do ticket |
| `advisories.md` | GHSA de dependência nova ou com versão alterada em manifesto tocado (npm, Maven/Gradle), consultado no GitHub Advisory Database; `não consultado (<motivo>)` sem `gh` ou com erro da API — nunca bloqueia a coleta |
| `ci.json`, `ci.md` | estado de cada check do PR (`gh pr checks`) — check vermelho é `blocker:` mesmo sem verificação local |

Revisão do mesmo alvo depois de o autor empurrar commits é incremental: a
skill grava `temp/cr/<alvo>/report-<sha7>.md` a cada rodada, e a próxima
lê `previous_report`/`previous_sha` em `context-status.json` para revisar
só o delta e marcar achado anterior como resolvido, aberto ou novo.

PR mecânico (bump de dependência, formatação, rename, doc) dispensa ticket:
o script classifica sozinho pelo diff (`mechanical`/`mechanical_kind` em
`context-status.json`) e, quando reconhece um, nem tenta ticket nem
`--spec-file` — a própria mudança já é a spec.

O script acrescenta `temp/` ao `.gitignore` do projeto na primeira execução
— só se o caminho ainda não estiver ignorado, e criando o arquivo se não
existir. `CR_SKIP_GITIGNORE=1` desliga esse comportamento; `CR_BASE_DIR` muda
onde o `temp/` é criado.

### Códigos de saída

| Código | Significado | O que fazer |
|---|---|---|
| `0` | contexto obtido | — |
| `2` | erro de uso, `jq`/`curl` ausente, ou `--spec-file` inválido/combinado com `--task`/`--provider` | ver `--help`; para o `jq`, rodar o instalador com `--deps` |
| `3` | id do ticket não encontrado | rodar de novo com `--task <id>` |
| `4` | credencial do tracker ausente, ou nenhum tracker configurado | preencher o `.env`, forçar `--provider`, ou usar `--spec-file` |
| `5` | o tracker recusou ou não devolveu o ticket | conferir o id, o token e o `reason` em `context-status.json` |

`3`, `4` e `5` são "faltou dado", não "deu ruim": a skill tenta o caminho
manual antes de desistir.

## Saída

Cada revisão devolve três blocos, nesta ordem:

1. **Achados** — `blocker:` / `sugestão:` / `nit:` / `dúvida:`, cada um com
   `arquivo:linha` e o efeito concreto, mais o que ficou bom no PR.
2. **Recomendação** — *Aprovar*, *Aprovar com ressalvas* ou *Rejeitar*,
   derivada mecanicamente da severidade dos achados, com o que precisaria
   mudar para virar o veredito, e uma frase sobre o que a revisão **não**
   cobriu. É insumo: quem decide é você.
3. **Comentário para o PR** — rascunho pronto para colar, na primeira pessoa,
   no idioma do PR e sem o jargão de severidade da skill. Junto, a skill
   grava `temp/cr/<pr>/review-<sha7>.json` no formato de review inline do
   GitHub (`comments[]` com `path`/`line`/`body`).

## Verificações (typecheck e testes)

```bash
scripts/run-checks.sh 158
```

Cria um worktree isolado no `head_sha` — nunca mexe no seu working tree —,
agrupa os arquivos tocados por `package.json` **mais próximo** (monorepo:
um pacote por manifesto, cada um com seu próprio `typecheck`/`lint`/teste),
reaproveita `node_modules` já instalado via symlink quando o diff não
altera dependências (o do próprio pacote se existir, senão o da raiz —
hoisting de workspace; nunca roda `npm install`), detecta `typecheck`/
`lint` em cada `package.json` (ou `tsc --noEmit` direto, se houver
`tsconfig.json` e `typescript` instalado) e o runner de teste (`vitest` ou
`jest`) em `node_modules/.bin`. Roda só os arquivos de teste que o diff
tocou, mais os que importam algum arquivo tocado pelo caminho relativo
(`'../src/a/b'`, não pelo nome nu — `index.ts` não casa a suíte inteira).

Quando typecheck ou teste falha no head, monta um segundo worktree em
`base_sha` (`temp/cr/<alvo>/wt-base`, sempre removido ao final) e roda o
mesmo comando lá: erro de typecheck que já existia na base sai da lista
(`checks.json` marca `preexisting`); teste que já falhava na base entra
como pré-existente, não como falha do PR. Sem `package.json` no caminho de
nenhum arquivo tocado, mas com `pom.xml`/`build.gradle*` no caminho, o
script registra "stack fora do Node" e sai `0` — Java/Android não rodam
aqui (fora de escopo desta versão).

`--keep` mantém o worktree do head vivo depois do script sair (caminho em
`checks.json.worktree`); sem a flag, é removido ao sair. O worktree da
base é sempre removido pelo próprio script.

`--prove-fix`, quando o diff toca arquivo de teste: copia esse arquivo por
cima do worktree da base (o código de produção continua sendo o da base,
sem o fix) e roda lá. `checks.json.prove_fix`: `"proves"` (falhou na
base, passa no head — o teste cobre o bug), `"does_not_prove"` (passa nos
dois — vira sugestão no relatório), `"inconclusive"` (erro de compilação
ou import na base), `null` (sem `--prove-fix`, ou nenhum teste tocado).

Grava `raw/checks-result.md` (legível, com a saída de quem falhou, por
pacote) e `raw/checks.json` (estruturado: resumo agregado no topo —
`deps`/`typecheck`/`lint`/`test` — e detalhe por pacote em `packages:
[{dir, typecheck, lint, test}]`). Teste e typecheck que falham são
`blocker:` no relatório da skill; lint que falha, não — cai na regra de não
reportar o que já é coberto por lint do CI.

Sai `0` se tudo que rodou passou (mesmo que nada tenha rodado, ou a stack
seja fora do Node), `1` se algo falhou (descontada a baseline), `2` se não
conseguiu montar o worktree do head.

## Publicar o review

```bash
scripts/post-review.sh <pr>                 # usa o review-<sha7>.json mais recente
scripts/post-review.sh <pr> --sha <sha7>    # força uma rodada específica
```

A skill nunca chama este script sozinha. Ele confere que o `commit_id`
gravado no JSON ainda é o head atual do PR antes de postar — se o PR mudou
desde que o review foi escrito (novo commit empurrado), recusa com exit `3`
e pede para revisar de novo, em vez de postar comentário na linha errada.
Também confere, com `gh pr diff`, que cada `comments[].line` (e
`start_line`, se houver) cai dentro de um hunk do diff atual — GitHub
recusa com HTTP 422 um comentário fora do diff, e aqui isso vira exit `5`
antes de qualquer coisa ser postada, nem parcialmente.

Item de `comments[]` com bloco ```` ```suggestion ``` ```` sai como
sugestão commitável no GitHub — a pessoa aceita com um clique em vez de
editar à mão.

| Código | Significado |
|---|---|
| `0` | publicado |
| `2` | erro de uso: sem PR numérico, `review-*.json` ausente, ou JSON inválido |
| `3` | `commit_id` do review diverge do head atual do PR |
| `4` | `gh` recusou a publicação |
| `5` | algum `comments[]` aponta para linha fora do diff atual |

## Testes

```bash
bash ms-codereview/tests/run.sh
```

Harness em bash puro: monta fixtures de repositório git em diretório
temporário, roda os scripts de verdade e confere exit code e campos do
JSON gerado. Cada arquivo `tests/f<N>.sh` cobre uma feature; `run.sh` os
carrega todos e imprime a contagem final.

## Manutenção

Edite este repositório, não a cópia instalada. A instalação substitui o
diretório da skill inteiro; o instalador guarda o que você tiver mudado em
`~/.config/ms-ai-tools/backups/` e avisa, mas restaurar é manual. Mudança
feita aqui e comitada sobrevive sozinha a toda atualização.

Corte o que não usar. Regra que fica na lista mas nunca gera achado só dilui
as que importam.

Adicione uma linha toda vez que se pegar escrevendo o mesmo comentário pela
terceira vez em PRs diferentes. Essa é a única fonte confiável de regra boa.

Regra que só vale para um cliente ou um projeto não entra aqui: ela vive no
`CLAUDE.md` daquele repositório, que já tem precedência sobre este checklist.

O `SKILL.md` carrega inteiro quando a skill é acionada; `reference/` carrega
por passo — só o arquivo do passo que precisa dele, e só quando a condição
daquele passo bate (relatório anterior existe, PR mecânico, script de
contexto falhou); `checklists/` carrega pelo diff, decidido por
`scripts/detect-checklists.sh` a partir de `checklists/index.json`, não por
julgamento na hora. Texto novo vai para o arquivo do passo que o usa, não
para o `SKILL.md` — salvo regra que molda a revisão inteira (calibragem,
barra de verificação, formato do relatório, veredito): essa fica no núcleo
mesmo crescendo, porque toda revisão a lê de qualquer forma.

### Adicionar um checklist novo

Criar `checklists/<nome>.md` e uma entrada em `checklists/index.json` com
pelo menos uma destas chaves:

| Chave | Casa quando |
|---|---|
| `paths` | algum arquivo do diff bate com o glob (`**/` no início também casa sem prefixo de diretório) |
| `deps` | a dependência está em `dependencies`/`devDependencies` do `package.json` **mais próximo** de algum arquivo `.ts`/`.tsx`/`.js`/`.jsx`/`.vue` tocado (monorepo: cada arquivo usa o manifesto do seu próprio diretório, subindo até achar um) |
| `manifest` | `{files, pattern, ext}` — algum arquivo tocado tem extensão em `ext`, e o manifesto mais próximo dele (primeiro nome de `files` encontrado subindo diretórios) contém `pattern` (`grep -qiE`). Base de `deps` para ecossistema fora do npm (Maven, Gradle) |
| `always` | `true`: carrega sempre que o diff tiver ao menos um arquivo, `why: "always"` — para o checklist transversal que toda revisão lê |
| `content` | a regex (ERE, case-insensitive) aparece numa linha adicionada do diff |
| `variants` | `{<nome>: {deps?, manifest?, paths?, content?}}` — mesma semântica das chaves acima, mas não decide se o checklist carrega: só quais seções dele aplicar. Entra na saída em `variants.<checklist>` quando casar |
| `paths_require_manifest` | `true`: `paths` só conta se `manifest` também casar — para padrão de arquivo genérico (`**/*.kts`) que sozinho não deve carregar o checklist num projeto de stack diferente |
| `exclusive_group` | Nome do grupo de desempate (ex.: `database`). Todo checklist do grupo é avaliado por completo (`paths`, `deps`, `manifest`, `content`, sem parar no primeiro), e só ficam os de `level` máximo do grupo — empate mantém todos. Descartado some de `load`/`why` e aparece em `suppressed` |

Fora de um `exclusive_group`, a detecção também passou a avaliar todos os
métodos (não só o primeiro que casar): `why` lista todos, separados por
`; `, e cada entrada carrega um `level` (`deps`/`manifest` = 3, `content`
= 2, `paths` = 1, `always` = 0 — nunca participa de grupo), usado só para
o desempate dentro de um grupo.

Qualquer uma basta; não precisa de todas. `index.json` é dado, não código —
adicionar checklist não toca `detect-checklists.sh`.

A passagem de segurança (`security`/`security_why`) é separada dos
checklists de stack: os padrões que a acionam (caminho sensível, API
perigosa, dependência nova) estão hardcoded em `detect-checklists.sh`, não
em `index.json` — mudar isso é editar o script, não o dado.

### Adicionar um tracker novo

Cada tracker é um arquivo em `scripts/providers/` que implementa quatro
funções, todas com o prefixo do nome do arquivo:

| Função | Contrato |
|---|---|
| `<p>_extract <strong\|weak>` | lê texto no stdin, imprime o id do ticket. `strong` = URL ou badge do tracker; `weak` = chave solta ou slug de branch |
| `<p>_id_matches <id>` | `0` se o id tem o formato deste tracker |
| `<p>_credentials` | define `AUTH_HEADER`; sem credencial, define `REASON` e devolve `1` |
| `<p>_fetch <id>` | grava `$RAW/ticket.md` e `$RAW/ticket.json`; em falha, define `REASON` e devolve `1` |

Use `http_get <url> <arquivo>` para as chamadas: ele devolve o HTTP code e
passa a credencial por stdin, fora do `argv`. Depois some o nome do arquivo à
lista `PROVIDERS` em `fetch-context.sh` e documente as variáveis no
`.env.example`. `providers/github.sh` foge um pouco do contrato porque não
tem variável própria: `<p>_credentials` confere `gh auth status` em vez de
ler `.env`, e entra por último em `PROVIDERS` para não roubar id de quem já
tem ClickUp ou Jira configurado.

O resto da skill não muda: `ticket.md` tem o mesmo formato para todo tracker,
então o `SKILL.md` não precisa saber qual está em uso.

## Relação com o /code-review

São coisas diferentes e complementares:

- `/code-review` é o comando nativo do Claude Code, roda em subagent próprio
  e caça bugs de correção
- `/ms-codereview` é este checklist, com contexto de ticket, o seu critério de
  severidade e o seu formato de saída

Usar os dois no mesmo PR e cruzar os resultados é melhor que escolher um.
