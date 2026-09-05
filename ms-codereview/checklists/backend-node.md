# Checklist — backend Node (Express, Fastify, NestJS)

Aplicar apenas ao que o diff efetivamente toca. `## Comum` aplica sempre;
`## Express`, `## Fastify` e `## NestJS` aplicam pela variante que casou
em `raw/checklists.json` (`variants["backend-node"]`); `## NestJS sobre
Fastify` aplica quando `nest` e `fastify` estão ambas na lista. Sem
`variants` para este checklist, aplicar tudo.

## Comum

Camadas e contrato:

- Handler de rota sem regra de negócio: valida entrada, chama serviço,
  monta resposta. Serviço sem `req`/`res`/header.
- Toda entrada de rota (body, query, params, header usado) validada por
  schema (zod, joi, ajv, class-validator); sem `body: any`. Query string
  é sempre string: número e booleano são convertidos e validados, não
  assumidos.
- Entidade do ORM ou linha do banco não vai direto na resposta: mapear
  para DTO. Coluna nova vaza sem querer, inclusive sensível.
- Rota nova autenticada por padrão; pública só com marcação explícita.
  Autorização além de autenticação: o usuário pode agir sobre *aquele*
  recurso.
- Endpoint que cria recurso e pode ser repetido pelo cliente (retry,
  duplo clique) tem chave de idempotência ou é naturalmente idempotente.
- Lista sem limite: paginação com `limit` máximo imposto no servidor.
- Resposta de erro segue um formato só (RFC 9457 ou o do projeto), sem
  SQL, stack trace, path ou mensagem interna.
- Mudança em contrato de resposta ou parâmetro existente é breaking para
  quem consome: versão, campo novo opcional, ou nota de migração.

Assincronia e erros:

- Todo `Promise` é aguardado ou tem `.catch()`. Rejeição não tratada
  derruba o processo no Node 15+.
- `forEach` com callback `async` não espera nada: `for...of` ou
  `Promise.all`. `Promise.all` em lote grande sem limite de concorrência
  estoura conexões: `p-limit` ou fatiar.
- `catch` que engole sem tratar nem relançar. `catch` que loga e
  responde 200.
- Erro específico (classe própria ou `HttpError` do framework) em vez de
  `throw new Error()` genérico que vira 500.
- `process.on('unhandledRejection')` e `uncaughtException` existem no
  bootstrap e **encerram** o processo depois de logar; não "seguram" o
  processo vivo.
- Chamada HTTP de saída tem timeout (`AbortSignal.timeout`, `timeout` do
  cliente); retry só em operação idempotente e com backoff.
- Job, consumer ou listener que pode falhar tem retry com limite e
  dead-letter; handler é idempotente porque a mensagem pode chegar duas
  vezes.
- Operação que bloqueia o event loop: `fs.*Sync`, `crypto.pbkdf2Sync`,
  `JSON.parse` de payload grande, regex com repetição aninhada em
  entrada do usuário, loop de CPU. `worker_threads` ou versão assíncrona.
- Stream sem tratamento de `error` e sem backpressure (`pipeline` em vez
  de `.pipe()` encadeado).
- `setInterval` sem `clearInterval` no shutdown; timer que mantém o
  processo vivo sem `unref()` quando não deveria.
- Shutdown gracioso: `SIGTERM` fecha servidor, espera requisições em
  voo, fecha pool e fila.

Banco de dados (pelo ORM ou driver; o checklist de banco cobre SQL e
migration):

- Escrita em mais de uma tabela roda em transação.
- Nenhuma query dentro de `for`, `map`, `forEach` (N+1).
- Read-modify-write concorrente (saldo, estoque, contador, status)
  usa lock, update atômico ou versão otimista; ler, calcular e gravar
  perde update.
- Query em tabela multi-tenant filtra pelo tenant do chamador.
- Entrada do usuário nunca é concatenada em query, comando ou path,
  inclusive em `raw()`, `query()` e template string do ORM.
- `path.join(base, entrada)` não impede traversal; `path.resolve` e
  conferir que o resultado começa com `base`.
- Conexão e cliente de banco são singleton por processo, não por
  requisição.

Configuração e segurança:

- Nenhum segredo, token, chave ou connection string no diff.
- `process.env` lido num único módulo de configuração, validado por
  schema no bootstrap, com tipo; não espalhado com fallback silencioso.
- Variável de ambiente nova está em `.env.example` e documentada.
- Log não inclui senha, token, e-mail, CPF, documento, body de request
  ou header `Authorization`. Logger estruturado com `redact` configurado
  (pino) quando o projeto usa.
