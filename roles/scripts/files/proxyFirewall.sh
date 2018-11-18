#!/bin/bash

# Clear config
iptables -t nat -F
iptables -t mangle -F
iptables -F
iptables -X


echo 1 > /proc/sys/net/ipv4/ip_forward

PORTS_TO_FORWARD_TCP="25 53 80 110 143 443 465 587 993 995 2224 3478 8008 8448 27015 64738"
PORTS_TO_FORWARD_UDP="53 34197 64738"
#DESTINATION_IP="212.83.165.111"
DESTINATION_IP="5.9.66.49"

for port in `echo $PORTS_TO_FORWARD_TCP`
do
	iptables -t nat -A PREROUTING -p tcp -m tcp --dport ${port} -j DNAT --to-destination ${DESTINATION_IP}
	iptables -A FORWARD -d ${DESTINATION_IP}/32 -p tcp -m tcp --dport ${port} -j ACCEPT
done

for port in `echo $PORTS_TO_FORWARD_UDP`
do
	iptables -t nat -A PREROUTING -p udp -m udp --dport ${port} -j DNAT --to-destination ${DESTINATION_IP}
	iptables -A FORWARD -d ${DESTINATION_IP}/32 -p tcp -m tcp --dport ${port} -j ACCEPT
done
iptables -t nat -A POSTROUTING -j MASQUERADE
