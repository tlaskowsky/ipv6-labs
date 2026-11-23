# Lab 1: Link-Local Addresses, Neighbor Discovery and SLAAC

**You will:** see how IPv6 hosts get addresses with no configuration, how they find each other without ARP, and how a router hands out a prefix.

**Topology:** one Ethernet segment.

```
 pc1 (eth0) ----+
 pc2 (eth0) ----+---- switch
 r1  (eth0) ----+
```

| Node | MAC address |
|---|---|
| pc1 | 52:54:00:a1:00:01 |
| pc2 | 52:54:00:a1:00:02 |
| r1  | 52:54:00:a1:00:fe |

---

## Part A: Link-local addresses (pc1)

1. Show the addresses on pc1:
   ```
   ip -6 addr show dev eth0
   ```
   You see one address that starts with `fe80::`. Nobody configured it.

2. Work out by hand how `fe80::5054:ff:fea1:1` comes from the MAC `52:54:00:a1:00:01` (EUI-64):
   - Split the MAC in half and insert `ff:fe` in the middle: `52:54:00:ff:fe:a1:00:01`
   - Flip the 7th bit of the first byte: `52` becomes `50`
   - Result: `5054:00ff:fea1:0001`, written short as `5054:ff:fea1:1`

3. Predict pc2's link-local address, then check it from pc2.

4. From pc1, ping pc2's link-local address. A link-local address needs the interface name after `%`:
   ```
   ping -6 -c3 fe80::5054:ff:fea1:2%eth0
   ```
   Try it without `%eth0`. What happens, and why?

5. Ping every IPv6 node on the link at once:
   ```
   ping -6 -c2 ff02::1%eth0
   ```

## Part B: Neighbor Discovery (two windows)

1. In window 1 on pc2, start a capture:
   ```
   tcpdump -ni eth0 icmp6
   ```
2. In window 2 on pc1, clear the neighbor cache and ping pc2:
   ```
   ip -6 neigh flush dev eth0
   ping -6 -c1 fe80::5054:ff:fea1:2%eth0
   ip -6 neigh
   ```
3. In the capture, find the **Neighbor Solicitation** (type 135) and **Neighbor Advertisement** (type 136). Which address was the solicitation sent to? It starts with `ff02::1:ff`. This is pc2's solicited-node multicast address, built from the last 24 bits of its address. Compare it with `ip -6 maddr show dev eth0` on pc2.

## Part C: Turn r1 into a router and use SLAAC

1. On r1, turn on IPv6 forwarding and give eth0 a global address:
   ```
   sysctl -w net.ipv6.conf.all.forwarding=1
   ip -6 addr add 2001:db8:a::1/64 dev eth0
   ```
2. On r1, create `/etc/radvd.conf` with `nano /etc/radvd.conf`:
   ```
   interface eth0 {
       AdvSendAdvert on;
       MinRtrAdvInterval 3;
       MaxRtrAdvInterval 10;
       prefix 2001:db8:a::/64 {
           AdvOnLink on;
           AdvAutonomous on;
       };
   };
   ```
3. Start the router advertisement daemon on r1:
   ```
   radvd
   ```
4. On pc1, ask for a Router Advertisement and read it:
   ```
   rdisc6 eth0
   ```
5. On pc1, look again:
   ```
   ip -6 addr show dev eth0
   ip -6 route
   ```
   **Expected:** a new address `2001:db8:a:0:5054:ff:fea1:1/64` and a default route `via fe80::5054:ff:fea1:fe`. The default gateway is r1's **link-local** address, not `2001:db8:a::1`.
6. From pc1, ping pc2's new global address and r1:
   ```
   ping -6 -c2 2001:db8:a:0:5054:ff:fea1:2
   ping -6 -c2 2001:db8:a::1
   ```
7. Optional: on pc2, run `tcpdump -ni eth0 'icmp6 and ip6[40] == 134'` and watch r1's Router Advertisements arrive every 3 to 10 seconds.

