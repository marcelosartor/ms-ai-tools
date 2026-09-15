# ms-prd-generator

## Descrição

Gera um PRD (Product Requirements Document) em markdown a partir de um
ticket de board, um arquivo local ou texto colado. O PRD formaliza o que
foi pedido — objetivo, requisitos, fora de escopo, critérios de aceite e
lacunas — para servir de base ao restante do fluxo de Spec-Driven
Development (SDD) do pool [ms-ai-tools](../README.md): quem implementa
depois trabalha a partir do PRD, não do ticket bruto.

Quando a origem é um ticket, a coleta de contexto (texto, comentários,
anexos) é delegada à skill
[ms-context-raw-generator](../ms-context-raw-generator/README.md), que
precisa estar instalada. Arquivo local ou texto colado não passam por
contexto intermediário: viram PRD direto.

## Como usar

```bash
/ms-prd-generator --ticket <id>
/ms-prd-generator --file <caminho>
/ms-prd-generator --text "<conteúdo>"
```

Exemplos:

```bash
/ms-prd-generator --ticket 86ajrqjc7
/ms-prd-generator --ticket ENG-451 --refresh   # ignora contexto já coletado, busca de novo
/ms-prd-generator --file docs/feature-exemplo.md
/ms-prd-generator --text "Adicionar botão de exportar CSV na tela de relatórios"
```

Grava em `temp/prd/prd-<identificador>.md`, na raiz do projeto onde a
skill está rodando (não no pool). O identificador é o id do ticket, o
nome do arquivo (sem espaços) ou um sequencial `prd-seqNNN`, nessa ordem
de prioridade conforme a origem usada.

Rodar de novo para o mesmo identificador pergunta antes de sobrescrever o
PRD existente.

### Configuração

Sem credenciais próprias — quando a origem é `--ticket`, usa a
configuração de board já feita para o
[ms-context-raw-generator](../ms-context-raw-generator/README.md).
