# F0 — Quebra do SKILL.md em núcleo e referência
#
# Verificações estáticas, sem rodar a skill. Em vez de um comm/diff linha a
# linha contra o SKILL.md pré-F0 (frágil a qualquer rejustificação de
# parágrafo em markdown), confere: os quatro arquivos de referência existem
# e abrem com "Lido no passo N"; cada um é citado no SKILL.md exatamente uma
# vez, no formato de ponteiro `reference/<arquivo>.md antes de continuar`;
# cada ponteiro está condicionado (guarda "Se ..."/"quando ...") ou vive num
# passo (10, 11) que a rejeição por falta de dados nunca alcança; e algumas
# frases-âncora do conteúdo movido aparecem no arquivo de referência certo e
# não sobraram no núcleo.
echo "-- F0: quebra do SKILL.md --"

SKILL_MD="$SKILL_DIR/SKILL.md"
REF_DIR="$SKILL_DIR/reference"

f19_arquivos_existem() {
  for f in contexto.md re-review.md comentario.md segunda-passagem.md; do
    if [ -f "$REF_DIR/$f" ]; then
      ok "f19: reference/$f existe"
    else
      fail "f19: reference/$f existe" "não encontrado"
    fi
  done
}

f19_abre_com_lido_no_passo() {
  for f in contexto.md re-review.md comentario.md segunda-passagem.md; do
    local primeira
    primeira="$(grep -m1 -v '^[[:space:]]*$' "$REF_DIR/$f" 2>/dev/null || true)"
    case "$primeira" in
      "Lido no passo "*) ok "f19: $f abre com 'Lido no passo'" ;;
      *) fail "f19: $f abre com 'Lido no passo'" "primeira linha: $primeira" ;;
    esac
  done
}

f19_ponteiro_unico_e_condicional() {
  # $1=arquivo referenciado $2=guarda esperada perto do ponteiro
  local arquivo="$1" guarda="$2" n trecho
  n="$(grep -c "reference/${arquivo} antes de continuar" "$SKILL_MD")"
  assert_eq "f19: reference/$arquivo citado exatamente uma vez (ponteiro)" "1" "$n"
  trecho="$(grep -B2 "reference/${arquivo} antes de continuar" "$SKILL_MD" || true)"
  case "$trecho" in
    *"$guarda"*) ok "f19: ponteiro de $arquivo é condicional ($guarda)" ;;
    *) fail "f19: ponteiro de $arquivo é condicional ($guarda)" "trecho: $trecho" ;;
  esac
}

f19_passo_tardio_sem_rejeicao() {
  # 10 e 11 nunca são alcançados por rejeição por falta de dados: o ponteiro
  # pode ser incondicional ali. Confere que a linha do ponteiro está dentro
  # do bloco do passo 10/11 do Procedimento (entre "10. **" e "12. **").
  local trecho
  trecho="$(sed -n '/^10\. \*\*/,/^12\. \*\*/p' "$SKILL_MD")"
  case "$trecho" in
    *"reference/comentario.md antes de continuar"*) ok "f19: ponteiro de comentario.md está no passo 10" ;;
    *) fail "f19: ponteiro de comentario.md está no passo 10" ;;
  esac
  case "$trecho" in
    *"reference/segunda-passagem.md antes de continuar"*) ok "f19: ponteiro de segunda-passagem.md está no passo 11" ;;
    *) fail "f19: ponteiro de segunda-passagem.md está no passo 11" ;;
  esac
}

f19_conteudo_movido_nao_duplicado() {
  # Frases que só existiam numa seção removida do núcleo não podem ter
  # sobrado no SKILL.md, e devem existir no arquivo de referência certo.
  if grep -q "Refutação independente de cada" "$SKILL_MD"; then
    fail "f19: 'Refutação independente' saiu do núcleo"
  else
    ok "f19: 'Refutação independente' saiu do núcleo"
  fi
  if grep -q "Refutação independente de cada" "$REF_DIR/segunda-passagem.md"; then
    ok "f19: 'Refutação independente' está em segunda-passagem.md"
  else
    fail "f19: 'Refutação independente' está em segunda-passagem.md"
  fi

  if grep -q "commit_id.*gravado ainda é o head atual" "$SKILL_MD"; then
    fail "f19: regra de post-review.sh saiu do núcleo"
  else
    ok "f19: regra de post-review.sh saiu do núcleo"
  fi
  if grep -q "commit_id" "$REF_DIR/comentario.md"; then
    ok "f19: JSON de review está em comentario.md"
  else
    fail "f19: JSON de review está em comentario.md"
  fi

  if grep -q "sha7 anterior. → .sha7 atual" "$SKILL_MD"; then
    fail "f19: bloco de re-review saiu do núcleo"
  else
    ok "f19: bloco de re-review saiu do núcleo"
  fi
  if grep -q "resolvido | o trecho mudou" "$REF_DIR/re-review.md"; then
    ok "f19: tabela de re-review está em re-review.md"
  else
    fail "f19: tabela de re-review está em re-review.md"
  fi

  if grep -q "Saídas do script: .0. contexto obtido" "$SKILL_MD"; then
    fail "f19: exit codes do fetch-context saíram do núcleo"
  else
    ok "f19: exit codes do fetch-context saíram do núcleo"
  fi
  if grep -q "Saídas do script: .0. contexto obtido" "$REF_DIR/contexto.md"; then
    ok "f19: exit codes do fetch-context estão em contexto.md"
  else
    fail "f19: exit codes do fetch-context estão em contexto.md"
  fi
}

f19_nucleo_intacto() {
  # Seções que toda revisão usa continuam no SKILL.md, palavra por palavra.
  for frase in \
    "**Bloqueia o merge** apenas: erro de lógica, falha de segurança, perda ou" \
    "Se não foi possível confirmar, apresentar como dúvida a investigar, nunca" \
    "Não postar o comentário no PR, não submeter review e não editar arquivos, a"
  do
    if grep -qF "$frase" "$SKILL_MD"; then
      ok "f19: núcleo mantém: ${frase:0:40}..."
    else
      fail "f19: núcleo mantém: ${frase:0:40}..."
    fi
  done
}

f19_ponteiro_unico() {
  local arquivo="$1" n
  n="$(grep -c "reference/${arquivo} antes de continuar" "$SKILL_MD")"
  assert_eq "f19: reference/$arquivo citado exatamente uma vez (ponteiro)" "1" "$n"
}

f19_arquivos_existem
f19_abre_com_lido_no_passo
f19_ponteiro_unico_e_condicional "contexto.md" "diferente de"
f19_ponteiro_unico_e_condicional "re-review.md" "previous_report"
f19_ponteiro_unico "comentario.md"
f19_ponteiro_unico "segunda-passagem.md"
f19_passo_tardio_sem_rejeicao
f19_conteudo_movido_nao_duplicado
f19_nucleo_intacto
