Lido no passo 2 do `SKILL.md`, só quando `raw/context-status.json` traz
`previous_report` não nulo.

## Re-review incremental

`raw/context-status.json` traz `head_sha`, `previous_report`,
`previous_sha` (sha7 do relatório anterior mais recente, se houver),
`previous_is_ancestor` (`true`/`false`/`null`), `previous_base_sha` e
`base_moved` (`true`/`false`/`null`). Ao final de toda revisão — passo 12
do procedimento — gravar o relatório completo em
`temp/cr/<alvo>/report-<sha7 de head_sha>.md`, começando com dois blocos
fixos, machine-readable:

```
<!-- meta
head_sha: <sha completo>
base_sha: <sha completo>
-->
<!-- achados
blocker | src/api/refund.ts:88 | double-charge quando retry após timeout | async function refund(
dúvida | src/db/refund.sql:12 | índice cobre o filtro por status? | CREATE INDEX idx_refund_status
-->
```

O bloco de achados tem quatro colunas, uma linha por achado que ficou no
relatório. A quarta é a **âncora**: o nome da função, método ou símbolo que
contém a linha, ou, quando não houver, a primeira linha de código do
trecho, sem espaços à esquerda, truncada em 80 caracteres.

**Modo incremental: quando `previous_report` existe e `previous_sha` não é
prefixo de `head_sha`** (o alvo mudou desde a última rodada). Quando é
prefixo, é o mesmo commit — ver "mesmo commit" abaixo.

**Guarda de rebase.** Se `previous_is_ancestor` for `false` ou `null`, não
entrar em modo incremental — o sha da rodada anterior saiu da linha do
head atual (rebase ou force-push), e o delta `previous_sha..head_sha`
incluiria commits que não são deste PR. Fazer revisão completa e abrir o
relatório com a linha:

`Revisão anterior (<sha7>) não é ancestral do head atual (rebase ou
force-push): revisão completa, achados anteriores reclassificados ao
final`

Os achados do relatório anterior ainda são reabertos e classificados
resolvido/aberto ao final (o usuário quer saber o que aconteceu com eles);
o que muda é que o delta não é usado para restringir a leitura.

Com a guarda passando (`previous_is_ancestor: true`):

- Ler o bloco de achados do `previous_report`.
- Se `base_moved` for `true` (a base recebeu merge desde a rodada
  anterior): o delta é `git diff <previous_sha>...<head_sha>` filtrado
  pelos arquivos que o PR toca (`raw/pr-files.tsv` ou
  `git diff --name-only <base_sha>...<head_sha>`) — mudança vinda da base
  não é lida como parte do PR.
- Caso contrário, o delta é `git diff <previous_sha>..<head_sha>` — o
  delta, não o PR inteiro.
- Rodar os passos 3–8 do procedimento (as quatro perguntas, testes,
  verificações, checklists, segurança se acionar) só sobre esse delta.
- Para cada achado da rodada anterior, reabrir e classificar:

  | estado | critério |
  |---|---|
  | resolvido | o trecho mudou e o cenário de falha não se reproduz mais |
  | aberto | o trecho não mudou, ou mudou e o cenário persiste |
  | novo | achado sobre o delta que não existia na rodada anterior |

  Arquivo que o delta não toca e que estava limpo na rodada anterior não é
  relido — só o que mudou, mais o que já era achado.

  **Reancoragem.** Procurar primeiro a âncora no arquivo atual
  (`grep -n -F`); se encontrar, é essa a linha a inspecionar. Se não
  encontrar e o arquivo existe, o trecho mudou: ler o arquivo em volta da
  linha antiga. Se o arquivo não existe mais, o achado é `resolvido` só se
  o cenário não se reproduz em outro lugar; caso contrário, `aberto` com a
  localização nova.

O relatório em modo incremental abre com uma linha própria, antes da
contagem de sempre:

`Desde a revisão anterior (<sha7 anterior> → <sha7 atual>): N resolvidos, N
abertos, N novos`

Lista, no formato padrão, só os abertos e os novos — resolvido aparece
apenas nessa contagem, não como item. O veredito sai da mesma tabela de
sempre, calculado sobre abertos + novos. O rascunho do comentário para o PR
menciona só abertos e novos, e abre reconhecendo os resolvidos numa frase
("já ajustou X e Y desde a última revisão").

**Mesmo commit: quando `previous_sha` já é igual a `head_sha`** (nada
mudou): avisar isso ao usuário e perguntar se é para revisar do zero mesmo
assim. Não refazer sozinho.

Sem `previous_report`, ou primeira revisão deste alvo: procedimento normal,
do início ao fim — nada muda.

## No relatório e no comentário

Em modo incremental (ver acima), abrir com a linha `Desde a revisão
anterior (...): N resolvidos, N abertos, N novos` antes de tudo.

Em modo incremental, só os itens abertos e novos entram; reconhecer os
resolvidos numa frase, sem repetir o que já foi corrigido.