## Part D: Duplicate Address Detection

1. On pc1, try to take r1's address:
   ```
   ip -6 addr add 2001:db8:a::1/64 dev eth0
   sleep 3; ip -6 addr show dev eth0
   ```
   **Expected:** the address is marked `dadfailed tentative` and is never used. Remove it:
   ```
   ip -6 addr del 2001:db8:a::1/64 dev eth0
   ```

## Part E: Privacy addresses

An EUI-64 address shows your MAC to every server you talk to. Temporary addresses fix that.

1. On pc2:
   ```
   sysctl -w net.ipv6.conf.eth0.use_tempaddr=2
   ip link set eth0 down; ip link set eth0 up
   sleep 8; ip -6 addr show dev eth0
   ```
   **Expected:** an extra address marked `temporary` with a random interface ID.
2. Use `sipcalc 2001:db8:a:0:5054:ff:fea1:2/64` to see the full expanded address and the network range.

## Check yourself

- Why does a link-local ping need `%eth0`?
- What replaces ARP in IPv6, and which multicast address does it use?
- Where did pc1 get its default gateway from?

---

# Stretch exercises (about 95 minutes)

Do these after Parts A to E, in order. They use the same three nodes. Each one ends with the result you should see. If you get lost, the last step of S4 and S6 puts everything back.

## S1: Neighbor cache states (15 min)

1. On pc1, clear the cache, ping pc2's global address once, then watch the neighbor entry age:
   ```
   ip -6 neigh flush dev eth0
   ping -6 -c1 2001:db8:a:0:5054:ff:fea1:2
   ip -6 neigh show dev eth0
   sleep 45; ip -6 neigh show dev eth0
   ```
   **Expected:** pc2's entry is `REACHABLE` at first and `STALE` after 15 to 45 seconds without traffic. A STALE entry is still used; it is checked again (`DELAY`, then `PROBE`) the next time pc1 sends to it. This is Neighbor Unreachability Detection (NUD) at work.
2. Ask for pc2's MAC directly, the IPv6 way:
   ```
   ndisc6 2001:db8:a:0:5054:ff:fea1:2 eth0
   ```
   **Expected:** `Target link-layer address: 52:54:00:A1:00:02`.
3. Put in a wrong static entry and see what breaks:
   ```
   ip -6 neigh replace 2001:db8:a:0:5054:ff:fea1:2 lladdr 52:54:00:de:ad:00 dev eth0 nud permanent
   ping -6 -c2 -W1 2001:db8:a:0:5054:ff:fea1:2
   ```
   **Expected:** 100% packet loss. The frames go to a MAC that nobody has. Fix it:
   ```
   ip -6 neigh del 2001:db8:a:0:5054:ff:fea1:2 dev eth0
   ping -6 -c2 2001:db8:a:0:5054:ff:fea1:2
   ```

## S2: Multicast groups (10 min)

1. Compare the multicast groups on pc1 and r1: `ip -6 maddr show dev eth0` on each.
   **Expected:** both have `ff02::1` (all nodes) and their own `ff02::1:ff...` groups. Only r1 has `ff02::2` (all routers), because forwarding is on.
2. From pc1, ping all routers on the link:
   ```
   ping -6 -c2 ff02::2%eth0
   ```
   **Expected:** only r1 (`fe80::5054:ff:fea1:fe`) replies. Compare with `ping -6 -c2 ff02::1%eth0`, where every node replies.
3. Work out pc2's solicited-node address from its global address (`ff02::1:ff` plus the last 24 bits), then ping it from pc1:
   ```
   ping -6 -c2 ff02::1:ffa1:2%eth0
   ```
   **Expected:** only pc2 replies. That is why Neighbor Solicitations disturb one host instead of the whole link.

## S3: Watch Duplicate Address Detection (10 min)

1. On pc2, capture Neighbor Solicitations only:
   ```
   tcpdump -ni eth0 'icmp6 and ip6[40] == 135'
   ```
