#!/usr/bin/env bash
#
# Baixa e extrai texto dos anexos listados em $RAW/attachments.json.
#
# Entrada esperada ($RAW/attachments.json, escrita por cada provider em
# <p>_attachments): array de objetos
#   {id, titulo, extensao, tamanho, data, autor, url, auth}
# `auth` diz se o download precisa do mesmo header usado para a API
# (Jira/Linear: sim — a URL do anexo exige a mesma credencial; ClickUp:
# não — a URL já vem assinada, e mandar Authorization pode até invalidar
# a assinatura).
#
# Saída em $RAW/attachments/:
#   <id>.<ext>            arquivo baixado, como veio do board
#   <id>.extraido.txt     texto extraído, só quando deu para extrair
# Mais $RAW/attachments-manifest.md: uma linha por anexo dizendo o que
# aconteceu — extraído, ou "sem texto extraível: leia
# attachments/<id>.<ext> diretamente" (é assim que a skill sabe quais
# anexos ela mesma precisa abrir para descrever).
#
# Texto puro (md/txt/json/csv/log/yml/yaml/sql/html/xml) é lido direto;
# PDF passa por `pdftotext` quando disponível; o resto (imagem, binário,
# PDF sem camada de texto) só é baixado — a extração desses fica para a
# skill, que lê o arquivo com sua própria ferramenta de leitura.

TEXT_EXTS="md txt json csv log yml yaml sql html xml"
LIMITE_BYTES=$((25 * 1024 * 1024))

extract_attachments() { # $1 = $RAW
  local raw="$1" manifest
  manifest="$raw/attachments-manifest.md"
  local f="$raw/attachments.json"

  if [ ! -s "$f" ] || ! jq -e 'length > 0' "$f" >/dev/null 2>&1; then
    printf '# Anexos\n\n(nenhum anexo)\n' > "$manifest"
    return 0
  fi

  mkdir -p "$raw/attachments"
  printf '# Anexos\n\n' > "$manifest"

  local n
  n="$(jq 'length' "$f")"
  local i=0
  while [ "$i" -lt "$n" ]; do
    local item id titulo ext tamanho data autor url auth base local_bin local_txt motivo
    item="$(jq -c ".[$i]" "$f")"
    id="$(printf '%s' "$item" | jq -r '.id // empty')"
    titulo="$(printf '%s' "$item" | jq -r '.titulo // "anexo"')"
    ext="$(printf '%s' "$item" | jq -r '.extensao // ""' | tr 'A-Z' 'a-z')"
    tamanho="$(printf '%s' "$item" | jq -r '.tamanho // 0')"
    data="$(printf '%s' "$item" | jq -r '.data // "-"')"
    autor="$(printf '%s' "$item" | jq -r '.autor // "-"')"
    url="$(printf '%s' "$item" | jq -r '.url // empty')"
    auth="$(printf '%s' "$item" | jq -r '.auth // false')"
    i=$((i + 1))

    base="$(printf '%s' "${id:-$titulo}" | tr -c 'A-Za-z0-9._-' '-' | sed 's/-\{2,\}/-/g')"
    [ -n "$base" ] || base="anexo-$i"
    local_bin="$raw/attachments/$base${ext:+.$ext}"
    local_txt="$raw/attachments/$base.extraido.txt"
    motivo=""

    if [ -z "$url" ]; then
      motivo="sem URL acessível"
    elif [ "$tamanho" != "0" ] && [ "$tamanho" -gt "$LIMITE_BYTES" ] 2>/dev/null; then
      motivo="arquivo acima do limite ($tamanho bytes) — não baixado"
    else
      local saved=false
      if [ -f "$local_bin" ]; then
        saved=true
      else
        local auth_flag=()
        [ "$auth" = "true" ] && [ -n "$AUTH_HEADER" ] && auth_flag=(-H "Authorization: $AUTH_HEADER")
        if curl -fsSL --max-time 120 "${auth_flag[@]}" -o "$local_bin" "$url" 2>>"$raw/http-error.log"; then
          saved=true
        else
          rm -f "$local_bin"
          motivo="falha no download"
        fi
      fi

      if [ "$saved" = true ]; then
        case " $TEXT_EXTS " in
          *" $ext "*)
            if iconv -f UTF-8 -t UTF-8 "$local_bin" > "$local_txt" 2>/dev/null; then
              [ -s "$local_txt" ] || { rm -f "$local_txt"; motivo="arquivo vazio"; }
            else
              rm -f "$local_txt"
              motivo="falha ao ler como texto"
            fi
            ;;
          *" pdf ")
            if command -v pdftotext >/dev/null 2>&1; then
              pdftotext -layout -enc UTF-8 "$local_bin" "$local_txt" 2>/dev/null || true
              if [ ! -s "$local_txt" ]; then
                rm -f "$local_txt"
                motivo="PDF sem camada de texto (provavelmente escaneado) — leia attachments/$(basename "$local_bin") diretamente"
              fi
            else
              motivo="pdftotext indisponível — leia attachments/$(basename "$local_bin") diretamente"
            fi
            ;;
          *)
            motivo="tipo não textual — leia attachments/$(basename "$local_bin") diretamente"
            ;;
        esac
      fi
    fi

    {
      printf -- '- **%s** (%s, %s, %s)\n' "$titulo" "${ext:-sem extensão}" "$data" "$autor"
      if [ -f "$local_txt" ]; then
        printf '  - extraído automaticamente: attachments/%s\n' "$(basename "$local_txt")"
      elif [ -f "$local_bin" ]; then
        printf '  - sem extração automática (%s): attachments/%s\n' "$motivo" "$(basename "$local_bin")"
      else
        printf '  - não baixado (%s)\n' "$motivo"
      fi
    } >> "$manifest"
  done
}
