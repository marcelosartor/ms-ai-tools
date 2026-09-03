# ms-ai-tools

Pool de ferramentas para desenvolvimento agêntico. Cada ferramenta é uma
skill do Claude Code — algumas próprias, outras adaptadas de terceiros — e
todas se instalam de uma vez.

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

### Onde as coisas ficam

| O quê | Onde | Muda com |
|---|---|---|
| Skills | `~/.claude/skills/<ferramenta>/` | `CLAUDE_SKILLS_DIR` |
| Credenciais | `~/.config/ms-ai-tools/.env` | `MS_AI_TOOLS_CONFIG_DIR` |
| Dependências (`jq`) | `~/.config/ms-ai-tools/bin/` | `MS_AI_TOOLS_CONFIG_DIR` |

As credenciais moram **fora** da pasta da skill de propósito: a instalação
substitui o diretório da ferramenta inteiro, então um `.env` lá dentro se
perderia a cada atualização. Um `.env` local ainda é lido, e vence o
compartilhado — útil para sobrepor um valor pontualmente.

Se você já tinha um `.env` dentro de uma skill, o instalador o resgata antes
de substituir o diretório: vira o `~/.config/ms-ai-tools/.env` se ainda não
houver um, ou é guardado ao lado como `.env.da-skill-<ferramenta>` se houver.
Credencial existente nunca é sobrescrita nem descartada.

## Ferramentas

| Ferramenta | O que faz | Comando | Credenciais |
|---|---|---|---|
| **[ms-codereview](ms-codereview/README.md)** | Revisão de PR de terceiros | `/ms-codereview` | ClickUp **ou** Jira |

### [ms-codereview](ms-codereview/README.md)

Revisa um pull request de terceiros cruzando três versões da mesma história —
o que o ticket pediu, o que o PR diz que faz e o que o código faz — e fecha
com um veredito (*Aprovar* / *Aprovar com ressalvas* / *Rejeitar*) e um
rascunho de comentário pronto para colar.

Só bloqueia merge por erro de lógica, falha de segurança, perda ou vazamento
de dado e regressão; o resto vira sugestão. Sem contexto que estabeleça o
comportamento esperado, rejeita por falta de dados em vez de inferir a
intenção a partir do diff. Nada é postado no PR sem você pedir.

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
└── scripts/          # *.sh recebem bit de execução na instalação
```

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
