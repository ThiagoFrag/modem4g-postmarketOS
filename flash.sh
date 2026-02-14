#!/bin/bash
# ============================================================================
#  flash.sh - Flash automatizado de postmarketOS em modems 4G USB (MSM8916)
#
#  Modems compatíveis: UFI001C, UFI001B, UFI003, MF601, UZ801 V3, JZ0145 V33
#  SoC: Qualcomm Snapdragon 410/412 (MSM8916)
#
#  Uso:
#    ./flash.sh                      # Modo interativo (pergunta tudo)
#    ./flash.sh --auto               # Detecta tudo automaticamente
#    ./flash.sh --backup-only        # Apenas faz backup
#    ./flash.sh --restore            # Restaura firmware original
#    ./flash.sh --status             # Verifica estado do modem
#
#  Baseado no projeto msm8916-mainline e no vídeo do VegaData
#  https://github.com/ThiagoFrag/modem4g-postmarketOS
# ============================================================================
set -euo pipefail

# ─── Cores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─── Configuração ───────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${WORK_DIR:-$HOME/modem4g-flash}"
BACKUP_DIR="$WORK_DIR/backups"
FIRMWARE_DIR="$WORK_DIR/firmware"
BUILD_DIR="$WORK_DIR/build"

# URLs dos repositórios
LK2ND_REPO="https://github.com/nicknisi/lk2nd.git"
LK2ND_REPO_OFFICIAL="https://github.com/nicknisi/lk2nd.git"
QHYPSTUB_REPO="https://github.com/nicknisi/qhypstub.git"
QTESTSIGN_REPO="https://github.com/nicknisi/qtestsign.git"
EDL_REPO="https://github.com/bkerler/edl.git"
DB410C_FW_URL="https://releases.linaro.org/96boards/dragonboard410c/linaro/rescue/latest/dragonboard-410c-bootloader-emmc-linux-176.zip"

# Modems suportados
declare -A MODEM_TARGETS=(
    ["ufi001c"]="thwc,ufi001c"
    ["ufi001b"]="thwc,ufi001c"
    ["ufi003"]="zhihe,various"
    ["mf601"]="zhihe,various"
    ["uz801"]="yiming,uz801-v3"
    ["jz0145"]="xiaoxun,jz0145-v33"
    ["generico"]="zhihe,various"
)

# Qualcomm IDs
QDL_VID="05c6"
QDL_PID="9008"
FASTBOOT_VID="18d1"
FASTBOOT_PID="d00d"

# ─── Funções de UI ──────────────────────────────────────────────────────────

banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
    ╔══════════════════════════════════════════════════════════════╗
    ║                                                              ║
    ║   ███╗   ███╗ ██████╗ ██████╗ ███████╗███╗   ███╗██╗  ██╗   ║
    ║   ████╗ ████║██╔═══██╗██╔══██╗██╔════╝████╗ ████║██║  ██║   ║
    ║   ██╔████╔██║██║   ██║██║  ██║█████╗  ██╔████╔██║███████║   ║
    ║   ██║╚██╔╝██║██║   ██║██║  ██║██╔══╝  ██║╚██╔╝██║╚════██║   ║
    ║   ██║ ╚═╝ ██║╚██████╔╝██████╔╝███████╗██║ ╚═╝ ██║     ██║   ║
    ║   ╚═╝     ╚═╝ ╚═════╝ ╚═════╝ ╚══════╝╚═╝     ╚═╝     ╚═╝   ║
    ║                                                              ║
    ║       postmarketOS em Modem 4G USB (MSM8916)                ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

log_info()    { echo -e "  ${BLUE}ℹ${NC}  $*"; }
log_ok()      { echo -e "  ${GREEN}✓${NC}  $*"; }
log_warn()    { echo -e "  ${YELLOW}⚠${NC}  $*"; }
log_error()   { echo -e "  ${RED}✗${NC}  $*"; }
log_step()    { echo -e "\n${BOLD}${MAGENTA}▶ $*${NC}"; }
log_substep() { echo -e "  ${DIM}→${NC} $*"; }

progress_bar() {
    local current=$1 total=$2 width=40
    local pct=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    printf "\r  ${CYAN}[${NC}"
    printf "%${filled}s" '' | tr ' ' '█'
    printf "%${empty}s" '' | tr ' ' '░'
    printf "${CYAN}]${NC} %3d%%" "$pct"
    [[ $current -eq $total ]] && echo ""
}

confirm() {
    local msg="${1:-Continuar?}"
    echo -en "\n  ${YELLOW}?${NC}  ${msg} ${DIM}[S/n]${NC} "
    read -r resp
    [[ -z "$resp" || "$resp" =~ ^[sSyY] ]]
}

