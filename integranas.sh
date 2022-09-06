#!/bin/bash

#clear
Menu() {
clear
#echo -e '\n'
echo "SCRIPT PARA INTEGRAO DE CONCENTRADORES"
echo ""
echo "Selecione a opo desejada:"
echo ""
echo "[ 1 ] | Mikrotik"
echo "[ 2 ] | Huawei"
echo "[ 3 ] | Cisco"
echo "[ 4 ] | Accel-PPP"
echo "[ 5 ] | Juniper"
read opcao
case $opcao in
1) Mikrotik ;;
2) Huawei ;;
3) Cisco ;;
4) Accel ;;
5) Juniper ;;
0) Sair ;;
*) "Comando desconhecido"; echo ; Menu;;
#break ;;
esac
}

Mikrotik () {
clear
echo "Script - Integrao Mikrotik"
echo ""
echo "Preencha as seguintes informaes:"
echo ""
echo "Usurio VPN:"
read USERVPN
echo "Senha NAS/VPN:"
read PASSVPNUSER
echo "IP do Radius:"
read RADIUS
echo "Porta do authentication:"
read AUC
echo "Porta do accounting:"
read ACC
echo "Porta de Aviso:"
read AVS
echo "Porta de Bloqueio:"
read BLQ
echo "Token:"
read TOKENAQUI
echo "Link do SGP:"
read LINKDOSGP
echo "IP do SGP:"
read IPSGP

cat <<EOF > Mikrotik-$login_vpn.txt

# AJUSTES NO MIKROTIK

/system backup save name=BACKUP_ANTES_DO_SGP
/export file=BACKUP_ANTES_DO_SGP_TXT
/ip accounting set enabled=yes
/system ntp client set enabled=yes primary-ntp=200.160.0.8
/system clock set time-zone-name=America/Recife
/radius incoming set accept=yes
/ip service set api disabled=no port=3540 address="$RADIUS,$IPSGP"
/user aaa set use-radius=yes
/ppp aaa set interim-update=5m use-radius=yes
/snmp community disable public
/snmp community add addresses="$RADIUS,$IPSGP" name=SGP-GRAPHICs
/snmp set enabled=yes trap-community=SGP-GRAPHICs trap-version=2
/user add name=SGP comment="SGP - ACESSO API - NAO ALTERAR OU REMOVER" \
    group=full password=$PASSVPNUSER
/system logging set 0 action=memory disabled=no prefix="" topics=info,!account
/radius
add comment="RADIUS SGP" secret=sgp@radius service=ppp,dhcp,login address=$RADIUS accounting-port=$ACC \
    authentication-port=$AUC timeout=00:00:03
    
/ppp profile add name=VPN-SGP
/interface pptp-client add connect-to=$IPSGP user=$USERVPN password=$PASSVPNUSER  name="VPN-SGP"\
    disabled=no comment=SGP profile=VPN-SGP keepalive-timeout=30

/interface sstp-client add connect-to=($IPSGP.":4433") user=$USERVPN password=$PASSVPNUSER name="SGP-VPN"\
    disabled=no profile=VPN-SGP comment=SGP keepalive-timeout=5

/interface  l2tp-client add connect-to=$IPSGP user=$USERVPN password=$PASSVPNUSER name="VPN-SGP"\
    disabled=no profile=VPN-SGP comment=SGP keepalive-timeout=30

/interface ovpn-client add connect-to=$IPSGP user=$USERVPN password=$PASSVPNUSER profile=VPN-SGP \
    name="VPN-SGP" disabled=no comment=SGP

# REGRAS DE AVISO E BLQOEUIO

/ip firewall address-list 
add address=$RADIUS list=SGP-SITES-LIBERADOS
add address=$IPSGP list=SGP-SITES-LIBERADOS
add address=208.67.222.222 list=SGP-SITES-LIBERADOS
add address=208.67.222.220 list=SGP-SITES-LIBERADOS
add address=8.8.8.8 list=SGP-SITES-LIBERADOS
add address=8.8.4.4 list=SGP-SITES-LIBERADOS
add address=1.1.1.1 list=SGP-SITES-LIBERADOS
add address=10.24.0.0/20 list=SGP-BLOQUEADOS
/ip firewall filter
add action=drop chain=forward dst-address-list=!SGP-SITES-LIBERADOS src-address-list=\
    SGP-BLOQUEADOS comment="SGP REGRA"
add chain=forward connection-mark=SGP-BLOQUEIO-AVISAR action=add-src-to-address-list \
    address-list=BLOQUEIO-AVISADOS address-list-timeout=00:01:00 comment="SGP REGRAS" dst-address=$IPSGP \
    dst-port=$AVS protocol=tcp 
/ip firewall nat 
add action=accept chain=srcnat comment="NAO FAZER NAT PARA O DO RADIUS, MANTER ESSA REGRA SEMPRE EM PRIMEIRO" \
    dst-address=$RADIUS dst-port="$AUC-$ACC,3799" protocol=udp 
add action=masquerade chain=srcnat comment="SGP REGRAS" src-address-list=\
    SGP-BLOQUEADOS 
add action=dst-nat chain=dstnat comment="SGP REGRAS" dst-address-list=\
    !SGP-SITES-LIBERADOS dst-port=80,443 log-prefix="" protocol=tcp \
    src-address-list=SGP-BLOQUEADOS to-addresses=$IPSGP to-ports=$BLQ 
add action=dst-nat chain=dstnat comment="SGP REGRAS" connection-mark=\
    SGP-BLOQUEIO-AVISAR log-prefix="" protocol=tcp to-addresses=$IPSGP to-ports=$AVS
/ip firewall mangle
add chain=prerouting connection-state=new src-address-list=SGP-BLOQUEIO-AVISAR protocol=tcp dst-port=80,443 \
    action=mark-connection new-connection-mark=BLOQUEIO-VERIFICAR passthrough=yes comment="SGP REGRAS" 
add chain=prerouting connection-mark=BLOQUEIO-VERIFICAR src-address-list=!BLOQUEIO-AVISADOS \
    action=mark-connection new-connection-mark=SGP-BLOQUEIO-AVISAR comment="SGP REGRAS" 
/system scheduler
add interval=4h name=sgp-aviso on-event=sgp-aviso policy=\
    ftp,reboot,read,write,policy,test,password,sniff,sensitive start-time=01:00:00 disabled=yes
/system script
add name=sgp-aviso policy=\
    ftp,reboot,read,write,policy,test,password,sniff,sensitive source=":log info\
    \_\"sgp aviso\";\r\
    \n/file remove [find where name=sgp_aviso.rsc]\r\
    \n/tool fetch url=\"$LINKDOSGP/ws/mikrotik/aviso/pendencia/\\?token=$TOKENAQUI&app=mikrotik\" dst-path=sgp_aviso.rsc;\r\
    \n:delay 30s\r\
    \nimport file-name=sgp_aviso.rsc;\r\
    \n:delay 10s;\r\
    \n/ip firewall address-list set timeout=00:15:00 [/ip firewall address-list find list=SGP-BLOQUEIO-AVISAR]";

EOF

subl Mikrotik-$login_vpn.txt
}

