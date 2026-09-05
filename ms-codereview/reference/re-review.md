Lido no passo 2 do `SKILL.md`, só quando `raw/context-status.json` traz
`previous_report` não nulo.

## Re-review incremental

`raw/context-status.json` traz `head_sha`, `previous_report` e
`previous_sha` (sha7 do relatório anterior mais recente, se houver). Ao
final de toda revisão — passo 12 do procedimento — gravar o relatório
completo em `temp/cr/<alvo>/report-<sha7 de head_sha>.md`, começando com um
bloco fixo, machine-readable, uma linha por achado que ficou no relatório:

```
<!-- achados
blocker | src/api/refund.ts:88 | double-charge quando retry após timeout
sugestão | src/api/refund.ts:120 | extrair cálculo de taxa
dúvida | src/db/refund.sql:12 | índice cobre o filtro por status?
-->
```

**Quando `previous_report` existe e `previous_sha` é prefixo de `head_sha`
mas os dois divergem** (o mesmo alvo mudou desde a última rodada): modo
incremental.

- Ler o bloco de achados do `previous_report`.
- Rodar os passos 3–8 do procedimento (as quatro perguntas, testes,
  verificações, checklists, segurança se acionar) só sobre
  `git diff <previous_sha>..<head_sha>` — o delta, não o PR inteiro.
- Para cada achado da rodada anterior, reabrir o `arquivo:linha` no `head`
  atual e classificar:

  | estado | critério |
  |---|---|
  | resolvido | o trecho mudou e o cenário de falha não se reproduz mais |
  | aberto | o trecho não mudou, ou mudou e o cenário persiste |
  | novo | achado sobre o delta que não existia na rodada anterior |

  Arquivo que o delta não toca e que estava limpo na rodada anterior não é
  relido — só o que mudou, mais o que já era achado.

O relatório em modo incremental abre com uma linha própria, antes da
contagem de sempre:

`Desde a revisão anterior (<sha7 anterior> → <sha7 atual>): N resolvidos, N
abertos, N novos`

Lista, no formato padrão, só os abertos e os novos — resolvido aparece
apenas nessa contagem, não como item. O veredito sai da mesma tabela de
sempre, calculado sobre abertos + novos. O rascunho do comentário para o PR
menciona só abertos e novos, e abre reconhecendo os resolvidos numa frase
("já ajustou X e Y desde a última revisão").

**Quando `previous_sha` já é igual a `head_sha`** (mesmo commit, nada
mudou): avisar isso ao usuário e perguntar se é para revisar do zero mesmo
assim. Não refazer sozinho.

Sem `previous_report`, ou primeira revisão deste alvo: procedimento normal,
do início ao fim — nada muda.

## No relatório e no comentário

Em modo incremental (ver acima), abrir com a linha `Desde a revisão
anterior (...): N resolvidos, N abertos, N novos` antes de tudo.

Em modo incremental, só os itens abertos e novos entram; reconhecer os
resolvidos numa frase, sem repetir o que já foi corrigido.
