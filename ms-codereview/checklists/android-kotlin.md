# Checklist — Android nativo (Kotlin)

Aplicar apenas ao que o diff efetivamente toca. `## Comum` aplica sempre;
`## Compose`, `## Views (XML)`, `## Room` e `## Hilt` aplicam pela
variante que casou em `raw/checklists.json`
(`variants["android-kotlin"]`); sem `variants` para este checklist,
aplicar tudo. Base: Kotlin 2.x, AGP 8.x/9.x, compileSdk/targetSdk 36,
Compose BOM corrente, Hilt, Room, Retrofit/OkHttp, WorkManager.

## Comum

### Kotlin

- `!!` sem justificativa ao lado; `lateinit` lido onde pode não ter sido
  inicializado (`::x.isInitialized` é sintoma).
- Tipo de plataforma vindo de Java tratado como não-nulo sem checagem.
- `when` sobre `sealed`/`enum` sem `else`, exaustivo pelo compilador;
  `else` que esconde subtipo novo é achado.
- `data class` com `Array` em `equals`; `List` mutável exposta como
  estado (`MutableList` em `data class` de UI state).
- `object` ou `companion object` segurando `Context`, `Activity` ou
  `View`: leak. Só `applicationContext`, e ainda assim com motivo.
- `==` e `===` trocados; `String.format` com locale para número/data.
- Dinheiro em `Double`/`Float`: `BigDecimal` ou inteiro em centavos.

### Coroutines e Flow

- `GlobalScope` nunca; `viewModelScope`, `lifecycleScope` ou escopo
  injetado com `SupervisorJob`.
- `runBlocking` fora de teste ou `main` bloqueia a thread principal (ANR).
- Chamada bloqueante (I/O, banco, parse pesado) em `Dispatchers.IO` ou
  `Default`; `withContext(Dispatchers.Main)` desnecessário dentro de
  `viewModelScope`.
- `async` sem `await` engole a exceção até alguém chamar `await`; erro
  em `launch` sem `CoroutineExceptionHandler` derruba o escopo pai a
  menos que seja `SupervisorJob`.
- Loop longo em coroutine chama `ensureActive()`/`yield()`: cancelamento
  é cooperativo. Limpeza depois de cancelar roda em
  `withContext(NonCancellable)`.
- `Flow` coletado na UI com `repeatOnLifecycle(STARTED)` ou
  `collectAsStateWithLifecycle()`; `launchIn(lifecycleScope)` cru coleta
  em background e gasta bateria.
- `stateIn(scope, WhileSubscribed(5_000), inicial)` para expor
  `StateFlow` derivado; `Eagerly` sem motivo mantém upstream vivo.
- `MutableStateFlow` privado e `StateFlow` público; evento único (toast,
  navegação) por `Channel`/`receiveAsFlow`, não por `StateFlow` (repete
  na rotação) nem `SharedFlow(replay = 0)` (perde se ninguém coleta).
- `callbackFlow` fecha com `awaitClose { cancelar }`; sem isso o listener
  vaza.
- `catch` no `Flow` antes do `collect` e depois do operador que pode
  falhar; `catch` acima de `flowOn` não pega o que vem de baixo.
- `Dispatchers` injetados, não hardcoded, para teste com
  `StandardTestDispatcher`.

### Arquitetura e estado

- Lógica em `ViewModel` ou camada de domínio; Activity, Fragment e
  Composable só renderizam estado e encaminham evento (UDF: estado desce,
  evento sobe).
- `ViewModel` não referencia `Context`, `View`, `Activity`, `Fragment`
  nem `NavController`: leak e impossível de testar. `AndroidViewModel`
  só com motivo.
- Estado que precisa sobreviver a morte do processo vai para
  `SavedStateHandle` ou `rememberSaveable`; `ViewModel` sobrevive à
  rotação, não à morte do processo.
- Uma fonte da verdade por dado: repositório com cache (Room/DataStore)
  e a UI observando, não cópia em cada tela.
- Estado de tela como `sealed interface` ou `data class` imutável com
  `copy`; carregando, erro e vazio representados.
- Hilt: `@Inject constructor`, escopo coerente (`@Singleton` segurando
  `Activity` é leak; `@ActivityRetainedScoped` para o que acompanha o
  `ViewModel`); `@Provides` que cria cliente HTTP ou banco é singleton.
- Navegação: rota tipada (`@Serializable` com Navigation 2.8+) ou
  constante; argumento pequeno (id), não objeto inteiro; `popUpTo` com
  `inclusive` certo para não empilhar login/splash; deep link declarado
  no grafo e no manifesto.
