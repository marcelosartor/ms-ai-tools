# Checklist — PostgreSQL / pgvector

Aplicar apenas ao que o diff efetivamente toca: migration, schema, query
em código de app ou SQL solto. Carregar também quando o diff mexe em
embedding, busca semântica ou chunking, mesmo sem tocar em `.sql`.

## Migration

- Tem `down()` — ou diz explicitamente por que não é reversível
- `ADD COLUMN ... NOT NULL` sem `DEFAULT` em tabela populada falha; em
  tabela grande, `DEFAULT` volátil reescreve a tabela inteira. Caminho:
  adicionar nula, backfill em lotes, depois `SET NOT NULL`
- Índice em tabela grande é `CREATE INDEX CONCURRENTLY` — e portanto fora
  de transação; a ferramenta de migration precisa suportar isso
- Rename de coluna ou tabela quebra a versão em produção durante o deploy:
  expand/contract em releases separados
- Migration não mistura DDL com backfill pesado na mesma transação: o lock
  dura o backfill inteiro
- `ALTER TYPE ... ADD VALUE` em enum tem restrições transacionais; enum que
  cresce com frequência era para ser tabela de lookup ou `text` + `CHECK`
- `DROP`, `TRUNCATE`, `DELETE` sem `WHERE` em migration são achados que
  exigem justificativa explícita e plano de backup
- DDL em tabela quente sem `SET lock_timeout` enfileira toda requisição
  atrás do lock enquanto espera; `lock_timeout` curto e retry
- FK ou `CHECK` em tabela populada: `ADD CONSTRAINT ... NOT VALID` e
  depois `VALIDATE CONSTRAINT`, que não bloqueia escrita
- `CREATE INDEX CONCURRENTLY` que falha deixa índice `INVALID`; a
  migration confere ou dropa antes de recriar
- Migration gerada por Prisma/Drizzle/TypeORM e editada à mão diverge do
  schema declarado: `prisma migrate diff`/`drizzle-kit check` limpos
- Migration que semeia dado é idempotente (`ON CONFLICT DO NOTHING`)
- Flyway/Liquibase: migration já aplicada nunca é editada (checksum);
  versão nova, mesmo para corrigir

## Schema e integridade

- Constraint (`UNIQUE`, `CHECK`, `NOT NULL`, FK) no banco, não só na
  validação da app — a app não é o único cliente do banco
- FK com `ON DELETE` explícito e pensado; sem FK vira órfão
- Tipo certo: `timestamptz` e não `timestamp`; `numeric` para dinheiro,
  nunca `float`; `uuid` nativo e não `varchar(36)`; `text` no lugar de
  `varchar(n)` com limite arbitrário
- Coluna nova usada em `WHERE`, `JOIN` ou `ORDER BY` tem índice; índice
  composto com as colunas na ordem em que a query filtra
- Filtro fixo repetido (`WHERE deleted_at IS NULL`, `WHERE status = 'ativo'`)
  pede índice parcial, menor e mais rápido que o completo
- Índice redundante (prefixo de outro) ou que nenhuma query usa é custo de
  escrita sem retorno
- JSONB: campo que a app filtra ou ordena sai para coluna própria ou ganha
  índice GIN; jsonb como "saco para tudo" é dívida que vira Seq Scan
- `UNIQUE` em tabela com soft-delete precisa ser índice parcial
  `WHERE deleted_at IS NULL`, senão registro apagado bloqueia recriar
- `serial` em tabela nova: `GENERATED ALWAYS AS IDENTITY`. UUID v4 como
  PK de tabela grande fragmenta o índice; v7 (ordenável) ou `bigint`
- Coluna `updated_at` sem trigger ou sem atualização pela app fica
  mentindo

## Queries

- Nenhuma query dentro de loop (N+1); `SELECT *` em código de app puxa
  coluna nova sem querer
- Entrada do usuário nunca é interpolada em SQL — inclusive em `raw()`,
  `query()` ou template string do ORM. Parâmetro sempre
- Paginação por keyset (`WHERE id > $last ORDER BY id LIMIT n`) em lista
  grande; `OFFSET` alto lê e descarta tudo antes
- `LIKE '%termo%'` em tabela grande não usa índice B-tree: `pg_trgm` ou
  full-text
