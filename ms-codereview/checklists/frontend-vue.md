# Checklist — frontend Vue / Quasar / Vuetify

Aplicar apenas ao que o diff efetivamente toca. Vale para Vue 2 e Vue 3;
onde a API difere, a diferença está anotada.

## Reatividade

- `v-for` com `:key` estável vindo do dado, nunca o índice do array
- Prop não é mutada diretamente; alteração sai por evento ou `v-model`
- `computed` em vez de `watch` quando não há efeito colateral real
- Vue 3: `reactive` não é destruturado — quebra a reatividade. Usar `toRefs`
  ou preferir `ref`
- Vue 3: `ref` acessado com `.value` no script, sem `.value` no template

## Ciclo de vida

- Listener, `setInterval`, subscription e observer criados no mount têm
  limpeza no unmount (`onUnmounted` no Vue 3, `beforeDestroy` no Vue 2)
- Chamada assíncrona que resolve depois do componente desmontar não tenta
  escrever em estado morto

## Estrutura

- Chamada de API fora do componente, em camada de serviço
- Componente acima de ~300 linhas deveria ser quebrado
- Lógica reaproveitável em composable (Vue 3) ou mixin/composable (Vue 2),
  não duplicada entre componentes
- Store guarda estado de domínio compartilhado, não estado local de tela

## Experiência e robustez

- Estado assíncrono trata os três caminhos: carregando, erro e vazio
- Formulário tem validação e bloqueia submit duplo
- Erro de API vira mensagem útil ao usuário, não silêncio nem stack trace
- Texto visível passa pelo i18n, sem string hardcoded na view

## Segurança

- Nada de `v-html` com conteúdo vindo do usuário ou da API sem sanitização
- Token, chave ou segredo não aparecem em código de front nem em `.env`
  exposto no bundle
- Regra de autorização não vive só no front: esconder botão não é controle
  de acesso

## Performance

- Lista longa é paginada ou virtualizada
- Watcher com `deep: true` em objeto grande tem justificativa
- Import pesado é lazy quando a rota permite