- Módulo Gradle novo: dependência entre módulos sem ciclo; `api` vs
  `implementation` consciente.

### Ciclo de vida e plataforma

- Trabalho iniciado em `onStart`/`onResume` para em `onStop`/`onPause`;
  receiver, sensor, câmera e localização registrados e desregistrados
  em par.
- Nada pesado em `onCreate` (parse, I/O síncrono, inicialização de SDK
  que pode ser adiada): custa no cold start.
- `Activity` recriada na rotação e em mudança de config: dado guardado
  em campo de `Activity`/`Fragment` some; `configChanges` no manifesto
  para evitar isso é achado, salvo caso justificado.
- Permissão em runtime via `ActivityResultContracts.RequestPermission`,
  com rationale e caminho de negação; pedido antes da necessidade ou em
  lote no onboarding é achado de UX e de política.
- Permissão de mídia: Photo Picker em vez de `READ_MEDIA_*`;
  `POST_NOTIFICATIONS` (13+) pedida antes de notificar; foreground
  service com `foregroundServiceType` declarado (14+) e permissão
  correspondente.
- `<queries>` no manifesto para pacote ou intent que o app consulta
  (11+).
- Trabalho em background garantido vai para `WorkManager` (constraints,
  `UniqueWork`, retry com backoff); `Service` sem tipo de foreground é
  morto pelo sistema.
- Edge-to-edge é forçado em targetSdk 35+: `enableEdgeToEdge()`,
  `WindowInsets` consumidos (`safeDrawing`, `innerPadding` do
  `Scaffold`), contraste de status bar; conteúdo sob a barra é bug.
- Predictive back: `android:enableOnBackInvokedCallback="true"`,
  `BackHandler` no Compose ou `OnBackPressedCallback`; `onBackPressed()`
  sobrescrito é deprecated e quebra a animação.
- Página de 16 KB: lib nativa nova (`.so`) alinhada a 16 KB; obrigatório
  para novos apps e atualizações desde novembro de 2025.
- `targetSdk` atual conforme prazo do Play (36 para novo app e update a
  partir de agosto de 2026); bump de `targetSdk` vem com a lista de
  mudanças de comportamento conferida.
- Locale por app (`android:localeConfig`) quando o app tem tradução;
  string com número, plural ou gênero usa `plurals` e placeholders, não
  concatenação.

### Rede e dados

- OkHttp com `connectTimeout`/`readTimeout`/`callTimeout`; Retrofit com
  `suspend` e tratamento de `HttpException`/`IOException` separado
  (erro de servidor vs sem rede).
- Retry com backoff só em erro transitório; nunca em POST não
  idempotente.
- Offline: dado que o usuário precisa ver sem rede vem do Room/DataStore
  com sincronização; tela que só funciona online diz isso.
- Lista grande com Paging 3 (`PagingSource` + `LazyPagingItems`), não
  carga completa.
- Room: migration explícita para toda mudança de schema;
  `fallbackToDestructiveMigration()` é **perda de dado do usuário**, só
  em dev; `exportSchema = true` com o diretório versionado;
  `autoMigrations` para o simples.
- DAO com `suspend` ou `Flow`; query no main thread só com
  `allowMainThreadQueries` em teste. Relação carregada com
  `@Transaction`. Índice em coluna de FK e de filtro.
- `SharedPreferences` para dado novo é achado: `DataStore`.
  `EncryptedSharedPreferences` está deprecated; segredo no Android
  Keystore.
- Arquivo temporário no `cacheDir`; arquivo compartilhado com outro app
  via `FileProvider`, nunca `file://`.
- Serialização: `kotlinx.serialization` ou Moshi com classe `@Serializable`
  explícita; campo novo do backend é opcional com default ou o parse
  quebra o app antigo.
- Imagem com Coil/Glide com tamanho alvo, não bitmap cheio em memória.

### Segurança

- Todo componente com `intent-filter` tem `android:exported` explícito
  (obrigatório desde API 31); exportado sem necessidade é achado;
  exportado com necessidade valida o `Intent` recebido (extras, `data`).
- Intent recebido de fora e repassado a `startActivity` sem validar
  (intent redirection); `PendingIntent` com `FLAG_IMMUTABLE` salvo
  necessidade explícita de mutável.
- Deep link/App Link verificado (`autoVerify` + `assetlinks.json`);
  parâmetro de deep link validado como entrada de usuário.
- WebView: `javaScriptEnabled` só com necessidade; `addJavascriptInterface`
  expõe métodos a qualquer página carregada; `allowFileAccess`,
  `allowContentAccess` desligados; URL carregada de fora validada por
  host; `WebViewClient.shouldOverrideUrlLoading` para não navegar para
  fora.
