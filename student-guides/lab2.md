---
title: "IPv6 Day 2 Lab: Routing and Dual Stack"
tags: ipv6, labs
---

# IPv6 Day 2 Lab: Routing and Dual Stack

**Day 2 lab (Lab 2 in the `lab` menu).** Core parts A to J: about 190 minutes. Stretch exercises: about 65 minutes.

The core parts use only what today's lecture and Day 1 covered. Each stretch exercise names the part of today's lecture it builds on, and explains anything new before you start.

[TOC]

## What you will do

- Configure two IPv6 routers and a link between them.
- Give each LAN its own prefix with SLAAC.
- Add static routes so the two LANs can reach each other.
- Add IPv4 next to IPv6 (dual stack) and reach one web server over both.
- See how a dual-stack host picks a protocol, and how one protocol can hide a fault in the other.
- See Path MTU Discovery and the ICMPv6 Packet Too Big message.
- Build NAT64 and DNS64 so an IPv6-only host can reach an IPv4-only web server.

## Suggested timing

| Block | Minutes |
|---|---|
| Start-up: open the terminals, read **Your network** | 10 |
| Part A: Address the routers | 15 |
| Part B: SLAAC on LAN A | 15 |
| Part C: SLAAC on LAN B | 10 |
| Part D: Static routes | 25 |
| Part E: Dual stack | 25 |
| Break | 10 |
| Part F: Which protocol does a dual-stack host pick? | 15 |
| Part G: Two stacks, two routing tables | 15 |
| Part H: One web server, two protocols | 15 |
| Part I: Path MTU between routers | 15 |
| Break | 10 |
| Part J: NAT64 and DNS64 | 40 |
| Check your work, check yourself, wrap-up | 20 |
| **Total** | **240** |

If you finish early, go on to the stretch exercises.

:::info
This lab uses the same skills as Lab 1 (addresses, `radvd`, `ping -6`, `tcpdump`). If you need a reminder of the `lab` menu or how to open more terminals, see **Getting Started**.
:::

**How to use this guide.** Before each command, read what it does and what you should see. After each output, read **How to read this** and compare it with your screen. At **Predict first**, write down your answer *before* you run the command, then open the folded answer.

## Your network

```
 pc1 ---eth0 [r1] eth1========eth1 [r2] eth0--- pc2
   LAN A                 link                 LAN B
 2001:db8:a::/64   2001:db8:ff::/64     2001:db8:b::/64
 10.1.0.0/24       10.255.0.0/30        10.2.0.0/24
 (SLAAC from r1)                        (SLAAC from r2)
```

| Node | Interface | IPv6 | IPv4 | MAC |
|---|---|---|---|---|
| pc1 | eth0 | SLAAC | 10.1.0.10/24 | `52:54:00:a2:00:01` |
| r1 | eth0 (LAN A) | `2001:db8:a::1`/64 | 10.1.0.1/24 | `52:54:00:a2:00:fe` |
| r1 | eth1 (link) | `2001:db8:ff::1`/64 | 10.255.0.1/30 | `52:54:00:a2:ff:01` |
| r2 | eth1 (link) | `2001:db8:ff::2`/64 | 10.255.0.2/30 | `52:54:00:a2:ff:02` |
| r2 | eth0 (LAN B) | `2001:db8:b::1`/64 | 10.2.0.1/24 | `52:54:00:a2:0b:fe` |
| pc2 | eth0 | SLAAC | 10.2.0.10/24 | `52:54:00:a2:0b:02` |

**Nothing is configured yet.** Every node has only its link-local addresses.

Think of it as two offices (LAN A and LAN B), each with its own router, joined by one link between the routers. There are **three** IPv6 subnets: one per LAN and one for the router link. A packet from pc1 to pc2 must cross two routers.

## Before you start: open four terminals

Open one terminal per node and keep them open for the whole lab (**Window > New Terminal** for each new one):

| Terminal | Type | Prompt |
|---|---|---|
| Terminal 1 | `lab 2 pc1` | `[s01 pc1]#` |
| Terminal 2 | `lab 2 r1` | `[s01 r1]#` |
| Terminal 3 | `lab 2 r2` | `[s01 r2]#` |
| Terminal 4 | `lab 2 pc2` | `[s01 pc2]#` |

:::warning
Lab 2 has its own pc1, r1 and pc2. They are not the Lab 1 nodes. Check that the menu or shortcut said **lab 2**.
:::

---

## Part A: Address the routers

:::info
**Why this matters**

A router is a computer that passes packets from one interface to another. Two things make a node a router: **forwarding** must be on, and each interface needs an address in the subnet it is attached to. When you add an address with `/64`, the node also learns that the whole /64 is reachable directly through that interface (a **connected route**).

On a real network, a router with forwarding off or a wrong address is a silent problem: hosts send traffic to it, and it goes nowhere.
:::

### A1. Configure r1

`sysctl -w` changes a kernel setting. `net.ipv6.conf.all.forwarding=1` turns on IPv6 forwarding on all interfaces. Without it, r1 is a **host** and drops every packet that is not addressed to r1 itself (stretch S4-2 shows this).

The two `ip -6 addr add` commands give r1 one address per interface. `/64` tells r1 that all of `2001:db8:a::/64` is on eth0 and all of `2001:db8:ff::/64` is on eth1.

**Terminal 2 (r1):**

```
sysctl -w net.ipv6.conf.all.forwarding=1
ip -6 addr add 2001:db8:a::1/64 dev eth0
ip -6 addr add 2001:db8:ff::1/64 dev eth1
```

**Expected:** `net.ipv6.conf.all.forwarding = 1`, then no output from the two `ip` commands.

**How to read this:** `sysctl` prints the new value to confirm it. `ip` prints nothing when it succeeds; any message from it means a typing mistake.

Check. `scope global` hides the link-local addresses, so you see only the ones you added:

```
ip -6 addr show scope global
```

**Expected:** `2001:db8:a::1/64` on eth0 and `2001:db8:ff::1/64` on eth1.

**How to read this:** each address is listed under its interface. Check that the LAN A address is on **eth0** and the link address on **eth1**. If they were swapped, r1 would look for LAN A on the wrong cable.

**Explain why:** Why does the router itself need an address on LAN A?

<details>
<summary>▶ Answer</summary>

Adding `2001:db8:a::1/64` on eth0 creates the connected route for `2001:db8:a::/64`. Without it, r1 would not know where to deliver packets coming back to pc1. It also gives r1 an address to use when it sends messages to LAN A hosts, such as the error you will see in D1.
</details>

### A2. Configure r2

The mirror image on r2: forwarding on, LAN B address on eth0, link address on eth1. r2 uses `::2` on the link because r1 already has `::1`.

**Terminal 3 (r2):**

```
sysctl -w net.ipv6.conf.all.forwarding=1
ip -6 addr add 2001:db8:b::1/64 dev eth0
ip -6 addr add 2001:db8:ff::2/64 dev eth1
```

Check with `ip -6 addr show scope global`. **Expected:** `2001:db8:b::1/64` on eth0 and `2001:db8:ff::2/64` on eth1.

### A3. Ping across the router link

**Predict first:** You have added no routes. Will r1 reach r2's link address?

<details>
<summary>▶ Answer</summary>

Yes. `2001:db8:ff::2` is inside `2001:db8:ff::/64`, which r1 knows is connected to eth1. r1 finds r2's MAC with Neighbor Discovery, as in Lab 1, and sends the packet straight to it. Neighbors on the same link need no route.
</details>

`-c2` sends two pings and stops.

**Terminal 2 (r1):**

```
ping -6 -c2 2001:db8:ff::2
```

**Expected:** `2 packets transmitted, 2 received, 0% packet loss`.

**How to read this:** 2 received proves that both addresses are correct and on the same link, and that Neighbor Discovery works between the routers.

<details>
<summary>▶ It says "Network is unreachable" or 100% loss</summary>

Check the addresses on both routers with `ip -6 addr show dev eth1`. A typing mistake in `2001:db8:ff::1` or `::2` is the usual cause. Remove a wrong address with `ip -6 addr del WRONG-ADDRESS/64 dev eth1` and add the right one.
</details>

---

## Part B: SLAAC on LAN A

:::info
**Why this matters**

pc1 still has only a link-local address. With **SLAAC** (Day 1), the router announces the LAN's prefix in **Router Advertisements (RAs)**, and each host builds its own address and learns its default gateway. No one types addresses on hundreds of PCs.

If RAs stop on a real network, hosts lose their global address and default route when the lifetimes run out, and users lose IPv6 even though the cables are fine.
:::

### B1. Router Advertisements from r1

`radvd` sends Router Advertisements. The box writes its configuration file and then starts it:

- `interface eth0`: advertise only on eth0 (LAN A).
- `MinRtrAdvInterval 3` / `MaxRtrAdvInterval 10`: send an RA every 3 to 10 seconds (short, so you do not wait in class).
- `prefix 2001:db8:a::/64`: the prefix for LAN A.
- `AdvOnLink on`: "this prefix is on this link; talk to these addresses directly".
- `AdvAutonomous on`: "you may build your own address from this prefix" (SLAAC).

**Terminal 2 (r1):** paste this whole box (it is the same file as in Lab 1):

```
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

**Expected:** no output. Check with `pgrep -a radvd`.

**How to read this:** `pgrep -a radvd` prints radvd's process ID and command line. If it prints nothing, radvd did not start: look for a typing mistake in the file, such as a missing `;`.

:::info
radvd sends advertisements only on `eth0` (LAN A), because the file names only `eth0`. The router link `eth1` gets no advertisements: routers configure their own addresses.
:::

### B2. Check pc1

**Predict first:** pc1's MAC is 52:54:00:a2:00:01. Which global address will it build?

<details>
<summary>▶ Answer</summary>

`2001:db8:a:0:5054:ff:fea2:1`: the prefix from the RA, plus the EUI-64 interface ID from the MAC (insert `ff:fe` in the middle, flip the 7th bit so `52` becomes `50`), as in Lab 1.
</details>

The first command shows pc1's addresses, the second its IPv6 routing table.

**Terminal 1 (pc1)**, after about 10 seconds:

```
ip -6 addr show dev eth0
ip -6 route
```

**Expected:**

```
    inet6 2001:db8:a:0:5054:ff:fea2:1/64 scope global dynamic mngtmpaddr
    inet6 fe80::5054:ff:fea2:1/64 scope link
