# Lab 3: IPv6 across an IPv4-only network - GRE and 6in4 tunnels
# Topology:  pc1 -- r1 ==== inet (IPv4 only) ==== r2 -- pc2
#     LAN-A 2001:db8:a::/64      192.0.2.0/30   198.51.100.0/30     LAN-B 2001:db8:b::/64
# Pre-built: both LANs already work (radvd on r1/r2), IPv4 between r1 and r2 works.
LAB_NODES="pc1 r1 inet r2 pc2"

lab_nodes_start() { start_node pc1; start_node r1; start_node inet noipv6 v4fwd; start_node r2; start_node pc2; }
lab_links() {
  L pc1  eth0 52:54:00:a3:00:01  r1   eth0 52:54:00:a3:00:fe
  L r1   eth1 52:54:00:a3:01:01  inet eth0 52:54:00:a3:01:fe
  L inet eth1 52:54:00:a3:02:fe  r2   eth1 52:54:00:a3:02:01
  L r2   eth0 52:54:00:a3:0b:fe  pc2  eth0 52:54:00:a3:00:02
}
radvd_for() {  # $1 = prefix
  printf '%s\n' 'interface eth0 {' ' AdvSendAdvert on; MinRtrAdvInterval 3; MaxRtrAdvInterval 10;' \
    " prefix $1 { AdvOnLink on; AdvAutonomous on; };" '};'
}
lab_prestage() {
  X inet "ip addr add 192.0.2.1/30 dev eth0 && ip addr add 198.51.100.1/30 dev eth1"
  X r1 "sysctl -qw net.ipv6.conf.all.forwarding=1
        ip addr add 192.0.2.2/30 dev eth1 && ip route add default via 192.0.2.1
        ip -6 addr add 2001:db8:a::1/64 dev eth0
        echo '$(radvd_for 2001:db8:a::/64)' > /etc/radvd.conf && radvd"
  X r2 "sysctl -qw net.ipv6.conf.all.forwarding=1
        ip addr add 198.51.100.2/30 dev eth1 && ip route add default via 198.51.100.1
        ip -6 addr add 2001:db8:b::1/64 dev eth0
        echo '$(radvd_for 2001:db8:b::/64)' > /etc/radvd.conf && radvd"
}

lab_solve() {
  X r1 "ip tunnel add gre1 mode gre local 192.0.2.2 remote 198.51.100.2 ttl 255
        ip link set gre1 up
        ip -6 addr add 2001:db8:fe::1/64 dev gre1
        ip -6 route replace 2001:db8:b::/64 via 2001:db8:fe::2"
  X r2 "ip tunnel add gre1 mode gre local 198.51.100.2 remote 192.0.2.2 ttl 255
        ip link set gre1 up
        ip -6 addr add 2001:db8:fe::2/64 dev gre1
        ip -6 route replace 2001:db8:a::/64 via 2001:db8:fe::1"
}

lab_check() {
  expect "inet has no IPv6 at all" X inet "! ip -6 addr show | grep -q inet6"
  expect "r1 reaches r2 over IPv4 (198.51.100.2)" X r1 "ping -c1 -W2 198.51.100.2"
  expect "pc1 has SLAAC address 2001:db8:a:0:5054:ff:fea3:1" \
         retry 20 X pc1 "ip -6 addr show dev eth0 | grep -q '2001:db8:a:0:5054:ff:fea3:1/64'"
  expect "pc2 has SLAAC address 2001:db8:b:0:5054:ff:fea3:2" \
         retry 20 X pc2 "ip -6 addr show dev eth0 | grep -q '2001:db8:b:0:5054:ff:fea3:2/64'"
  expect "r1 has a tunnel interface that is up" X r1 "ip -d link show | grep -Eq '(gre|sit|ipip)[^ ]* remote'"
  expect "pc1 pings pc2 over IPv6 through the tunnel" X pc1 "ping -6 -c2 -W2 2001:db8:b:0:5054:ff:fea3:2"
  # Prove the packets cross inet as IPv4 (GRE = proto 47, 6in4 = proto 41)
  X inet "rm -f /tmp/cap; (timeout 6 tcpdump -c1 -ni eth0 'ip proto 47 or ip proto 41' > /tmp/cap 2>/dev/null &)"
  sleep 1; X pc1 "ping -6 -c3 -W1 2001:db8:b:0:5054:ff:fea3:2" >/dev/null 2>&1; sleep 2
  expect "inet sees the IPv6 traffic only as IPv4 tunnel packets" X inet "grep -Eq 'GRE|IP6|ip-proto-41' /tmp/cap"
}
