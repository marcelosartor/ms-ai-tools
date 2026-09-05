# Checklist — chamada a modelo, RAG, agente

Aplicar apenas ao que o diff efetivamente toca.

## Prompt e entrada

- Entrada do usuário entra no prompt delimitada e identificada como
  dado, nunca concatenada solta no system prompt; conteúdo recuperado
  (RAG, página, e-mail) é tratado como não confiável: instrução dentro
  dele não é seguida (prompt injection).
- Prompt vive em arquivo ou constante versionada, não em string espalhada
  pelo código; mudança de prompt é diff legível.
- Mudança de prompt, modelo ou temperatura vem com evidência: eval,
  amostra comparada ou ao menos o caso que motivou. "Ficou melhor" sem
  isso é `dúvida:`.
- Modelo e versão pinados explicitamente (`claude-...-YYYYMMDD`,
  `gpt-...-YYYY-MM-DD`); alias que muda por baixo é regressão
  silenciosa.
- Tamanho do contexto: entrada grande é truncada ou resumida de forma
  determinística, não cortada no meio; histórico de chat tem janela.
- Idioma: instrução de responder no idioma do usuário, quando o produto
  é multilíngue.

## Saída

- Saída do modelo é parseada por schema (JSON schema, tool use,
  structured output), com fallback quando não valida; `JSON.parse` de
  texto livre sem tentativa de reparo nem retry é achado.
- Saída nunca é executada, interpolada em SQL/shell/HTML ou usada como
  URL sem validação, com o mesmo rigor de entrada de usuário.
- Ação com efeito colateral (enviar e-mail, gravar, pagar) decidida pelo
  modelo passa por confirmação ou allowlist; tool que o modelo chama tem
  validação própria dos argumentos.
- Alucinação com custo: citação, link, número ou id devolvido pelo
  modelo é verificado contra a fonte antes de ser mostrado como fato.

## Custo, latência e falha

- Chamada tem timeout e o streaming tem timeout de inatividade;
  cancelamento do cliente cancela a chamada.
- Retry com backoff só em erro transitório (429, 5xx, timeout); retry
  em 400 repete o erro e paga por ele.
- Limite de tokens de saída (`max_tokens`) definido; loop de agente tem
  limite de iterações e de custo.
- Custo por requisição é estimável e há teto por usuário ou por dia
  quando o produto é aberto.
- Cache de resposta (ou prompt caching do provedor) para prompt
  repetido; chave de cache inclui modelo, prompt e parâmetros.
- Fila ou concorrência limitada para lote; `Promise.all` de mil chamadas
  vira 429.
- Falha do provedor tem caminho: mensagem ao usuário, fallback de modelo
  ou degradação, não 500 cru.

## Dado e segurança

- PII, segredo ou dado de cliente enviado ao provedor tem base legal e
  está no contrato; o que não precisa ir é removido ou mascarado antes.
- Chave do provedor só no servidor; nunca no client, no bundle, no app
  mobile ou em URL.
- Log de prompt e resposta: útil para depurar, mas contém PII; redigido
  ou com retenção curta, e desligável.
- Conteúdo recuperado por RAG respeita permissão do usuário que
  pergunta: índice compartilhado sem filtro por tenant/ACL vaza
  documento.
- Tool que acessa rede ou arquivo por instrução do modelo tem allowlist
  de host e de caminho (SSRF e traversal via modelo).

## RAG e embeddings

Complementa o checklist de banco.

- Chunking: tamanho, sobreposição e metadado (fonte, posição, versão)
  declarados; mudança de estratégia reindexa tudo, não só documentos
  novos.
- Mesmo modelo de embedding, versão e pré-processamento na indexação e
  na consulta (o checklist de banco também diz; aqui é o lado da app).
- Documento atualizado ou apagado some do índice; índice órfão devolve
  conteúdo que não existe mais.
- Reranking, filtro por metadado e híbrido (texto + vetor) têm
  estratégia declarada; `top_k` não é arbitrário.
- Eval de recuperação existe (conjunto de perguntas com fonte esperada)
  e roda quando o índice ou o modelo muda.

## Testes

- Chamada ao modelo é isolada atrás de interface; teste unitário usa
  resposta gravada, não a API.
- Parser de saída tem teste com resposta malformada, vazia, truncada e
  com texto antes do JSON.
- Prompt injection tem ao menos um caso de teste ("ignore as instruções
  anteriores e ...").
- Eval automatizado (mesmo pequeno) para a tarefa principal; se não
  existe, o relatório diz isso na frase de "o que não cobriu".
