# Checklist — SQL Server

Aplicar apenas ao que o diff efetivamente toca.

Base: SQL Server 2022 e Azure SQL; item que depende de edição
(Enterprise, Standard, Azure) diz qual. Cliente típico: `mssql` (Node),
`mssql-jdbc` (Java), EF Core quando aparecer.

## Migration e DDL

- Script de migration roda com `SET XACT_ABORT ON`: sem isso, erro no
  meio do batch deixa a transação aberta e metade aplicada. DDL é
  transacional no SQL Server; a migration inteira vai numa transação,
  exceto o que não pode (`CREATE DATABASE`, full-text, `ALTER DATABASE`).
- Separador `GO` é do cliente, não do T-SQL: a ferramenta de migration
  precisa entendê-lo (Flyway e DbUp entendem; `mssql` do Node não).
  Script com `GO` executado por driver quebra com erro de sintaxe.
- `ADD COLUMN ... NOT NULL` em tabela populada exige `DEFAULT`; com
  `DEFAULT` constante é só metadado no Enterprise e no Azure SQL, mas
  reescreve a tabela no Standard.
- `ALTER COLUMN` (tipo, tamanho, nulabilidade) reescreve e bloqueia, e
  falha se a coluna está em índice, constraint ou estatística: derrubar
  e recriar dependências no script, não descobrir em produção.
- `sp_rename` de coluna ou tabela não atualiza view, procedure, função ou
  trigger que a citam: quebram na próxima execução. `sp_refreshsqlmodule`
  em cada dependente, ou expand/contract.
- Índice em tabela grande: `WITH (ONLINE = ON)` só no Enterprise e no
  Azure; no Standard bloqueia a tabela o build inteiro. `RESUMABLE = ON`
  (2017+ para rebuild, 2019+ para create) para índice que demora horas.
- `UPDATE`/`DELETE` em massa numa instrução escala para lock de tabela
  (~5000 locks): lotes com `TOP (n)` em loop, `WAITFOR DELAY` entre eles
  quando a tabela é quente.
- FK ou `CHECK` em tabela populada com `WITH NOCHECK` é rápido mas deixa
  a constraint *untrusted*: o otimizador a ignora. Depois,
  `WITH CHECK CHECK CONSTRAINT`, ou aceitar e dizer.
- `DROP COLUMN` é metadado; o espaço só volta com `ALTER INDEX ... REBUILD`.
- Procedure, função e view com `CREATE OR ALTER` (2016 SP1+): migration
  idempotente. `DROP` + `CREATE` perde permissão concedida no objeto.
- Objeto criado sem schema explícito vai para o schema padrão do login,
  que pode não ser `dbo`. Sempre `dbo.` (ou o schema do projeto).
- Coluna nova com collation diferente da do banco gera *collation
  conflict* em `JOIN`; e a sensibilidade a maiúsculas (`_CI_`/`_CS_`)
  da collation é o que decide se `'a' = 'A'`. Código que assume um
  comportamento sem conferir a collation é achado.
- Tabela temporal (`SYSTEM_VERSIONING`) quando o requisito é histórico ou
  auditoria; trigger de auditoria à mão para isso é sugestão.
- `DROP`, `TRUNCATE`, `DELETE` sem `WHERE` exigem justificativa e plano
  de restore. `TRUNCATE` é minimamente logado: não há restore de linha,
  só de ponto no tempo.

## Schema e integridade

- Toda tabela tem índice clusterizado; heap é achado. Chave clusterizada
  estreita, crescente e única: `BIGINT IDENTITY` ou `NEWSEQUENTIALID()`.
  `UNIQUEIDENTIFIER` com `NEWID()` como clusterizada fragmenta a cada
  insert; uuid aleatório fica como chave alternativa não clusterizada.
- Texto em `NVARCHAR`, literal com `N'...'`: `VARCHAR` transforma caractere
  fora da collation em `?`, sem erro. `NVARCHAR(MAX)` só quando
  ultrapassa 4000: não indexa e vai para fora da página.
