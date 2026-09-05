# Checklist — pipeline, container, infra

Aplicar apenas ao que o diff efetivamente toca.

## GitHub Actions / CI

- `pull_request_target` com `actions/checkout` do `head` do PR executa
  código de fork com segredo do repositório. Só com `persist-credentials:
  false` e sem segredo, ou trocar por `pull_request`.
- Entrada não confiável (`github.event.pull_request.title`, `body`,
  `head_ref`, `issue.title`, comentário) interpolada direto em `run:`
  é injeção de shell; passar por `env:` e citar `"$VAR"`.
- Action de terceiro pinada por sha completo, não por tag mutável; tag
  major (`@v4`) é aceitável só para actions oficiais se o projeto já
  faz assim.
- `permissions:` mínimo no workflow ou job; padrão `write-all` é achado.
- Segredo impresso em log (`echo $SECRET`, `set -x` com segredo no
  ambiente).
- Cache de dependência com chave que inclui o lockfile; cache sem chave
  correta serve dependência errada.
- Job de deploy só em `main`/tag, com `environment` protegido; deploy
  disparado por PR é achado.
- `continue-on-error: true` em passo que deveria falhar o pipeline.
- Matriz ou runner mudou de versão sem o motivo.
- Timeout no job (`timeout-minutes`); sem ele um job travado consome
  minutos até o limite de 6 h.

## Container

- Imagem base pinada por tag específica (e idealmente digest), não
  `latest`; base atualizada quando a anterior tem CVE conhecido.
- Usuário não-root no `Dockerfile` (`USER`); processo como root em
  container é achado.
- Segredo em `ARG`/`ENV`/layer: fica na imagem. Montar em runtime ou
  usar `--secret`.
- `.dockerignore` exclui `.git`, `node_modules`, `.env`, `temp/`.
- Ordem de layers: dependências antes do código, para cache; `COPY . .`
  antes do `npm ci` invalida tudo.
- `HEALTHCHECK` ou probe equivalente; app que trava sem morrer não é
  reiniciada.
- Sinal de parada chega ao processo (`exec` no entrypoint, sem shell
  intermediário); `SIGTERM` que não chega vira `SIGKILL` sem shutdown
  gracioso.
- JVM em container: flags container-aware (padrão desde 17) e limite de
  heap coerente com o limite do container.
- Multi-stage: imagem final sem toolchain de build.

## Infra como código e configuração de serviço

- Recurso público (bucket, DB com IP público, porta aberta 0.0.0.0/0)
  sem justificativa.
- Segredo em `.tf`, `values.yaml`, `docker-compose.yml` versionado.
- Mudança destrutiva (`destroy`, replace de banco, rename de recurso
  stateful) sem plano e sem backup.
- Nginx/proxy: `client_max_body_size`, timeouts, `proxy_set_header
  X-Forwarded-*`, e a app confia nesses headers só vindo do proxy.
- Réplica ou escala mudou e o que roda `@Scheduled`/cron sabe disso
  (lock distribuído).
- Log e métrica do serviço novo chegam onde os outros chegam.
