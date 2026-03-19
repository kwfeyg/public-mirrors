#!/bin/bash

set -eu

err() {
    printf "\nErro: %s.\n" "$1" 1>&2
    exit 1
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
    printf "\n\033[1;36m═══════════════════════════════════════════════════════\033[0m\n"
    printf "\033[1;37m%28s%s%-12s\033[0m\n" "WINDOWS SERVER INSTALLER"
    printf "\033[1;36m═══════════════════════════════════════════════════════\033[0m\n"
    printf "\033[0;37mReinstalação completa do disco via Windows Setup em RAM.\033[0m\n"
    printf "\033[0;37mModo atual: Standard Evaluation com Desktop Experience.\033[0m\n\n"
}

select_version() {
    while true; do
        banner
        printf "\033[1;32m  [1]\033[0m Windows Server 2019 Standard Eval\n"
        printf "\033[1;32m  [2]\033[0m Windows Server 2022 Standard Eval\n"
        printf "\033[1;32m  [3]\033[0m Windows Server 2025 Standard Eval\n\n"
        printf "\033[1;33mEscolha a versão: \033[0m"
        read -r selected

        case "${selected:-}" in
            1)
                windows_version=2019
                windows_slug=ws2019
                iso_url="https://software-download.microsoft.com/download/sg/17763.253.190108-0006.rs5_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
                image_index=2
                break
                ;;
            2)
                windows_version=2022
                windows_slug=ws2022
                iso_url="https://software-static.download.prss.microsoft.com/sg/download/888969d5-f34g-4e03-ac9d-1f9786c66749/SERVER_EVAL_x64FRE_en-us.iso"
                image_index=2
                break
                ;;
            3)
                windows_version=2025
                windows_slug=ws2025
                iso_url="https://software-static.download.prss.microsoft.com/dbazure/888969d5-f34g-4e03-ac9d-1f9786c66749/26100.1742.240906-0331.ge_release_svc_refresh_SERVER_EVAL_x64FRE_en-us.iso"
                image_index=2
                break
                ;;
            *)
                printf "\n\033[1;31mOpção inválida.\033[0m\n"
                sleep 2
                ;;
        esac
    done
}

prompt_password() {
    while true; do
        printf "\033[1;33mSenha do Administrator no novo Windows: \033[0m"
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

detect_architecture() {
    case "$(uname -m)" in
        x86_64|amd64) ;;
        *) err 'O instalador Windows atual suporta apenas x86_64/amd64' ;;
    esac
}

check_memory() {
    local mem_kb
    mem_kb=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
    [ -n "${mem_kb:-}" ] || err 'Não foi possível detectar a memória total'
    [ "$mem_kb" -ge 6291456 ] || err 'Para o instalador Windows, use no mínimo 6 GB de RAM'
}

