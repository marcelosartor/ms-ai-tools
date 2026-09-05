Lido no passo 10 do `SKILL.md`.

## Comentário para o PR

Depois da recomendação, oferecer um rascunho pronto para colar, dentro de
um bloco de código para facilitar a cópia.

Junto do texto, gravar `temp/cr/<alvo>/review-<sha7 de head_sha>.json` no
formato que `gh api repos/{owner}/{repo}/pulls/{n}/reviews` aceita:

```json
{
  "commit_id": "<head_sha completo>",
  "event": "APPROVE",
  "body": "<o rascunho, sem os itens que viraram comentário inline>",
  "comments": [
    { "path": "src/api/refund.ts", "line": 88, "side": "RIGHT", "body": "<texto do item>" }
  ]
}
```

Veredito → `event`: Aprovar → `APPROVE`; Aprovar com ressalvas → `COMMENT`;
Rejeitar → `REQUEST_CHANGES`. Cada item acionável do rascunho vira uma
entrada em `comments[]` quando o `arquivo:linha` está dentro do diff
(`line` é a linha do arquivo **novo**, `side` sempre `"RIGHT"`); item sobre
linha fora do diff fica só no `body`. As regras do rascunho acima (primeira
pessoa, idioma do PR, sem jargão, ≤ 15 linhas) valem tanto para `body`
quanto para cada `comments[].body`.

Este JSON não é postado sozinho. Ao final, mostrar ao usuário o comando
para publicar quando ele decidir:

```bash
scripts/post-review.sh <pr>
```

`post-review.sh` confere que o `commit_id` gravado ainda é o head atual do
PR antes de postar — recusa e pede para revisar de novo se o PR mudou
desde então.

Regras do rascunho:

- Primeira pessoa, como se o usuário tivesse escrito. É ele quem assina.
- Mesmo idioma do PR.
- Sem o jargão desta skill. Nada de `blocker:`, `nit:`, `sugestão:` —
  traduzir para "isso impede o merge", "isso é opcional".
- Só o que o autor precisa acionar. Nit e observação interna ficam fora do
  comentário, mesmo estando no relatório.
- Cada ponto com `arquivo:linha` e o efeito concreto, nunca o rótulo.
- Onde havia `dúvida:`, perguntar de verdade em vez de afirmar.
- Abrir reconhecendo o que ficou bom, quando houver; fechar dizendo o que
  falta para aprovar.
- Curto. Passando de ~15 linhas, cortar itens em vez de resumir todos.
- Em modo incremental, ver reference/re-review.md.
