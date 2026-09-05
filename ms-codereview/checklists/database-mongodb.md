# Checklist — MongoDB

Aplicar apenas ao que o diff efetivamente toca.

Base: MongoDB 7 e 8, driver Node `mongodb` 6.x, Mongoose 8, Spring Data
MongoDB (Boot 4), Java driver 5. Atlas quando o item diz.

## Modelagem e schema

- Modelar pelo padrão de acesso: embutir o que é lido junto e tem
  tamanho limitado; referenciar o que cresce sem limite ou é
  compartilhado. Array que só cresce dentro do documento (comentários,
  eventos, log) bate no limite de 16 MB e reescreve o documento inteiro
  a cada `$push`: coleção própria ou bucket pattern.
- Validação de schema no banco (`$jsonSchema` com `validationLevel`), não
  só no Mongoose ou na entidade: script, outro serviço e o shell também
  escrevem. Campo obrigatório novo entra no validador junto do backfill.
- Mongoose: `strict` (padrão) descarta campo desconhecido em silêncio;
  `strictQuery` decide se filtro por campo fora do schema vira `{}`.
  Campo com erro de digitação vira campo novo sem aviso: schema tipado,
  e `required`/`enum`/`default` no schema.
- Tipos: dinheiro em `Decimal128`, nunca `Double`; data em `Date` (BSON,
  UTC), não string; inteiro de 64 bits em `Long`/`BigInt`, não `Number`
  do JS acima de 2^53.
- `_id`: `ObjectId` ou string, mas um só por coleção e igual ao que a
  query usa. Filtro com string contra campo `ObjectId` não acha nada e
  não dá erro.
- Documento antigo não tem o campo novo: código lê com default, trata
  `$exists: false`, ou o PR traz backfill em lotes (`updateMany` com
  filtro `{campo: {$exists: false}}` e `limit` via cursor). Campo
  `schemaVersion` quando a coleção evolui muito.
- Cópia desnormalizada (nome do usuário no pedido) tem caminho de
  atualização ou o PR diz que aceita ficar desatualizada.
- Polimorfismo com discriminador (Mongoose `discriminator`, Spring
  `_class`); coleção por tipo ou por tenant é anti-padrão (limite de
  coleções, índices duplicados). Tenant como campo indexado.
- `save()` no Spring Data e `replaceOne` substituem o documento inteiro:
  campo que a entidade não conhece some. Atualização parcial com
  `Update`/`$set`.
- Índice declarado no código (`index: true`, `@Indexed`) com criação
  automática desligada em produção (`autoIndex: false`;
  `spring.data.mongodb.auto-index-creation` é `false` por padrão desde o
  Boot 3): criar índice é migration explícita, não efeito colateral do
  deploy.
- Time series collection para métrica e telemetria; capped collection
  para log com rotação; TTL para dado que expira.

## Índices

- Toda query nova tem índice; `COLLSCAN` em `explain("executionStats")`
  numa coleção grande é achado; `totalDocsExamined` muito maior que
  `nReturned` idem.
- Índice composto na ordem ESR: igualdade, ordenação, intervalo. Índice
  na ordem errada serve para o filtro e não para o `sort`, que vai para
  memória (limite de 100 MB, erro sem `allowDiskUse`).
- Campo array vira índice multikey; composto com dois arrays é proibido.
- `unique` em campo que pode faltar: documento sem o campo conta como
  `null`, o segundo falha. `partialFilterExpression: {campo: {$exists:
  true}}` (`sparse` é legado).
- Índice parcial para filtro fixo (`{status: "ativo"}`); TTL
  (`expireAfterSeconds`) em vez de cron de `deleteMany`; o TTL apaga em
  background, não no segundo exato.
- `$regex` sem âncora `^` não usa índice; case-insensitive com índice de
  collation (`strength: 2`), não `$options: "i"`. Collation da query
  igual à do índice.
- Text index (um por coleção) ou Atlas Search; `$text` sem índice falha.
- Build de índice em coleção grande é pesado e, em replica set, rolling
  quando possível; nunca no startup da app.
- Índice demais custa escrita; índice não usado (`$indexStats`) sai.
  Wildcard index só com justificativa.
- Query coberta (projeção dentro do índice) para lista quente.
- Atlas Vector Search: definição do índice versionada, `numDimensions`
  igual ao modelo de embedding, `numCandidates` ≥ `limit` (10x é o
  ponto de partida), campo de pré-filtro declarado no índice; trocar de
  modelo é campo novo e reindexação (mesma regra do pgvector).

## Queries e escrita

- Filtro construído com objeto vindo da requisição
  (`find(req.query)`, `{email: req.body.email}` recebendo `{$gt: ""}`) é
  injeção de operador: validar tipo e forma antes, `sanitizeFilter`
  (Mongoose) ou `express-mongo-sanitize`. `$where`, `$function`,
  `mapReduce` com string do usuário é execução de código. `$regex` com
  entrada do usuário sem escape é ReDoS.
- Filtro que pode virar `{}`: variável `undefined` num campo
  (`{userId: undefined}`) faz o Mongoose remover o campo e o
  `updateMany`/`deleteMany` pegar a coleção inteira. `blocker:` quando
  o caminho existe.