spinner() {
    local pid=$1 msg="${2:-Aguarde...}"
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while kill -0 "$pid" 2>/dev/null; do
        for (( i=0; i<${#chars}; i++ )); do
            printf "\r  ${CYAN}${chars:$i:1}${NC}  %s" "$msg"
            sleep 0.1
        done
    done
    printf "\r%*s\r" $((${#msg} + 6)) ""
}

# ─── Verificações ───────────────────────────────────────────────────────────

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script precisa rodar como ${BOLD}root${NC}"
        log_info "Use: ${BOLD}sudo ./flash.sh${NC}"
        exit 1
    fi
}

detect_distro() {
    if command -v pacman &>/dev/null; then
        echo "arch"
    elif command -v apt &>/dev/null; then
        echo "debian"
    elif command -v dnf &>/dev/null; then
        echo "fedora"
    else
        echo "unknown"
    fi
}

install_deps() {
    log_step "Verificando dependências..."
    local distro
    distro=$(detect_distro)
    local missing=()

    # Ferramentas essenciais
    local tools=(git python3 fastboot adb gcc dtc wget unzip ssh sshpass)
    local cross_arm="arm-none-eabi-gcc"
    local cross_aarch64="aarch64-linux-gnu-gcc"

    for tool in "${tools[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done
    command -v "$cross_arm" &>/dev/null || missing+=("$cross_arm")
    command -v "$cross_aarch64" &>/dev/null || missing+=("$cross_aarch64")

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_ok "Todas as dependências instaladas"
        return 0
    fi

    log_warn "Faltam: ${missing[*]}"

    case "$distro" in
        arch)
            log_substep "Instalando via pacman..."
            pacman -S --noconfirm --needed \
                git python python-pip android-tools dtc wget unzip \
                openssh sshpass arm-none-eabi-gcc aarch64-linux-gnu-gcc \
                make 2>/dev/null || true
            ;;
        debian)
            log_substep "Instalando via apt..."
            apt update -qq
            apt install -y -qq \
                git python3 python3-pip python3-dev adb fastboot \
                device-tree-compiler wget unzip openssh-client sshpass \
                gcc-arm-none-eabi gcc-aarch64-linux-gnu make 2>/dev/null || true
            ;;
        fedora)
            log_substep "Instalando via dnf..."
            dnf install -y \
                git python3 python3-pip android-tools dtc wget unzip \
                openssh-clients sshpass arm-none-eabi-gcc-cs \
                gcc-aarch64-linux-gnu make 2>/dev/null || true
            ;;
        *)
            log_error "Distro não reconhecida. Instale manualmente:"
            log_info "  ${missing[*]}"
            exit 1
            ;;
    esac

    # EDL tool
    if ! command -v edl &>/dev/null && [[ ! -x "$WORK_DIR/edl/edl" ]]; then
        install_edl
    fi

    log_ok "Dependências instaladas"
}

install_edl() {
    log_substep "Instalando EDL tool (bkerler)..."
    if [[ ! -d "$WORK_DIR/edl" ]]; then
        git clone --depth 1 "$EDL_REPO" "$WORK_DIR/edl" 2>/dev/null
        cd "$WORK_DIR/edl"
        git submodule update --init --recursive 2>/dev/null
    fi
    cd "$WORK_DIR/edl"
    pip3 install -r requirements.txt --break-system-packages 2>/dev/null || \
    pip3 install -r requirements.txt 2>/dev/null || true

    # Instalar globalmente
    pip3 install . --break-system-packages 2>/dev/null || \
    pip3 install . 2>/dev/null || true

    # Configurar udev
    if [[ -d /etc/udev/rules.d ]]; then
        cat > /etc/udev/rules.d/99-edl.rules << 'UDEV'
# Qualcomm EDL (QDL mode)
SUBSYSTEM=="usb", ATTR{idVendor}=="05c6", ATTR{idProduct}=="9008", MODE="0666", ENV{ID_MM_DEVICE_IGNORE}="1"
# Android Fastboot
SUBSYSTEM=="usb", ATTR{idVendor}=="18d1", ATTR{idProduct}=="d00d", MODE="0666"
UDEV
        udevadm control --reload-rules 2>/dev/null || true
        udevadm trigger 2>/dev/null || true
    fi
}

find_edl() {
    # Procurar EDL em vários locais
    local edl_paths=(
        "$(command -v edl 2>/dev/null)"
        "$HOME/.local/bin/edl"
        "$WORK_DIR/edl/edl"
        "/usr/local/bin/edl"
    )
    for p in "${edl_paths[@]}"; do
        [[ -n "$p" && -x "$p" ]] && echo "$p" && return 0
    done
    # Tentar via python
    if python3 -c "import edlclient" 2>/dev/null; then
        echo "edl"
        return 0
    fi
    return 1
}

find_loader() {
    # Procurar firehose loader para MSM8916
    local search_paths=(
        "$WORK_DIR"
        "$SCRIPT_DIR"
        "$HOME"
        "/tmp"
    )
    for base in "${search_paths[@]}"; do
        local found
        found=$(find "$base" -maxdepth 5 -name "prog_emmc_firehose_8916*" -type f 2>/dev/null | head -1)
        [[ -n "$found" ]] && echo "$found" && return 0
    done
    return 1
}

# ─── Detecção do Modem ─────────────────────────────────────────────────────

detect_modem_mode() {
    if lsusb 2>/dev/null | grep -qi "${QDL_VID}:${QDL_PID}"; then
        echo "edl"
    elif lsusb 2>/dev/null | grep -qi "${FASTBOOT_VID}:${FASTBOOT_PID}"; then
        echo "fastboot"
    elif ip addr 2>/dev/null | grep -q "172.16.42"; then
        echo "linux"
    elif adb devices 2>/dev/null | grep -q "device$"; then
        echo "android"
    else
        echo "none"
    fi
}

wait_for_mode() {
    local target_mode=$1
    local timeout=${2:-60}
    local msg=${3:-"Aguardando modem..."}
    local elapsed=0

    echo -en "  ${CYAN}⏳${NC}  ${msg}"
    while [[ $elapsed -lt $timeout ]]; do
        local mode
        mode=$(detect_modem_mode)
        if [[ "$mode" == "$target_mode" ]]; then
            echo -e " ${GREEN}detectado!${NC}"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo -en "."
    done
    echo -e " ${RED}timeout!${NC}"
    return 1
}

identify_modem() {
    log_step "Identificando modem..."
    local mode
    mode=$(detect_modem_mode)

    case "$mode" in
        edl)
            log_ok "Modem em modo ${BOLD}EDL${NC} (Qualcomm 9008)"
            ;;
        fastboot)
            log_ok "Modem em modo ${BOLD}Fastboot${NC}"
            ;;
        linux)
            log_ok "Modem rodando ${BOLD}Linux${NC} (postmarketOS)"
            ;;
        android)
            log_ok "Modem rodando ${BOLD}Android${NC}"
            # Tentar pegar info via ADB
            local model
            model=$(adb shell getprop ro.product.model 2>/dev/null || echo "desconhecido")
            log_info "Modelo: $model"
            ;;
        *)
            log_error "Nenhum modem detectado!"
            echo ""
            log_info "Conecte o modem em modo EDL:"
            log_info "  1. Desconecte o modem"
            log_info "  2. Segure o botão EDL (test point na placa)"
            log_info "  3. Conecte o modem mantendo o botão"
            log_info "  4. Solte o botão"
            return 1
            ;;
    esac
    echo "$mode"
}

