---
name: ms-codereview
description: Revisa um pull request de terceiros com critério calibrado para bloquear apenas correção, segurança e dados, e fecha com uma recomendação de aprovar ou rejeitar mais um rascunho de comentário para o PR. Use quando o usuário pedir para revisar um PR, fazer code review, analisar um diff antes de aprovar, ou perguntar se deve aprovar ou rejeitar uma mudança. Aceita número de PR, nome de branch ou range de refs como argumento.
license: Apache-2.0
metadata:
  version: 0.6.0
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
buscar o ticket: `scripts/fetch-context.sh <alvo>`.

**Exceção: PR mecânico dispensa ticket.** Bump de dependência, formatação,
rename e correção de doc não têm ticket e não precisam — a própria mudança
é a spec, e o que ela deveria fazer é o que o título diz. Revisão reduzida
por tipo, ver reference/contexto.md.

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

   Se o script sair diferente de `0`, ou `raw/context-status.json` trouxer
   `mechanical: true`: ler reference/contexto.md antes de continuar.

   Se `raw/context-status.json` trouxer `previous_report` não nulo: ler
   reference/re-review.md antes de continuar — esta é uma re-revisão.

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

5. **Rodar o que for barato.** `scripts/run-checks.sh <alvo>` roda
   typecheck e os testes que o diff tocou num worktree isolado, sem
   instalar nada. Ler `raw/checks-result.md`. Teste que falha é `blocker:`
   com o trecho da saída; typecheck que falha é `blocker:` — são resultado
   verificado, não inferência de leitura. Lint que falha **não** é achado
   (já coberto por "Não reportar"). O relatório ganha uma linha depois da
   contagem, ex.: `verificações: typecheck ok · 3 testes ok · lint não
   rodou (sem script)`.

6. **Aplicar os checklists.** Quais carregar não é julgamento: ler
   `raw/checklists.json` (campo `load`), gerado por
   `scripts/detect-checklists.sh` a partir do diff — mesmo diff, mesmo
   conjunto, toda vez. Cada nome em `load` é o arquivo
   `checklists/<nome>.md`. O relatório ganha uma linha citando o motivo de
   cada checklist carregado, vindo do campo `why` (ex.: `checklist:
   frontend-react (paths: src/pages/Search.tsx)`). `load` vazio não é
   achado — só significa que o diff não tocou nenhuma camada com
   checklist. Cada checklist tem uma seção `Comum` e seções por variante:
   aplicar `Comum` mais as seções listadas em `variants` para esse
   checklist (campo `variants` do mesmo `raw/checklists.json`); se
   `variants` não lista nada para ele, aplicar todas as seções.

7. **Passagem de segurança, se `raw/checklists.json` acionar.** Quando
   `security: true`, despachar um subagent (`Agent`, `general-purpose`)
   com `prompts/security.md` preenchido (`security_why`, `base`, `head`) e
   acesso ao repositório, antes de reportar. Os achados dele entram na
   lista como qualquer outro — mesma calibragem, mesma barra de
   verificação, mesmo refutador do passo seguinte para todo `blocker:`. O
   relatório traz uma linha: `segurança: passagem dedicada (motivo:
   <security_why>)` quando acionou, ou `segurança: não acionada` quando
   não.

8. **Verificar antes de reportar.** Ver a barra de verificação abaixo.

9. **Reportar** no formato descrito abaixo.

10. **Recomendar e rascunhar o comentário.** Sempre, mesmo quando o
    relatório não teve nenhum achado.
    Ler reference/comentario.md antes de continuar.

11. **Revisar a própria revisão** antes de entregar. Ler
    reference/segunda-passagem.md antes de continuar.

12. **Gravar o relatório da rodada**, para a próxima revisão deste mesmo
    alvo poder ser incremental. Ver reference/re-review.md.

## Calibragem de severidade

**Bloqueia o merge** apenas: erro de lógica, falha de segurança, perda ou
vazamento de dado, regressão de comportamento.

**Não bloqueia**: design discutível, nomenclatura, organização,
legibilidade, oportunidade de refatoração. Estes viram sugestão.

## Não reportar

- Qualquer coisa coberta por lint, formatter ou checagem de tipo do CI —
  isto é sobre inferir esse tipo de problema lendo o código; typecheck que
  a skill roda de verdade (passo 5, "Rodar o que for barato") é resultado
  verificado, não inferência, e por isso é `blocker:` mesmo assim. Lint
  executado continua fora do relatório mesmo quando falha
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

Em modo incremental, ver reference/re-review.md. Depois, sempre: uma linha
de contagem no formato `2 correção, 4 estilo`. Quando não houver achado de
correção, começar com "Nenhum problema de correção encontrado".

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

Todo `blocker:` que chegou até aqui passou por refutação independente (ver
"Segunda passagem") — não é a mesma leitura confirmando a si mesma.

Fechar com uma frase sobre o que a revisão **não** cobriu: teste que não
rodou, alcance que só QA fecha, ambiente que não existe aqui. Aprovação não
é garantia, e é o usuário que assina.

A decisão continua sendo dele — tem prazo, criticidade e time que esta
análise não tem. A recomendação é insumo, e ele pode ignorá-la sem
justificar. Dizer isso uma vez, em uma linha, e não repetir.

## Limites

Não postar o comentário no PR, não submeter review e não editar arquivos, a
menos que o usuário peça explicitamente. O rascunho é rascunho até ele
mandar publicar: o comentário sai com o nome dele, e ele valida cada ponto
antes.

Escrever dentro de `temp/cr/<alvo>/` (achados refutados, relatório da
rodada, JSON de review) não conta como editar o projeto: é área de
trabalho da própria skill, já fora do versionamento. A restrição acima é
sobre o código do repositório revisado.
