Lido no passo 2 do `SKILL.md`, só quando `fetch-context.sh` sai diferente de
`0` ou `raw/context-status.json` traz `mechanical: true`.

## Chamada e flags

```bash
scripts/fetch-context.sh 158                       # id do ticket vem do corpo do PR ou da branch
scripts/fetch-context.sh 158 --task DEV-142        # quando não der para descobrir sozinho
scripts/fetch-context.sh 158 --provider jira       # quando o formato do id for ambíguo
scripts/fetch-context.sh 158 --spec-file docs/specs/refund.md  # sem tracker: arquivo local vira o contexto
```

O script fala com o tracker configurado — ClickUp ou Jira — e grava o
ticket sempre nos mesmos arquivos (`raw/ticket.md`), qualquer que seja ele.
Descobre o tracker sozinho pelo formato do id; `--provider` só é necessário
quando erra. As credenciais ficam em `.env` na raiz desta skill (modelo em
`.env.example`). Nunca colar credencial em comando nem citá-la no relatório.
Provider sem credencial configurada nem é tentado na descoberta automática —
só entra na jogada se `--provider` pedir por ele explicitamente.

Sem tracker, ou quando o usuário indicar um documento em vez de um ticket:
`--spec-file <caminho>` usa esse arquivo como fonte do contexto, sem tocar
em tracker nenhum. Só roda quando o parâmetro é passado explicitamente —
não existe busca automática em diretório de specs, porque não há como casar
PR e arquivo sem risco de pegar o errado; se o usuário não indicar o
arquivo, pular esse passo e seguir para o caminho do ticket ou para a
rejeição por falta de dados.

## Saídas do script e caminho manual

Saídas do script: `0` contexto obtido, `3` id do ticket não encontrado, `4`
credencial ausente ou nenhum tracker configurado, `5` o tracker recusou. Em
`3`, `4` ou `5`, tentar uma vez o caminho manual — perguntar o id ao
usuário, pedir o caminho do documento de spec, ou ler o ticket pelo MCP do
tracker se estiver conectado.

## PR mecânico

Bump de dependência, formatação, rename e correção de doc não têm ticket e
não precisam — a própria mudança é a spec, e o que ela deveria fazer é o
que o título diz. `scripts/fetch-context.sh` classifica isso sozinho
(`context-status.json`: `mechanical` e `mechanical_kind`); quando
`mechanical: true`, ele nem tenta ticket nem `--spec-file`. PR misto (ex.:
bump de dependência junto de código novo) não é mecânico e segue o fluxo
normal. Revisão reduzida por tipo:

- `deps`: major bump tem changelog/breaking lido e citado; lockfile bate
  com o `package.json`; dependência nova responde "é necessária, é
  mantida, o que puxa junto".
- `format`: confirmar que `git diff -w` está vazio; nada mais a revisar.
- `rename`: nenhum import ou referência ao caminho antigo sobrou
  (`grep -rn` pelo nome antigo fora do diff).
- `docs`: só correção factual contra o código, quando o doc descreve
  comportamento.

Veredito continua saindo da tabela de sempre.
