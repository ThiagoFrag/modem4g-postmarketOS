#!/bin/bash
# ============================================================================
#  setup.sh - Configuração pós-instalação do postmarketOS no modem 4G
#
#  Este script é executado via SSH no modem já com postmarketOS rodando.
#  Ele configura WiFi, pacotes, APN para dados móveis, etc.
#
#  Uso:
#    ./setup.sh                    # Modo interativo
#    ./setup.sh --wifi             # Apenas configurar WiFi
#    ./setup.sh --modem            # Apenas configurar modem celular
#    ./setup.sh --info             # Mostrar info do sistema
#    ./setup.sh --remote           # Executar remotamente (do host)
#
#  Exemplo remoto:
#    sshpass -p "SENHA" ssh user@172.16.42.1 < setup.sh
# ============================================================================
set -euo pipefail

# ─── Cores ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

log_info()  { echo -e "  ${BLUE}ℹ${NC}  $*"; }
log_ok()    { echo -e "  ${GREEN}✓${NC}  $*"; }
log_warn()  { echo -e "  ${YELLOW}⚠${NC}  $*"; }
log_error() { echo -e "  ${RED}✗${NC}  $*"; }
log_step()  { echo -e "\n${BOLD}${CYAN}▶ $*${NC}"; }

# ─── Variáveis ──────────────────────────────────────────────────────────────
SSH_USER="${SSH_USER:-th}"
SSH_PASS="${SSH_PASS:-}"
MODEM_IP="172.16.42.1"

# ─── Execução Remota ────────────────────────────────────────────────────────

run_remote() {
    # Executar este script remotamente via SSH
    if [[ -z "$SSH_PASS" ]]; then
        echo -en "  ${YELLOW}?${NC}  Senha SSH para ${SSH_USER}@${MODEM_IP}: "
        read -rs SSH_PASS
        echo ""
    fi

    log_info "Conectando ao modem via SSH..."
    if ! ping -c 1 -W 3 "$MODEM_IP" &>/dev/null; then
        log_error "Não foi possível alcançar $MODEM_IP"
        return 1
    fi

    # Copiar e executar remotamente
    sshpass -p "$SSH_PASS" ssh -o StrictHostKeyChecking=no \
        -o PreferredAuthentications=password \
        -o PubkeyAuthentication=no \
        "${SSH_USER}@${MODEM_IP}" \
        'bash -s' < "${BASH_SOURCE[0]}"
}

# ─── Detecção de Ambiente ───────────────────────────────────────────────────

is_on_modem() {
    # Verifica se estamos rodando no modem
    [[ -f /etc/deviceinfo ]] || return 1
    grep -q "msm8916\|zhihe\|ufi" /etc/deviceinfo 2>/dev/null || \
    uname -r 2>/dev/null | grep -q "msm8916"
}

# ─── Informações do Sistema ─────────────────────────────────────────────────

show_info() {
    log_step "Informações do Sistema"
    echo ""

    # OS
    local os_name
    os_name=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo "N/A")
    echo -e "  ${BOLD}OS:${NC}          $os_name"

    # Kernel
    echo -e "  ${BOLD}Kernel:${NC}      $(uname -r)"

    # Device
    local device
    device=$(cat /sys/firmware/devicetree/base/model 2>/dev/null | tr -d '\0' || echo "N/A")
    echo -e "  ${BOLD}Device:${NC}      $device"

    # CPU
    local cpu
    cpu=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "N/A")
    local cores
    cores=$(nproc 2>/dev/null || echo "?")
    echo -e "  ${BOLD}CPU:${NC}         $cpu (${cores} cores)"

    # RAM
    local mem_total mem_free
    mem_total=$(free -h | awk '/Mem:/ {print $2}')
    mem_free=$(free -h | awk '/Mem:/ {print $4}')
    echo -e "  ${BOLD}RAM:${NC}         ${mem_free} livre / ${mem_total} total"

    # Disco
    local disk
    disk=$(df -h / | awk 'NR==2 {printf "%s livre / %s total (%s usado)", $4, $2, $5}')
    echo -e "  ${BOLD}Disco:${NC}       $disk"

    # Uptime
    echo -e "  ${BOLD}Uptime:${NC}      $(uptime -p 2>/dev/null || echo 'N/A')"

    # Interfaces de rede
    echo ""
    echo -e "  ${BOLD}Interfaces de Rede:${NC}"
    ip -brief addr show 2>/dev/null | while read -r iface state addrs; do
        local color
        case "$state" in
            UP)   color="${GREEN}" ;;
            DOWN) color="${RED}" ;;
            *)    color="${YELLOW}" ;;
        esac
        printf "    %-12s ${color}%-6s${NC} %s\n" "$iface" "$state" "$addrs"
    done

    # WiFi
    echo ""
    if iw dev wlan0 info &>/dev/null; then
        local ssid
        ssid=$(iw dev wlan0 link 2>/dev/null | grep SSID | awk '{print $2}' || echo "não conectado")
        echo -e "  ${BOLD}WiFi:${NC}        $ssid"
    fi

    # Modem celular
    if command -v mmcli &>/dev/null; then
        echo ""
        echo -e "  ${BOLD}Modem Celular:${NC}"
        mmcli -L 2>/dev/null | while read -r line; do
            echo -e "    $line"
        done
    fi
}

