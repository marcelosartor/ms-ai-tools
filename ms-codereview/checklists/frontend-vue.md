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
- Vue 3: destruturar `props` perde reatividade antes do 3.5 (com 3.5+ a
  destruturação reativa é suportada, mas `watch(prop)` precisa de getter)
- Vue 3: `watch` em objeto reativo precisa de getter (`() => obj.campo`)
  ou `deep: true`; `watch(obj.campo)` observa o valor uma vez
- `v-if` e `v-for` no mesmo elemento: precedência mudou entre Vue 2 e 3;
  separar em `<template>`
- `<component :is>` e `<KeepAlive>` sem `key` reaproveitam estado entre
  itens diferentes

## Ciclo de vida

- Listener, `setInterval`, subscription e observer criados no mount têm
  limpeza no unmount (`onUnmounted` no Vue 3, `beforeDestroy` no Vue 2)
- Chamada assíncrona que resolve depois do componente desmontar não tenta
  escrever em estado morto
- Mudança de parâmetro na **mesma** rota não remonta o componente:
  `watch(() => route.params.id)` ou `:key="route.fullPath"` no
  `<RouterView>`
- Navigation guard assíncrono retorna ou chama `next` exatamente uma
  vez; `beforeRouteLeave` quando há formulário com dado não salvo
- `<script setup>` com `await` de topo exige `<Suspense>` no pai

## Estrutura

- Chamada de API fora do componente, em camada de serviço
- Componente acima de ~300 linhas deveria ser quebrado
- Lógica reaproveitável em composable (Vue 3) ou mixin/composable (Vue 2),
  não duplicada entre componentes
- Store guarda estado de domínio compartilhado, não estado local de tela
- Pinia: destruturar store sem `storeToRefs` perde reatividade; mutar
  estado fora de action é padrão só se o projeto adotou
- `provide`/`inject` com chave tipada (`InjectionKey`), não string solta
- `defineEmits` e `defineProps` tipados; evento emitido sem estar
  declarado

## Experiência e robustez

- Estado assíncrono trata os três caminhos: carregando, erro e vazio
- Formulário tem validação e bloqueia submit duplo
- Erro de API vira mensagem útil ao usuário, não silêncio nem stack trace
- Texto visível passa pelo i18n, sem string hardcoded na view
- Formulário: `.number`/`.trim`/`.lazy` onde o dado exige; input
  numérico devolve string sem `.number`
- Quasar: `q-table` com dado server-side usa `@request` e
  `v-model:pagination`; regra de `QForm`/`QInput` devolve `true` ou
  string de erro, não booleano falso
- Vuetify: `v-data-table-server` com `@update:options`; `rules` com o
  mesmo contrato
- Cor, espaçamento e fonte pelo tema (`$q`, Quasar variables, Vuetify
  theme) e não hardcoded: quebra dark mode

## Segurança

- Nada de `v-html` com conteúdo vindo do usuário ou da API sem sanitização
- Token, chave ou segredo não aparecem em código de front nem em `.env`
  exposto no bundle
- Regra de autorização não vive só no front: esconder botão não é controle
  de acesso
- `href`/`src` com valor do usuário validado (bloqueia `javascript:`)
- `import.meta.env.VITE_*` vai para o bundle: nenhum segredo com esse
  prefixo
- Rota com `meta.requiresAuth` sem guard global que a aplique é rota
  aberta

## Acessibilidade

- Elemento clicável que não é `<button>`/`<a>` tem `role`, `tabindex` e
  handler de teclado
- Imagem tem `alt`; input tem `<label>` ou `aria-label`; Quasar/Vuetify
  já fazem isso quando o `label` é passado, e não quando é um
  `placeholder`
- Foco volta para quem abriu ao fechar `QDialog`/`v-dialog`; não desligar
  o `focus trap` sem motivo

## Testes

- Componente com regra visível tem teste (Vue Test Utils ou Testing
  Library) por comportamento e texto/role, não por classe CSS
- Assíncrono: `await flushPromises()`/`nextTick` antes de afirmar;
  afirmação sem esperar passa por acaso
- Composable com lógica tem teste próprio, sem montar componente
- Store Pinia em teste usa `createTestingPinia`; ação mockada não
  afirma efeito real
- Correção de bug vem com teste que falharia sem o fix. Nenhum teste
  sem asserção

## Performance

- Lista longa é paginada ou virtualizada
- Watcher com `deep: true` em objeto grande tem justificativa
- Import pesado é lazy quando a rota permite
- `shallowRef` para lista grande que só troca inteira; `v-memo` em item
  de lista pesado
- `computed` que devolve objeto novo a cada acesso não cacheia nada