select_modem_model() {
    echo ""
    echo -e "  ${BOLD}Selecione o modelo do seu modem:${NC}"
    echo ""
    echo -e "    ${CYAN}1${NC}) UFI-001C / UFI-001B"
    echo -e "    ${CYAN}2${NC}) UFI-003 / MF601 / Genérico"
    echo -e "    ${CYAN}3${NC}) UZ801 V3.0"
    echo -e "    ${CYAN}4${NC}) JZ0145 V33"
    echo -e "    ${CYAN}5${NC}) Não sei (usar genérico)"
    echo ""
    echo -en "  ${YELLOW}?${NC}  Escolha [1-5]: "
    read -r choice

    case "$choice" in
        1) echo "ufi001c" ;;
        2) echo "generico" ;;
        3) echo "uz801" ;;
        4) echo "jz0145" ;;
        *) echo "generico" ;;
    esac
}

# ─── Backup ─────────────────────────────────────────────────────────────────

do_backup() {
    log_step "Fazendo backup completo do modem..."
    local edl_bin loader backup_name backup_path

    edl_bin=$(find_edl) || { log_error "EDL não encontrado. Instale primeiro."; return 1; }
    loader=$(find_loader) || { log_error "Firehose loader não encontrado."; return 1; }

    backup_name="backup-$(date +%Y%m%d-%H%M%S)"
    backup_path="$BACKUP_DIR/$backup_name"
    mkdir -p "$backup_path"

    log_info "Salvando em: $backup_path"
    log_warn "Isso pode levar 10-20 minutos..."
    echo ""

    # Backup de todas as partições
    "$edl_bin" rl "$backup_path" --loader="$loader" 2>&1 | while IFS= read -r line; do
        if [[ "$line" == *"Progress"* ]]; then
            echo -en "\r  ${DIM}$line${NC}"
        elif [[ "$line" == *"Dumped"* || "$line" == *"Read"* ]]; then
            echo -e "\r  ${GREEN}✓${NC} $line"
        fi
    done
    echo ""

    # Verificar backup
    local n_files
    n_files=$(find "$backup_path" -name "*.bin" | wc -l)
    if [[ $n_files -gt 20 ]]; then
        log_ok "Backup completo: $n_files partições salvas"
        log_info "Caminho: ${BOLD}$backup_path${NC}"

        # Salvar info
        echo "Data: $(date)" > "$backup_path/backup-info.txt"
        echo "Partições: $n_files" >> "$backup_path/backup-info.txt"
        lsusb | grep -i "05c6\|18d1" >> "$backup_path/backup-info.txt" 2>/dev/null
    else
        log_error "Backup pode estar incompleto ($n_files partições)"
        return 1
    fi
}

