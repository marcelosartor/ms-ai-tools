# Checklist — Java / Spring Boot

Aplicar apenas ao que o diff efetivamente toca. `## Comum` aplica sempre;
`## JPA / Hibernate`, `## Spring Security`, `## WebFlux (reativo)` e
`## Mensageria (Kafka, RabbitMQ)` aplicam pela variante que casou em
`raw/checklists.json` (`variants["java-spring"]`: `jpa`, `security`,
`webflux`, `messaging`); sem `variants` para este checklist, aplicar
tudo. Base: Java 25 LTS, Spring Boot 4.x (Framework 7) — item que
difere no Boot 3.x anota a diferença.

## Comum

### Java (25 LTS como base)

- `record` para DTO, value object e chave composta; classe com só
  campos, getters e `equals` gerado é `record`. Entidade JPA **não** pode
  ser `record` (precisa de construtor sem argumento e mutabilidade).
- `sealed` + `switch` com pattern matching (21+) exaustivo sem `default`;
  `default` que engole subtipo novo é achado. `instanceof` com pattern
  (16+) em vez de cast.
- `Optional` só como retorno; como campo, parâmetro ou em coleção é
  achado. `Optional.get()` sem `isPresent`/`orElseThrow` é `NoSuchElementException`
  disfarçada.
- `var` em local com tipo óbvio pela direita; `var` que esconde o tipo
  de uma chamada é nit.
- Text block (`"""`) para SQL, JSON e HTML em código.
- Coleção imutável (`List.of`, `Stream.toList()`, `Collections.unmodifiable*`)
  exposta por getter; `Collectors.toList()` é mutável e ninguém garante
  que fica assim. Cópia defensiva de coleção recebida no construtor.
- Stream: sem efeito colateral em `map`/`filter`; `.parallel()` em I/O
  ou em coleção pequena; `findFirst` em stream não ordenado com a
  intenção de "o primeiro". Gatherers (24+) quando o projeto já usa.
- `InterruptedException` capturada restaura a flag
  (`Thread.currentThread().interrupt()`) ou propaga.
- `catch (Exception e)` que loga e segue; exceção checada embrulhada em
  `RuntimeException` sem causa; `throw` de `Error`.
- `try-with-resources` para tudo que é `AutoCloseable` (stream de
  arquivo, JDBC, `HttpClient` de 21+, `ExecutorService` em 19+).
- `BigDecimal` para dinheiro com `scale` e `RoundingMode` explícitos;
  `compareTo` para igualdade (`equals` compara scale). `double` para
  dinheiro é `blocker:`.
- `java.time` (`Instant` para armazenar e transportar; `ZonedDateTime`/
  `LocalDate` quando o dia civil importa) e `Clock` injetado para teste;
  `Date`, `Calendar`, `SimpleDateFormat` em código novo são achado.
- `String` comparada com `==`; `equals` sem `hashCode`; `hashCode` de
  entidade JPA baseado em campo mutável ou em id nulo antes do persist
  (usar id de negócio ou `getClass` + id com fallback constante).
- `enum` persistido ou serializado por `ordinal()`: reordenar quebra
  dado; `EnumType.STRING` ou campo explícito.
- Serialização Java nativa (`Serializable` + `ObjectInputStream`) em
  código novo é achado de segurança; formato explícito (JSON, protobuf).
- Threads: `synchronized` funciona com virtual threads sem pinning desde
  o 24; em 21, bloco `synchronized` longo com I/O dentro pina a carrier
  thread (`ReentrantLock`). `ThreadLocal` com virtual threads em massa
  custa memória: `ScopedValue` (final em 25) para contexto de requisição.
- `ExecutorService` de virtual threads (`newVirtualThreadPerTaskExecutor`)
  não é pool: nunca "reaproveitar" virtual thread; pool de conexão JDBC
  vira o gargalo e o tamanho dele precisa ser pensado.
- `CompletableFuture` sem executor usa o `commonPool` e bloqueia quem
  mais o usa; `join()` em thread de requisição é bloqueio disfarçado.