```

**How to read this:** `scope global` is the new SLAAC address, `scope link` the link-local one. `dynamic` means the address came from an RA and has a lifetime: it expires if the RAs stop.

and in the routing table:

```
default via fe80::5054:ff:fea2:fe dev eth0 proto ra metric 1024 expires 28sec hoplimit 64 pref medium
```

`fe80::5054:ff:fea2:fe` is r1's link-local address on eth0.

**How to read this:**

| Field | Meaning |
|---|---|
| `default` | Used for any destination that no other route matches. |
| `via fe80::...:fe` | The **next hop**: the router to send the packet to (r1). |
| `dev eth0` | The interface to send it out of. |
| `proto ra` | Learned from a Router Advertisement. |
| `metric 1024` | Cost; when two routes match equally, the lower metric wins. |
| `expires 28sec` | Removed unless a new RA arrives; each RA resets the timer. |

You also see `2001:db8:a::/64 dev eth0` with no `via`: the on-link route from `AdvOnLink`. pc1 sends packets for LAN A addresses directly, not through r1.

**Explain why:** Why is the gateway r1's link-local address and not 2001:db8:a::1?

<details>
<summary>▶ Answer</summary>

RAs are always sent from the router's link-local address, and pc1 uses that source as its gateway. A next hop only has to be reachable on the link, so link-local is enough. It also never changes, even if the global prefix is renumbered.
</details>

---

## Part C: SLAAC on LAN B

:::info
**Why this matters**

LAN B is a different subnet, so it needs its own router (r2) advertising its own /64. Each LAN must have a different prefix: that is how routers tell which side of the network an address is on.
:::

### C1. Router Advertisements from r2

Only the prefix line differs from r1's file.

**Terminal 3 (r2):** the same file, with LAN B's prefix:

```
cat > /etc/radvd.conf <<'EOF'
interface eth0 {
    AdvSendAdvert on;
    MinRtrAdvInterval 3;
    MaxRtrAdvInterval 10;
    prefix 2001:db8:b::/64 {
        AdvOnLink on;
        AdvAutonomous on;
    };
};
EOF
radvd
```

### C2. Check pc2

**Predict first:** Pc2's MAC is 52:54:00:a2:0b:02, r2's eth0 MAC is 52:54:00:a2:0b:fe. What address and default gateway will pc2 get?

<details>
<summary>▶ Answer</summary>

Address `2001:db8:b:0:5054:ff:fea2:b02`; default gateway `fe80::5054:ff:fea2:bfe`, r2's link-local address, the source of the RAs.
</details>

**Terminal 4 (pc2)**, after about 10 seconds:

```
ip -6 addr show dev eth0
ip -6 route
```

**Expected:** the address `2001:db8:b:0:5054:ff:fea2:b02/64` and `default via fe80::5054:ff:fea2:bfe` (r2).

**How to read this:** the address has LAN B's prefix, and everything pc2 sends off its LAN goes to r2 first.

:::success
From here on, **PC2-ADDRESS** means `2001:db8:b:0:5054:ff:fea2:b02`. The commands below already have it filled in.
:::

---

## Part D: Static routes

:::info
**Why this matters**

**A router only knows the networks it is directly attached to.** r1 has never heard of LAN B, and r2 has never heard of LAN A. A **static route** is a line you add to a router's table: "to reach this prefix, send the packet to that next-hop router".

On a real network, a missing route means one office cannot reach the other, even though every cable and PC is fine.
:::

### D1. Try to reach pc2

**Predict first:** pc1 has a default route and both routers are up. Will the ping reach pc2?

<details>
<summary>▶ Answer</summary>

No. pc1 hands the packet to r1, but r1 does not know where LAN B is.
</details>

**Terminal 1 (pc1):**

```
ping -6 -c2 2001:db8:b:0:5054:ff:fea2:b02
```

**Expected:** it fails:

```
From 2001:db8:a::1 icmp_seq=1 Destination unreachable: No route
```

**How to read this:** `From 2001:db8:a::1` is **who sent this message**: r1, not pc2. `Destination unreachable: No route` is the ICMPv6 error a router sends when nothing in its routing table matches. It comes back at once: a router is saying "I don't know where that is", which is different from a packet that is simply lost.

Why does it fail, and who sent the error?

<details>
<summary>▶ Answer</summary>

pc1 sends the packet to its default gateway, r1 (`2001:db8:a::1` is r1). r1 only knows the networks it is directly attached to (`2001:db8:a::/64` and `2001:db8:ff::/64`). It has no route to `2001:db8:b::/64` and no default route, so it drops the packet and sends ICMPv6 **Destination Unreachable: No route** back to pc1.
</details>

You can see r1's table. **Terminal 2 (r1):**

```
ip -6 route
```

**Expected:** routes for `2001:db8:a::/64`, `2001:db8:ff::/64` and `fe80::/64`, and nothing for `2001:db8:b::/64`.

**How to read this:** these routes have `dev` but **no `via`**, which means "directly connected: deliver straight to the destination". `proto kernel` means Linux added them itself when you added the addresses. There is no `default` line: routers do not take a default route from RAs.

### D2. Add a route on each router

`ip -6 route add PREFIX via NEXT-HOP` adds a static route. The next hop must be directly reachable on one of the router's links. Linux works out by itself that `2001:db8:ff::2` is on eth1.

**Terminal 2 (r1):** "LAN B is behind r2":

```
ip -6 route add 2001:db8:b::/64 via 2001:db8:ff::2
```

**Predict first:** With only this route on r1, would pc1's ping to pc2 work?

<details>
<summary>▶ Answer</summary>

No. The request now reaches pc2, but the reply goes to r2, and r2 does not know where LAN A is. See the folded question at the end of D3.
</details>

The second route is the way back: LAN A is behind r1.

**Terminal 3 (r2):** "LAN A is behind r1":

```
ip -6 route add 2001:db8:a::/64 via 2001:db8:ff::1
```

**Expected:** no output from either. Check with `ip -6 route` on each router: r1 now has `2001:db8:b::/64 via 2001:db8:ff::2 dev eth1`.

**How to read this:** unlike the connected routes, this one **has a `via`**: packets for LAN B go to the next-hop router r2, out of `eth1`. It shows no `proto kernel` because you added it by hand, and it gets metric 1024, the default for routes you add.

### D3. Ping and trace

`traceroute` shows **which routers** a packet passes. It sends packets with hop limit 1, then 2, then 3. Each router lowers the hop limit by one; the router where it reaches zero drops the packet and sends back ICMPv6 **Time Exceeded**, which reveals its address. `-n` shows addresses without looking up names.

**Terminal 1 (pc1):**

```
ping -6 -c2 2001:db8:b:0:5054:ff:fea2:b02
traceroute -6 -n 2001:db8:b:0:5054:ff:fea2:b02
```

**Expected:** `0% packet loss`, and the trace shows three hops:

```
traceroute to 2001:db8:b:0:5054:ff:fea2:b02 (2001:db8:b:0:5054:ff:fea2:b02), 30 hops max, 80 byte packets
 1  2001:db8:a::1  0.105 ms  0.031 ms  0.027 ms
 2  2001:db8:ff::2  0.070 ms  0.040 ms  0.038 ms
 3  2001:db8:b:0:5054:ff:fea2:b02  0.081 ms  0.048 ms  0.046 ms