# ─── Compilação ─────────────────────────────────────────────────────────────

compile_qhypstub() {
    log_substep "Compilando qhypstub..."
    local qhyp_dir="$BUILD_DIR/qhypstub"

    if [[ ! -d "$qhyp_dir" ]]; then
        git clone --depth 1 https://github.com/msm8916-mainline/qhypstub.git "$qhyp_dir" 2>/dev/null
    fi

    cd "$qhyp_dir"
    make CROSS_COMPILE=aarch64-linux-gnu- clean 2>/dev/null || true
    make CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" 2>/dev/null

    # Assinar com qtestsign
    local qts_dir="$BUILD_DIR/qtestsign"
    if [[ ! -d "$qts_dir" ]]; then
        git clone --depth 1 https://github.com/nicknisi/qtestsign.git "$qts_dir" 2>/dev/null || \
        git clone --depth 1 https://github.com/nicknisi/qtestsign.git "$qts_dir" 2>/dev/null
    fi
    # Tentar diferentes locais do qtestsign
    if [[ -f "$qts_dir/qtestsign.py" ]]; then
        python3 "$qts_dir/qtestsign.py" hyp "$qhyp_dir/qhypstub.mbn" 2>/dev/null
    elif command -v qtestsign &>/dev/null; then
        qtestsign hyp "$qhyp_dir/qhypstub.mbn" 2>/dev/null
    else
        # Compilar e usar o qtestsign do msm8916-mainline
        if [[ ! -d "$BUILD_DIR/msm-qtestsign" ]]; then
            git clone --depth 1 https://github.com/nicknisi/qtestsign.git "$BUILD_DIR/msm-qtestsign" 2>/dev/null
        fi
        python3 "$BUILD_DIR/msm-qtestsign/qtestsign.py" hyp "$qhyp_dir/qhypstub.mbn" 2>/dev/null || true
    fi

    local signed="$qhyp_dir/qhypstub-test-signed.mbn"
    if [[ ! -f "$signed" ]]; then
        signed="$qhyp_dir/qhypstub.mbn"
        log_warn "Usando qhypstub sem assinatura (pode funcionar)"
    fi

    cp "$signed" "$FIRMWARE_DIR/qhypstub.mbn"
    log_ok "qhypstub compilado"
}

compile_lk1st() {
    local target=$1
    log_substep "Compilando lk1st para ${BOLD}$target${NC}..."
    local lk_dir="$BUILD_DIR/lk2nd"

    if [[ ! -d "$lk_dir" ]]; then
        git clone --depth 1 https://github.com/nicknisi/lk2nd.git "$lk_dir" 2>/dev/null
        cd "$lk_dir"
        git submodule update --init --recursive 2>/dev/null
    fi

    cd "$lk_dir"
    make clean 2>/dev/null || true
    make TOOLCHAIN_PREFIX=arm-none-eabi- lk1st-msm8916 \
        LK2ND_BUNDLE_DTB="msm8916-512mb-mtp.dtb" \
        LK2ND_COMPATIBLE="$target" \
        -j"$(nproc)" 2>/dev/null

    local output="$lk_dir/build-lk1st-msm8916/emmc_appsboot.mbn"
    if [[ -f "$output" ]]; then
        cp "$output" "$FIRMWARE_DIR/lk1st.mbn"
        log_ok "lk1st compilado para $target"
    else
        log_error "Falha ao compilar lk1st!"
        return 1
    fi
}

download_db410c_firmware() {
    log_substep "Baixando firmware DragonBoard 410c..."
    local fw_zip="$WORK_DIR/db410c-fw.zip"

    if [[ ! -f "$FIRMWARE_DIR/tz.mbn" ]]; then
        wget -q --show-progress -O "$fw_zip" "$DB410C_FW_URL" 2>&1 || \
        wget -q -O "$fw_zip" "$DB410C_FW_URL" 2>&1

        local extract_dir
        extract_dir=$(mktemp -d)
        unzip -o "$fw_zip" -d "$extract_dir" 2>/dev/null

        # Encontrar os .mbn dentro do zip
        find "$extract_dir" -name "tz.mbn" -exec cp {} "$FIRMWARE_DIR/tz.mbn" \;
        find "$extract_dir" -name "sbl1.mbn" -exec cp {} "$FIRMWARE_DIR/sbl1.mbn" \;
        find "$extract_dir" -name "hyp.mbn" -exec cp {} "$FIRMWARE_DIR/hyp-db410c.mbn" \;
        rm -rf "$extract_dir" "$fw_zip"
    fi

    if [[ -f "$FIRMWARE_DIR/tz.mbn" ]]; then
        log_ok "Firmware DragonBoard 410c OK"
    else
        log_error "Falha ao baixar firmware!"
        return 1
    fi
}

