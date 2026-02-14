# Acesso aos Modems 4G via Proxmox

## Credenciais

| Item | Valor |
|------|-------|
| **Usuario SSH** | `th` |
| **Senha SSH** | `147258369` |
| **IP do modem** | `172.16.42.1` |
| **IP do host (lado modem)** | `172.16.42.2` |
| **OS** | postmarketOS edge |
| **Kernel** | 6.12.1-msm8916 |

---

## Cenario

```
                    rede local 192.168.100.0/24
                              |
         ┌────────────────────┼────────────────────┐
         |                    |                     |
   ┌─────┴─────┐       ┌─────┴─────┐         ┌────┴────┐
   | Proxmox   |       |   VM 1    |         |  VM 2   |
   | (host)    |       | 192.168.  |         | 192.168.|
   | .100.209  |       | 100.xxx   |         | 100.xxx |
   └─────┬─────┘       └───────────┘         └─────────┘
         |
    USB  | enp*s0u* (172.16.42.2)
         |
   ┌─────┴─────┐
   | Modem 4G  |
   | usb0      |
   | 172.16.42.1|
   └───────────┘
```

Os modems estao conectados via USB no host Proxmox.
As VMs precisam acessar a rede 172.16.42.0/24 atraves do host.

---

## Metodo 1: Roteamento pelo Host (recomendado)

Permite que qualquer VM na rede local acesse os modems sem USB passthrough.

### No host Proxmox (uma vez):

```bash
# 1. Habilitar IP forwarding
echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf
sysctl -p

# 2. Permitir forward da rede local para os modems
iptables -A FORWARD -s 192.168.100.0/24 -d 172.16.42.0/24 -j ACCEPT
iptables -A FORWARD -s 172.16.42.0/24 -d 192.168.100.0/24 -j ACCEPT

# 3. NAT para que o modem veja os pacotes vindo do host
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -d 172.16.42.0/24 -j MASQUERADE

# 4. Salvar regras para sobreviver reboot
apt install iptables-persistent -y
netfilter-persistent save
```

### Na VM (ou em qualquer maquina da rede):

```bash
# Adicionar rota para a rede dos modems via host Proxmox
sudo ip route add 172.16.42.0/24 via 192.168.100.209

# Tornar persistente (Debian/Ubuntu):
echo "172.16.42.0/24 via 192.168.100.209" | sudo tee -a /etc/network/routes

# Ou no netplan (Ubuntu):
# /etc/netplan/01-netcfg.yaml
#   routes:
#     - to: 172.16.42.0/24
#       via: 192.168.100.209

# Testar
ping 172.16.42.1
ssh th@172.16.42.1
```

### Script para aplicar tudo no host:

```bash
#!/bin/bash
# Rodar no host Proxmox como root

# Habilitar forwarding
sysctl -w net.ipv4.ip_forward=1
grep -q "ip_forward" /etc/sysctl.conf || echo 'net.ipv4.ip_forward = 1' >> /etc/sysctl.conf

# Regras de firewall
iptables -A FORWARD -s 192.168.100.0/24 -d 172.16.42.0/24 -j ACCEPT
iptables -A FORWARD -s 172.16.42.0/24 -d 192.168.100.0/24 -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -A POSTROUTING -s 192.168.100.0/24 -d 172.16.42.0/24 -j MASQUERADE

echo "Pronto! VMs podem acessar 172.16.42.1 adicionando rota:"
echo "  ip route add 172.16.42.0/24 via 192.168.100.209"
```

---

## Metodo 2: USB Passthrough para VM

Passa o modem USB inteiro para uma VM. A VM controla o modem diretamente.
O host perde acesso ao modem.

### Identificar o modem:

```bash
# No host Proxmox
lsusb | grep 18d1
# Exemplo: Bus 007 Device 007: ID 18d1:d001 Google Inc.
```

### Via interface web do Proxmox:

1. Ir em **Datacenter > Node > VM > Hardware**
2. Clicar **Add > USB Device**
3. Selecionar **Use USB Vendor/Product ID**
4. Escolher o dispositivo `18d1:d001` (Google Inc.)
5. Reiniciar a VM

### Via linha de comando:

```bash
# Descobrir bus e device
lsusb | grep 18d1
# Bus 007 Device 007: ID 18d1:d001

# Adicionar ao config da VM (trocar VMID pelo ID da sua VM)
VMID=100
echo "usb0: host=18d1:d001" >> /etc/pve/qemu-server/${VMID}.conf

# Reiniciar VM
qm reboot $VMID
```

### Na VM apos passthrough:

```bash
# O modem aparece como interface de rede
ip link show
# Procurar por enp*, usb0 ou similar

# Configurar IP
sudo ip addr add 172.16.42.2/24 dev enp0s20f0u1  # ajustar nome da interface
sudo ip link set enp0s20f0u1 up

# Acessar
ssh th@172.16.42.1
```

---

## Metodo 3: SSH Tunnel (mais simples, sem config no host)

Cria um tunel SSH do Proxmox host para a VM, sem mexer em rotas.

### Na VM:

```bash
# Tunel: porta 2222 local da VM -> modem porta 22
ssh -L 2222:172.16.42.1:22 root@192.168.100.209 -N &

# Agora acessar o modem pela porta local
ssh -p 2222 th@localhost
# Senha: 147258369
```

### Ou no host Proxmox (port forward permanente):

```bash
# Qualquer maquina que acesse 192.168.100.209:2201 cai no modem 1
# Qualquer maquina que acesse 192.168.100.209:2202 cai no modem 2
iptables -t nat -A PREROUTING -p tcp -d 192.168.100.209 --dport 2201 \
  -j DNAT --to-destination 172.16.42.1:22
iptables -t nat -A PREROUTING -p tcp -d 192.168.100.209 --dport 2202 \
  -j DNAT --to-destination 172.16.42.1:22

iptables -t nat -A POSTROUTING -d 172.16.42.1 -j MASQUERADE

# Salvar
netfilter-persistent save
```

Depois de qualquer VM ou PC na rede:

```bash
# Modem 1
ssh -p 2201 th@192.168.100.209

# Modem 2
ssh -p 2202 th@192.168.100.209

# Senha: 147258369
```

---

## Metodo recomendado

Para uso simples, o **Metodo 3 (port forward)** e o mais pratico:

1. Roda 2 comandos no host Proxmox
2. De qualquer VM ou PC na rede, conecta direto via `ssh -p 2201 th@192.168.100.209`
3. Nao precisa mexer em rotas nas VMs

### Resumo de acesso rapido:

```bash
# Modem 1 (de qualquer lugar na rede 192.168.100.0/24):
ssh -p 2201 th@192.168.100.209
# Senha: 147258369

# Modem 2:
ssh -p 2202 th@192.168.100.209
# Senha: 147258369
```

---

## Troubleshooting

| Problema | Solucao |
|----------|---------|
| Rota nao funciona | Verificar `sysctl net.ipv4.ip_forward` esta 1 |
| USB passthrough nao aparece | Instalar `apt install qemu-guest-agent` na VM |
| Modem nao responde ping | Verificar `ip addr` no host, interface do modem deve ter 172.16.42.2 |
| Dois modems mesmo IP | Ambos usam 172.16.42.1, usar port forward com portas diferentes |
| Conexao recusada | Verificar se modem esta ligado: `lsusb \| grep 18d1` |
