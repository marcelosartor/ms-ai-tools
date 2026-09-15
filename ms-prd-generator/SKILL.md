---
name: ms-prd-generator
description: Gera um PRD (Product Requirements Document) em markdown a partir de um ticket de board, um arquivo local ou texto colado — base do fluxo de Spec-Driven Development (SDD) do pool. Use quando o usuário pedir para gerar um PRD, formalizar uma especificação a partir de um ticket ou de um contexto bruto, ou preparar a entrada para planejamento/implementação de uma feature. Aceita --ticket <id>, --file <caminho> ou --text "<conteúdo>".
license: Apache-2.0
metadata:
  version: 0.1.0
---

# Geração de PRD

Gerar o PRD a partir da origem indicada em `$ARGUMENTS`, sempre com uma das
três flags — sem flag, perguntar qual origem o usuário quer usar:

- `--ticket <id>` — busca o contexto no board via a skill
  `ms-context-raw-generator` (precisa estar instalada; se não estiver,
  avisar e parar — não tentar buscar o board sem ela).
- `--file <caminho>` — usa o conteúdo do arquivo indicado como contexto
  bruto, direto, sem passar por um contexto intermediário.
- `--text "<conteúdo>"` — usa o texto colado como contexto bruto, direto,
  da mesma forma.

`--refresh` (só combinada com `--ticket`) força a `ms-context-raw-generator`
a buscar o ticket de novo em vez de reaproveitar um contexto já gerado.

## Onde o PRD é gravado

```
temp/prd/prd-<identificador>.md
```

`<base>` é a raiz do projeto onde a skill está rodando (o diretório atual),
não o pool `ms-ai-tools`. O identificador segue esta prioridade:

1. `--ticket <id>` → o próprio id do ticket.
2. `--file <caminho>` → o nome do arquivo, sem extensão, em minúsculas,
   espaços e caracteres especiais virando `-`.
3. `--text` → sequencial `seqNNN`, calculado a partir do que já existe em
   `temp/prd/`.

Calcular com `scripts/prd-number.sh --ticket <id>` / `--file <caminho>` /
`--text` — não inventar o identificador à mão, é assim que duas execuções
para a mesma origem batem no mesmo nome de arquivo.

## Procedimento

1. **Obter o contexto bruto**, conforme a origem:

   - **Ticket**: invocar a skill `ms-context-raw-generator` com o id (e
     `--refresh`, se passado). Ela devolve o caminho de
     `temp/<ticket>/context-raw/context-raw-<ticket>.md` — ler esse
     arquivo inteiro como contexto. Se a skill não estiver instalada ou
     falhar (credencial ausente, ticket não encontrado), reportar o
     motivo ao usuário e parar — não gerar PRD a partir de suposição.
   - **Arquivo**: ler o arquivo indicado inteiro.
   - **Texto**: usar o conteúdo passado, direto.

2. **Calcular o identificador** com `scripts/prd-number.sh`, conforme a
   origem (ver acima).

3. **Checar se o PRD já existe.** Se `temp/prd/prd-<identificador>.md` já
   existir, perguntar ao usuário se quer sobrescrever antes de continuar —
   nunca sobrescrever sem perguntar, nunca versionar sozinho (`-v2` etc.).

4. **Escrever o PRD** em `temp/prd/prd-<identificador>.md`, com estas
   seções:

   - `# PRD: <título>` — título do ticket/arquivo, ou uma frase curta que
     resuma o texto colado.
   - `## Objetivo` — o problema que este PRD resolve e para quem, em
     poucas frases.
   - `## Contexto` — o que já existe hoje e por que essa entrega é
     necessária; citar a origem (ticket/arquivo/texto) explicitamente.
   - `## Requisitos` — lista objetiva do que a entrega precisa fazer,
     numerada, uma frase testável por item. Requisito que o contexto não
     deixa claro entra em Lacunas, não é inferido.
   - `## Fora de escopo` — o que fica de fora desta entrega, quando o
     contexto sugerir um limite (ex.: uma etapa futura mencionada mas não
     pedida agora).
   - `## Critérios de aceite` — como verificar que cada requisito foi
     atendido; um item por requisito, quando possível.
   - `## Lacunas` — pergunta que o contexto não responde e que quem for
     implementar vai precisar decidir ou perguntar. Nunca inventar a
     resposta para preencher a lacuna.

   Cada afirmação do PRD precisa rastrear até algo que está no contexto
   bruto — este documento formaliza o que foi pedido, não adiciona
   requisito novo por conta própria.

5. **Reportar.** Dizer o caminho do arquivo final.

## Erros e dados incompletos

Contexto insuficiente para preencher uma seção não é motivo para inventar
conteúdo — vira item em Lacunas, ou (se nem o objetivo geral dá para
estabelecer) motivo para parar e pedir mais contexto ao usuário antes de
gerar o PRD.