Huawei () {
clear
echo "Script - Integrao Huawei-NE20/40/8000"
echo ""
echo "Preencha as seguintes informaes:"
echo ""
echo "Nome do Provedor:"
read PROVEDOR
echo "Secrets Radius: (Mnimo de 16 caracters)"
read SECRETS
echo "IP do Radius:"
read IP_RADIUS
echo "IP do NAS:"
read IP_NAS
echo "Porta do authentication:"
read AUTH_PORT
echo "Porta do accounting:"
read ACCT_PORT
echo "Interface IP NAS: (Ex: loopback0)"
read INTERFACE
echo "Nome do Pool IPv4:"
read POOLV4
echo "Nome do Pool IPv6-PD:"
read POOLPDV6
echo "Nome do Pool IPv6-Prefix:"
read POOLPREFIXOV6

cat <<EOF > Huawei-$PROVEDOR.txt

system-view

radius-server group sgp-$PROVEDOR
radius-server shared-key-cipher $SECRETS
radius-server authentication $IP_RADIUS source ip-address $IP_NAS $AUTH_PORT weight 0
radius-server accounting $IP_RADIUS source ip-address $IP_NAS $ACCT_PORT weight 0
commit
radius-server type standard
undo radius-server user-name domain-included
radius-server traffic-unit byte
commit
radius-server source interface $INTERFACE
radius-attribute case-sensitive qos-profile-name
radius-server format-attribute nas-port-id vendor redback-simple
commit
radius-server accounting-stop-packet send force
radius-server retransmit 5 timeout 10
radius-server accounting-start-packet resend 3
commi
radius-server accounting-stop-packet resend 3
radius-server accounting-interim-packet resend 5
radius-attribute assign hw-mng-ipv6 pppoe motm
commi
radius-attribute apply framed-ipv6-pool match pool-type
radius-attribute apply user-name match user-type ipoe
radius-attribute service-type value outbound user-type ipoe
commit
quit

radius local-ip all
commit
radius-server authorization $IP_RADIUS destination-port 3799 server-group sgp-$PROVEDOR shared-key $SECRETS
commit

aaa
authentication-scheme auth_$PROVEDOR
authentication-mode radius local
commit
quit
accounting-scheme acct_$PROVEDOR
accounting interim interval 5
accounting send-update
commit
quit

aaa
domain $PROVEDOR-sgp
authentication-scheme auth_$PROVEDOR
accounting-scheme acct_$PROVEDOR
commit
radius-server group sgp-$PROVEDOR
dns primary-ip 8.8.8.8
commit
dns second-ip 8.8.4.4
dns primary-ipv6 2001:4860:4860::8888
commit
dns second-ipv6 2001:4860:4860::8844
qos rate-limit-mode car inbound
commit
qos rate-limit-mode car outbound
ip-pool $POOLV4
commit
ipv6-pool $POOLPDV6
ipv6-pool $POOLPREFIXOV6
accounting-start-delay 10 online user-type ppp ipoe static
commit
quit

snmp-agent community read cipher SGP_HUAWEI_GRAPHICs
snmp-agent sys-info version v2c
commit

ip pool bloqueados bas local
gateway 10.24.0.1 255.255.252.0
section 0 10.24.0.2 10.24.3.254
commit
quit
ipv6 prefix bloqueiov6prefix local
prefix 2001:DC8:100::/40
commit
quit
ipv6 prefix bloqueiov6pd delegation
prefix 2001:DB8:900::/40 delegating-prefix-length 56
commit
quit
ipv6 pool bloqueiov6prefix bas local 
dns-server 2001:4860:4860::8888
prefix bloqueiov6prefix
commit
quit
ipv6 pool bloqueiov6pd bas delegation 
dns-server 2001:4860:4860::8888
prefix bloqueiov6pd
commit
quit

return
save
y

########################################################### CONFIGURACOES NO SGP #######################################################################

#Variaveis

Nome : HUAWEI_RATE
Descrição: Controle de banda via radius - Dinâmica
Valor : 1

Nome : BLOQUEIO_V6_PREFIX
Descrição: Suspensão de clientes IPv6
Valor : bloqueiov6prefix

Nome : BLOQUEIO_V6_PD
Descrição: Suspensão de clientes IPv6
Valor : bloqueiov6pd

Nome : HUAWEI_POOL_ENABLE
Descrição: HUAWEI_POOL_ENABLE
Valor : 1

#Recriar Radius

from apps.netcore.utils.radius import manage 
print("recriar radius Iniciando") 
manage.Manage().ResetRadius() 
print("Radius recriado")

EOF

subl Huawei-$PROVEDOR.txt
}

