# Lab 3: IPv6 Across an IPv4-Only Network (Tunnels)

**You will:** connect two IPv6 sites across a network that only speaks IPv4, first with a GRE tunnel, then with a 6in4 (SIT) tunnel, and see what tunnels do to the MTU.

**Topology:**

```
 pc1 --eth0 [r1] eth1 ---- [inet] ---- eth1 [r2] eth0-- pc2
 2001:db8:a::/64    192.0.2.0/30   198.51.100.0/30    2001:db8:b::/64
```

`inet` is an IPv4-only router that stands in for the internet. It has no IPv6 at all.

**Already done for you:** both LANs work (r1 and r2 run radvd), and r1 can reach r2 over IPv4.

| Node | Address |
|---|---|
| r1 eth1 | 192.0.2.2/30 (default route to inet) |
| r2 eth1 | 198.51.100.2/30 (default route to inet) |
| pc1 | 2001:db8:a:0:5054:ff:fea3:1 |
| pc2 | 2001:db8:b:0:5054:ff:fea3:2 |

---

## Part A: See the problem

1. On r1: `ping -c2 198.51.100.2` works (IPv4).
2. On pc1: `ping -6 -c2 2001:db8:b:0:5054:ff:fea3:2` fails. r1 has no IPv6 path to LAN B.
3. On inet: `ip -6 addr` shows nothing. IPv6 cannot cross it as-is.

## Part B: GRE tunnel

1. On **r1**:
   ```
   ip tunnel add gre1 mode gre local 192.0.2.2 remote 198.51.100.2 ttl 255
   ip link set gre1 up
   ip -6 addr add 2001:db8:fe::1/64 dev gre1
   ip -6 route add 2001:db8:b::/64 via 2001:db8:fe::2
   ```
2. On **r2**, the mirror image:
   ```
   ip tunnel add gre1 mode gre local 198.51.100.2 remote 192.0.2.2 ttl 255
   ip link set gre1 up
   ip -6 addr add 2001:db8:fe::2/64 dev gre1
   ip -6 route add 2001:db8:a::/64 via 2001:db8:fe::1
   ```
3. From pc1: `ping -6 -c3 2001:db8:b:0:5054:ff:fea3:2` now works.
4. Prove that inet only sees IPv4. On **inet**, capture while you ping from pc1:
   ```
   tcpdump -ni eth0 -c4 'ip proto 47'
   ```
   **Expected:** lines like `IP 192.0.2.2 > 198.51.100.2: GREv0 ... IP6 2001:db8:a::... > 2001:db8:b::...` The IPv6 packet rides inside an IPv4 GRE packet (IP protocol 47).

## Part C: Tunnels and MTU

1. On r1: `ip link show gre1`. **Expected:** `mtu 1476` (1500 minus 20 bytes of outer IPv4 and 4 bytes of GRE).
2. From pc1, send a full-size packet and forbid fragmenting it:
   ```
   ping -6 -c2 -M do -s 1452 2001:db8:b:0:5054:ff:fea3:2
   ```
   1452 bytes of data + 8 ICMPv6 + 40 IPv6 = 1500 bytes. **Expected:** `From 2001:db8:a::1 ... Packet too big: mtu=1476` (that is r1). The second packet shows `message too long, mtu: 1476` because pc1 has already learned the smaller size. IPv6 routers never fragment; they send ICMPv6 Packet Too Big back to the sender.
3. Try `-s 1428` (1428 + 48 = 1476). It works.
4. Check what pc1 learned: `ip -6 route get 2001:db8:b:0:5054:ff:fea3:2` shows `mtu 1476`. This is Path MTU Discovery. It is why Packet Too Big must never be blocked by a firewall.

## Part D: 6in4 (SIT) instead of GRE

1. Remove the GRE tunnel on **both** routers:
   ```
   ip tunnel del gre1
   ```