2. On pc1, add a new, unused address:
   ```
   ip -6 addr add 2001:db8:a::99/64 dev eth0
   ```
   **Expected:** in the capture, `:: > ff02::1:ff00:99: ... neighbor solicitation, who has 2001:db8:a::99`. The source is `::` (unspecified) because pc1 may not use the address until DAD is done.
3. Remove it: `ip -6 addr del 2001:db8:a::99/64 dev eth0`. Stop the capture with Ctrl+C.

## S4: Tune the Router Advertisements (25 min)

Every change below is made on r1 in `/etc/radvd.conf`, then applied with:
```
pkill radvd; sleep 1; radvd
```
Then look on pc1 with `rdisc6 eth0`, `ip -6 addr show dev eth0` and `ip -6 route`.

1. **Two prefixes.** Add a second prefix block inside `interface eth0 { ... }`:
   ```
   prefix 2001:db8:a1::/64 { AdvOnLink on; AdvAutonomous on; };
   ```
   **Expected:** pc1 now has two global addresses, `2001:db8:a:0:5054:ff:fea1:1` and `2001:db8:a1:0:5054:ff:fea1:1`. Check which one pc1 uses as the source for each prefix:
   ```
   ip -6 route get 2001:db8:a1::1
   ip -6 route get 2001:db8:a::1
   ```
   r1 has no address in `2001:db8:a1::/64` yet. Add one (`ip -6 addr add 2001:db8:a1::1/64 dev eth0` on r1), then ping it from pc1.
2. **Lifetimes.** Change the first prefix to:
   ```
   prefix 2001:db8:a::/64 { AdvOnLink on; AdvAutonomous on; AdvValidLifetime 300; AdvPreferredLifetime 120; };
   ```
   **Expected:** on pc1, `preferred_lft` drops to about 120 seconds, but `valid_lft` only drops to about **7200** seconds, not 300. A host never lets a Router Advertisement cut an address's remaining valid lifetime below 2 hours (RFC 4862), so one bad advertisement cannot wipe out everyone's addresses.
3. **Deprecate an address.** Set `AdvPreferredLifetime 0;` on that prefix.
   **Expected:** pc1's `2001:db8:a:0:...` address is marked `deprecated`. It still answers, but pc1 no longer picks it for new connections (`ip -6 route get 2001:db8:a::1` now shows another source, or none from that prefix).
4. **No default router.** Add `AdvDefaultLifetime 0;` on its own line inside `interface eth0 { ... }` (not inside a prefix).
   **Expected:** pc1 keeps its addresses, but its `default via fe80::5054:ff:fea1:fe` route disappears. The router is still on the link; it just tells hosts "do not use me as a gateway".
5. **Put it back.** Restore the radvd.conf from Part C (one prefix, no lifetimes, no AdvDefaultLifetime), restart radvd, and check pc1 again has `2001:db8:a:0:5054:ff:fea1:1` and its default route. Remove the extra address on r1: `ip -6 addr del 2001:db8:a1::1/64 dev eth0`. pc1 and pc2 keep their `2001:db8:a1:0:...` address until its lifetime runs out; remove it on each with `ip -6 addr del 2001:db8:a1:0:5054:ff:fea1:1/64 dev eth0` (use `fea1:2` on pc2).

Note: when radvd stops it sends a last advertisement with a router lifetime of 0, so the default route on pc1 vanishes for a few seconds every time you restart it.

## S5: Inside the IPv6 header (25 min)

1. On pc2, capture with full header detail. From pc1, send one ping to pc2's global address:
   ```
   # pc2
   tcpdump -vni eth0 'icmp6 and ip6[40] == 128'
   # pc1
   ping -6 -c1 2001:db8:a:0:5054:ff:fea1:2
   ```
   **Expected:** `IP6 (flowlabel 0x..., hlim 64, next-header ICMPv6 (58) payload length: 64) 2001:db8:a:0:5054:ff:fea1:1 > 2001:db8:a:0:5054:ff:fea1:2`. Find each field of the 40-byte header: flow label, hop limit, next header, payload length, source and destination. There is no header checksum and no fragment fields.
