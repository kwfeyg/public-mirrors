#!/bin/bash

set -eu

RAW_BASE_URL="https://raw.githubusercontent.com/kwfeyg/public-mirrors/main"
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

require_root() {
    [ "$(id -u)" -eq 0 ] || err 'É necessário executar como root'
}

banner() {
    clear
    printf "\n\033[1;34m═══════════════════════════════════════════════════════\033[0m\n"
    printf "\033[1;37m%28s%s%-12s\033[0m\n" "PLAYON / MAIN INSTALLER"
    printf "\033[1;34m═══════════════════════════════════════════════════════\033[0m\n"
    printf "\033[0;37mReinstalação completa do sistema com menu centralizado.\033[0m\n"
    printf "\033[0;37mDebian segue o instalador original. Ubuntu usa fluxo dedicado.\033[0m\n\n"
}

pause_return() {
    printf "\n\033[1;33mEnter para voltar ao menu...\033[0m"
    read -r _
}

dns_banner() {
    clear
    printf "\n\033[1;34m═══════════════════════════════════════════════════════\033[0m\n"
    printf "\033[1;37m%24s%s%-15s\033[0m\n" "DNS PERSISTENTE"
    printf "\033[1;34m═══════════════════════════════════════════════════════\033[0m\n"
    printf "\033[0;37mPersistência com systemd + bloqueio do /etc/resolv.conf.\033[0m\n\n"
}

ensure_dns_dependencies() {
    command_exists systemctl || err 'systemctl não encontrado'
    command_exists chattr || err 'chattr não encontrado'
    command_exists lsattr || err 'lsattr não encontrado'
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
    chattr +i "$DNS_RESOLV_PATH"
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
    chattr +i "$DNS_RESOLV_PATH"
    printf "\n\033[1;32mArquivo travado: %s\033[0m\n" "$DNS_RESOLV_PATH"
    pause_return
}

run_dns_script_now() {
    require_root
    [ -x "$DNS_SCRIPT_PATH" ] || err 'O script de DNS ainda não foi criado'
    unlock_resolv_if_needed
    "$DNS_SCRIPT_PATH"
    if [ -e "$DNS_RESOLV_PATH" ]; then
        chattr +i "$DNS_RESOLV_PATH" || true
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
    download "$RAW_BASE_URL/debianinstall-original.sh" "$tmp_script"
    chmod +x "$tmp_script"
    bash "$tmp_script"
}

run_ubuntu_installer() {
    export TERM=xterm
    local tmp_script=/tmp/ubuntuinstall.sh
    printf "\n\033[1;36mBaixando o instalador Ubuntu...\033[0m\n"
    download "$RAW_BASE_URL/ubuntuinstall.sh" "$tmp_script"
    chmod +x "$tmp_script"
    bash "$tmp_script"
}

show_windows_status() {
    printf "\n\033[1;31mWindows ainda não está liberado nesta versão.\033[0m\n"
    printf "\033[0;37mO item já existe no menu principal, mas o fluxo WinPE/Unattend\033[0m\n"
    printf "\033[0;37mainda precisa ser homologado para não prometer uma reinstalação\033[0m\n"
    printf "\033[0;37mque não esteja 100%% segura.\033[0m\n"
    pause_return
}

while true; do
    banner
    printf "\033[1;32m  [1]\033[0m Debian\n"
    printf "\033[1;32m  [2]\033[0m Ubuntu\n"
    printf "\033[1;32m  [3]\033[0m Windows \033[0;37m(em breve)\033[0m\n"
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
            show_windows_status
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
