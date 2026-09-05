# ms-ai-tools

Pool de ferramentas para desenvolvimento agêntico. Cada ferramenta é uma
skill do Claude Code — algumas próprias, outras adaptadas de terceiros — e
todas se instalam de uma vez.

## Objetivo

O ms-ai-tools existe para formalizar um workflow de **Spec-Driven
Development (SDD)**: código nasce de uma especificação acordada — o que o
ticket pediu, o que a mudança deveria fazer — e não do que parece razoável
enquanto se escreve. Cada etapa desse processo ganha uma ferramenta
determinada, em vez de depender de disciplina manual repetida a cada
projeto e a cada pessoa.

A cobertura é parcial por natureza: o pool cresce por etapa do workflow, não
por acúmulo de utilitários soltos. Hoje só a etapa de **revisão** tem
ferramenta (`ms-codereview`); especificação, planejamento e implementação
ainda dependem de processo manual.

Nada aqui é específico de cliente ou de projeto. O que uma ferramenta precisa
saber do domínio vem do `CLAUDE.md` do repositório onde ela roda, ou do
ticket, nunca de regra embutida na skill.

## Instalação

Sem clonar nada:

```bash
npx github:marcelosartor/ms-ai-tools                 # instala todas as ferramentas
npx github:marcelosartor/ms-ai-tools ms-codereview   # instala só as indicadas
npx github:marcelosartor/ms-ai-tools --list          # o que existe e o que já está instalado
npx github:marcelosartor/ms-ai-tools --doctor        # confere as dependências
npx github:marcelosartor/ms-ai-tools --deps          # só instala as dependências
```

Roda direto do repositório, então cada execução traz a versão mais recente.
Requer Node >= 18.

Quem clonou usa o mesmo instalador pelo atalho `./install.sh <mesmos
argumentos>`.

O instalador faz duas perguntas: **onde instalar** e **qual tracker você
usa**. Ambas têm flag equivalente, e fora de terminal (CI, pipe) ele nunca
pergunta — assume global e não mexe em credencial, para não travar.

### Global ou local

| Escopo | Onde | Vale em | Flag |
|---|---|---|---|
| Global | `~/.claude/skills/` | todos os seus projetos | `--global` |
| Local | `./.claude/skills/` (diretório corrente) | só esse projeto; pode ser comitado | `--local` |

`--dir <caminho>` instala num diretório específico; `CLAUDE_SKILLS_DIR`
continua funcionando e dispensa a pergunta.

Instalar local permite comitar a skill junto com o código, e o time inteiro
recebe sem instalar nada. Uma ressalva que o instalador avisa sozinho: **a
skill pessoal vence a de projeto**, então se a mesma ferramenta já estiver
instalada global, é ela que roda — remova a global para a local valer.

Credenciais e dependências ficam sempre no seu diretório de usuário, mesmo na
instalação local. Token é por pessoa, não por repositório, e comitar um seria
um problema.

### Qual tracker

A pergunta serve para já preparar o `.env`. Escolhido o tracker, o instalador
escreve as variáveis dele em `~/.config/ms-ai-tools/.env` com valores de
exemplo, e diz onde pegar o token de verdade:

```
  ✓ Jira Cloud: 3 variável(is) escritas em ~/.config/ms-ai-tools/.env
      edite o arquivo e substitua os valores de exemplo (id.atlassian.com/…)
```

**Valor já preenchido nunca é sobrescrito** — o instalador não tem como saber
se o que está lá é melhor que o placeholder que ele traria. Rodar de novo com
o mesmo tracker não duplica nada; com outro, acrescenta o bloco novo ao lado.

`--provider clickup` (ou `jira-cloud`, `jira-server`) responde sem perguntar;
`--provider none` pula a etapa.

### Dependências