# ─── Atualização do Sistema ─────────────────────────────────────────────────

update_system() {
    log_step "Atualizando sistema..."

    apk update 2>/dev/null && log_ok "Índice atualizado"
    apk upgrade 2>/dev/null && log_ok "Pacotes atualizados"
}

install_packages() {
    log_step "Instalando pacotes úteis..."

    local packages=(
        # Rede
        networkmanager
        networkmanager-wifi
        networkmanager-wwan
        modemmanager
        wpa_supplicant
        # Ferramentas
        htop
        nano
        vim
        curl
        wget
        iptables
        dnsmasq
        # Compartilhamento de internet
        nftables
    )

    for pkg in "${packages[@]}"; do
        if apk info -e "$pkg" &>/dev/null; then
            log_ok "$pkg (já instalado)"
        else
            if apk add "$pkg" 2>/dev/null; then
                log_ok "$pkg"
            else
                log_warn "$pkg (falhou - pode não existir)"
            fi
        fi
    done
}

# ─── WiFi ───────────────────────────────────────────────────────────────────

setup_wifi() {
    log_step "Configuração WiFi"
    echo ""

    # Verificar se wlan0 existe
    if ! ip link show wlan0 &>/dev/null; then
        log_error "Interface wlan0 não encontrada!"
        return 1
    fi

    # Listar redes disponíveis
    log_info "Procurando redes WiFi..."
    ip link set wlan0 up 2>/dev/null

    if command -v nmcli &>/dev/null; then
        # NetworkManager
        nmcli device wifi rescan 2>/dev/null
        sleep 2
        echo ""
        echo -e "  ${BOLD}Redes WiFi disponíveis:${NC}"
        nmcli -t -f SSID,SIGNAL,SECURITY device wifi list 2>/dev/null | \
            sort -t: -k2 -rn | head -20 | while IFS=: read -r ssid signal security; do
            [[ -z "$ssid" ]] && continue
            local bar=""
            local s=${signal:-0}
            if ((s > 75)); then bar="████"; elif ((s > 50)); then bar="███░"; elif ((s > 25)); then bar="██░░"; else bar="█░░░"; fi
            printf "    ${DIM}%s${NC} %-30s %s\n" "$bar" "$ssid" "${security:-open}"
        done

        echo ""
        echo -en "  ${YELLOW}?${NC}  Nome da rede (SSID): "
        read -r wifi_ssid
        echo -en "  ${YELLOW}?${NC}  Senha: "
        read -rs wifi_pass
        echo ""

        if [[ -n "$wifi_ssid" ]]; then
            nmcli device wifi connect "$wifi_ssid" password "$wifi_pass" 2>/dev/null && \
                log_ok "Conectado a ${BOLD}$wifi_ssid${NC}" || \
                log_error "Falha ao conectar"
        fi
    else
        # wpa_supplicant manual
        echo -en "  ${YELLOW}?${NC}  Nome da rede (SSID): "
        read -r wifi_ssid
        echo -en "  ${YELLOW}?${NC}  Senha: "
        read -rs wifi_pass
        echo ""

        if [[ -n "$wifi_ssid" ]]; then
            mkdir -p /etc/wpa_supplicant
            wpa_passphrase "$wifi_ssid" "$wifi_pass" > /etc/wpa_supplicant/wpa_supplicant.conf

            # Iniciar
            killall wpa_supplicant 2>/dev/null || true
            wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null
            udhcpc -i wlan0 2>/dev/null &

            sleep 3
            if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
                log_ok "Conectado a ${BOLD}$wifi_ssid${NC} com acesso à internet"
            else
                log_warn "Conectado mas sem internet"
            fi
        fi
    fi
}

