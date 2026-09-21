# grill-me

## Descrição

Atalho de invocação manual para uma sessão de _grilling_: uma entrevista
implacável que afia um plano ou design antes de qualquer código. O
`SKILL.md` tem uma linha — chama a skill [grilling](../grilling/README.md),
que carrega o método de fato. Tem `disable-model-invocation: true`, então só
roda quando **você** digita `/grill-me`; o modelo não a dispara sozinho.

**Depende da `grilling`.** O instalador instala todas as ferramentas por
padrão, e as duas vêm juntas. Ao instalar por nome
(`ms-ai-tools grill-me`), instale `grilling` também — sozinha, esta não faz
nada.

## Atribuição

Skill de terceiro, incluída **sem modificação**.

- **Autor:** Matt Pocock
- **Fonte:** <https://github.com/mattpocock/skills>
  (`skills/productivity/grill-me`, commit `959a8e9f`, versão 1.2.3 do plugin)
- **Licença:** MIT — texto e aviso de copyright em [LICENSE](LICENSE)

O `SKILL.md` não traz `metadata.version` (o upstream não define), então o
`--list` do instalador mostra "sem versão". A versão de origem é a acima.

## Como usar

```bash
/grill-me
```

Exemplo, com um plano já descrito na conversa:

```
> Quero migrar o cache de sessão de Redis para o Postgres.
> /grill-me
```

A skill devolve a primeira rodada de perguntas numeradas, cada uma com a
resposta que ela recomenda, e só segue quando você responder.

Sem credenciais nem dependências.