- `usesCleartextTraffic="false"` (padrão desde 28) e
  `network_security_config` sem exceção ampla; pinning de certificado é
  decisão declarada, com plano de rotação.
- Segredo em `BuildConfig`, `strings.xml`, `local.properties` comitado
  ou `google-services.json` com chave sensível é extraível do APK:
  backend intermediário, ou ao menos chave restrita por pacote e SHA.
- `debuggable`, `allowBackup` e `dataExtractionRules` conscientes: backup
  de banco com token de sessão vaza.
- Log (`Log.d`, Timber) com PII ou token; em release, Timber sem
  `DebugTree` ou R8 removendo `Log.*`.
- Banco via Room, sem `rawQuery` com concatenação; `SupportSQLiteQuery`
  com argumentos.
- Tela com dado sensível (senha, cartão) com `FLAG_SECURE`; campo de
  senha com `inputType` correto e sem autofill indevido; clipboard limpo
  ou não usado para segredo.
- Biometria via `BiometricPrompt` com `CryptoObject` quando protege
  chave; só "passou na biometria" sem criptografia é bypassável.
- Chave criptográfica no Android Keystore, gerada no dispositivo, com
  `setUserAuthenticationRequired` quando faz sentido.
- Dependência nova: tamanho no APK, permissões que ela declara no
  manifesto mesclado (`merged manifest`), manutenção.

### Build e release

- Versões em `libs.versions.toml` (version catalog); número solto em
  `build.gradle.kts` é nit, exceto quando duplica o catálogo.
- Release com `isMinifyEnabled = true` e `isShrinkResources = true`;
  regra de `proguard-rules.pro`/`@Keep` para classe usada por reflexão
  ou serialização (Gson, Retrofit, Room já vêm com regras; modelo
  próprio serializado por reflexão precisa).
- `signingConfig` sem senha no repositório; keystore de release fora do
  VCS.
- `compileSdk` e `targetSdk` explícitos e atuais; `minSdk` declarado e
  API acima dele guardada por `Build.VERSION.SDK_INT` ou `@RequiresApi`.
- KSP no lugar de kapt para Room/Hilt/Moshi (kapt é legado e lento).
- `BuildConfig` só com o que varia por build type; flavor novo tem
  `applicationIdSuffix` e recursos coerentes.
- Baseline Profile atualizado quando tela de entrada muda; startup
  medido antes e depois quando o PR diz que melhora performance.
- Compose: `kotlinCompilerExtensionVersion` sai com Kotlin 2.x (plugin
  `org.jetbrains.kotlin.plugin.compose`); strong skipping é padrão desde
  o Compose 1.7/Kotlin 2.0.20.

### Acessibilidade e UX

- Toda imagem informativa tem `contentDescription`; decorativa tem
  `null` (Compose) ou `importantForAccessibility="no"`.
- Alvo de toque mínimo de 48 dp; texto em `sp`, nunca `dp`; layout
  sobrevive a fonte 200% e a tela estreita.
- Cor não é o único indicador de estado; contraste mínimo 4.5:1.
- Ordem de foco e `semantics` para leitor de tela em componente
  customizado; tela nova passou pelo TalkBack ao menos uma vez.
- Texto na tela vem de `strings.xml`; `start`/`end` em vez de
  `left`/`right` (RTL).
- Dark mode: cor pelo tema (`MaterialTheme`/`?attr`), não hardcoded;
  tela conferida nos dois modos.

### Testes

- `ViewModel` com teste unitário: `runTest`, `Dispatchers.setMain`
  (regra de `MainDispatcherRule`), dispatcher injetado; `Flow` com
  Turbine.
- Repositório testado com fake (implementação em memória), não com
  Mockito em tudo; mock que só ecoa o que o teste passou não prova nada.
- Room: teste com banco em memória; toda migration nova tem teste com
  `MigrationTestHelper`.
- Compose: teste de UI com `createComposeRule`, seletores por semântica
  (`onNodeWithText`, `testTag` com moderação), sem `Thread.sleep` (usar
  `waitUntil` ou idling).
- Robolectric para o que precisa de framework Android sem emulador; teste
  instrumentado só para o que depende de dispositivo.
- Screenshot test (Compose Preview Screenshot Testing) para componente
  visual compartilhado quando o projeto adota.
- Correção de bug vem com teste que falha sem o fix. Nenhum teste sem
  asserção.

## Compose

- Lista em `LazyColumn`/`LazyRow` com `key = { it.id }` estável e
  `contentType` quando há tipos misturados; sem `key`, remoção reanima
  tudo e estado de item vaza para o vizinho.
