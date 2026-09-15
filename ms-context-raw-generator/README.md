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

### Configuração

Requer `jq` e `curl`, e a credencial do board que você usa — mesmas
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
