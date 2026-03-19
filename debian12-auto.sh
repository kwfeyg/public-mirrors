#!/usr/bin/env bash

set -euo pipefail

SCRIPT_URL="https://raw.githubusercontent.com/kwfeyg/public-mirrors/main/debianinstall.sh"
DEFAULT_VERSION="12"
DEFAULT_TIMEZONE="UTC-3"

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m'

banner() {
  printf "\n${RED}════════════════════════════════════════════════════════════${NC}\n"
  printf "${CYAN}%-60s${NC}\n" "PLAYON / DEBIAN AUTO INSTALLER"
  printf "${RED}════════════════════════════════════════════════════════════${NC}\n"
}

info() {
  printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

ok() {
  printf "${GREEN}[OK]${NC} %s\n" "$1"
}

warn() {
  printf "${YELLOW}[ATENÇÃO]${NC} %s\n" "$1"
}

fail() {
  printf "${RED}[ERRO]${NC} %s\n" "$1" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Uso:
  ROOT_PASSWORD='sua_senha' bash <(wget -qO- https://raw.githubusercontent.com/kwfeyg/root-scripts/main/mirrors/debian12-auto.sh)

Ou:
  bash <(wget -qO- https://raw.githubusercontent.com/kwfeyg/root-scripts/main/mirrors/debian12-auto.sh) --password 'sua_senha'

Opções:
  --password SENHA       Define a senha root para o Debian novo
  --version N            Versão Debian (padrão: 12)
  --timezone TZ          Timezone do instalador (padrão: UTC-3)
  --script-url URL       URL do script base espelhado
  --help                 Mostra esta ajuda

Observação:
  Este wrapper automatiza a execução do instalador base sem remover as funções dele.
  Ele baixa o script espelhado, força terminal compatível, fixa Debian 12 por padrão
  e confirma automaticamente a última etapa antes do reboot.
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Comando obrigatório ausente: $1"
}

ROOT_PASSWORD="${ROOT_PASSWORD:-}"
DEBIAN_VERSION="${DEBIAN_VERSION:-$DEFAULT_VERSION}"
INSTALL_TIMEZONE="${INSTALL_TIMEZONE:-$DEFAULT_TIMEZONE}"

while [ $# -gt 0 ]; do
  case "$1" in
    --password)
      ROOT_PASSWORD="${2:-}"
      shift 2
      ;;
    --version)
      DEBIAN_VERSION="${2:-}"
      shift 2
      ;;
    --timezone)
      INSTALL_TIMEZONE="${2:-}"
      shift 2
      ;;
    --script-url)
      SCRIPT_URL="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Opção não reconhecida: $1"
      ;;
  esac
done

[ "$(id -u)" -eq 0 ] || fail "Execute como root"
require_cmd bash
require_cmd wget

case "$DEBIAN_VERSION" in
  10|11|12|13|buster|bullseye|bookworm|trixie|oldoldstable|oldstable|stable|testing|sid|unstable)
    ;;
  *)
    fail "Versão Debian inválida: $DEBIAN_VERSION"
    ;;
esac

[ -n "$ROOT_PASSWORD" ] || fail "Defina a senha com ROOT_PASSWORD ou --password"
[ "${#ROOT_PASSWORD}" -ge 8 ] || fail "A senha precisa ter pelo menos 8 caracteres"

banner
warn "Este processo prepara reinstalação completa do sistema e pode apagar o Ubuntu atual."
warn "Faça backup antes de continuar."
printf "\n"
info "Versão Debian alvo: $DEBIAN_VERSION"
info "Timezone configurada: $INSTALL_TIMEZONE"
info "Script base: $SCRIPT_URL"

TMP_DIR="$(mktemp -d)"
BASE_SCRIPT="$TMP_DIR/debianinstall.sh"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

info "Baixando instalador base espelhado..."
wget -qO "$BASE_SCRIPT" "$SCRIPT_URL"
chmod +x "$BASE_SCRIPT"
ok "Instalador baixado com sucesso."

export TERM=xterm
export DEBIAN_FRONTEND=noninteractive

RUN_CMD=(
  bash "$BASE_SCRIPT"
  --version "$DEBIAN_VERSION"
  --password "$ROOT_PASSWORD"
  --timezone "$INSTALL_TIMEZONE"
)

printf "\n"
info "Iniciando execução automática do instalador..."
warn "Ao final, a confirmação de reboot será enviada automaticamente."
printf "\n"

if command -v script >/dev/null 2>&1; then
  printf '\n' | script -q -c "$(printf '%q ' "${RUN_CMD[@]}")" /dev/null
else
  printf '\n' | "${RUN_CMD[@]}"
fi