- `remember` para cálculo caro ou objeto que precisa manter identidade;
  `rememberSaveable` para entrada do usuário (sobrevive à rotação e à
  morte do processo).
- Nada de efeito colateral no corpo do composable (chamada de rede,
  analytics, navegação, `setState`): `LaunchedEffect(chave)` com a chave
  certa, `DisposableEffect` com `onDispose`, `SideEffect` para sincronizar
  com objeto não-Compose; `LaunchedEffect(Unit)` só para "uma vez por
  entrada na composição" e com essa intenção.
- Navegação disparada por evento (`LaunchedEffect` observando estado, ou
  callback de clique), nunca durante a composição.
- Estado elevado (state hoisting): composable de UI recebe estado e
  lambdas, não `ViewModel`; `ViewModel` só na raiz da tela
  (`hiltViewModel()`).
- `collectAsStateWithLifecycle()` em vez de `collectAsState()`.
- Leitura de estado que muda muito (scroll, animação) adiada para a fase
  de layout/draw (`Modifier.offset { }`, `graphicsLayer { }`) ou
  `derivedStateOf`; ler no corpo recompõe a árvore a cada frame.
- Parâmetro de composable estável: `data class` com `val` e coleção
  imutável (`kotlinx.collections.immutable` ou `@Immutable`); com strong
  skipping o lambda não é mais problema, mas `List` mutável ainda é.
- Ordem de `Modifier` importa (`padding` antes de `background` pinta o
  padding; `clickable` antes de `padding` estende a área de toque);
  `modifier: Modifier = Modifier` é o primeiro parâmetro opcional e é
  aplicado no nó raiz.
- `LazyColumn` dentro de `Column(verticalScroll)` sem altura fixa crasha;
  `fillMaxSize` em item de lista lazy é bug.
- `imePadding()`/`navigationBarsPadding()` onde o teclado ou a barra
  cobrem conteúdo; `Scaffold` recebe `contentWindowInsets` coerente.
- `@Preview` para tela ou componente novo, incluindo dark theme e
  `fontScale` maior; `@PreviewParameter` para estados (carregando, erro,
  vazio).
- Tema Material 3: `MaterialTheme.colorScheme`/`typography`/`shapes`;
  `Color(0xFF...)` e `16.sp` soltos fora do tema são achado.
- `Text` com `stringResource`; `pluralStringResource` para plural;
  `Modifier.semantics` com `contentDescription`/`role` em componente
  customizado.
- Animação com `animate*AsState`/`AnimatedVisibility`, respeitando
  `LocalAccessibilityManager`/reduzir movimento quando o projeto trata.
- Recomposição excessiva em tela com problema declarado: Layout
  Inspector com contagem, e a correção é de escopo (quebrar composable),
  não `remember` em tudo.

## Views (XML)

- `ViewBinding` em vez de `findViewById`; `binding` de `Fragment` zerado
  em `onDestroyView`.
- `LiveData`/`Flow` observado com `viewLifecycleOwner` em `Fragment`,
  nunca `this`: observer sobrevive à view e duplica.
- `RecyclerView` com `ListAdapter` + `DiffUtil`; `notifyDataSetChanged`
  é achado; `setHasStableIds` quando há animação de item.
- `ConstraintLayout` plano em vez de `LinearLayout` aninhado profundo;
  `wrap_content` em item de lista com imagem sem tamanho conhecido
  causa pulo.
- `Fragment` com construtor com argumento é recriado sem ele:
  `newInstance` com `Bundle`/`setArguments`.
- `AsyncTask`, `Handler` de `Looper` sem remover callbacks, `Thread`
  cru: substituir por coroutine.

## Room

- Schema, migration, query e concorrência do SQLite estão em
  `database-sqlite-android.md` (F12), que carrega junto quando o diff
  toca Room. Aqui só o que é integração com o app: instância única de
  `RoomDatabase` provida pelo DI como singleton; DAO injetado no
  repositório, nunca na UI; `TypeConverter` registrado na classe do
  banco; `@Query` de retorno `Flow` emite a cada mudança na tabela
  (query pesada observada em tela quente re-roda o tempo todo).

## Hilt

- Já coberto em "Arquitetura"; aplicar também: `@Module` `@InstallIn`
  coerente com o escopo; `@Binds` para interface; `@AssistedInject`
  para `ViewModel` com argumento de runtime; `@HiltAndroidTest` +
  `HiltTestApplication` para teste instrumentado; `@TestInstallIn`
  substitui módulo em teste sem `@UninstallModules` em cada teste.
