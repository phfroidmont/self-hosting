#!/bin/bash

# Clear config
iptables -t nat -F
iptables -t mangle -F
iptables -F
iptables -X


echo 1 > /proc/sys/net/ipv4/ip_forward

PORTS_TO_FORWARD_TCP_STORAGE="53 80 143 443 2224 3478 8008 8448 27015 64738"
PORTS_TO_FORWARD_UDP_STORAGE="53 34197 64738"
PORTS_TO_FORWARD_TCP_MAIL="25 110 143 465 587 993 995"

DESTINATION_IP_STORAGE="5.9.66.49"
DESTINATION_IP_MAIL="5.9.66.49"

for port in `echo $PORTS_TO_FORWARD_TCP_STORAGE`
do
	iptables -t nat -A PREROUTING -p tcp -m tcp --dport ${port} -j DNAT --to-destination ${DESTINATION_IP_STORAGE}
	iptables -A FORWARD -d ${DESTINATION_IP_STORAGE}/32 -p tcp -m tcp --dport ${port} -j ACCEPT
done

for port in `echo $PORTS_TO_FORWARD_UDP_STORAGE`
do
	iptables -t nat -A PREROUTING -p udp -m udp --dport ${port} -j DNAT --to-destination ${DESTINATION_IP_STORAGE}
	iptables -A FORWARD -d ${DESTINATION_IP_STORAGE}/32 -p tcp -m tcp --dport ${port} -j ACCEPT
done

for port in `echo $PORTS_TO_FORWARD_TCP_MAIL`
do
	iptables -t nat -A PREROUTING -p tcp -m tcp --dport ${port} -j DNAT --to-destination ${DESTINATION_IP_MAIL}
	iptables -A FORWARD -d ${DESTINATION_IP_MAIL}/32 -p tcp -m tcp --dport ${port} -j ACCEPT
done

iptables -t nat -A POSTROUTING -j MASQUERADE
