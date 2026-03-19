#!/bin/bash

set -eu

err() {
    printf "\nErro: %s.\n" "$1" 1>&2
    exit 1
}

warn() {
    printf "\nAviso: %s.\n" "$1" 1>&2
}

command_exists() {
    command -v "$1" > /dev/null 2>&1
}

download() {
    if command_exists wget; then
        wget -O "$2" "$1"
    elif command_exists curl; then
        curl -fL "$1" -o "$2"
    else
        err 'Não foi possível encontrar wget ou curl'
    fi
}

require_root() {
    [ "$(id -u)" -eq 0 ] || err 'É necessário executar como root'
}

banner() {
    clear
    printf "\n\033[1;35m═══════════════════════════════════════════════════════\033[0m\n"
    printf "\033[1;37m%29s%s%-11s\033[0m\n" "UBUNTU REINSTALLER"
    printf "\033[1;35m═══════════════════════════════════════════════════════\033[0m\n"
    printf "\033[0;37mReinstalação completa do disco com Ubuntu Server.\033[0m\n\n"
}

prompt_password() {
    while true; do
        printf "\033[1;33mSenha root do novo sistema: \033[0m"
        read -r password
        [ -n "$password" ] || {
            printf "\n\033[1;31mA senha não pode ficar vazia.\033[0m\n\n"
            continue
        }
        [ "${#password}" -ge 8 ] || {
            printf "\n\033[1;31mA senha deve ter pelo menos 8 caracteres.\033[0m\n\n"
            continue
        }
        break
    done
}

select_version() {
    local default=18.04
    while true; do
        banner
        printf "\033[1;32m  [1]\033[0m Ubuntu 18.04 LTS \033[0;37m(legacy)\033[0m\n"
        printf "\033[1;32m  [2]\033[0m Ubuntu 20.04 LTS\n"
        printf "\033[1;32m  [3]\033[0m Ubuntu 22.04 LTS\n"
        printf "\033[1;32m  [4]\033[0m Ubuntu 24.04 LTS\n\n"
        printf "\033[1;33mEscolha a versão [padrão %s]: \033[0m" "$default"
        read -r selected
        selected=${selected:-1}
        case "$selected" in
            1) ubuntu_version=18.04; ubuntu_series=bionic; installer_kind=legacy; break ;;
            2) ubuntu_version=20.04; ubuntu_series=focal; installer_kind=live; break ;;
            3) ubuntu_version=22.04; ubuntu_series=jammy; installer_kind=live; break ;;
            4) ubuntu_version=24.04; ubuntu_series=noble; installer_kind=live; break ;;
            *) printf "\n\033[1;31mOpção inválida.\033[0m\n"; sleep 2 ;;
        esac
    done
}

set_release_urls() {
    case "$ubuntu_version" in
        18.04)
            linux_url="https://archive.ubuntu.com/ubuntu/dists/bionic-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/linux"
            initrd_url="https://archive.ubuntu.com/ubuntu/dists/bionic-updates/main/installer-amd64/current/images/netboot/ubuntu-installer/amd64/initrd.gz"
            iso_url=
            ;;
        20.04)
            linux_url=
            initrd_url=
            iso_url="https://old-releases.ubuntu.com/releases/focal/ubuntu-20.04.6-live-server-amd64.iso"
            ;;
        22.04)
            linux_url=
            initrd_url=
            iso_url="https://releases.ubuntu.com/22.04/ubuntu-22.04.5-live-server-amd64.iso"
            ;;
        24.04)
            linux_url=
            initrd_url=
            iso_url="https://releases.ubuntu.com/24.04/ubuntu-24.04.4-live-server-amd64.iso"
            ;;
        *)
            err "Versão Ubuntu não suportada: $ubuntu_version"
            ;;
    esac
}

detect_architecture() {
    local machine
    machine=$(uname -m)
    case "$machine" in
        x86_64|amd64)
            architecture=amd64
            ;;
        *)
            err "Arquitetura ainda não suportada neste instalador Ubuntu: $machine"
            ;;
    esac
}

detect_hostname() {
    hostname_short=$(hostname -s 2> /dev/null || true)
    [ -n "${hostname_short:-}" ] || hostname_short=ubuntu-server
}

detect_boot_disk() {
    local boot_source disk_name
    boot_source=$(df /boot 2> /dev/null | awk 'NR==2 {print $1}')
    [ -n "${boot_source:-}" ] || boot_source=$(df / 2> /dev/null | awk 'NR==2 {print $1}')
    [ -n "${boot_source:-}" ] || err 'Não foi possível detectar o disco atual'

    disk_name=$(lsblk -no PKNAME "$boot_source" 2> /dev/null || true)
    if [ -n "$disk_name" ]; then
        target_disk="/dev/$disk_name"
    else
        target_disk="$boot_source"
    fi
}