2. Change the hop limit and look again:
   ```
   ping -6 -c1 -t 5 2001:db8:a:0:5054:ff:fea1:2
   ```
   **Expected:** `hlim 5`. Hop limit is IPv6's version of the IPv4 TTL.
3. **Fragment header.** Stop the capture, then capture everything pc1 sends and send a ping too big for one packet:
   ```
   # pc2
   tcpdump -vni eth0 'ip6 src 2001:db8:a:0:5054:ff:fea1:1'
   # pc1
   ping -6 -c1 -s 3000 2001:db8:a:0:5054:ff:fea1:2
   ```
   **Expected:** three packets with `next-header Fragment (44)` and `frag (...:0|1448)`, `frag (...:1448|1448)`, `frag (...:2896|112)`. pc1 split the packet itself. In IPv6 only the sending host fragments, and it uses an extension header to do it.
4. **Hop-by-Hop header.** On pc1, capture packets whose first header is Hop-by-Hop Options (next header 0). Then make pc2 rejoin the link:
   ```
   # pc1
   tcpdump -vni eth0 'ip6 proto 0'
   # pc2
   ip link set eth0 down; ip link set eth0 up
   ```
   **Expected:** `next-header Options (0) ... :: > ff02::16: HBH (rtalert: 0x0000) ... multicast listener report v2 ... gaddr ff02::1:ffa1:2`. pc2 announces that it is joining its solicited-node group (Part B), and that message carries a Hop-by-Hop Options header. pc2 gets its global address back within about 10 seconds.
5. **Compare with IPv4.** Give pc1 and pc2 a temporary IPv4 address, capture on pc2 and ping:
   ```
   # pc1
   ip addr add 10.0.0.1/24 dev eth0
   # pc2
   ip addr add 10.0.0.2/24 dev eth0
   tcpdump -vni eth0 icmp
   # pc1
   ping -c1 10.0.0.2
   ```
   **Expected:** `IP (tos 0x0, ttl 64, id ..., offset 0, flags [DF], proto ICMP (1), length 84)`. IPv4 carries an ID, flags, fragment offset and a header checksum in every packet. IPv6 dropped the checksum and moved fragmenting into an extension header that only appears when needed.
6. Remove the IPv4 addresses: `ip addr del 10.0.0.1/24 dev eth0` on pc1 and `ip addr del 10.0.0.2/24 dev eth0` on pc2.

## S6: Stable privacy addresses (10 min)

EUI-64 puts your MAC in every address. RFC 7217 "stable privacy" addresses use a hash instead: the address stays the same on one network but cannot be traced to the MAC.

1. On pc2:
   ```
   sysctl -w net.ipv6.conf.eth0.addr_gen_mode=3
   ip link set eth0 down; ip link set eth0 up
   sleep 8; ip -6 addr show dev eth0
   ```
   **Expected:** the link-local and the `2001:db8:a:0:...` address no longer contain `5054:ff:fe`.
2. Put it back so the checks at the end of the day pass:
   ```
   sysctl -w net.ipv6.conf.eth0.addr_gen_mode=0
   sysctl -w net.ipv6.conf.eth0.use_tempaddr=0
   ip link set eth0 down; ip link set eth0 up
   sleep 8; ip -6 addr show dev eth0
   ```
   **Expected:** `fe80::5054:ff:fea1:2` and `2001:db8:a:0:5054:ff:fea1:2` are back.

## Stretch: check yourself

- Why does a host need a router lifetime of more than 0 before it adds a default route?
- What is the difference between a deprecated address and an expired one?
- Which IPv6 header field replaced the IPv4 TTL, and which extension header did the 3000-byte ping use?
