---
title: "IPv6 Day 3 Lab: IPv6 Across an IPv4-Only Network (Tunnels)"
tags: ipv6, labs
---

# IPv6 Day 3 Lab: IPv6 Across an IPv4-Only Network (Tunnels)

**Day 3 lab (Lab 3 in the `lab` menu).** Core parts: about 205 minutes. Stretch exercises: about 65 minutes.

[TOC]

## What you will do

- Connect two IPv6 sites across a network that speaks only IPv4.
- Build a GRE tunnel, then a 6in4 (SIT) tunnel, and compare them on the wire.
- See what a tunnel does to the MTU, and how Packet Too Big and Path MTU Discovery deal with it.
- Plan an address hierarchy for the two sites (/48, /56, /64) and write it down.
- Troubleshoot: read ICMPv6 error messages, find a Path MTU black hole, and fix a broken tunnel.
- Hand out addresses with DHCPv6, stateful and stateless.
- Secure IPv6: a firewall that does not break it, and a rogue Router Advertisement attack and its defense.

### How to use this guide

**Core parts** A to K are the scheduled lab: do them in order. Parts A to D use the tunneling topics from Day 2's lecture (Module 5). Parts E to K follow today's lecture modules in order: Module 7 (IPAM) in Part E, Module 8 (monitoring and troubleshooting) in Parts F to H, Module 9 (DHCPv6) in Part I, and Module 10 (security) in Parts J and K. Each part shows its minutes in its title. **Stretch exercises** come after Part K, for when you finish early. Each one says how it ties to today's lecture, and a **New in this exercise** box explains anything the lecture did not cover.

#### Suggested timing

| Block | Minutes |
|---|---|
| Start-up: open the terminals, read "Your network" | 10 |
| Parts A to D: tunnels (10 + 25 + 20 + 20) | 75 |
| Break | 10 |
| Parts E to H: address plan, ICMPv6 errors, Path MTU black hole, troubleshooting (15 + 15 + 15 + 15) | 60 |
| Break | 10 |
| Parts I to K: DHCPv6, firewall, rogue Router Advertisement (25 + 20 + 25) | 70 |
| Wrap-up: Check your work, Check yourself | 5 |
| **Total** | **240** |

Each part starts with a **Why this matters** box: read it first. **Predict first** questions ask what you expect before you run a command; **Explain why** questions ask you to explain a result. Answers are folded under **▶ Answer**: try first, then open them. A wrong prediction is the best moment to learn. **How to read this** paragraphs tell you which parts of an output matter and what they prove.

:::info
Reminder of the `lab` menu and multiple terminals: **Getting Started**.
:::

## Your network

```
 pc1 --eth0 [r1] eth1 ---- eth0 [inet] eth1 ---- eth1 [r2] eth0-- pc2
 2001:db8:a::/64    192.0.2.0/30      198.51.100.0/30    2001:db8:b::/64
```

`inet` is an IPv4-only router that stands in for the internet. It has no IPv6 at all.

Think of two offices that run IPv6 inside, connected by a provider that offers only IPv4. This is common during the move to IPv6: your own network is often ready long before every provider on the path is.

**Already done for you:** both LANs work (r1 and r2 run radvd, so pc1 and pc2 have SLAAC addresses), and r1 can reach r2 over IPv4 through inet. What is missing is any IPv6 path between the two sites.

| Node | Interface | Address |
|---|---|---|
| pc1 | eth0 | `2001:db8:a:0:5054:ff:fea3:1` (SLAAC) |
| r1 | eth0 | `2001:db8:a::1/64` |
| r1 | eth1 | `192.0.2.2/30`, default route to inet |
| inet | eth0 / eth1 | `192.0.2.1/30` / `198.51.100.1/30` |
| r2 | eth1 | `198.51.100.2/30`, default route to inet |
| r2 | eth0 | `2001:db8:b::1/64` |
| pc2 | eth0 | `2001:db8:b:0:5054:ff:fea3:2` (SLAAC) |

In this lab **PC2-ADDRESS** is `2001:db8:b:0:5054:ff:fea3:2`. The commands below already have it filled in.

### Words you will meet today

| Word | Meaning |
|---|---|
| Encapsulation | Putting a whole packet inside another packet, like a letter inside a second envelope |
| Outer header / inner packet | The header added in front (here IPv4) / the original packet carried inside (here IPv6) |
| Tunnel endpoint | The router that adds or removes the outer header: r1 and r2 |
| Overhead | The extra bytes the outer headers add to every packet |

## Before you start: open five terminals

| Terminal | Type | Prompt |
|---|---|---|
| Terminal 1 | `lab 3 pc1` | `[s01 pc1]#` |
| Terminal 2 | `lab 3 r1` | `[s01 r1]#` |
| Terminal 3 | `lab 3 inet` | `[s01 inet]#` |
| Terminal 4 | `lab 3 r2` | `[s01 r2]#` |
| Terminal 5 | `lab 3 pc2` | `[s01 pc2]#` |

Part K also uses three of your Lab 1 nodes. You open those terminals in Part K.

:::warning
Lab 3 has its own pc1, r1, r2 and pc2, separate from Labs 1 and 2. Check that each one was opened with **lab 3**.
:::

---

## Part A: See the problem (10 min)

:::info
**Why this matters**

Before you fix something, prove what is broken. You will show three facts: IPv4 works between the routers, IPv6 does not work between the sites, and the router in the middle cannot carry IPv6 at all. Together they explain why we need a tunnel. On a real network, this is the first check when a site "has no IPv6": what does the path in the middle support?
:::

### A1. IPv4 works between the routers

`ping -c2` sends two (`-c2` = count 2) IPv4 echo requests to r2's outside address. No `-6`, so this is plain IPv4.

**Terminal 2 (r1):**

```
ping -c2 198.51.100.2
```

**Expected:** `2 packets transmitted, 2 received, 0% packet loss`. r1 reaches r2 through inet over IPv4.

**How to read this:** 0% loss means the IPv4 path works in both directions. This is the road the tunnel will use. If it fails, no tunnel can work, so always test the outer (IPv4) path first.

### A2. IPv6 does not work between the sites

`-6` makes ping use IPv6. The destination is pc2's SLAAC address.

**Predict first:** you will get an error, not a timeout. Which node sends it, and why?

<details>
<summary>▶ Answer</summary>

