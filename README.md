<p align="center">
  <img src="https://wiki.postmarketos.org/images/thumb/a/a1/PostmarketOS_logo.svg/200px-PostmarketOS_logo.svg.png" width="80" alt="postmarketOS">
</p>

<h1 align="center">modem4g-postmarketOS</h1>

<p align="center">
  <b>Transforme seu modem 4G USB barato em um servidor Linux completo</b><br>
  <sub>postmarketOS em modems Snapdragon 410 (MSM8916) -- UFI001C, UZ801, JZ0145 e compatíveis</sub>
</p>

<p align="center">
  <a href="#modems-compatíveis">Compatibilidade</a> •
  <a href="#como-funciona">Como Funciona</a> •
  <a href="#instalação-resumida">Instalação</a> •
  <a href="GUIA_COMPLETO.md">Guia Completo</a> •
  <a href="#troubleshooting">Troubleshooting</a>
</p>

---

## O que é isso?

Documentação completa para instalar **postmarketOS** (Linux Alpine) em modems 4G USB chineses baseados no **Snapdragon 410 (MSM8916)**. Esses modems custam ~R$30 no AliExpress e viram um mini servidor Linux com Wi-Fi, 4G e SSH.

Baseado no vídeo do **[VegaData](https://www.youtube.com/@VegaData)**: [Como instalar o Linux no MODEM!](https://www.youtube.com/watch?v=xzmWhbSOzOw)

### O que você ganha

| Recurso | Detalhe |
|---------|---------|
| **SSH remoto** | Acesso via `172.16.42.1` pela USB |
| **Wi-Fi** | Conecta em redes para acesso à internet |
| **4G** | Usa o chip do modem para dados móveis |
| **~3.2GB** | Armazenamento após reparticionamento |
| **Alpine Linux** | `apk add` qualquer pacote |
| **Reversível** | Restaura o Android original a qualquer momento |

---

## Modems Compatíveis

Todos precisam ter SoC **MSM8916** (Qualcomm Snapdragon 410/412):

| Modelo | Target lk1st | Status |
|--------|--------------|--------|
| UFI-001C / UFI-001B | `thwc,ufi001c` | Funciona |
| UFI-003 / MF601 / genérico | `zhihe,various` | Funciona |
| UZ801 V3.0 | `yiming,uz801-v3` | Funciona (lk1st obrigatório) |
| JZ0145 V33 | `xiaoxun,jz0145-v33` | Funciona |

Para descobrir seu modelo, abra o modem e leia o texto na placa.

---

## Requisitos

- **Linux** (Ubuntu, Debian, Pop!_OS) -- **obrigatório**, não funciona direto no Windows
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
│  │      │      │        │ cache   │          │  │
│  │      │      │        │recovery │          │  │
│  └──────┴──────┴────────┴─────────┴──────────┘  │
│                     │                           │
│                     ▼                           │
│  Após flash (Linux):                            │
│  ┌──────┬──────┬────────┬────────────────────┐  │
│  │ sbl1 │ tz*  │ aboot* │   userdata (Linux) │  │
│  │      │(db410│(lk1st) │   postmarketOS     │  │
│  │      │  c)  │        │   BTRFS comprimido  │  │
│  └──────┴──────┴────────┴────────────────────┘  │
│  * hyp também é substituído por qhypstub        │
│                                                 │
│  Após reparticionamento:                        │
│  ┌──────┬──────┬────────┬───────────┬────────┐  │
│  │ sbl1 │ tz   │ aboot  │boot(Linux)│persist │  │
│  │      │      │        │  ~3.2GB   │  40MB  │  │
│  └──────┴──────┴────────┴───────────┴────────┘  │
└─────────────────────────────────────────────────┘
```

### Fluxo de boot

```
Power On → SBL1 → TZ (db410c) → HYP (qhypstub) → ABOOT (lk1st) → Linux Kernel → postmarketOS
```

---

## Instalação Resumida

O **[GUIA_COMPLETO.md](GUIA_COMPLETO.md)** tem cada passo explicado em detalhe. Aqui vai o resumo rápido:

### 1. Instalar dependências

```bash
sudo apt install python3 python3-dev python3-pip liblzma-dev adb fastboot git \
    gcc-aarch64-linux-gnu gcc-arm-none-eabi device-tree-compiler pipx kpartx
sudo apt purge modemmanager

git clone https://github.com/bkerler/edl.git && cd edl
git submodule update --init --recursive
pip3 install -r requirements.txt && sudo ./autoinstall.sh

pipx install pmbootstrap
export PATH=$PATH:$HOME/.local/bin
```

### 2. Backup do modem (modo EDL)

```bash
# Colocar modem em EDL: adb reboot edl  OU  segurar botão + conectar USB
edl rl backup_modem
```

### 3. Compilar bootloader

```bash
# qhypstub
git clone https://github.com/msm8916-mainline/qhypstub.git
cd qhypstub && make

# lk1st (trocar LK2ND_COMPATIBLE pelo seu modelo - ver tabela acima)
git clone https://github.com/msm8916-mainline/lk2nd.git
cd lk2nd && git submodule update --init --recursive
make TOOLCHAIN_PREFIX=arm-none-eabi- lk1st-msm8916 \
  LK2ND_BUNDLE_DTB="msm8916-512mb-mtp.dtb" \
  LK2ND_COMPATIBLE="zhihe,various"
```

### 4. Gerar imagem postmarketOS

```bash
pmbootstrap init    # device: generic-zir, UI: console, extra: nano
pmbootstrap install --filesystem btrfs
```

### 5. Baixar firmware DragonBoard 410c

```bash
wget https://releases.linaro.org/96boards/dragonboard410c/linaro/rescue/latest/dragonboard-410c-bootloader-emmc-linux-176.zip
unzip dragonboard-410c-bootloader-emmc-linux-176.zip
```

### 6. Flashar (modo EDL)

```bash
edl w hyp hypstub_test_signed.mbn
edl w tz tz.mbn
edl w aboot emmc_appsboot.mbn
edl w userdata rootfs-generic-zir.img
edl reset
```

### 7. Conectar

```bash
ssh usuario@172.16.42.1
```

---

## Após a Instalação

```bash
# Wi-Fi
sudo nmtui

# Atualizar
sudo apk update

# Instalar pacotes
sudo apk add htop python3 nodejs nano
```

### Ideias de uso

- **Pi-hole** -- bloqueador de anúncios
- **WireGuard** -- VPN portátil
- **Bot Telegram/Discord** -- roda 24/7
- **Servidor web** -- nginx
- **Monitor de rede** -- sniffer portátil

---

## Troubleshooting

| Problema | Solução |
|----------|---------|
| `adb` mostra "no permissions" | `adb kill-server && sudo adb start-server` |
| `pmbootstrap` não encontrado | `export PATH=$PATH:$HOME/.local/bin` no `~/.bashrc` |
| SSH dá erro de chave | `ssh-keygen -R 172.16.42.1` |
| Modem não entra em EDL | Abrir modem, procurar test points na placa |
| Wi-Fi não funciona pós-repartição | Reflashar `persist.bin` do backup |
| EDL não detecta o modem | `sudo apt purge modemmanager` e reconectar |

---

## Referências

- [postmarketOS Wiki - Generic Zir](https://wiki.postmarketos.org/wiki/Generic_Qualcomm_Snapdragon_410/412_(generic-zir))
- [EDL - bkerler](https://github.com/bkerler/edl)
- [qhypstub](https://github.com/msm8916-mainline/qhypstub)
- [lk2nd](https://github.com/msm8916-mainline/lk2nd)
- [Firmware DragonBoard 410c](https://releases.linaro.org/96boards/dragonboard410c/linaro/rescue/latest/)
- [VegaData - Video original](https://www.youtube.com/watch?v=xzmWhbSOzOw)

---

## Licença

MIT

<p align="center">
  <sub>Baseado no trabalho do <a href="https://www.youtube.com/@VegaData">VegaData</a> e do projeto <a href="https://github.com/msm8916-mainline">msm8916-mainline</a></sub>
</p>