- Structured concurrency (`StructuredTaskScope`) ainda é preview em 25:
  `--enable-preview` em produção é achado, salvo decisão explícita do
  projeto.
- Log com placeholder (`log.info("x={}", x)`) e nunca concatenação nem
  `toString` de entidade com relação lazy; MDC limpo ao fim da
  requisição (com virtual threads, o filtro precisa garantir).
- `switch` clássico com fallthrough sem comentário; `switch` de
  expressão preferido.
- Kotlin com Spring: classe `open` (plugin `kotlin-spring` cuida das
  anotadas); `lateinit var` para injeção de campo é achado, construtor
  primário; `data class` como entidade JPA tem os mesmos problemas de
  `equals`/`hashCode`; nulabilidade de coluna coerente com o tipo.

### Spring: camadas, beans e transação

- Controller sem regra de negócio; service sem `HttpServletRequest`,
  `ResponseEntity` ou header; repositório sem lógica.
- Injeção por construtor (com `final`); `@Autowired` em campo é achado.
  Um construtor não precisa da anotação.
- Bean singleton com estado mutável por requisição (campo que guarda o
  usuário, contador, `SimpleDateFormat`) é bug de concorrência e
  vazamento entre usuários.
- Dependência circular entre beans: proibida por padrão desde Boot 2.6;
  `@Lazy` para contornar é sintoma que merece ser dito.
- `@Transactional` em método público de bean chamado de **fora** do
  bean: chamada interna (`this.metodo()`) não passa pelo proxy e não abre
  transação; método `private`/`final` idem. Kotlin: classe e método
  precisam ser `open` (o plugin faz).
- `@Transactional` só faz rollback em `RuntimeException` e `Error`;
  exceção checada precisa de `rollbackFor`. `catch` dentro do método
  transacional que engole a exceção do repositório deixa a transação
  marcada como rollback-only e o commit falha depois com mensagem
  confusa.
- `@Transactional(readOnly = true)` em leitura; sem isso o Hibernate faz
  dirty check em tudo que carregou.
- Transação longa envolvendo chamada HTTP, fila ou espera: segura
  conexão do pool; o efeito externo sai da transação ou vai para
  `@TransactionalEventListener(AFTER_COMMIT)`/outbox.
- `spring.jpa.open-in-view=false`; com `true` (padrão), a sessão dura a
  requisição inteira e esconde `LazyInitializationException` no
  controller à custa de conexão presa.
- `@Async` só funciona em método público chamado de outro bean, com
  `@EnableAsync` e executor configurado (Boot autoconfigura
  `applicationTaskExecutor`; com `spring.threads.virtual.enabled=true`
  ele usa virtual threads); retorno `void` engole exceção sem
  `AsyncUncaughtExceptionHandler`.
- `@Scheduled` em app com mais de uma instância roda em todas: ShedLock
  ou fila; `fixedRate` com execução mais longa que o intervalo empilha.
- Evento de domínio (`ApplicationEventPublisher`) síncrono por padrão:
  listener lento trava o publicador; `@TransactionalEventListener` para
  reagir após commit.
- `@ConfigurationProperties` com `@Validated` em vez de `@Value`
  espalhado; propriedade nova documentada e com padrão seguro; segredo
  via ambiente/vault, nunca em `application.yml` versionado.
- Perfil (`@Profile`, `spring.profiles.active`): código só de dev
  (`@Profile("dev")`) não tem efeito colateral quando ausente.
- Bean condicional (`@ConditionalOn*`) novo tem teste de que existe e de
  que não existe nas duas condições.
- Boot 4: starters renomeados (`spring-boot-starter-web` →
  `spring-boot-starter-webmvc`, e outros), autoconfiguração
  modularizada; PR de upgrade cita a nota de migração e não mistura
  feature com upgrade.

### Web (MVC e contratos)

- `@Valid` em `@RequestBody` e `@Validated` na classe para `@RequestParam`/
  `@PathVariable`; DTO com constraints Jakarta Validation (`@NotNull`,
  `@Size`, `@Pattern`), aninhado com `@Valid` no campo.