O instalador resolve o `jq` sozinho: baixa o binário oficial da release do
[jqlang/jq](https://github.com/jqlang/jq), **confere o sha256 contra o hash
fixado no repositório** e grava em `~/.config/ms-ai-tools/bin/`. Hash que não
bate é erro, não aviso — binário não verificado não chega ao disco. As
ferramentas põem esse diretório na frente do `PATH`, então nada precisa ser
configurado.

Se você já tem `jq` no sistema, ele é usado e nada é baixado. `--no-deps`
pula a etapa; `--deps` faz só ela.

`curl` e `gh` ficam a cargo do sistema — um já vem em toda parte, o outro
precisa de `gh auth login` de qualquer forma. O instalador termina reportando
o estado dos três.

Confira com `/skills` numa sessão do Claude Code.

### Versões

O pool e cada ferramenta têm versão própria, em [semver](https://semver.org):

```bash
npx github:marcelosartor/ms-ai-tools --version
# ms-ai-tools 0.1.0
#   ms-codereview        v0.1.0
```

A versão do pool vive em `package.json`; a de cada ferramenta, em
`metadata.version` no `SKILL.md` dela. O frontmatter de skill não tem campo
`version` — chave desconhecida é erro nos caminhos de distribuição da
claude.ai e da API —, e `metadata` é o mapa livre que a especificação reserva
para dado de catálogo como este.

O instalador lê as duas pontas e mostra a transição:

```
$ npx github:marcelosartor/ms-ai-tools --list
  ms-codereview        v0.2.0       instalada v0.1.0 → atualiza para v0.2.0

$ npx github:marcelosartor/ms-ai-tools
  ✓ ms-codereview        v0.1.0 → v0.2.0
```

Cada versão do pool vira uma tag git, então dá para fixar uma:

```bash
npx github:marcelosartor/ms-ai-tools#v0.1.0
```

Sem tag, o npx sempre traz o topo da `main`.

### Atualizar uma instalação existente

Não há procedimento especial: rode o instalador de novo. Ele substitui o
diretório da ferramenta inteiro, e por isso guarda antes o que for seu.

A cada instalação é gravado um manifesto (`.ms-ai-tools.json`) com o hash de
cada arquivo como ele saiu do pacote. Na atualização seguinte, o instalador
compara a cópia instalada com esse manifesto — é o que separa "você editou
este arquivo" de "a versão nova mudou este arquivo", coisa que comparar com o
pacote novo não distingue.

Se algo seu for encontrado, a instalação anterior é copiada para
`~/.config/ms-ai-tools/backups/<ferramenta>-v<versão>-<data>/` antes de ser
substituída, e o instalador diz o que era:

```
  ✓ ms-codereview        v0.1.0 → v0.2.0
      3 arquivo(s) alterado(s) por você na cópia instalada — guardados em
      ~/.config/ms-ai-tools/backups/ms-codereview-v0.1.0-2026-09-03T18-29-45
        editados: checklists/backend-node-nest.md
        seus:     checklists/meu-python.md
```

Nada é guardado quando a cópia instalada está igual ao pacote — atualização
limpa não deixa lixo. Uma instalação sem manifesto (feita à mão, ou por uma
versão antiga do instalador) não dá para classificar: nesse caso a cópia é
guardada por precaução sempre que diferir.

O `.env` fica fora do backup de propósito: já é resgatado para
`~/.config/ms-ai-tools/.env`, e não há por que espalhar credencial pelos
backups.

`--no-backup` desliga o comportamento. Backups nunca são apagados
automaticamente — limpe `~/.config/ms-ai-tools/backups/` quando quiser.

**Melhor ainda é não personalizar a cópia instalada.** Regra específica de um
projeto pertence ao `CLAUDE.md` do repositório onde a ferramenta roda, que já
tem precedência. Regra que vale para todo projeto pertence a este repositório,
por commit — aí ela sobrevive sozinha às atualizações.

### Onde as coisas ficam

| O quê | Onde | Muda com |
|---|---|---|
| Skills | `~/.claude/skills/<ferramenta>/` | `CLAUDE_SKILLS_DIR` |
| Credenciais | `~/.config/ms-ai-tools/.env` | `MS_AI_TOOLS_CONFIG_DIR` |
| Dependências (`jq`) | `~/.config/ms-ai-tools/bin/` | `MS_AI_TOOLS_CONFIG_DIR` |
| Backups de atualização | `~/.config/ms-ai-tools/backups/` | `MS_AI_TOOLS_CONFIG_DIR` |

As credenciais moram **fora** da pasta da skill de propósito: a instalação
substitui o diretório da ferramenta inteiro, então um `.env` lá dentro se
perderia a cada atualização. Um `.env` local ainda é lido, e vence o
compartilhado — útil para sobrepor um valor pontualmente.

Se você já tinha um `.env` dentro de uma skill, o instalador o resgata antes
de substituir o diretório: vira o `~/.config/ms-ai-tools/.env` se ainda não
houver um, ou é guardado ao lado como `.env.da-skill-<ferramenta>` se houver.
Credencial existente nunca é sobrescrita nem descartada.

## Ferramentas

| Ferramenta | Etapa do SDD | Comando | Credenciais |
|---|---|---|---|
| **[ms-codereview](ms-codereview/README.md)** | Revisão | `/ms-codereview` | ClickUp **ou** Jira |

### [ms-codereview](ms-codereview/README.md) — etapa de revisão

**Por que existe:** revisar um PR de terceiro cruzando três versões da mesma
história — o que o ticket pediu, o que o PR diz que faz, o que o código faz —
é trabalho manual e inconsistente entre revisores. A ferramenta formaliza
esse cruzamento como parte do workflow de SDD, em vez de depender de cada
revisor lembrar de fazê-lo.

**Quando usar:** antes de aprovar um pull request de terceiro — em especial
quando a descrição do PR não deixa claro qual era o comportamento esperado, e
por isso vale confirmar contra o ticket.

**Por que usar, e não só ler o diff:** severidade calibrada (só bloqueia por
erro de lógica, falha de segurança, perda/vazamento de dado ou regressão; o
resto vira sugestão), veredito mecânico derivado dos achados (*Aprovar* /
*Aprovar com ressalvas* / *Rejeitar*), segunda passagem que descarta o que
não se sustenta antes de entregar, e rejeição explícita por falta de dados em
vez de inferir a intenção a partir do código. Nada é postado no PR sem você
pedir.

Busca o ticket no **ClickUp** ou no **Jira** (Cloud e Server/DC), escolhendo
o tracker pelo formato do id que encontra no PR ou na branch. Traz checklists
de Node/NestJS e Vue/Quasar/Vuetify, carregados só quando o diff toca a
camada.

Requer `jq`, `curl` e `gh` autenticado.
→ **[Instalação, configuração dos trackers e manutenção](ms-codereview/README.md)**

```bash
npx github:marcelosartor/ms-ai-tools ms-codereview
```

## Adicionar uma ferramenta

Uma pasta na raiz com um `SKILL.md` já é uma ferramenta — o `install.sh`
descobre sozinho. A convenção do pool:

```
<nome-da-ferramenta>/
├── SKILL.md          # frontmatter com name e description; é o que o Claude carrega
├── README.md         # instalação, configuração e manutenção
├── .env.example      # modelo das credenciais, se houver
├── .gitignore        # contendo .env
├── .npmignore        # idem: o npm ignora o .gitignore de subdiretório ao empacotar
├── credentials.json  # opcional: trackers/credenciais que o instalador oferece
└── scripts/          # *.sh recebem bit de execução na instalação
```

O `README.md` da ferramenta precisa conter três coisas:

- **Descrição** do que ela faz.
- **Atribuição**, quando a ferramenta (ou parte dela) vier de terceiro: o
  link da fonte original e o crédito autoral, perto do topo. Ferramenta
  própria não precisa da seção.
- **Como usar**: comando, argumentos, exemplo.

O `credentials.json` é o que faz o instalador perguntar pelo tracker sem
conhecer tracker nenhum — cada ferramenta declara os seus:

```json
{
  "pergunta": "Qual tracker você usa para os tickets?",
  "opcoes": [
    {
      "id": "clickup",
      "label": "ClickUp",
      "onde": "Settings > Apps > API Token",
      "vars": { "CLICKUP_TOKEN": "pk_000..." },
      "opcionais": { "CLICKUP_TEAM_ID": "1234567" }
    }
  ]
}
```

`vars` entram no `.env` prontas para editar; `opcionais` entram comentadas.
Ferramenta sem o arquivo simplesmente não gera a pergunta.

O `SKILL.md` carrega a versão da ferramenta:

```yaml
---
name: minha-ferramenta
description: …
license: Apache-2.0
metadata:
  version: 0.1.0
---
```

Ferramenta sem `metadata.version` continua instalando — o instalador a mostra
como "sem versão".

O `.npmignore` não é decorativo: ao empacotar, o npm usa o `.gitignore` de um
diretório só quando não há `.npmignore` nele — e avisa. Sem os dois, um `.env`
local acabaria dentro do pacote publicado.

O instalador descobre a pasta sozinha — nada a registrar em `package.json`.
Depois acrescente a ferramenta à tabela acima, com uma seção própria e link
para o `README.md` dela.

O nome da pasta vira o comando (`/ms-codereview`), então renomear a pasta
renomeia o comando. Mantenha o `SKILL.md` enxuto: ele carrega inteiro toda
vez que a skill dispara — o material extenso vai em arquivos que a skill
carrega sob demanda.

## Licença

[Apache 2.0](LICENSE).
