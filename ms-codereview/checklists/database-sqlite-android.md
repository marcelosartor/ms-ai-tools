# Checklist — SQLite no Android (Room)

Aplicar apenas ao que o diff efetivamente toca.

Base: Room 2.7+ com `androidx.sqlite`, Kotlin. A versão do SQLite é a
do sistema (API 21 ≈ 3.8, API 30 ≈ 3.28, API 34 ≈ 3.39), salvo quando
o projeto usa `sqlite-bundled`, que traz uma versão fixa. Item que
depende de recurso do motor diz a versão e a API em que entrou.

## Versão do motor

- Recurso de SQL usado existe no SQLite do `minSdk`: `UPSERT` e
  `RENAME COLUMN` (3.24/3.25, API 30), window functions (3.25, API 30),
  `RETURNING` e `DROP COLUMN` (3.35, API 34), `STRICT` (3.37), funções
  `json_*` (varia, não contar). Ou o projeto usa `sqlite-bundled` e o
  item diz isso.
- Limite de variáveis por instrução: 999 até 3.32 (API 31): `IN (:ids)`
  com lista grande falha; fatiar a lista.
- Robolectric roda outro SQLite (mais novo) que o dispositivo: teste que
  passa no Robolectric com função nova precisa de teste instrumentado no
  emulador do `minSdk`.

## Migration

- Toda mudança de schema sobe `version` e tem `Migration(from, to)` ou
  `@AutoMigration` (com `AutoMigrationSpec` para rename e delete).
  `fallbackToDestructiveMigration()` apaga o banco do usuário: é
  `blocker:` fora de build de dev.
- `exportSchema = true` com o diretório de schemas versionado; o diff do
  JSON exportado é a mudança real e é lido na revisão.
- Cadeia de migrations cobre toda versão já publicada até a atual: o
  usuário pula versões e o Room encadeia; buraco na cadeia cai no
  destrutivo.
- `ALTER TABLE` do SQLite só faz `ADD COLUMN` (com `NOT NULL` exige
  `DEFAULT` constante), `RENAME`, e `DROP COLUMN` a partir do 3.35. O
  resto é recriar: `CREATE TABLE _new`, `INSERT INTO _new SELECT`,
  `DROP TABLE`, `ALTER TABLE _new RENAME`, recriar índices, tudo dentro
  da mesma transação (o Room já a abre; não abrir outra).
- Tipo e nulabilidade no SQL da migration batem **exatamente** com o que
  a entidade declara (`INTEGER NOT NULL` vs `INTEGER`, `TEXT` vs
  `TEXT NOT NULL DEFAULT ''`): divergência dá "Migration didn't properly
  handle" em runtime, só pega com teste de migration.
- Índice criado na migration com o nome que o Room gera
  (`index_<tabela>_<coluna>`), senão o Room o vê como faltando.
- `PRAGMA foreign_keys` está desligado dentro da migration (não muda
  dentro de transação): recriar tabela com FK não valida órfão; limpar
  antes ou validar depois com `PRAGMA foreign_key_check`.
- Migration de dados (transformar valor) usa `execSQL`/`query` no
  `SupportSQLiteDatabase`, em lotes se a tabela for grande, e nunca a
  classe de entidade (que reflete o schema atual, não o antigo).
- Migration pesada roda na primeira abertura, na thread de quem abriu:
  primeira query fora da main thread, e o app mostra estado de
  "atualizando" se demora.
- `createFromAsset`/`createFromFile` com banco pré-populado: a versão do
  asset acompanha `version` e o asset não é editado sem migration.

## Schema e integridade

- `@PrimaryKey(autoGenerate = true)` em `Long` vira alias do `rowid`;
  `Int` trunca acima de 2^31. Chave `String` (uuid) funciona, com índice
  maior; `WITHOUT ROWID` só com motivo.
- `@ForeignKey` com `onDelete` explícito e `@Index` na coluna filha (o
  Room avisa `MISSING_INDEX_ON_FOREIGN_KEY_CHILD`; o aviso é achado).
- `@Index(unique = true)` para chave de negócio; `@Ignore` em campo que
  não é coluna.
- SQLite não tem tipo de data, booleano nem decimal: booleano em
  `INTEGER` 0/1 (o Room faz), data em epoch millis `Long` com
  `TypeConverter` (texto só em ISO 8601 para ordenar), dinheiro em
  inteiro de centavos. `REAL` é double.
- Nulabilidade da coluna igual à do tipo Kotlin: coluna nula com tipo
  não-nulo crasha na leitura; o Room deriva `NOT NULL` do tipo.
- `COLLATE NOCASE` só dobra ASCII: `'É' = 'é'` é falso. Para texto de
  usuário, `COLLATE LOCALIZED`/`UNICODE` (só no Android) ou coluna
  normalizada.
- `@Embedded` com `prefix` quando dois objetos têm campo de mesmo nome;
  `@Relation` para um-para-muitos na leitura, sem exigir FK.
- Enum salvo pelo nome (`TEXT`), nunca `ordinal`.
- `@ColumnInfo(defaultValue)` é para a migration e para `INSERT` parcial;
  não substitui o default do Kotlin.