- Entidade JPA como `@RequestBody` ou como resposta é achado: DTO ou
  `record` de entrada/saída; binding direto em entidade é mass
  assignment.
- `@ControllerAdvice` com `ProblemDetail` (RFC 9457,
  `spring.mvc.problemdetails.enabled=true`) e mapeamento explícito;
  handler genérico que devolve `e.getMessage()` ao cliente vaza detalhe.
- Status HTTP coerente: 201 em criação com `Location`, 204 sem corpo,
  404 vs 403 conforme política de enumeração, 409 em conflito.
- Paginação com `Pageable` e `spring.data.web.pageable.max-page-size`
  definido; endpoint que devolve `List` de tabela sem limite é achado.
  `Page` faz `count(*)`; `Slice` quando o total não é necessário.
- Versionamento de API: Framework 7 tem `@RequestMapping(version = ...)`
  e `ApiVersionConfigurer`; mudança incompatível em endpoint existente
  sem versão é achado de contrato.
- Cliente HTTP novo com `RestClient` (síncrono) ou `WebClient` (reativo);
  `RestTemplate` em código novo é achado. Timeouts de conexão e leitura
  configurados no `ClientHttpRequestFactory`; sem eles, sem limite.
  Interface HTTP declarativa (`@HttpExchange` + `@ImportHttpServices` no
  Framework 7) quando o projeto adota.
- Resiliência: Framework 7 traz `@Retryable` e `@ConcurrencyLimit` no
  core (`org.springframework.resilience`); Boot 3.x usa Spring Retry ou
  Resilience4j. Retry só em operação idempotente, com backoff e limite;
  circuit breaker para dependência externa que cai.
- Upload: `spring.servlet.multipart.max-file-size` e `max-request-size`
  definidos; tipo do arquivo validado pelo conteúdo, não pela extensão;
  gravado fora da árvore da app com nome gerado.
- Cache: `@Cacheable` com chave explícita quando o método tem mais de um
  argumento; `@CacheEvict`/`@CachePut` na escrita; TTL configurado no
  `CacheManager` (o padrão em memória não expira); valor serializável
  quando o cache é Redis; chamada interna não passa pelo proxy (mesmo
  problema de `@Transactional`).
- Jackson 3 no Boot 4 (`tools.jackson.*`): padrões mudaram em relação ao
  2 (ex.: propriedade desconhecida não falha mais por padrão; formatos
  de data); PR que migra confere serialização de cada DTO com teste, e
  `@JsonProperty`/`@JsonIgnore` vêm do pacote novo. Anotação do Jackson
  2 numa classe serializada pelo 3 é ignorada em silêncio.
- Observabilidade: `@Observed`/Micrometer no caso de uso novo, log com
  `traceId`; endpoint novo aparece nas métricas com tag de rota, não
  com id na URL (cardinalidade).

### Configuração e segurança de plataforma

Aplica sempre; a variante `security` aprofunda.

- Actuator: `management.endpoints.web.exposure.include` restrito;
  `env`, `heapdump`, `threaddump` expostos sem auth é `blocker:`.
  `management.server.port` separado ou endpoints atrás de auth.
- `server.error.include-stacktrace`/`include-message` em `never` fora de
  dev.
- `spring.jpa.hibernate.ddl-auto` em `none`/`validate` em produção;
  `update`/`create` é `blocker:`. Schema por Flyway/Liquibase.
- CORS via `CorsConfigurationSource` com origens explícitas;
  `@CrossOrigin("*")` em endpoint autenticado é achado.
- Segredo, senha de banco, chave de API em `application*.yml`
  versionado, `@Value` com default hardcoded, ou log de `Environment`.
- Log de request com body ou header `Authorization` (filtro de log,
  `logging.level.org.springframework.web=DEBUG` em produção).
- Dependência nova: gerenciada pelo BOM do Boot (sem versão explícita
  quando o BOM tem), necessária, mantida, o que puxa; advisory
  consultado (F4).

### Testes

- Slice test (`@WebMvcTest`, `@DataJpaTest`, `@JsonTest`,
  `@RestClientTest`) onde basta; `@SpringBootTest` sobe o contexto
  inteiro e `@DirtiesContext` a cada teste multiplica o tempo.