```

Hop 1 is r1, hop 2 is r2 (its address on the router link), hop 3 is pc2.

**How to read this:** one line per hop: the address that answered, then three round-trip times (three tries). Hops 1 and 2 sent Time Exceeded. Hop 3 is the destination, so the trace ends. A router answers from the address it uses toward pc1, normally the interface facing pc1, which is why r2 shows `2001:db8:ff::2`.

<details>
<summary>▶ Ping works one way but I added only one route. Why must both routers have one?</summary>

The echo request needs r1's route to reach LAN B. The echo reply comes back from pc2 to pc1 and needs r2's route to reach LAN A. Without it, pc2 gets the request but the reply is dropped at r2. Every path needs a route in both directions.
</details>

**Explain why:** Pc1 and pc2 needed no new routes. Why only the routers?

<details>
<summary>▶ Answer</summary>

The PCs send everything off their own LAN to their default gateway, so they never need to know where the other LAN is. Only the routers choose the next step, so only they need the routes.
</details>

---

## Part E: Dual stack

Now add IPv4 next to IPv6 on the same links. Both protocols run at the same time.

:::info
**Why this matters**

Most networks today are **dual stack**: hosts have IPv4 and IPv6 addresses, and applications can use either. It lets a network add IPv6 without stopping anything that works on IPv4.

The key idea: IPv4 and IPv6 are **separate protocols** sharing the same cables. Each needs its own addresses, routes and forwarding switch. When a name has both kinds of address, the host must choose which to try first, so "it works for me but not for you" can depend on which protocol was used.
:::

### E1. Add IPv4 everywhere

On each router you repeat Parts A and D for IPv4: turn on `net.ipv4.ip_forward`, add one address per interface, add one route to the far LAN. `ip` without `-6` works out the protocol from the address. `;` runs two commands on one line.

**Predict first:** Does any of the IPv6 setup help IPv4?

<details>
<summary>▶ Answer</summary>

No. IPv6 forwarding, addresses and routes are used only by IPv6. IPv4 starts from nothing.
</details>

**Terminal 2 (r1):**

```
sysctl -w net.ipv4.ip_forward=1
ip addr add 10.1.0.1/24 dev eth0; ip addr add 10.255.0.1/30 dev eth1
ip route add 10.2.0.0/24 via 10.255.0.2
```

**Terminal 3 (r2):**

```
sysctl -w net.ipv4.ip_forward=1
ip addr add 10.2.0.1/24 dev eth0; ip addr add 10.255.0.2/30 dev eth1
ip route add 10.1.0.0/24 via 10.255.0.1
```

IPv4 has no Router Advertisements, so the PCs also need their IPv4 default gateway typed by hand. Without it they could reach only their own LAN.

**Terminal 1 (pc1):**

```
ip addr add 10.1.0.10/24 dev eth0; ip route add default via 10.1.0.1
```

**Terminal 4 (pc2):**

```
ip addr add 10.2.0.10/24 dev eth0; ip route add default via 10.2.0.1
```

Test IPv4 end to end (`ping` uses IPv4 because you give it an IPv4 address). **Terminal 1 (pc1):**

```
ping -c2 10.2.0.10
```

**Expected:** `0% packet loss`.

**How to read this:** the request used pc1's default route and r1's route; the reply used pc2's default route and r2's route. Every line you just typed was needed.

:::info
IPv4 needed its own forwarding switch (`net.ipv4.ip_forward`), its own addresses, its own routes and its own default gateways. IPv4 and IPv6 share the cables, but nothing else.
:::

### E2. Start a web server on pc2

You need a real application to see dual stack at work. The first line makes a small web page. The second starts Python's web server on port 8080: `--bind ::` sets the listening address (`::` is the IPv6 "any address"), `> /tmp/web.log 2>&1` sends its messages to a log file, and `&` runs it in the background.

**Terminal 4 (pc2):**

```
cd /tmp && echo "Hello from pc2" > index.html
python3 -m http.server 8080 --bind :: > /tmp/web.log 2>&1 &
```

**Expected:** a line like `[1] 123` (the job number and process ID). The server runs in the background and writes its log to `/tmp/web.log`.

Check that it listens. `ss -ltn` lists **l**istening **T**CP sockets with **n**umbers instead of names:

```
ss -ltn | grep 8080
```

**Expected:**

```
LISTEN 0      5                  *:8080            *:*
```

**How to read this:** `LISTEN` means waiting for connections (the `0` and `5` are queue sizes; ignore them). `*:8080` means port 8080 on **every** address, IPv6 and IPv4. An IPv4-only socket shows `0.0.0.0:8080` instead (you will see one in H3).

`--bind ::` means "listen on every IPv6 address". As you will see, it accepts IPv4 too.

:::warning
If `ss` shows nothing, wait three seconds and try again; the server can take a moment to start.
:::

### E3. Fetch the page over IPv4 and over IPv6

`curl` fetches a web page. `-4` forces IPv4 and `-6` forces IPv6, so each line tests one protocol alone. Testing each protocol separately is the first step in any dual-stack troubleshooting.

**Terminal 1 (pc1):**

```
curl -4 http://10.2.0.10:8080/
curl -6 "http://[2001:db8:b:0:5054:ff:fea2:b02]:8080/"
```

**Expected:** `Hello from pc2` twice.

**How to read this:** the same server answered over both protocols, each using its own routes.

:::info
An IPv6 address in a URL goes inside **square brackets**, because the colons in the address would otherwise be read as the start of the port number.
:::

### E4. One name, two addresses

People use names. When a name has an IPv4 and an IPv6 address, the host must choose which to try first. `/etc/hosts` is the local list of names and addresses. `cat >>` **adds** lines to its end; a single `>` would replace the whole file.

Give pc2 a name on pc1, with both addresses. **Terminal 1 (pc1):**

```
cat >> /etc/hosts <<'EOF'
10.2.0.10                       pc2
2001:db8:b:0:5054:ff:fea2:b02   pc2
EOF
```

Check (`tail -2` shows the last two lines). Note that the IPv4 line comes first in the file:

```
tail -2 /etc/hosts
```

Now fetch the page by name, with details (`-v` prints each step, including the address curl tries):

```
curl -v http://pc2:8080/
```

**Expected** (near the top):

```
*   Trying [2001:db8:b:0:5054:ff:fea2:b02]:8080...
* Connected to pc2 (2001:db8:b:0:5054:ff:fea2:b02) port 8080
```

and at the end `Hello from pc2`.

**How to read this:** `Trying` is the first address curl attempted (brackets mean IPv6). `Connected to pc2 (...)` is the address that worked. Both are IPv6, although IPv4 is first in `/etc/hosts`, so the file order did not decide.

Which protocol did curl try first?

<details>
<summary>▶ Answer</summary>

IPv6. When a name has both an IPv6 and an IPv4 address, the default address selection rules (RFC 6724) put IPv6 first. The application tries IPv6, and falls back to IPv4 only if IPv6 fails.
</details>

---

## Part F: Which protocol does a dual-stack host pick?

*Today's lecture:* Module 4, "How Dual-Stack Works": when DNS returns both A and AAAA records, the OS preference rules decide (RFC 6724, usually IPv6 first).

:::info
**Why this matters**

When an application asks for a name's addresses, the system returns a **sorted list**, and the application tries them in that order. The order follows the **default address selection rules (RFC 6724)**. On Linux, `/etc/gai.conf` can change it.

On a real network this order decides which protocol users actually use. Changing it is also a common way to hide an IPv6 problem instead of fixing it.
:::

You added `pc2` to pc1's `/etc/hosts` with both addresses in E4.

### F1. The default order

`getent ahosts pc2` looks up pc2 exactly as an application does and prints the addresses in the order the application gets them. In the curl line, `-s` hides the progress bar, `-v` shows details, `-m3` gives up after 3 seconds, and `2>&1 | grep Trying` keeps only the `Trying` line (curl writes its details to the error stream, so `2>&1` is needed).

**Terminal 1 (pc1):**

```
getent ahosts pc2
curl -sv -m3 http://pc2:8080/ 2>&1 | grep Trying
```

**Expected:** `getent` lists the IPv6 address first:

```
2001:db8:b:0:5054:ff:fea2:b02 STREAM pc2
2001:db8:b:0:5054:ff:fea2:b02 DGRAM
2001:db8:b:0:5054:ff:fea2:b02 RAW
10.2.0.10       STREAM
10.2.0.10       DGRAM
10.2.0.10       RAW
```

and curl prints `*   Trying [2001:db8:b:0:5054:ff:fea2:b02]:8080...`. By default (RFC 6724) hosts prefer IPv6.

**How to read this:** each address appears three times, once per socket type (`STREAM` = TCP, `DGRAM` = UDP, `RAW`); ignore the repeats. What matters is the **order**: IPv6 on top, and curl's `Trying` line agrees.

### F2. Prefer IPv4 instead

A `precedence` line gives a group of addresses a priority; higher is tried first. In the default RFC 6724 table, IPv6 addresses get 40 and IPv4 addresses 35.

**Predict first:** After giving IPv4 precedence 100, which address comes first?

<details>
<summary>▶ Answer</summary>

`10.2.0.10`. 100 beats IPv6's precedence, so IPv4 sorts to the top and curl tries it first.
</details>

**Terminal 1 (pc1):**

```
echo 'precedence ::ffff:0:0/96 100' > /etc/gai.conf
getent ahosts pc2
curl -sv -m3 http://pc2:8080/ 2>&1 | grep Trying
```

**Expected:** `10.2.0.10` is now first, and curl prints `*   Trying 10.2.0.10:8080...`.

`::ffff:0:0/96` is how the address selection table writes "all IPv4 addresses". Giving it precedence 100 puts IPv4 above IPv6. This is the setting people change when "IPv6 is slow", instead of fixing the IPv6 problem.

**How to read this:** the network, routes and `/etc/hosts` did not change. Only pc1's sorting rule changed, and the application followed it.

### F3. Remove it

Without `/etc/gai.conf`, the built-in RFC 6724 order applies again. Part G needs the default order.

**Terminal 1 (pc1):**

```
rm /etc/gai.conf
```

---

## Part G: Two stacks, two routing tables

*Today's lecture:* Module 4, "How Dual-Stack Works": separate IPv4 and IPv6 routing tables, and Happy Eyeballs (try IPv6 first, fall back to IPv4 quickly). Also "Dual-Stack Pros & Cons": the two stacks can drift apart.

:::info
**Why this matters**

Here you break one protocol, keep the other, and watch an application. Modern applications try IPv6 first and quickly **fall back** to IPv4 if it fails ("happy eyeballs"). Good for users, bad for network staff: a broken IPv6 network can look healthy, because every page still loads over IPv4. On a real network, such a fault can stay hidden for months.
:::

### G1. Compare the tables

**Terminal 2 (r1):**

```
ip route
ip -6 route
```

Two separate tables: IPv4 routes in one, IPv6 routes in the other.

**How to read this:** both have the same shape: connected routes (no `via`) and one static route toward LAN B (`10.2.0.0/24 via 10.255.0.2` and `2001:db8:b::/64 via 2001:db8:ff::2`).

### G2. Break only IPv6

**Terminal 2 (r1):**

```
ip -6 route del 2001:db8:b::/64
```

Now test each protocol, then the name. `-W2` makes ping wait at most 2 seconds; `-m5` limits curl to 5 seconds; `grep -E 'Trying|Connected|Hello'` keeps the tried addresses, the one that worked, and the page.

**Predict first:** Will the curl by name still print "Hello from pc2"?

<details>
<summary>▶ Answer</summary>

Yes. curl tries IPv6 first, r1 answers No route at once, and curl moves on to the IPv4 address, which works.
</details>

**Terminal 1 (pc1):**

```
ping -6 -c1 -W2 2001:db8:b:0:5054:ff:fea2:b02
ping -c1 -W2 10.2.0.10
curl -sv -m5 http://pc2:8080/ 2>&1 | grep -E 'Trying|Connected|Hello'
```

**Expected:** the IPv6 ping fails (`Destination unreachable: No route`), the IPv4 ping works, and curl prints:

```
*   Trying [2001:db8:b:0:5054:ff:fea2:b02]:8080...
*   Trying 10.2.0.10:8080...
* Connected to pc2 (10.2.0.10) port 8080
Hello from pc2
```

curl tried IPv6, it failed, and curl quietly used IPv4. A user would notice nothing. That is why an IPv6 fault on a dual-stack network can go unseen for a long time.

**How to read this:** **two** `Trying` lines: IPv6 first, then IPv4. `Connected to pc2 (10.2.0.10)` shows only IPv4 worked. Without `-v`, you would never know IPv6 failed.

**Explain why:** The fallback was instant here. When would users feel a delay?

<details>
<summary>▶ Answer</summary>

Here r1 returned "No route" at once. If IPv6 packets were lost silently instead, the client would have to wait before giving up on IPv6. curl waits only 200 milliseconds before it also tries IPv4; older applications may wait many seconds. That is what users call "IPv6 makes things slow".
</details>

### G3. Swap the fault

The first command restores the IPv6 route; the second removes the IPv4 route to LAN B.

**Terminal 2 (r1):** put the IPv6 route back and remove the IPv4 one:

```
ip -6 route add 2001:db8:b::/64 via 2001:db8:ff::2
ip route del 10.2.0.0/24
```

**Predict first:** Which protocol will curl use, and will it be slower?

<details>
<summary>▶ Answer</summary>

IPv6, with no delay. IPv6 is tried first and works, so curl never needs IPv4.
</details>

Run the same three commands in **Terminal 1 (pc1)** again.

**Expected:** now only IPv4 fails, and curl connects over IPv6 straight away (`Connected to pc2 (2001:db8:b:0:5054:ff:fea2:b02)`).

**How to read this:** only **one** `Trying` line now. A fault in either protocol can hide behind the other, so you must test each one on its own (`ping -6` and `ping`, `curl -6` and `curl -4`).

### G4. Put it back

**Terminal 2 (r1):**

```
ip route add 10.2.0.0/24 via 10.255.0.2
```

---

## Part H: One web server, two protocols

*Today's lecture:* Module 4, "Dual-Stack Architecture": applications can use either protocol stack, so each service must listen on both.

:::info
**Why this matters**

A dual-stack network is not enough: each **application** must also listen on both protocols. Here you see how one IPv6 socket serves IPv4 clients, and what happens when a server listens on IPv4 only. That is a common surprise when IPv6 is turned on: IPv6 users get "connection refused", and IPv6-only clients cannot use the service at all.
:::

### H1. Restart the server with a fresh log

`pkill -f http.server` stops the server (`-f` matches the whole command line). It then starts again as in E2, with an empty log, and `ss` confirms it listens.

**Terminal 4 (pc2):**

```
pkill -f http.server
cd /tmp && python3 -m http.server 8080 --bind :: > /tmp/web.log 2>&1 &
sleep 2; ss -ltn | grep 8080
```

**Expected:** `*:8080`. One IPv6 socket that accepts both protocols.

### H2. One request over each protocol

`-g` makes curl treat the square brackets as part of the IPv6 address, not as a curl pattern.

**Terminal 1 (pc1):**

```
curl -s -m5 http://10.2.0.10:8080/
curl -s -m5 -g "http://[2001:db8:b:0:5054:ff:fea2:b02]:8080/"
```

The server log has one line per request, starting with the client address.

**Terminal 4 (pc2):**

```
cat /tmp/web.log
```

**Predict first:** How can an IPv6 socket show an IPv4 client (10.1.0.10)?

<details>
<summary>▶ Answer</summary>

As an IPv6 address that contains the IPv4 address: `::ffff:10.1.0.10`.
</details>

**Expected:** two requests:

```
::ffff:10.1.0.10 - - [23/Nov/2026 13:05:12] "GET / HTTP/1.1" 200 -
2001:db8:a:0:5054:ff:fea2:1 - - [23/Nov/2026 13:05:13] "GET / HTTP/1.1" 200 -
```

The IPv4 client shows up as an **IPv4-mapped IPv6 address**: `::ffff:` plus the IPv4 address. That is how one IPv6 socket serves IPv4 clients too (the setting `net.ipv6.bindv6only` is 0). It is the same idea as the `64:ff9b::` addresses in Part J: an IPv4 address carried in the last 32 bits of an IPv6 address.

**How to read this:** the first field is the client. Line 2 is pc1's SLAAC address, so that request came over IPv6. `200` means success. Your times will differ.

### H3. Restart it on IPv4 only

`--bind 0.0.0.0` is the IPv4 "any address": the server now listens on IPv4 only, like a server set up before anyone thought about IPv6.

**Terminal 4 (pc2):**

```
pkill -f http.server
python3 -m http.server 8080 --bind 0.0.0.0 > /tmp/web.log 2>&1 &
sleep 2; ss -ltn | grep 8080
```

**Expected:** `0.0.0.0:8080`.

**How to read this:** port 8080 on IPv4 addresses only. Nothing listens for IPv6 on port 8080 now.

**Predict first:** The network has not changed. Will the IPv6 request still work?

<details>
<summary>▶ Answer</summary>

No. The packets still reach pc2, but no program listens for IPv6 on port 8080, so pc2 refuses the connection.
</details>

Repeat both curls in **Terminal 1 (pc1)**. **Expected:** the IPv4 request works, and the IPv6 one prints nothing. To see why, run it with `-v`:

```
curl -sv -m5 -g "http://[2001:db8:b:0:5054:ff:fea2:b02]:8080/" 2>&1 | tail -2
```

**Expected:** `Failed to connect ... Couldn't connect to server` (pc2 refused the connection). The network is dual stack, but this application is not.

