# Checklist — backend Node / NestJS

Aplicar apenas ao que o diff efetivamente toca.

## Camadas

- Controller sem regra de negócio: recebe DTO, chama service, devolve resposta
- Service sem conhecimento de HTTP: nada de `Request`, `Response`, headers
- Query de banco fora do controller

## Contrato e validação

- Toda entrada de rota tem DTO com validação; sem `@Body() body: any`
- Entidade do ORM não vai direto na resposta HTTP — vaza coluna nova sem
  querer, incluindo campos sensíveis
- Rota nova está autenticada, salvo marcação explícita de rota pública
- Autorização verificada, não só autenticação: o usuário autenticado pode
  agir sobre *aquele* recurso?

## Banco de dados

- Escrita que atinge mais de uma tabela roda dentro de transação
- Nenhuma query dentro de `for`, `map` ou `forEach` (N+1)
- Coluna nova usada em `WHERE`, `JOIN` ou `ORDER BY` tem índice na migration
- Migration tem `down()` implementado
- Migration destrutiva (drop de coluna, `NOT NULL` em tabela populada) vai
  em duas etapas, em releases separados
- Query em tabela multi-tenant filtra pelo tenant do chamador
- Paginação em endpoint que devolve lista de tamanho não limitado

## Erros e assincronia

- Nenhum `catch` engole a exceção sem tratar nem relançar
- Exceção específica em vez de `throw new Error()` genérico em camada que
  vira 500
- Mensagem ao cliente não expõe SQL, stack trace ou path de arquivo
- Todo `Promise` é aguardado ou tem `.catch()` explícito
- `forEach` com callback `async` não espera nada — deve ser `for...of` ou
  `Promise.all`
- Job, listener ou consumer que pode falhar tem retry ou dead-letter

## Segurança e configuração

- Nenhum segredo, token, chave ou connection string no diff
- Nada de `process.env` espalhado; configuração centralizada e validada
- Log não inclui senha, token, e-mail, CPF, documento ou body de request
- Entrada do usuário não é concatenada em query, comando ou path
- Dependência nova: é necessária? é mantida? o que ela puxa junto?

## Testes

- Regra de negócio nova ou corrigida vem com teste
- Correção de bug vem com teste que falharia sem o fix
- Nenhum teste sem asserção
- Rota nova tem teste cobrindo caminho feliz e ao menos um erro esperado