- Banco de teste é o mesmo de produção via Testcontainers
  (`@ServiceConnection`, Boot 3.1+); H2 tem dialeto diferente e passa
  query que quebra no Postgres.
- `@MockitoBean`/`@MockitoSpyBean` (Boot 3.4+; `@MockBean` foi removido
  no Boot 4). Mock de repositório em teste de service com lógica de
  query esconde o SQL errado.
- `@Transactional` em teste faz rollback e esconde erro de flush e de
  constraint: `TestEntityManager.flush()` ou teste sem `@Transactional`
  com limpeza explícita para o caminho de escrita.
- `MockMvc` (ou `MockMvcTester` com AssertJ, Boot 3.4+) para controller:
  caminho feliz, validação (400), auth (401/403), não encontrado.
- `@WithMockUser`/`@WithSecurityContext` em teste de endpoint protegido;
  teste que passa sem usuário em rota que deveria exigir é achado.
- `MockRestServiceServer`/WireMock para cliente HTTP; teste que bate na
  API real é flaky.
- ArchUnit (quando o projeto tem) para regra de camada; se não tem e o
  PR cruza camada, é sugestão.
- Correção de bug vem com teste que falha sem o fix. Nenhum teste sem
  asserção. `Thread.sleep` em teste é flaky: Awaitility.

## JPA / Hibernate

- N+1: relação acessada em loop sem `JOIN FETCH`, `@EntityGraph` ou
  projeção; `spring.jpa.properties.hibernate.default_batch_fetch_size`
  como rede de segurança, não como solução.
- `FetchType.EAGER` em coleção é achado; `@ManyToOne` é EAGER por padrão
  e precisa de `LAZY` explícito.
- Bidirecional: `mappedBy` do lado certo, os dois lados sincronizados no
  método de domínio (`addItem` seta o pai); `@OneToMany` sem `mappedBy`
  cria tabela de junção sem querer.
- `equals`/`hashCode` (ver Java); `toString` gerado com Lombok em
  entidade com relação lazy dispara query ou `LazyInitializationException`.
- `@Version` para update concorrente de registro que dois usuários
  editam; sem ele o último grava por cima. `@Lock(PESSIMISTIC_WRITE)`
  para saldo/estoque.
- Batch: `GenerationType.IDENTITY` desliga o batch de insert;
  `SEQUENCE` com `allocationSize` e `hibernate.jdbc.batch_size`.
  `saveAll` de dez mil entidades sem `flush`/`clear` periódico estoura
  memória.
- `@Query` JPQL/nativa com parâmetro nomeado; concatenação de string em
  query é `blocker:`. Query derivada com nome de sessenta caracteres é
  nit; com lógica que o nome não expressa, `@Query`.
- `@Modifying` com `clearAutomatically = true` (ou `flushAutomatically`)
  em update/delete em massa; entidade em cache de primeiro nível fica
  desatualizada sem isso.
- Projeção (interface ou `record`) para leitura de lista; carregar
  entidade inteira com relações para mostrar duas colunas.
- `Specification`/Criteria para filtro dinâmico; `if` encadeado montando
  JPQL em string.
- Migration Flyway/Liquibase para toda mudança de entidade; a migration
  segue o checklist de banco; `V__` já aplicada nunca é editada.
- Tipo de coluna coerente: `Instant`/`OffsetDateTime` em `timestamptz`,
  `BigDecimal` com `precision`/`scale`, `@Enumerated(STRING)`, `@Lob`
  consciente, `@Column(length)` só com motivo.
- Soft delete via `@SQLRestriction`/`@SoftDelete` (Hibernate 6.4+) com
  índice parcial no banco; filtro esquecido numa query nativa mostra
  registro apagado.
- Multi-tenant: discriminador aplicado por filtro do Hibernate ou por
  RLS; query nativa que ignora o filtro é vazamento.

## Spring Security

- `SecurityFilterChain` com `anyRequest().authenticated()` no fim;
  `permitAll` é lista explícita e curta; rota nova não listada é
  autenticada por padrão. `denyAll` para actuator sensível.