# ─── Modem Celular ──────────────────────────────────────────────────────────

setup_modem() {
    log_step "Configuração do Modem Celular"
    echo ""

    # Verificar ModemManager
    if ! command -v mmcli &>/dev/null; then
        log_info "Instalando ModemManager..."
        apk add modemmanager 2>/dev/null || { log_error "Não foi possível instalar ModemManager"; return 1; }
    fi

    # Iniciar serviço
    rc-service modemmanager start 2>/dev/null || true
    sleep 3

    # Detectar modem
    local modem_id
    modem_id=$(mmcli -L 2>/dev/null | grep -o '/Modem/[0-9]*' | head -1 | grep -o '[0-9]*')

    if [[ -z "$modem_id" ]]; then
        log_warn "Nenhum modem detectado. O SIM card está inserido?"
        return 1
    fi

    log_ok "Modem encontrado: #$modem_id"

    # Info do modem
    echo ""
    mmcli -m "$modem_id" 2>/dev/null | grep -E "model|manufacturer|state|signal|operator" | while read -r line; do
        echo -e "    ${DIM}$line${NC}"
    done

    # Verificar SIM
    local sim_path
    sim_path=$(mmcli -m "$modem_id" 2>/dev/null | grep "primary sim" | grep -o '/SIM/[0-9]*')
    if [[ -z "$sim_path" ]]; then
        log_warn "Nenhum SIM card detectado!"
        return 1
    fi

    # Configurar APN
    echo ""
    log_info "APNs comuns no Brasil:"
    echo -e "    ${DIM}Claro:    claro.com.br${NC}"
    echo -e "    ${DIM}Vivo:     zap.vivo.com.br${NC}"
    echo -e "    ${DIM}TIM:      timbrasil.br${NC}"
    echo -e "    ${DIM}Oi:       gprs.oi.com.br${NC}"
    echo ""
    echo -en "  ${YELLOW}?${NC}  APN da operadora: "
    read -r apn

    if [[ -n "$apn" ]]; then
        # Criar conexão
        if command -v nmcli &>/dev/null; then
            nmcli connection add type gsm ifname '*' con-name "mobile" apn "$apn" 2>/dev/null
            nmcli connection up mobile 2>/dev/null && \
                log_ok "Conexão móvel ativada com APN: $apn" || \
                log_warn "Falha ao ativar - verifique o APN"
        else
            # Método direto via mmcli
            mmcli -m "$modem_id" --simple-connect="apn=$apn" 2>/dev/null && \
                log_ok "Conectado via dados móveis (APN: $apn)" || \
                log_warn "Falha ao conectar"
        fi
    fi
}

# ─── Compartilhar Internet via USB ──────────────────────────────────────────

setup_usb_tethering() {
    log_step "Compartilhar internet do modem via USB"
    echo ""

    log_info "Isso permite usar o modem como 'modem USB' pelo computador"
    log_info "A internet (WiFi ou dados móveis) será compartilhada via USB"
    echo ""

    # Habilitar IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    log_ok "IP forwarding habilitado"

    # Detectar interface com internet
    local inet_iface=""
    for iface in wlan0 wwan0 ppp0 rmnet_data0; do
        if ip route 2>/dev/null | grep "default" | grep -q "$iface"; then
            inet_iface="$iface"
            break
        fi
    done

    if [[ -z "$inet_iface" ]]; then
        log_warn "Nenhuma interface com internet detectada"
        log_info "Conecte ao WiFi ou dados móveis primeiro"
        return 1
    fi

    log_ok "Interface internet: $inet_iface"

    # Configurar NAT
    iptables -t nat -A POSTROUTING -o "$inet_iface" -j MASQUERADE 2>/dev/null
    iptables -A FORWARD -i usb0 -o "$inet_iface" -j ACCEPT 2>/dev/null
    iptables -A FORWARD -i "$inet_iface" -o usb0 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
    log_ok "NAT configurado (usb0 → $inet_iface)"

    # Tornar persistente
    cat > /etc/local.d/usb-tethering.start << TETHER
#!/bin/sh
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -o $inet_iface -j MASQUERADE
iptables -A FORWARD -i usb0 -o $inet_iface -j ACCEPT
iptables -A FORWARD -i $inet_iface -o usb0 -m state --state ESTABLISHED,RELATED -j ACCEPT
TETHER
    chmod +x /etc/local.d/usb-tethering.start
    rc-update add local default 2>/dev/null || true

    log_ok "Tethering ativo e persistente!"
    echo ""
    log_info "No computador host, configure:"
    log_info "  IP: 172.16.42.2/24"
    log_info "  Gateway: 172.16.42.1"
    log_info "  DNS: 8.8.8.8"
}