- `VARCHAR` sem tamanho é `VARCHAR(1)` na declaração e `VARCHAR(30)` no
  `CAST`: truncamento silencioso.
- Data em `DATETIME2`, não `DATETIME` (precisão de 3 ms, mínimo 1753).
  Não há equivalente a `timestamptz`: `DATETIMEOFFSET` quando o fuso
  importa, ou `DATETIME2` em UTC com a convenção escrita.
- Dinheiro em `DECIMAL(p, s)` com escala definida; `MONEY` arredonda em
  divisão, `FLOAT` nunca. Booleano em `BIT`.
- `UNIQUE` aceita só **um** `NULL` (diferente do Postgres): coluna
  opcional única precisa de índice filtrado `WHERE col IS NOT NULL`.
- Índice filtrado (`WHERE status = 'ativo'`) no lugar do índice completo
  para filtro fixo; a query só o usa se o predicado for literal igual,
  não parâmetro (senão `OPTION (RECOMPILE)`).
- `INCLUDE` para cobrir a query e evitar *Key Lookup*; índice composto
  na ordem em que a query filtra e ordena.
- `IDENTITY` tem buraco depois de rollback e de restart: nada assume
  sequência contígua. `SCOPE_IDENTITY()` ou `OUTPUT INSERTED.id`, nunca
  `@@IDENTITY` (pega o id de trigger).
- FK com `ON DELETE` pensado; SQL Server proíbe mais de um caminho de
  cascade para a mesma tabela: o modelo precisa saber disso antes.
- Coluna computada que a query filtra é `PERSISTED` e indexada.
- `TEXT`, `NTEXT`, `IMAGE` são deprecated: `NVARCHAR(MAX)`,
  `VARBINARY(MAX)`.
- Constraint no banco, não só na app; JSON em `NVARCHAR(MAX)` filtrado
  por `JSON_VALUE` sem coluna computada indexada é scan.

## Queries

- Parâmetro sempre: `sp_executesql` com `@param`, `request.input()` no
  `mssql` do Node com tipo explícito, `PreparedStatement` no JDBC.
  `EXEC(@sql)` com concatenação e EF `FromSqlRaw` com interpolação são
  `blocker:`.
- Conversão implícita mata o índice: `NVARCHAR` comparado a `VARCHAR`, ou
  `INT` a string. Driver Java manda string como `NVARCHAR` por padrão
  (`sendStringParametersAsUnicode=true`): coluna `VARCHAR` indexada vira
  scan. Tipo do parâmetro igual ao da coluna.
- `WITH (NOLOCK)`/`READ UNCOMMITTED` como "otimização" lê linha suja,
  duplicada ou pulada. Leitura sem bloqueio é `READ_COMMITTED_SNAPSHOT
  ON` no banco (RCSI), decisão de projeto; `NOLOCK` novo é achado.
- Isolamento padrão é `READ COMMITTED` com lock: leitor bloqueia
  escritor e vice-versa sem RCSI. Transação longa segura lock e monta
  fila. Deadlock (erro 1205) é esperado sob carga: quem chama tem retry.
- `TRY/CATCH` com `XACT_STATE()` antes do `ROLLBACK`; `@@TRANCOUNT` não é
  transação aninhada: `ROLLBACK` interno desfaz tudo. Savepoint quando
  precisa de rollback parcial.
- `MERGE` tem histórico de bug e condição de corrida sem `HOLDLOCK`;
  upsert seguro é `UPDATE ... ; IF @@ROWCOUNT = 0 INSERT` na mesma
  transação com `WITH (UPDLOCK, HOLDLOCK)` no `SELECT`/`UPDATE`, ou
  `MERGE WITH (HOLDLOCK)` com o motivo.
- Read-modify-write concorrente: `UPDATE ... SET x = x + 1 OUTPUT
  INSERTED.x`, ou `SELECT ... WITH (UPDLOCK, ROWLOCK)` dentro da
  transação. Ler, calcular na app e gravar perde update.
- `OFFSET ... FETCH` exige `ORDER BY` determinístico (desempate por
  chave); sem isso página repete e pula linha. Página funda lê e
  descarta tudo antes: keyset por chave.
