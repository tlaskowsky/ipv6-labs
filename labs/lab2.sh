# Lab 2: Routing between two IPv6 LANs and dual stack (Day 1-2 topics only;
#        DHCPv6 and firewalls are Day 3 lecture topics, so they live in Lab 3's bonus)
# Topology:  pc1 --eth0-- r1 --eth1====eth1-- r2 --eth0-- pc2
#           LAN-A 2001:db8:a::/64   link 2001:db8:ff::/64   LAN-B 2001:db8:b::/64
#           (SLAAC from r1)                                   (SLAAC from r2)
LAB_NODES="pc1 r1 r2 pc2"

lab_nodes_start() { start_node pc1; start_node r1; start_node r2; start_node pc2; }
lab_links() {
  L pc1 eth0 52:54:00:a2:00:01  r1 eth0 52:54:00:a2:00:fe
  L r1  eth1 52:54:00:a2:ff:01  r2 eth1 52:54:00:a2:ff:02
  L r2  eth0 52:54:00:a2:0b:fe  pc2 eth0 52:54:00:a2:0b:02
}
lab_prestage() { :; }   # students configure everything

lab_solve() {
  X r1 "sysctl -qw net.ipv6.conf.all.forwarding=1 net.ipv4.ip_forward=1
        ip -6 addr add 2001:db8:a::1/64 dev eth0 2>/dev/null
        ip -6 addr add 2001:db8:ff::1/64 dev eth1 2>/dev/null
        printf '%s\n' 'interface eth0 {' ' AdvSendAdvert on; MinRtrAdvInterval 3; MaxRtrAdvInterval 10;' \
          ' prefix 2001:db8:a::/64 { AdvOnLink on; AdvAutonomous on; };' '};' > /etc/radvd.conf
        pkill radvd; radvd
        ip -6 route replace 2001:db8:b::/64 via 2001:db8:ff::2
        ip addr add 10.1.0.1/24 dev eth0 2>/dev/null; ip addr add 10.255.0.1/30 dev eth1 2>/dev/null
        ip route replace 10.2.0.0/24 via 10.255.0.2; true"
  X r2 "sysctl -qw net.ipv6.conf.all.forwarding=1 net.ipv4.ip_forward=1
        ip -6 addr add 2001:db8:b::1/64 dev eth0 2>/dev/null
        ip -6 addr add 2001:db8:ff::2/64 dev eth1 2>/dev/null
        printf '%s\n' 'interface eth0 {' ' AdvSendAdvert on; MinRtrAdvInterval 3; MaxRtrAdvInterval 10;' \
          ' prefix 2001:db8:b::/64 { AdvOnLink on; AdvAutonomous on; };' '};' > /etc/radvd.conf
        pkill radvd; radvd
        ip -6 route replace 2001:db8:a::/64 via 2001:db8:ff::1
        ip addr add 10.2.0.1/24 dev eth0 2>/dev/null; ip addr add 10.255.0.2/30 dev eth1 2>/dev/null
        ip route replace 10.1.0.0/24 via 10.255.0.1; true"
  X pc1 "ip addr add 10.1.0.10/24 dev eth0 2>/dev/null; ip route replace default via 10.1.0.1; true"
  X pc2 "ip addr add 10.2.0.10/24 dev eth0 2>/dev/null; ip route replace default via 10.2.0.1; true"
  XD pc2 "cd /tmp && echo 'Hello from pc2' > index.html && exec python3 -m http.server 8080 --bind ::"
  # wait until the web server listens (a cold, small machine can take a few seconds)
  retry 20 X pc2 "ss -ltn | grep -q ':8080 '" || echo "  warning: web server on pc2 did not start"
}

PC2_V6=2001:db8:b:0:5054:ff:fea2:b02   # EUI-64 from pc2's MAC 52:54:00:a2:0b:02

lab_check() {
  expect "r1 has IPv6 forwarding on" X r1 "[ \$(sysctl -n net.ipv6.conf.all.forwarding) = 1 ]"
  expect "r2 has IPv6 forwarding on" X r2 "[ \$(sysctl -n net.ipv6.conf.all.forwarding) = 1 ]"
  expect "pc1 got SLAAC address 2001:db8:a:0:5054:ff:fea2:1" \
         retry 20 X pc1 "ip -6 addr show dev eth0 | grep -q '2001:db8:a:0:5054:ff:fea2:1/64'"
  expect "pc2 got SLAAC address $PC2_V6" \
         retry 20 X pc2 "ip -6 addr show dev eth0 | grep -q '$PC2_V6/64'"
  expect "r1 can reach r2 across the link (2001:db8:ff::2)" X r1 "ping -6 -c1 -W2 2001:db8:ff::2"
  local v6=$PC2_V6
  expect "pc1 can ping pc2 over IPv6 (${v6:-no address})" X pc1 "ping -6 -c1 -W2 ${v6:-2001:db8:b::dead}"
  expect "traceroute pc1 -> pc2 goes via r1 and r2" \
         X pc1 "traceroute -6 -n -w1 -q1 ${v6:-2001:db8:b::dead} | grep -q '2001:db8:ff::2'"
  expect "pc1 can ping pc2 over IPv4 (10.2.0.10)" X pc1 "ping -c1 -W2 10.2.0.10"
  expect "web on pc2 answers over IPv6" retry 5 X pc1 "curl -s -m3 -g 'http://[${v6:-2001:db8:b::dead}]:8080/' | grep -q pc2"
  expect "web on pc2 answers over IPv4" retry 5 X pc1 "curl -s -m3 http://10.2.0.10:8080/ | grep -q pc2"
  expect "r2 reaches pc2 on LAN B (neighbor discovery works)" \
         X r2 "ip -6 neigh flush dev eth0; ping -6 -c1 -W2 ${v6:-2001:db8:b::dead}"
}