**How to read this:** there is no "No route" from a router, and the answer is immediate: pc2 itself said "nobody listens on that port". When the network is fine but one protocol fails, check how the application listens with `ss -ltn`.

### H4. Put it back

Listen on `::` again so the server serves both protocols.

**Terminal 4 (pc2):**

```
pkill -f http.server
python3 -m http.server 8080 --bind :: > /tmp/web.log 2>&1 &
```

---

## Part I: Path MTU between routers

*Today's lecture:* Module 5, "Tunneling Considerations": MTU issues, Path MTU Discovery (PMTUD) and ICMPv6 Packet Too Big. Day 1 covered why IPv6 routers never fragment. Here a smaller router link stands in for a tunnel, whose extra headers make the MTU smaller.

:::info
**Why this matters**

The **MTU** is the largest packet a link can carry (1500 bytes on Ethernet). **IPv6 routers never fragment.** When a packet is too big for the next link, the router drops it and sends ICMPv6 **Packet Too Big**, with the right MTU, back to the sender. The sender then sends smaller packets. This is **Path MTU Discovery**.

On a real network, if Packet Too Big messages never reach the sender, small things work but large transfers hang: web pages load half way and stop.
:::

### I1. Make the router link smaller

`ip link set eth1 mtu 1400` sets eth1's MTU to 1400 bytes. Do it on **both** routers: both ends of a link must agree, or packets in one direction can be dropped with no error.

A WAN or VPN link often has a smaller MTU than Ethernet. Run this in **Terminal 2 (r1)** and in **Terminal 3 (r2)**:

```
ip link set eth1 mtu 1400
```

Check with `ip link show eth1`. **Expected:** `mtu 1400`.

**How to read this:** the LANs still have MTU 1500, so the router link is now the smallest link on the path.

### I2. Send a full-size packet that must not be fragmented

**Predict first:** pc1 sends a 1500-byte packet. Who notices it is too big, and what does pc1 receive?

<details>
<summary>▶ Answer</summary>

The packet fits on LAN A, so it leaves pc1. r1 cannot send it out of eth1 (1400 bytes), so r1 drops it and sends Packet Too Big with `mtu=1400` back to pc1.
</details>

**Terminal 1 (pc1):**

```
ping -6 -c2 -M do -s 1452 2001:db8:b:0:5054:ff:fea2:b02
```

`-s 1452` is 1452 bytes of data. With 8 bytes of ICMPv6 header and 40 bytes of IPv6 header the packet is exactly 1500 bytes. `-M do` forbids fragmenting it.

**Expected:**

```
From 2001:db8:a::1 icmp_seq=1 Packet too big: mtu=1400
ping: local error: message too long, mtu: 1400
```

r1 could not forward the 1500-byte packet onto the 1400-byte link. IPv6 routers never fragment, so r1 dropped it and sent ICMPv6 **Packet Too Big** back to pc1. pc1 remembered the smaller size, so the second ping fails before it even leaves pc1.

**How to read this:** line 1 comes **from r1** and carries the next link's MTU. Line 2, `local error`, is pc1 itself refusing to send: it now applies the learned path MTU to every packet to pc2. A normal application would simply send smaller packets.

**Explain why:** Why does IPv6 make the sender, not the router, deal with packet size?

<details>
<summary>▶ Answer</summary>

Fragmenting costs routers time and memory, and losing one piece loses the whole packet. In IPv6 a router only drops the packet and sends one small message; the sender learns the size once and then sends packets that fit the whole path.
</details>

### I3. Measure the whole path

`tracepath` works like traceroute, but also reports the MTU it discovers along the path.

**Terminal 1 (pc1):**

```
tracepath -6 -n 2001:db8:b:0:5054:ff:fea2:b02
```

**Expected:** the last line says:

```
     Resume: pmtu 1400 hops 3 back 3
```

**How to read this:** `pmtu 1400` is the path MTU, the smallest MTU on the path (the router link). `hops 3` is the distance to pc2, and `back 3` the hops the replies took back.

### I4. Put it back

In **Terminal 2 (r1)** and **Terminal 3 (r2)**:

```
ip link set eth1 mtu 1500
```

pc1 still remembers "1400 to pc2" and would forget it only after some minutes. This makes it forget now, so it uses full-size packets again.

**Terminal 1 (pc1):** forget the learned MTU:

```
ip -6 route flush cache
```

---

## Part J: NAT64 and DNS64

*Today's lecture:* Module 6, "NAT64/DNS64 Refresher" and "Translation Considerations". Day 1 introduced the idea in "Translation Example: NAT64 & DNS64 Concept" and "How does 64:ff9b::/96 work?".

:::info
**Why this matters**

New networks are often built **IPv6-only**: no IPv4 addresses to plan or run out of. But many servers are still **IPv4-only**, and an IPv6-only host cannot send a packet to an IPv4 address. NAT64 and DNS64 solve this with three jobs:

1. **DNS64**: when a name has only an IPv4 (A) record, the resolver makes up an IPv6 (AAAA) record: `64:ff9b::` plus the IPv4 address.
2. **Routing**: the network sends `64:ff9b::/96` to the NAT64 gateway.
3. **NAT64**: the gateway translates the IPv6 packet into an IPv4 packet, and translates the replies back.

In AWS, these are the DNS64 setting on a subnet, a route to the NAT gateway, and the NAT gateway itself. Here you build each job yourself, so you can watch each one work.
:::

The plan:

```
 pc1 (IPv6 only) ---- r1 ---- r2 (DNS64 + NAT64) ---- pc2 (IPv4-only web and DNS)
                                IPv6 in  |  IPv4 out
```

