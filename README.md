<p align="center">
  <img src="https://wiki.postmarketos.org/images/thumb/a/a1/PostmarketOS_logo.svg/200px-PostmarketOS_logo.svg.png" width="80" alt="postmarketOS">
</p>

<h1 align="center">modem4g-postmarketOS</h1>

<p align="center">
  <b>Transforme seu modem 4G USB barato em um servidor Linux completo</b><br>
  <sub>postmarketOS em modems Snapdragon 410 (MSM8916) — UFI001C, UZ801, JZ0145 e compatíveis</sub>
</p>

<p align="center">
  <a href="#modems-compatíveis">Compatibilidade</a> •
  <a href="#como-funciona">Como Funciona</a> •
  <a href="#flash-automatizado-">Flash Automático</a> •
  <a href="#instalação-manual">Manual</a> •
  <a href="GUIA_COMPLETO.md">Guia Completo</a> •
  <a href="#troubleshooting">Troubleshooting</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/SoC-MSM8916-blue" alt="MSM8916">
  <img src="https://img.shields.io/badge/OS-postmarketOS-green" alt="postmarketOS">
  <img src="https://img.shields.io/badge/Kernel-6.12-orange" alt="Kernel">
  <img src="https://img.shields.io/badge/Licença-MIT-yellow" alt="MIT">
</p>

---

## O que é isso?

Documentação e **scripts automatizados** para instalar **postmarketOS** (Linux Alpine) em modems 4G USB chineses baseados no **Snapdragon 410 (MSM8916)**. Esses modems custam ~R$30 no AliExpress e viram um mini servidor Linux com Wi-Fi, 4G e SSH.