- Autorização de recurso (é *dele*?) com `@PreAuthorize` referenciando o
  principal e o id, ou verificação no service; só "está logado" não
  basta.
- Method security habilitada (`@EnableMethodSecurity`); `@PreAuthorize`
  em método chamado internamente não passa pelo proxy (mesma regra do
  `@Transactional`).
- CSRF: desligado só em API stateless com bearer token; com sessão por
  cookie, ligado, e o front envia o token. `csrf().disable()` num app com
  form login é `blocker:`.
- Sessão: `sessionCreationPolicy(STATELESS)` em API por token; com
  sessão, `sessionFixation().migrateSession()`, cookie `HttpOnly`,
  `Secure`, `SameSite` (`server.servlet.session.cookie.*`), timeout.
- Senha com `PasswordEncoder` (`DelegatingPasswordEncoder`, bcrypt ou
  argon2); comparação de hash constante; senha nunca logada nem
  devolvida.
- JWT: validação de assinatura, `iss`, `aud`, `exp`; algoritmo fixo
  (`none`/`HS` quando se espera `RS` é bypass); resource server via
  `oauth2ResourceServer().jwt()` com `jwk-set-uri`, não parser manual.
- Rate limit em login, reset de senha e envio de código
  (Bucket4j/gateway); sem ele, força bruta.
- Mensagem de erro de login não distingue usuário inexistente de senha
  errada.
- `@AuthenticationPrincipal` ou `SecurityContextHolder` no controller;
  id do usuário vindo de parâmetro da requisição para "quem sou eu" é
  IDOR.
- Headers de segurança do Spring (`headers()` padrão: HSTS, X-Content-Type,
  frame options) não desligados sem motivo; CSP quando serve HTML.
- Teste: cada regra nova de `SecurityFilterChain` tem teste com e sem
  autenticação; `@WithMockUser` com o papel errado devolve 403.

## WebFlux (reativo)

- Nada bloqueante dentro de `Mono`/`Flux` (JDBC, `RestTemplate`,
  `Thread.sleep`, `block()`): trava o event loop. R2DBC ou
  `publishOn(Schedulers.boundedElastic())` com motivo.
- `subscribe()` manual em código de aplicação é achado: a cadeia é
  retornada e o framework assina.
- Erro tratado com `onErrorResume`/`onErrorMap` no lugar certo; `doOnError`
  só observa.
- `flatMap` sem limite de concorrência em `Flux` grande; `concatMap`
  quando a ordem importa.
- `Mono` reutilizado com `cache()` consciente; `Mono.just(valorCaro)`
  avalia na construção.
- Contexto (`contextWrite`/`deferContextual`) para segurança e tracing;
  `ThreadLocal` não funciona.
- Backpressure: `Flux` de banco ou fila consumido com `limitRate` quando
  o consumidor é mais lento.
- Teste com `StepVerifier` e `WebTestClient`; `block()` em teste é
  aceitável, em produção não.

## Mensageria (Kafka, RabbitMQ)

- Consumer idempotente: a mesma mensagem chega duas vezes (at-least-once);
  chave de deduplicação ou operação naturalmente idempotente.
- Ack manual ou modo de ack coerente com o tratamento de erro; ack antes
  de processar perde mensagem em falha.
- Retry com limite e backoff (`DefaultErrorHandler`/`RetryTopic`), e
  dead-letter; sem DLT, mensagem venenosa trava a partição.
- Escrita no banco e publicação de evento na mesma operação: outbox
  transacional ou `@TransactionalEventListener(AFTER_COMMIT)`; publicar
  dentro da transação e dar rollback gera evento de algo que não
  aconteceu.
- Schema da mensagem versionado (campo novo opcional; nunca renomear
  nem mudar tipo); `JsonDeserializer` com `trusted.packages` restrito,
  nunca `*`.
- Chave de partição escolhida pela ordenação necessária (por
  agregado); sem chave, a ordem por entidade não existe.
- Consumer com `concurrency` maior que o número de partições desperdiça
  threads; `max.poll.interval` coerente com o tempo de processamento.
