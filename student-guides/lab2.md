# Lab 2: Routing and Dual Stack

**You will:** route between two IPv6 networks and run IPv4 and IPv6 side by side.

**Topology:**

```
 pc1 ---eth0 [r1] eth1========eth1 [r2] eth0--- pc2
   LAN A                 link                 LAN B
 2001:db8:a::/64   2001:db8:ff::/64     2001:db8:b::/64
 10.1.0.0/24       10.255.0.0/30        10.2.0.0/24
 (SLAAC from r1)                        (SLAAC from r2)
```

| Node | Interface | IPv6 | IPv4 |
|---|---|---|---|
| r1 | eth0 | 2001:db8:a::1/64 | 10.1.0.1/24 |
| r1 | eth1 | 2001:db8:ff::1/64 | 10.255.0.1/30 |
| r2 | eth1 | 2001:db8:ff::2/64 | 10.255.0.2/30 |
| r2 | eth0 | 2001:db8:b::1/64 | 10.2.0.1/24 |
| pc1 | eth0 | SLAAC | 10.1.0.10/24 |
| pc2 | eth0 | SLAAC | 10.2.0.10/24 |

Nothing is configured yet.

---

## Part A: Address the routers

1. On **r1**:
   ```
   sysctl -w net.ipv6.conf.all.forwarding=1
   ip -6 addr add 2001:db8:a::1/64 dev eth0
   ip -6 addr add 2001:db8:ff::1/64 dev eth1
   ```
2. On **r2**:
   ```
   sysctl -w net.ipv6.conf.all.forwarding=1
   ip -6 addr add 2001:db8:b::1/64 dev eth0
   ip -6 addr add 2001:db8:ff::2/64 dev eth1
   ```
3. From r1, ping r2 across the link: `ping -6 -c2 2001:db8:ff::2`

## Part B: SLAAC on LAN A

1. On r1, create `/etc/radvd.conf` (same as Lab 1, prefix `2001:db8:a::/64`) and run `radvd`.
2. On pc1, check `ip -6 addr` and `ip -6 route`. **Expected:** `2001:db8:a:0:5054:ff:fea2:1/64` and a default route via r1.

## Part C: SLAAC on LAN B

1. On r2, create `/etc/radvd.conf` like r1's, but with prefix `2001:db8:b::/64`, and run `radvd`.
2. On pc2, check `ip -6 addr` and `ip -6 route`. **Expected:** `2001:db8:b:0:5054:ff:fea2:b02/64` and a default route via `fe80::5054:ff:fea2:bfe` (r2).

From here on, `PC2-ADDRESS` means `2001:db8:b:0:5054:ff:fea2:b02`.

## Part D: Static routes

1. From pc1, ping PC2-ADDRESS. It fails. Why?
2. Add a route on each router:
   ```
   # r1
   ip -6 route add 2001:db8:b::/64 via 2001:db8:ff::2
   # r2
   ip -6 route add 2001:db8:a::/64 via 2001:db8:ff::1
   ```
3. Ping again from pc1, then trace the path:
   ```
   traceroute -6 -n PC2-ADDRESS
   ```

## Part E: Dual stack

1. Add IPv4 alongside IPv6:
   ```
   # r1
   sysctl -w net.ipv4.ip_forward=1
   ip addr add 10.1.0.1/24 dev eth0; ip addr add 10.255.0.1/30 dev eth1
   ip route add 10.2.0.0/24 via 10.255.0.2
   # r2
   sysctl -w net.ipv4.ip_forward=1
   ip addr add 10.2.0.1/24 dev eth0; ip addr add 10.255.0.2/30 dev eth1
   ip route add 10.1.0.0/24 via 10.255.0.1
   # pc1
   ip addr add 10.1.0.10/24 dev eth0; ip route add default via 10.1.0.1
   # pc2
   ip addr add 10.2.0.10/24 dev eth0; ip route add default via 10.2.0.1
   ```
2. On pc2, start a small web server that listens on both protocols:
   ```
   cd /tmp && echo "Hello from pc2" > index.html
   python3 -m http.server 8080 --bind :: &
   ```
3. From pc1:
   ```
   curl -4 http://10.2.0.10:8080/
   curl -6 "http://[PC2-ADDRESS]:8080/"
   ```
   IPv6 addresses in a URL go inside square brackets.
4. On pc1, give pc2 a name with both addresses in `/etc/hosts`:
   ```
   10.2.0.10      pc2
   PC2-ADDRESS    pc2
   ```
   Then run `curl -v http://pc2:8080/`. Which protocol did curl try first? (Look at the `Trying` line.)

## Check yourself

- Why does a router need IPv6 forwarding turned on, and what does it do differently once it is?
- Why did each router need a route for the far LAN twice, once for IPv4 and once for IPv6?
- Which protocol did curl try first in Part E, and why?

---

# Stretch exercises (about 110 minutes)

