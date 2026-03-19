#!/bin/bash

set -eu

RAW_BASE_URL="https://raw.githubusercontent.com/kwfeyg/public-mirrors/main"

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
    printf "\033[0;37mEu não vou deixar uma reinstalação Windows aparecendo como pronta\033[0m\n"
    printf "\033[0;37msem homologar WinPE, drivers, unattend e pós-boot remoto.\033[0m\n"
    pause_return
}

while true; do
    banner
    printf "\033[1;32m  [1]\033[0m Debian\n"
    printf "\033[1;32m  [2]\033[0m Ubuntu\n"
    printf "\033[1;32m  [3]\033[0m Windows Server 2019 \033[0;37m(em preparação)\033[0m\n"
    printf "\033[1;32m  [4]\033[0m Windows Server 2022 \033[0;37m(em preparação)\033[0m\n"
    printf "\033[1;32m  [5]\033[0m Windows Server 2025 \033[0;37m(em preparação)\033[0m\n"
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
        3|4|5)
            show_windows_status
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