- `TOP (n)` sem `ORDER BY` devolve qualquer coisa.
- Parameter sniffing: procedure cujo parâmetro varia muito de
  seletividade fica com o plano da primeira execução. `OPTION (RECOMPILE)`
  ou `OPTIMIZE FOR` com o motivo escrito.
- Variável de tabela tem estimativa de 1 linha: com muitas linhas o plano
  sai errado; `#temp` tem estatística.
- Cursor ou `WHILE` linha a linha onde uma instrução baseada em conjunto
  resolve.
- Trigger dispara por **instrução**, não por linha: `INSERTED`/`DELETED`
  são conjuntos. `SELECT @id = id FROM inserted` só vê uma linha e
  ignora o resto.
- Procedure com `SET NOCOUNT ON`; erro com `THROW` (50000+), não
  `RAISERROR` novo; procedure que falha sem `XACT_ABORT` deixa transação
  aberta no cliente.
- Data: `SYSUTCDATETIME()`/`GETUTCDATE()`, não `GETDATE()` (hora do
  servidor). Literal ISO 8601 `'2026-09-05T10:00:00'`; `'05/09/2026'`
  depende de `SET LANGUAGE`. Comparação de intervalo com `>= início AND
  < fim`, não `BETWEEN` em datetime.
- `LIKE '%termo%'` é scan; full-text (`CONTAINS`) ou coluna de busca.
- `SELECT *` em código de app; `COUNT(*)` numa tabela grande a cada
  requisição (`sys.dm_db_partition_stats` para aproximado).
- Query nova em tabela grande com plano de execução real conferido
  (`SET STATISTICS IO ON`): *Scan* onde se esperava *Seek*, *Key Lookup*
  em muitas linhas, *Sort* sem índice.
- Multi-tenant: filtro pelo tenant em toda query, ou Row-Level Security
  (`CREATE SECURITY POLICY` com função de predicado) cobrindo a tabela
  nova.
- Hint de query (`FORCESEEK`, `INDEX(...)`, `MAXDOP`) tem justificativa
  e data para rever.

## Dados e segurança

- Login da app não é `sysadmin` nem `db_owner`; permissão por schema ou
  `EXECUTE` em procedure (ownership chaining), mínimo necessário.
- Connection string: `Encrypt=True` e `TrustServerCertificate=False`
  (drivers desde 2022 criptografam por padrão; `TrustServerCertificate=True`
  em produção desliga a validação e é achado). Autenticação integrada ou
  Entra ID onde existe; senha no `.env`, nunca no código.
- `xp_cmdshell`, `OPENROWSET`, linked server ou `sp_send_dbmail` chamados
  a partir de código de app.
- Dado sensível: Always Encrypted ou Dynamic Data Masking quando o
  projeto adota; masking não é controle de acesso, só apresentação.
- Coluna sensível (documento, e-mail, token) não vai para log nem para
  resposta sem necessidade; log de query com parâmetro em produção.
- Migration de dados irreversível tem backup e ponto de restore; job do
  SQL Agent alterado no PR aparece no diff e é revisado como código.
- Auditoria (`SERVER AUDIT`/tabela temporal) para tabela com requisito
  de rastreabilidade, não trigger que grava em tabela solta.

## Testes

- Migration testada nos dois sentidos contra SQL Server de verdade
  (Testcontainers `mcr.microsoft.com/mssql/server` ou Azure SQL Edge);
  H2 ou SQLite "em modo SQL Server" não têm o mesmo dialeto.
- Query com lógica (janela, `MERGE`, CTE recursiva, `PIVOT`) tem teste
  com dados reais, não mock do ORM.
- Procedure, função e trigger nova têm teste (tSQLt quando o projeto
  adota; senão teste de integração pela app).
- Teste com collation igual à de produção quando o banco é `_CS_`: em
  `_CI_` o teste passa e produção não acha o registro.
- Caminho de deadlock tem retry testado quando o PR toca escrita
  concorrente.