2. On **r1**:
   ```
   ip tunnel add sit1 mode sit local 192.0.2.2 remote 198.51.100.2 ttl 255
   ip link set sit1 up
   ip -6 addr add 2001:db8:fe::1/64 dev sit1
   ip -6 route add 2001:db8:b::/64 via 2001:db8:fe::2
   ```
3. On **r2**, mirror it with `local 198.51.100.2 remote 192.0.2.2`, address `2001:db8:fe::2/64` and a route to `2001:db8:a::/64` via `2001:db8:fe::1`.
4. Ping from pc1 again, and on inet capture `tcpdump -ni eth0 -c4 'ip proto 41'`.
5. Compare with GRE:
   - IP protocol number on the wire: GRE is 47, 6in4 is 41.
   - Tunnel MTU (`ip link show sit1`): 1480 instead of 1476. 6in4 has no extra header, only the outer IPv4.
   - GRE can carry other protocols too (IPv4, multicast for routing protocols). 6in4 carries only IPv6.

## Check yourself

- Why does the tunnel need IPv4 addresses on both ends but IPv6 addresses inside?
- What would break if a firewall on the path dropped ICMPv6 Packet Too Big?
- When would you pick GRE over 6in4?

---

# Stretch exercises (about 95 minutes)

Do these after Parts A to D, in order, on the same five nodes. You finished Part D with a 6in4 (`sit1`) tunnel.

## S1: Where did inet go? (10 min)

1. From pc1:
   ```
   traceroute -6 -n 2001:db8:b:0:5054:ff:fea3:2
   ```
   **Expected:** three hops: `2001:db8:a::1` (r1), `2001:db8:fe::2` (r2 at the far end of the tunnel), then pc2. inet never shows up.
2. Why not? The IPv6 hop limit only goes down at r1 and r2. inet forwards the outer IPv4 packet and lowers the **IPv4** TTL, which the IPv6 packet inside never sees. To IPv6, the whole IPv4 network is one hop.

## S2: Back to GRE, and carry IPv4 through it too (20 min)

1. Swap the 6in4 tunnel back to GRE.
   On **r1**:
   ```
   ip tunnel del sit1
   ip tunnel add gre1 mode gre local 192.0.2.2 remote 198.51.100.2 ttl 255
   ip link set gre1 up
   ip -6 addr add 2001:db8:fe::1/64 dev gre1
   ip -6 route add 2001:db8:b::/64 via 2001:db8:fe::2
   ```
   On **r2**, the mirror image:
   ```
   ip tunnel del sit1
   ip tunnel add gre1 mode gre local 198.51.100.2 remote 192.0.2.2 ttl 255
   ip link set gre1 up
   ip -6 addr add 2001:db8:fe::2/64 dev gre1
   ip -6 route add 2001:db8:a::/64 via 2001:db8:fe::1
   ```
   Check from pc1 that `ping -6 -c2 2001:db8:b:0:5054:ff:fea3:2` works again.
2. Give both LANs private IPv4 networks and route them through the tunnel:
   ```
   # r1
   sysctl -w net.ipv4.ip_forward=1
   ip addr add 10.1.0.1/24 dev eth0
   ip route add 10.2.0.0/24 dev gre1
   # r2
   sysctl -w net.ipv4.ip_forward=1
   ip addr add 10.2.0.1/24 dev eth0
   ip route add 10.1.0.0/24 dev gre1
   # pc1
   ip addr add 10.1.0.10/24 dev eth0; ip route add default via 10.1.0.1
   # pc2
   ip addr add 10.2.0.10/24 dev eth0; ip route add default via 10.2.0.1
   ```
3. From pc1: `ping -c2 10.2.0.10`. **Expected:** it works.
4. On inet, prove it has no idea where 10.2.0.0 is, yet carries the traffic:
   ```
   ip route get 10.2.0.10
   tcpdump -ni eth0 -c2 'ip proto 47'      # then ping 10.2.0.10 from pc1 again
   ```
   **Expected:** `Network is unreachable` for the route lookup, and in the capture `GREv0 ... IP 10.1.0.10 > 10.2.0.10`. GRE carries IPv4 as easily as IPv6. A 6in4 tunnel could not do this; it carries only IPv6.