generate_rootfs() {
    log_substep "Gerando imagem postmarketOS via pmbootstrap..."

    if ! command -v pmbootstrap &>/dev/null; then
        log_info "Instalando pmbootstrap..."
        pip3 install pmbootstrap --break-system-packages 2>/dev/null || \
        pipx install pmbootstrap 2>/dev/null || {
            log_error "Não foi possível instalar pmbootstrap"
            log_info "Instale manualmente: pipx install pmbootstrap"
            return 1
        }
    fi

    # Verificar se já existe uma imagem
    local existing
    existing=$(find "$WORK_DIR" "$HOME" -maxdepth 3 -name "generic-zhihe-raw.img" -o -name "generic-zhihe.img" 2>/dev/null | head -1)
    if [[ -n "$existing" ]]; then
        log_ok "Imagem encontrada: $existing"
        cp "$existing" "$FIRMWARE_DIR/rootfs.img"
        return 0
    fi

    # TODO: automação do pmbootstrap init + install
    log_warn "Imagem rootfs não encontrada!"
    log_info "Gere manualmente:"
    log_info "  pmbootstrap init        # device: generic-zhihe, UI: console"
    log_info "  pmbootstrap install --filesystem btrfs"
    log_info "Depois copie a imagem .img para: $FIRMWARE_DIR/rootfs.img"
    return 1
}

# ─── Flash via EDL ──────────────────────────────────────────────────────────

flash_edl() {
    local edl_bin loader
    edl_bin=$(find_edl) || { log_error "EDL não encontrado!"; return 1; }
    loader=$(find_loader) || { log_error "Firehose loader não encontrado!"; return 1; }

    local hyp_img="$FIRMWARE_DIR/qhypstub.mbn"
    local tz_img="$FIRMWARE_DIR/tz.mbn"
    local aboot_img="$FIRMWARE_DIR/lk1st.mbn"
    local rootfs_img="$FIRMWARE_DIR/rootfs.img"

    # Verificar todos os arquivos
    log_step "Verificando arquivos para flash..."
    local all_ok=true
    for f in "$hyp_img" "$tz_img" "$aboot_img" "$rootfs_img"; do
        if [[ -f "$f" ]]; then
            log_ok "$(basename "$f") ($(du -h "$f" | cut -f1))"
        else
            log_error "FALTA: $(basename "$f")"
            all_ok=false
        fi
    done
    [[ "$all_ok" == "false" ]] && return 1

    log_step "Flasheando partições via EDL..."
    echo ""

    # 1. hyp
    echo -e "  ${CYAN}[1/5]${NC} Flasheando ${BOLD}hyp${NC} (qhypstub)..."
    "$edl_bin" w hyp "$hyp_img" --loader="$loader" 2>&1 | tail -1
    log_ok "hyp ✓"

    # 2. tz
    echo -e "  ${CYAN}[2/5]${NC} Flasheando ${BOLD}tz${NC} (TrustZone DragonBoard)..."
    "$edl_bin" w tz "$tz_img" --loader="$loader" 2>&1 | tail -1
    log_ok "tz ✓"

    # 3. aboot
    echo -e "  ${CYAN}[3/5]${NC} Flasheando ${BOLD}aboot${NC} (lk1st)..."
    "$edl_bin" w aboot "$aboot_img" --loader="$loader" 2>&1 | tail -1
    log_ok "aboot ✓"

    # 4. userdata (imagem MBR com boot+rootfs)
    local rootfs_size
    rootfs_size=$(du -h "$rootfs_img" | cut -f1)
    echo -e "  ${CYAN}[4/5]${NC} Flasheando ${BOLD}userdata${NC} (rootfs $rootfs_size)..."
    echo -e "         ${DIM}Isso pode levar 3-10 minutos...${NC}"
    "$edl_bin" w userdata "$rootfs_img" --loader="$loader" 2>&1 | \
        grep -E "Progress|Wrote" | while IFS= read -r line; do
            if [[ "$line" == *"Wrote"* ]]; then
                echo -e "\r  ${GREEN}✓${NC} $line"
            else
                echo -en "\r  ${DIM}${line}${NC}"
            fi
        done
    echo ""
    log_ok "userdata ✓"

    # 5. Reset
    echo -e "  ${CYAN}[5/5]${NC} Reiniciando modem..."
    "$edl_bin" reset --loader="$loader" 2>&1 || true
    log_ok "Reset enviado"
}

# ─── Restauração ────────────────────────────────────────────────────────────

