#!/bin/bash

set -eu

RAW_BASE_URL="https://raw.githubusercontent.com/kwfeyg/public-mirrors/main"
LOCAL_BASE_DIR="/opt/system-installer"
DNS_SCRIPT_PATH="/usr/local/sbin/fix-dns.sh"
DNS_SERVICE_PATH="/etc/systemd/system/fix-dns.service"
DNS_RESOLV_PATH="/etc/resolv.conf"

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

resolve_script_path() {
    local script_name=$1
    if [ -x "$LOCAL_BASE_DIR/$script_name" ]; then
        printf '%s\n' "$LOCAL_BASE_DIR/$script_name"
        return 0
    fi
    printf '%s/%s\n' "$RAW_BASE_URL" "$script_name"
}

prepare_runner_script() {
    local script_name=$1
    local target_path=$2
    local resolved
    resolved=$(resolve_script_path "$script_name")

    if [ -x "$resolved" ]; then
        cp "$resolved" "$target_path"
    else
        download "$resolved" "$target_path"
    fi
    chmod +x "$target_path"
}

require_root() {
    [ "$(id -u)" -eq 0 ] || err 'É necessário executar como root'
}

banner() {
    clear
    printf "\n\033[1;34m═══════════════════════════════════════════════════════\033[0m\n"
    printf "\033[1;37m%25s%s%-14s\033[0m\n" "UNIFIED OS INSTALLER"
    printf "\033[1;34m═══════════════════════════════════════════════════════\033[0m\n"
    printf "\033[0;37mReinstalação completa do sistema com seleção central.\033[0m\n"
    printf "\033[0;37mDebian usa o instalador original. Ubuntu usa o fluxo oficial dedicado.\033[0m\n\n"
}

pause_return() {
    printf "\n\033[1;33mEnter para voltar ao menu...\033[0m"
    read -r _
}

dns_banner() {
    clear
    printf "\n\033[1;34m═══════════════════════════════════════════════════════\033[0m\n"
    printf "\033[1;37m%25s%s%-14s\033[0m\n" "DNS PERSISTENTE"
    printf "\033[1;34m═══════════════════════════════════════════════════════\033[0m\n"
    printf "\033[0;37mPersistência com systemd + bloqueio do /etc/resolv.conf.\033[0m\n\n"
}

ensure_dns_dependencies() {
    command_exists systemctl || err 'systemctl não encontrado'
    command_exists chattr || err 'chattr não encontrado'
    command_exists lsattr || err 'lsattr não encontrado'
}

can_lock_resolv_conf() {
    local output_file
    output_file=$(mktemp)
    if chattr +i "$DNS_RESOLV_PATH" > /dev/null 2>"$output_file"; then
        chattr -i "$DNS_RESOLV_PATH" > /dev/null 2>&1 || true
        rm -f "$output_file"
        return 0
    fi
    DNS_LOCK_ERROR=$(cat "$output_file" 2> /dev/null || true)
    rm -f "$output_file"
    return 1
}

apply_lock_if_supported() {
    DNS_LOCK_ERROR=
    if can_lock_resolv_conf; then
        chattr +i "$DNS_RESOLV_PATH"
        printf "\n\033[1;32mArquivo travado com chattr +i.\033[0m\n"
        return 0
    fi

    printf "\n\033[1;33mAviso:\033[0m o bloqueio imutável com chattr não é suportado nesta VPS.\n"
    if [ -n "${DNS_LOCK_ERROR:-}" ]; then
        printf "\033[0;37mDetalhe: %s\033[0m\n\n" "$DNS_LOCK_ERROR"
    fi
    printf "\033[0;37mO DNS continuará persistente via systemd no boot, mas sem trava imutável no /etc/resolv.conf.\033[0m\n"
    return 1
}

write_dns_script() {
    mkdir -p /usr/local/sbin /etc/systemd/system
    cat > "$DNS_SCRIPT_PATH" <<'EOF_SCRIPT'
#!/bin/bash
cat > /etc/resolv.conf <<'EOF_RESOLV'
domain vcn03190314.oraclevcn.com
search vcn03190314.oraclevcn.com
nameserver 169.254.169.254
nameserver 1.0.0.1
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 208.67.222.222
nameserver 208.67.220.220
nameserver 103.86.99.103
nameserver 103.86.96.103
EOF_RESOLV
EOF_SCRIPT
    chmod +x "$DNS_SCRIPT_PATH"
}

write_dns_service() {
    cat > "$DNS_SERVICE_PATH" <<'EOF_SERVICE'
[Unit]
Description=Fix persistent DNS on boot
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/fix-dns.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF_SERVICE
}

unlock_resolv_if_needed() {
    if lsattr "$DNS_RESOLV_PATH" 2>/dev/null | awk '{print $1}' | grep -q 'i'; then
        chattr -i "$DNS_RESOLV_PATH"
    fi
}