- SQLite aceita qualquer tipo em qualquer coluna (afinidade): `STRICT`
  (3.37+, `sqlite-bundled`) quando o projeto pode; senão validar na app.

## Queries e concorrência

- `@Query` é validada em compilação: aproveitar. `@RawQuery` com
  concatenação, `rawQuery("... $x")` ou `execSQL` com valor do usuário é
  injeção; `SimpleSQLiteQuery(sql, args)` e `selectionArgs`.
- Todo acesso fora da main thread: DAO `suspend` ou `Flow`;
  `allowMainThreadQueries()` só em teste.
- `Flow` de DAO re-emite a cada escrita em qualquer tabela da query
  (invalidation tracker): query pesada observada numa tela quente
  re-roda a cada insert. `distinctUntilChanged()`, query estreita, ou
  não observar.
- N+1: loop chamando DAO por item; `@Transaction` com `@Relation`, ou
  `JOIN` num POJO.
- Lista grande: `PagingSource` do Room; `LIMIT/OFFSET` funda lê e
  descarta; coluna do `ORDER BY` indexada.
- `LIKE '%x%'` é scan e só ignora caixa em ASCII: `@Fts4`/FTS5 para busca
  em texto.
- Inserção em massa numa transação só (`@Transaction` no DAO ou
  `withTransaction`); uma transação por linha faz `fsync` por linha e é
  100x mais lento.
- `OnConflictStrategy.REPLACE` apaga e reinsere: dispara `ON DELETE
  CASCADE` nas filhas e troca o `rowid`. Para atualizar, `@Upsert` (Room
  2.5+) ou `IGNORE` seguido de `@Update`.
- SQLite tem **um** escritor por vez. WAL (padrão do Room) deixa leitura
  concorrer com escrita, mas escrita longa bloqueia toda escrita:
  `SQLiteDatabaseLockedException`. Transação de escrita curta, sem
  chamada de rede dentro.
- Uma instância de `RoomDatabase` por processo (singleton no DI): duas
  instâncias no mesmo arquivo dão lock e invalidation desatualizada.
  Segundo processo (widget, `:service`) usa
  `enableMultiInstanceInvalidation()`.
- `EXPLAIN QUERY PLAN` para query nova em tabela grande: `SCAN` onde se
  esperava `SEARCH ... USING INDEX`.
- Data em `TEXT` comparada com formato diferente; fuso: gravar UTC e
  converter na exibição.
- `= NULL` nunca é verdadeiro; `IS NULL`. `IN (...)` com lista vazia é
  erro de sintaxe no Room, conferir antes.
- `COUNT(*)` observado em `Flow` em tabela grande custa a cada escrita.
- Fora do Room (`SQLiteOpenHelper`): `compileStatement` reutilizado em
  loop; `Cursor` fechado em `use {}`; `getColumnIndexOrThrow`.

## Dados e segurança

- Banco em armazenamento interno (`getDatabasePath`), nunca externo;
  arquivo compartilhado com outro app só via `ContentProvider`/`FileProvider`.
- `allowBackup`/`dataExtractionRules` excluem o banco quando ele guarda
  token, sessão ou dado sensível; senão o backup os leva (cross-ref
  `android-kotlin`).
- Dado sensível em repouso: SQLCipher (`sqlcipher-android`) com chave no
  Keystore, ou não guardar (token em `EncryptedFile`/Keystore, não em
  tabela). Dispositivo com root lê o arquivo.
- `ContentProvider` exportado sobre o banco: `selection` e `sortOrder`
  vindos de fora são injeção; `projectionMap` e `SQLiteQueryBuilder`
  com `setStrict(true)`.
- Log de query com valores em release.
- Apagar de verdade: `PRAGMA secure_delete` quando o dado apagado não
  pode ser recuperável; `VACUUM` depois de exclusão em massa (o arquivo
  não encolhe sozinho) e `VACUUM` precisa de 2x o espaço.
- Blob grande (imagem, PDF) em arquivo com o caminho na tabela, não em
  `BLOB`; arquivo WAL cresce depois de transação grande sem checkpoint.
- Corrupção: o `DefaultDatabaseErrorHandler` apaga e recria o banco;
  se o dado local é a única cópia, estratégia de sincronização ou
  handler próprio.
- Logout e troca de conta: `clearAllTables()` ou banco por usuário; dado
  do usuário anterior aparecendo para o próximo é vazamento.

## Testes

- Toda migration tem teste com `MigrationTestHelper`, partindo de cada
  versão publicada e validando o schema exportado
  (`validateMigration`).
- DAO com teste em banco em memória (`Room.inMemoryDatabaseBuilder`);
  `Flow` de DAO com Turbine, incluindo que a escrita emite.
- Estratégia de conflito testada quando o PR usa `REPLACE`/`@Upsert` em
  tabela com filhas.
- Escrita concorrente testada (duas coroutines) quando o PR toca o
  caminho que dá `LockedException`.
- Teste instrumentado no `minSdk` para função SQL nova (ver "Versão do
  motor").
- Correção de bug vem com teste que falha sem o fix. Nenhum teste sem
  asserção.