do_restore() {
    log_step "Restaurar firmware original"

    # Listar backups disponíveis
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        # Procurar backups em outros locais
        local found_backup
        found_backup=$(find "$HOME" -maxdepth 4 -name "gpt_main0.bin" -type f 2>/dev/null | head -1)
        if [[ -n "$found_backup" ]]; then
            local bdir
            bdir=$(dirname "$found_backup")
            log_info "Backup encontrado em: $bdir"
        else
            log_error "Nenhum backup encontrado!"
            log_info "Sem backup, não é possível restaurar."
            return 1
        fi
    fi

    echo ""
    echo -e "  ${BOLD}Backups disponíveis:${NC}"
    local i=1
    local -a backup_list
    for d in "$BACKUP_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local n_files
        n_files=$(find "$d" -name "*.bin" | wc -l)
        echo -e "    ${CYAN}$i${NC}) $(basename "$d") ($n_files partições)"
        backup_list+=("$d")
        i=$((i + 1))
    done

    # Também procurar fora do BACKUP_DIR
    while IFS= read -r gpt; do
        local bdir
        bdir=$(dirname "$gpt")
        # Evitar duplicatas
        local skip=false
        for existing in "${backup_list[@]}"; do
            [[ "$bdir/" == "$existing" ]] && skip=true
        done
        [[ "$skip" == "true" ]] && continue
        local n_files
        n_files=$(find "$bdir" -name "*.bin" | wc -l)
        echo -e "    ${CYAN}$i${NC}) $bdir ($n_files partições)"
        backup_list+=("$bdir/")
        i=$((i + 1))
    done < <(find "$HOME" -maxdepth 5 -name "gpt_main0.bin" -type f 2>/dev/null)

    if [[ ${#backup_list[@]} -eq 0 ]]; then
        log_error "Nenhum backup encontrado!"
        return 1
    fi

    echo ""
    echo -en "  ${YELLOW}?${NC}  Escolha o backup [1-$((i-1))]: "
    read -r choice
    choice=${choice:-1}
    local selected="${backup_list[$((choice - 1))]}"

    log_info "Usando backup: $selected"

    if ! confirm "Restaurar firmware original? O Linux será apagado."; then
        log_info "Cancelado."
        return 0
    fi

    local edl_bin loader
    edl_bin=$(find_edl) || { log_error "EDL não encontrado!"; return 1; }
    loader=$(find_loader) || { log_error "Firehose loader não encontrado!"; return 1; }

    # Verificar modo EDL
    if [[ "$(detect_modem_mode)" != "edl" ]]; then
        log_warn "Modem não está em modo EDL!"
        log_info "Coloque o modem em modo EDL e pressione Enter..."
        read -r
        wait_for_mode "edl" 60 "Aguardando modo EDL..." || return 1
    fi

    log_step "Restaurando GPT..."
    "$edl_bin" w gpt "${selected}gpt_main0.bin" --loader="$loader" 2>&1 | tail -1

    log_step "Restaurando todas as partições..."
    log_warn "Isso pode levar 20+ minutos..."
    "$edl_bin" wf "$selected" --loader="$loader" 2>&1 | \
        grep -E "Progress|Wrote" | while IFS= read -r line; do
            echo -en "\r  ${DIM}${line:0:80}${NC}"
        done
    echo ""

    log_step "Reiniciando..."
    "$edl_bin" reset --loader="$loader" 2>&1 || true

    log_ok "Firmware original restaurado!"
    log_info "O modem deve voltar a funcionar como modem 4G normal."
}

# ─── Verificação Pós-Flash ──────────────────────────────────────────────────

post_flash_check() {
    log_step "Verificando boot do postmarketOS..."

    echo -e "  ${DIM}Aguardando modem reiniciar (pode levar até 60s)...${NC}"
    sleep 5

    if wait_for_mode "linux" 90 "Aguardando postmarketOS iniciar..."; then
        log_ok "postmarketOS está rodando!"
        echo ""

        # Verificar IP
        local modem_ip="172.16.42.1"
        if ping -c 1 -W 3 "$modem_ip" &>/dev/null; then
            log_ok "Ping OK: $modem_ip"
        else
            log_warn "Ping falhou. Aguarde mais um pouco..."
            sleep 10
            ping -c 1 -W 5 "$modem_ip" &>/dev/null && log_ok "Ping OK: $modem_ip"
        fi

        # Tentar SSH
        echo ""
        log_info "Para acessar o modem:"
        echo -e "    ${BOLD}ssh <usuario>@172.16.42.1${NC}"
        echo ""
        log_info "Senha: a que você definiu no pmbootstrap"
        echo ""

        return 0
    fi

    # Verificar se caiu em fastboot
    if [[ "$(detect_modem_mode)" == "fastboot" ]]; then
        log_warn "Modem entrou em fastboot em vez de iniciar o Linux"
        log_info "Isso pode significar que a imagem rootfs não é do tipo correto."
        log_info "A imagem precisa ser a ${BOLD}raw${NC} (MBR com boot+rootfs),"
        log_info "não apenas a partição rootfs separada."
        return 1
    fi

    log_error "Modem não iniciou postmarketOS."
    return 1
}

# ─── Status ─────────────────────────────────────────────────────────────────

show_status() {
    banner
    log_step "Status do modem"
    echo ""

    local mode
    mode=$(detect_modem_mode)

    case "$mode" in
        edl)
            echo -e "  Estado:  ${YELLOW}⬤${NC}  Modo EDL (Qualcomm 9008)"
            echo -e "  Ação:    Pronto para flash ou backup"
            ;;
        fastboot)
            echo -e "  Estado:  ${YELLOW}⬤${NC}  Modo Fastboot (lk1st)"
            echo -e "  Ação:    lk1st carregou mas não encontrou Linux"
            echo -e "  Fix:     Reflash com imagem raw (MBR boot+rootfs)"
            ;;
        linux)
            echo -e "  Estado:  ${GREEN}⬤${NC}  postmarketOS rodando"
            local modem_ip="172.16.42.1"
            if ping -c 1 -W 2 "$modem_ip" &>/dev/null; then
                echo -e "  IP:      $modem_ip"
                echo -e "  SSH:     ssh <user>@$modem_ip"

                # Tentar pegar info via SSH se sshpass estiver disponível
                if command -v sshpass &>/dev/null; then
                    echo ""
                    echo -en "  ${YELLOW}?${NC}  Senha SSH (Enter p/ pular): "
                    read -rs ssh_pass
                    echo ""
                    if [[ -n "$ssh_pass" ]]; then
                        echo ""
                        local info
                        info=$(sshpass -p "$ssh_pass" ssh -o StrictHostKeyChecking=no \
                            -o PreferredAuthentications=password \
                            -o PubkeyAuthentication=no \
                            "$modem_ip" \
                            "uname -a; echo '|||'; df -h /; echo '|||'; free -h | head -2; echo '|||'; cat /etc/os-release | grep PRETTY" 2>/dev/null)
                        if [[ -n "$info" ]]; then
                            IFS='|||' read -ra parts <<< "$info"
                            echo -e "  ${BOLD}Sistema:${NC}"
                            echo -e "  ${DIM}$(echo "${parts[0]}" | tr -s ' ')${NC}"
                        fi
                    fi
                fi
            fi
            ;;
        android)
            echo -e "  Estado:  ${BLUE}⬤${NC}  Android original"
            echo -e "  Ação:    Use 'adb reboot edl' para entrar em EDL"
            ;;
        *)
            echo -e "  Estado:  ${RED}⬤${NC}  Nenhum modem detectado"
            echo -e "  Ação:    Conecte o modem ou entre em modo EDL"
            ;;
    esac

    # Mostrar USB devices relevantes
    echo ""
    log_info "Dispositivos USB:"
    lsusb 2>/dev/null | grep -iE "qualcomm|05c6|18d1|google|android" | while read -r line; do
        echo -e "    ${DIM}$line${NC}"
    done

    echo ""
}