mk_hash() {
    password_hash=$(mkpasswd -m sha-256 "$password" 2> /dev/null) ||
    password_hash=$(openssl passwd -5 "$password" 2> /dev/null) ||
    password_hash=$(python3 -c 'import crypt, sys; print(crypt.crypt(sys.argv[1], crypt.mksalt(crypt.METHOD_SHA256)))' "$password" 2> /dev/null) ||
    err 'Não foi possível gerar o hash da senha'
}

ensure_grub_tools() {
    if command_exists update-grub || command_exists grub-mkconfig || command_exists grub2-mkconfig; then
        return
    fi
    err 'Não foi possível encontrar update-grub, grub-mkconfig ou grub2-mkconfig'
}

setup_grub_defaults() {
    mkdir -p /etc/default/grub.d
    cat > /etc/default/grub.d/zz-osinstall.cfg <<EOF
GRUB_DEFAULT=osinstall-ubuntu
GRUB_TIMEOUT=5
EOF
}

run_grub_update() {
    if command_exists update-grub; then
        update-grub
        grub_cfg=/boot/grub/grub.cfg
    elif command_exists grub2-mkconfig; then
        grub_cfg=/boot/grub2/grub.cfg
        grub2-mkconfig -o "$grub_cfg"
    else
        grub_cfg=/boot/grub/grub.cfg
        grub-mkconfig -o "$grub_cfg"
    fi
}

write_custom_grub_entry() {
    local rel_dir kernel_line initrd_line
    rel_dir=$(grub-mkrelpath "$installer_directory" 2> /dev/null || grub2-mkrelpath "$installer_directory" 2> /dev/null || true)
    [ -n "${rel_dir:-}" ] || err 'Não foi possível calcular o caminho relativo para o GRUB'

    case "$installer_kind" in
        legacy)
            kernel_line="linux ${rel_dir}/linux auto=true priority=critical"
            initrd_line="initrd ${rel_dir}/initrd.gz"
            ;;
        live)
            kernel_line="linux ${rel_dir}/linux iso-url=${iso_url} autoinstall subiquity.autoinstallpath=autoinstall.yaml ip=dhcp ---"
            initrd_line="initrd ${rel_dir}/initrd"
            ;;
        *)
            err 'Tipo de instalador inválido'
            ;;
    esac

    cat > /etc/grub.d/09_osinstall_ubuntu <<EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry 'Ubuntu Installer' --id osinstall-ubuntu {
    insmod part_msdos
    insmod part_gpt
    insmod ext2
    insmod xfs
    insmod btrfs
    ${kernel_line}
    ${initrd_line}
}
EOF
    chmod +x /etc/grub.d/09_osinstall_ubuntu
}

create_workdir() {
    installer_directory="/boot/ubuntu-${ubuntu_series}"
    rm -rf "$installer_directory"
    mkdir -p "$installer_directory"
    cd "$installer_directory"
}

ensure_iso_extractor() {
    if command_exists xorriso || command_exists bsdtar || command_exists 7z; then
        return
    fi

    if command_exists apt-get; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y xorriso
        command_exists xorriso && return
    fi

    err 'Não foi possível encontrar ou instalar uma ferramenta para extrair arquivos de ISO (xorriso, bsdtar ou 7z)'
}

extract_from_iso() {
    local iso_file=$1
    local source_path=$2
    local output_path=$3

    if command_exists xorriso; then
        xorriso -osirrox on -indev "$iso_file" -extract "$source_path" "$output_path" > /dev/null 2>&1
    elif command_exists bsdtar; then
        bsdtar -xOf "$iso_file" "${source_path#/}" > "$output_path"
    elif command_exists 7z; then
        7z e -y -so "$iso_file" "${source_path#/}" > "$output_path"
    else
        err 'Nenhuma ferramenta de extração de ISO está disponível'
    fi
}

convert_initrd_to_plain_cpio() {
    local source=$1
    local target=$2
    local file_type
    file_type=$(file -b "$source")

    case "$file_type" in
        *"cpio archive"*)
            cp "$source" "$target"
            ;;
        *"gzip compressed"*)
            gzip -dc "$source" > "$target"
            ;;
        *"XZ compressed"*)
            xz -dc "$source" > "$target"
            ;;
        *"Zstandard compressed"*)
            command_exists zstd || err 'O initrd está em zstd e o sistema não possui zstd'
            zstd -dc "$source" > "$target"
            ;;
        *"LZ4 compressed"*)
            command_exists lz4 || err 'O initrd está em lz4 e o sistema não possui lz4'
            lz4 -dc "$source" > "$target"
            ;;
        *)
            err "Formato do initrd não reconhecido: $file_type"
            ;;
    esac
}