Baseado no vídeo do **[VegaData](https://www.youtube.com/@VegaData)**: [Como instalar o Linux no MODEM!](https://www.youtube.com/watch?v=xzmWhbSOzOw)

### O que você ganha

| Recurso | Detalhe |
|---------|---------|
| 🖥️ **SSH remoto** | Acesso via `172.16.42.1` pela USB |
| 📶 **Wi-Fi** | Conecta em redes para acesso à internet |
| 📱 **4G** | Usa o chip do modem para dados móveis |
| 💾 **~3.2GB** | Armazenamento após reparticionamento |
| 📦 **Alpine Linux** | `apk add` qualquer pacote |
| 🔄 **Reversível** | Restaura o Android original a qualquer momento |

---

## Modems Compatíveis

Todos precisam ter SoC **MSM8916** (Qualcomm Snapdragon 410/412):

| Modelo | Target lk1st | RAM | Status |
|--------|--------------|-----|--------|
| UFI-001C / UFI-001B | `thwc,ufi001c` | 512MB | ✅ Funciona |
| UFI-003 / MF601 / genérico | `zhihe,various` | 512MB | ✅ Funciona |
| UZ801 V3.0 | `yiming,uz801-v3` | 512MB | ✅ Funciona |
| JZ0145 V33 (Xiaoxun) | `xiaoxun,jz0145-v33` | 512MB | ✅ Testado |

Para descobrir seu modelo, abra o modem e leia o texto na placa.

---

## Flash Automatizado ⚡

> **Modo mais fácil!** O script faz tudo sozinho: backup, compilação, download e flash.

### Pré-requisitos

- **Linux** (Arch, Ubuntu, Debian, Fedora)
- Modem 4G USB com SoC MSM8916
- Cabo USB
- Acesso root (`sudo`)

### Uso rápido

```bash
# 1. Clonar o repositório
git clone https://github.com/ThiagoFrag/modem4g-postmarketOS.git
cd modem4g-postmarketOS

# 2. Colocar modem em modo EDL (test point + USB)

# 3. Executar o flash
sudo ./flash.sh
```

### Modos do script

```bash
sudo ./flash.sh              # Modo interativo (menu completo)
sudo ./flash.sh --auto       # Flash rápido (detecta arquivos automaticamente)
sudo ./flash.sh --backup-only # Apenas backup do firmware original
sudo ./flash.sh --restore    # Restaurar firmware original (voltar ao Android)
sudo ./flash.sh --status     # Verificar estado do modem
sudo ./flash.sh --deps       # Apenas instalar dependências
```

### Menu interativo

```
╔══════════════════════════════════════════════════════════════╗
║   ███╗   ███╗ ██████╗ ██████╗ ███████╗███╗   ███╗██╗  ██╗  ║
║   ██╔████╔██║██║   ██║██║  ██║█████╗  ██╔████╔██║███████║  ║
║   ██║ ╚═╝ ██║╚██████╔╝██████╔╝███████╗██║ ╚═╝ ██║    ██║  ║
║       postmarketOS em Modem 4G USB (MSM8916)                ║
╚══════════════════════════════════════════════════════════════╝

  1) Flash completo (backup + compilar + flash postmarketOS)
  2) Flash rápido (já tenho os arquivos compilados)
  3) Apenas backup do firmware original
  4) Restaurar firmware original (voltar pro Android)
  5) Status do modem
  6) Instalar dependências
```

### Pós-instalação

Após o flash, use o script de setup para configurar WiFi, dados móveis, etc:

```bash
# Pelo host (via SSH)
./setup.sh --remote

# Ou direto no modem
ssh user@172.16.42.1
./setup.sh
```

```bash
./setup.sh                # Menu interativo
./setup.sh --wifi         # Apenas WiFi
./setup.sh --modem        # Apenas dados móveis
./setup.sh --tethering    # Compartilhar internet via USB
./setup.sh --info         # Informações do sistema
```

---

## Requisitos

- **Linux** (Ubuntu, Debian, Arch, Fedora) — **obrigatório**, não funciona direto no Windows
- Modem 4G USB com SoC MSM8916
- Cabo USB
- Palito de dente (para o botão EDL)

---

## Como Funciona

```
┌─────────────────────────────────────────────────┐
│                 MODEM 4G USB                    │
│              (Snapdragon 410)                   │
│                                                 │
│  Partições originais (Android):                 │
│  ┌──────┬──────┬────────┬─────────┬──────────┐  │
│  │ sbl1 │ tz   │ aboot  │ system  │ userdata │  │
│  └──────┴──────┴────────┴─────────┴──────────┘  │
│                     │                           │
│                     ▼                           │
│  Após flash (Linux):                            │
│  ┌──────┬──────┬────────┬────────────────────┐  │
│  │ sbl1 │ tz*  │ aboot* │   userdata (Linux) │  │
│  │      │(db41 │(lk1st) │ ┌──────┬─────────┐ │  │
│  │      │ 0c)  │        │ │ boot │ rootfs   │ │  │
│  │      │      │        │ │(ext2)│ (ext4)   │ │  │
│  └──────┴──────┴────────┴─┴──────┴─────────┘─┘  │
│  * hyp substituído por qhypstub                  │
│                                                 │
│  A imagem MBR dentro de userdata contém:        │
│  - Partição 1: boot (kernel + extlinux.conf)    │
│  - Partição 2: rootfs (postmarketOS)            │
└─────────────────────────────────────────────────┘
```

### Fluxo de boot

```
Power On → SBL1 → TZ (db410c) → HYP (qhypstub) → ABOOT (lk1st)
                                                       │
                                      ┌────────────────┘
                                      ▼
                              Scan partições
                              Encontra MBR em userdata
                              Monta boot (ext2)
                              Lê extlinux.conf
                                      │
                                      ▼
                              Carrega kernel + DTB
                                      │
                                      ▼
                              postmarketOS ✓
```

### Partições modificadas

| Partição | Original | Após Flash |
|----------|----------|------------|
| `hyp` | Hypervisor Qualcomm | qhypstub (permite kernel 64-bit) |
| `tz` | TrustZone original | TrustZone DragonBoard 410c |
| `aboot` | Bootloader Android (LK) | lk1st (procura Linux) |
| `userdata` | Dados do Android | Imagem MBR (boot + rootfs) |

---

## Instalação Manual

O **[GUIA_COMPLETO.md](GUIA_COMPLETO.md)** tem cada passo explicado em detalhe. Aqui vai o resumo rápido:

### 1. Instalar dependências

```bash
# Debian/Ubuntu
sudo apt install python3 python3-dev python3-pip liblzma-dev adb fastboot git \
    gcc-aarch64-linux-gnu gcc-arm-none-eabi device-tree-compiler pipx kpartx
sudo apt purge modemmanager

# Arch Linux
sudo pacman -S python python-pip android-tools dtc git \
    aarch64-linux-gnu-gcc arm-none-eabi-gcc sshpass make

# EDL tool
git clone https://github.com/bkerler/edl.git && cd edl
git submodule update --init --recursive
pip3 install -r requirements.txt && sudo ./autoinstall.sh
```

### 2. Backup do modem (modo EDL)

```bash
# Colocar modem em EDL: adb reboot edl  OU  segurar botão + conectar USB
edl rl backup_modem --loader=prog_emmc_firehose_8916_gucci_peek.mbn
```

### 3. Compilar bootloader

```bash
# qhypstub (hypervisor stub para kernel 64-bit)
git clone https://github.com/msm8916-mainline/qhypstub.git
cd qhypstub && make CROSS_COMPILE=aarch64-linux-gnu-
# Assinar com qtestsign
python3 qtestsign.py hyp qhypstub.mbn

# lk1st (trocar LK2ND_COMPATIBLE pelo seu modelo - ver tabela acima)
git clone https://github.com/msm8916-mainline/lk2nd.git
cd lk2nd && git submodule update --init --recursive
make TOOLCHAIN_PREFIX=arm-none-eabi- lk1st-msm8916 \
  LK2ND_BUNDLE_DTB="msm8916-512mb-mtp.dtb" \
  LK2ND_COMPATIBLE="xiaoxun,jz0145-v33"
```

### 4. Gerar imagem postmarketOS

```bash
pmbootstrap init    # device: generic-zhihe, UI: console
pmbootstrap install
# A imagem RAW estará em ~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/
```

### 5. Baixar firmware DragonBoard 410c

```bash
wget https://releases.linaro.org/96boards/dragonboard410c/linaro/rescue/latest/dragonboard-410c-bootloader-emmc-linux-176.zip
unzip dragonboard-410c-bootloader-emmc-linux-176.zip
```

### 6. Flashar (modo EDL)

```bash
# IMPORTANTE: usar a imagem RAW (MBR com boot+rootfs), NÃO a rootfs separada!
edl w hyp qhypstub-test-signed.mbn --loader=prog_emmc_firehose_8916_gucci_peek.mbn
edl w tz tz.mbn --loader=prog_emmc_firehose_8916_gucci_peek.mbn
edl w aboot emmc_appsboot.mbn --loader=prog_emmc_firehose_8916_gucci_peek.mbn
edl w userdata generic-zhihe-raw.img --loader=prog_emmc_firehose_8916_gucci_peek.mbn
edl reset --loader=prog_emmc_firehose_8916_gucci_peek.mbn
```

### 7. Conectar

```bash
# Aguardar ~30s após reset, depois:
ssh usuario@172.16.42.1
```

---

## Estrutura do Projeto

```
modem4g-postmarketOS/
├── flash.sh            # 🔧 Script de flash automatizado
├── setup.sh            # ⚙️  Script de configuração pós-instalação
├── GUIA_COMPLETO.md    # 📖 Guia detalhado passo a passo
├── README.md           # 📋 Este arquivo
└── LICENSE             # MIT
```

---

## Após a Instalação

```bash
# Acessar o modem
ssh usuario@172.16.42.1

# Wi-Fi
sudo nmtui
# ou
./setup.sh --wifi

# Atualizar sistema
sudo apk update && sudo apk upgrade

# Instalar pacotes
sudo apk add htop python3 nodejs nano curl
```

### Ideias de uso

- 🛡️ **Pi-hole** — bloqueador de anúncios portátil
- 🔒 **WireGuard** — VPN portátil
- 🤖 **Bot Telegram/Discord** — roda 24/7
- 🌐 **Servidor web** — nginx
- 📡 **Monitor de rede** — sniffer portátil
- 📶 **Hotspot 4G→WiFi** — compartilhar dados móveis
- 🔗 **Tethering USB** — usar como modem Linux no PC

---

## Troubleshooting

| Problema | Solução |
|----------|---------|
| Modem cai em fastboot ao invés de boot | A imagem rootfs está errada. Use a imagem **RAW** (MBR com boot+rootfs), não a rootfs separada |
| `adb` mostra "no permissions" | `adb kill-server && sudo adb start-server` |
| `pmbootstrap` não encontrado | `export PATH=$PATH:$HOME/.local/bin` |
| SSH dá erro de chave | `ssh-keygen -R 172.16.42.1` |
| Modem não entra em EDL | Abrir modem, procurar test points na placa |
| Wi-Fi não funciona pós-repartição | Reflashar `persist.bin` do backup |
| EDL não detecta o modem | `sudo systemctl stop ModemManager` e reconectar |
| `fastboot` trava | Fastboot não funciona bem com lk1st nestes modems. Use EDL sempre |
| Avisos de sector size no EDL | Normal, pode ignorar. O flash funciona mesmo assim |

### Como entrar em modo EDL

1. Desconecte o modem
2. Abra o case (deslize ou desparafuse)
3. Localize o test point na placa (geralmente próximo ao SoC)
4. Use um palito ou pinça para curto-circuitar o test point com GND
5. Conecte o USB **mantendo** o curto
6. Solte após 2 segundos
7. Verifique: `lsusb | grep 9008`

---

## Referências

- [postmarketOS Wiki - Generic Zhihe](https://wiki.postmarketos.org/wiki/Generic_Qualcomm_Snapdragon_410/412_(generic-zhihe))
- [EDL - bkerler](https://github.com/bkerler/edl)
- [qhypstub](https://github.com/msm8916-mainline/qhypstub)
- [lk2nd / lk1st](https://github.com/msm8916-mainline/lk2nd)
- [Firmware DragonBoard 410c](https://releases.linaro.org/96boards/dragonboard410c/linaro/rescue/latest/)
- [VegaData - Video original](https://www.youtube.com/watch?v=xzmWhbSOzOw)

---

## Licença

MIT — veja [LICENSE](LICENSE)

<p align="center">
  <sub>Baseado no trabalho do <a href="https://www.youtube.com/@VegaData">VegaData</a> e do projeto <a href="https://github.com/msm8916-mainline">msm8916-mainline</a></sub>
</p>
