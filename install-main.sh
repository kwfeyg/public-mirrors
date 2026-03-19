#!/bin/bash

set -eu

RAW_BASE_URL="https://raw.githubusercontent.com/kwfeyg/public-mirrors/main"
INSTALL_DIR="/opt/system-installer"
BIN_PATH="/usr/local/bin/main"

err() {
    printf "\nErro: %s.\n" "$1" 1>&2
    exit 1
}

command_exists() {
    command -v "$1" > /dev/null 2>&1
}

download() {
    if command_exists wget; then
        wget -qO "$2" "$1"
    elif command_exists curl; then
        curl -fsSL "$1" -o "$2"
    else
        err 'Não foi possível encontrar wget ou curl'
    fi
}

[ "$(id -u)" -eq 0 ] || err 'Execute como root'

mkdir -p "$INSTALL_DIR"

for script_name in installsystem.sh debianinstall-original.sh ubuntuinstall.sh windowsinstall.sh; do
    printf "Instalando %s...\n" "$script_name"
    download "$RAW_BASE_URL/$script_name" "$INSTALL_DIR/$script_name"
    chmod +x "$INSTALL_DIR/$script_name"
done

cat > "$BIN_PATH" <<EOF
#!/bin/bash
set -eu
export TERM=\${TERM:-xterm}

case "\${1:-}" in
    update)
        bash "$INSTALL_DIR/install-main.sh"
        ;;
    path)
        printf '%s\n' "$INSTALL_DIR"
        ;;
    *)
        exec bash "$INSTALL_DIR/installsystem.sh"
        ;;
esac
EOF
chmod +x "$BIN_PATH"

cat > "$INSTALL_DIR/install-main.sh" <<'EOF'
#!/bin/bash
set -eu
export TERM=${TERM:-xterm}
if command -v wget >/dev/null 2>&1; then
    bash <(wget -qO- https://raw.githubusercontent.com/kwfeyg/public-mirrors/main/install-main.sh)
elif command -v curl >/dev/null 2>&1; then
    bash <(curl -fsSL https://raw.githubusercontent.com/kwfeyg/public-mirrors/main/install-main.sh)
else
    echo "wget ou curl é obrigatório para atualizar o instalador." >&2
    exit 1
fi
EOF
chmod +x "$INSTALL_DIR/install-main.sh"

printf "\nInstalação concluída.\n"
printf "Comando disponível: main\n"
printf "Atualizar depois: main update\n"
