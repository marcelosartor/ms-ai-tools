# ms-context-raw-generator

## Descrição

Gera um documento de contexto bruto em markdown a partir de um ticket de
board — **ClickUp**, **Jira** (Cloud e Server/DC) ou **Linear**. O
documento traz título, metadados, descrição, campos personalizados,
comentários e os anexos do ticket: texto extraído automaticamente onde dá
(markdown, txt, json, csv, log, yml, sql, html, xml, PDF com camada de
texto), e descrição escrita pela IA para imagem ou PDF escaneado, onde não
dá. O resultado é autocontido — quem o lê não precisa abrir o board.

Pensada para ser a base do fluxo de Spec-Driven Development (SDD) do pool
[ms-ai-tools](../README.md): outra ferramenta da etapa de especificação
(`ms-prd-generator`) a chama para montar o contexto que vai virar PRD, mas
ela também roda sozinha, quando o que se quer é só o dossiê do ticket.

A coleta (busca no board, download de anexo, extração de texto puro/PDF) é
toda determinística, por script — só a descrição de anexo sem texto
extraível e a síntese final do documento passam pela IA.

## Como usar

```bash
/ms-context-raw-generator <ticket>
/ms-context-raw-generator <ticket> --provider jira    # força o board
/ms-context-raw-generator <ticket> --refresh            # ignora o cache e busca de novo
```

Exemplos:

```bash
/ms-context-raw-generator 86ajrqjc7
/ms-context-raw-generator ENG-451 --provider linear
```

Grava em `temp/<ticket>/context-raw/context-raw-<ticket>.md`, na raiz do
projeto onde a skill está rodando (não no pool). Os dados brutos da coleta
ficam ao lado, em `temp/<ticket>/context-raw/raw/`.

Rodar de novo para o mesmo ticket, sem `--refresh`, pergunta se você quer
reaproveitar o que já foi gerado ou buscar tudo de novo.

### Segurança: prompt injection

Descrição, comentário e anexo de ticket são escritos por qualquer pessoa
com acesso ao ticket, e a IA os lê. Por isso o que vem do board é tratado
como dado, nunca instrução. `scripts/fetch-raw-context.sh` faz, por
script (a lógica está em `scripts/untrusted.sh`, idêntica à do
`ms-codereview`):

- remove do texto caracteres invisíveis (zero-width, bidi, Unicode
  tags), de controle e comentários HTML — os jeitos mais baratos de
  esconder instrução de quem lê o ticket renderizado;
- envolve `ticket.md`, `attachments-manifest.md` e cada
  `attachments/*.extraido.txt` num bloco
  `<dado-nao-confiavel marca="…">`, com marca aleatória por execução: o
  texto de dentro não consegue fechar o bloco e escrever depois dele
  como se fosse instrução. O bloco vai junto para o contexto final,
  então quem o ler depois (ex.: o `ms-prd-generator`) sabe onde termina
  o dado;
- registra em `raw/suspeitas.md` arquivo e linha de cada sinal (frases
  de troca de papel, "ignore as instruções", comando remoto, pedido de
  leitura de segredo, base64 longo, texto escondido por estilo). Nunca
  cita o trecho, para não reinjetar o ataque. `injection_signals` em
  `context-status.json` traz a contagem, e o script avisa ao terminar.

**O que isso não garante.** É heurística: `suspeitas.md` vazio não prova
que o ticket é seguro, e os padrões são fáceis de contornar. Imagem e PDF
escaneado não passam pelo script — a IA os lê direto, e o `SKILL.md` só
pede que ela descreva sem obedecer e sinalize. O que sobra é o seu olho:
com sinais, leia o ticket no board antes de usar o contexto.

Para limitar o que uma injeção bem-sucedida alcança, veja
[Conteúdo de terceiros e prompt injection](../README.md#conteúdo-de-terceiros-e-prompt-injection)
no README do pool.

### Testes

```bash
bash ms-context-raw-generator/tests/run.sh
```

Bash puro, com um `curl` falso no `PATH`: roda o script de verdade contra
um ClickUp de mentira com um ticket carregado de injeção e confere a
higienização, os blocos marcados, os sinais e o cache.

### Configuração

Requer `jq`, `curl` e `perl` (sem `perl` a higienização é pulada e isso fica registrado em `suspeitas.md`), e a credencial do board que você usa — mesmas
variáveis do `ms-codereview`, compartilhadas pelo mesmo
`~/.config/ms-ai-tools/.env` quando as duas ferramentas estão instaladas
(veja [`.env.example`](.env.example)):

| Board | Variáveis |
|---|---|
| ClickUp | `CLICKUP_TOKEN` (`CLICKUP_TEAM_ID` só para id customizado) |
| Jira Cloud | `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN` |
| Jira Server/DC | `JIRA_BASE_URL`, `JIRA_TOKEN` |
| Linear | `LINEAR_API_KEY` |

Sem `--provider`, o board é descoberto pelo formato do id do ticket. Jira e
Linear usam o mesmo formato (`CHAVE-123`); com os dois configurados, o
desempate favorece o Jira — force `--provider linear` quando for o caso.

### Limite conhecido: anexo do Linear

O Linear não tem um campo de anexo tão direto quanto o `attachments[]` do
ClickUp ou o `attachment[]` do Jira. A conexão `attachments` da API é para
link externo (PR do GitHub, arquivo do Figma) — entra no documento como
referência, não como arquivo baixado. Arquivo de verdade (screenshot
colado, upload direto na descrição ou num comentário) vira um link
`https://uploads.linear.app/...` embutido no markdown, e é isso que a
ferramenta garimpa por busca de padrão — funciona para o caso comum, mas
não é garantia de pegar todo anexo em todo formato futuro da API.
