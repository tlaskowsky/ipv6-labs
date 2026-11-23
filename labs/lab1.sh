# Lab 1: Link-local addresses, Neighbor Discovery and SLAAC
# Topology (one LAN):   pc1 ---+
#                       pc2 ---+-- sw1 (plain Ethernet switch, hidden)
#                       r1  ---+
LAB_NODES="pc1 pc2 r1"

lab_nodes_start() {
  start_node sw1 noipv6
  start_node pc1; start_node pc2; start_node r1
}
lab_links() {
  L pc1 eth0 52:54:00:a1:00:01  sw1 p1 -
  L pc2 eth0 52:54:00:a1:00:02  sw1 p2 -
  L r1  eth0 52:54:00:a1:00:fe  sw1 p3 -
}
lab_prestage() {
  # sw1 becomes a dumb switch (Linux bridge, multicast snooping off so ND always floods)
  X sw1 'ip link add br0 type bridge && ip link set br0 type bridge mcast_snooping 0 &&
         for p in p1 p2 p3; do ip link set $p master br0; done && ip link set br0 up'
}

RADVD_CONF='interface eth0 {
    AdvSendAdvert on;
    MinRtrAdvInterval 3;
    MaxRtrAdvInterval 10;
    prefix 2001:db8:a::/64 {
        AdvOnLink on;
        AdvAutonomous on;
    };
};'

lab_solve() {
  X r1 "sysctl -qw net.ipv6.conf.all.forwarding=1
        ip -6 addr add 2001:db8:a::1/64 dev eth0 2>/dev/null || true
        cat > /etc/radvd.conf <<'R'
$RADVD_CONF
R
        pkill radvd; radvd"
}

lab_check() {
  expect "pc1 link-local is fe80::5054:ff:fea1:1 (EUI-64 from its MAC)" \
         X pc1 "ip -6 addr show dev eth0 | grep -q 'fe80::5054:ff:fea1:1/64'"
  expect "pc1 can ping pc2 link-local (fe80::5054:ff:fea1:2%eth0)" \
         X pc1 "ping -6 -c1 -W2 fe80::5054:ff:fea1:2%eth0"
  expect "r1 has 2001:db8:a::1/64 on eth0" X r1 "ip -6 addr show dev eth0 | grep -q '2001:db8:a::1/64'"
  expect "r1 forwarding is on"             X r1 "[ \$(sysctl -n net.ipv6.conf.all.forwarding) = 1 ]"
  expect "radvd is running on r1"          X r1 "pgrep -x radvd"
  expect "pc1 got SLAAC address 2001:db8:a:0:5054:ff:fea1:1" \
         retry 20 X pc1 "ip -6 addr show dev eth0 | grep -q '2001:db8:a:0:5054:ff:fea1:1/64'"
  expect "pc2 got SLAAC address 2001:db8:a:0:5054:ff:fea1:2" \
         retry 20 X pc2 "ip -6 addr show dev eth0 | grep -q '2001:db8:a:0:5054:ff:fea1:2/64'"
  expect "pc1 default route points at r1 (fe80::5054:ff:fea1:fe)" \
         X pc1 "ip -6 route show default | grep -q 'via fe80::5054:ff:fea1:fe'"
  expect "pc1 can ping pc2 global address" X pc1 "ping -6 -c1 -W2 2001:db8:a:0:5054:ff:fea1:2"
  expect "pc1 can ping r1 2001:db8:a::1"   X pc1 "ping -6 -c1 -W2 2001:db8:a::1"
}