- Query nova em tabela grande passou por `EXPLAIN (ANALYZE, BUFFERS)`;
  Seq Scan onde havia índice esperado é achado
- Escrita em mais de uma tabela roda em transação
- Read-modify-write concorrente (saldo, estoque, contador) usa
  `SELECT ... FOR UPDATE`, `UPDATE ... RETURNING` ou expressão atômica;
  ler, calcular na app e gravar perde update
- Upsert com `INSERT ... ON CONFLICT`, não `SELECT` seguido de `INSERT`
- Multi-tenant: toda query filtra pelo tenant do chamador — ou RLS está
  ligado e a policy cobre a tabela nova
- Comparação de data respeita fuso: `timestamptz` com `AT TIME ZONE` onde
  o dia civil importa
- Atrás de PgBouncer em modo `transaction`, `SET` de sessão (inclusive
  `ef_search`, `search_path`, `statement_timeout`) não gruda: `SET LOCAL`
  dentro da transação. Prepared statement nomeado também não
- `statement_timeout` para query de usuário; sem ele, uma query ruim
  segura a conexão

## pgvector

- Dimensão declarada na coluna (`vector(1536)`) e igual à do modelo de
  embedding em uso. Trocar de modelo é coluna nova e reindexação, não
  `UPDATE` in place misturando vetores de modelos diferentes
- Operador bate com o índice e com a normalização: `<=>` cosseno,
  `<->` L2, `<#>` produto interno negativo. Índice com
  `vector_cosine_ops` não serve para query com `<->`
- Índice existe: sem ele toda busca é scan completo. HNSW é o padrão
  (melhor recall, build mais lento, mais memória); IVFFlat exige dados
  para treinar `lists` — criado em tabela vazia produz índice inútil
- Busca sempre com `ORDER BY <op> LIMIT n`; sem `LIMIT` não há ANN, há
  scan
- Busca com `WHERE` seletivo junto do `ORDER BY` vetorial pode devolver
  menos de `n` linhas (filtro pós-índice). Se o filtro é sempre o mesmo,
  índice parcial; se varia, conferir se `hnsw.iterative_scan` está
  disponível e ligado, ou aumentar `ef_search`
- Embedding gerado na app usa o mesmo modelo, versão e pré-processamento
  (limpeza, truncamento, prefixo de instrução) na indexação e na consulta
- Chunk guarda metadado para voltar à origem (documento, posição, versão)
  e some junto com o documento pai (`ON DELETE CASCADE`)
- Reprocessar embeddings roda em lotes com retomada, não num `UPDATE` só
- Vetor de 1536 floats pesa ~6 KB por linha: `halfvec` quando o recall
  permite; coluna vetorial fora da tabela consultada por outros caminhos
- Busca híbrida (vetor + texto + filtros) tem estratégia declarada — RRF,
  reranking, filtro antes/depois — e não dois passos improvisados
- `ef_search`/`probes` alterados por sessão, não em `postgresql.conf`
  global sem justificativa
- Dimensão acima de 2000 **não indexa** com `vector` (HNSW e IVFFlat):
  `text-embedding-3-large` (3072) exige `halfvec` (até 4000) ou redução
  de dimensão no modelo
- `maintenance_work_mem` cobre o build do índice HNSW; abaixo disso o
  build cai para disco e demora horas. `m` e `ef_construction` alterados
  têm justificativa
- `hnsw.ef_search` maior que o `LIMIT` da consulta; igual ou menor
  devolve menos que `n` com filtro

## Dados e segurança

- Migration de dados irreversível tem backup e roda em lotes com log de
  progresso
- Coluna sensível (documento, e-mail, token) não vai para log nem para
  resposta sem necessidade
- Nenhuma credencial de banco no diff; role da app não é superuser e tem
  o mínimo de permissão
- Função `SECURITY DEFINER` ou trigger nova tem revisão de quem pode
  chamar e do que executa

## Testes

- Migration testada nos dois sentidos
- Query com lógica (agregação, janela, CTE recursiva) tem teste com dados
  reais, não só mock do ORM
- Função SQL ou trigger nova tem teste
- Busca vetorial tem teste de recall com corpus conhecido — verifica a
  ordenação esperada, não só que "devolveu algo"