Do these after Parts A to E, in order, on the same four nodes. `PC2-ADDRESS` is `2001:db8:b:0:5054:ff:fea2:b02`. Each one puts things back at the end, so the checks at the end of the day still pass.

## S1: Routers that only need link-local next hops (15 min)

1. On r1, look at the route to LAN B: `ip -6 route show 2001:db8:b::/64`. It points at r2's global address on the link, `2001:db8:ff::2`.
2. Find r2's link-local address on the link: `ip -6 addr show dev eth1 scope link` on r2. **Expected:** `fe80::5054:ff:fea2:ff02`.
3. Point both routes at link-local addresses instead. A link-local next hop needs the interface name:
   ```
   # r1
   ip -6 route replace 2001:db8:b::/64 via fe80::5054:ff:fea2:ff02 dev eth1
   # r2
   ip -6 route replace 2001:db8:a::/64 via fe80::5054:ff:fea2:ff01 dev eth1
   ```
   From pc1, `ping -6 -c2 PC2-ADDRESS` still works.
4. Now take the global addresses off the router link completely:
   ```
   # r1
   ip -6 addr del 2001:db8:ff::1/64 dev eth1
   # r2
   ip -6 addr del 2001:db8:ff::2/64 dev eth1
   ```
   Ping again from pc1, then `traceroute -6 -n PC2-ADDRESS`. **Expected:** ping still works. Hop 2 now shows `2001:db8:b::1`, because r2 has no global address on the link any more and answers from another of its addresses. A route only needs a next hop on the same link, and every IPv6 interface already has a link-local address.
5. Put it back:
   ```
   # r1
   ip -6 addr add 2001:db8:ff::1/64 dev eth1
   ip -6 route replace 2001:db8:b::/64 via 2001:db8:ff::2
   # r2
   ip -6 addr add 2001:db8:ff::2/64 dev eth1
   ip -6 route replace 2001:db8:a::/64 via 2001:db8:ff::1
   ```

## S2: Path MTU between routers (15 min)

1. Make the router-to-router link smaller, as a WAN or VPN link often is:
   ```
   # r1 and r2
   ip link set eth1 mtu 1400
   ```
2. From pc1, send a full-size packet that must not be fragmented:
   ```
   ping -6 -c2 -M do -s 1452 PC2-ADDRESS
   ```
   **Expected:** `From 2001:db8:a::1 ... Packet too big: mtu=1400`, then `message too long, mtu: 1400` on the second try.
3. Let pc1 measure the whole path:
   ```
   tracepath -6 -n PC2-ADDRESS
   ```
   **Expected:** the last line says `pmtu 1400 hops 3`.
4. Put it back: `ip link set eth1 mtu 1500` on r1 and r2, then `ip -6 route flush cache` on pc1.

## S3: A second subnet and one summary route (20 min)

LAN B's site owns `2001:db8:b::/48`. That is 65,536 subnets of /64, from `2001:db8:b:0::/64` to `2001:db8:b:ffff::/64`. Part C used the first one.

1. On r2, add the second subnet, `2001:db8:b:1::/64`, to LAN B:
   ```
   ip -6 addr add 2001:db8:b:1::1/64 dev eth0
   ```
   Add a second prefix inside `interface eth0 { ... }` in r2's `/etc/radvd.conf`, then restart radvd:
   ```
   prefix 2001:db8:b:1::/64 { AdvOnLink on; AdvAutonomous on; };
   ```
   ```
   pkill radvd; sleep 1; radvd
   ```
2. On pc2, after about 10 seconds: `ip -6 addr show dev eth0`. **Expected:** a second address, `2001:db8:b:1:5054:ff:fea2:b02`.
3. From pc1, ping it: `ping -6 -c1 2001:db8:b:1:5054:ff:fea2:b02`. **Expected:** `Destination unreachable: No route` from r1. r1 only knows the first /64.
4. On r1, replace the /64 route with one route for the whole site:
   ```
   ip -6 route del 2001:db8:b::/64
   ip -6 route add 2001:db8:b::/48 via 2001:db8:ff::2
   ```
   Ping both of pc2's addresses from pc1. **Expected:** both work. One /48 route covers every subnet the site will ever add. Check with `ip -6 route get 2001:db8:b:abcd::1` on r1: it also goes to r2.
5. Put it back:
   ```
   # r1
   ip -6 route del 2001:db8:b::/48
   ip -6 route add 2001:db8:b::/64 via 2001:db8:ff::2
   # r2: remove the second prefix block from /etc/radvd.conf, then
   ip -6 addr del 2001:db8:b:1::1/64 dev eth0
   pkill radvd; sleep 1; radvd
   # pc2
   ip -6 addr del 2001:db8:b:1:5054:ff:fea2:b02/64 dev eth0
   ```

## S4: Which protocol does a dual-stack host pick? (15 min)