- Atualização atômica com operador (`$inc`, `$set`, `$push`,
  `$addToSet`) e `findOneAndUpdate` filtrando pelo estado esperado; ler,
  alterar na app e gravar perde update. Versão otimista (`__v` com
  `optimisticConcurrency`, `@Version` no Spring) para documento que dois
  usuários editam.
- Upsert precisa de índice único no campo do filtro, senão dois upserts
  simultâneos inserem dois; e o código trata `E11000` com retry.
- Transação multi-documento só quando a modelagem não resolve; curta
  (limite de 60 s, `WriteConflict` tem retry); toda operação recebe
  `session`, e a que esquece roda fora da transação sem aviso.
- Write concern `majority` para dado que não pode sumir em failover;
  `w: 0` é perda de dado. Read preference `secondaryPreferred` lê
  desatualizado: relatório sim, "leia o que acabou de gravar" não.
- Paginação com `skip` grande é O(n): keyset por `_id` ou pelo campo do
  `sort` indexado; `sort` em resultado grande sem índice estoura a
  memória.
- Projeção sempre; `lean()` no Mongoose para leitura (hidratar documento
  custa); `select: false` no schema para senha e token, e `toJSON` que
  remove `__v` e sensível.
- Aggregation: `$match` primeiro e com índice, `$project` cedo,
  `$lookup` no campo indexado da coleção estrangeira; `$lookup` em loop
  é N+1; `$unwind` multiplica documentos; estágio acima de 100 MB
  precisa de `allowDiskUse`; `$group` na coleção inteira sem `$match`.
- `$in` com array enorme, `$or` sem índice em cada ramo, `$ne`, `$nin`,
  `$exists: false` usam índice mal ou não usam.
- Cursor: `toArray()` de resultado sem limite; iterar em lotes; cursor
  sem consumir expira em 10 min e `noCursorTimeout` é leak.
- `countDocuments` (exato, com filtro) vs `estimatedDocumentCount`
  (metadado, rápido); `count()` é deprecated.
- Mongoose: `updateOne`/`findOneAndUpdate` **não** rodam validação nem
  middleware de `save` (a menos de `runValidators: true`);
  `findOneAndUpdate` devolve o documento antigo sem `returnDocument:
  "after"`; query é *thenable*: `.then` duas vezes executa duas vezes;
  `bufferCommands` esconde conexão caída até o timeout.
- Spring Data: `@Transactional` exige `MongoTransactionManager`
  declarado (não é automático); `@DBRef` carrega por documento (N+1),
  preferir id + consulta; `MongoTemplate` com nome de campo vindo do
  usuário em `Criteria.where` é injeção; `_class` no documento.
- Change stream: resume token persistido, `fullDocument` quando precisa
  do documento, handler idempotente (evento pode repetir).
- Um `MongoClient` por processo (pool), nunca por requisição;
  `maxPoolSize`, `serverSelectionTimeoutMS` e `socketTimeoutMS`
  configurados; `retryWrites` ligado exige handler idempotente.
- Data em UTC; `$dateToString`/`$dateTrunc` com `timezone` quando o dia
  civil importa.

## Dados e segurança

- Autenticação ligada; usuário da app com `readWrite` no banco
  (`authSource` certo), não `root`, `dbAdmin` nem `clusterAdmin`; TLS na
  connection string (`tls=true`); Atlas com allowlist de IP ou private
  endpoint.
- Connection string (`mongodb+srv://user:senha@`) no `.env`, nunca no
  código nem no log de startup.
- Senha, token e PII com `select: false`/projeção e `toJSON` que remove;
  Client-Side Field Level Encryption ou Queryable Encryption quando o
  projeto adota para campo regulado.
- Migration (`migrate-mongo`, Mongock, script próprio): versionada,
  idempotente, em lotes com `bulkWrite` e retomável; não roda no startup
  de app com várias instâncias sem lock. `drop`, `deleteMany({})` e
  `renameCollection` exigem backup e justificativa.
- Exclusão de usuário (LGPD/GDPR) alcança as cópias desnormalizadas.
- Profiler ou log de query em produção com documento inteiro; log da app
  com documento contendo PII.
- Oplog dimensionado quando o PR adiciona change stream ou consumidor
  lento (resume token fora do oplog não retoma).

## Testes

- Teste contra MongoDB de verdade (Testcontainers ou
  `mongodb-memory-server`), não driver mockado; **replica set**
  (`MongoMemoryReplSet`) quando o código usa transação ou change stream,
  porque standalone não os suporta e o teste passa por não rodar.
- Índice de que a query depende é criado no teste (ou a migration
  roda) e conferido com `listIndexes`; sem isso, o teste passa em
  `COLLSCAN`.
- Pipeline de aggregation com lógica tem teste com documentos de
  fixture, incluindo documento sem o campo novo e com schema antigo.
- Script de migration testado contra documento na forma antiga.
- Validador `$jsonSchema` testado: documento inválido é rejeitado.
- Mongoose: validação e hooks testados no caminho que os dispara (`save`
  vs `updateOne`); `strictQuery` conferido quando o filtro vem de fora.
- Contador ou saldo com `$inc`/versão otimista tem teste concorrente
  quando o PR o toca.
- Correção de bug vem com teste que falha sem o fix. Nenhum teste sem
  asserção.
