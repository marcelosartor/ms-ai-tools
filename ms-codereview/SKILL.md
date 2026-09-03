---
name: ms-codereview
description: Revisa um pull request de terceiros com critério calibrado para bloquear apenas correção, segurança e dados, e fecha com uma recomendação de aprovar ou rejeitar mais um rascunho de comentário para o PR. Use quando o usuário pedir para revisar um PR, fazer code review, analisar um diff antes de aprovar, ou perguntar se deve aprovar ou rejeitar uma mudança. Aceita número de PR, nome de branch ou range de refs como argumento.
license: Apache-2.0
metadata:
  version: 0.3.0
---

# Revisão de pull request

Revisar o alvo indicado em `$ARGUMENTS`. Sem argumento, revisar a branch
atual contra a branch padrão do repositório.

O usuário é revisor externo: não escreveu este código e frequentemente não
conhece o projeto a fundo. O objetivo é dar a ele material para decidir
aprovar ou rejeitar, mais uma recomendação explícita de qual dos dois — a
decisão continua sendo dele, mas ele não deve ter que inferi-la sozinho a
partir da lista de achados.

## Precedência

O `CLAUDE.md` do projeto vence este checklist onde houver conflito. Se o
repositório tem convenção própria, ela é a fonte da verdade. Nunca apontar
como problema um padrão já estabelecido no codebase.

## Contexto obrigatório

Revisar sem saber o que o PR **deveria** fazer só produz achado sobre o que
ele faz — que é a parte fácil e a menos útil. A fonte primária é a descrição
do PR. Quando ela não deixa claro qual era o comportamento esperado
(descrição vazia, só "ajustes", ou que descreve a solução sem o problema),
buscar o ticket:

```bash
scripts/fetch-context.sh 158                       # id do ticket vem do corpo do PR ou da branch
scripts/fetch-context.sh 158 --task DEV-142        # quando não der para descobrir sozinho
scripts/fetch-context.sh 158 --provider jira       # quando o formato do id for ambíguo
```

O script fala com o tracker configurado — ClickUp ou Jira — e grava o
ticket sempre nos mesmos arquivos (`raw/ticket.md`), qualquer que seja ele.
Descobre o tracker sozinho pelo formato do id; `--provider` só é necessário
quando erra. As credenciais ficam em `.env` na raiz desta skill (modelo em
`.env.example`). Nunca colar credencial em comando nem citá-la no relatório.

Saídas do script: `0` contexto obtido, `3` id do ticket não encontrado, `4`
credencial ausente, `5` o tracker recusou. Em `3`, `4` ou `5`, tentar uma
vez o caminho manual — perguntar o id ao usuário, ou ler o ticket pelo MCP
do tracker se estiver conectado.

**Se ainda assim não for possível estabelecer o que o PR deveria fazer, a
revisão para aqui: rejeitar por falta de dados.** Não inferir a intenção a
partir do código. Um PR que faz exatamente o que o código diz continua
podendo ser a solução errada para o problema, e isso é justamente o que a
leitura do diff não enxerga. Dizer o que falta e o que destravaria.

Ler o ticket **antes** do diff. No fim, comparar as três versões: o que o
ticket pediu, o que o PR diz que faz, o que o código faz. Cada divergência
entre elas é um achado de natureza diferente.

## Procedimento

1. **Dimensionar.** `git diff --stat` do range. Acima de ~400 linhas de
   código não-mecânico, dizer isso ao usuário antes de qualquer análise.

2. **Coletar o contexto bruto.** Rodar `scripts/fetch-context.sh <alvo>` na
   raiz do repositório revisado. Ele grava PR, corpo, arquivos, comentários
   e — quando houver — o ticket do tracker em `temp/cr/<alvo>/raw/`. Todo
   dado de geração de contexto vive ali, inclusive o que for coletado à mão
   depois — o script já garante `temp/` no `.gitignore` do projeto. Ler
   `raw/pr-body.md` e guardar o que o autor **afirma** ter feito:
   divergência entre isso e o que ele fez é achado relevante.

3. **Responder quatro perguntas antes de julgar o diff.** São o contexto
   mínimo; sem elas a revisão vira leitura de linha. Responder para si, não
   para o relatório:

   - *O que esse PR muda e por quê?* Começar pelo impacto — quem sente a
     mudança e como — e não pelo diff.
   - *Os métodos alterados são chamados de onde mais no projeto?* Chamador
     que o autor não tocou é onde a regressão se esconde.
   - *Qual era o comportamento antes e qual é depois, nos casos de borda?*
     Lista vazia, erro do serviço externo, retentativa, concorrência, lote
     grande, timeout.
   - *O padrão usado aqui é o do resto do projeto ou é novo?* Se é novo, é
     decisão de arquitetura disfarçada de PR e merece ser dita. Se é o de
     sempre, não é achado (ver Precedência).

   As três últimas só se respondem lendo o codebase fora do diff. É a etapa
   que mais vale para um revisor externo.