# ─── SSH Keys ───────────────────────────────────────────────────────────────

setup_ssh_keys() {
    log_step "Configurar acesso SSH por chave"
    echo ""

    local auth_keys="/home/${SSH_USER}/.ssh/authorized_keys"
    mkdir -p "/home/${SSH_USER}/.ssh"

    echo -en "  ${YELLOW}?${NC}  Cole sua chave pública SSH (ou Enter p/ pular): "
    read -r pubkey

    if [[ -n "$pubkey" ]]; then
        echo "$pubkey" >> "$auth_keys"
        chmod 700 "/home/${SSH_USER}/.ssh"
        chmod 600 "$auth_keys"
        chown -R "${SSH_USER}:${SSH_USER}" "/home/${SSH_USER}/.ssh"
        log_ok "Chave adicionada"
    fi
}

# ─── Hostname ───────────────────────────────────────────────────────────────

set_hostname() {
    echo -en "  ${YELLOW}?${NC}  Novo hostname (Enter p/ manter '$(hostname)'): "
    read -r new_hostname
    if [[ -n "$new_hostname" ]]; then
        echo "$new_hostname" > /etc/hostname
        hostname "$new_hostname"
        log_ok "Hostname: $new_hostname"
    fi
}

# ─── Menu Principal ─────────────────────────────────────────────────────────

main_menu() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}   ${BOLD}Setup postmarketOS - Modem 4G USB${NC}     ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
    echo ""

    show_info

    echo ""
    echo -e "  ${BOLD}O que configurar?${NC}"
    echo ""
    echo -e "    ${CYAN}1${NC}) ${BOLD}Setup completo${NC} (atualizar + pacotes + WiFi)"
    echo -e "    ${CYAN}2${NC}) Atualizar sistema"
    echo -e "    ${CYAN}3${NC}) Instalar pacotes úteis"
    echo -e "    ${CYAN}4${NC}) Configurar WiFi"
    echo -e "    ${CYAN}5${NC}) Configurar modem celular (dados móveis)"
    echo -e "    ${CYAN}6${NC}) Compartilhar internet via USB (tethering)"
    echo -e "    ${CYAN}7${NC}) Configurar chaves SSH"
    echo -e "    ${CYAN}8${NC}) Mudar hostname"
    echo -e "    ${CYAN}9${NC}) Mostrar info do sistema"
    echo -e "    ${CYAN}0${NC}) Sair"
    echo ""
    echo -en "  ${YELLOW}?${NC}  Escolha [0-9]: "
    read -r choice

    case "$choice" in
        1)
            update_system
            install_packages
            setup_wifi
            setup_usb_tethering
            set_hostname
            ;;
        2) update_system ;;
        3) install_packages ;;
        4) setup_wifi ;;
        5) setup_modem ;;
        6) setup_usb_tethering ;;
        7) setup_ssh_keys ;;
        8) set_hostname ;;
        9) show_info ;;
        0) exit 0 ;;
        *) log_error "Opção inválida" ;;
    esac
}

# ─── Main ───────────────────────────────────────────────────────────────────

case "${1:-}" in
    --remote)
        run_remote
        ;;
    --wifi)
        setup_wifi
        ;;
    --modem)
        setup_modem
        ;;
    --info)
        show_info
        ;;
    --tethering)
        setup_usb_tethering
        ;;
    --update)
        update_system
        install_packages
        ;;
    --help|-h)
        echo "Uso: $0 [opção]"
        echo ""
        echo "Opções:"
        echo "  (sem opção)    Modo interativo"
        echo "  --remote       Executar remotamente do host via SSH"
        echo "  --wifi         Apenas configurar WiFi"
        echo "  --modem        Apenas configurar dados móveis"
        echo "  --tethering    Compartilhar internet via USB"
        echo "  --update       Atualizar sistema e pacotes"
        echo "  --info         Mostrar info do sistema"
        echo "  --help         Esta mensagem"
        ;;
    *)
        if is_on_modem; then
            main_menu
        else
            log_warn "Este script deve ser executado no modem."
            log_info "Use: $0 --remote  (para executar remotamente via SSH)"
            log_info "Ou:  ssh user@172.16.42.1 < $0"
        fi
        ;;
esac
