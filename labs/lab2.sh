# Lab 2: Routing between two IPv6 LANs, dual stack, Path MTU and NAT64/DNS64
#        (Day 1-2 topics only; DHCPv6 and firewalls are Day 3 lecture topics, so they live in Lab 3)
# Topology:  pc1 --eth0-- r1 --eth1====eth1-- r2 --eth0-- pc2
#           LAN A 2001:db8:a::/64   link 2001:db8:ff::/64   LAN B 2001:db8:b::/64
#           (SLAAC from r1)                                   (SLAAC from r2)
# Part J: r2 is the NAT64 gateway (tayga, tun device nat64, prefix 64:ff9b::/96, pool 192.168.255.0/24)
#         and the DNS64 resolver (unbound on 2001:db8:b::1); pc2 answers A web.lab = 100.64.0.10
#         (dnsmasq on 100.64.0.10 only). r2 needs /dev/net/tun, hence "start_node r2 tun".
#         Why 100.64.0.10: Ubuntu's tayga 0.9.2 drops 64:ff9b::/96 traffic to non-global IPv4
#         (RFC 1918 and the documentation ranges) and has no switch for it; it accepts 100.64.0.0/10.
LAB_NODES="pc1 r1 r2 pc2"

lab_nodes_start() { start_node pc1; start_node r1; start_node r2 tun; start_node pc2; }
lab_links() {
  L pc1 eth0 52:54:00:a2:00:01  r1 eth0 52:54:00:a2:00:fe
  L r1  eth1 52:54:00:a2:ff:01  r2 eth1 52:54:00:a2:ff:02
  L r2  eth0 52:54:00:a2:0b:fe  pc2 eth0 52:54:00:a2:0b:02
}
lab_prestage() { :; }   # students configure everything

# The answer key leaves the lab as it is after Part J's "Put it back":
# pc1 dual stack again, web server on pc2 listening on ::, NAT64/DNS64 still running.
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

  # ---- Part J: NAT64 (tayga) and DNS64 (unbound) on r2, IPv4-only DNS on pc2 ----
  # LAN B gets a second IPv4 subnet, 100.64.0.0/24, that tayga treats as public
  X r2 "ip addr add 100.64.0.1/24 dev eth0 2>/dev/null; true"
  X pc2 "ip addr add 100.64.0.10/24 dev eth0 2>/dev/null; true"
  # pc2: answers "A web.lab = 100.64.0.10" and nothing for AAAA (NODATA), on IPv4 only
  X pc2 "pkill -x dnsmasq; sleep 1
         dnsmasq -u root --no-resolv --no-hosts --listen-address=100.64.0.10 --bind-interfaces \
           --address=/web.lab/100.64.0.10 --local-ttl=60 --log-queries --log-facility=/tmp/dns.log \
           </dev/null >/dev/null 2>&1" || echo "  warning: dnsmasq on pc2 did not start"
  # r1: send the NAT64 prefix to r2
  X r1 "ip -6 route replace 64:ff9b::/96 via 2001:db8:ff::2"
  # r2: tayga (ipv6-addr is required with 64:ff9b::/96 and a private ipv4-addr)
  X r2 "printf '%s\n' 'tun-device nat64' 'ipv4-addr 192.168.255.1' 'ipv6-addr 2001:db8:b:64::1' \
          'prefix 64:ff9b::/96' 'dynamic-pool 192.168.255.0/24' \
          'data-dir /var/spool/tayga' > /etc/tayga.conf
        mkdir -p /var/spool/tayga
        ip link show nat64 >/dev/null 2>&1 || tayga --mktun >/dev/null 2>&1
        ip link set nat64 up
        ip -6 route replace 64:ff9b::/96 dev nat64
        ip route replace 192.168.255.0/24 dev nat64
        pgrep -x tayga >/dev/null || tayga </dev/null >/dev/null 2>&1; true"
  # r2: unbound can bind 2001:db8:b::1 only once DAD has finished (address no longer tentative)
  retry 10 X r2 "ip -6 addr show dev eth0 | grep '2001:db8:b::1/64' | grep -vq tentative"
  X r2 "printf '%s\n' 'server:' '    interface: 2001:db8:b::1' \
          '    access-control: 2001:db8:a::/64 allow' '    access-control: 2001:db8:b::/64 allow' \
          '    access-control: 2001:db8:ff::/64 allow' \
          '    module-config: \"dns64 iterator\"' '    dns64-prefix: 64:ff9b::/96' \
          '    domain-insecure: \"lab.\"' '    username: \"\"' '    chroot: \"\"' \
          '    logfile: \"/tmp/unbound.log\"' '    verbosity: 1' \
          'forward-zone:' '    name: \"lab.\"' '    forward-addr: 100.64.0.10' > /etc/unbound/lab.conf
        pkill -x unbound; sleep 1
        unbound -c /etc/unbound/lab.conf </dev/null >/dev/null 2>&1" || echo "  warning: unbound on r2 did not start"
}

PC2_V6=2001:db8:b:0:5054:ff:fea2:b02   # EUI-64 from pc2's MAC 52:54:00:a2:0b:02
NAT64_PC2=64:ff9b::6440:a              # 64:ff9b::/96 + 100.64.0.10 (6440:000a)

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
  # the two IPv4 checks below fail while pc1 is IPv6-only in Part J; Part J's "Put it back" fixes that
  expect "pc1 can ping pc2 over IPv4 (10.2.0.10)" X pc1 "ping -c1 -W2 10.2.0.10"
  expect "web on pc2 answers over IPv6" retry 5 X pc1 "curl -s -m3 -g 'http://[${v6:-2001:db8:b::dead}]:8080/' | grep -q pc2"
  expect "web on pc2 answers over IPv4" retry 5 X pc1 "curl -s -m3 http://10.2.0.10:8080/ | grep -q pc2"
  expect "r2 reaches pc2 on LAN B (neighbor discovery works)" \
         X r2 "ip -6 neigh flush dev eth0; ping -6 -c1 -W2 ${v6:-2001:db8:b::dead}"
  # Part J
  expect "r2 runs the NAT64 translator (tayga)" X r2 "pgrep -x tayga"
  expect "DNS64 on r2 answers AAAA web.lab = $NAT64_PC2" \
         retry 5 X pc1 "dig +short +time=2 +tries=1 AAAA web.lab @2001:db8:b::1 | grep -qx '$NAT64_PC2'"
  expect "pc1 reaches pc2's web server through NAT64 ($NAT64_PC2)" \
         retry 5 X pc1 "curl -s -m3 -g 'http://[$NAT64_PC2]:8080/' | grep -q pc2"
}
