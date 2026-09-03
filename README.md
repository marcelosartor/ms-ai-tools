# ms-ai-tools

Pool de ferramentas para desenvolvimento agêntico. Cada ferramenta é uma
skill do Claude Code — algumas próprias, outras adaptadas de terceiros — e
todas se instalam de uma vez.

Nada aqui é específico de cliente ou de projeto. O que uma ferramenta precisa
saber do domínio vem do `CLAUDE.md` do repositório onde ela roda, ou do
ticket, nunca de regra embutida na skill.

## Instalação

```bash
git clone <este-repo> && cd ms-ai-tools
./install.sh                  # instala todas as ferramentas
./install.sh ms-codereview    # instala só as indicadas
./install.sh --list           # o que existe e o que já está instalado
```

O destino padrão é `~/.claude/skills/`; `CLAUDE_SKILLS_DIR` muda isso.
Reinstalar sobrescreve a skill mas **preserva o `.env`** já configurado — as
credenciais nunca são copiadas do repositório nem apagadas na atualização.

Confira com `/skills` numa sessão do Claude Code.

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

## Adicionar uma ferramenta

Uma pasta na raiz com um `SKILL.md` já é uma ferramenta — o `install.sh`
descobre sozinho. A convenção do pool:

```
<nome-da-ferramenta>/
├── SKILL.md          # frontmatter com name e description; é o que o Claude carrega
├── README.md         # instalação, configuração e manutenção
├── .env.example      # modelo das credenciais, se houver
├── .gitignore        # contendo .env
└── scripts/          # *.sh recebem bit de execução na instalação
```

Depois acrescente a ferramenta à tabela acima, com uma seção própria e link
para o `README.md` dela.

O nome da pasta vira o comando (`/ms-codereview`), então renomear a pasta
renomeia o comando. Mantenha o `SKILL.md` enxuto: ele carrega inteiro toda
vez que a skill dispara — o material extenso vai em arquivos que a skill
carrega sob demanda.

## Licença

[Apache 2.0](LICENSE).