# ─── Fluxo Principal ───────────────────────────────────────────────────────

main_interactive() {
    banner

    echo -e "  ${BOLD}O que você quer fazer?${NC}"
    echo ""
    echo -e "    ${CYAN}1${NC}) ${BOLD}Flash completo${NC} (backup + compilar + flash postmarketOS)"
    echo -e "    ${CYAN}2${NC}) ${BOLD}Flash rápido${NC} (já tenho os arquivos compilados)"
    echo -e "    ${CYAN}3${NC}) ${BOLD}Apenas backup${NC} do firmware original"
    echo -e "    ${CYAN}4${NC}) ${BOLD}Restaurar${NC} firmware original (voltar pro Android)"
    echo -e "    ${CYAN}5${NC}) ${BOLD}Status${NC} do modem"
    echo -e "    ${CYAN}6${NC}) ${BOLD}Instalar dependências${NC}"
    echo -e "    ${CYAN}0${NC}) Sair"
    echo ""
    echo -en "  ${YELLOW}?${NC}  Escolha [0-6]: "
    read -r choice

    case "$choice" in
        1) full_flash ;;
        2) quick_flash ;;
        3) ensure_edl && do_backup ;;
        4) do_restore ;;
        5) show_status ;;
        6) install_deps ;;
        0) exit 0 ;;
        *) log_error "Opção inválida"; exit 1 ;;
    esac
}

ensure_edl() {
    local mode
    mode=$(detect_modem_mode)
    if [[ "$mode" == "edl" ]]; then
        return 0
    elif [[ "$mode" == "android" ]]; then
        log_info "Reiniciando modem em modo EDL via ADB..."
        adb reboot edl 2>/dev/null
        wait_for_mode "edl" 30 "Aguardando modo EDL..." || return 1
    else
        log_warn "Modem precisa estar em modo EDL!"
        echo ""
        log_info "  1. Desconecte o modem"
        log_info "  2. Segure o botão EDL (test point na placa)"
        log_info "  3. Conecte o modem mantendo o botão"
        log_info "  4. Pressione Enter quando pronto..."
        read -r
        wait_for_mode "edl" 30 "Aguardando modo EDL..." || return 1
    fi
}

