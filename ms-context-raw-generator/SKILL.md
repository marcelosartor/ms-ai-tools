---
name: ms-context-raw-generator
description: Gera um documento de contexto bruto em markdown a partir de um ticket de board (ClickUp, Jira ou Linear) — texto, comentários e anexos, incluindo descrição de imagens e PDFs escaneados. Use quando o usuário pedir o contexto completo de um ticket, um "dossiê" ou "contexto bruto" de uma atividade, ou quando outra skill do pool (ex.: ms-prd-generator) precisar desse contexto para gerar um documento derivado. Aceita o id do ticket como argumento.
license: Apache-2.0
metadata:
  version: 0.1.0
---

# Contexto bruto de um ticket

Gerar o contexto bruto do ticket indicado em `$ARGUMENTS` (o id do ticket,
ex.: `86ajrqjc7`, `ABC-123`, `ENG-123`). Flags aceitas junto ao id:

- `--provider clickup|jira|linear` — força o board, quando o formato do id
  é ambíguo (Jira e Linear usam o mesmo formato `CHAVE-123`) ou quando o
  usuário já sabe qual é.
- `--refresh` — ignora qualquer contexto bruto já gerado para este ticket e
  busca tudo de novo.

Sem id, perguntar qual ticket.

## O que esta skill produz

Um único arquivo, autocontido — quem o lê não precisa abrir o board:

```
temp/<ticket>/context-raw/context-raw-<ticket>.md
```

`<base>` é a raiz do projeto onde a skill está rodando (o diretório atual),
não o pool `ms-ai-tools`. Todo dado de coleta fica em
`temp/<ticket>/context-raw/raw/`, ao lado do arquivo final.

## Procedimento

1. **Checar reaproveitamento.** Se `temp/<ticket>/context-raw/context-raw-<ticket>.md`
   já existe e `--refresh` não foi passado: perguntar ao usuário se quer
   reaproveitar o contexto já gerado (mostrar a data de modificação do
   arquivo) ou gerar de novo. Reaproveitar encerra aqui, informando o
   caminho do arquivo. Gerar de novo segue para o passo 2 como se
   `--refresh` tivesse sido passado.

2. **Coletar dados brutos.** Rodar, na raiz do projeto:

   ```bash
   scripts/fetch-raw-context.sh <ticket> [--provider <board>] [--refresh]
   ```

   O script é determinístico: descobre o board pelo formato do id (ou usa
   o forçado por `--provider`), busca o ticket, os comentários e a lista de
   anexos, baixa cada anexo e já extrai texto dos que dá para extrair sem
   IA (markdown, txt, json, csv, log, yml, sql, html, xml, e PDF com
   camada de texto via `pdftotext`). Grava tudo em `raw/`:

   - `raw/ticket.md` — dossiê do ticket (título, metadados, descrição,
     campos personalizados, comentários), já em markdown.
   - `raw/attachments-manifest.md` — uma linha por anexo, dizendo se foi
     extraído automaticamente (e onde está o texto) ou se precisa de
     leitura direta (e onde está o arquivo baixado).
   - `raw/attachments/` — os anexos baixados e, quando houve extração, o
     `.extraido.txt` correspondente.

   Códigos de saída diferentes de `0`:
   - `2` erro de uso — corrigir o comando e tentar de novo.
   - `3` id não corresponde ao formato de nenhum board conhecido —
     perguntar ao usuário qual board é e rodar de novo com `--provider`.
   - `4` credencial ausente — dizer qual variável falta e em qual arquivo
     ela deveria estar (a mensagem do script já traz isso); a skill não
     continua sem credencial.
   - `5` o board recusou ou não encontrou o ticket — mostrar o motivo (na
     mensagem do script) ao usuário; a skill não inventa conteúdo no lugar
     do que não veio.

3. **Descrever os anexos sem extração automática.** Ler
   `raw/attachments-manifest.md`. Para cada anexo marcado "sem extração
   automática", abrir o arquivo indicado em `raw/attachments/` com a
   ferramenta de leitura (ela lê imagem e PDF diretamente) e escrever uma
   descrição objetiva do que ele mostra — não é para transcrever o
   arquivo inteiro, é para alguém que não vai abri-lo entender do que se
   trata. PDF sem camada de texto entra aqui também (é assim que o
   `attachments-manifest.md` o marca).

4. **Escrever o contexto bruto.** Montar
   `temp/<ticket>/context-raw/context-raw-<ticket>.md` com, nesta ordem:

   - O conteúdo de `raw/ticket.md` (título, metadados, descrição, campos
     personalizados, comentários) — sem reescrever, é dado do board.
   - `## Anexos`: um item por anexo — texto extraído automaticamente
     (inline, ou resumido se for muito longo, citando o caminho do
     arquivo completo em `raw/attachments/`) ou a descrição escrita no
     passo 3.
   - `## Síntese`: um parágrafo curto, escrito por você, contando do que
     se trata o ticket — o problema, o que se pede, qualquer restrição
     que apareça na descrição/comentários/anexos. Não é resumo do
     resumo: é a leitura de quem juntou as peças, para quem só vai ler
     esta seção decidir se precisa abrir o resto.

5. **Reportar.** Dizer o caminho do arquivo final. Se a skill foi chamada
   por outra skill (ex.: `ms-prd-generator`), devolver o caminho para
   quem chamou, sem perguntar mais nada.

## Erros e dados incompletos

Nunca inventar conteúdo de ticket, comentário ou anexo que o board não
devolveu. Campo vazio ou anexo que falhou no download aparece como tal no
documento final (o `attachments-manifest.md` já registra o motivo) — não
é preenchido com suposição.