## S3: GRE keys (10 min)

A GRE key is a number both ends must agree on. It separates tunnels that share the same two endpoints. It is **not** a password.

1. On r1 only: `ip tunnel change gre1 ikey 42 okey 42`
2. From pc1: `ping -6 -c2 -W1 2001:db8:b:0:5054:ff:fea3:2`. **Expected:** 100% packet loss. r2 drops GRE packets that carry a key it does not expect.
3. On inet, capture one packet while you ping again: `tcpdump -ni eth0 -c1 'ip proto 47'`. **Expected:** `GREv0, key=0x2a` (42 in hex). Anyone on the path can read the key.
4. On r2: `ip tunnel change gre1 ikey 42 okey 42`. Ping again. **Expected:** it works. Leave the key on both routers.
5. Check `ip link show gre1` on r1. The MTU is now **1472**: the key added 4 more bytes of GRE header.

## S4: A tunnel is not encryption (10 min)

1. On inet, capture with the packet contents shown:
   ```
   tcpdump -ni eth0 -c1 -X 'ip proto 47'
   ```
2. From pc1, send a ping filled with the bytes of the word SECRET:
   ```
   ping -6 -c1 -p 534543524554 2001:db8:b:0:5054:ff:fea3:2
   ```
   **Expected:** the right-hand column of the capture shows `SECRETSECRETSECRET...`. GRE and 6in4 hide nothing. To protect traffic across an untrusted network you add IPsec (or a VPN such as WireGuard) around or instead of the tunnel.

## S5: The Path MTU black hole, and MSS clamping (30 min)

This is the most common real-world tunnel problem: small pings work, but large downloads hang.

1. On **pc2**, make a large file and serve it:
   ```
   cd /tmp && head -c 300000 /dev/urandom > big.bin
   python3 -m http.server 8080 --bind :: &
   ```
2. On **pc1**, download it:
   ```
   curl -6 -s -o /dev/null -m 10 -w '%{size_download} bytes\n' -g 'http://[2001:db8:b:0:5054:ff:fea3:2]:8080/big.bin'
   ```
   **Expected:** `300000 bytes`. pc2 sent 1500-byte packets, r2 answered with Packet Too Big, and pc2 resent smaller ones (Part C). If you get `0 bytes`, the web server was still starting; try again.
3. **Break it.** On r2, drop the Packet Too Big messages it sends, the way a badly configured firewall would. On pc2, forget what it learned:
   ```
   # r2
   nft add table inet lab
   nft add chain inet lab out '{ type filter hook output priority 0; }'
   nft add rule inet lab out icmpv6 type packet-too-big drop
   # pc2
   ip -6 route flush cache
   ```
   Run the same curl on pc1 again. **Expected:** `0 bytes` after 10 seconds. The connection opens (small packets), but every full-size data packet is dropped at r2 and pc2 is never told why. That is a black hole.
4. **Work around it.** On r1, rewrite the TCP maximum segment size in every new connection so it fits the tunnel:
   ```
   nft add table inet clamp
   nft add chain inet clamp transit '{ type filter hook forward priority 0; }'
   nft add rule inet clamp transit tcp flags syn tcp option maxseg size set rt mtu
   ```
   On pc2, run `ip -6 route flush cache` again, then repeat the curl on pc1. **Expected:** `300000 bytes`, even though Packet Too Big is still blocked.
5. See what changed. On pc2: `tcpdump -ni eth0 -c1 'tcp dst port 8080'`, then run the curl on pc1 once more. **Expected:** `mss 1412` in the SYN (tunnel MTU 1472, minus 40 bytes of IPv6 and 20 of TCP). Without the clamp it would say `mss 1440`.
6. Clean up: `nft delete table inet clamp` on r1, `nft delete table inet lab` on r2, and `ip -6 route flush cache` on pc2.