- Dependência nova: é necessária? é mantida? o que puxa junto? (o
  relatório de advisories já foi lido)
- `engines.node` ou `.nvmrc` compatível com API usada (`fetch` global,
  `AbortSignal.timeout`, `structuredClone`, `--env-file`).
- ESM e CJS não se misturam sem interop explícito; `require` de módulo
  ESM-only falha em runtime, não no typecheck.
- Dinheiro em `number` com ponto flutuante: inteiro em centavos ou
  biblioteca decimal.
- Data e hora: `Date` sem fuso explícito em cálculo de dia civil.

Testes:

- Regra de negócio nova ou corrigida vem com teste; correção de bug vem
  com teste que falha sem o fix.
- Nenhum teste sem asserção. Teste de rota cobre caminho feliz e ao
  menos um erro esperado (validação, 401/403, 404).
- Mock do banco em teste de query com lógica esconde N+1 e SQL errado:
  teste de integração com banco real (testcontainers ou o do CI).
- Teste que depende de ordem, de hora real (`Date.now()` sem fake) ou
  de rede externa é flaky.

## Express

- Express 4: handler `async` que rejeita **não** chega ao middleware de
  erro; precisa de `try/catch` + `next(err)` ou `express-async-errors`.
  Express 5: rejeição vai para `next` sozinha, mas `try/catch` que engole
  continua sendo achado.
- Middleware de erro tem exatamente quatro parâmetros
  (`err, req, res, next`) e é registrado **depois** das rotas.
- Ordem de `app.use` importa: auth, body parser e CORS antes das rotas
  que dependem deles; 404 handler por último.
- `res.send`/`res.json` depois de já ter respondido (`ERR_HTTP_HEADERS_SENT`):
  todo caminho retorna após responder.
- Body parser com `limit` explícito; `express.json()` sem limite aceita
  payload de 100 kB por padrão, com limite maior sem justificativa é
  DoS.
- `app.set('trust proxy', ...)` configurado quando há proxy na frente;
  sem isso `req.ip` e `secure` estão errados. Com `true` sem restrição,
  `X-Forwarded-For` é forjável.
- Express 4: `req.query` é objeto aninhado via `qs` (`?a[b]=1`): validar
  o tipo antes de usar; `?id[]=1` transforma string em array. Express 5:
  parser "simple" por padrão, comportamento diferente do 4 ao migrar.
- Express 5: sintaxe de rota mudou (`path-to-regexp` 8): `*` vira
  `/*splat`, `?` opcional vira `{/:param}`; rota migrada sem ajuste não
  casa mais.
- `express.static` com diretório que contém arquivo sensível
  (`.env`, `.git`).
- `helmet` (ou headers equivalentes) e `cors` com `origin` explícito;
  `cors()` sem opção libera tudo.
- Sessão: `cookie.secure`, `httpOnly`, `sameSite`, `secret` de
  ambiente; store de sessão em memória (`MemoryStore`) é só para dev.
- Router modular (`express.Router()`) com prefixo; rota definida direto
  em `app` fora do bootstrap é organização, não achado, salvo padrão do
  projeto.

## Fastify

- Toda rota tem `schema` de `body`, `querystring`, `params` e
  **`response`**: sem schema de resposta não há `fast-json-stringify` e
  campo não declarado vaza; com schema, campo não declarado é
  silenciosamente omitido, o que também esconde bug.
- Handler `async` **retorna** o payload ou faz `await reply.send()`;
  `reply.send()` sem `return`/`await` em handler async gera resposta
  duplicada ou promise pendurada.
- Plugin com estado compartilhado (decorator, hook global) usa
  `fastify-plugin` para quebrar o encapsulamento; sem ele, o decorator
  só existe no escopo do plugin e `fastify.x` é `undefined` fora.
- Registro de plugin é assíncrono: acesso a decorator antes de
  `await fastify.ready()` ou dentro do mesmo `register` sem `await`.
- Hook certo para cada coisa: `onRequest` para auth que não precisa do
  body, `preHandler` quando precisa, `preValidation` para transformar
  entrada; auth em `preHandler` valida body antes de autenticar.
- Ajv coage tipos por padrão (`coerceTypes`): `"1"` vira `1`; o schema
  precisa restringir o que aceita (`minimum`, `enum`) e não confiar só
  no tipo.
- `bodyLimit` e `connectionTimeout`/`requestTimeout` definidos no
  construtor; padrão de 1 MiB e sem timeout de requisição.
- Logger pino do próprio Fastify com `redact` para `req.headers.authorization`,
  `cookie` e campos de body sensíveis.