Cisco () {
clear
echo "Script - Integrao Cisco"
echo ""
echo "Preencha as seguintes informaes:"
echo ""
echo "Nome do Provedor:"
read NOME_PROV
echo "Secrets Radius:"
read SECRETS
echo "IP do Radius:"
read IP_RADIUS
echo "IP do NAS:"
read IP_NAS
echo "Porta do authentication:"
read AUT_PORT
echo "Porta do accounting:"
read ACC_PORT

cat <<EOF > cisco-$NOME_PROV.txt

enable
conf t

radius-server attribute 44 include-in-access-req default-vrf
no radius-server attribute 77 include-in-acct-req
no radius-server attribute 77 include-in-access-req
radius-server attribute 6 on-for-login-auth
radius-server attribute 6 support-multiple
radius-server attribute 8 include-in-access-req
radius-server attribute 32 include-in-access-req 
radius-server attribute 32 include-in-accounting-req 
radius-server attribute 55 include-in-acct-req
radius-server attribute 55 access-request include
radius-server attribute 25 access-request include
radius-server attribute nas-port format d
radius-server attribute 31 mac format ietf upper-case
radius-server attribute 31 mac format one-byte delimiter colon upper-case
radius-server attribute 31 send nas-port-detail mac-only
radius-server attribute nas-port-id include circuit-id 
radius-server dead-criteria time 15 tries 3
radius-server retransmit 6
radius-server timeout 30
radius-server deadtime 10
radius-server authorization default Framed-Protocol ppp
radius-server vsa send cisco-nas-port

radius server sgp-$NOME_PROV
address ipv4 $IP_RADIUS auth-port $AUT_PORT acct-port $ACC_PORT
timeout 5
retransmit 3
key 7 $SECRETS

aaa new-model
aaa group server radius sgp-$NOME_PROV
server name sgp-$NOME_PROV
!
aaa authentication login default local
aaa authentication login ssh local
aaa authentication ppp default group sgp-$NOME_PROV
aaa authorization exec default local 
aaa authorization network default group sgp-$NOME_PROV 
aaa authorization configuration PPPoE group sgp-$NOME_PROV
aaa accounting delay-start all
aaa accounting delay-start extended-delay 1
aaa accounting session-duration ntp-adjusted
aaa accounting update periodic 5
aaa accounting exec default none
aaa accounting network default start-stop group sgp-$NOME_PROV

aaa server radius dynamic-author
client $IP_RADIUS server-key 7 $SECRETS
server-key 7 $SECRETS
port 3799
auth-type any
ignore session-key
ignore server-key
!
aaa session-id common
aaa max-sessions 8000
aaa policy interface-config allow-subinterface
ppp packet throttle 100 10 450

policy-map OUT-PADRAO
class class-default
police cir 2000000000
conform-action transmit
exceed-action drop

policy-map IN-PADRAO
class class-default
police cir 2000000000
conform-action transmit
exceed-action drop

subscriber service multiple-accept
subscriber service session-accounting
subscriber access pppoe pre-authorize nas-port-id default
subscriber templating

ip local pool bloqueados 10.24.0.1 10.24.3.254

ipv6 local pool bloqueiov6pd 2001:DB1:100::/43 56
ipv6 local pool bloqueiov6prefix 2001:DB8:200::/48 64

ipv6 dhcp pool bloqueiov6pd
prefix-delegation pool bloqueiov6pd lifetime 1800 600
dns-server 2001:4860:4860::8888
dns-server 2001:4860:4860::8844
domain-name $DOMAIN_CISCO

EOF

subl cisco-$NOME_PROV.txt
}

