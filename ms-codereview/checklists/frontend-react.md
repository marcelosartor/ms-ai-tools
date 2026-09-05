# Checklist — frontend React / Vite / Tailwind / shadcn

Aplicar apenas ao que o diff efetivamente toca. Assume React 18+ com
componentes de função; onde a lib (TanStack Query, react-hook-form, zod)
importa, o item diz "se o projeto usa".

## Hooks e estado

- Lista renderizada com `key` estável vinda do dado, nunca o índice
- Array de dependências de `useEffect`/`useMemo`/`useCallback` completo;
  `eslint-disable react-hooks/exhaustive-deps` só com o motivo ao lado
- `useEffect` que só copia prop ou estado para outro estado é estado
  derivado disfarçado: calcular direto no render ou em `useMemo`
- Estado não é mutado no lugar (`push`, atribuição em objeto): `setState`
  recebe cópia nova, senão o React não re-renderiza
- Hook não é chamado dentro de `if`, loop ou depois de `return` antecipado
- `useState` inicializado com cálculo caro usa a forma preguiçosa
  (`useState(() => ...)`)
- Contexto usado como store global de tudo: cada mudança re-renderiza todo
  consumidor. Estado de domínio compartilhado vai para a store do projeto
  ou para o cache de dados

## Efeitos e assincronia

- Efeito que cria listener, timer, subscription ou observer devolve cleanup
- Fetch em efeito trata resposta atrasada: `AbortController` ou flag
  `ignore` no cleanup — senão resposta antiga sobrescreve a nova e escreve
  em componente desmontado
- Strict Mode monta e desmonta duas vezes em dev: efeito precisa ser
  idempotente. Efeito que "só funciona em produção" é bug
- Se o projeto usa TanStack Query/SWR: mutação invalida ou atualiza a query
  afetada; fetch manual em `useEffect` ao lado do cache é duplicação

## Dados e formulários

- Chamada de API fora do componente: hook de dados ou camada de serviço
- Estado assíncrono trata os três caminhos: carregando, erro e vazio
- Formulário bloqueia submit duplo e desabilita o botão enquanto pende
- Se o projeto usa react-hook-form + zod: schema é a fonte da validação;
  validação duplicada à mão no `onSubmit` diverge com o tempo
- Loading não desmonta o formulário — perde o que o usuário digitou
- Erro de API vira mensagem útil, não silêncio nem stack trace

## shadcn/ui

- Componente em `components/ui/` é código copiado, não dependência:
  alteração ali muda a app inteira. Mudança "de passagem" num primitivo
  compartilhado para atender uma tela é achado; o certo é variante ou
  wrapper
- Variante nova entra pelo `cva` do componente, não por classe condicional
  espalhada nos usos
- Classes combinadas com `cn()`; concatenar string quebra o override do
  `tailwind-merge` e a classe do chamador perde
- Composição com Radix respeita a acessibilidade: `Dialog`/`Sheet` têm
  `Title` (ou `VisuallyHidden`), `asChild` quando o filho já é interativo,
  nada de `<button>` dentro de `<button>`
- `Form` do shadcn usa `FormField` + `FormMessage`: erro de validação chega
  ao usuário e ao leitor de tela

## Tailwind

- Classe montada por template string (`bg-${cor}-500`) não entra no bundle:
  o JIT não enxerga. Mapear para classes completas
- Cor, espaçamento ou fonte hardcoded onde existe token do tema (CSS var
  ou `tailwind.config`) — quebra dark mode e tema
- Componente compartilhado alterado foi conferido em dark mode e em
  viewport estreito, não só onde o autor testou
- `@apply` para criar "componente CSS" ao lado de um componente React que
  faz o mesmo é duplicação

## Vite e build

- `import.meta.env.VITE_*` vai para o bundle: segredo não entra no `.env`
  do front, nem com prefixo `VITE_`
- Rota ou tela pesada com `React.lazy` + `Suspense`; import estático de lib
  grande usada numa tela só puxa a lib para o bundle inicial
- Alias de import (`@/`) consistente entre `tsconfig` e `vite.config`
- Dependência nova: é necessária? é mantida? quanto adiciona ao bundle?

## Acessibilidade

- Elemento clicável que não é `<button>` ou `<a>` tem `role`, `tabIndex` e
  handler de teclado
- Imagem tem `alt`; input tem `<label>` associado ou `aria-label`
- Foco não some após ação: fechar modal devolve o foco para quem abriu
  (o Radix faz isso sozinho, a menos que o código tenha desligado)

## Segurança

- `dangerouslySetInnerHTML` só com conteúdo sanitizado
- `href`/`src` com valor vindo do usuário é validado (bloqueia `javascript:`)
- Regra de autorização não vive só no front: esconder botão não é controle
  de acesso; a rota da API tem a sua

## Performance

- Lista longa é paginada ou virtualizada
- `memo`/`useMemo`/`useCallback` só onde há re-render mensurável; memo
  indiscriminado é ruído. O inverso também é achado: componente `memo`
  recebendo função ou objeto literal novo a cada render não memoriza nada
- Objeto ou array literal como `value` de Provider recria a cada render e
  re-renderiza todo consumidor

## Testes

- Componente com regra visível tem teste (Testing Library) por
  comportamento e `role`, não por classe CSS ou detalhe de implementação
- Hook customizado com lógica tem teste próprio
- Correção de bug vem com teste que falharia sem o fix
- Nenhum teste sem asserção
