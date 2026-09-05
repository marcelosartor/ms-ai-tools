Lido no passo 11 do `SKILL.md`.

## Segunda passagem

Com relatório, recomendação e rascunho prontos, revisar a própria revisão
antes de entregar. Percorrer cada achado e conferir:

- O `arquivo:linha` citado ainda contém o que o achado afirma. Reabrir o
  trecho; não confiar na memória da primeira leitura.
- A afirmação sobre o comportamento anterior bate com o código em `main`
  (`git show main:<arquivo>`), e não com o que se supôs que era.
- O achado não descreve código que o PR só moveu de lugar, nem padrão já
  adotado no resto do projeto.
- A severidade sobrevive: `blocker:` que não consegue descrever o cenário
  concreto de falha — entrada, estado, resultado errado — vira `dúvida:`.
- O veredito continua derivando da tabela depois de qualquer
  reclassificação feita acima.
- Cada ponto do rascunho tem lastro num achado que sobreviveu.

Achado que não sobrevive sai do relatório; não é rebaixado para "menciono
por precaução". Relatório menor e correto vale mais que um maior com um
item furado — quem assina é o usuário, e o custo do falso positivo é a
credibilidade dele.

**Refutação independente de cada `blocker:`.** A checagem acima é feita por
quem escreveu o achado — carrega o mesmo viés. Para todo `blocker:` que
sobreviver até aqui, despachar um subagent (`Agent`, `general-purpose`) com
`prompts/refute.md` preenchido, um por blocker, em paralelo (até 8 por
rodada; acima disso, agrupar achados do mesmo arquivo num único subagent).
O subagent recebe acesso ao repositório, a `temp/cr/<alvo>/raw/` e ao
worktree de `--keep` (passo 5) preenchido em `{{worktree}}` — pode
escrever um teste de até 30 linhas ali para tentar reproduzir o cenário,
em vez de confiar só na leitura. Mas **não** recebe o relatório inteiro —
só o achado que vai testar, sem saber dos outros. A tarefa dele é tentar
derrubar a afirmação, não confirmá-la.

Aplicar o veredito do subagent:

| veredito do refutador | efeito |
|---|---|
| `CONFIRMADO` | mantém `blocker:`. Se a `nota` começar com `severidade: sugestão` ou `severidade: dúvida` (cenário real, mas trecho inalcançável ou efeito abaixo do limiar de bloqueio), reclassificar para essa severidade em vez de manter `blocker:`, e registrar em `refuted.md` como `rebaixado` (`arquivo:linha`, afirmação, motivo da nota) |
| `REFUTADO` | achado sai do relatório; registrar em `temp/cr/<alvo>/refuted.md` (`arquivo:linha`, afirmação, evidência da refutação) para auditoria |
| `INCONCLUSIVO` | vira `dúvida:`, com a `nota` do refutador anexada |

`sugestão:` e `nit:` não passam pelo refutador — a checagem manual acima já
basta para o que não bloqueia.