| Role | Node | Program |
|---|---|---|
| IPv6-only client | pc1 | (you remove its IPv4 address in J8) |
| IPv4-only web server | pc2 | Python web server, listening on IPv4 only |
| IPv4-only DNS server for the name `web.lab` | pc2 | `dnsmasq`, with only an A record |
| NAT64 gateway | r2 | `tayga` |
| DNS64 resolver | r2 | `unbound` |

### J1. Give pc2 a public IPv4 address

:::info
**Why a second IPv4 address?** The well-known prefix `64:ff9b::/96` is meant only for **public** IPv4 addresses. The NAT64 program in this lab, tayga, follows this rule strictly: it drops traffic between IPv6 hosts and private IPv4 addresses such as `10.2.0.10` behind this prefix. (It treats the documentation ranges, such as the lecture's example `198.51.100.10`, the same way.) The rule stops IPv6 clients from using a NAT64 gateway to reach private IPv4 networks behind it.

So pc2 gets a second IPv4 address, `100.64.0.10`, which tayga treats as public. The range `100.64.0.0/10` is set aside for Internet providers' own use, and no public server uses it, so it is safe in a lab. r2 gets `100.64.0.1` on the same LAN so it can reach pc2 there.
:::

`ip addr add` adds a second address; the first one (`10.2.0.10`, `10.2.0.1`) stays.

**Terminal 3 (r2):**

```
ip addr add 100.64.0.1/24 dev eth0
```

**Terminal 4 (pc2):**

```
ip addr add 100.64.0.10/24 dev eth0
```

Test from **Terminal 3 (r2)**:

```
ping -c2 100.64.0.10
```

**Expected:** `0% packet loss`.

**How to read this:** LAN B now carries two IPv4 subnets, `10.2.0.0/24` and `100.64.0.0/24`. pc2's IPv4 default route (via `10.2.0.1`, from E1) does not change.

### J2. Make pc2 an IPv4-only server

The first two lines restart the web server on IPv4 only, as in H3. The last command starts a small DNS server that knows one name, `web.lab`, with one IPv4 address. Its options:

- `-u root`: run as root (as in Lab 3).
- `--no-resolv --no-hosts`: use no other DNS server and not `/etc/hosts`; answer only from this command line.
- `--listen-address=100.64.0.10 --bind-interfaces`: listen on pc2's public IPv4 address only.
- `--address=/web.lab/100.64.0.10`: the A record. There is no IPv6 address for `web.lab`.
- `--local-ttl=60`: answers may be kept for 60 seconds.
- `--log-queries --log-facility=/tmp/dns.log`: write every question to a log file.

`\` continues the command on the next line.

**Terminal 4 (pc2):**

```
pkill -f http.server
cd /tmp && python3 -m http.server 8080 --bind 0.0.0.0 > /tmp/web.log 2>&1 &
dnsmasq -u root --no-resolv --no-hosts --listen-address=100.64.0.10 --bind-interfaces \
  --address=/web.lab/100.64.0.10 --local-ttl=60 --log-queries --log-facility=/tmp/dns.log
```

Check after two seconds:

```
ss -ltn
```

**Expected:** among the lines, `0.0.0.0:8080` (the web server) and `100.64.0.10:53` (the DNS server).

**How to read this:** both addresses are IPv4. Nothing on pc2 listens on IPv6 for these services. pc2 is now like a server on an IPv4-only site.

### J3. Ask pc2's DNS server

`dig` asks a DNS server a question and prints the answer. `@100.64.0.10` chooses the server, `+short` prints only the answer, and `A` or `AAAA` is the record type (IPv4 or IPv6 address).

r2 is on LAN B, so it can reach pc2 over IPv4. **Terminal 3 (r2):**

```
dig @100.64.0.10 +short A web.lab
dig @100.64.0.10 +short AAAA web.lab
```

**Expected:** `100.64.0.10` for the first line, and **nothing** for the second.

Empty output can mean "no IPv6 address" or "something failed". The status line tells you which:

```
dig @100.64.0.10 AAAA web.lab | grep status
```

**Expected:** a line with `status: NOERROR`.

**How to read this:** `NOERROR` with an empty answer means "the name exists, but it has no AAAA record". This is exactly the case on the lecture slide: "if only an A record exists". DNS64 acts only in this case.

### J4. Predict the made-up address

**Predict first:** DNS64 will put `100.64.0.10` into the last 32 bits of `64:ff9b::/96`. Write the result in IPv6 hex notation.

<details>
<summary>▶ Answer</summary>

Convert each of the four IPv4 numbers (decimal) to two hex digits: 100 = `64`, 64 = `40`, 0 = `00`, 10 = `0a`. That gives `6440:000a`. Drop the leading zeros in each group: `6440:a`. The full address is `64:ff9b::6440:a`.

Careful: the decimal 100 becomes hex `64`, and the decimal 64 becomes hex `40`. You can also write the address with the IPv4 part in dots, as the lecture slide did (`64:ff9b::198.51.100.10`): `64:ff9b::100.64.0.10` is the same address.
</details>

### J5. Start the NAT64 gateway on r2

`tayga` is a small NAT64 program. It uses a **virtual interface** called `nat64`: r2's kernel routes packets into `nat64`, tayga reads them, rewrites the header from IPv6 to IPv4 (or back), and gives the new packet back to the kernel, which routes it on.

Its configuration file, line by line:

| Line | Meaning |
|---|---|
| `tun-device nat64` | The name of the virtual interface. |
| `ipv4-addr 192.168.255.1` | tayga's own IPv4 address (used when tayga itself sends an error message). |
| `ipv6-addr 2001:db8:b:64::1` | tayga's own IPv6 address, for the same reason. |
| `prefix 64:ff9b::/96` | The NAT64 prefix: the well-known prefix from the lecture. |
| `dynamic-pool 192.168.255.0/24` | IPv4 addresses that tayga gives to IPv6 clients. |
| `data-dir /var/spool/tayga` | Where tayga keeps its list of which client has which pool address. |

After the file: `tayga --mktun` creates the `nat64` interface, `ip link set nat64 up` turns it on, and two routes send traffic into it: IPv6 packets for `64:ff9b::/96` (to be translated to IPv4) and IPv4 packets for the pool (replies to be translated back to IPv6). The last line, `tayga`, starts the translator in the background.

**Terminal 3 (r2):** paste the whole box:

```
cat > /etc/tayga.conf <<'EOF'
tun-device nat64
ipv4-addr 192.168.255.1
ipv6-addr 2001:db8:b:64::1
prefix 64:ff9b::/96
dynamic-pool 192.168.255.0/24
data-dir /var/spool/tayga
EOF
mkdir -p /var/spool/tayga
tayga --mktun
ip link set nat64 up
ip -6 route add 64:ff9b::/96 dev nat64
ip route add 192.168.255.0/24 dev nat64
tayga
```

**Expected:** one line from `tayga --mktun`, `Created persistent tun device nat64`, and nothing else. Check with `pgrep -a tayga` (it prints tayga's process) and:

```
ip -6 route show 64:ff9b::/96
ip route show 192.168.255.0/24
```

**Expected:** `64:ff9b::/96 dev nat64 ...` and `192.168.255.0/24 dev nat64 scope link`.

**How to read this:** both routes point **into** the translator, one for each direction. r2 still needs both forwarding switches (IPv6 and IPv4) from Parts A and E, because a translated packet is forwarded like any other packet.

:::info
**One IPv4 address per client.** tayga gives each IPv6 client **its own** IPv4 address from the pool (1:1). A real NAT64 gateway, such as the AWS NAT gateway, **shares one** IPv4 address among many clients and tells them apart by port numbers. It must keep a table of every connection: this is the "Statefulness" point on today's "Translation Considerations" slide. Stretch S3 shows the sharing version.
:::

### J6. Route 64:ff9b::/96 to the gateway

**Predict first:** pc1 will send packets to `64:ff9b::6440:a`. Which nodes need a new route: pc1, r1, or both?

<details>
<summary>▶ Answer</summary>

Only r1. pc1 sends everything off its LAN to r1 (its default route). r1 knows LAN A, LAN B and the router link, but not `64:ff9b::/96`, so it would answer "No route", as in D1. This is the "Routing" job from the lecture: send `64:ff9b::/96` to the NAT64 gateway.
</details>

**Terminal 2 (r1):**

```
ip -6 route add 64:ff9b::/96 via 2001:db8:ff::2
```

**Predict first:** pc2 will reply to an address in `192.168.255.0/24`. Does pc2 need a new route?

<details>
<summary>▶ Answer</summary>

No. pc2 sends everything off its LAN to its IPv4 default gateway, r2 (`10.2.0.1`, from E1). r2 has the route that sends `192.168.255.0/24` into the translator.
</details>

Test the translation before DNS is involved: use the address you worked out in J4. **Terminal 1 (pc1):**

```
ping -6 -c2 64:ff9b::6440:a
curl -s -g "http://[64:ff9b::6440:a]:8080/"
```

**Expected:** `64 bytes from 64:ff9b::6440:a ...` and `0% packet loss`, then `Hello from pc2`.

**How to read this:** pc1 used IPv6 only, and pc2 answered on its IPv4-only server. r2 translated in both directions: the request from IPv6 to IPv4, and the reply from IPv4 back to IPv6. `ping -6` works too, because tayga also translates ICMPv6 echo messages to ICMPv4 and back.

### J7. Start the DNS64 resolver on r2

`unbound` is a DNS resolver: hosts send it their questions, and it finds the answers. Its configuration file, line by line:

| Line | Meaning |
|---|---|
| `interface: 2001:db8:b::1` | Listen on this r2 address (IPv6). |
| `access-control: ... allow` | Answer only hosts in the lab's three IPv6 subnets. |
| `module-config: "dns64 iterator"` | Turn on DNS64 in front of the normal lookup. |
| `dns64-prefix: 64:ff9b::/96` | The prefix that DNS64 puts in front of the IPv4 address. |
| `domain-insecure: "lab."` | `lab.` is a private name: do not expect security signatures for it. |
| `username: ""` and `chroot: ""` | Run as root in the normal file system (simple for a lab). |
| `logfile:` and `verbosity: 1` | Write a short log to `/tmp/unbound.log`. |
| `forward-zone:` with `name: "lab."` and `forward-addr: 100.64.0.10` | Send every question about names ending in `lab` to pc2's DNS server, over IPv4. |

The A record stays on pc2's DNS server, not on r2. That is how it is on a real network: the IPv4-only site runs its own DNS, and the DNS64 resolver only changes the answers it gets from there.

**Terminal 3 (r2):** paste the whole box:

```
cat > /etc/unbound/lab.conf <<'EOF'
server:
    interface: 2001:db8:b::1
    access-control: 2001:db8:a::/64 allow
    access-control: 2001:db8:b::/64 allow
    access-control: 2001:db8:ff::/64 allow
    module-config: "dns64 iterator"
    dns64-prefix: 64:ff9b::/96
    domain-insecure: "lab."
    username: ""
    chroot: ""
    logfile: "/tmp/unbound.log"
    verbosity: 1
forward-zone:
    name: "lab."
    forward-addr: 100.64.0.10
EOF
unbound-checkconf /etc/unbound/lab.conf
unbound -c /etc/unbound/lab.conf
```

**Expected:** `unbound-checkconf: no errors in /etc/unbound/lab.conf`, then no output from `unbound`. Check with `pgrep -a unbound`.

**How to read this:** `unbound-checkconf` reads the file and reports typing mistakes before you start the program. `unbound` then starts in the background.

### J8. Make pc1 IPv6-only

The first two lines remove pc1's IPv4 default route and address. The third line tells pc1 to send its DNS questions to r2's resolver, over IPv6: `/etc/resolv.conf` is the file that lists a host's DNS resolver. (On a real network a host can learn the resolver from the Router Advertisement: the RDNSS option on today's "Dual-Stack Configuration Elements" slide.) The last two lines check.

**Terminal 1 (pc1):**

```
ip route del default via 10.1.0.1
ip addr del 10.1.0.10/24 dev eth0
echo 'nameserver 2001:db8:b::1' > /etc/resolv.conf
ip -4 addr show dev eth0
ip route
```

**Expected:** no output from the last two commands: pc1 has no IPv4 address and no IPv4 route.

Try IPv4 anyway:

```
ping -c1 100.64.0.10
```

**Expected:** `ping: connect: Network is unreachable`.

**How to read this:** the error comes from pc1 itself, at once. With no IPv4 address and no IPv4 route, pc1 cannot send any IPv4 packet. The only way to pc2's web server is now IPv6, through r2.

### J9. Ask for web.lab

`+noall +answer` makes `dig` print only the answer lines. With no `@server`, dig uses the resolver in `/etc/resolv.conf` (r2).

**Terminal 1 (pc1):**

```
dig +noall +answer AAAA web.lab
dig +noall +answer A web.lab
```

**Expected:**

```
web.lab.		60	IN	AAAA	64:ff9b::6440:a
web.lab.		60	IN	A	100.64.0.10
```

The `60` (seconds the answer may be kept) can be lower on your screen.

**How to read this:** pc2's DNS server has no AAAA record for `web.lab` (J3), so r2 **made one up**: `64:ff9b::` plus `100.64.0.10`, the address you predicted in J4. The A record passes through unchanged, but pc1 cannot use it: it has no IPv4.

### J10. Fetch the page and watch the translation

`tcpdump -i any` captures on every interface of r2 and prints the interface name and direction (`In` or `Out`) on each line. `-n` shows addresses as numbers, `-c 4` stops after four packets, and `tcp port 8080` keeps only web traffic. The first four packets are the first packet of the connection, seen four times on its way through r2.

**Terminal 3 (r2):** start the capture first:

```
tcpdump -n -i any -c 4 'tcp port 8080'
```

**Terminal 1 (pc1):** fetch the page by name. `grep -E` keeps the lines that show the address curl tried, the one that worked, and the page:

```
curl -sv http://web.lab:8080/ 2>&1 | grep -E 'Trying|Connected|Hello'
```

**Expected on pc1:**

```
*   Trying [64:ff9b::6440:a]:8080...
* Connected to web.lab (64:ff9b::6440:a) port 8080
Hello from pc2
```

**Expected on r2** (your times, port numbers and the last number of the 192.168.255 address will differ):

```
... eth1  In  IP6 2001:db8:a:0:5054:ff:fea2:1.45678 > 64:ff9b::6440:a.8080: Flags [S], ...
... nat64 Out IP6 2001:db8:a:0:5054:ff:fea2:1.45678 > 64:ff9b::6440:a.8080: Flags [S], ...
... nat64 In  IP 192.168.255.27.45678 > 100.64.0.10.8080: Flags [S], ...
... eth0  Out IP 192.168.255.27.45678 > 100.64.0.10.8080: Flags [S], ...
```

**How to read this:** follow one packet (`Flags [S]`, the first packet of a TCP connection):

1. `eth1 In IP6`: it arrives from r1 as IPv6, from pc1 to `64:ff9b::6440:a`.
2. `nat64 Out IP6`: the route for `64:ff9b::/96` sends it into the translator.
3. `nat64 In IP`: it comes back out as **IPv4**. The destination is `100.64.0.10`, taken from the last 32 bits. The source is pc1's address from the pool.
4. `eth0 Out IP`: r2 forwards it to pc2 as a normal IPv4 packet.

Now look at the server's side. **Terminal 4 (pc2):**

```
tail -1 /tmp/web.log
grep web.lab /tmp/dns.log
```

**Expected:** the web log line starts with `192.168.255.` (the same pool address as in the capture). The DNS log shows questions for `web.lab` that came `from 100.64.0.1` (r2).

**How to read this:** pc2 never saw pc1's IPv6 address. Its web server sees an IPv4 client from the pool, and its DNS server only ever talked to r2, over IPv4. As far as pc2 knows, the whole world is IPv4.

**Explain why:** Today's "Translation Considerations" slide says translation breaks the end-to-end model and makes troubleshooting harder. Where do you see both here?

<details>
<summary>▶ Answer</summary>

The server's log shows `192.168.255.x`, not pc1's real address, so the server cannot tell who the client really is. To trace one connection you must match r2's records (which IPv6 client had which pool address) with pc2's log. Without translation, the server would log pc1's own address.
</details>

### J11. Put it back

Give pc1 its IPv4 address and default route again, and let pc2's web server listen on both protocols again (as in E2). Leave everything else from this part as it is (the `100.64.0.x` addresses, tayga, unbound, dnsmasq, the routes and pc1's `/etc/resolv.conf`): the self-check tests them, and stretch S3 uses them.

**Terminal 1 (pc1):**

```
ip addr add 10.1.0.10/24 dev eth0; ip route add default via 10.1.0.1
```

**Terminal 4 (pc2):**

```
pkill -f http.server
cd /tmp && python3 -m http.server 8080 --bind :: > /tmp/web.log 2>&1 &
```

Check from **Terminal 1 (pc1)**:

```
curl -4 http://10.2.0.10:8080/
curl -6 -g "http://[2001:db8:b:0:5054:ff:fea2:b02]:8080/"
```

**Expected:** `Hello from pc2` twice.

**Predict first:** pc1 is dual stack again, and its resolver is still r2. Which address will `curl http://web.lab:8080/` use now: `100.64.0.10` or `64:ff9b::6440:a`?

<details>
<summary>▶ Answer</summary>

`64:ff9b::6440:a`. r2 still answers both the A record and the made-up AAAA record, and the default address selection rules (RFC 6724, Part F) put the IPv6 address first. So pc1 still goes through the translator, although it has IPv4 again. On a real dual-stack network that adds the translator's delay and connection state for no reason. This is why DNS64 is turned on only for IPv6-only subnets, as on the Day 1 slide "NAT64/DNS64 + EIGW/NGW in AWS". You can check with `curl -sv http://web.lab:8080/ 2>&1 | grep Connected`.
</details>

---

## Check your work

The check program tests all four nodes, so it runs on the Cloud9 machine, not on a node.

Open a **new** terminal (**Window > New Terminal**); leave the four node terminals as they are. In the new terminal (the Cloud9 machine):

```
sudo labctl check 2 1
```

**Expected:** fourteen `PASS` lines and:

```
Result: 14 passed, 0 failed
```

The last three lines test Part J: tayga runs on r2, r2's DNS64 answers `64:ff9b::6440:a` for `web.lab`, and pc1 reaches pc2's web server through NAT64.

<details>
<summary>▶ I got a FAIL. What now?</summary>

| FAIL line mentions | Go back to |
|---|---|
| forwarding | A1 / A2 (`sysctl -w net.ipv6.conf.all.forwarding=1` on the router) |
| SLAAC address | B1 / C1: is radvd running on that router (`pgrep -a radvd`)? |
| ping or traceroute over IPv6 | D2: routes on **both** routers |
| ping over IPv4, or web over IPv4 | E1, and J11: did you give pc1 its IPv4 address and default route back? |
| web over IPv6 | J11: is the server on pc2 listening on `::` (`ss -ltn | grep 8080` shows `*:8080`)? If not, start it again as in J11 |
| tayga | J5 on r2 (`pgrep -a tayga`) |
| DNS64 | J7: is unbound running on r2 (`pgrep -a unbound`)? J1 / J2: does pc2 have `100.64.0.10`, and is dnsmasq running (`pgrep -a dnsmasq`)? |
| through NAT64 | J6: the route for `64:ff9b::/96` on r1; J5: the two routes into `nat64` on r2 |
</details>

## Check yourself

1. Why does a router need IPv6 forwarding turned on, and what does it do differently once it is?
2. Why did each router need a route for the far LAN twice, once for IPv4 and once for IPv6?
3. Which protocol did curl try first in E4, and why?
4. Why is "prefer IPv4" in `/etc/gai.conf` (Part F) a workaround rather than a fix?
5. Why can an IPv6 problem on a dual-stack network go unnoticed (Part G)?
6. The network is dual stack, but a server listens on `0.0.0.0` only. What do IPv6 clients see (Part H)?
7. In Part I, who sent Packet Too Big, and why does IPv6 need it?
8. Name the three jobs that let pc1 reach `web.lab` in Part J, and the node that did each one.

<details>
<summary>▶ Answers</summary>

1. With forwarding off, a node is a host: it drops packets that are not addressed to it. With forwarding on, it passes them on according to its routing table. It also joins the all-routers group `ff02::2` and stops accepting Router Advertisements by default.
2. IPv4 and IPv6 are separate protocols with separate routing tables (`ip route` and `ip -6 route`). A route in one table does nothing for the other.
3. IPv6, because the default address selection rules (RFC 6724) prefer IPv6 over IPv4.
4. It hides the IPv6 fault instead of repairing it. IPv6 stays broken; hosts just stop using it first.
5. Applications try IPv6 first and fall back to IPv4 when IPv6 fails (Happy Eyeballs). Users still get their page, so nobody reports a problem.
6. "Connection refused" (curl: "Couldn't connect to server"). The packets arrive, but no program listens for IPv6 on that port. Check with `ss -ltn`.
7. r1, the router in front of the smaller link. IPv6 routers never fragment, so the router drops the packet and tells the sender the right size. If Packet Too Big messages are blocked, large transfers hang (today's "Tunneling Considerations" slide).
8. DNS64 on r2 (unbound) made up the AAAA record `64:ff9b::6440:a`. Routing on r1 sent `64:ff9b::/96` to r2. NAT64 on r2 (tayga) translated IPv6 to IPv4 and the replies back.
</details>

---

# Stretch exercises (about 65 minutes)

Do these after Parts A to J, in order, on the same four nodes and terminals. Each one names the part of today's lecture it builds on. Each one puts things back at the end, so the self-check still passes. **PC2-ADDRESS** is `2001:db8:b:0:5054:ff:fea2:b02` (filled in below).

Always finish the "Put it back" step before the next exercise, or the next one will not behave as described.

## S1: Routers that only need link-local next hops (15 min)

*Ties to today's lecture:* Module 4, "Dual-Stack Configuration Elements": router setup (forwarding, interface addresses, routes). The next hops are link-local addresses (Day 1), as in the default route you saw in Part B.

:::info
**Why this matters**

A next hop only has to be reachable **on the link**, and every IPv6 interface already has a link-local address. So routers can use link-local next hops, and in IPv6 this is common. On a real network it helps because link-local addresses never change when the global prefix is renumbered, and a router link may not need global addresses at all.
:::

### S1-1. Look at r1's route

`ip -6 route show PREFIX` shows only the route for that prefix.

**Terminal 2 (r1):**

```
ip -6 route show 2001:db8:b::/64
```

**Expected:** `2001:db8:b::/64 via 2001:db8:ff::2 dev eth1 metric 1024 pref medium`. The next hop is r2's **global** address on the link.

### S1-2. Find r2's link-local address on the link

`scope link` shows only the link-local address.

**Terminal 3 (r2):**

```
ip -6 addr show dev eth1 scope link
```

**Expected:** `inet6 fe80::5054:ff:fea2:ff02/64 scope link`. (r1's link-local on eth1 is `fe80::5054:ff:fea2:ff01`.)

**How to read this:** the interface ID comes from r2's eth1 MAC `52:54:00:a2:ff:02` (EUI-64). r2 made this address by itself; you never configured it.

### S1-3. Point the routes at link-local addresses

A link-local next hop needs the interface name (`dev eth1`), for the same reason a link-local ping needs `%eth0`.

Every interface has its own `fe80::/64`, so a link-local address alone does not say which cable to use. `ip -6 route replace` swaps the existing route for the new one in one step, so traffic never goes without a route.

**Terminal 2 (r1):**

```
ip -6 route replace 2001:db8:b::/64 via fe80::5054:ff:fea2:ff02 dev eth1
```

**Terminal 3 (r2):**

```
ip -6 route replace 2001:db8:a::/64 via fe80::5054:ff:fea2:ff01 dev eth1
```

**Terminal 1 (pc1):**

```
ping -6 -c2 2001:db8:b:0:5054:ff:fea2:b02
```

**Expected:** `0% packet loss`.

**How to read this:** both routes now use link-local next hops, and LAN A still reaches LAN B.

### S1-4. Remove the global addresses from the router link

**Predict first:** After you remove both global link addresses, will the ping still work? What will hop 2 of the trace show?

<details>
<summary>▶ Answer</summary>

The ping still works: the routes use link-local next hops, which are still there. Hop 2 cannot be `2001:db8:ff::2` any more, because that address is gone, so r2 must answer from another of its addresses.
</details>

**Terminal 2 (r1):**

```
ip -6 addr del 2001:db8:ff::1/64 dev eth1
```

**Terminal 3 (r2):**

```
ip -6 addr del 2001:db8:ff::2/64 dev eth1
```

**Terminal 1 (pc1):**

```
ping -6 -c2 2001:db8:b:0:5054:ff:fea2:b02
traceroute -6 -n 2001:db8:b:0:5054:ff:fea2:b02
```

**Expected:** the ping still works. In the trace, hop 2 now shows `2001:db8:b::1`:

```
 1  2001:db8:a::1  ...
 2  2001:db8:b::1  ...
 3  2001:db8:b:0:5054:ff:fea2:b02  ...
```

r2 has no global address on the link any more, so it answers from another of its addresses. A route only needs a next hop on the same link, and every IPv6 interface already has a link-local address.

**How to read this:** hop 2 is still r2. Its Time Exceeded message must cross r1 to reach LAN A, and routers never forward packets from link-local addresses, so r2 uses a global address from another interface: its LAN B address.

**Explain why:** What is a downside of a router link with no global addresses?

<details>
<summary>▶ Answer</summary>

Nobody outside the link can reach the routers' link interfaces, and traceroute shows addresses from other interfaces, which is harder to read. Many networks keep global addresses on router links for troubleshooting, even when routes use link-local next hops.
</details>

### S1-5. Put it back

Add the global address **first**: a route `via 2001:db8:ff::2` is accepted only when the router has a connected route to `2001:db8:ff::/64`, and that comes from its own address on the link.

**Terminal 2 (r1):**

```
ip -6 addr add 2001:db8:ff::1/64 dev eth1
ip -6 route replace 2001:db8:b::/64 via 2001:db8:ff::2
ip -6 route replace 64:ff9b::/96 via 2001:db8:ff::2
```

The third line restores the NAT64 route from J6, in case it went away with the link address.

**Terminal 3 (r2):**

```
ip -6 addr add 2001:db8:ff::2/64 dev eth1
ip -6 route replace 2001:db8:a::/64 via 2001:db8:ff::1
```

Check from **Terminal 1 (pc1)** that `traceroute -6 -n 2001:db8:b:0:5054:ff:fea2:b02` shows `2001:db8:ff::2` at hop 2 again.

## S2: A second subnet and one summary route (20 min)

*Ties to today's lecture:* Module 4, "Dual-Stack Pros & Cons": "routers need larger routing tables". A summary route keeps the IPv6 table small. It also uses /48 and /64 prefix lengths (Day 1).

:::info
**New in this exercise**

**Summarisation** (also called aggregation) means one route for a large block instead of one route for each small subnet inside it. A site that owns a /48 can split it into 65,536 subnets of /64. Other routers need only **one** route for the /48.

This works because of the **longest-match rule**: when several routes match an address, a router uses the one with the longest prefix (the most specific one). A /48 route matches every address in the site, and a more specific /64 route, if one exists, still wins for its own subnet.
:::

:::info
**Why this matters**

If every other router needed one route per /64, tables would grow and every new subnet would need changes on many routers. On a real network, forgetting a route for a new subnet cuts its users off from everything outside their LAN. A summary route prevents that.
:::

LAN B's site owns `2001:db8:b::/48`. That is 65,536 subnets of /64, from `2001:db8:b:0::/64` to `2001:db8:b:ffff::/64`. Part C used the first one.

### S2-1. Add a second subnet to LAN B

r2 gets an address in a second subnet, `2001:db8:b:1::/64`, on the same LAN, and radvd advertises both prefixes. radvd reads its file only at start, so `pkill radvd; sleep 1; radvd` restarts it.

**Terminal 3 (r2):**

```
ip -6 addr add 2001:db8:b:1::1/64 dev eth0
cat > /etc/radvd.conf <<'EOF'
interface eth0 {
    AdvSendAdvert on;
    MinRtrAdvInterval 3;
    MaxRtrAdvInterval 10;
    prefix 2001:db8:b::/64 {
        AdvOnLink on;
        AdvAutonomous on;
    };
    prefix 2001:db8:b:1::/64 { AdvOnLink on; AdvAutonomous on; };
};
EOF
pkill radvd; sleep 1; radvd
```

### S2-2. Check pc2

**Terminal 4 (pc2)**, after about 10 seconds:

```
ip -6 addr show dev eth0
```

**Expected:** a second global address, `2001:db8:b:1:5054:ff:fea2:b02`.

**How to read this:** same interface ID, different prefix. One RA can carry several prefixes, and SLAAC builds one address per prefix.

### S2-3. Try to reach it from LAN A

**Predict first:** Will pc1 reach pc2's new address?

<details>
<summary>▶ Answer</summary>

No. r1 has a route only for `2001:db8:b::/64`; the new address is in `2001:db8:b:1::/64`. r1 will answer No route, as in D1.
</details>

**Terminal 1 (pc1):**

```
ping -6 -c1 2001:db8:b:1:5054:ff:fea2:b02
```

**Expected:** `From 2001:db8:a::1 icmp_seq=1 Destination unreachable: No route`. r1 only knows the first /64.

### S2-4. One route for the whole site

You delete the /64 first so you can see the /48 working alone.

**Terminal 2 (r1):** replace the /64 route with a /48:

```
ip -6 route del 2001:db8:b::/64
ip -6 route add 2001:db8:b::/48 via 2001:db8:ff::2
```

**Terminal 1 (pc1):**

```
ping -6 -c1 2001:db8:b:0:5054:ff:fea2:b02
ping -6 -c1 2001:db8:b:1:5054:ff:fea2:b02
```

**Expected:** both work. One /48 route covers every subnet the site will ever add.

**How to read this:** both addresses start with the same 48 bits, `2001:db8:b`, so one route matches both. r2 then delivers each one, because both /64s are connected to its eth0.

`ip -6 route get ADDRESS` sends nothing; it only shows which route r1 would use.

**Predict first:** Where will r1 send a packet for 2001:db8:b:abcd::1?

<details>
<summary>▶ Answer</summary>

To r2: the address starts with `2001:db8:b`, so the /48 matches.
</details>

**Terminal 2 (r1):**

```
ip -6 route get 2001:db8:b:abcd::1
```

**Expected:** `... via 2001:db8:ff::2 dev eth1 ...`. Even a subnet that does not exist yet goes to r2.

**How to read this:** the output shows the next hop (`via`) and interface (`dev`) r1 chose. When the site adds that subnet one day, r1 needs no change.

**Explain why:** What happens to a packet for a subnet inside the /48 that LAN B does not use?

<details>
<summary>▶ Answer</summary>

r1 sends it to r2. r2 has no route for it, so r2 drops it and returns Destination Unreachable. The summary only says "this whole block is over there"; the site's own router knows which subnets exist.
</details>

### S2-5. Put it back

**Terminal 2 (r1):**

```
ip -6 route del 2001:db8:b::/48
ip -6 route add 2001:db8:b::/64 via 2001:db8:ff::2
```

On r2: the original one-prefix radvd file, remove the second address, restart radvd.

**Terminal 3 (r2):**

```
cat > /etc/radvd.conf <<'EOF'
interface eth0 {
    AdvSendAdvert on;
    MinRtrAdvInterval 3;
    MaxRtrAdvInterval 10;
    prefix 2001:db8:b::/64 {
        AdvOnLink on;
        AdvAutonomous on;
    };
};
EOF
ip -6 addr del 2001:db8:b:1::1/64 dev eth0
pkill radvd; sleep 1; radvd
```

pc2 keeps a SLAAC address until its lifetime runs out, even when RAs stop mentioning the prefix, so you remove it by hand.

**Terminal 4 (pc2):**

```
ip -6 addr del 2001:db8:b:1:5054:ff:fea2:b02/64 dev eth0
```

## S3: Share one IPv4 address, as a real NAT64 gateway does (15 min)

*Ties to today's lecture:* Module 6, "Translation Considerations": "Statefulness (NAT64): like NAT44, requires gateway to maintain connection state". It also uses the NAT slide from Day 1's IPv4 refresher.

:::info
**New in this exercise**

In Part J, tayga gave each IPv6 client **its own** IPv4 address from a pool. That needs one IPv4 address per client, which is exactly what IPv4 does not have.

A real NAT64 gateway shares **one** IPv4 address among all clients, like the home router on Day 1's NAT slide. To send the replies to the right client, it also changes the **source port** when needed and keeps a **table of connections**: client address and port on one side, shared address and port on the other. Linux calls this **masquerade**: "rewrite the source to my own address on the way out, and remember the connection".

You add masquerade with `nft`, the Linux packet filter tool (firewalls are a Day 3 topic; here you use only this one rule):

- `nft add table ip lab64`: a new, empty table for IPv4 rules named `lab64`.
- `nft add chain ... '{ type nat hook postrouting priority 100 ; }'`: a chain for address translation, run just before a packet leaves r2.
- `nft add rule ... ip saddr 192.168.255.0/24 oifname "eth0" masquerade`: packets from tayga's pool that leave on eth0 get r2's own address as source.

tayga still translates IPv6 to IPv4. Masquerade then hides the pool behind r2's address. Together they behave like a stateful NAT64 gateway.
:::

### S3-1. Two clients, two pool addresses

r1 can be a second IPv6 client: it has a route to `64:ff9b::/96` (J6).

**Terminal 1 (pc1)** and then **Terminal 2 (r1)**, the same command:

```
curl -s -g "http://[64:ff9b::6440:a]:8080/"
```

**Terminal 4 (pc2):** the last two requests in the server log:

```
tail -2 /tmp/web.log
```

**Expected:** `Hello from pc2` on pc1 and r1, then two log lines that start with **different** pool addresses, for example:

```
::ffff:192.168.255.27 - - [...] "GET / HTTP/1.1" 200 -
::ffff:192.168.255.140 - - [...] "GET / HTTP/1.1" 200 -
```

**How to read this:** the server listens on `::` again (J11), so IPv4 clients appear as `::ffff:` plus the IPv4 address (as in H2). Each IPv6 client got its own IPv4 address from the pool. Your numbers will differ.

### S3-2. Share r2's address

**Predict first:** After the masquerade rule, which client address will pc2's log show for both requests?

<details>
<summary>▶ Answer</summary>

r2's address on that LAN, `100.64.0.1`, for both. The packets go to `100.64.0.10`, so r2 uses its own address in `100.64.0.0/24` as the new source.
</details>

**Terminal 3 (r2):** paste the whole box. The last line lists the table so you can check it:

```
nft add table ip lab64
nft add chain ip lab64 post '{ type nat hook postrouting priority 100 ; }'
nft add rule ip lab64 post ip saddr 192.168.255.0/24 oifname "eth0" masquerade
nft list table ip lab64
```

**Expected:** the table, with the chain and the `masquerade` rule.

Repeat the curl in **Terminal 1 (pc1)** and **Terminal 2 (r1)**, then `tail -2 /tmp/web.log` in **Terminal 4 (pc2)**.

**Expected:** both new lines start with `::ffff:100.64.0.1`.

**How to read this:** pc2 now sees one IPv4 client, r2, for every IPv6 client. r2 tells the connections apart by the port numbers in its connection table. This is how a NAT64 gateway can serve thousands of IPv6 clients with one public IPv4 address.

**Explain why:** The lecture lists "potential single point of failure" for stateful NAT64. Why is the connection table the reason?

<details>
<summary>▶ Answer</summary>

Only this gateway knows which IPv6 client and port belong to each shared address and port. If it fails, the table is lost: every open connection breaks, and replies cannot go to the right client. Another gateway cannot take over those connections without that table.
</details>

### S3-3. Put it back

Delete the table: this removes the chain and the rule.

**Terminal 3 (r2):**

```
nft delete table ip lab64
```

## S4: Break it, find it, fix it (15 min)

*Ties to today's lecture:* Module 4, "Dual-Stack Configuration Elements": IPv6 forwarding on, and routes in both directions. Reading traceroute rests on the hop limit (Day 1). Troubleshooting in depth is a Day 3 topic; here you use only `ping` and `traceroute`.

:::info
**Why this matters**

Troubleshooting starts from a symptom ("pc1 cannot reach pc2"), not from the cause. Here you create two common faults and learn to recognise them from `ping` and `traceroute` output, so the output tells you which router to look at.
:::

For each fault: make the change, **predict** what pc1 will see, test from **Terminal 1 (pc1)** with:

```
ping -6 -c2 -W1 2001:db8:b:0:5054:ff:fea2:b02
traceroute -6 -n -w1 2001:db8:b:0:5054:ff:fea2:b02
```

then fix it.

`-W1` and `-w1` wait only one second per reply. Use this table to read the results:

| What pc1 sees | What it usually means |
|---|---|
| `Destination unreachable: No route` from a router | That router has no route to the destination. |
| Trace answers up to hop N, then `* * *` | Replies from further on cannot come back: check routes **toward pc1**. |
| `* * *` from hop 1 | The first router is not forwarding at all. |

### S4-1. A missing return route

You remove r2's route back to LAN A. **Predict first:** An error message, or silence? How far will the trace get?

**Terminal 3 (r2):**

```
ip -6 route del 2001:db8:a::/64
```

<details>
<summary>▶ Expected result and fix</summary>

The ping gets no reply. The traceroute shows hop 1 (`2001:db8:a::1`) and then only `* * *`. pc2 still gets the requests, but r2 cannot send anything back to LAN A, not even the traceroute replies.

Fix, in **Terminal 3 (r2)**:

```
ip -6 route add 2001:db8:a::/64 via 2001:db8:ff::1
```
</details>

**Explain why:** The fault is on r2, but the trace goes silent after hop 1. Why?

<details>
<summary>▶ Answer</summary>

r1 can answer because r1 knows LAN A. Every answer from hop 2 onward must pass through r2, which has no route to LAN A. A trace shows where the **answers stop coming back**, not where the requests stop, so check the next router's route back to the source.
</details>

### S4-2. A router that stopped routing

You turn off IPv6 forwarding on r1; its addresses and routes stay. **Predict first:** Will r1 answer at hop 1? Will anyone send an error?

**Terminal 2 (r1):**

```
sysctl -w net.ipv6.conf.all.forwarding=0
```

<details>
<summary>▶ Expected result and fix</summary>

pc1 still has its default route, but the ping gets no reply and the traceroute gets no answer at all (`* * *` from hop 1). r1 now acts as a host and quietly drops packets that are not addressed to itself.

Fix, in **Terminal 2 (r1)**:

```
sysctl -w net.ipv6.conf.all.forwarding=1
```
</details>

**Explain why:** Both faults made the ping silent. How does the trace tell them apart?

<details>
<summary>▶ Answer</summary>

In S4-1 hop 1 answered, so r1 worked and the fault was further on. In S4-2 not even hop 1 answered: a host does not lower the hop limit or send Time Exceeded for packets not addressed to it. Silence from hop 1 points at the first router itself.
</details>

Finally, run the self-check again in the Cloud9 terminal: `sudo labctl check 2 1`. **Expected:** `Result: 14 passed, 0 failed`.

## Stretch: check yourself

1. Why can a router use a link-local address as a next hop, but a host on another LAN cannot reach it?
2. What does one /48 route save you compared with one route per /64?
3. In S3, how many IPv4 addresses did r2 need for two IPv6 clients, before and after the masquerade rule?

<details>
<summary>▶ Answers</summary>

1. A next hop only has to be reachable on the directly connected link, and link-local addresses are valid on that link. Routers never forward packets to or from link-local addresses, so nobody beyond the link can reach them.
2. One route covers every subnet the site has or will add, so r1 does not need a change each time LAN B's site adds a /64. Smaller routing tables, fewer changes, fewer mistakes.
3. Before: two pool addresses, one per client (1:1). After: one, r2's own address, shared by both clients. The price is a connection table on r2 (state).
</details>

---

**Next:** **IPv6 Day 3 Lab: IPv6 Across an IPv4-Only Network** (tomorrow)