4. **Ler os testes primeiro.** Eles revelam o que o autor achou que estava
   construindo. Teste ausente onde havia regra de negócio nova, ou teste
   sem asserção, são achados.

5. **Aplicar os checklists.** Carregar apenas o que o diff tocar:
   - Backend Node/NestJS: `checklists/backend-node-nest.md`
   - Frontend Vue/Quasar/Vuetify: `checklists/frontend-vue.md`

6. **Verificar antes de reportar.** Ver a barra de verificação abaixo.

7. **Reportar** no formato descrito abaixo.

8. **Recomendar e rascunhar o comentário.** Sempre, mesmo quando o
   relatório não teve nenhum achado.

9. **Revisar a própria revisão** antes de entregar. Ver "Segunda passagem".

## Calibragem de severidade

**Bloqueia o merge** apenas: erro de lógica, falha de segurança, perda ou
vazamento de dado, regressão de comportamento.

**Não bloqueia**: design discutível, nomenclatura, organização,
legibilidade, oportunidade de refatoração. Estes viram sugestão.

## Não reportar

- Qualquer coisa coberta por lint, formatter ou checagem de tipo do CI
- Arquivos gerados, `*.lock`, `dist/`, `coverage/`
- Padrão arquitetural já adotado no projeto
- Falta de teste em código que não é regra de negócio
- Código que o diff apenas moveu de lugar, salvo se for bloqueante
- Mais de cinco itens de nit; acima disso, citar como contagem no resumo

## Barra de verificação

Toda afirmação sobre comportamento precisa de confirmação lendo o código,
com `arquivo:linha`. Inferência a partir do nome de função ou variável não
basta.

Se não foi possível confirmar, apresentar como dúvida a investigar, nunca
como problema. Falso positivo em PR de terceiro custa a credibilidade do
revisor: na dúvida, perguntar em vez de afirmar.

## Formato do relatório

Abrir com uma linha de contagem no formato `2 correção, 4 estilo`. Quando
não houver achado de correção, começar com "Nenhum problema de correção
encontrado".

Depois, no máximo três frases sobre o que o PR faz e onde está o maior
risco.

Então os achados, cada um com prefixo de severidade, localização
`arquivo:linha`, e o porquê:

- `blocker:` impede o merge
- `sugestão:` melhoria que não bloqueia
- `nit:` detalhe menor
- `dúvida:` não foi possível confirmar; perguntar ao autor

Fechar apontando o que ficou bom no PR, quando houver. Isso não é cortesia:
sinaliza ao autor qual padrão repetir.

## Recomendação

Depois dos achados, emitir uma recomendação. Ela é um dos três estados de
review do GitHub, nunca um meio-termo inventado:

| Veredito | Quando |
|---|---|
| **Aprovar** | nenhum `blocker:`, e nenhuma `dúvida:` cuja resposta possa virar um |
| **Aprovar com ressalvas** (*Comment*) | nenhum `blocker:`, mas há `dúvida:` que pode virar um, ou o alcance da mudança excede o que leitura de diff cobre |
| **Rejeitar** (*Request changes*) | existe pelo menos um `blocker:` em aberto, ou não foi possível estabelecer o que o PR deveria fazer |

Rejeição por falta de dados é o único caso em que o relatório não lista
achados: não houve revisão. Ele diz o que falta — ticket, descrição, id —,
o que já foi tentado e o que destravaria. Não misturar com achados parciais
de um diff lido sem contexto: isso dá ao usuário a impressão de que a
revisão aconteceu.

O veredito sai desta tabela, não de impressão geral. Se o resultado
mecânico parecer errado, o erro está na classificação de algum achado —
reclassificar o achado, nunca ajustar o veredito para compensar.

No máximo três frases, contendo:

1. o veredito;
2. o motivo, ancorado nos achados que o produziram, citados por
   `arquivo:linha` e não por resumo;
3. o que precisaria mudar para virar o veredito.

Fechar com uma frase sobre o que a revisão **não** cobriu: teste que não
rodou, alcance que só QA fecha, ambiente que não existe aqui. Aprovação não
é garantia, e é o usuário que assina.

A decisão continua sendo dele — tem prazo, criticidade e time que esta
análise não tem. A recomendação é insumo, e ele pode ignorá-la sem
justificar. Dizer isso uma vez, em uma linha, e não repetir.

## Comentário para o PR

Depois da recomendação, oferecer um rascunho pronto para colar, dentro de
um bloco de código para facilitar a cópia.

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

## Limites

Não postar o comentário no PR, não submeter review e não editar arquivos, a
menos que o usuário peça explicitamente. O rascunho é rascunho até ele
mandar publicar: o comentário sai com o nome dele, e ele valida cada ponto
antes.