Accel () {
clear
echo "Script - Integrao Accel-PPP"
echo ""
echo "Preencha as seguintes informaes:"
echo ""
echo "Nome do NAS:"
read NAS_NAME
echo "IP do NAS:"
read IP_NAS
echo "IP do Radius:"
read IP_RADIUS
echo "Secrets do Radius:"
read SECRETS
echo "Porta do authentication:"
read AUT_PORT
echo "Porta do accounting:"
read ACC_PORT
echo "Gateway Accel-PPP:"
read GW_IP_ADD

cat <<EOF > Accel-PPP-$NAS_NAME.txt

[radius]
dictionary=/usr/local/share/accel-ppp/radius/dictionary  
nas-identifier=$NAS_NAME
nas-ip-address=$IP_NAS
gw-ip-address=$GW_IP_ADD
server=$IP_RADIUS,$SECRETS,auth-port=$AUT_PORT,acct-port=$ACC_PORT,req-limit=50,fail-timeout=0,max-fail=10,weight=1
dae-server=$IP_NAS:3799,$SECRETS
acct-interim-interval=300
acct-timeout=0
max-try=30
acct-delay-time=0
interim-verbose=1
verbose=1
timeout=30
acct-on=0


#SHAPER ACCEL

[shaper]
vendor=Accel
attr=Filter-Id
ifb=ifb0
up-limiter=htb
down-limiter=tbf

#SHAPER MIKROTIK

[shaper]
vendor=Mikrotik
attr=Mikrotik-Rate-Limit
ifb=ifb0
up-limiter=htb
down-limiter=tbf
leaf-qdisc=fq_codel limit 512 flows 1024 quantum 1492 target 8ms interval 4ms noecn
verbose=1

outro exemplo:

[shaper]
verbose=1
vendor=Mikrotik
attr=Mikrotik-Rate-Limit
down-burst-factor=0.1
up-burst-factor=1.0
ifb=ifb0
up-limiter=police
down-limiter=tbf
rate-multiplier=1.088

#BLOQUEIO IPv6

[ipv6-pool]
attr-prefix=Delegated-IPv6-Prefix-Pool
attr-address=Framed-IPv6-Pool
fc00:158c:6c0::/42,64,name=bloqueiov6prefix
delegate=fc00:158c:700::/42,56,name=bloqueiov6pd

OBS:. Pools com o parmetro name devem ficar acima dos demais.

EOF

subl Accel-PPP-$NAS_NAME.txt
}