append_file_to_cpio() {
    local archive_file=$1
    local source_file=$2
    local source_name
    source_name=$(basename "$source_file")

    local tmpdir
    tmpdir=$(mktemp -d)
    cp "$source_file" "$tmpdir/$source_name"
    (
        cd "$tmpdir"
        printf '%s\n' "$source_name" | cpio -o -H newc -A -F "$archive_file" > /dev/null 2>&1
    )
    rm -rf "$tmpdir"
}

build_legacy_preseed() {
    cat > preseed.cfg <<EOF
d-i debian-installer/language string en
d-i debian-installer/country string US
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us

d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string ${hostname_short}
d-i netcfg/get_domain string

d-i mirror/country string manual
d-i mirror/http/hostname string archive.ubuntu.com
d-i mirror/http/directory string /ubuntu
d-i mirror/http/proxy string
d-i mirror/suite string bionic
d-i mirror/udeb/suite string bionic

d-i clock-setup/utc boolean true
d-i time/zone string America/Sao_Paulo
d-i clock-setup/ntp boolean true

d-i passwd/root-login boolean true
d-i passwd/make-user boolean false
d-i passwd/root-password-crypted password ${password_hash}

d-i partman-auto/method string regular
d-i partman-auto/disk string ${target_disk}
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

tasksel tasksel/first multiselect standard
d-i pkgsel/include string openssh-server
d-i pkgsel/upgrade select full-upgrade

d-i grub-installer/bootdev string ${target_disk}
d-i finish-install/reboot_in_progress note
EOF
}

prepare_legacy_installer() {
    printf "\n\033[1;36mBaixando o Ubuntu 18.04 legacy netboot...\033[0m\n"
    download "$linux_url" linux
    download "$initrd_url" initrd.gz
    gzip -d initrd.gz
    build_legacy_preseed
    append_file_to_cpio initrd preseed.cfg
    gzip -1 initrd
}

build_autoinstall_yaml() {
    cat > autoinstall.yaml <<EOF
version: 1
locale: en_US.UTF-8
keyboard:
  layout: us
timezone: America/Sao_Paulo
storage:
  layout:
    name: direct
identity:
  hostname: ${hostname_short}
  username: admin
  password: ${password_hash}
ssh:
  install-server: true
  allow-pw: true
updates: security
late-commands:
  - curtin in-target --target=/target -- /bin/bash -c "usermod -p '${password_hash}' root"
  - curtin in-target --target=/target -- /bin/bash -c "sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config"
  - curtin in-target --target=/target -- /bin/bash -c "sed -ri 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config"
  - curtin in-target --target=/target -- /bin/bash -c "systemctl enable ssh || true"
EOF
}

prepare_live_installer() {
    ensure_iso_extractor
    printf "\n\033[1;36mBaixando a ISO oficial do Ubuntu %s...\033[0m\n" "$ubuntu_version"
    download "$iso_url" installer.iso

    printf "\n\033[1;36mExtraindo kernel e initrd da ISO...\033[0m\n"
    extract_from_iso installer.iso /casper/vmlinuz linux
    extract_from_iso installer.iso /casper/initrd initrd.raw
    convert_initrd_to_plain_cpio initrd.raw initrd
    rm -f initrd.raw installer.iso

    build_autoinstall_yaml
    append_file_to_cpio initrd autoinstall.yaml
}

final_message_and_reboot() {
    printf "\n\033[1;32m═══════════════════════════════════════════════\033[0m\n"
    printf "\033[1;37m%23s%s%-14s\033[0m\n" "UBUNTU PRONTO"
    printf "\033[1;32m═══════════════════════════════════════════════\033[0m\n"
    printf "\n\033[0;37mA entrada do instalador foi criada no GRUB.\033[0m\n"
    printf "\033[0;37mNa próxima inicialização, o sistema vai formatar o disco e instalar o Ubuntu %s.\033[0m\n" "$ubuntu_version"
    printf "\n\033[1;31mEnter continuar ou CTRL+C cancelar: \033[0m"
    read -r _
    reboot
}

main() {
    require_root
    detect_architecture
    select_version
    set_release_urls
    detect_hostname
    detect_boot_disk
    prompt_password
    mk_hash
    ensure_grub_tools
    create_workdir

    case "$installer_kind" in
        legacy)
            prepare_legacy_installer
            ;;
        live)
            prepare_live_installer
            ;;
        *)
            err 'Tipo de instalador inválido'
            ;;
    esac

    setup_grub_defaults
    write_custom_grub_entry
    run_grub_update
    final_message_and_reboot
}

main "$@"