MSS clamping only helps TCP. The real fix is to never block ICMPv6 Packet Too Big.

## S6: Break it, find it, fix it (15 min)

For each fault: make the change, predict what pc1 will see, test with `ping -6` and `traceroute -6 -n` to pc2, look at inet with `tcpdump -ni eth0 'ip proto 47 or icmp'`, then fix it.

1. **On r1:** `ip tunnel change gre1 remote 198.51.100.9`
   **Expected:** no reply on pc1. On inet you see `GREv0` packets to `198.51.100.9` and `ICMP net 198.51.100.9 unreachable` going back to r1. Fix: `ip tunnel change gre1 remote 198.51.100.2` on r1.
2. **On r2:** `ip -6 route del 2001:db8:a::/64`
   **Expected:** no reply on pc1, and traceroute shows only r1 and then `* * *`. The tunnel is fine in one direction; r2 cannot send anything back. Fix: `ip -6 route add 2001:db8:a::/64 via 2001:db8:fe::1` on r2.

## Stretch: check yourself

- Why does IPv6 traceroute not show the IPv4 routers inside a tunnel?
- What would you check first if users say "ping works but web pages hang" across a tunnel?
- Name two things a GRE key does not protect against.

---

# Bonus exercises: Wednesday's lecture topics (if time allows)

These cover today's lecture topics: troubleshooting with ICMPv6, DHCPv6, firewalls and Neighbor Discovery security. Do them in any order. B1 to B3 use this lab's nodes; B4 uses your Lab 1 nodes. Each one puts things back at the end.

`PC2-ADDRESS` is `2001:db8:b:0:5054:ff:fea3:2`.

## B1: Read the ICMPv6 error messages (15 min)

Every IPv6 failure has a reason, and ICMPv6 tells you which one. All tests are from **pc1**.

1. **Hop limit.** Send a ping that may cross only one router:
   ```
   ping -6 -c1 -t 1 PC2-ADDRESS
   ```
   **Expected:** `From 2001:db8:a::1 ... Time exceeded: Hop limit`. This is the message traceroute is built on.
2. **No route.** Ping a network nobody has:
   ```
   ping -6 -c1 -W2 2001:db8:c::1
   ```
   **Expected:** `From 2001:db8:a::1 ... Destination unreachable: No route`. r1 has no IPv6 default route.
3. **Prohibited.** On r1, block that network on purpose, then ping again from pc1:
   ```
   ip -6 route add prohibit 2001:db8:c::/64
   ```
   **Expected:** `Destination unreachable: Administratively prohibited`.
4. **Black hole.** On r1, change it to a silent drop, then ping again from pc1:
   ```
   ip -6 route replace blackhole 2001:db8:c::/64
   ```
   **Expected:** no error at all, only `100% packet loss`. Silent drops are harder to troubleshoot. Remove the route: `ip -6 route del 2001:db8:c::/64` on r1.

## B2: DHCPv6 on LAN B, stateful and stateless (25 min)

LAN B gets its addresses from radvd on r2 (SLAAC). Here r2 hands them out with DHCPv6 instead.

1. **Stateful (M flag).** On **r2**, stop radvd and start dnsmasq as a DHCPv6 server. `--enable-ra` makes it send Router Advertisements with the M flag ("get your address from DHCPv6"):
   ```
   pkill radvd
   dnsmasq -u root --port=0 --interface=eth0 --bind-interfaces --enable-ra \
     --dhcp-range=2001:db8:b::100,2001:db8:b::1ff,64,1h \
     --log-dhcp --log-facility=/tmp/dnsmasq.log
   ```