pc1 sends the packet to its default router r1 (learned from r1's Router Advertisement, Day 1). r1 has no route to `2001:db8:b::/64` and no IPv6 default route, so r1 answers with ICMPv6 Destination Unreachable.
</details>

**Terminal 1 (pc1):**

```
ping -6 -c2 2001:db8:b:0:5054:ff:fea3:2
```

**Expected:**

```
From 2001:db8:a::1 icmp_seq=1 Destination unreachable: No route
```

r1 (`2001:db8:a::1`) has no IPv6 route to LAN B.

**How to read this:** `From 2001:db8:a::1` names the sender of the error: r1, not pc2. So LAN A works; the problem is r1's routing table. `No route` is the reason code (more in Part F).

### A3. inet has no IPv6

`ip -6 addr` lists every IPv6 address on the node. A normal Linux node shows at least `::1` and a link-local `fe80::` address per interface (Day 1).

**Terminal 3 (inet):**

```
ip -6 addr
```

**Expected:** no output at all. inet has IPv6 turned off, so you cannot simply add IPv6 routes through it. IPv6 has to travel **inside** IPv4.

**How to read this:** not even `::1` or link-local: inet is like a provider router that was never set up for IPv6. It drops every IPv6 packet, but it does forward IPv4.

**Explain why:** why can r1 not simply use inet as the next hop of an IPv6 route?

<details>
<summary>▶ Answer</summary>

A next hop must be a neighbour that speaks the same protocol on a shared link. inet has no IPv6 address to name as next hop, and it could not forward IPv6 anyway. The only thing everyone on the path understands is IPv4.
</details>

---

## Part B: GRE tunnel (25 min)

A tunnel puts each IPv6 packet inside an IPv4 packet at one end (r1), sends it across the IPv4 network, and unpacks it at the other end (r2).

:::info
**Why this matters**

r1 puts a new IPv4 header in front of each IPv6 packet (**encapsulation**) and sends it to r2's IPv4 address. Routers in the middle see an ordinary IPv4 packet. r2 removes the IPv4 header (**decapsulation**) and routes the original IPv6 packet onto LAN B. Like a letter put in a second envelope: the post office only reads the outside address.

**GRE** (Generic Routing Encapsulation) adds a small 4-byte header between the outer IPv4 header and the inner packet. It says what kind of packet is inside, so GRE can carry IPv6, IPv4 and more. Real use: joining IPv6 branch offices across an IPv4-only provider, with no change on any host.
:::

### B1. Build the tunnel on r1

On r1 you create the tunnel interface, switch it on, give it an IPv6 address, and route LAN B into it.

**Terminal 2 (r1):**

```
ip tunnel add gre1 mode gre local 192.0.2.2 remote 198.51.100.2 ttl 255
ip link set gre1 up
ip -6 addr add 2001:db8:fe::1/64 dev gre1
ip -6 route add 2001:db8:b::/64 via 2001:db8:fe::2
```

Line by line:

| Command | Meaning |
|---|---|
| `ip tunnel add gre1 mode gre local 192.0.2.2 remote 198.51.100.2 ttl 255` | Create a GRE tunnel interface `gre1` from r1's IPv4 address to r2's IPv4 address |
| `ip link set gre1 up` | Turn the interface on |
| `ip -6 addr add 2001:db8:fe::1/64 dev gre1` | Give the inside of the tunnel an IPv6 address |
| `ip -6 route add 2001:db8:b::/64 via 2001:db8:fe::2` | Send traffic for LAN B to r2's end of the tunnel |

The first command, word by word:

- `gre1`: the new interface. It looks like a network card but has no cable: whatever is sent into it gets wrapped.
- `mode gre`: GRE encapsulation; the outer IPv4 header carries protocol number 47.
- `local 192.0.2.2`: source of the outer IPv4 header. It must be r1's own address (`eth1`).
- `remote 198.51.100.2`: destination of the outer header, r2's outside address. Incoming GRE packets from this address belong to `gre1`.
- `ttl 255`: the TTL (IPv4's hop limit) of the outer header. 255 is the maximum, so the outer packet does not expire on its way across the IPv4 network.

The tunnel is a link between r1 and r2, like a cable, so it gets its own prefix, `2001:db8:fe::/64` (r1 `::1`, r2 `::2`). The route uses r2's tunnel address as next hop, so LAN B's traffic leaves through `gre1` and gets wrapped.

**Expected:** no output. Check:

```
ip -6 addr show dev gre1
```

**Expected:** `inet6 2001:db8:fe::1/64 scope global` (and a link-local address).

**How to read this:** `scope global` is your address. The link-local address appeared by itself when the interface came up, as on Ethernet (Day 1). GRE has no handshake: r1 will start sending wrapped packets to `198.51.100.2` whether r2 is ready or not.

**Explain why:** why does the route point to `2001:db8:fe::2` and not to r2's LAN address `2001:db8:b::1`?

<details>
<summary>▶ Answer</summary>

A next hop must be directly reachable on one of r1's links. The only link r1 and r2 share is the tunnel. `2001:db8:b::1` is on LAN B, which r1 cannot reach yet: that is the problem we are fixing.
</details>

### B2. Build the mirror image on r2

r2 must unwrap what r1 sends, and wrap the replies going back.

**Terminal 4 (r2):** local and remote are swapped:

```
ip tunnel add gre1 mode gre local 198.51.100.2 remote 192.0.2.2 ttl 255
ip link set gre1 up
ip -6 addr add 2001:db8:fe::2/64 dev gre1
ip -6 route add 2001:db8:a::/64 via 2001:db8:fe::1
```

**Predict first:** if you forgot the last line on r2 (the route to LAN A), would pc1's request reach pc2? Would pc1 get a reply?

<details>
<summary>▶ Answer</summary>

The request would reach pc2. pc2's reply goes to its router r2, which has no route back to LAN A, so it is lost: pc1 sees 100% loss. Routes are needed in **both** directions. You will make this mistake on purpose in Part H (step H3).
</details>

### B3. Ping across the tunnel

**Predict first:** which node adds the IPv4 header to the echo request, and which removes it?

<details>
<summary>▶ Answer</summary>

r1 adds the IPv4 and GRE headers, inet forwards IPv4 only, r2 removes them. For the reply, r2 wraps and r1 unwraps.
</details>

**Terminal 1 (pc1):**

```
ping -6 -c3 2001:db8:b:0:5054:ff:fea3:2
```

**Expected:** `3 packets transmitted, 3 received, 0% packet loss`.

**How to read this:** 0% loss proves both directions work. pc1 and pc2 did nothing special: only the two routers know the tunnel exists.

<details>
<summary>▶ Still "No route" or 100% loss?</summary>

- Check `ip -6 route` on **both** routers: r1 needs the route to `2001:db8:b::/64`, r2 the route to `2001:db8:a::/64`.
- Check `ip tunnel show` on both: r1's `local` must be r2's `remote` and the other way round.
- From r1, `ping -6 -c2 2001:db8:fe::2` tests the tunnel alone.
</details>

### B4. Prove that inet sees only IPv4

Now you look at the wire in the middle and see the encapsulation yourself. On a real network, a capture in the path is how you prove what the provider carries.

tcpdump options: `-n` numbers instead of names, `-i eth0` inet's link toward r1, `-c4` stop after 4 packets (2 requests, 2 replies). The filter `'ip proto 47'` keeps IPv4 packets whose protocol field is 47 (GRE).

**Predict first:** inet has no IPv6. Will its capture show IPv6 addresses?

<details>
<summary>▶ Answer</summary>

Yes. tcpdump decodes all the bytes, and the IPv6 packet is inside as data. inet carries the IPv6 addresses but never uses them: it reads only the outer IPv4 header.
</details>

**Terminal 3 (inet):** start a capture of GRE packets (IP protocol 47). It stops by itself after 4 packets:

```
tcpdump -ni eth0 -c4 'ip proto 47'
```

**Terminal 1 (pc1):**

```
ping -6 -c2 2001:db8:b:0:5054:ff:fea3:2
```

**Expected** in Terminal 3 (inet):

```
IP 192.0.2.2 > 198.51.100.2: GREv0, length 108: IP6 2001:db8:a:0:5054:ff:fea3:1 > 2001:db8:b:0:5054:ff:fea3:2: ICMP6, echo request, id 7, seq 1, length 64
IP 198.51.100.2 > 192.0.2.2: GREv0, length 108: IP6 2001:db8:b:0:5054:ff:fea3:2 > 2001:db8:a:0:5054:ff:fea3:1: ICMP6, echo reply, id 7, seq 1, length 64
```

Read one line from left to right: the outer **IPv4** header (`IP 192.0.2.2 > 198.51.100.2`), the GRE header (`GREv0`), then the original **IPv6** packet (`IP6 ... ICMP6, echo request`). inet forwards it like any other IPv4 packet.

**How to read this:**

- `IP 192.0.2.2 > 198.51.100.2`: outer header, from r1 (`local`) to r2 (`remote`).
- `GREv0`: GRE header, version 0. `length 108` = 4 bytes GRE + 104 bytes inner packet (40 bytes IPv6 header + 64 bytes ICMPv6).
- `IP6 ...:1 > ...:2`: the original pc1-to-pc2 packet, unchanged.
- In the reply line, the outer addresses are swapped: r2 wrapped it.

**Explain why:** why are the outer addresses r1 and r2, not pc1 and pc2?

<details>
<summary>▶ Answer</summary>

pc1 and pc2 have no IPv4 internet addresses and do not know the tunnel exists. The outer header only carries the packet between the tunnel ends, so it uses their addresses: an envelope addressed office to office, with a letter inside addressed person to person.
</details>

---

## Part C: Tunnels and MTU (20 min)

:::info
**Why this matters**

Every tunnel adds headers, but the Ethernet link underneath still carries at most 1500 bytes. Less room is left for the inner packet: that is the **tunnel MTU**.

IPv6 routers never fragment (Day 2). If a packet is too big for the next link, the router drops it and sends ICMPv6 **Packet Too Big** to the sender, which then sends smaller packets: **Path MTU Discovery** (PMTUD). Tunnels are where this happens most in real life. When it works, users notice nothing. When Packet Too Big is blocked, web pages and downloads start but never finish (Part G).
:::

### C1. The tunnel MTU

**Predict first:** Ethernet MTU is 1500, the outer IPv4 header is 20 bytes, the GRE header 4 bytes. What MTU will `gre1` have?

<details>
<summary>▶ Answer</summary>

1500 - 20 - 4 = 1476 bytes.
</details>

**Terminal 2 (r1):**

```
ip link show gre1
```

**Expected:** `... gre1@NONE: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1476 ...`

1476 = 1500 (Ethernet) minus 20 bytes of outer IPv4 header minus 4 bytes of GRE header.

**How to read this:** `@NONE`: not tied to one physical interface; Linux reaches `remote` through the normal IPv4 routing table. `POINTOPOINT`: exactly two ends. `NOARP`: no address resolution; there is only one possible neighbour and no MAC addresses, so no Neighbor Solicitation is needed.

### C2. Send a full-size packet

`-s 1452` sets the amount of ping data. `-M do` means "do not fragment": in IPv6 only the sender may fragment, and this switches even that off, so you see clearly what happens to a 1500-byte packet.

**Predict first:** pc1's own link MTU is 1500, so the packet can leave pc1. Where does it fail, and who tells pc1?

<details>
<summary>▶ Answer</summary>

At r1, which cannot put 1500 bytes into the 1476-byte tunnel. r1 drops it and sends Packet Too Big, with `mtu=1476`, to pc1.
</details>

**Terminal 1 (pc1):**

```
ping -6 -c2 -M do -s 1452 2001:db8:b:0:5054:ff:fea3:2
```

1452 bytes of data + 8 bytes ICMPv6 + 40 bytes IPv6 = 1500 bytes. `-M do` forbids fragmenting.

**Expected:**

```
From 2001:db8:a::1 icmp_seq=1 Packet too big: mtu=1476
ping: local error: message too long, mtu: 1476
```

The first packet reached r1, which could not fit it into the 1476-byte tunnel. IPv6 routers never fragment, so r1 dropped it and sent ICMPv6 **Packet Too Big** back to pc1. pc1 remembered the smaller size, so the second packet fails on pc1 itself.

**How to read this:** line 1 comes from r1 and carries the MTU that fits, so the sender knows the exact size to use. Line 2, `local error`, did not come from the network: pc1's own kernel refused, because it now knows the limit. This proves pc1 learned from the message.

**Explain why:** an IPv4 router may split a big packet. Why does r1 drop it instead?

<details>
<summary>▶ Answer</summary>

IPv6 moved fragmentation from routers to the sending host, to keep routers simpler and faster. Routers only drop and report. The price: the sender must receive Packet Too Big, or it never learns the right size.
</details>

### C3. Send a packet that fits

**Terminal 1 (pc1):**

```
ping -6 -c2 -M do -s 1428 2001:db8:b:0:5054:ff:fea3:2
```

1428 + 48 = 1476. **Expected:** `0% packet loss`.

**How to read this:** the largest packet that fits is exactly the tunnel MTU. One byte more and r1 would send Packet Too Big again.

### C4. See what pc1 learned

`ip -6 route get` asks the kernel which route it would use for a destination, and shows what it has learned about it.

**Terminal 1 (pc1):**

```
ip -6 route get 2001:db8:b:0:5054:ff:fea3:2
```

**Expected:**

```
2001:db8:b:0:5054:ff:fea3:2 from :: via fe80::5054:ff:fea3:fe dev eth0 proto ra src 2001:db8:a:0:5054:ff:fea3:1 metric 1024 expires 595sec mtu 1476 hoplimit 64 pref medium
```

`mtu 1476` is the path MTU pc1 learned. This is **Path MTU Discovery**. It is why a firewall must never block ICMPv6 Packet Too Big.

**How to read this:**

- `via fe80::5054:ff:fea3:fe ... proto ra`: next hop is r1's link-local address, learned from a Router Advertisement.
- `mtu 1476`: stored for this destination only; hosts on LAN A still get 1500.
- `expires 595sec`: after about 10 minutes pc1 forgets the value and tries full size again, in case the path changed.
- `pref medium`: the router preference from the RA (used in Part K).

**Explain why:** what would have happened in C2 if a firewall between r1 and pc1 dropped all ICMPv6?

<details>
<summary>▶ Answer</summary>

pc1 would never get Packet Too Big. It would keep sending 1500-byte packets, r1 would keep dropping them, and pc1 would see only timeouts with no error. This is a **PMTU black hole** (Part G).
</details>

---

## Part D: 6in4 (SIT) instead of GRE (20 min)

:::info
**Why this matters**

**6in4** puts the IPv6 packet directly after the IPv4 header, with no header in between. The IPv4 protocol field is **41**, meaning "an IPv6 packet follows". Linux calls this tunnel type **SIT** (Simple Internet Transition). It is the classic standard way to tunnel IPv6 only: 4 bytes less overhead than GRE, but it carries nothing else. Comparing both on the wire shows what each header costs and gives.
:::

### D1. Remove the GRE tunnel

Run this in **Terminal 2 (r1)** and in **Terminal 4 (r2)**:

```
ip tunnel del gre1
```

Deleting the tunnel also removes its addresses and the route through it.

The new tunnel reuses the same inside addresses and routes, so the old one must go first. Until D3 is done, pc1 would again get `No route` from r1, as in A2.

### D2. Build a 6in4 tunnel on r1

Compare with B1 before you type.

**Terminal 2 (r1):**

```
ip tunnel add sit1 mode sit local 192.0.2.2 remote 198.51.100.2 ttl 255
ip link set sit1 up
ip -6 addr add 2001:db8:fe::1/64 dev sit1
ip -6 route add 2001:db8:b::/64 via 2001:db8:fe::2
```

Only the mode (`sit`) and the name changed.

`mode sit` means IPv6 directly in IPv4, protocol 41. `local`, `remote` and `ttl 255` mean the same as for GRE.

### D3. Mirror it on r2

**Terminal 4 (r2):**

```
ip tunnel add sit1 mode sit local 198.51.100.2 remote 192.0.2.2 ttl 255
ip link set sit1 up
ip -6 addr add 2001:db8:fe::2/64 dev sit1
ip -6 route add 2001:db8:a::/64 via 2001:db8:fe::1
```

### D4. Test and capture

The filter is now `'ip proto 41'` ("IPv6 inside"); the GRE filter (47) would catch nothing.

**Predict first:** compared with the GRE capture in B4, what will be missing from each line?

<details>
<summary>▶ Answer</summary>

The `GREv0, length ...` part: the IPv6 header comes straight after the IPv4 header.
</details>

**Terminal 3 (inet):** capture IP protocol 41:

```
tcpdump -ni eth0 -c4 'ip proto 41'
```

**Terminal 1 (pc1):**

```
ping -6 -c2 2001:db8:b:0:5054:ff:fea3:2
```

**Expected:** the ping works, and in Terminal 3 (inet):

```
IP 192.0.2.2 > 198.51.100.2: IP6 2001:db8:a:0:5054:ff:fea3:1 > 2001:db8:b:0:5054:ff:fea3:2: ICMP6, echo request, id 8, seq 1, length 64
```

This time there is no `GREv0` between the IPv4 and IPv6 headers.

**How to read this:** same outer header as GRE (same tunnel ends), then directly `IP6 ...`: tcpdump saw protocol 41 and decoded the next bytes as IPv6.

### D5. Compare with GRE

**Predict first:** what MTU will `sit1` have?

<details>
<summary>▶ Answer</summary>

1500 - 20 = 1480 bytes: no GRE header.
</details>

**Terminal 2 (r1):**

```
ip link show sit1
```

**Expected:** `mtu 1480`.

| | GRE | 6in4 (SIT) |
|---|---|---|
| IP protocol number on the wire | 47 | 41 |
| Extra header | outer IPv4 (20) + GRE (4) | outer IPv4 (20) only |
| Tunnel MTU | 1476 | 1480 |
| Can carry | IPv6, IPv4, multicast (for routing protocols) and more | IPv6 only |

**How to read this table:** the protocol number is what a firewall on the path must allow (Part J). GRE can carry many protocols because its header names the inner protocol; with 6in4, protocol 41 always means IPv6.

**Explain why:** a provider firewall allows IPv4 protocol 47 but blocks 41. Which tunnel can you use?

<details>
<summary>▶ Answer</summary>

Only GRE. A tunnel that "never comes up" is often a firewall that blocks its protocol number.
</details>

You finish Part D with the 6in4 tunnel (`sit1`) in place. Leave it: Parts F to J use it.

---

## Part E: Plan the addresses (IPAM) (15 min)

*From today's lecture: Module 7, IPv6 Address Management (hierarchical planning, nibble boundaries, documentation).*

:::info
**Why this matters**

In this lab the prefixes `2001:db8:a::/64`, `2001:db8:b::/64` and `2001:db8:fe::/64` were picked one by one, with no plan. A real organisation gets one prefix from its provider, usually a /48, and divides it from the top down: the /48 for the organisation, a /56 for each site, a /64 for each LAN. Dividing on **nibble boundaries** (steps of 4 bits, one hex digit) keeps every level in whole hex digits, so you can read the site and the LAN straight from an address. You will plan this lab's two offices as if they shared one /48, check the plan with `sipcalc`, and write it down. Writing it down is part of the plan.
:::

`sipcalc` is a subnet calculator that is installed on every lab node. Nothing in this part changes the network: it is a plan on paper, and the lab keeps its current addresses. Use **Terminal 1 (pc1)** for every command.

Your organisation has the prefix `2001:db8:1200::/48`. It is inside `2001:db8::/32`, the range kept for documentation and labs.

### E1. Look at the organisation prefix

**Terminal 1 (pc1):**

```
sipcalc 2001:db8:1200::/48
```

**Expected** (other lines not shown):

```
Expanded Address        - 2001:0db8:1200:0000:0000:0000:0000:0000
Compressed address      - 2001:db8:1200::
...
Prefix length           - 48
...
Network range           - 2001:0db8:1200:0000:0000:0000:0000:0000 -
                          2001:0db8:1200:ffff:ffff:ffff:ffff:ffff
```

**How to read this:** the first 48 bits (three groups, `2001:0db8:1200`) are fixed by the provider. The fourth group (16 bits) is where you number your sites and LANs. The last 64 bits are interface IDs, as on every /64 LAN (Day 1).

**Predict first:** how many /56 site prefixes fit in a /48? How many /64 LANs fit in a /56?

<details>
<summary>▶ Answer</summary>

56 − 48 = 8 bits, so 2⁸ = 256 sites. 64 − 56 = 8 bits, so 256 LANs per site. In the fourth group, the first two hex digits are the site and the last two are the LAN.
</details>

### E2. Split the /48 into site prefixes

`-S 56` splits the network into /56 prefixes. sipcalc prints each one on two lines: the first and the last address. `grep -c Network` counts them. `grep -A1 Network | head -6` shows the first three, each with its second line.

**Terminal 1 (pc1):**

```
sipcalc -S 56 2001:db8:1200::/48 | grep -c Network
sipcalc -S 56 2001:db8:1200::/48 | grep -A1 Network | head -6
```

**Expected:** `256`, then:

```
Network                 - 2001:0db8:1200:0000:0000:0000:0000:0000 -
                          2001:0db8:1200:00ff:ffff:ffff:ffff:ffff
Network                 - 2001:0db8:1200:0100:0000:0000:0000:0000 -
                          2001:0db8:1200:01ff:ffff:ffff:ffff:ffff
Network                 - 2001:0db8:1200:0200:0000:0000:0000:0000 -
                          2001:0db8:1200:02ff:ffff:ffff:ffff:ffff
```

**How to read this:** from one /56 to the next, only the first two hex digits of the fourth group change: `00`, `01`, `02` and so on up to `ff`. Site `01` is `2001:db8:1200:0100::/56`, or `2001:db8:1200:100::/56` in short form. Careful: `100` here is hex `0100` with the leading zero dropped (Day 1 shortening rules), not "one hundred".

### E3. Why nibble boundaries

A /57 is not on a nibble boundary: 57 is not a multiple of 4.

**Predict first:** you split site `01` into two /57 prefixes. Where does the first one end?

<details>
<summary>▶ Answer</summary>

At `2001:db8:1200:17f:ffff:ffff:ffff:ffff`. The split falls in the middle of a hex digit.
</details>

**Terminal 1 (pc1):**

```
sipcalc -S 57 2001:db8:1200:100::/56 | grep -A1 Network
```

**Expected:**

```
Network                 - 2001:0db8:1200:0100:0000:0000:0000:0000 -
                          2001:0db8:1200:017f:ffff:ffff:ffff:ffff
Network                 - 2001:0db8:1200:0180:0000:0000:0000:0000 -
                          2001:0db8:1200:01ff:ffff:ffff:ffff:ffff
```

**How to read this:** the two halves are `0100` to `017f` and `0180` to `01ff`. To know which half `2001:db8:1200:1a3::` is in, you must convert `a` to binary. With steps of 4 bits (/48, /52, /56, /60, /64), every level is a whole hex digit, and you can read it without any arithmetic.

### E4. Write the plan

Use these rules, and fill in the six blanks in your notes:

- Site `00` is for infrastructure: links between routers, such as the tunnel.
- Site `01` is Office A (LAN A, pc1). Site `02` is Office B (LAN B, pc2).
- Inside each site, the first LAN or link is number `01`.
- The router's address on a LAN is `::1`.

| Prefix or address | Level | Used for | Where |
|---|---|---|---|
| `2001:db8:1200::/48` | organisation | the whole company | from the provider |
| `2001:db8:1200::/56` | site `00` | infrastructure links | r1, r2 |
| (1) ______ | /64 | tunnel link r1 to r2 | tunnel interface on r1 and r2 |
| (2) ______ | site `01`, /56 | Office A | |
| (3) ______ | /64 | LAN A | r1 eth0, pc1 |
| (4) ______ | static address | r1 on LAN A | r1 eth0 |
| `2001:db8:1200:200::/56` | site `02` | Office B | |
| (5) ______ | /64 | LAN B | r2 eth0, pc2 |
| (6) ______ | DHCPv6 pool | addresses `::100` to `::1ff` on LAN B (you build one in Part I) | r2 |

<details>
<summary>▶ Answers</summary>

1. `2001:db8:1200:1::/64` (site `00`, link `01`: the fourth group is `0001`)
2. `2001:db8:1200:100::/56`
3. `2001:db8:1200:101::/64`
4. `2001:db8:1200:101::1`
5. `2001:db8:1200:201::/64`
6. `2001:db8:1200:201::100` to `2001:db8:1200:201::1ff`
</details>

Check one answer with sipcalc. **Terminal 1 (pc1):**

```
sipcalc 2001:db8:1200:201::/64 | grep -A1 'Network range'
```

**Expected:**

```
Network range           - 2001:0db8:1200:0201:0000:0000:0000:0000 -
                          2001:0db8:1200:0201:ffff:ffff:ffff:ffff
```

**How to read this:** the fourth group `0201` reads as site `02`, LAN `01`. You can read the plan from the address itself.

**Explain why:** Office A grows to 300 LANs. Does its /56 still fit?

<details>
<summary>▶ Answer</summary>

No. A /56 holds 256 /64 LANs. Give the site a block one nibble bigger: a /52 holds 4096 /64 LANs and is still on a nibble boundary.
</details>

**Explain why:** besides the prefixes, what else should the plan record, according to today's lecture?

<details>
<summary>▶ Answer</summary>

For each subnet: the VLAN ID, a description and the location. Also static addresses (routers, servers) and DHCPv6 pool ranges. A spreadsheet works for this lab; a real network uses an IPAM tool (for example NetBox or phpIPAM).
</details>

---

## Part F: Read the ICMPv6 error messages (15 min)

*From today's lecture: Module 8, Monitoring & Troubleshooting (ping and traceroute, ICMPv6).*

Every IPv6 failure has a reason, and ICMPv6 tells you which one. All tests are sent from **Terminal 1 (pc1)**.

:::info
**Why this matters**

When something fails, ask "who told me, and what did they say?". ICMPv6 errors carry a **type** and a **code** naming the reason. Telling them apart points you straight at the problem: a hop limit running out, a missing route, a deliberate block, or a silent drop.
:::

### F1. Hop limit exceeded

`-t 1` sets the hop limit to 1. Each router lowers it by 1 and discards the packet at 0.

**Predict first:** who answers, and with which message?

<details>
<summary>▶ Answer</summary>

r1: it lowers the hop limit to 0, discards the packet and sends Time Exceeded.
</details>

**Terminal 1 (pc1):** a ping that may cross only one router:

```
ping -6 -c1 -t 1 2001:db8:b:0:5054:ff:fea3:2
```

**Expected:** `From 2001:db8:a::1 icmp_seq=1 Time exceeded: Hop limit`. This is the message traceroute is built on.

**How to read this:** ICMPv6 type 3 (Time Exceeded), code 0. The hop limit also stops looping packets from circling forever.

### F2. No route

**Terminal 1 (pc1):** ping a network nobody has:

```
ping -6 -c1 -W2 2001:db8:c::1
```

**Expected:** `From 2001:db8:a::1 icmp_seq=1 Destination unreachable: No route`. r1 has no IPv6 default route.

**How to read this:** type 1 (Destination Unreachable), code 0. A routing problem: check the routing table of the router named in `From`.

### F3. Administratively prohibited

A `prohibit` route matches the prefix but rejects packets and says why, like a firewall rule that rejects.

**Predict first:** the same router answers. What changes?

<details>
<summary>▶ Answer</summary>

The code: still Destination Unreachable, but "Administratively prohibited".
</details>

**Terminal 2 (r1):** block that network on purpose:

```
ip -6 route add prohibit 2001:db8:c::/64
```

Ping again from **Terminal 1 (pc1)** (same command as F2). **Expected:** `Destination unreachable: Administratively prohibited`.

**How to read this:** type 1, code 1. Someone blocked it on purpose: look for a policy, not a missing route.

### F4. Black hole

`replace` changes the existing route; `blackhole` drops with no message.

**Terminal 2 (r1):** change it to a silent drop:

```
ip -6 route replace blackhole 2001:db8:c::/64
```

Ping again from **Terminal 1 (pc1)**. **Expected:** no error at all, only `1 packets transmitted, 0 received, 100% packet loss`. Silent drops are harder to troubleshoot.

**Explain why:** many firewalls drop silently instead of rejecting. What do they gain, and what does it cost?

<details>
<summary>▶ Answer</summary>

They tell an attacker less. The cost: you cannot see where the packet died, and applications wait for a timeout instead of failing at once with a reason.
</details>

**Put it back.** Remove the route. **Terminal 2 (r1):**

```
ip -6 route del 2001:db8:c::/64
```

---

## Part G: The Path MTU black hole (15 min)

*From today's lecture: Module 8, Common Issue: Path MTU Discovery (PMTUD).*

This is the most common real-world tunnel problem: small pings work, but large downloads hang.

:::info
**Why this matters**

When Packet Too Big is blocked somewhere, small packets still work (ping, opening a TCP connection, a short request), but large packets vanish without an error. Users say "the page opens but never finishes loading". This is a **PMTU black hole**. Today's lecture gives the fix: let ICMPv6 Packet Too Big (type 2) through. You will see a download work, break it with one firewall rule, and fix it.
:::

You are still on the 6in4 tunnel (`sit1`) from Part D, so the tunnel MTU is 1480.

### G1. Serve a large file from pc2

Line 1 creates a 300000-byte random file. Line 2 starts Python's web server on port 8080 on all addresses (`--bind ::`), in the background (`&`). Line 3 waits, then lists listening TCP sockets (`ss -ltn`) and keeps the line for port 8080.

**Terminal 5 (pc2):**

```
cd /tmp && head -c 300000 /dev/urandom > big.bin
python3 -m http.server 8080 --bind :: > /tmp/web.log 2>&1 &
sleep 2; ss -ltn | grep 8080
```

**Expected:** a line with `*:8080`.

### G2. Download it

curl options: `-6` IPv6, `-s` silent, `-o /dev/null` discard the file, `-m 10` give up after 10 seconds, `-w` print the bytes received, `-g` allow the square brackets around the IPv6 address.

pc1 downloads, so **pc2** sends the big packets, and **r2** must fit them into the tunnel.

**Predict first:** who sends Packet Too Big, and to whom?

<details>
<summary>▶ Answer</summary>

r2, to pc2. pc2 then sends smaller packets and the download completes.
</details>

**Terminal 1 (pc1):**

```
curl -6 -s -o /dev/null -m 10 -w '%{size_download} bytes\n' -g 'http://[2001:db8:b:0:5054:ff:fea3:2]:8080/big.bin'
```

**Expected:** `300000 bytes`. pc2 sent 1500-byte packets, r2 answered with Packet Too Big, and pc2 resent smaller ones (as in Part C).

:::warning
`0 bytes`? The web server may still have been starting. Wait a few seconds and run the curl again.
:::

Check what pc2 learned, as you did for pc1 in C4. **Terminal 5 (pc2):**

```
ip -6 route get 2001:db8:a:0:5054:ff:fea3:1
```

**Expected:** the line contains `mtu 1480`, for example:

```
2001:db8:a:0:5054:ff:fea3:1 from :: via fe80::5054:ff:fea3:bfe dev eth0 proto ra src 2001:db8:b:0:5054:ff:fea3:2 metric 1024 expires 597sec mtu 1480 hoplimit 64 pref medium
```

**How to read this:** `mtu 1480` is the 6in4 tunnel MTU. pc2 learned it from r2's Packet Too Big. Path MTU Discovery worked.

### G3. Break it

nftables is the Linux firewall. A **table** holds chains; `inet` means it covers IPv4 and IPv6. A **chain** is a list of rules attached to a **hook**: `output` sees packets that r2 **creates itself**, such as its Packet Too Big messages. The rule drops them. This copies a real mistake: blocking ICMP "for security".

**Terminal 4 (r2):** drop the Packet Too Big messages r2 sends, the way a badly configured firewall would:

```
nft add table inet lab
nft add chain inet lab out '{ type filter hook output priority 0; }'
nft add rule inet lab out icmpv6 type packet-too-big drop
```

`ip -6 route flush cache` clears the MTU values pc2 learned in G2, so it must learn again, which it now cannot.

**Terminal 5 (pc2):** make pc2 forget the MTU it learned:

```
ip -6 route flush cache
```

**Predict first:** what will curl print? Will the connection open at all?

<details>
<summary>▶ Answer</summary>

The connection opens (handshake and request are small). The big data packets are dropped silently, so curl waits 10 seconds and prints `0 bytes`.
</details>

Run the same curl in **Terminal 1 (pc1)** again.

**Expected:** `0 bytes` after 10 seconds. The connection opens (small packets), but every full-size data packet is dropped at r2 and pc2 is never told why. That is a **black hole**.

**How to read this:** no "connection refused", no "no route", just a wait and then nothing. A hang with no error while small things still work is the classic sign.

**Explain why:** small pings from pc1 to pc2 still work now. Why?

<details>
<summary>▶ Answer</summary>

A normal ping is about 100 bytes, far below the 1480-byte tunnel MTU. r2 never needs to send Packet Too Big for it, so the firewall rule never matters. That is why "ping works" proves nothing about large packets.
</details>

### G4. Fix it

The real fix is to stop blocking Packet Too Big. Deleting a table deletes its chains and rules.

**Predict first:** you remove the rule. pc2 has not learned the MTU yet. Will the next download work?

<details>
<summary>▶ Answer</summary>

Yes. pc2's first big packet is dropped, but now r2's Packet Too Big reaches pc2, which learns 1480 and resends smaller packets, as in G2.
</details>

**Terminal 4 (r2):**

```
nft delete table inet lab
```

Run the curl in **Terminal 1 (pc1)** again. **Expected:** `300000 bytes`.

**Put it back:** stop the web server (`pkill -f` matches the full command line). **Terminal 5 (pc2):**

```
pkill -f http.server
```

Stretch S5 shows a workaround, MSS clamping, for networks where you cannot remove such a rule yourself.

---

## Part H: Break it, find it, fix it (15 min)

*From today's lecture: Module 8, Key Troubleshooting Tools (ping, traceroute, `ip -6 route`, tcpdump).*

:::info
**Why this matters**

Most real tunnel problems are small mistakes: a wrong address, a missing route. You will make two on purpose and learn what each looks like from outside. The method: test from a host, then look at the wire in the middle.
:::

You are still on the 6in4 tunnel (`sit1`) from Part D. These are the three tests for every step of this part:

- **Terminal 1 (pc1):** `ping -6 -c2 -W1 2001:db8:b:0:5054:ff:fea3:2` and `traceroute -6 -n -w1 -m5 2001:db8:b:0:5054:ff:fea3:2`
- **Terminal 3 (inet):** `tcpdump -ni eth0 -c6 'ip proto 41 or icmp'` while you ping

`-w1` makes traceroute wait at most 1 second for each answer, and `-m5` stops it after 5 hops. The tcpdump filter shows 6in4 packets (protocol 41) and IPv4 ICMP errors, such as those inet sends. If tcpdump does not stop by itself, press **Ctrl+C**.

### H1. Know what "healthy" looks like

Before you break anything, run the three tests once while everything works. You need a normal result to compare with.

**Expected:** the ping shows `0% packet loss`. traceroute shows three hops:

```
 1  2001:db8:a::1  ...
 2  2001:db8:fe::2  ...
 3  2001:db8:b:0:5054:ff:fea3:2  ...
```

On inet, you see 6in4 packets in **both** directions: `IP 192.0.2.2 > 198.51.100.2: IP6 ...` (requests) and `IP 198.51.100.2 > 192.0.2.2: IP6 ...` (replies).

**How to read this:** hop 1 is r1, hop 2 is r2 (it answers from its tunnel address), hop 3 is pc2. inet is not in the list. Stretch S1 explains why. For now, remember: three hops, traffic in both directions on inet.

For each fault below: make the change, **predict** what pc1 will see, then run the three tests.

### H2. Wrong tunnel endpoint

This points the tunnel at an address where no router exists, like a typo or a changed provider address.

**Terminal 2 (r1):**

```
ip tunnel change sit1 remote 198.51.100.9
```

<details>
<summary>▶ Expected result and fix</summary>

No reply on pc1. On inet you see 6in4 packets going to `198.51.100.9` (`IP 192.0.2.2 > 198.51.100.9: IP6 ...`) and `ICMP net 198.51.100.9 unreachable` going back to r1: inet has no route to that address.

Fix, in **Terminal 2 (r1)**:

```
ip tunnel change sit1 remote 198.51.100.2
```
</details>

**Explain why:** inet sends an error. Why does it not help pc1?

<details>
<summary>▶ Answer</summary>

It is an IPv4 error about the outer packet, so it goes to the outer source, r1. pc1 never sees it. That is why you capture in the middle.
</details>

### H3. Missing return route

**Terminal 4 (r2):**

```
ip -6 route del 2001:db8:a::/64
```

<details>
<summary>▶ Expected result and fix</summary>

No reply on pc1, and traceroute shows only r1 and then `* * *`. On inet you see 6in4 packets going one way only (`192.0.2.2 > 198.51.100.2`). The tunnel works; r2 just cannot send anything back to LAN A.

Fix, in **Terminal 4 (r2)**:

```
ip -6 route add 2001:db8:a::/64 via 2001:db8:fe::1
```
</details>

**Explain why:** r2 receives the second traceroute probe. Why does it not appear as hop 2?

<details>
<summary>▶ Answer</summary>

r2 wants to send Time Exceeded to pc1, but it has no route to LAN A, so that message is lost too. When a capture shows traffic in one direction only, check the return routes.
</details>

Run the three tests once more. **Expected:** the same healthy result as in H1. Both faults are fixed, so there is nothing else to put back.

---

## Part I: DHCPv6 on LAN B, stateful and stateless (25 min)

*From today's lecture: Module 9, DHCPv6 vs SLAAC (the M and O flags, stateful and stateless DHCPv6).*

LAN B gets its addresses from radvd on r2 (SLAAC). Here r2 hands them out with DHCPv6 instead.

:::info
**Why this matters**

With SLAAC the network has no central record of who uses which address, and many organisations want one, or want to hand out DNS settings centrally. Router Advertisements tell hosts what to use, with two flags:

- **M** (Managed): get your **address** from DHCPv6. **Stateful**: the server remembers which address each host has.
- **O** (Other): use SLAAC for the address, but get **other settings** (such as DNS) from DHCPv6. **Stateless**: no per-host record.

Either way the RA is still needed: DHCPv6 never gives hosts a default router.
:::

### I1. Stateful DHCPv6 (M flag)

dnsmasq is a small DNS and DHCP server. Its options: `-u root` run as root, `--port=0` switch off its DNS part, `--interface=eth0 --bind-interfaces` serve LAN B only, `--dhcp-range=...::100,...::1ff,64,1h` hand out `::100` to `::1ff` with a 1-hour lease (`64` is the prefix length for the RA), `--log-dhcp --log-facility=...` log every message. `\` continues the command on the next line.

**Terminal 4 (r2):** stop radvd and start dnsmasq as a DHCPv6 server. `--enable-ra` makes it send Router Advertisements with the **M** flag ("get your address from DHCPv6"). Paste the whole box:

```
pkill radvd
dnsmasq -u root --port=0 --interface=eth0 --bind-interfaces --enable-ra \
  --dhcp-range=2001:db8:b::100,2001:db8:b::1ff,64,1h \
  --log-dhcp --log-facility=/tmp/dnsmasq.log
```

**Expected:** no output. Check with `pgrep -a dnsmasq`.

### I2. Ask for an address on pc2

Flushing removes the global addresses but keeps the link-local one, which the DHCPv6 client talks from. `rdisc6` sends a Router Solicitation and prints the RA it receives.

**Terminal 5 (pc2):** drop the SLAAC address, read the RA, then ask DHCPv6:

```
ip -6 addr flush dev eth0 scope global
sleep 8; rdisc6 eth0
```

**Expected** in the rdisc6 output:

```
Stateful address conf.    :          Yes
```

**How to read this:** `Stateful address conf.` is the **M** flag; the next line, `Stateful other conf.`, is the **O** flag. With M set, pc2's address will come from DHCPv6.

`dhclient` options: `-6` DHCPv6, `-v` print each message, `-1` try once only.

**Predict first:** what prefix length will the DHCPv6 address have?

<details>
<summary>▶ Answer</summary>

/128. I3 explains why.
</details>

Now ask for an address:

```
dhclient -6 -v -1 eth0
ip -6 addr show dev eth0
```

**Expected:** dhclient prints its exchange (`XMT: Solicit`, `RCV: Advertise`, `XMT: Request`, `RCV: Reply`), and pc2 has an address between `2001:db8:b::100` and `2001:db8:b::1ff`, for example:

```
    inet6 2001:db8:b::1a7/128 scope global dynamic
```

**How to read this:** `XMT` = sent, `RCV` = received. **Solicit**: pc2 asks for a server (to multicast `ff02::1:2`, all DHCPv6 servers and relays). **Advertise**: r2 offers. **Request**: pc2 asks for that address. **Reply**: r2 confirms. Same idea as DHCPv4's Discover, Offer, Request, Ack. `dynamic` means the address has a lease time.

### I3. Why /128?

Look at the prefix length on that address: **/128**, not /64. DHCPv6 gives an address only. The on-link prefix and the default route still come from the Router Advertisement.

**Terminal 5 (pc2):**

```
ip -6 route
```

**Expected:** `2001:db8:b::/64 dev eth0 proto kernel ...` and `default via fe80::5054:ff:fea3:bfe dev eth0 proto ra ...`. Both come from the RA: the on-link prefix and the default router.

**How to read this:** the `/64` route says "these addresses are on my link, talk to them directly"; the kernel added it from the prefix in the RA. The default route (`proto ra`) points to r2's link-local address.

**Explain why:** why can DHCPv6 not replace Router Advertisements?

<details>
<summary>▶ Answer</summary>

DHCPv6 cannot tell a host its default router or its on-link prefix. Without an RA, pc2 would have an address but could not reach other networks.
</details>

From **Terminal 1 (pc1)**, ping pc2's new address through the tunnel (use the address you saw, for example `ping -6 -c2 2001:db8:b::1a7`). **Expected:** `0% packet loss`.

### I4. Read the exchange on the server

**Terminal 4 (r2):**

```
cat /tmp/dnsmasq.log
```

**Expected:** lines with `DHCPSOLICIT`, `DHCPADVERTISE`, `DHCPREQUEST` and `DHCPREPLY`, and the address that was handed out.

**How to read this:** the same four messages from the server's side. The record of which client (identified by its DUID, a DHCP client ID) got which address is the **state** in stateful DHCPv6.

### I5. Stateless DHCPv6 (O flag)

Now SLAAC gives the address, and DHCPv6 gives only "other" settings such as DNS servers.

`ra-stateless` means no address pool: the RA says "SLAAC for the address, DHCPv6 for the rest" (O set, M not set). The two `--dhcp-option` lines give a DNS server (IPv6 address in square brackets) and a search domain (`www` is tried as `www.lab.example`).

**Terminal 4 (r2):**

```
pkill dnsmasq
dnsmasq -u root --port=0 --interface=eth0 --bind-interfaces --enable-ra \
  --dhcp-range=2001:db8:b::,ra-stateless,64 \
  --dhcp-option=option6:dns-server,[2001:db8:b::53] \
  --dhcp-option=option6:domain-search,lab.example \
  --log-dhcp --log-facility=/tmp/dnsmasq.log
```

### I6. pc2 with stateless DHCPv6

`pkill dhclient` stops the old client, which still held its lease.

**Predict first:** which flags will the RA show, and what address will pc2 get?

<details>
<summary>▶ Answer</summary>

M = No, O = Yes. pc2 builds its SLAAC /64 address from its MAC again.
</details>

**Terminal 5 (pc2):**

```
pkill dhclient; ip -6 addr flush dev eth0 scope global
sleep 10; rdisc6 eth0; ip -6 addr show dev eth0
```

**Expected:** in the RA, `Stateful address conf. : No` and `Stateful other conf. : Yes`, and pc2 has its SLAAC address `2001:db8:b:0:5054:ff:fea3:2/64` again.

Ask for the other settings only (`-S` sends an Information-Request, not a Solicit):

```
dhclient -6 -S -v -1 eth0
cat /etc/resolv.conf
```

**Expected:** `/etc/resolv.conf` contains `nameserver 2001:db8:b::53` and `search lab.example`.

**How to read this:** `/etc/resolv.conf` holds Linux's DNS settings; both lines came from DHCPv6. Only two messages were needed (Information-Request, Reply), because no address is reserved.

### I7. Put it back

**Terminal 4 (r2):**

```
pkill dnsmasq; radvd
```

**Terminal 5 (pc2):**

```
pkill dhclient; ip -6 addr flush dev eth0 scope global
sleep 10; ip -6 addr show dev eth0
```

**Expected:** `2001:db8:b:0:5054:ff:fea3:2` is back.

---

## Part J: Firewall r2 without breaking IPv6 (20 min)

*From today's lecture: Module 10, Firewalling IPv6 (stateful firewalls; do not block all ICMPv6).*

:::info
**Why this matters**

Many IPv4 administrators block all ICMP "for security". In IPv6 that breaks the network: Neighbor Discovery (IPv6's ARP), Router Advertisements and Packet Too Big are all ICMPv6. You will break r2 with such a rule, then build a policy that drops by default but allows what IPv6 needs. You will also see the difference between traffic **to** the router (`input` hook) and **through** it (`forward` hook).
:::

### J1. A "security" rule that breaks everything

The chain `in` sits on the `input` hook (packets addressed to r2 itself), with `policy accept` (unmatched packets pass). The rule drops Neighbor Solicitation and Advertisement.

**Predict first:** pc2 clears its neighbour cache and pings r2. What happens?

<details>
<summary>▶ Answer</summary>

It fails. pc2 sends a Neighbor Solicitation to learn r2's MAC address, r2 drops it, and pc2 can never send the echo request.
</details>

**Terminal 4 (r2):** drop Neighbor Solicitation and Advertisement:

```
nft add table inet lab
nft add chain inet lab in '{ type filter hook input priority 0; policy accept; }'
nft add rule inet lab in icmpv6 type '{ nd-neighbor-solicit, nd-neighbor-advert }' drop
```

### J2. Test

`ip -6 neigh flush` empties pc2's neighbour cache, like clearing an ARP table.

**Terminal 5 (pc2):**

```
ip -6 neigh flush dev eth0; ping -6 -c2 -W1 2001:db8:b::1
```

**Expected:** `100% packet loss`.

**Terminal 1 (pc1):**

```
ping -6 -c2 -W1 2001:db8:b:0:5054:ff:fea3:2
```

**Expected:** this fails too. pc2 (whose cache you just cleared) can no longer find r2's MAC address to send its replies, and r2 soon loses pc2's entry as well. With no Neighbor Discovery there is no "ARP", so nothing works.

### J3. A sensible policy

Drop by default, but allow the ICMPv6 that IPv6 needs. **Terminal 4 (r2):** paste the whole box:

```
nft flush chain inet lab in
nft add rule inet lab in ct state established,related accept
nft add rule inet lab in iif lo accept
nft add rule inet lab in icmpv6 type '{ destination-unreachable, packet-too-big, time-exceeded, parameter-problem, echo-request, echo-reply, nd-router-solicit, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert }' accept
nft add rule inet lab in ip protocol icmp accept
nft add chain inet lab in '{ policy drop; }'
```

Line by line: remove the bad rule; allow replies to r2's own connections and their related ICMP errors (`ct` = connection tracking); allow loopback; allow the ICMPv6 that IPv6 needs (errors, echo, and the four Neighbor Discovery types); allow IPv4 ICMP (errors about the tunnel's IPv4 path, as in H2); finally set the policy to **drop**. The policy comes last so the allow rules are in place before anything is dropped.

Show the result:

```
nft list table inet lab
```

**How to read this:** the chain shows its hook (`input`), its policy (`drop`; priority 0 may appear as `filter`), then the rules. nftables checks rules from the top; the first accept or drop decides. Packets that match nothing get the policy.

**Predict first:** which ping from J2 works now? Hint: what protocol are the tunnel packets when they reach r2?

<details>
<summary>▶ Answer</summary>

pc2 to r2 works (ND and echo allowed). pc1 to pc2 still fails; see below.
</details>

### J4. Test again, then allow the tunnel

Repeat the two pings from J2 (pc2 to r2, pc1 to pc2).

**Expected:** pc2 can ping r2 now, but pc1 still cannot reach pc2.

<details>
<summary>▶ Why does pc1 still fail?</summary>

The tunnel packets arrive at r2 as **IPv4 protocol 41** (6in4), addressed to r2 itself. They go through r2's `input` chain, and the new policy drops everything it does not allow, including protocol 41.
</details>

Allow the tunnel. **Terminal 4 (r2):**

```
nft add rule inet lab in ip protocol 41 accept
```

(Use `ip protocol gre` instead if you are on a GRE tunnel.) Ping from **Terminal 1 (pc1)** again. **Expected:** it works.

**Explain why:** after r2 unwraps the 6in4 packet, the inner pc1-to-pc2 packet is not for r2. Which hook checks it?

<details>
<summary>▶ Answer</summary>

`forward`, because it passes through r2. `input` saw only the outer IPv4 packet, which was addressed to r2. The next step filters that forwarded traffic.
</details>

### J5. Filter traffic passing through r2

**Terminal 5 (pc2):** run two web servers:

```
cd /tmp && echo "Hello from pc2" > index.html
python3 -m http.server 8080 --bind :: > /dev/null 2>&1 &
python3 -m http.server 9090 --bind :: > /dev/null 2>&1 &
```

The new chain is on the `forward` hook with `policy drop`. It allows replies to allowed connections, all ICMPv6 passing through (including Packet Too Big), and new TCP connections from LAN A to port 8080 only: a typical "allow one service" policy.

**Terminal 4 (r2):** allow only port 8080 from LAN A:

```
nft add table inet fw
nft add chain inet fw transit '{ type filter hook forward priority 0; policy drop; }'
nft add rule inet fw transit ct state established,related accept
nft add rule inet fw transit meta l4proto ipv6-icmp accept
nft add rule inet fw transit ip6 saddr 2001:db8:a::/64 tcp dport 8080 accept
```

**Predict first:** of the three tests below, which work? Will port 9090 fail at once or after a wait?

<details>
<summary>▶ Answer</summary>

8080 and the ping work. 9090 fails after a wait, because r2 drops the connection request silently.
</details>

### J6. Test from pc1

`-m3` gives up after 3 seconds; `echo "exit code $?"` prints curl's exit code.

**Terminal 1 (pc1):**

```
curl -s -m3 -g "http://[2001:db8:b:0:5054:ff:fea3:2]:8080/"
curl -s -m3 -g "http://[2001:db8:b:0:5054:ff:fea3:2]:9090/"; echo "exit code $?"
ping -6 -c1 -W2 2001:db8:b:0:5054:ff:fea3:2
```

**Expected:** port 8080 answers `Hello from pc2`, port 9090 times out (`exit code 28`), and the ping works.

**How to read this:** exit code 28 means "timed out". A timeout, not "connection refused", shows a silent drop: the SYN vanished at the firewall.

<details>
<summary>▶ Why does the rule meta l4proto ipv6-icmp accept matter, even if you only care about the web server?</summary>

Without it, r2 would also drop ICMPv6 errors passing through, including **Packet Too Big**. Large transfers through the tunnel would hang: the Path MTU black hole from Part G.
</details>

### J7. Clean up

`pkill -f` matches the full command line, so it stops both servers.

**Terminal 4 (r2):**

```
nft delete table inet fw; nft delete table inet lab
```

**Terminal 5 (pc2):**

```
pkill -f http.server
```

---

## Part K: Rogue Router Advertisement, attack and defense (25 min)

*From today's lecture: Module 10, NDP Security Issues & Mitigations (Router Advertisement spoofing, RA Guard).*

This part needs a link with two hosts and a router, so it uses your **Lab 1** network. Any host on a link can claim to be a router. Here pc2 does it.

:::info
**Why this matters**

Router Advertisements are not authenticated, and hosts trust them. A fake router with a higher preference becomes the hosts' default gateway, so all their traffic to other networks passes through it. It can read, change or drop that traffic: a "man in the middle". A misconfigured PC can cause the same trouble by accident. You will play the attacker, prove the traffic is captured, then block the fake RAs.
:::

### K0. Get Lab 1 ready

Open three more terminals: `lab 1 pc1`, `lab 1 pc2` and `lab 1 r1`. Below they are called **Lab 1 pc1**, **Lab 1 pc2** and **Lab 1 r1**.

In **Lab 1 pc1**, run `ip -6 addr show dev eth0`. If you see `2001:db8:a:0:5054:ff:fea1:1`, Lab 1 is ready: go to K1.

If not (for example because Cloud9 slept and rebuilt the labs), set up r1 as in Lab 1 Part C. **Lab 1 r1:** paste the whole box:

```
sysctl -w net.ipv6.conf.all.forwarding=1
ip -6 addr add 2001:db8:a::1/64 dev eth0
cat > /etc/radvd.conf <<'EOF'
interface eth0 {
    AdvSendAdvert on;
    MinRtrAdvInterval 3;
    MaxRtrAdvInterval 10;
    prefix 2001:db8:a::/64 {
        AdvOnLink on;
        AdvAutonomous on;
    };
};
EOF
radvd
```

This rebuilds Lab 1's router: forwarding on (radvd expects to run on a router), r1's address, and a radvd file that sends RAs every 3 to 10 seconds with the prefix flags `AdvOnLink` (on-link) and `AdvAutonomous` (SLAAC allowed).

After about 10 seconds, check again in **Lab 1 pc1**. **Expected:** `2001:db8:a:0:5054:ff:fea1:1` and `default via fe80::5054:ff:fea1:fe`.

### K1. Make pc2 a rogue router

Two differences from r1's file: `AdvDefaultPreference high` sets the RA's router preference (low, medium or high; medium is normal), and a different prefix, `2001:db8:bad::/64`, makes the rogue's work easy to spot. Forwarding is on because radvd expects to run on a router; a real attacker would also forward traffic on so nobody notices.

**Predict first:** after 10 seconds, what will pc1 have, and which default route will it use?

<details>
<summary>▶ Answer</summary>

A second address from `2001:db8:bad::/64` and two default routes. pc1 uses pc2's, because its preference is higher.
</details>

**Lab 1 pc2:** paste the whole box:

```
cat > /etc/radvd.conf <<'EOF'
interface eth0 {
    AdvSendAdvert on;
    MinRtrAdvInterval 3;
    MaxRtrAdvInterval 10;
    AdvDefaultPreference high;
    prefix 2001:db8:bad::/64 { AdvOnLink on; AdvAutonomous on; };
};
EOF
sysctl -w net.ipv6.conf.all.forwarding=1
radvd
```

### K2. Look at pc1

**Lab 1 pc1**, after about 10 seconds:

```
ip -6 addr show dev eth0
ip -6 route
```

**Expected:** a new address `2001:db8:bad:0:5054:ff:fea1:1`, and two default routes:

```
default via fe80::5054:ff:fea1:fe dev eth0 proto ra metric 1024 expires 24sec hoplimit 64 pref medium
default via fe80::5054:ff:fea1:2 dev eth0 proto ra metric 1024 expires 27sec hoplimit 64 pref high
```

There are two gateways: pc2 (`fe80::5054:ff:fea1:2`) with **pref high** and r1 (`...:fea1:fe`) with **pref medium**. The high preference wins. pc1 now sends traffic for the outside world to pc2, which could read or change it.

**How to read this:** both routes are `proto ra`: pc1 cannot tell a real router from a fake one. `expires` counts down the router lifetime and is reset by each new RA. The metric is equal, so `pref` decides. The rogue removed nothing; it only added.

### K3. Prove it

`2001:db8:ffff::1` is off-link, so pc1 sends the ping to its preferred default router.

**Predict first:** the pings are not addressed to pc2. Will pc2 see them?

<details>
<summary>▶ Answer</summary>

Yes. The IPv6 destination is `2001:db8:ffff::1`, but the Ethernet destination is pc2's MAC, because pc2 is now pc1's gateway.
</details>

**Lab 1 pc2:**

```
tcpdump -ni eth0 icmp6 and dst 2001:db8:ffff::1
```

**Lab 1 pc1:**

```
ping -6 -c3 -W1 2001:db8:ffff::1
```

**Expected:** Lab 1 pc2 sees pc1's three echo requests. Press **Ctrl+C** in Lab 1 pc2.

### K4. Defend pc1

The rule drops every RA whose Ethernet source MAC is **not** r1's. You can check it is r1's MAC: r1's link-local `fe80::5054:ff:fea1:fe` is built from it by EUI-64 (Day 1): `52` becomes `50` when the U/L bit flips, and `ff:fe` goes in the middle. The next three lines remove what pc1 already learned: routes from RAs, the rogue prefix route, and the global addresses. r1's next RA brings back the good ones; the rogue's RAs are now dropped.

**Lab 1 pc1:** accept Router Advertisements only from r1's MAC address, then throw away what pc1 learned from the rogue:

```
nft add table inet guard
nft add chain inet guard in '{ type filter hook input priority 0; policy accept; }'
nft add rule inet guard in icmpv6 type nd-router-advert ether saddr != 52:54:00:a1:00:fe drop
ip -6 route flush dev eth0 proto ra
ip -6 route del 2001:db8:bad::/64 dev eth0
ip -6 addr flush dev eth0 scope global
```

Wait 10 seconds, then:

```
ip -6 addr show dev eth0
ip -6 route
```

**Expected:** only `2001:db8:a:0:5054:ff:fea1:1` comes back, and the only default route is via r1 (`fe80::5054:ff:fea1:fe`).

**Explain why:** why is this filter weak protection on a real network?

<details>
<summary>▶ Answer</summary>

An attacker can fake r1's MAC address as the source, and you would need the filter on every host. That is why the protection belongs in the switch.
</details>

### K5. Clean up

**Lab 1 pc2:**

```
pkill radvd; sysctl -w net.ipv6.conf.all.forwarding=0
```

**Lab 1 pc1:**

```
nft delete table inet guard
```

:::info
On real networks this protection lives in the switch, not on every PC. It is called **RA Guard**.
:::

With RA Guard, the switch allows Router Advertisements only on the port where the real router is connected, and drops RAs from every other port before they reach the hosts.

---

## Check your work

Open a **new** terminal (**Window > New Terminal**); leave the five node terminals as they are. In the new terminal (the Cloud9 machine):

```
sudo labctl check 3 1
```

**Expected:** ten `PASS` lines and:

```
Result: 10 passed, 0 failed
```

The checks cover the tunnel (Parts A to D) and that you put things back in Parts F, G, I and J. The last check sends a few pings from pc1 and watches inet: it should see them only as IPv4 tunnel packets. Part K runs on your Lab 1 nodes, so this check does not cover it.

<details>
<summary>▶ I got a FAIL. What now?</summary>

| FAIL line mentions | Go back to |
|---|---|
| tunnel interface | D2 / D3: `ip link show sit1` on r1 should say `UP` |
| pc1 pings pc2 | Routes on **both** routers (`ip -6 route`), and `local`/`remote` swapped on r2 (H2, H3 fixes) |
| test route for `2001:db8:c::/64` | F4 put back: `ip -6 route del 2001:db8:c::/64` on r1 |
| Router Advertisements with radvd | I7 put back: `pkill dnsmasq; radvd` on r2 |
| no firewall tables | G4 and J7 put back: `nft list tables` on r2 should print nothing |
| inet sees the traffic | Run the check again; if it still fails, check that the ping in D4 works |
</details>

## Check yourself

1. Why does the tunnel need IPv4 addresses on both ends but IPv6 addresses inside?
2. What would break if a firewall on the path dropped ICMPv6 Packet Too Big?
3. When would you pick GRE over 6in4?
4. Why do address plans divide a /48 on nibble boundaries, such as /56 and /64?
5. Which ICMPv6 message would you expect from a firewall that rejects instead of drops?
6. A capture in the middle of a tunnel shows packets in one direction only. What do you check first?
7. Why is a DHCPv6 address /128, and where does the default route come from?
8. What do the M and O flags in a Router Advertisement tell hosts?
9. Name three ICMPv6 types you must never block, and why.
10. Why is a rogue RA dangerous even if it does not take any existing address?

<details>
<summary>▶ Answers</summary>

1. The network between the routers speaks only IPv4, so the outer packet that inet forwards must carry IPv4 source and destination addresses (the tunnel's `local` and `remote`). The IPv6 addresses inside the tunnel let the routers route IPv6 into it like into any other link.
2. Path MTU Discovery. Hosts would keep sending packets too big for the tunnel, the router would keep dropping them, and the sender would never be told. Small packets work; big ones vanish (Part G).
3. When you need to carry more than IPv6: IPv4, multicast for a routing protocol, or several tunnels between the same two routers (GRE keys, Stretch S3). 6in4 is lighter (4 bytes less overhead) but carries only IPv6.
4. Each level is then a whole number of hex digits, so you can read the site and the LAN straight from the address (Part E). A split such as /57 falls in the middle of a hex digit.
5. Destination Unreachable, usually with code "Administratively prohibited" (F3).
6. The return routes on the far tunnel router (H3). The tunnel itself works if packets arrive at the far end.
7. DHCPv6 hands out an address, not a prefix or a route. The on-link prefix and the default route come from the Router Advertisement.
8. M (Managed): get your address from DHCPv6. O (Other): get other settings, such as DNS servers, from DHCPv6.
9. For example: Packet Too Big (Path MTU Discovery breaks), Neighbor Solicitation and Neighbor Advertisement (no neighbor can be reached at all), Router Advertisement (hosts get no prefix or gateway), Time Exceeded and Destination Unreachable (troubleshooting and fast failure).
10. It can make itself the preferred default gateway, so hosts send their outside traffic through the attacker, who can read, change or drop it.
</details>

---

# Stretch exercises (about 65 minutes)

Do these after Part K, in order, on the five Lab 3 nodes and terminals. You finished the core parts with the 6in4 (`sit1`) tunnel from Part D.

## S1: Where did inet go? (10 min)

*Ties to today's Module 8, Monitoring and Basic Tools: traceroute6 maps the path by raising the Hop Limit one step at a time. Here you see what it cannot see inside a tunnel (you saw the three hops in Part H).*

:::info
**Why this matters**

traceroute is often the first tool used when something is slow or broken. Through a tunnel, one "hop" can hide a whole IPv4 network. Knowing this helps you read traceroute correctly on real networks.
:::

traceroute sends probes with hop limit 1, 2, 3 and so on. Each router that lowers the hop limit to 0 answers with ICMPv6 Time Exceeded, which reveals who it is (Part F). `-n` shows numbers.

**Predict first:** how many hops will you see? Will inet appear? Decide, then compare with the output and the folded explanation.

**Terminal 1 (pc1):**

```
traceroute -6 -n 2001:db8:b:0:5054:ff:fea3:2
```

**Expected:** three hops:

```
 1  2001:db8:a::1  ...
 2  2001:db8:fe::2  ...
 3  2001:db8:b:0:5054:ff:fea3:2  ...
```

r1, then r2 at the far end of the tunnel, then pc2. inet never shows up.

**How to read this:** r2 answers from its **tunnel** address `2001:db8:fe::2`, because the probe arrived through the tunnel. The `...` are the times of the three probes per hop.

<details>
<summary>▶ Why not?</summary>

The IPv6 hop limit only goes down at r1 and r2. inet forwards the outer IPv4 packet and lowers the **IPv4** TTL, which the IPv6 packet inside never sees. To IPv6, the whole IPv4 network is one hop.
</details>

## S2: Back to GRE, and carry IPv4 through it too (20 min)

*Ties to today's Module 10, IPsec in IPv6: site-to-site VPNs are often "GRE over IPsec", and GRE is chosen there because it carries more than IPv6 (Day 2's Module 5, Manual Tunnels: GRE). Private IPv4 networks and dual stack are from Day 1 and Day 2.*

:::info
**Why this matters**

Because the GRE header names the inner protocol, one GRE tunnel can carry IPv6 and IPv4 together. Real use: two offices with private IPv4 networks (`10.x.x.x`) joined across the internet. The internet cannot route private addresses, but it does not need to: it only reads the outer header.
:::

### S2-1. Swap the 6in4 tunnel back to GRE

The commands from B1 and B2, after removing `sit1`.

**Terminal 2 (r1):**

```
ip tunnel del sit1
ip tunnel add gre1 mode gre local 192.0.2.2 remote 198.51.100.2 ttl 255
ip link set gre1 up
ip -6 addr add 2001:db8:fe::1/64 dev gre1
ip -6 route add 2001:db8:b::/64 via 2001:db8:fe::2
```

**Terminal 4 (r2):**

```
ip tunnel del sit1
ip tunnel add gre1 mode gre local 198.51.100.2 remote 192.0.2.2 ttl 255
ip link set gre1 up
ip -6 addr add 2001:db8:fe::2/64 dev gre1
ip -6 route add 2001:db8:a::/64 via 2001:db8:fe::1
```

**Terminal 1 (pc1):**

```
ping -6 -c2 2001:db8:b:0:5054:ff:fea3:2
```

**Expected:** `0% packet loss`.

### S2-2. Give both LANs private IPv4 networks, routed through the tunnel

On each router: `sysctl -w net.ipv4.ip_forward=1` lets it forward IPv4 (a separate switch from IPv6 forwarding). `ip addr add` puts an IPv4 network on the LAN, which is now dual stack (Day 2). `ip route add ... dev gre1` sends the other LAN's IPv4 network into the tunnel; no `via` is needed, because a point-to-point link has only one other end.

**Terminal 2 (r1):**

```
sysctl -w net.ipv4.ip_forward=1
ip addr add 10.1.0.1/24 dev eth0
ip route add 10.2.0.0/24 dev gre1
```

**Terminal 4 (r2):**

```
sysctl -w net.ipv4.ip_forward=1
ip addr add 10.2.0.1/24 dev eth0
ip route add 10.1.0.0/24 dev gre1
```

Each host gets an IPv4 address and a default gateway (its router's `10.x` address).

**Terminal 1 (pc1):**

```
ip addr add 10.1.0.10/24 dev eth0; ip route add default via 10.1.0.1
```

**Terminal 5 (pc2):**

```
ip addr add 10.2.0.10/24 dev eth0; ip route add default via 10.2.0.1
```

**Predict first:** inet has no route to any `10.x` network. Will pc1 reach `10.2.0.10`?

<details>
<summary>▶ Answer</summary>

Yes. inet never routes a `10.x` address: the outer header still says `192.0.2.2 > 198.51.100.2`.
</details>

### S2-3. Ping over IPv4 through the tunnel

**Terminal 1 (pc1):**

```
ping -c2 10.2.0.10
```

**Expected:** `0% packet loss`.

### S2-4. inet carries traffic for a network it does not know

`ip route get` asks inet where it would send a packet for `10.2.0.10`.

**Terminal 3 (inet):**

```
ip route get 10.2.0.10
```

**Expected:** `RTNETLINK answers: Network is unreachable`. inet has no idea where `10.2.0.0` is.

Now capture:

```
tcpdump -ni eth0 -c2 'ip proto 47'
```

and in **Terminal 1 (pc1)** run `ping -c2 10.2.0.10` again.

**Expected** in Terminal 3 (inet):

```
IP 192.0.2.2 > 198.51.100.2: GREv0, length 88: IP 10.1.0.10 > 10.2.0.10: ICMP echo request, id 9, seq 1, length 64
```

GRE carries IPv4 as easily as IPv6. A 6in4 tunnel could not do this; it carries only IPv6.

**How to read this:** after `GREv0` comes `IP 10.1.0.10 > 10.2.0.10`: IPv4 inside IPv4. `length 88` = 4 (GRE) + 20 (inner IPv4 header) + 64 (ICMP). It was 108 for IPv6 because the IPv6 header is 20 bytes bigger.

**Explain why:** how does r2 know whether the unwrapped packet is IPv4 or IPv6?

<details>
<summary>▶ Answer</summary>

The GRE header has a protocol type field, using Ethernet's EtherType codes: `0x86DD` for IPv6, `0x0800` for IPv4. 6in4 has no such field.
</details>

## S3: GRE keys (10 min)

*Ties to today's Module 8 (a silent failure that you find by comparing both ends) and Module 10 (what proves who sent a packet, and what does not). GRE keys were not in the lecture: read the box first.*

:::info
**New in this exercise: GRE keys**

A GRE key is a number both ends must agree on. It is an optional extra 4-byte field in the GRE header. The receiving router uses it to separate tunnels that share the same two endpoint addresses: a packet belongs to the tunnel whose key it carries. It is **not** a password: it travels in clear text, and it proves nothing about who sent the packet.
:::

:::info
**Why this matters**

When two routers need several tunnels between the same two IPv4 addresses, the receiver must tell them apart. The key does this. You will see a key mismatch, that anyone can read the key, and what it costs in MTU.
:::

### S3-1. Set a key on r1 only

`ip tunnel change` modifies a tunnel. `ikey 42`: incoming packets must carry key 42. `okey 42`: put key 42 on outgoing packets.

**Predict first:** r1 now sends key 42 but r2 expects none. What happens to pc1's ping?

<details>
<summary>▶ Answer</summary>

r2 drops the packets because the key does not match its tunnel. Replies (with no key) would also be dropped by r1, which now expects 42.
</details>

**Terminal 2 (r1):**

```
ip tunnel change gre1 ikey 42 okey 42
```

### S3-2. Test

`-W1` waits at most 1 second per reply.

**Terminal 1 (pc1):**

```
ping -6 -c2 -W1 2001:db8:b:0:5054:ff:fea3:2
```

**Expected:** `100% packet loss`. r2 drops GRE packets that carry a key it does not expect.

**How to read this:** loss with no error message: a key mismatch is silent and looks like a broken path. That is why you compare `ip tunnel show` on both ends.

### S3-3. Anyone can read the key

**Terminal 3 (inet):**

```
tcpdump -ni eth0 -c1 'ip proto 47'
```

Ping again from **Terminal 1 (pc1)** (same command as S3-2).

**Expected** in Terminal 3 (inet): `GREv0, key=0x2a` (`0x2a` is 42 in hexadecimal). The key travels in clear text.

**Explain why:** could someone who sees this traffic send packets into your tunnel?

<details>
<summary>▶ Answer</summary>

Yes. They can read the key and both addresses, then forge GRE packets with r1's source address and key 42. The key separates tunnels; it does not prove who sent a packet.
</details>

### S3-4. Set the same key on r2

**Terminal 4 (r2):**

```
ip tunnel change gre1 ikey 42 okey 42
```

Ping again from **Terminal 1 (pc1)**. **Expected:** `0% packet loss`. Leave the key on both routers.

### S3-5. The key costs 4 bytes

**Predict first:** what MTU will `gre1` have now?

<details>
<summary>▶ Answer</summary>

1476 - 4 = 1472 bytes.
</details>

**Terminal 2 (r1):**

```
ip link show gre1
```

**Expected:** `mtu 1472`. The key added 4 more bytes of GRE header (1476 − 4).

Remember 1472: it is the tunnel MTU for the rest of the Stretch exercises.

## S4: A tunnel is not encryption (10 min)

*Ties to today's Module 10, IPsec in IPv6: GRE and 6in4 do not encrypt; IPsec ESP (protocol 50) does. Day 2's GRE slide made the same point: GRE is often paired with IPsec over public networks.*

:::info
**Why this matters**

"Tunnel" sounds like a private pipe. It is not: GRE and 6in4 wrap packets but do not encrypt them. You will hide a word in a ping and read it on inet.
:::

`-X` makes tcpdump print each packet's bytes, in hexadecimal on the left and as text on the right. `-p` fills the ping's data with a repeated pattern.

**Terminal 3 (inet):** capture one packet and show its contents:

```
tcpdump -ni eth0 -c1 -X 'ip proto 47'
```

**Terminal 1 (pc1):** send a ping filled with the bytes of the word SECRET (`53 45 43 52 45 54` in hexadecimal):

```
ping -6 -c1 -p 534543524554 2001:db8:b:0:5054:ff:fea3:2
```

**Expected** in Terminal 3 (inet): the right-hand column of the hex dump shows `SECRETSECRETSECRET...`.

**How to read this:** the first bytes are headers (outer IPv4, GRE with key, IPv6, ICMPv6). Then come the data bytes `5345 4352 4554`, again and again. The right column shows printable bytes as letters and others as dots.

GRE and 6in4 hide nothing. To protect traffic across an untrusted network you add IPsec (or a VPN such as WireGuard) around or instead of the tunnel.

## S5: Work around a black hole with MSS clamping (15 min)

*Ties to today's Module 8, Common Issue: Path MTU Discovery (Part G), and to Day 2's Tunneling Considerations slide, which says "manual MTU clamping might be needed". TCP's MSS and MSS clamping were not in the lecture: read the box first.*

:::info
**New in this exercise: TCP MSS and MSS clamping**

TCP's **MSS** (Maximum Segment Size) is the most data one side wants to receive in one TCP packet. Each side announces it in the first packet of a connection, the **SYN** (the packet that opens a TCP connection). A host sets its MSS from its own link: on Ethernet, 1500 − 40 (IPv6 header) − 20 (TCP header) = 1440.

**MSS clamping** means a router lowers that number in every SYN that passes through it. Then both sides send TCP packets that fit the tunnel from the start, and nobody needs Packet Too Big. It is a workaround for networks where you cannot remove a rule that blocks Packet Too Big.
:::

:::info
**Why this matters**

In Part G you fixed the black hole by removing the bad rule. Sometimes the rule sits in a network that is not yours, and you cannot remove it. MSS clamping on your own tunnel router makes TCP work anyway.
:::

You are on the GRE tunnel with key 42 from S3 (tunnel MTU 1472). If you skipped S3, the numbers in S5-3 differ: see the note there.

### S5-1. Make the black hole again

This repeats G1 and G3: start the web server on pc2, block Packet Too Big on r2, and make pc2 forget the MTU.

**Terminal 5 (pc2):**

```
cd /tmp && head -c 300000 /dev/urandom > big.bin
python3 -m http.server 8080 --bind :: > /tmp/web.log 2>&1 &
sleep 2; ss -ltn | grep 8080
```

**Terminal 4 (r2):**

```
nft add table inet lab
nft add chain inet lab out '{ type filter hook output priority 0; }'
nft add rule inet lab out icmpv6 type packet-too-big drop
```

**Terminal 5 (pc2):**

```
ip -6 route flush cache
```

**Terminal 1 (pc1):**

```
curl -6 -s -o /dev/null -m 10 -w '%{size_download} bytes\n' -g 'http://[2001:db8:b:0:5054:ff:fea3:2]:8080/big.bin'
```

**Expected:** `0 bytes` after 10 seconds, as in G3.

### S5-2. Clamp the MSS on r1

The chain uses the `forward` hook: packets r1 passes between pc1 and the tunnel. The rule matches TCP packets with the SYN flag (connection setup) and sets the MSS to fit the MTU of the route the packet takes (`rt mtu`), minus the IPv6 and TCP headers. pc1's SYN passes r1 on its way into the tunnel, so pc2 learns the lower MSS and never sends a segment that is too big.

**Terminal 2 (r1):** rewrite the TCP maximum segment size (MSS) in every new connection so the packets fit the tunnel:

```
nft add table inet clamp
nft add chain inet clamp transit '{ type filter hook forward priority 0; }'
nft add rule inet clamp transit tcp flags syn tcp option maxseg size set rt mtu
```

**Terminal 5 (pc2):**

```
ip -6 route flush cache
```

**Predict first:** Packet Too Big is still blocked on r2. Will the download work?

<details>
<summary>▶ Answer</summary>

Yes. pc2 never sends a packet too big for the tunnel, so no Packet Too Big is needed.
</details>

Repeat the curl in **Terminal 1 (pc1)**. **Expected:** `300000 bytes`, even though Packet Too Big is still blocked.

**Explain why:** why is MSS clamping called a workaround, not a fix?

<details>
<summary>▶ Answer</summary>

Only TCP has an MSS, so other traffic (for example large UDP packets) still falls into the black hole. The real fix is to let Packet Too Big through.
</details>

### S5-3. See what changed

This captures the first packet to port 8080: pc1's SYN, after r1 rewrote it.

**Terminal 5 (pc2):**

```
tcpdump -ni eth0 -c1 'tcp dst port 8080'
```

Run the curl in **Terminal 1 (pc1)** once more.

**Expected** in Terminal 5 (pc2): the connection's first packet (SYN) shows `mss 1412`:

```
IP6 2001:db8:a:0:5054:ff:fea3:1.43210 > 2001:db8:b:0:5054:ff:fea3:2.8080: Flags [S], seq ..., win 64800, options [mss 1412,sackOK,TS val ... ecr 0,nop,wscale 7], length 0
```

1412 = tunnel MTU 1472 (with the GRE key) − 40 bytes IPv6 − 20 bytes TCP. Without the clamp it would say `mss 1440`. If you skipped S3, you see `mss 1416` (GRE without a key, MTU 1476) or `mss 1420` (6in4, MTU 1480).

**How to read this:** `Flags [S]` marks a SYN. The other options (`sackOK`, `TS`, `wscale`) are untouched. pc1 announced 1440 (1500 - 40 - 20), based on its own link; r1 lowered it.

### S5-4. Put it back

Deleting a table deletes its chains and rules.

**Terminal 2 (r1):**

```
nft delete table inet clamp
```

**Terminal 4 (r2):**

```
nft delete table inet lab
```

**Terminal 5 (pc2):**

```
ip -6 route flush cache
pkill -f http.server
```

:::info
MSS clamping only helps TCP. The real fix is to never block ICMPv6 Packet Too Big.
:::

## Stretch: check yourself

1. Why does IPv6 traceroute not show the IPv4 routers inside a tunnel?
2. Why can one GRE tunnel carry IPv4 and IPv6, but a 6in4 tunnel cannot?
3. Name two things a GRE key does not protect against.
4. What do you add when tunnel traffic must stay private across the internet?
5. Packet Too Big is blocked in a network you do not control. What can you do on your own tunnel router, and what does it not cover?

<details>
<summary>▶ Answers</summary>

1. Only the routers at the tunnel ends lower the IPv6 hop limit. The IPv4 routers in between lower the outer IPv4 TTL, which IPv6 never sees.
2. The GRE header has a protocol type field that names the inner packet (`0x86DD` IPv6, `0x0800` IPv4). 6in4 has no such field: protocol 41 always means IPv6.
3. Anyone on the path can read the traffic (no encryption), read the key itself, and send forged packets with the same key (no authentication).
4. IPsec (ESP encrypts), around or instead of the tunnel, for example GRE over IPsec.
5. MSS clamping: the router lowers the MSS in every TCP SYN so TCP packets fit the tunnel. It does not cover UDP or any other traffic without an MSS; the real fix is still to let Packet Too Big through.
</details>
