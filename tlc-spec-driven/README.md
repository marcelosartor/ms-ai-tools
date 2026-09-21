# tlc-spec-driven

## Descrição

Planejamento e implementação de uma feature em até quatro fases —
**Specify → Design → Tasks → Execute** —, com a profundidade ajustada ao
tamanho da mudança (uma alteração pequena vira spec de uma linha; uma feature
grande ganha spec com IDs de requisito, design e tasks atômicas). Requisitos
em notação EARS, commits atômicos no padrão Conventional Commits,
rastreabilidade requisito → task → teste, e ao final um **Verifier
independente** (quem escreve não é quem verifica) que grava
`validation.md`. Os portões estruturais da spec, das tasks, dos commits e da
conclusão são scripts Python, não memória do modelo. O estado do projeto
(decisões, handoff, lições) fica em `.specs/` no repositório onde a skill
roda.

## Atribuição

Skill de terceiro, incluída **sem modificação**.

- **Autor:** Felipe Rodrigues ([felipfr](https://github.com/felipfr)) —
  [Tech Leads Club](https://github.com/tech-leads-club)
- **Fonte:** <https://github.com/tech-leads-club/agent-skills>
  (`packages/skills-catalog/skills/(development)/tlc-spec-driven`, commit
  `120b6767`, versão 3.3.0)
- **Licença:** `SKILL.md` e `references/` sob
  [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/); os scripts
  (`scripts/*.py`) sob MIT. O [LICENSE](LICENSE) é o do repositório de
  origem, com a nota de licenciamento duplo. Os dois exigem atribuição, e o
  Tech Leads Club pede que ela seja mantida qualquer que seja o uso.
- **Alterações:** nenhuma. Os arquivos são idênticos aos do commit acima.

## Como usar

```bash
/tlc-spec-driven
```

Ou em linguagem natural — a skill dispara por frases como "specify feature",
"design", "tasks", "implement", "validate", "verify work", "record decision",
"pause work", "resume work".

Exemplos:

```
> /tlc-spec-driven especificar a exportação de relatórios em CSV
> implement                       # executa as tasks já aprovadas
> resume work                     # retoma a partir de .specs/STATE.md
```

A aprovação de uma spec ou de tasks autoriza só implementação e commits
**locais**; `git push`, deploy e afins pedem autorização à parte.

### Requisitos

`python3` (só biblioteca padrão) no `PATH` — os portões rodam
`python3 <pasta-da-skill>/scripts/*.py`. O `ms-ai-tools --doctor` confere.
Sem credenciais.

### Relação com o resto do pool

Cobre as etapas seguintes ao PRD: o documento gerado pelo
[ms-prd-generator](../ms-prd-generator/README.md) é uma boa entrada para o
Specify. Não substitui o PRD — parte dele.