detect_firmware() {
    if [ -d /sys/firmware/efi ]; then
        firmware_mode=uefi
    else
        firmware_mode=bios
    fi
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

ensure_grub_tools() {
    if command_exists update-grub || command_exists grub-mkconfig || command_exists grub2-mkconfig; then
        return
    fi
    err 'Não foi possível encontrar update-grub, grub-mkconfig ou grub2-mkconfig'
}

setup_grub_defaults() {
    mkdir -p /etc/default/grub.d
    cat > /etc/default/grub.d/zz-osinstall-windows.cfg <<EOF
GRUB_DEFAULT=osinstall-windows
GRUB_TIMEOUT=5
EOF
}

run_grub_update() {
    if command_exists update-grub; then
        update-grub
    elif command_exists grub2-mkconfig; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        grub-mkconfig -o /boot/grub/grub.cfg
    fi
}

create_workdir() {
    installer_directory="/boot/windows-${windows_slug}"
    cached_iso="/tmp/windows-${windows_slug}.iso"
    if [ -f "$installer_directory/installer.iso" ] && [ ! -f "$cached_iso" ]; then
        cp "$installer_directory/installer.iso" "$cached_iso"
    fi
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

extract_optional_from_iso() {
    local iso_file=$1
    local source_path=$2
    local output_path=$3
    if extract_from_iso "$iso_file" "$source_path" "$output_path" 2> /dev/null; then
        return 0
    fi
    return 1
}

prepare_media() {
    ensure_iso_extractor

    if [ -f "$cached_iso" ] && [ ! -f installer.iso ]; then
        cp "$cached_iso" installer.iso
    fi

    if [ -f installer.iso ] && [ -s installer.iso ]; then
        printf "\n\033[1;36mReutilizando a ISO já baixada do Windows Server %s...\033[0m\n" "$windows_version"
    else
        printf "\n\033[1;36mBaixando a ISO oficial do Windows Server %s...\033[0m\n" "$windows_version"
        download "$iso_url" installer.iso
    fi

    printf "\n\033[1;36mBaixando o wimboot oficial...\033[0m\n"
    download "https://github.com/ipxe/wimboot/releases/latest/download/wimboot" wimboot

    printf "\n\033[1;36mExtraindo os arquivos de boot do Windows...\033[0m\n"
    extract_from_iso installer.iso /sources/boot.wim boot.wim
    if extract_optional_from_iso installer.iso /sources/install.wim install.wim; then
        install_image_name=install.wim
    elif extract_optional_from_iso installer.iso /sources/install.esd install.esd; then
        install_image_name=install.esd
    else
        err 'Não foi possível localizar install.wim ou install.esd na ISO'
    fi
    extract_from_iso installer.iso /boot/BCD BCD
    extract_from_iso installer.iso /boot/boot.sdi boot.sdi
}

build_startnet() {
    cat > startnet.cmd <<'EOF'
@echo off
wpeinit
ping -n 3 127.0.0.1 >nul
if exist X:\sources\setup.exe (
  X:\sources\setup.exe /unattend:X:\Windows\System32\autounattend.xml
  exit /b
)
if exist X:\setup.exe (
  X:\setup.exe /unattend:X:\Windows\System32\autounattend.xml
  exit /b
)
EOF
}

build_autounattend() {
    local windows_partition_id
    local partition_block

    if [ "$firmware_mode" = uefi ]; then
        windows_partition_id=3
        partition_block=$(cat <<'EOF'
                <CreatePartitions>
                    <CreatePartition wcm:action="add">
                        <Order>1</Order>
                        <Type>EFI</Type>
                        <Size>100</Size>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                        <Order>2</Order>
                        <Type>MSR</Type>
                        <Size>16</Size>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                        <Order>3</Order>
                        <Type>Primary</Type>
                        <Extend>true</Extend>
                    </CreatePartition>
                </CreatePartitions>
                <ModifyPartitions>
                    <ModifyPartition wcm:action="add">
                        <Order>1</Order>
                        <PartitionID>1</PartitionID>
                        <Format>FAT32</Format>
                        <Label>System</Label>
                    </ModifyPartition>
                    <ModifyPartition wcm:action="add">
                        <Order>2</Order>
                        <PartitionID>3</PartitionID>
                        <Format>NTFS</Format>
                        <Label>Windows</Label>
                        <Letter>C</Letter>
                    </ModifyPartition>
                </ModifyPartitions>
EOF
)
    else
        windows_partition_id=2
        partition_block=$(cat <<'EOF'
                <CreatePartitions>
                    <CreatePartition wcm:action="add">
                        <Order>1</Order>
                        <Type>Primary</Type>
                        <Size>500</Size>
                    </CreatePartition>
                    <CreatePartition wcm:action="add">
                        <Order>2</Order>
                        <Type>Primary</Type>
                        <Extend>true</Extend>
                    </CreatePartition>
                </CreatePartitions>
                <ModifyPartitions>
                    <ModifyPartition wcm:action="add">
                        <Order>1</Order>
                        <PartitionID>1</PartitionID>
                        <Format>NTFS</Format>
                        <Label>System</Label>
                        <Active>true</Active>
                    </ModifyPartition>
                    <ModifyPartition wcm:action="add">
                        <Order>2</Order>
                        <PartitionID>2</PartitionID>
                        <Format>NTFS</Format>
                        <Label>Windows</Label>
                        <Letter>C</Letter>
                    </ModifyPartition>
                </ModifyPartitions>
EOF
)
    fi

    cat > autounattend.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend">
    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <SetupUILanguage>
                <UILanguage>en-US</UILanguage>
            </SetupUILanguage>
            <InputLocale>en-US</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>0</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
${partition_block}
                </Disk>
            </DiskConfiguration>
            <ImageInstall>
                <OSImage>
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/INDEX</Key>
                            <Value>${image_index}</Value>
                        </MetaData>
                        <Path>X:\Windows\System32\${install_image_name}</Path>
                    </InstallFrom>
                    <InstallTo>
                        <DiskID>0</DiskID>
                        <PartitionID>${windows_partition_id}</PartitionID>
                    </InstallTo>
                    <WillShowUI>OnError</WillShowUI>
                </OSImage>
            </ImageInstall>
            <UserData>
                <AcceptEula>true</AcceptEula>
                <FullName>Administrator</FullName>
                <Organization>VPS</Organization>
            </UserData>
        </component>
    </settings>
    <settings pass="oobeSystem">
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <InputLocale>en-US</InputLocale>
            <SystemLocale>en-US</SystemLocale>
            <UILanguage>en-US</UILanguage>
            <UserLocale>en-US</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
            <AutoLogon>
                <Enabled>true</Enabled>
                <LogonCount>1</LogonCount>
                <Username>Administrator</Username>
                <Password>
                    <Value>${password}</Value>
                    <PlainText>true</PlainText>
                </Password>
            </AutoLogon>
            <UserAccounts>
                <AdministratorPassword>
                    <Value>${password}</Value>
                    <PlainText>true</PlainText>
                </AdministratorPassword>
            </UserAccounts>
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <FirstLogonCommands>
                <SynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <CommandLine>cmd /c net user Administrator /active:yes</CommandLine>
                    <Description>Enable Administrator</Description>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <CommandLine>cmd /c reg add "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" /v fDenyTSConnections /t REG_DWORD /d 0 /f</CommandLine>
                    <Description>Enable RDP</Description>
                </SynchronousCommand>
                <SynchronousCommand wcm:action="add">
                    <Order>3</Order>
                    <CommandLine>cmd /c netsh advfirewall firewall set rule group="remote desktop" new enable=Yes</CommandLine>
                    <Description>Open RDP Firewall</Description>
                </SynchronousCommand>
            </FirstLogonCommands>
        </component>
    </settings>
</unattend>
EOF
}

write_custom_grub_entry() {
    local rel_dir
    rel_dir=$(grub-mkrelpath "$installer_directory" 2> /dev/null || grub2-mkrelpath "$installer_directory" 2> /dev/null || true)
    [ -n "${rel_dir:-}" ] || err 'Não foi possível calcular o caminho relativo para o GRUB'

    cat > /etc/grub.d/09_osinstall_windows <<EOF
#!/bin/sh
exec tail -n +3 \$0
menuentry 'Windows Server Installer' --id osinstall-windows {
    insmod part_msdos
    insmod part_gpt
    insmod ext2
    insmod ntfs
    linux ${rel_dir}/wimboot index=2 gui
    initrd \\
      newc:/BCD:${rel_dir}/BCD \\
      newc:/boot.sdi:${rel_dir}/boot.sdi \\
      newc:/boot.wim:${rel_dir}/boot.wim \\
      newc:/${install_image_name}:${rel_dir}/${install_image_name} \\
      newc:/Windows/System32/startnet.cmd:${rel_dir}/startnet.cmd \\
      newc:/Windows/System32/autounattend.xml:${rel_dir}/autounattend.xml
}
EOF
    chmod +x /etc/grub.d/09_osinstall_windows
}

final_message_and_reboot() {
    printf "\n\033[1;32m═══════════════════════════════════════════════\033[0m\n"
    printf "\033[1;37m%23s%s%-14s\033[0m\n" "WINDOWS PRONTO"
    printf "\033[1;32m═══════════════════════════════════════════════\033[0m\n"
    printf "\n\033[0;37mA entrada do instalador Windows foi criada no GRUB.\033[0m\n"
    printf "\033[0;37mNa próxima inicialização, o sistema vai formatar o disco e instalar o Windows Server %s.\033[0m\n" "$windows_version"
    printf "\n\033[1;31mEnter continuar ou CTRL+C cancelar: \033[0m"
    read -r _
    reboot
}

main() {
    require_root
    detect_architecture
    check_memory
    select_version
    prompt_password
    detect_firmware
    detect_boot_disk
    ensure_grub_tools
    create_workdir
    prepare_media
    build_startnet
    build_autounattend
    setup_grub_defaults
    write_custom_grub_entry
    run_grub_update
    final_message_and_reboot
}

main "$@"