- Decorator de request (`fastify.decorateRequest`) com valor de objeto ou
  array compartilha a referência entre requisições: inicializar com
  `null` e atribuir no hook.
- `reply.hijack()` ou stream manual: `reply.raw` sem finalizar deixa a
  conexão aberta.
- Erro customizado com `statusCode` ou `@fastify/sensible`;
  `setErrorHandler` não vaza `validation` cru na resposta em produção.
- `trustProxy` configurado quando há proxy.

## NestJS

- `ValidationPipe` global com `whitelist: true` e
  `forbidNonWhitelisted: true` (ou `transform` consciente): sem
  `whitelist`, campo não declarado no DTO chega ao serviço (mass
  assignment).
- DTO aninhado tem `@ValidateNested()` e `@Type(() => Classe)`; sem os
  dois, o objeto interno não é validado e o pipe passa qualquer coisa.
- Provider novo está registrado em `providers` do módulo, e o módulo
  que o exporta está em `imports` de quem usa; erro de DI é runtime, o
  typecheck não pega.
- Provider singleton (padrão) não guarda estado por requisição em
  propriedade: vaza dado entre usuários. `Scope.REQUEST` resolve mas se
  propaga para quem injeta e cria instância por requisição; usar
  `CLS`/`AsyncLocalStorage` ou passar o contexto como argumento.
- `forwardRef` para dependência circular é sintoma; módulo novo que
  precisa dele merece ser dito.
- Ordem de execução: middleware → guard → interceptor (antes) → pipe →
  handler → interceptor (depois) → filter. Auth em interceptor ou pipe
  é lugar errado; guard não tem acesso ao body validado.
- Guard lê `request.user` posto por uma strategy/guard anterior; rota
  com `@UseGuards(RolesGuard)` sem `AuthGuard` antes tem `user`
  `undefined`.
- Exception filter global devolve formato único e não vaza `stack` fora
  de dev; `HttpException` das camadas HTTP, exceção de domínio mapeada
  no filter, não `throw new HttpException` dentro do service.
- Interceptor de resposta que envolve tudo em `{data}` quebra quem
  espera stream ou download.
- `@Res()` no handler desliga a serialização e os interceptores; usar
  `@Res({ passthrough: true })` quando só precisa de cookie/header.
- `ConfigModule` com `validationSchema`/`validate` e `ConfigService`
  tipado; `process.env` direto fora do módulo de config é achado.
- `@Cron`/`@Interval` em app com mais de uma instância roda em todas:
  lock distribuído ou fila.
- `@OnEvent` handler que lança exceção derruba o emissor a menos que
  `suppressErrors`; handler assíncrono sem `await` engole erro.
- BullMQ/queue: `@Process` idempotente, `attempts` e `backoff`
  configurados, `removeOnComplete` para não crescer o Redis.
- Swagger: decorator `@ApiProperty` divergente do DTO é nit, mas
  `@ApiResponse` prometendo campo que a resposta não tem é achado de
  contrato.
- Teste de módulo com `Test.createTestingModule` substitui só o que
  precisa (`overrideProvider`); mockar o repositório em teste de service
  com lógica de query esconde o SQL errado.
- Teste e2e cria a app com o **mesmo** adaptador de produção (ver
  seção abaixo) e chama `app.init()` (Express) ou
  `app.getHttpAdapter().getInstance().ready()` (Fastify) antes das
  requisições.

## NestJS sobre Fastify

- `@Res()` é `FastifyReply`, não `Response` do Express: `res.status().json()`
  do Express não existe; `reply.code().send()`.
- Multipart: `multer`/`FileInterceptor` não funcionam; `@fastify/multipart`
  registrado no adaptador e handler próprio.
- Webhook que valida assinatura precisa de `rawBody: true` em
  `NestFactory.create` e `@Req() req.rawBody`; com Express o mecanismo é
  outro.
- Middleware Nest (`configure(consumer)`) roda em cima de hook do
  Fastify e não vê `req.body`; wildcard de rota em `forRoutes` segue a
  sintaxe do Fastify, não a do Express.
- `enableCors` e `helmet` usam as versões `@fastify/cors` e
  `@fastify/helmet` registradas no adaptador; o pacote do Express
  registrado como middleware não funciona.
- Erro que o Fastify gera na validação de schema do próprio adaptador
  (quando alguém adiciona `schema` na rota) chega antes do
  `ValidationPipe`; um dos dois é redundante.
- Teste e2e com `NestFastifyApplication` e `FastifyAdapter`, mais
  `await app.getHttpAdapter().getInstance().ready()`; supertest funciona
  com `app.getHttpServer()` só depois disso.
