#!/usr/bin/env bash
# PROMPT 11.3.4/11.3.4.1 — guarda de segurança obrigatória ANTES de rodar
# qualquer script desta pasta, E antes de colar qualquer SQL no SQL
# Editor. Nenhum outro script de supabase/homolog/ deve ser rodado sem que
# este aqui tenha impresso "LIBERADO" primeiro.
#
# REQUISITO DE AMBIENTE (Windows): este é um script BASH. Precisa do Git
# Bash (instalado junto com o Git for Windows, mas NÃO fica no PATH de uma
# sessão comum do PowerShell/cmd por padrão — o arquivo existir no disco
# NÃO significa que ele roda). Rode de uma das formas abaixo:
#   - Abra "Git Bash" (item do menu Iniciar, instalado junto com o Git) e
#     rode: ./00_check_target_not_producao.sh env/homologacao.env
#   - Ou, de dentro do PowerShell, chame o bash.exe pelo caminho completo,
#     ex.: & "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe" 00_check_target_not_producao.sh env/homologacao.env
#     (o caminho exato depende de onde o Git foi instalado na sua máquina)
#   - Se preferir não depender de bash nenhum, use o equivalente
#     `00_check_target_not_producao.ps1` (mesma lógica, PowerShell nativo).
#
# LIMITAÇÃO IMPORTANTE (seção 3 do PROMPT 11.3.4.1): este script só
# compara ARQUIVOS DE CONFIGURAÇÃO (env/*.env vs. o .env de produção deste
# repositório). Ele NÃO sabe, e NÃO PODE saber, qual projeto está
# realmente aberto na aba do navegador onde você vai colar o SQL — rodar
# este script no terminal NÃO protege automaticamente um SQL colado
# manualmente no SQL Editor de outro projeto (ex.: uma aba antiga, ainda
# aberta, do projeto de produção). Por isso a ÚLTIMA etapa deste script
# pede para você digitar o ref que você VÊ na URL do Dashboard aberto —
# essa confirmação manual não é opcional.
#
# O QUE FAZ:
#   1. Exige, como argumento, o caminho de um arquivo .env de HOMOLOGAÇÃO
#      (ex.: env/homologacao.env — ver env/homologacao.env.example).
#   2. Recusa se esse arquivo não existir, ou não declarar literalmente
#      SUPABASE_ENV=homologacao (o nome do arquivo NUNCA é usado como prova).
#   3. Extrai o "project ref" (subdomínio) da SUPABASE_URL de homologação e
#      do .env de PRODUÇÃO deste repositório (por padrão, ./.env — o mesmo
#      arquivo que `flutter run`/`flutter build` usam quando nenhuma flag
#      --dart-define-from-file é passada).
#   4. Recusa se qualquer um dos dois refs não puder ser determinado, ou se
#      os dois refs forem IGUAIS (apontaria para o projeto de produção).
#   5. Pede para você digitar o ref visível na URL do Dashboard aberto no
#      navegador, e recusa se não bater com o ref de homologação do passo 3.
#
# NUNCA imprime a URL nem a chave completas — só uma prévia curta do
# project ref (4 caracteres + comprimento), o suficiente para conferência
# visual humana, insuficiente para ser usado como credencial.
#
# USO:
#   ./00_check_target_not_producao.sh env/homologacao.env
#   echo $?   # 0 = liberado para prosseguir; qualquer outro valor = recusado
set -euo pipefail

HOMOLOG_ENV_FILE="${1:-}"
PROD_ENV_FILE="${PROD_ENV_FILE:-.env}"

fail() {
  echo "RECUSADO: $1" >&2
  echo "Nenhum script de homologação deve prosseguir, e nenhum SQL deve ser colado." >&2
  exit 1
}

[ -n "$HOMOLOG_ENV_FILE" ] || fail "informe o caminho do .env de homologação como argumento (ex.: env/homologacao.env)."
[ -f "$HOMOLOG_ENV_FILE" ] || fail "arquivo '$HOMOLOG_ENV_FILE' não encontrado."
[ -f "$PROD_ENV_FILE" ] || fail "arquivo de produção '$PROD_ENV_FILE' não encontrado — sem ele não dá para confirmar que o destino é diferente."

extrair_ref() {
  grep -oE 'SUPABASE_URL=https://[a-z0-9]+\.supabase\.co' "$1" 2>/dev/null \
    | head -1 \
    | sed -E 's#SUPABASE_URL=https://([a-z0-9]+)\.supabase\.co#\1#'
}

extrair_supabase_env() {
  grep -oE '^SUPABASE_ENV=[a-zA-Z]*' "$1" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '\r' | tr '[:upper:]' '[:lower:]'
}

DECLARADO=$(extrair_supabase_env "$HOMOLOG_ENV_FILE")
[ "$DECLARADO" = "homologacao" ] || fail "'$HOMOLOG_ENV_FILE' não declara SUPABASE_ENV=homologacao explicitamente (encontrado: '${DECLARADO:-<ausente>}'). O nome do arquivo nunca é suficiente."

REF_PROD=$(extrair_ref "$PROD_ENV_FILE")
REF_HOMOLOG=$(extrair_ref "$HOMOLOG_ENV_FILE")

[ -n "$REF_PROD" ] || fail "não foi possível extrair o project ref de produção de '$PROD_ENV_FILE' — recusando por segurança (destino não identificável)."
[ -n "$REF_HOMOLOG" ] || fail "não foi possível extrair o project ref de '$HOMOLOG_ENV_FILE' — recusando por segurança (destino não identificável)."
[ "$REF_HOMOLOG" != "$REF_PROD" ] || fail "o project ref de '$HOMOLOG_ENV_FILE' é IGUAL ao de produção — isto apontaria para o banco de PRODUÇÃO."

echo "OK (arquivos) — '$HOMOLOG_ENV_FILE' é diferente do projeto de produção."
echo "  SUPABASE_ENV declarado: $DECLARADO"
echo "  project ref (homologação): ${REF_HOMOLOG:0:4}...(${#REF_HOMOLOG} caracteres)"
echo "  project ref (produção, só para conferência visual): ${REF_PROD:0:4}...(${#REF_PROD} caracteres)"
echo "  (nenhuma URL ou chave completa foi impressa)"
echo
echo "CONFIRMAÇÃO VISUAL OBRIGATÓRIA — este script não vê sua tela."
echo "No navegador, confira a URL do Dashboard do projeto que está ABERTO"
echo "agora (formato: https://supabase.com/dashboard/project/<ref>)."
read -r -p "Digite o <ref> que você VÊ na URL do Dashboard aberto: " REF_DASHBOARD
REF_DASHBOARD=$(echo "$REF_DASHBOARD" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

[ -n "$REF_DASHBOARD" ] || fail "nenhum ref foi digitado — sem confirmação visual, não prossiga."
[ "$REF_DASHBOARD" != "$REF_PROD" ] || fail "o ref digitado é o de PRODUÇÃO — a aba aberta no navegador NÃO é homologação. Feche-a e abra o projeto de homologação antes de continuar."
[ "$REF_DASHBOARD" = "$REF_HOMOLOG" ] || fail "o ref digitado ('${REF_DASHBOARD:0:4}...') não bate com o ref de '$HOMOLOG_ENV_FILE' ('${REF_HOMOLOG:0:4}...'). Não é o projeto esperado — não prossiga com ambiguidade."

echo
echo "LIBERADO — arquivo de configuração E aba do Dashboard confirmam o mesmo projeto de HOMOLOGAÇÃO."
