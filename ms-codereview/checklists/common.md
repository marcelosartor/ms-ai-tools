# Checklist — comum a todo PR

Aplicar sempre; é curto de propósito. Cobre o que nenhum checklist de
stack vê.

- Variável de ambiente, flag ou configuração nova está em
  `.env.example` (ou equivalente) e documentada; valor padrão em
  produção é o seguro.
- Formato de dado persistido mudou (JSON em coluna, arquivo, cache,
  `localStorage`, mensagem de fila): quem lê o formato antigo ainda
  funciona, ou há migração.
- Contrato consumido por outro sistema (resposta de API, evento, schema
  de export) mudou de forma incompatível sem versão nem aviso.
- Comportamento visível ao usuário mudou e a documentação, o texto de
  ajuda ou o changelog que o descrevem não mudaram.
- Feature flag nova: quem a liga, onde é lida, e o que acontece com o
  código quando ela sumir.
- `TODO`/`FIXME` novo sem ticket ou sem dono.
- Código comentado, `console.log`/`print` de debug, `.only` em teste,
  `skip` sem motivo.
- Arquivo grande ou binário adicionado ao repositório sem ser asset
  necessário.
- Nome de branch, título e descrição do PR descrevem a mudança de
  verdade; descrição promete algo que o diff não faz (já é achado pelo
  procedimento; aqui só reforça a leitura).
- Data, hora e fuso: cálculo de "hoje", "fim do mês", prazo, sem fuso
  explícito.
- Texto visível novo passa pelo i18n quando o projeto tem i18n.
- Licença de dependência nova é compatível com o projeto (GPL em produto
  fechado é achado).