Juniper () {
clear
echo "Script - Integrao Juniper"
echo ""
echo "Preencha as seguintes informaes:"
echo ""
echo "Nome do Provedor:"
read NOME_PROV
echo "IP do Radius:"
read IP_RADIUS
echo "Secrets do Radius:"
read SECRETS
echo "IP do NAS:"
read IP_NAS
echo "Porta do authentication:"
read AUT_PORT
echo "Porta do accounting:"
read ACC_PORT

cat <<EOF > Juniper-$NOME_PROV.txt

conf 

set dynamic-profiles SGP-$NOME_PROV-Limit variables up-rate default-value 32k
set dynamic-profiles SGP-$NOME_PROV-Limit variables up-rate mandatory
set dynamic-profiles SGP-$NOME_PROV-Limit variables down-rate default-value 32k
set dynamic-profiles SGP-$NOME_PROV-Limit variables down-rate mandatory
set dynamic-profiles SGP-$NOME_PROV-Limit variables burst-up default-value 2m
set dynamic-profiles SGP-$NOME_PROV-Limit variables burst-down default-value 2m
set dynamic-profiles SGP-$NOME_PROV-Limit variables filter-up uid
set dynamic-profiles SGP-$NOME_PROV-Limit variables filter-down uid
set dynamic-profiles SGP-$NOME_PROV-Limit variables shaper-up uid
set dynamic-profiles SGP-$NOME_PROV-Limit variables shaper-down uid
set dynamic-profiles SGP-$NOME_PROV-Limit interfaces "\$junos-interface-ifd-name" unit "\$junos-interface-unit" family inet filter input "\$filter-up"
set dynamic-profiles SGP-$NOME_PROV-Limit interfaces "\$junos-interface-ifd-name" unit "\$junos-interface-unit" family inet filter output "\$filter-down"
set dynamic-profiles SGP-$NOME_PROV-Limit firewall family inet filter "\$filter-up" interface-specific
set dynamic-profiles SGP-$NOME_PROV-Limit firewall family inet filter "\$filter-up" term accept then policer "\$shaper-up"
set dynamic-profiles SGP-$NOME_PROV-Limit firewall family inet filter "\$filter-up" term accept then service-filter-hit
set dynamic-profiles SGP-$NOME_PROV-Limit firewall family inet filter "\$filter-up" term accept then accept
set dynamic-profiles SGP-$NOME_PROV-Limit firewall family inet filter "\$filter-down" interface-specific
set dynamic-profiles SGP-$NOME_PROV-Limit firewall family inet filter "\$filter-down" term accept then policer "\$shaper-down"
set dynamic-profiles SGP-$NOME_PROV-Limit firewall family inet filter "\$filter-down" term accept then service-filter-hit
set dynamic-profiles SGP-$NOME_PROV-Limit firewall family inet filter "\$filter-down" term accept then accept
set dynamic-profiles SGP-$NOME_PROV-Limit firewall policer "\$shaper-up" filter-specific
set dynamic-profiles SGP-$NOME_PROV-Limit firewall policer "\$shaper-up" logical-interface-policer
set dynamic-profiles SGP-$NOME_PROV-Limit firewall policer "\$shaper-up" if-exceeding bandwidth-limit "\$up-rate"
set dynamic-profiles SGP-$NOME_PROV-Limit firewall policer "\$shaper-up" if-exceeding burst-size-limit "\$burst-up"
set dynamic-profiles SGP-$NOME_PROV-Limit firewall policer "\$shaper-up" then discard
set dynamic-profiles SGP-$NOME_PROV-Limit firewall policer "\$shaper-down" filter-specific
set dynamic-profiles SGP-$NOME_PROV-Limit firewall policer "\$shaper-down" logical-interface-policer
set dynamic-profiles SGP-$NOME_PROV-Limit firewall policer "\$shaper-down" if-exceeding bandwidth-limit "\$down-rate"
set dynamic-profiles SGP-$NOME_PROV-Limit firewall policer "\$shaper-down" if-exceeding burst-size-limit "\$burst-down"
set dynamic-profiles SGP-$NOME_PROV-Limit firewall policer "\$shaper-down" then discard

set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables up-rate default-value 32k
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables up-rate mandatory
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables down-rate default-value 32k
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables down-rate mandatory
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables burst-up default-value 2m
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables burst-down default-value 2m
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables filter-up-v6 uid
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables filter-down-v6 uid
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables shaper-up-v6 uid
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 variables shaper-down-v6 uid
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 interfaces "\$junos-interface-ifd-name" unit "\$junos-interface-unit" family inet6 filter input "\$filter-up-v6"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 interfaces "\$junos-interface-ifd-name" unit "\$junos-interface-unit" family inet6 filter output "\$filter-down-v6"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-up-v6" interface-specific
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-up-v6" term accept then policer "\$shaper-up-v6"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-up-v6" term accept then service-filter-hit
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-up-v6" term accept then accept
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-down-v6" interface-specific
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-down-v6" term accept then policer "\$shaper-down-v6"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-down-v6" term accept then service-filter-hit
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall family inet6 filter "\$filter-down-v6" term accept then accept
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-up-v6" filter-specific
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-up-v6" logical-interface-policer
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-up-v6" if-exceeding bandwidth-limit "\$up-rate"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-up-v6" if-exceeding burst-size-limit "\$burst-up"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-up-v6" then discard
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-down-v6" filter-specific
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-down-v6" logical-interface-policer
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-down-v6" if-exceeding bandwidth-limit "\$down-rate"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-down-v6" if-exceeding burst-size-limit "\$burst-down"
set dynamic-profiles SGP-$NOME_PROV-Limit-V6 firewall policer "\$shaper-down-v6" then discard

set access radius-server $IP_RADIUS port $AUT_PORT
set access radius-server $IP_RADIUS accounting-port $ACC_PORT
set access radius-server $IP_RADIUS secret '"$SECRETS"
set access radius-server $IP_RADIUS timeout 40
set access radius-server $IP_RADIUS retry 3
set access radius-server $IP_RADIUS accounting-timeout 20
set access radius-server $IP_RADIUS accounting-retry 6
set access radius-server $IP_RADIUS source-address $IP_NAS
set access radius-disconnect-port 3799
set access radius-disconnect $IP_RADIUS secret "$SECRETS"

set access profile SGP-$NOME_PROV accounting-order radius
set access profile SGP-$NOME_PROV authentication-order radius
set access profile SGP-$NOME_PROV domain-name-server-inet 8.8.8.8
set access profile SGP-$NOME_PROV domain-name-server-inet 8.8.4.4
set access profile SGP-$NOME_PROV domain-name-server-inet6 2001:4860:4860::8888
set access profile SGP-$NOME_PROV domain-name-server-inet6 2001:4860:4860::8844
set access profile SGP-$NOME_PROV radius authentication-server $IP_RADIUS
set access profile SGP-$NOME_PROV radius accounting-server $IP_RADIUS
set access profile SGP-$NOME_PROV radius options nas-identifier 4
set access profile SGP-$NOME_PROV radius options nas-port-id-delimiter "%"
set access profile SGP-$NOME_PROV radius options nas-port-id-format nas-identifier
set access profile SGP-$NOME_PROV radius options nas-port-id-format interface-description
set access profile SGP-$NOME_PROV radius options nas-port-type ethernet ethernet
set access profile SGP-$NOME_PROV radius options calling-station-id-delimiter :
set access profile SGP-$NOME_PROV radius options calling-station-id-format mac-address
set access profile SGP-$NOME_PROV radius options accounting-session-id-format decimal
set access profile SGP-$NOME_PROV radius options client-authentication-algorithm direct
set access profile SGP-$NOME_PROV radius options client-accounting-algorithm direct
set access profile SGP-$NOME_PROV radius options service-activation dynamic-profile required-at-login
set access profile SGP-$NOME_PROV accounting order radius
set access profile SGP-$NOME_PROV accounting coa-immediate-update
set access profile SGP-$NOME_PROV accounting update-interval 10
set access profile SGP-$NOME_PROV accounting statistics volume-time
set access domain map default access-profile SGP-$NOME_PROV

set access address-assignment pool bloqueiov6prefix family inet6 prefix 2001:D08:100::/40
set access address-assignment pool bloqueiov6prefix family inet6 range ipv6-pppoe prefix-length 64
set access address-assignment pool bloqueiov6pd family inet6 prefix 2001:DB8:900::/40
set access address-assignment pool bloqueiov6pd family inet6 range prefixn-range prefix-length 64

commit

########################################################### CONFIGURACOES NO SGP #######################################################################

#Setar profile nos planos do SGP em Lote:

Menu: TSMX/WebShell Script

radius={
  "reply": [
    {
      "attribute": "ERX-Service-Activate:1",
      "value": "\"SGP-$NOME_PROV-Limit({upload}M,{download}M)\"",
      "op": "+="
    },
    {
      "attribute": "ERX-Service-Activate:2",
      "value": "\"SGP-$NOME_PROV-Limit-V6({upload}M,{download}M)\"",
      "op": "+="
    }
  ]
}
from apps.admcore import models
from apps.netcore.utils.radius import manage
print(models.PlanoInternet.objects.all().update(radius_json=radius))
m = manage.Manage()
for i in models.PlanoInternet.objects.all():
    m.delRadiusPlano(i)
    m.addRadiusPlano(i)

#Variaveis

Nome : BLOQUEIO_V6_PREFIX
Descrição: Suspensão de clientes IPv6
Valor : bloqueiov6prefix

Nome : BLOQUEIO_V6_PD
Descrição: Suspensão de clientes IPv6
Valor : bloqueiov6pd

Nome : ERX_POOL_ENABLE
Descrição: ERX_POOL_ENABLE
Valor : 1

EOF

subl Juniper-$NOME_PROV.txt
}

Voltar() {
    clear
        Menu
}

Sair() {
    clear
    exit
}
clear
Menu