2. On **pc2**, drop the SLAAC address, read the RA, then ask for an address:
   ```
   ip -6 addr flush dev eth0 scope global
   sleep 8; rdisc6 eth0
   dhclient -6 -v -1 eth0
   ip -6 addr show dev eth0
   ```
   **Expected:** `Stateful address conf. : Yes`, and an address between `2001:db8:b::100` and `2001:db8:b::1ff`.
3. Notice the prefix length on that address is **/128**, not /64. DHCPv6 gives an address only; the on-link prefix and the default route still come from the RA. Check `ip -6 route` on pc2. From pc1, ping the new address through the tunnel.
4. On r2, read the exchange: `cat /tmp/dnsmasq.log` (Solicit, Advertise, Request, Reply).
5. **Stateless (O flag).** Let SLAAC give the address and DHCPv6 give only "other" settings such as DNS servers. On **r2**:
   ```
   pkill dnsmasq
   dnsmasq -u root --port=0 --interface=eth0 --bind-interfaces --enable-ra \
     --dhcp-range=2001:db8:b::,ra-stateless,64 \
     --dhcp-option=option6:dns-server,[2001:db8:b::53] \
     --dhcp-option=option6:domain-search,lab.example \
     --log-dhcp --log-facility=/tmp/dnsmasq.log
   ```
6. On **pc2**:
   ```
   pkill dhclient; ip -6 addr flush dev eth0 scope global
   sleep 10; rdisc6 eth0; ip -6 addr show dev eth0
   dhclient -6 -S -v -1 eth0
   cat /etc/resolv.conf
   ```
   **Expected:** `Stateful address conf. : No` and `Stateful other conf. : Yes`, the SLAAC address `2001:db8:b:0:5054:ff:fea3:2/64` again, and in resolv.conf `nameserver 2001:db8:b::53` and `search lab.example`. `-S` sends an Information-Request, not a Solicit.
7. Put it back. On **r2**: `pkill dnsmasq; radvd`. On **pc2**: `pkill dhclient; ip -6 addr flush dev eth0 scope global`, wait 10 seconds and check that `2001:db8:b:0:5054:ff:fea3:2` is back.

## B3: Firewall r2 without breaking IPv6 (20 min)

1. On **r2**, add a "security" rule that drops Neighbor Solicitation and Advertisement:
   ```
   nft add table inet lab
   nft add chain inet lab in '{ type filter hook input priority 0; policy accept; }'
   nft add rule inet lab in icmpv6 type '{ nd-neighbor-solicit, nd-neighbor-advert }' drop
   ```
2. On pc2: `ip -6 neigh flush dev eth0; ping -6 -c2 -W1 2001:db8:b::1`. It fails. From pc1, `ping -6 -c2 -W1 PC2-ADDRESS` fails too, because r2 can no longer find pc2's MAC. With no Neighbor Discovery there is no "ARP", so nothing works.
3. Replace it with a sensible policy: drop by default, but allow the ICMPv6 that IPv6 needs:
   ```
   nft flush chain inet lab in
   nft add rule inet lab in ct state established,related accept
   nft add rule inet lab in iif lo accept
   nft add rule inet lab in icmpv6 type '{ destination-unreachable, packet-too-big, time-exceeded, parameter-problem, echo-request, echo-reply, nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert }' accept
   nft add rule inet lab in ip protocol icmp accept
   nft add chain inet lab in '{ policy drop; }'
   ```
4. Test again. **Expected:** pc2 can ping r2, but pc1 still cannot reach pc2. The tunnel packets themselves arrive at r2 as IPv4 protocol 47, and the policy now drops them. Allow the tunnel:
   ```
   nft add rule inet lab in ip protocol gre accept
   ```
   (Use `ip protocol 41` instead if you are on the 6in4 tunnel.) Ping from pc1 again. It works.
