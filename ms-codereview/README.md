# ms-codereview v0.1.0

Revisão de pull request de terceiros para o Claude Code: cruza o ticket, a
descrição do PR e o diff, e fecha com um veredito e um rascunho de
comentário pronto para colar.

Faz parte do pool [ms-ai-tools](../README.md). A versão da skill fica em
`metadata.version` no `SKILL.md`, e o instalador mostra a transição ao
atualizar.

A skill parte de um revisor externo — alguém que não escreveu o código e
muitas vezes não conhece o projeto a fundo. Por isso ela exige saber o que o
PR **deveria** fazer antes de julgar o que ele faz, e por isso é agnóstica a
projeto e a cliente: o que sabe do domínio vem do `CLAUDE.md` do repositório
revisado e do ticket, nunca de regra embutida aqui.

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
- **Segunda passagem.** Antes de entregar, relê cada achado contra o código e
  descarta o que não se sustenta. Falso positivo em PR de terceiro custa a
  credibilidade de quem assina.
- **Não posta nada.** Comentário e review só saem quando você mandar.

## Instalação

```bash
npx github:marcelosartor/ms-ai-tools ms-codereview
```

Quem clonou o repositório usa `./install.sh ms-codereview`, que chama o mesmo
instalador. Manualmente também funciona:

```bash
mkdir -p ~/.claude/skills && cp -r ms-codereview ~/.claude/skills/
```

Estrutura final:

```
~/.claude/skills/ms-codereview/
├── SKILL.md                    # o procedimento de revisão; carrega inteiro
├── README.md
├── .env.example
├── scripts/
│   ├── fetch-context.sh        # coleta PR + ticket
│   └── providers/
│       ├── clickup.sh
│       └── jira.sh
└── checklists/                 # carregam só se o diff tocar na camada
    ├── backend-node-nest.md
    └── frontend-vue.md

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

O `.env` nunca é versionado, nunca entra no pacote npm, nunca é impresso no
relatório e nunca passa pela linha de comando — as credenciais vão para o `curl` por stdin, então não
aparecem em `ps`.

Sem credencial a skill ainda revisa PRs cuja descrição já explica o esperado
— mas rejeita por falta de dados os que não explicam.

### Como o tracker é escolhido

Pelo formato do id encontrado no corpo do PR ou no nome da branch:

| Encontrado | Vai para |
|---|---|
| `app.clickup.com/t/86ajrqjc7`, badge `ClickUp-86ajrqjc7-`, `feat/86ajrqjc7` | ClickUp |
| `.../browse/DEV-142`, `?selectedIssue=DEV-142`, `feat/DEV-142-corrige-saldo` | Jira |

Prefixo de conventional commit não é confundido com chave de projeto:
`fix/123-ajuste` não vira `FIX-123`.

O único caso ambíguo é o id customizado do ClickUp (`DEV-123`), que tem a
mesma cara de uma chave do Jira e por isso cai no Jira por padrão. Se o seu
ClickUp usa esse formato, fixe `TRACKER_PROVIDER=clickup` no `.env`.

Para forçar pontualmente, use `--provider` na chamada do script.

## Contexto coletado

`scripts/fetch-context.sh` é a parte determinística da revisão. A skill o
chama sozinha, mas ele roda à mão para depurar:

```bash
scripts/fetch-context.sh 158                    # PR + ticket descoberto sozinho
scripts/fetch-context.sh 158 --task DEV-142     # força o id do ticket
scripts/fetch-context.sh 158 --provider jira    # força o tracker
scripts/fetch-context.sh --help
```

Grava em `temp/cr/<pr>/raw/`, dentro do repositório revisado:

| Arquivo | Conteúdo |
|---|---|
| `pr.json`, `pr-body.md`, `pr-files.tsv`, `pr-comments.md` | o PR |
| `ticket.md` | o ticket em Markdown — mesmo formato para todo tracker |
| `ticket.json`, `ticket-comments.json` | resposta crua da API |
| `context-status.json` | o que deu certo, o tracker usado e o motivo do que faltou |

O script acrescenta `temp/` ao `.gitignore` do projeto na primeira execução
— só se o caminho ainda não estiver ignorado, e criando o arquivo se não
existir. `CR_SKIP_GITIGNORE=1` desliga esse comportamento; `CR_BASE_DIR` muda
onde o `temp/` é criado.

### Códigos de saída

| Código | Significado | O que fazer |
|---|---|---|
| `0` | contexto obtido | — |
| `2` | erro de uso, ou `jq`/`curl` ausente | ver `--help`; para o `jq`, rodar o instalador com `--deps` |
| `3` | id do ticket não encontrado | rodar de novo com `--task <id>` |
| `4` | credencial do tracker ausente | preencher o `.env` |
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
   no idioma do PR e sem o jargão de severidade da skill.

## Manutenção

Corte o que não usar. Regra que fica na lista mas nunca gera achado só dilui
as que importam.

Adicione uma linha toda vez que se pegar escrevendo o mesmo comentário pela
terceira vez em PRs diferentes. Essa é a única fonte confiável de regra boa.

Regra que só vale para um cliente ou um projeto não entra aqui: ela vive no
`CLAUDE.md` daquele repositório, que já tem precedência sobre este checklist.

O `SKILL.md` carrega inteiro quando a skill é acionada; os checklists só
carregam se o diff tocar naquela camada. Por isso vale manter o `SKILL.md`
enxuto e engordar os checklists.

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
`.env.example`.

O resto da skill não muda: `ticket.md` tem o mesmo formato para todo tracker,
então o `SKILL.md` não precisa saber qual está em uso.

## Relação com o /code-review

São coisas diferentes e complementares:

- `/code-review` é o comando nativo do Claude Code, roda em subagent próprio
  e caça bugs de correção
- `/ms-codereview` é este checklist, com contexto de ticket, o seu critério de
  severidade e o seu formato de saída

Usar os dois no mesmo PR e cruzar os resultados é melhor que escolher um.