full_flash() {
    log_step "Flash Completo do postmarketOS"
    echo ""

    # 1. Dependências
    install_deps

    # 2. Preparar diretórios
    mkdir -p "$WORK_DIR" "$BACKUP_DIR" "$FIRMWARE_DIR" "$BUILD_DIR"

    # 3. Selecionar modelo
    local model target
    model=$(select_modem_model)
    target="${MODEM_TARGETS[$model]}"
    log_ok "Modelo: ${BOLD}$model${NC} (target: $target)"

    # 4. Verificar modo EDL
    ensure_edl || return 1

    # 5. Backup
    if confirm "Fazer backup do firmware original? (RECOMENDADO)"; then
        do_backup || log_warn "Backup falhou, continuando..."
    fi

    # 6. Compilar firmware
    log_step "Compilando firmware..."
    download_db410c_firmware
    compile_qhypstub
    compile_lk1st "$target"

    # 7. Rootfs
    generate_rootfs || {
        log_error "Rootfs não disponível. Gere a imagem e rode novamente."
        return 1
    }

    # 8. Flash
    ensure_edl || return 1
    flash_edl

    # 9. Verificar
    post_flash_check
}

quick_flash() {
    log_step "Flash Rápido"
    echo ""

    mkdir -p "$FIRMWARE_DIR"

    # Procurar arquivos existentes
    log_info "Procurando arquivos de firmware..."

    # qhypstub
    local qhyp
    qhyp=$(find "$HOME" -maxdepth 4 \( -name "qhypstub-test-signed.mbn" -o -name "qhypstub.mbn" \) -type f 2>/dev/null | head -1)
    if [[ -n "$qhyp" ]]; then
        cp "$qhyp" "$FIRMWARE_DIR/qhypstub.mbn"
        log_ok "qhypstub: $qhyp"
    else
        log_error "qhypstub não encontrado!"
        return 1
    fi

    # tz.mbn
    local tz
    tz=$(find "$HOME" -maxdepth 5 -name "tz.mbn" -type f 2>/dev/null | head -1)
    if [[ -n "$tz" ]]; then
        cp "$tz" "$FIRMWARE_DIR/tz.mbn"
        log_ok "tz.mbn: $tz"
    else
        log_error "tz.mbn não encontrado!"
        return 1
    fi

    # lk1st
    local lk
    lk=$(find "$HOME" -maxdepth 4 \( -name "lk1st*.mbn" -o -name "emmc_appsboot.mbn" \) -type f 2>/dev/null | head -1)
    if [[ -n "$lk" ]]; then
        cp "$lk" "$FIRMWARE_DIR/lk1st.mbn"
        log_ok "lk1st: $lk"
    else
        log_error "lk1st não encontrado!"
        return 1
    fi

    # rootfs
    local rootfs
    rootfs=$(find "$HOME" -maxdepth 4 \( -name "generic-zhihe-raw.img" -o -name "generic-zhihe.img" -o -name "rootfs-raw*.img" \) -type f 2>/dev/null | head -1)
    if [[ -n "$rootfs" ]]; then
        cp "$rootfs" "$FIRMWARE_DIR/rootfs.img" 2>/dev/null || \
        ln -sf "$rootfs" "$FIRMWARE_DIR/rootfs.img"
        log_ok "rootfs: $rootfs ($(du -h "$rootfs" | cut -f1))"
    else
        log_error "Imagem rootfs não encontrada!"
        log_info "Procurei por: generic-zhihe-raw.img, generic-zhihe.img, rootfs-raw*.img"
        return 1
    fi

    echo ""

    # Verificar EDL
    ensure_edl || return 1

    # Flash
    flash_edl

    # Verificar
    post_flash_check
}

# ─── Main ───────────────────────────────────────────────────────────────────

main() {
    # Desabilitar ModemManager
    systemctl stop ModemManager 2>/dev/null || true
    systemctl disable ModemManager 2>/dev/null || true

    # Remover módulos que interferem
    for mod in qcserial usb_wwan qmi_wwan option; do
        rmmod "$mod" 2>/dev/null || true
    done

    case "${1:-}" in
        --auto)
            banner
            mkdir -p "$WORK_DIR" "$BACKUP_DIR" "$FIRMWARE_DIR" "$BUILD_DIR"
            quick_flash
            ;;
        --backup|--backup-only)
            banner
            mkdir -p "$BACKUP_DIR"
            ensure_edl && do_backup
            ;;
        --restore)
            banner
            do_restore
            ;;
        --status)
            show_status
            ;;
        --deps)
            banner
            install_deps
            ;;
        --help|-h)
            echo "Uso: sudo $0 [opção]"
            echo ""
            echo "Opções:"
            echo "  (sem opção)    Modo interativo"
            echo "  --auto         Flash rápido automático"
            echo "  --backup-only  Apenas backup do firmware"
            echo "  --restore      Restaurar firmware original"
            echo "  --status       Verificar estado do modem"
            echo "  --deps         Instalar dependências"
            echo "  --help         Esta mensagem"
            ;;
        *)
            main_interactive
            ;;
    esac
}

check_root
main "$@"