5. **Traffic passing through r2.** Run two web servers on **pc2**, then allow only one of them from LAN A:
   ```
   # pc2
   cd /tmp && echo "Hello from pc2" > index.html
   python3 -m http.server 8080 --bind :: > /dev/null 2>&1 &
   python3 -m http.server 9090 --bind :: > /dev/null 2>&1 &
   # r2
   nft add table inet fw
   nft add chain inet fw transit '{ type filter hook forward priority 0; policy drop; }'
   nft add rule inet fw transit ct state established,related accept
   nft add rule inet fw transit meta l4proto ipv6-icmp accept
   nft add rule inet fw transit ip6 saddr 2001:db8:a::/64 tcp dport 8080 accept
   ```
6. From **pc1**:
   ```
   curl -s -m3 -g "http://[PC2-ADDRESS]:8080/"
   curl -s -m3 -g "http://[PC2-ADDRESS]:9090/"; echo "exit code $?"
   ping -6 -c1 -W2 PC2-ADDRESS
   ```
   **Expected:** port 8080 answers, port 9090 times out (exit code 28), and ping works. Why does the rule `meta l4proto ipv6-icmp accept` matter even though you only care about the web server? (Think about Stretch S5.)
7. Clean up: `nft delete table inet fw; nft delete table inet lab` on r2, and `pkill -f http.server` on pc2.

## B4: Rogue Router Advertisement, attack and defense (25 min)

This one needs a link with two hosts and a router, so it uses your **Lab 1** network. In the menu, pick Lab 1. If Lab 1 is not in its end-of-Part-C state (r1 running radvd, pc1 and pc2 with `2001:db8:a:0:...` addresses), ask the instructor to reset it.

Any host on a link can claim to be a router. Here pc2 does it.

1. On **pc2**, create `/etc/radvd.conf`:
   ```
   interface eth0 {
       AdvSendAdvert on;
       MinRtrAdvInterval 3;
       MaxRtrAdvInterval 10;
       AdvDefaultPreference high;
       prefix 2001:db8:bad::/64 { AdvOnLink on; AdvAutonomous on; };
   };
   ```
   Then on pc2:
   ```
   sysctl -w net.ipv6.conf.all.forwarding=1
   radvd
   ```
2. On **pc1**, after about 10 seconds:
   ```
   ip -6 addr show dev eth0
   ip -6 route
   ```
   **Expected:** a new address `2001:db8:bad:0:5054:ff:fea1:1` and a second default route `via fe80::5054:ff:fea1:2 ... pref high` next to r1's `pref medium` one. The high preference wins. pc1 now sends traffic for the outside world to pc2, which could read or change it.
3. Prove it. On pc2 run `tcpdump -ni eth0 icmp6 and dst 2001:db8:ffff::1`, then on pc1 run `ping -6 -c3 -W1 2001:db8:ffff::1`.
   **Expected:** pc2 sees pc1's pings.
4. **Defend pc1.** Accept Router Advertisements only from r1's MAC:
   ```
   nft add table inet guard
   nft add chain inet guard in '{ type filter hook input priority 0; policy accept; }'
   nft add rule inet guard in icmpv6 type nd-router-advert ether saddr != 52:54:00:a1:00:fe drop
   ip -6 route flush dev eth0 proto ra
   ip -6 addr flush dev eth0 scope global
   ```
   Wait 10 seconds, then check `ip -6 addr` and `ip -6 route` on pc1.
   **Expected:** only `2001:db8:a:0:...` comes back, and the only default route is via r1 (`fe80::5054:ff:fea1:fe`).
5. Clean up. On pc2: `pkill radvd; sysctl -w net.ipv6.conf.all.forwarding=0`. On pc1: `nft delete table inet guard`.

On real networks this protection lives in the switch, not on every PC. It is called **RA Guard**.

## Bonus: check yourself

- Which ICMPv6 message would you expect from a firewall that rejects instead of drops?
- Why is a DHCPv6 address /128, and where does the default route come from?
- What do the M and O flags in a Router Advertisement tell hosts?
- Name three ICMPv6 types you must never block, and why.
- Why is a rogue RA dangerous even if it does not take any existing address?
