# Guia Completo: Instalar Linux (postmarketOS) em Modem 4G USB

**Baseado no video do canal VegaData** - [Como instalar o Linux no MODEM! (postmarketOS)](https://www.youtube.com/watch?v=xzmWhbSOzOw)

---

## Requisitos

- **Modem 4G USB** baseado no Snapdragon 410 (MSM8916) - modelos compatíveis:
  - Família **UFI** (UFI001C, etc.)
  - **UF** (modelo UF genérico)
  - **Z801 V3** / Z801 V3.2
- **Computador rodando Linux** (Ubuntu, Pop!_OS, Debian ou derivados recomendados)
  - O WSL do Windows pode funcionar, mas não é garantido
- **Cabo USB** para conectar o modem
- **Palito de dente ou chave de ejetar chip** (para apertar botão EDL)
- **Chave de fenda pequena** (para abrir o modem)

---

## PARTE 1 - Verificar Compatibilidade do Modem

### 1.1 Verificar modelo externo

Olhe a parte de trás do modem. Deve aparecer o modelo (UFI, UF, Z801, etc.). Se aparecer algum desses, provavelmente é compatível.

### 1.2 Testar o modem ANTES de abrir

**IMPORTANTE**: Antes de abrir o modem, conecte-o no computador e verifique se funciona normalmente (luzes piscando, cria rede Wi-Fi, etc.). Só depois de confirmar que funciona, prossiga para abrir.

### 1.3 Abrir o modem e verificar a placa

1. Desparafuse os 4 parafusos nos cantos do modem (guarde-os, são muito pequenos)
2. Use uma unha ou ferramenta fina na borda para ir destacando o plástico - **com cuidado para não quebrar as travas**
3. Dentro, verifique:
   - **Modelo da placa**: procure por textos como "JZ02", "UFI001C", "JZ0145" etc.
   - **Versão**: V30, V33, etc.
   - **SoC**: deve aparecer **MSM8916** (Snapdragon 410). Pode estar coberto por proteção metálica
4. Monte o modem de volta

### 1.4 Verificar pelo computador (via ADB)

Conecte o modem no PC Linux e abra o terminal:

```bash
# Instalar ADB (Android Debug Bridge)
sudo apt install adb

# Verificar dispositivos conectados
adb devices

# Se aparecer "no permissions", corrigir assim:
adb kill-server
sudo adb start-server
adb devices

# Entrar no shell do modem
adb shell

# Ver propriedades do sistema
getprop | grep product
```

Deve aparecer informações como:
- `ro.board.platform` = **msm8916** (confirma Snapdragon 410)
- Modelo da família UFI ou similar

Saia do shell com `Ctrl+D`.

---

## PARTE 2 - Instalar Ferramentas (EDL)

O EDL (Emergency Download) é uma ferramenta para interagir com o modo de download de emergência de chips Qualcomm. Permite backup e flash de baixo nível.

### 2.1 Instalar dependências e EDL

```bash
# Instalar dependências
sudo apt install python3 python3-dev python3-pip liblzma-dev adb fastboot git

# Desinstalar ModemManager (pode conflitar com o EDL)
sudo apt purge modemmanager

# Parar o serviço do ModemManager (se usar systemd)
sudo systemctl stop ModemManager

# Clonar e instalar o EDL
git clone https://github.com/bkerler/edl.git
cd edl
git submodule update --init --recursive
pip3 install -r requirements.txt
sudo ./autoinstall.sh
```

### 2.2 Reconstruir initramfs e reiniciar

```bash
sudo update-initramfs -u -k all
sudo reboot
```

### 2.3 Verificar instalação do EDL

Após reiniciar:

```bash
edl --help
```

Se aparecer as opcões do EDL, está funcionando.

---

## PARTE 3 - Fazer Backup do Modem (ESSENCIAL)

**NAO PULE ESTA ETAPA.** O backup é necessário para restaurar o modem ao estado original e para o reparticionamento posterior.

### 3.1 Colocar o modem em modo EDL

Existem **duas formas**:

**Forma 1 - Via ADB (só funciona com Android):**
```bash
adb reboot edl
```

**Forma 2 - Botão físico (funciona sempre):**
1. Remova a tampa traseira do modem
2. Localize o botão pequeno num buraquinho (nem todos os modems têm)
3. Pressione e segure o botão com palito de dente
4. Enquanto segura, conecte o modem na USB
5. As luzes do modem NÃO vão piscar (indica modo EDL)

### 3.2 Verificar modo EDL

```bash
lsusb
```

Deve aparecer algo como: `Qualcomm... QDL mode` - confirma modo EDL ativo.

### 3.3 Executar o backup

```bash
edl rl zironline_backup
```

Isso vai salvar todas as partições do modem na pasta `zironline_backup/`. Demora uns 10-20 minutos.

### 3.4 Guardar o backup

**Copie essa pasta para vários lugares seguros** (nuvem, HD externo, etc.). Voce vai precisar dela para restaurar o modem ou reparticionar.

---

## PARTE 4 - Gerar Imagem do postmarketOS (pmbootstrap)

### 4.1 Instalar pmbootstrap

O método recomendado atualmente é via `pipx` (o `pip install` está deprecated):

```bash
# Instalar pipx se não tiver
sudo apt install pipx

# Instalar pmbootstrap
pipx install pmbootstrap

# Verificar instalação
pmbootstrap --version
```

Se aparecer `command not found`, adicione o caminho ao PATH:

```bash
# Editar ~/.bashrc
nano ~/.bashrc

# Adicionar no final do arquivo:
export PATH=$PATH:$HOME/.local/bin

# Salvar (Ctrl+X, Y, Enter) e reabrir o terminal
```

### 4.2 Instalar dependência extra

```bash
# kpartx é necessário para o pmbootstrap manipular partições de imagens
sudo apt install kpartx
```

### 4.3 Inicializar o pmbootstrap

```bash
pmbootstrap init
```

Responda as perguntas assim:

| Pergunta | Resposta |
|----------|----------|
| Work path | Enter (deixar padrão) |
| Repository path | Enter (deixar padrão) |
| Channel | Digitar `v25.12` (última versão estável) |
| Device | Digitar `generic` e depois `zir` |
| Kernel | Enter (padrão = UFI, ou escolha o seu modelo) |
| Username | Digite seu nome de usuário desejado |
| Audio | Enter (padrão) |
| Wi-Fi | Enter (wpa_supplicant, padrão) |
| UI | Enter (console, sem interface gráfica) |
| OpenSSH | Enter (sim, essencial para acessar o modem) |
| Extra packages | Digitar `nano` (editor de texto, **importante para o reparticionamento**) |
| Timezone | Enter (aceitar sugestão) |
| Locale | Digitar `pt_BR` |
| Hostname | Enter (generic-zir, padrão) |
| Build outdated packages | Enter (sim) |

### 4.4 Gerar a imagem

```bash
pmbootstrap install --filesystem btrfs
```

Usa BTRFS porque tem compactação, importante já que o modem tem só ~4GB de armazenamento.

Vai pedir para configurar senha de usuário - **guarde essa senha**.

### 4.5 Copiar a imagem para local acessível

A imagem gerada fica num caminho longo. Copie para sua home:

```bash
cp ~/.local/var/pmbootstrap/chroot_rootfs_generic-zir/home/user/rootfs-generic-zir.img ~
```

(O caminho exato pode variar - o pmbootstrap mostra no final da instalação)

---

## PARTE 5 - Compilar Bootloader e Firmware

O modem vem com bootloader para Android 32-bit. O postmarketOS precisa de kernel 64-bit, então precisamos substituir partes do firmware.

### 5.1 Clonar repositórios necessários

```bash
cd ~

# Clonar qhypstub (hypervisor stub para MSM8916)
git clone https://github.com/msm8916-mainline/qhypstub.git

# Clonar lk2nd (bootloader Little Kernel)
git clone https://github.com/msm8916-mainline/lk2nd.git
cd lk2nd
git submodule update --init --recursive
```

### 5.2 Instalar ferramentas de cross-compilação

```bash
sudo apt install gcc-aarch64-linux-gnu gcc-arm-none-eabi device-tree-compiler
```

### 5.3 Compilar qhypstub

```bash
cd ~/qhypstub
make
```

### 5.4 Compilar lk2nd (bootloader)

```bash
cd ~/lk2nd
```

Antes de compilar, determine o **alvo correto** para seu modem.

Os alvos ficam definidos no arquivo `lk2nd/device/dts/msm8916/msm8916-512mb-mtp.dts`. Para ver:

```bash
nano lk2nd/device/dts/msm8916/msm8916-512mb-mtp.dts
```

Alvos possíveis (campo `compatible` de cada bloco):
- **`zhihe,various`** - genérico para modems desconhecidos (UFI001B/C, UFI003, MF601). **Usar se não souber qual é o seu** (recomendado na dúvida)
- **`thwc,ufi001c`** - se sua placa diz UFI001C ou UFI001B
- **`yiming,uz801-v3`** - se for modelo UZ801 V3.0
- **`xiaoxun,jz0145-v33`** - se a placa diz JZ0145 V33

Compilar com lk1st (substituir o `LK2ND_COMPATIBLE` pelo alvo do seu modem):

```bash
# Exemplo com alvo genérico (zhihe,various):
make TOOLCHAIN_PREFIX=arm-none-eabi- lk1st-msm8916 \
  LK2ND_BUNDLE_DTB="msm8916-512mb-mtp.dtb" \
  LK2ND_COMPATIBLE="zhihe,various"

# Exemplo para UFI001C especificamente:
make TOOLCHAIN_PREFIX=arm-none-eabi- lk1st-msm8916 \
  LK2ND_BUNDLE_DTB="msm8916-512mb-mtp.dtb" \
  LK2ND_COMPATIBLE="thwc,ufi001c"
```

O binário gerado estará em `build-lk1st-msm8916/emmc_appsboot.mbn`.

> **NOTA IMPORTANTE para UZ801 V3.0**: O firmware aboot original deste modem é incompatível com qhypstub e o tz.mbn do DragonBoard. Por isso é obrigatório usar lk1st (que substitui o aboot). Nos outros modems (UFI001C, JZ0145, etc.) lk1st também é recomendado.

### 5.5 Baixar firmware do DragonBoard 410c

```bash
cd ~
wget https://releases.linaro.org/96boards/dragonboard410c/linaro/rescue/latest/dragonboard-410c-bootloader-emmc-linux-176.zip
unzip dragonboard-410c-bootloader-emmc-linux-176.zip
```

> **Nota**: O número da versão (176) pode mudar. Verifique a versão mais recente em:
> https://releases.linaro.org/96boards/dragonboard410c/linaro/rescue/latest/
> Ou na [página do postmarketOS para zir](https://wiki.postmarketos.org/wiki/Generic_Qualcomm_Snapdragon_410/412_(generic-zir))

---

## PARTE 6 - Organizar Arquivos para Flash

### 6.1 Criar pasta de trabalho

```bash
mkdir ~/postmarket-zir
cd ~/postmarket-zir
```

### 6.2 Copiar arquivos necessários

```bash
# Imagem do postmarketOS
cp ~/rootfs-generic-zir.img .

# qhypstub compilado
cp ~/qhypstub/hypstub_test_signed.mbn .

# Trust Zone do DragonBoard (dentro da pasta extraída do zip)
cp ~/dragonboard-410c-bootloader-emmc-linux-*/tz.mbn .

# Bootloader compilado (lk1st)
cp ~/lk2nd/build-lk1st-msm8916/emmc_appsboot.mbn .

# SBL1 do DragonBoard (necessário para UZ801 V3 - ver nota na Parte 5.4)
cp ~/dragonboard-410c-bootloader-emmc-linux-*/sbl1.mbn .
```

---

## PARTE 7 - Flashar o postmarketOS no Modem

### 7.1 Colocar modem em modo EDL

Use ADB ou botão físico (veja Parte 3.1).

Confirme com:
```bash
lsusb
# Deve mostrar QDL mode
```

### 7.2 Flashar partições (uma por uma)

```bash
cd ~/postmarket-zir

# 1. Flashar hypervisor
edl w hyp hypstub_test_signed.mbn

# 2. Flashar Trust Zone
edl w tz tz.mbn

# 3. Flashar bootloader (partição aboot = Application Boot)
edl w aboot emmc_appsboot.mbn

# 4. Flashar o Linux na partição userdata
edl w userdata rootfs-generic-zir.img
```

### 7.3 Reiniciar o modem

```bash
edl reset
```

Ou desconecte e reconecte o USB.

---

## PARTE 8 - Primeiro Acesso ao Linux

### 8.1 Verificar conexão

Após reiniciar, o PC deve detectar um **novo adaptador de rede**. Verifique:
- Seu PC recebe IP `172.16.42.2`
- O modem está em `172.16.42.1`

### 8.2 Conectar via SSH

```bash
ssh seuusuario@172.16.42.1
```

- Se der erro de chave SSH (por já ter conectado antes em outro modem):
  ```bash
  ssh-keygen -R 172.16.42.1
  ```
- Digite `yes` para aceitar a chave
- Digite a senha configurada no pmbootstrap

### 8.3 Verificações iniciais

```bash
# Ver informações do sistema
hostnamectl

# Ver armazenamento
df -h

# Conectar ao Wi-Fi
sudo nmtui
# Selecione "Activate a connection" e escolha sua rede

# Atualizar repositórios
sudo apk update

# Instalar fastfetch para ver specs
sudo apk add fastfetch
fastfetch
```

---

## PARTE 9 - Reparticionamento (Ganhar Mais Espaço)

O modem tem ~4GB mas o Linux só usa ~2.2GB (partição userdata). Partições do Android (system, cache, recovery) estão desperdiçando espaço. Este processo libera quase 1GB extra.

### 9.1 Ativar debug shell

Ainda conectado via SSH no modem:

```bash
# Editar o deviceinfo
sudo nano /etc/deviceinfo

# Encontrar a linha com "deviceinfo_kernel_cmdline_append"
# Remover o # (descomentar) e adicionar dentro das aspas:
# postmarketos.debug-shell

# Salvar: Ctrl+X, Y, Enter

# Atualizar initramfs
sudo mkinitfs

# Reiniciar
sudo reboot
```

### 9.2 Conectar no debug shell

```bash
# Usar telnet em vez de SSH
telnet 172.16.42.1
```

### 9.3 Reparticionar com parted

```bash
# Abrir o parted no disco do modem
parted /dev/mmcblk0

# Ver partições atuais
p
```

Anote o tamanho total do disco (ex: 3909MB) e as partições existentes.

### 9.4 Deletar partições desnecessárias

Dentro do parted, delete as partições do Android **uma por uma** (os números podem variar no seu modem):

```
rm 27    # userdata
rm 26    # recovery
rm 25    # cache
rm 24    # persist (VAMOS RECRIAR DEPOIS com backup)
rm 23    # system
```

### 9.5 Redimensionar partição boot

A partição persist ocupa ~34MB. Reserve 40MB para ela:

```
# Calcular: tamanho_total - 40 = novo fim da partição boot
# Exemplo: 3909 - 40 = 3869

resizepart 22 3869
```

### 9.6 Criar nova partição persist

```
mkpart persist ext4 3870 100%
```

### 9.7 Verificar resultado

```
p
```

Deve mostrar duas partições: boot (grande) e persist (40MB).

Sair:
```
Ctrl+D   # sair do parted
Ctrl+D   # sair do debug shell
```

---

## PARTE 10 - Reinstalar Após Reparticionamento

O modem agora está sem sistema. Precisa entrar em modo EDL pelo botão físico.

### 10.1 Entrar em modo EDL

1. Pressione e segure o botão EDL
2. Conecte o modem na USB
3. Verifique: `lsusb` deve mostrar `QDL mode`

### 10.2 Restaurar partição persist

```bash
cd ~/zironline_backup
edl w persist persist.bin
```

### 10.3 Flashar Linux na partição boot (agora maior)

```bash
cd ~/postmarket-zir
edl w boot rootfs-generic-zir.img
```

**ATENÇÃO**: Agora é partição `boot` (não mais `userdata`), porque redimensionamos ela para ocupar o espaço maior.

### 10.4 Reiniciar e verificar

```bash
edl reset
```

Conecte via SSH e verifique:

```bash
ssh seuusuario@172.16.42.1

# Verificar espaço - deve mostrar ~3.2GB agora (antes era ~2.2GB)
df -h

# Testar Wi-Fi
sudo nmtui
```

---

## PARTE 11 - Restaurar Software Original (Desfazer Tudo)

Se quiser voltar o modem pro Android original:

### 11.1 Modo EDL

Aperte o botão e conecte na USB.

### 11.2 Restaurar tabela de partições

```bash
cd ~/zironline_backup
edl w gpt gpt_main0.bin
```

### 11.3 Restaurar todas as partições

```bash
edl wf ~/zironline_backup
```

Demora uns 20 minutos. Ao terminar, desconecte e reconecte o modem. Ele volta a funcionar como modem 4G normal.

---

## Resumo dos Comandos Principais

| Ação | Comando |
|------|---------|
| Instalar ADB | `sudo apt install adb` |
| Ver dispositivos Android | `adb devices` |
| Entrar no shell do modem | `adb shell` |
| Reiniciar em modo EDL | `adb reboot edl` |
| Verificar modo EDL | `lsusb` (procurar QDL mode) |
| Backup completo | `edl rl zironline_backup` |
| Flashar partição | `edl w <partição> <arquivo>` |
| Flashar todas as partições | `edl wf <pasta_backup>` |
| Reiniciar modem via EDL | `edl reset` |
| Conectar via SSH | `ssh usuario@172.16.42.1` |
| Conectar Wi-Fi | `sudo nmtui` |
| Atualizar pacotes | `sudo apk update` |
| Instalar pacote | `sudo apk add <pacote>` |

---

## Troubleshooting

**ADB mostra "no permissions":**
```bash
adb kill-server
sudo adb start-server
```

**pmbootstrap dá "command not found":**
Adicione `$HOME/.local/bin` ao PATH: `export PATH=$PATH:$HOME/.local/bin` no `~/.bashrc`.

**SSH dá erro de chave:**
```bash
ssh-keygen -R 172.16.42.1
```

**Modem não entra em modo EDL pelo botão:**
Abra o modem e procure test points na placa. Alguns modelos não têm botão EDL.

**Wi-Fi não funciona após reparticionamento:**
A partição persist não foi restaurada corretamente. Reflashe-a a partir do backup.

---

## Links Úteis

- [postmarketOS Wiki - Zir (modems Snapdragon 410)](https://wiki.postmarketos.org/wiki/Generic_Qualcomm_Snapdragon_410/412_(generic-zir))
- [Ferramenta EDL (bkerler)](https://github.com/bkerler/edl)
- [qhypstub (msm8916-mainline)](https://github.com/msm8916-mainline/qhypstub)
- [lk2nd bootloader (msm8916-mainline)](https://github.com/msm8916-mainline/lk2nd)
- [Firmware DragonBoard 410c (Linaro)](https://releases.linaro.org/96boards/dragonboard410c/linaro/rescue/latest/)
- [Canal VegaData no YouTube](https://www.youtube.com/@VegaData)
- [postmarketOS - Guia de Instalação](https://wiki.postmarketos.org/wiki/Installation_guide)