apply_persistent_dns() {
    require_root
    ensure_dns_dependencies
    printf "\n\033[1;36mAplicando DNS persistente...\033[0m\n"
    unlock_resolv_if_needed
    write_dns_script
    write_dns_service
    systemctl daemon-reload
    systemctl enable --now fix-dns.service
    "$DNS_SCRIPT_PATH"
    apply_lock_if_supported || true
    printf "\n\033[1;32mDNS persistente aplicado com sucesso.\033[0m\n\n"
    cat "$DNS_RESOLV_PATH"
    pause_return
}

show_dns_status() {
    require_root
    ensure_dns_dependencies
    printf "\n\033[1;36mConteúdo atual de %s:\033[0m\n\n" "$DNS_RESOLV_PATH"
    cat "$DNS_RESOLV_PATH" 2>/dev/null || true
    printf "\n\033[1;36mStatus do serviço:\033[0m\n\n"
    systemctl status fix-dns.service --no-pager || true
    printf "\n\033[1;36mAtributos do arquivo:\033[0m\n\n"
    lsattr "$DNS_RESOLV_PATH" 2>/dev/null || true
    pause_return
}

unlock_dns_file() {
    require_root
    ensure_dns_dependencies
    if [ -e "$DNS_RESOLV_PATH" ]; then
        chattr -i "$DNS_RESOLV_PATH" || true
        printf "\n\033[1;32mArquivo destravado: %s\033[0m\n" "$DNS_RESOLV_PATH"
    else
        printf "\n\033[1;31mArquivo não encontrado: %s\033[0m\n" "$DNS_RESOLV_PATH"
    fi
    pause_return
}

lock_dns_file() {
    require_root
    ensure_dns_dependencies
    [ -e "$DNS_RESOLV_PATH" ] || err 'O arquivo /etc/resolv.conf não existe'
    apply_lock_if_supported || true
    pause_return
}

run_dns_script_now() {
    require_root
    [ -x "$DNS_SCRIPT_PATH" ] || err 'O script de DNS ainda não foi criado'
    unlock_resolv_if_needed
    "$DNS_SCRIPT_PATH"
    if [ -e "$DNS_RESOLV_PATH" ]; then
        apply_lock_if_supported || true
    fi
    printf "\n\033[1;32mScript executado com sucesso.\033[0m\n\n"
    cat "$DNS_RESOLV_PATH"
    pause_return
}

dns_menu() {
    while true; do
        dns_banner
        printf "\033[1;32m  [1]\033[0m Aplicar DNS persistente\n"
        printf "\033[1;32m  [2]\033[0m Verificar status DNS\n"
        printf "\033[1;32m  [3]\033[0m Destravar /etc/resolv.conf\n"
        printf "\033[1;32m  [4]\033[0m Travar /etc/resolv.conf\n"
        printf "\033[1;32m  [5]\033[0m Executar fix-dns.sh agora\n"
        printf "\033[1;32m  [0]\033[0m Voltar\n\n"
        printf "\033[1;33mEscolha a ação DNS: \033[0m"
        read -r dns_choice

        case "${dns_choice:-}" in
            1) apply_persistent_dns ;;
            2) show_dns_status ;;
            3) unlock_dns_file ;;
            4) lock_dns_file ;;
            5) run_dns_script_now ;;
            0) return 0 ;;
            *)
                printf "\n\033[1;31mOpção inválida.\033[0m\n"
                sleep 2
                ;;
        esac
    done
}

run_debian_installer() {
    export TERM=xterm
    local tmp_script=/tmp/debianinstall.sh
    printf "\n\033[1;36mBaixando o instalador Debian original...\033[0m\n"
    prepare_runner_script "debianinstall-original.sh" "$tmp_script"
    bash "$tmp_script"
}

run_ubuntu_installer() {
    export TERM=xterm
    local tmp_script=/tmp/ubuntuinstall.sh
    printf "\n\033[1;36mBaixando o instalador Ubuntu...\033[0m\n"
    prepare_runner_script "ubuntuinstall.sh" "$tmp_script"
    bash "$tmp_script"
}

run_windows_installer() {
    export TERM=xterm
    local tmp_script=/tmp/windowsinstall.sh
    printf "\n\033[1;36mBaixando o instalador Windows...\033[0m\n"
    prepare_runner_script "windowsinstall.sh" "$tmp_script"
    bash "$tmp_script"
}

while true; do
    banner
    printf "\033[1;32m  [1]\033[0m Debian\n"
    printf "\033[1;32m  [2]\033[0m Ubuntu\n"
    printf "\033[1;32m  [3]\033[0m Windows Server\n"
    printf "\033[1;32m  [4]\033[0m Área DNS\n"
    printf "\033[1;32m  [0]\033[0m Sair\n\n"
    printf "\033[1;33mEscolha o sistema: \033[0m"
    read -r choice

    case "${choice:-}" in
        1)
            run_debian_installer
            ;;
        2)
            run_ubuntu_installer
            ;;
        3)
            run_windows_installer
            ;;
        4)
            dns_menu
            ;;
        0)
            exit 0
            ;;
        *)
            printf "\n\033[1;31mOpção inválida.\033[0m\n"
            sleep 2
            ;;
    esac
done