You added `pc2` to pc1's `/etc/hosts` with both addresses in Part E.

1. On pc1:
   ```
   getent ahosts pc2
   curl -sv -m3 http://pc2:8080/ 2>&1 | grep Trying
   ```
   **Expected:** the IPv6 address is listed first and curl tries `[PC2-ADDRESS]:8080` first. By default (RFC 6724) hosts prefer IPv6.
2. Tell pc1 to prefer IPv4 instead:
   ```
   echo 'precedence ::ffff:0:0/96 100' > /etc/gai.conf
   getent ahosts pc2
   curl -sv -m3 http://pc2:8080/ 2>&1 | grep Trying
   ```
   **Expected:** `10.2.0.10` is now first. This is the setting people change when "IPv6 is slow" instead of fixing the IPv6 problem.
3. Remove it: `rm /etc/gai.conf`.

## S5: Two stacks, two routing tables (15 min)

1. On r1, compare `ip route` and `ip -6 route`. Two separate tables: IPv4 routes in one, IPv6 routes in the other.
2. Break only IPv6. On r1: `ip -6 route del 2001:db8:b::/64`. From pc1:
   ```
   ping -6 -c1 -W2 PC2-ADDRESS
   ping -c1 -W2 10.2.0.10
   curl -sv -m5 http://pc2:8080/ 2>&1 | grep -E 'Trying|Connected|Hello'
   ```
   **Expected:** the IPv6 ping fails and the IPv4 ping works. curl tries `[PC2-ADDRESS]:8080` first, then `10.2.0.10:8080`, and gets `Hello from pc2` over IPv4. A user would notice nothing, which is why an IPv6 fault on a dual-stack network can go unseen for a long time.
3. Swap the fault. On r1, put the IPv6 route back and remove the IPv4 one:
   ```
   ip -6 route add 2001:db8:b::/64 via 2001:db8:ff::2
   ip route del 10.2.0.0/24
   ```
   Repeat the three commands on pc1. **Expected:** now only IPv4 fails, and curl connects over IPv6 straight away.
4. Put it back on r1: `ip route add 10.2.0.0/24 via 10.255.0.2`.

## S6: One web server, two protocols (15 min)

1. On pc2, stop the web server from Part E and start it again with its log in a file:
   ```
   pkill -f http.server
   cd /tmp && python3 -m http.server 8080 --bind :: > /tmp/web.log 2>&1 &
   ss -ltn | grep 8080
   ```
   **Expected:** `*:8080`. One IPv6 socket that accepts both protocols.
2. From pc1, fetch the page once over each protocol:
   ```
   curl -s -m5 http://10.2.0.10:8080/
   curl -s -m5 -g "http://[PC2-ADDRESS]:8080/"
   ```
   On pc2, `cat /tmp/web.log`. **Expected:** one request from `2001:db8:a:0:5054:ff:fea2:1` and one from `::ffff:10.1.0.10`. The IPv4 client shows up as an IPv4-mapped IPv6 address (`::ffff:` plus the IPv4 address). That is how one IPv6 socket serves IPv4 clients too (`sysctl net.ipv6.bindv6only` is 0).
3. Restart the server on IPv4 only:
   ```
   pkill -f http.server
   python3 -m http.server 8080 --bind 0.0.0.0 > /tmp/web.log 2>&1 &
   ss -ltn | grep 8080
   ```
   Repeat both curls on pc1. **Expected:** `0.0.0.0:8080`, the IPv4 request works and the IPv6 one gets `Couldn't connect to server`. The network is dual stack, but this application is not.
4. Put it back on pc2:
   ```
   pkill -f http.server
   python3 -m http.server 8080 --bind :: > /tmp/web.log 2>&1 &
   ```

## S7: Break it, find it, fix it (15 min)

For each fault: make the change, predict what pc1 will see, test with `ping -6` and `traceroute -6 -n` to PC2-ADDRESS, then fix it.

1. **On r2:** `ip -6 route del 2001:db8:a::/64`
   **Expected:** ping from pc1 gets no reply, and traceroute shows r1 and then only `* * *`. pc2 still gets the requests, but r2 cannot send the replies back. Fix: `ip -6 route add 2001:db8:a::/64 via 2001:db8:ff::1` on r2.
2. **On r1:** `sysctl -w net.ipv6.conf.all.forwarding=0`
   **Expected:** pc1 still has its default route, but ping gets no reply and traceroute gets no answer at all. r1 now acts as a host and quietly drops packets that are not for itself. Fix: `sysctl -w net.ipv6.conf.all.forwarding=1` on r1.

## Stretch: check yourself

- Why can a router use a link-local address as a next hop, but a host on another LAN cannot reach it?
- What does one /48 route save you compared with one route per /64?
- Why is "prefer IPv4" in gai.conf a workaround rather than a fix?
- Why can an IPv6 problem on a dual-stack network go unnoticed?
