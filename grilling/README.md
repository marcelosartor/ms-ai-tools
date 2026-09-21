# grilling

## Descrição

Entrevista o usuário sem pressa sobre um plano, decisão ou ideia até os dois
chegarem a um entendimento compartilhado. O plano vira uma **árvore de
decisões** — cada decisão gera as que dependem dela — e a skill pergunta
por rodadas: todas as questões cujos pré-requisitos já foram resolvidos, cada
uma com a resposta que ela recomenda. Fatos do ambiente ela levanta sozinha
(via subagent); só as decisões vão para o usuário. Termina quando não resta
ramo sem visitar, e não age antes de o usuário confirmar.

É o motor da skill [grill-me](../grill-me/README.md), que só a chama.

## Atribuição

Skill de terceiro, incluída **sem modificação**.

- **Autor:** Matt Pocock
- **Fonte:** <https://github.com/mattpocock/skills>
  (`skills/productivity/grilling`, commit `959a8e9f`, versão 1.2.3 do plugin)
- **Licença:** MIT — texto e aviso de copyright em [LICENSE](LICENSE)

## Como usar

Normalmente não se chama direto: use `/grill-me`. A skill também dispara por
descrição quando o usuário pede para "grelhar" um plano ou usa frases
parecidas.

```bash
/grilling
```

Exemplo: ao terminar o esboço de uma feature, peça `/grill-me` antes de
gerar o PRD. Cada rodada traz as perguntas numeradas (`Q1`, `Q2`…), cada uma
com a resposta recomendada; responda só o que discordar ou quiser mudar.

Sem credenciais nem dependências além do próprio Claude Code.
