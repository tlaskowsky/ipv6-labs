---
title: "IPv6 Day 1 Lab: Link-Local, Neighbor Discovery and SLAAC"
tags: ipv6, labs
---

# IPv6 Day 1 Lab: Link-Local, Neighbor Discovery and SLAAC

**Day 1 lab (Lab 1 in the `lab` menu).** Core parts: about 195 minutes. Stretch exercises: about 80 minutes. The core parts use only what today's lecture covered.

[TOC]

## What you will do

- See the address every IPv6 interface gives itself with no configuration (link-local).
- Work out an interface ID from a MAC address by hand (EUI-64).
- Watch how IPv6 finds a neighbor's MAC address without ARP (Neighbor Discovery).
- Turn a node into a router that hands out a prefix, and watch hosts configure themselves (SLAAC).
- See Duplicate Address Detection stop an address conflict, and see its packet on the wire.
- Find the multicast groups every node joins, and the extra ones a router joins.
- Add a Unique Local (ULA) prefix next to the global one, and name the type and scope of every address on a host.
- Find the loopback address and an anycast address that every Linux router has.
- Write addresses in full and short form, and read prefixes and subnets.
- Turn on privacy (temporary) addresses.
- Read the IPv6 header in a capture: hop limit, flow label, Next Header and the Fragment header, side by side with IPv4.

:::info
New to the lab environment? Do **Getting Started** first. It shows how to open Cloud9, the `lab` menu and a second terminal.
:::

### How to use this guide

**Core parts** A to L are the scheduled lab: do them in order. They use only what today's lecture covered. Each part shows its minutes in its title and names the lecture module it comes from. **Stretch exercises** come after Part L, for when you finish early. Each one says how it ties to today's lecture, and a **New in this exercise** box explains anything the lecture did not cover.

Each step says why you run a command and what the output proves. When you see **Predict first**, write down your guess before you run the command. When you see **Explain why**, answer in your own words before you open the answer. The "How to read this" notes connect the output on your screen to today's lecture.

#### Suggested timing

| Block | Minutes |
|---|---|
| Start-up: Getting Started, open the three terminals | 15 |
| Parts A to D: link-local, Neighbor Discovery, SLAAC, DAD (20 + 15 + 30 + 10) | 75 |
| Break | 10 |
| Parts E to H: DAD on the wire, multicast groups, ULA, address types (10 + 10 + 20 + 15) | 55 |
| Break | 10 |
| Parts I to L: anycast, notation and prefixes, privacy addresses, the IPv6 header (15 + 20 + 10 + 20) | 65 |
| Wrap-up: Check your work, Check yourself | 10 |
| **Total** | **240** |

## Your network

Three nodes on one Ethernet segment (a switch you do not need to touch):

```
 pc1 (eth0) ----+
 pc2 (eth0) ----+---- switch
 r1  (eth0) ----+
```

| Node | Role | MAC address of eth0 |
|---|---|---|
| pc1 | host | `52:54:00:a1:00:01` |
| pc2 | host | `52:54:00:a1:00:02` |
| r1 | will become the router | `52:54:00:a1:00:fe` |

Nothing is configured yet: no global addresses, no router.

All three nodes are on the **same link**: they reach each other directly, with no router in between. Link-local addresses and `ff02::` multicast groups work only inside one link, so everything you send today reaches these three nodes and no others. Keep the MAC addresses in mind: you will find them hidden inside IPv6 addresses.

## Before you start: open three terminals

You will use all three nodes. Open them now and keep them open for the whole lab. Each node is a separate small Linux machine, so always check the prompt before you type.

1. In the first terminal (on the Cloud9 machine), type:
   ```
   lab 1 pc1
   ```
   **Expected:** the prompt changes to `[s01 pc1]#`. We call this **Terminal 1 (pc1)**.
2. Open a second terminal (**Window > New Terminal**) and type:
   ```
   lab 1 pc2
   ```
   **Expected:** `[s01 pc2]#`. This is **Terminal 2 (pc2)**.
3. Open a third terminal and type:
   ```
   lab 1 r1
   ```
   **Expected:** `[s01 r1]#`. This is **Terminal 3 (r1)**.

---

## Part A: Link-local addresses (20 min)

*From today's lecture: Module 2, Link-Local Addresses and EUI-64; Module 2, Multicast Addresses.*

:::info
**Why this matters.** As soon as an IPv6 interface comes up, it builds a **link-local address** in `fe80::/64` by itself, with no server and no router. This address is valid only on the local link. Neighbor Discovery, Router Advertisements and the default gateway (Part C) all run on link-local addresses. A device whose link-local address does not work cannot find its router or get a global address, even when its cable is fine.
:::

### A1. Look at pc1's address

`ip -6 addr show dev eth0` lists the IPv6 addresses (`-6`) of one interface (`dev eth0`). Nothing is configured, so you see only what the interface did by itself.

**Predict first:** how many IPv6 addresses will pc1 have?

<details>
<summary>▶ Answer</summary>

One, a link-local address. A global address needs a router (Part C).
</details>

**Terminal 1 (pc1):**

```
ip -6 addr show dev eth0
```

**Expected** (the number after `@if` differs):

```
36: eth0@if35: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc noqueue state UP group default qlen 1000 link-netnsid 1
    inet6 fe80::5054:ff:fea1:1/64 scope link
       valid_lft forever preferred_lft forever
```

There is exactly one IPv6 address. It starts with `fe80::` and has `scope link`. Nobody configured it: the interface made it by itself as soon as it came up.

#### How to read this

- `mtu 1500`: the largest packet this link carries. IPv6 needs at least 1280 on every link.
- `fe80::5054:ff:fea1:1/64`: `/64` means the first 64 bits are the prefix (`fe80::`) and the last 64 bits are the **interface ID** (`5054:ff:fea1:1`).
- `scope link`: valid only on this link. A router never forwards a packet with this address.
- `valid_lft forever preferred_lft forever`: it never expires. The global address in Part C will have a countdown instead.

### A2. Work out the interface ID by hand (EUI-64)

Once you know this rule, you can look at an address and see which MAC it was built from. That helps when you troubleshoot, and it is the reason for the privacy addresses in Part K.

The last 64 bits of `fe80::5054:ff:fea1:1` come from pc1's MAC address `52:54:00:a1:00:01`. Follow the steps on paper:

| Step | Result |
|---|---|
| 1. Start with the MAC | `52:54:00:a1:00:01` |
| 2. Split it in half and put `ff:fe` in the middle | `52:54:00:ff:fe:a1:00:01` |
| 3. Flip the 7th bit of the first byte: `52` is `0101 0010`, flipping that bit gives `0101 0000` = `50` | `50:54:00:ff:fe:a1:00:01` |
| 4. Group into 16-bit blocks | `5054:00ff:fea1:0001` |
| 5. Drop leading zeros | `5054:ff:fea1:1` |
| 6. Put `fe80::` in front | `fe80::5054:ff:fea1:1` |

#### How to read this

- A MAC has 48 bits, an interface ID needs 64. Step 2 adds the missing 16 bits. `ff:fe` in the middle of an interface ID almost always means "built from a MAC".
- The bit in step 3 is the **universal/local bit**. IPv6 inverts its meaning so that simple hand-made IDs, like the `::1` you give r1 in Part C, need no special bit.

### A3. Predict pc2's address, then check it

pc2's MAC is `52:54:00:a1:00:02`. Write down what you think its link-local address is.

<details>
<summary>▶ Answer</summary>

`fe80::5054:ff:fea1:2`. Only the last byte of the MAC is different, so only the last block of the address changes.
</details>

Now check it with the same command as in A1. **Terminal 2 (pc2):**

```
ip -6 addr show dev eth0
```

**Expected:** `inet6 fe80::5054:ff:fea1:2/64 scope link`

By the same rule, r1 (`52:54:00:a1:00:fe`) is `fe80::5054:ff:fea1:fe`. You will see it often today.

### A4. Ping pc2's link-local address

Now prove that two hosts with no configuration can already talk. `ping -6` sends ICMPv6 Echo Requests and waits for Echo Replies.

**Terminal 1 (pc1):**

```
ping -6 -c3 fe80::5054:ff:fea1:2%eth0
```

**Expected:**

```
PING fe80::5054:ff:fea1:2%eth0 (fe80::5054:ff:fea1:2%eth0) 56 data bytes
64 bytes from fe80::5054:ff:fea1:2%eth0: icmp_seq=1 ttl=64 time=0.120 ms
64 bytes from fe80::5054:ff:fea1:2%eth0: icmp_seq=2 ttl=64 time=0.070 ms
64 bytes from fe80::5054:ff:fea1:2%eth0: icmp_seq=3 ttl=64 time=0.065 ms

--- fe80::5054:ff:fea1:2%eth0 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss
```

`-c3` sends three pings and stops. `%eth0` is the **zone ID**: it tells pc1 which interface to send the packet out of.

#### How to read this

Three replies from pc2's link-local address, `0% packet loss`. `ttl=64` is really the IPv6 **hop limit** (Part L); ping still uses the IPv4 name.

**Predict first:** what happens if you leave out `%eth0`?

Now try it **without** `%eth0`:

```
ping -6 -c3 fe80::5054:ff:fea1:2
```

**Expected:** a warning (`ping: Warning: IPv6 link-local address on ICMP datagram socket may require ifname or scope-id`) and then `3 packets transmitted, 0 received, 100% packet loss`. Without the zone ID the pings go nowhere.

<details>
<summary>▶ Why does a link-local address need %eth0?</summary>

Every interface on a host has an address in `fe80::/64`, so `fe80::/64` exists on every link at the same time. The address alone does not say which link the neighbor is on. The zone ID (`%eth0`) picks the interface.
</details>

### A5. Ping every IPv6 node on the link at once

IPv6 has **no broadcast**. To reach many nodes, it sends to a **multicast group**, and only nodes that joined the group process the packet. `ff` at the start means multicast; `02` means **link scope**, so the packet never leaves this link. It still needs `%eth0`, because `ff02::1` exists on every link.

**Predict first:** how many different nodes will answer?

<details>
<summary>▶ Answer</summary>

Three: pc2, r1 and pc1 itself, because pc1 is a member of the group too.
</details>

**Terminal 1 (pc1):**

```
ping -6 -c2 ff02::1%eth0
```

**Expected:** replies from three addresses: pc1 itself (`fe80::5054:ff:fea1:1`), pc2 (`...:fea1:2`) and r1 (`...:fea1:fe`). Extra replies to the same ping are marked `(DUP!)`. That is normal for a multicast ping.

`ff02::1` is the **all-nodes** multicast group. Every IPv6 interface listens to it.

#### How to read this

Every reply comes from a link-local address, because the request went to a link-scope group. One request, several members, several replies: a quick way to find every IPv6 device on a link. Unlike a broadcast, a multicast can be ignored by devices that have not joined the group.

---

## Part B: Neighbor Discovery (15 min)

*From today's lecture: Module 3, Neighbor Discovery Protocol (address resolution with NS/NA, solicited-node multicast).*

IPv6 has no ARP. It finds a neighbor's MAC address with two ICMPv6 messages: **Neighbor Solicitation** (NS, type 135) and **Neighbor Advertisement** (NA, type 136).

:::info
**Why this matters.** Before pc1 can put an IPv6 packet into an Ethernet frame, it needs the destination's MAC. It asks with an NS ("who has this IPv6 address?"), the owner answers with an NA ("me, here is my MAC"), and pc1 stores the answer in its **neighbor cache**. The NS is not broadcast: it goes to the **solicited-node** multicast group that, in practice, only the owner listens to. Every packet on a LAN depends on this. If Neighbor Discovery fails, pings to a neighbor or the gateway time out even though addresses and cables are correct.
:::

### B1. Start a capture on pc2

`tcpdump` prints packets as they pass. `-n` shows numbers instead of names, `-i eth0` picks the interface, and `icmp6` keeps only ICMPv6 (Neighbor Discovery, ping and Router Advertisements are all ICMPv6). You capture on pc2 because pc2 is the node being looked for.

**Terminal 2 (pc2):**

```
tcpdump -ni eth0 icmp6
```

**Expected:**

```
listening on eth0, link-type EN10MB (Ethernet), snapshot length 262144 bytes
```

Leave it running.

### B2. Clear pc1's neighbor cache and ping pc2

pc1 already learned pc2's MAC in Part A. `ip -6 neigh flush dev eth0` empties the cache, so pc1 must ask again. After one ping, `ip -6 neigh` shows the cache.

**Terminal 1 (pc1):** run these three commands one after the other:

```
ip -6 neigh flush dev eth0
ping -6 -c1 fe80::5054:ff:fea1:2%eth0
ip -6 neigh
```

**Expected** for the last command:

```
fe80::5054:ff:fea1:2 dev eth0 lladdr 52:54:00:a1:00:02 REACHABLE
```

pc1 has learned pc2's MAC address (`lladdr`).

#### How to read this

The IPv6 address, the **link-layer address** (`lladdr`, pc2's MAC) and the state. `REACHABLE` means "confirmed very recently"; stretch S1 shows how this changes. The table does the job of the IPv4 ARP table. The difference is how the entry was learned, which you see next.

### B3. Read the capture

Go back to **Terminal 2 (pc2)**. **Expected** (times removed):

```
IP6 fe80::5054:ff:fea1:1 > ff02::1:ffa1:2: ICMP6, neighbor solicitation, who has fe80::5054:ff:fea1:2, length 32
IP6 fe80::5054:ff:fea1:2 > fe80::5054:ff:fea1:1: ICMP6, neighbor advertisement, tgt is fe80::5054:ff:fea1:2, length 32
IP6 fe80::5054:ff:fea1:1 > fe80::5054:ff:fea1:2: ICMP6, echo request, id 1, seq 1, length 64
IP6 fe80::5054:ff:fea1:2 > fe80::5054:ff:fea1:1: ICMP6, echo reply, id 1, seq 1, length 64
```

You may see one more NS/NA pair a few seconds later, when pc2 checks that pc1 is still there. Press **Ctrl+C** to stop the capture.

#### How to read this

Each line is: source `>` destination, then the message type.

- **NS:** from pc1 to the multicast group `ff02::1:ffa1:2`: "who has `fe80::5054:ff:fea1:2`?" It must go to a group because pc1 does not know pc2's MAC yet. pc1 puts its own MAC in the NS, so pc2 learns it at the same time.
- **NA:** from pc2 straight back to pc1 (unicast), carrying pc2's MAC. `tgt is` names the address that was looked up.
- **Echo request and reply:** only now can the ping itself go out. `length 32` on the NS and NA is the message plus an 8-byte option that carries the MAC.

Questions:

1. Which address was the neighbor solicitation sent **to**?
2. How is that address built?

<details>
<summary>▶ Answers</summary>

1. `ff02::1:ffa1:2`. It is not sent to everyone (`ff02::1`), only to pc2's **solicited-node multicast address**.
2. `ff02::1:ff` followed by the **last 24 bits** of the address being looked up. The last 24 bits of `fe80::5054:ff:fea1:2` are `a1:00:02`, so the group is `ff02::1:ffa1:2`.
</details>

**Explain why:** `ff02::1` would also reach pc2. Why use the solicited-node group?

<details>
<summary>▶ Answer</summary>

With `ff02::1`, every node on the link would have to read and drop every lookup. Only nodes whose address ends in `a1:00:02` join `ff02::1:ffa1:2`. On a link with hundreds of hosts, that saves all the others from the work.
</details>

### B4. Find the solicited-node group on pc2

A node receives multicast only for groups it has **joined**, so pc2 must be in `ff02::1:ffa1:2`. `ip -6 maddr show dev eth0` lists the groups eth0 has joined.

**Terminal 2 (pc2):**

```
ip -6 maddr show dev eth0
```

**Expected:** the list includes:

```
	inet6 ff02::1:ffa1:2
	inet6 ff02::1
```

pc2 joined `ff02::1:ffa1:2` so that it hears solicitations for its own address.

#### How to read this

`ff02::1` is the all-nodes group (A5). A node joins one solicited-node group for each of its addresses, automatically. Lines starting with `link` and a MAC beginning `33:33` (if you see them) are the matching Ethernet multicast addresses, which let the network card filter out groups pc2 has not joined.

---

## Part C: Turn r1 into a router and use SLAAC (30 min)

*From today's lecture: Module 3, Neighbor Discovery Protocol (router discovery with RS/RA, SLAAC).*

:::info
**Why this matters.** A router sends **Router Advertisements** (RA, ICMPv6 type 134) that say "I am a router, this is the link's prefix, and this is how you may use it". A host can ask for one at once with a **Router Solicitation** (RS, type 133). From the prefix, each host builds its own address: prefix + its own interface ID. This is **SLAAC**. "Stateless" means the router keeps no list of who has which address. In many company networks every laptop and phone is configured this way. If RAs stop or are wrong, hosts keep only link-local addresses and cannot reach anything beyond the link, all at the same time.
:::

### C1. Make r1 a router and give it a global address

r1 is still an ordinary host. Two changes make it the router of this link:

- `sysctl -w net.ipv6.conf.all.forwarding=1` changes a kernel setting that tells Linux "this node is a router". r1 then joins the all-routers group `ff02::2` (Part F) and gets a router-only anycast address (Part I), and radvd (C3) expects this setting. Passing packets between networks, the "forwarding" in the name, is for a later day.
- `ip -6 addr add 2001:db8:a::1/64 dev eth0` gives r1 a fixed global address. A router does not configure itself from its own advertisements, so you set it by hand.

**Terminal 3 (r1):**

```
sysctl -w net.ipv6.conf.all.forwarding=1
ip -6 addr add 2001:db8:a::1/64 dev eth0
```

**Expected:** the first command prints `net.ipv6.conf.all.forwarding = 1`. The second prints nothing (no news is good news).

Check the address:

```
ip -6 addr show dev eth0
```

**Expected:** two addresses now: `inet6 2001:db8:a::1/64 scope global` and `inet6 fe80::5054:ff:fea1:fe/64 scope link`.

#### How to read this

`scope global` means usable beyond this link. There is no `dynamic` flag: you typed this address, so it never expires. The link-local address stays: every IPv6 interface has several addresses at once.

:::info
`2001:db8::/32` is the documentation prefix. It is reserved for examples and labs like this one, so it can never clash with a real network.
:::

### C2. Write the Router Advertisement settings

r1 now has the prefix, but nobody else knows about it. Hosts learn a prefix only from RAs, so r1 needs a program that sends them.

r1 will use the program **radvd** to send Router Advertisements. Create its configuration file by pasting this whole box into **Terminal 3 (r1)** in one go:

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
```

The box writes every line up to `EOF` into `/etc/radvd.conf`. It is a way to create a file without an editor; `cat /etc/radvd.conf` then shows it.

Check the file:

```
cat /etc/radvd.conf
```

**Expected:** the same 9 lines, from `interface eth0 {` to `};`.

What the settings mean:

| Setting | Meaning |
|---|---|
| `AdvSendAdvert on` | Send Router Advertisements on eth0 |
| `MinRtrAdvInterval 3` / `MaxRtrAdvInterval 10` | Send one every 3 to 10 seconds (the default is much slower; fast is handy in a lab) |
| `prefix 2001:db8:a::/64` | The prefix hosts on this link should use |
| `AdvOnLink on` | Addresses in this prefix are on this link: reach them directly |
| `AdvAutonomous on` | Hosts may build their own address from this prefix (SLAAC) |

Without `AdvAutonomous on`, hosts would learn the prefix but build no address: no SLAAC. Values you did not set, such as lifetimes, use radvd's defaults; you will see them in C4.

### C3. Start radvd

`radvd` reads `/etc/radvd.conf` and keeps running in the background. `pgrep -a radvd` lists running radvd processes, to prove it started.

**Terminal 3 (r1):**

```
radvd
```

**Expected:** no output; you get the prompt back. radvd now runs in the background. Check it:

```
pgrep -a radvd
```

**Expected:** one or two lines with `radvd` in them.

:::warning
If `radvd` prints an error, it names the line of `/etc/radvd.conf` it did not like. Paste the box from C2 again and rerun `radvd`.
:::

### C4. Ask for a Router Advertisement

A host that has just joined a link does not want to wait up to 10 seconds, so it sends an RS. `rdisc6 eth0` does that on eth0 and prints the answer.

**Predict first:** an RS must reach routers but not hosts. Which address does it go to?

<details>
<summary>▶ Answer</summary>

`ff02::2`, the **all-routers** group. The first output line shows it.
</details>

**Terminal 1 (pc1):**

```
rdisc6 eth0
```

`rdisc6` sends a Router Solicitation (type 133) and prints the Router Advertisement (type 134) that comes back.

**Expected:**

```
Soliciting ff02::2 (ff02::2) on eth0...

Hop limit                 :           64 (      0x40)
Stateful address conf.    :           No
Stateful other conf.      :           No
Mobile home agent         :           No
Router preference         :       medium
Neighbor discovery proxy  :           No
Router lifetime           :           30 (0x0000001e) seconds
Reachable time            :  unspecified (0x00000000)
Retransmit time           :  unspecified (0x00000000)
 Prefix                   : 2001:db8:a::/64
  On-link                 :          Yes
  Autonomous address conf.:          Yes
  Valid time              :        86400 (0x00015180) seconds
  Pref. time              :        14400 (0x00003840) seconds
 Source link-layer address: 52:54:00:A1:00:FE
 from fe80::5054:ff:fea1:fe
```

Find in the output: the prefix, the two flags you set (`On-link`, `Autonomous`), how long r1 may be used as a default router (`Router lifetime`), and who sent it (`from fe80::5054:ff:fea1:fe`, r1's link-local address).

#### How to read this

The top part is about the **router**, the indented part about the **prefix**.

| Line | What it tells the host |
|---|---|
| `Hop limit : 64` | Use hop limit 64 in packets you send |
| `Stateful address conf.` / `Stateful other conf.` | Flags for another configuration method (a later day). `No` means: use SLAAC alone |
| `Router lifetime : 30` | Use me as your **default gateway** for 30 seconds. radvd's default is 3 x `MaxRtrAdvInterval`. Each new RA renews it |
| `Reachable time`, `Retransmit time` | Neighbor Discovery timers. `unspecified` = use your own defaults |
| `On-link : Yes` / `Autonomous address conf. : Yes` | Your two flags from C2 |
| `Valid time : 86400` | An address from this prefix exists for 1 day unless renewed |
| `Pref. time : 14400` | For 4 hours it is **preferred** for new connections |
| `Source link-layer address` | r1's MAC, so pc1 needs no NS to find r1 |

**Explain why:** why does the RA come from r1's link-local address, not `2001:db8:a::1`?

<details>
<summary>▶ Answer</summary>

Hosts use RAs before they have any global address, and a router's global addresses may change. The link-local address always exists, so it is the stable way to name the router. Hosts then use it as their gateway (C5).
</details>

### C5. See what pc1 configured by itself

**Predict first:** write down the global address pc1 will build (prefix from the RA, interface ID from A2).

<details>
<summary>▶ Answer</summary>

`2001:db8:a:0:5054:ff:fea1:1`: prefix `2001:db8:a:0` plus pc1's EUI-64 interface ID.
</details>

**Terminal 1 (pc1):**

```
ip -6 addr show dev eth0
```

**Expected:** a new global address:

```
    inet6 2001:db8:a:0:5054:ff:fea1:1/64 scope global dynamic mngtmpaddr
       valid_lft 86390sec preferred_lft 14390sec
    inet6 fe80::5054:ff:fea1:1/64 scope link
       valid_lft forever preferred_lft forever
```

The first 64 bits came from r1's prefix (`2001:db8:a:0`). The last 64 bits are the same interface ID as the link-local address (`5054:ff:fea1:1`). pc1 built the address itself: that is **SLAAC** (Stateless Address Autoconfiguration).

#### How to read this

- `dynamic`: learned from an RA. It lives only as long as RAs keep renewing it. r1's hand-made address did not have this.
- `mngtmpaddr`: the base for privacy (temporary) addresses. You use that in Part K.
- `preferred_lft 14390sec`: time left to use this address for **new** connections (from `Pref. time`).
- `valid_lft 86390sec`: time left before the address is removed (from `Valid time`).
- Every new RA resets both counters, so while r1 advertises, the address never runs out.

Two lifetimes let a network move to a new prefix gently: stop preferring the old one (no new connections) while it stays valid (running connections continue). You try this in stretch S2.

Now the routing table. `ip -6 route` shows where pc1 sends each destination.

```
ip -6 route
```

**Expected:**

```
2001:db8:a::/64 dev eth0 proto kernel metric 256 expires 86390sec pref medium
fe80::/64 dev eth0 proto kernel metric 256 pref medium
default via fe80::5054:ff:fea1:fe dev eth0 proto ra metric 1024 expires 28sec hoplimit 64 pref medium
```

#### How to read this

- `2001:db8:a::/64 dev eth0`: this prefix is on the link (from `AdvOnLink on`). It expires with the prefix's valid lifetime.
- `fe80::/64 dev eth0`: link-local is always on the link.
- `default via ...`: everything else goes to r1. `expires 28sec` is the 30-second router lifetime counting down.

:::success
Look closely at the default route: `via fe80::5054:ff:fea1:fe`. The default gateway is r1's **link-local** address, not `2001:db8:a::1`. Hosts always learn their gateway from the source of the Router Advertisement, which is a link-local address. `proto ra` means "learned from a Router Advertisement".
:::

**Explain why:** the default route expires in 28 seconds. Why is it still there a minute later?

<details>
<summary>▶ Answer</summary>

Each RA (every 3 to 10 seconds) resets the router lifetime to 30 seconds. The route disappears only if RAs stop for 30 seconds, for example when the router fails. That is how hosts stop using a dead router.
</details>

### C6. Ping across the new global addresses

pc2 got its own global address the same way: `2001:db8:a:0:5054:ff:fea1:2`.

The first ping tests pc2's SLAAC address, the second r1's hand-made address.

**Terminal 1 (pc1):**

```
ping -6 -c2 2001:db8:a:0:5054:ff:fea1:2
ping -6 -c2 2001:db8:a::1
```

**Expected:** `2 packets transmitted, 2 received, 0% packet loss` for both. Global addresses need no `%eth0`.

**Explain why:** why is no zone ID needed now?

<details>
<summary>▶ Answer</summary>

pc1's routing table says `2001:db8:a::/64 dev eth0`, so pc1 knows the interface. `fe80::/64` exists on every interface, so only a zone ID can choose.
</details>

### C7 (optional). Watch the Router Advertisements arrive

Routers also send RAs unasked, on a timer. This filter keeps only ICMPv6 type 134.

**Terminal 2 (pc2):**

```
tcpdump -ni eth0 'icmp6 and ip6[40] == 134'
```

`ip6[40]` is the first byte after the 40-byte IPv6 header, which is the ICMPv6 type. 134 is Router Advertisement.

**Expected:** a new line every 3 to 10 seconds:

```
IP6 fe80::5054:ff:fea1:fe > ff02::1: ICMP6, router advertisement, length 56
```

They go to `ff02::1`, all nodes. Press **Ctrl+C** to stop.

One RA to all nodes updates every host's lifetimes and default route at once.

---

## Part D: Duplicate Address Detection (DAD) (10 min)

*From today's lecture: Module 2, Unspecified Address; Module 3, Neighbor Discovery Protocol (DAD).*

Before an interface uses a new address, it asks the link "is anyone already using this?". If someone is, the address is not used.

:::info
**Why this matters.** A new address starts as **tentative**. The node sends an NS for its own new address; if anyone answers, the address is a duplicate and is not used. If nobody answers in about a second, it becomes usable. Every IPv6 address goes through DAD, link-local and SLAAC ones too. Duplicate addresses are hard to troubleshoot: traffic goes sometimes to one device, sometimes to the other. A server configured with the router's address by mistake could cut off a whole link. DAD stops the newcomer first.
:::

### D1. Try to steal r1's address

You give pc1 the address r1 already uses. `sleep 3` gives DAD time to finish before you look.

**Predict first:** will pc1 use the address? Will r1 notice any problem?

<details>
<summary>▶ Answer</summary>

No and no. DAD runs **before** pc1 uses the address, so pc1 never sends from it, and r1 just answers the check.
</details>

**Terminal 1 (pc1):**

```
ip -6 addr add 2001:db8:a::1/64 dev eth0
sleep 3; ip -6 addr show dev eth0
```

**Expected:** the stolen address is marked as failed:

```
    inet6 2001:db8:a::1/64 scope global dadfailed tentative
```

`tentative` means "still being checked". `dadfailed` means r1 answered that it already owns the address, so pc1 will never use it.

#### How to read this

pc1 sent an NS "who has `2001:db8:a::1`?" to that address's solicited-node group, `ff02::1:ff00:1`, which r1 has joined. r1 answered with an NA, so pc1 marked the address `dadfailed`. The dead address stays in the list until you remove it. Part E shows the DAD packet itself.

### D2. Remove it

A failed address is useless and would confuse the self-check, so delete exactly what you added.

**Terminal 1 (pc1):**

```
ip -6 addr del 2001:db8:a::1/64 dev eth0
```

**Expected:** no output. Run `ip -6 addr show dev eth0` and check that `2001:db8:a::1` is gone.

pc1's SLAAC and link-local addresses are still there.

---

## Part E: Watch Duplicate Address Detection on the wire (10 min)

*From today's lecture: Module 2, Unspecified Address (`::` as a source during DAD); Module 3, Neighbor Discovery Protocol (DAD).*

:::info
**Why this matters.** Part D showed only the result of DAD. Here you see the packet: an NS for the new address, sent from the **unspecified address** `::` to the address's solicited-node group. Every device sends these for every new address, so you need to recognise them in a capture and not mistake them for normal lookups.
:::

### E1. Capture only Neighbor Solicitations

The filter `ip6[40] == 135` looks at the first byte after the 40-byte IPv6 header, which is the ICMPv6 type (see C7). Type 135 is Neighbor Solicitation. Pings and RAs are hidden, so the DAD packet is easy to spot.

**Terminal 2 (pc2):**

```
tcpdump -ni eth0 'icmp6 and ip6[40] == 135'
```

**Expected:** `listening on eth0, ...`. Leave it running.

### E2. Add a new, unused address on pc1

Nobody uses `2001:db8:a::99`, so adding it starts a DAD check that should pass.

**Predict first:** what source and destination will the DAD packet have?

<details>
<summary>▶ Answer</summary>

Source `::`. Destination `ff02::1:ff00:99`, the solicited-node group of `2001:db8:a::99`.
</details>

**Terminal 1 (pc1):**

```
ip -6 addr add 2001:db8:a::99/64 dev eth0
```

**Expected** in Terminal 2 (pc2):

```
IP6 :: > ff02::1:ff00:99: ICMP6, neighbor solicitation, who has 2001:db8:a::99, length 32
```

The source is `::`, the **unspecified address**. pc1 may not use `2001:db8:a::99` until DAD has finished, so it asks without a source address.

#### How to read this

A source of `::` is how you recognise DAD; compare B3, where the NS came from pc1's link-local address. There is only one line because nobody answered, so the address became usable after about a second.

**Explain why:** in Part D, r1 answered a DAD check from `::`. Where could r1 send its answer?

<details>
<summary>▶ Answer</summary>

To `ff02::1`, all nodes. The asker has no usable address yet, but it is in the all-nodes group.
</details>

### E3. Put it back

Remove the test address so later steps start clean. The self-check tests that it is gone.

**Terminal 1 (pc1):**

```
ip -6 addr del 2001:db8:a::99/64 dev eth0
```

In **Terminal 2 (pc2)**, press **Ctrl+C** to stop the capture.

---

## Part F: Multicast groups (10 min)

*From today's lecture: Module 2, Multicast Addresses (`ff02::1`, `ff02::2`, scope); Module 3, Neighbor Discovery Protocol (solicited-node multicast).*

:::info
**Why this matters.** IPv6 replaces broadcast with multicast groups, each with a meaning: `ff02::1` all nodes, `ff02::2` all routers, `ff02::1:ffXX:XXXX` one solicited-node group per address. Neighbor Discovery and Router Solicitations depend on them. A router that is not in `ff02::2` never hears Router Solicitations, so new hosts wait longer to configure themselves.
:::

### F1. Compare pc1 and r1

**Predict first:** which group will r1 have that pc1 does not?

Run this in **Terminal 1 (pc1)** and in **Terminal 3 (r1)**:

```
ip -6 maddr show dev eth0
```

**Expected:** both have `ff02::1` and their own `ff02::1:ff...` groups. Only r1 also has `ff02::2`.

#### How to read this

- pc1's link-local and global addresses both end in `a1:00:01`, so they share one solicited-node group, `ff02::1:ffa1:1`.
- r1 also has `2001:db8:a::1` (ending `00:00:01`), so it is in `ff02::1:ffa1:fe` and `ff02::1:ff00:1`. You also see `ff02::1:ff00:0` on r1: Part I shows which address it belongs to.
- The fourth hex digit of a multicast address is its **scope**: `2` = link, `5` = site. r1 also lists `ff05::2`, the all-routers group with site scope. Groups that start with `ff01` (scope `1`) never leave the node itself.

<details>
<summary>▶ Why only r1?</summary>

`ff02::2` is the **all-routers** group. A node joins it when forwarding is on, and you turned forwarding on for r1 in C1. radvd also makes sure r1 is in it, because Router Solicitations are sent there.
</details>

### F2. Ping all routers

The same ping reaches different nodes depending only on the group address.

**Terminal 1 (pc1):**

```
ping -6 -c2 ff02::2%eth0
```

**Expected:** replies only from `fe80::5054:ff:fea1:fe` (r1). Compare with:

```
ping -6 -c2 ff02::1%eth0
```

where every node replies.

### F3. Ping pc2's solicited-node group

First work out pc2's solicited-node address from its global address `2001:db8:a:0:5054:ff:fea1:2`: `ff02::1:ff` plus the last 24 bits.

<details>
<summary>▶ Answer</summary>

The last 24 bits are `a1:00:02`, so the group is `ff02::1:ffa1:2`. It is the same group as for pc2's link-local address, because both addresses end in the same 24 bits.
</details>

**Terminal 1 (pc1):**

```
ping -6 -c2 ff02::1:ffa1:2%eth0
```

**Expected:** only pc2 replies. That is why a Neighbor Solicitation disturbs one host instead of the whole link.

**Explain why:** two addresses can end in the same 24 bits. Does that break Neighbor Discovery?

<details>
<summary>▶ Answer</summary>

No. Both owners join the same group and both receive the NS, but the NS names the full target address, so only the real owner answers. The group only needs to keep the list of listeners small.
</details>

---

## Part G: Add a Unique Local (ULA) prefix (20 min)

*From today's lecture: Module 2, Unique Local Addresses (ULA) and Address Types & Scopes; Module 3, Neighbor Discovery Protocol (SLAAC).*

:::info
**Why this matters.** A **Unique Local Address** (ULA, `fd00::/8`) is the IPv6 match for IPv4 private addresses: it works inside an organisation but is not routed on the Internet. Many networks give each LAN a ULA prefix **next to** the global one. Internal servers then keep the same ULA addresses even when the internet provider, and so the global prefix, changes. One router can announce both prefixes in the same Router Advertisement, and every host builds one address from each. On a real network you will see several unicast addresses on every interface, and you must tell them apart.
:::

### G1. Read the ULA prefix on paper

The lab uses the ULA prefix `fd12:3456:789a:1::/64`. Split it into the parts from the lecture slide:

| Part | Bits | In this prefix |
|---|---|---|
| `fd` | 8 | `fd`: a locally assigned ULA |
| Global ID | 40 | `12:3456:789a` |
| Subnet ID | 16 | `0001` (written `1`) |
| Interface ID | 64 | built by each host |

On a real network you choose the 40-bit Global ID **at random**, so two companies that merge later do not have the same prefix. This lab uses an easy-to-read one.

**Predict first:** r1 will announce this prefix with `AdvAutonomous on`. Write down the ULA address pc1 will build.

<details>
<summary>▶ Answer</summary>

`fd12:3456:789a:1:5054:ff:fea1:1`: the ULA prefix plus pc1's EUI-64 interface ID from A2. SLAAC works the same way for every prefix.
</details>

### G2. Give r1 a ULA address and announce the prefix

Two changes on r1, as in Part C: a fixed address in the new prefix for r1 itself, and a second `prefix` block in radvd's file. radvd reads its file only when it starts, so the box ends with `pkill radvd; sleep 1; radvd`: stop it, wait, start it with the new file.

**Terminal 3 (r1):** paste this whole box:

```
ip -6 addr add fd12:3456:789a:1::1/64 dev eth0
cat > /etc/radvd.conf <<'EOF'
interface eth0 {
    AdvSendAdvert on;
    MinRtrAdvInterval 3;
    MaxRtrAdvInterval 10;
    prefix 2001:db8:a::/64 {
        AdvOnLink on;
        AdvAutonomous on;
    };
    prefix fd12:3456:789a:1::/64 {
        AdvOnLink on;
        AdvAutonomous on;
    };
};
EOF
pkill radvd; sleep 1; radvd
```

**Expected:** no output. Check that radvd runs again with `pgrep -a radvd`.

:::info
When radvd stops, it sends a last advertisement with a router lifetime of 0, so pc1 and pc2 drop their default route for a few seconds. The next RA brings it back. Keep this file: later parts and the self-check use it.
:::

### G3. See both prefixes in one Router Advertisement

**Terminal 1 (pc1):**

```
rdisc6 eth0
```

**Expected:** the same router part as in C4, then **two** prefix blocks:

```
 Prefix                   : 2001:db8:a::/64
  On-link                 :          Yes
  Autonomous address conf.:          Yes
  Valid time              :        86400 (0x00015180) seconds
  Pref. time              :        14400 (0x00003840) seconds
 Prefix                   : fd12:3456:789a:1::/64
  On-link                 :          Yes
  Autonomous address conf.:          Yes
  Valid time              :        86400 (0x00015180) seconds
  Pref. time              :        14400 (0x00003840) seconds
 Source link-layer address: 52:54:00:A1:00:FE
 from fe80::5054:ff:fea1:fe
```

#### How to read this

One RA carries one router part and any number of prefix parts. Each prefix has its own flags and lifetimes. The RA still comes from r1's link-local address, whatever prefixes it carries.

### G4. See pc1's new address and route

**Terminal 1 (pc1):**

```
ip -6 addr show dev eth0
```

**Expected:** three addresses (the newest is listed first):

```
    inet6 fd12:3456:789a:1:5054:ff:fea1:1/64 scope global dynamic mngtmpaddr
       valid_lft 86395sec preferred_lft 14395sec
    inet6 2001:db8:a:0:5054:ff:fea1:1/64 scope global dynamic mngtmpaddr
       valid_lft 86390sec preferred_lft 14390sec
    inet6 fe80::5054:ff:fea1:1/64 scope link
       valid_lft forever preferred_lft forever
```

Check it against your prediction in G1.

#### How to read this

- Both global-looking addresses end in the same interface ID, `5054:ff:fea1:1`. SLAAC builds one address per autonomous prefix.
- The ULA shows `scope global`, not "site". The lecture puts ULA in **site scope**: it must stay inside the organisation. Linux's scope column knows only `host`, `link` and `global`. Keeping ULA traffic inside the site is the job of the routers and firewalls at the edge of the site, not of the host.

Now the routes:

```
ip -6 route
```

**Expected:** a new on-link route for the ULA prefix:

```
2001:db8:a::/64 dev eth0 proto kernel metric 256 expires 86390sec pref medium
fd12:3456:789a:1::/64 dev eth0 proto kernel metric 256 expires 86395sec pref medium
fe80::/64 dev eth0 proto kernel metric 256 pref medium
default via fe80::5054:ff:fea1:fe dev eth0 proto ra metric 1024 expires 28sec hoplimit 64 pref medium
```

`AdvOnLink on` told pc1 that `fd12:3456:789a:1::/64` is on its own link, so pc1 reaches those addresses directly, with Neighbor Discovery. There is still one default route: one router, one gateway.

### G5. Ping over the ULA addresses

pc2 built `fd12:3456:789a:1:5054:ff:fea1:2` the same way.

**Terminal 1 (pc1):**

```
ping -6 -c2 fd12:3456:789a:1::1
ping -6 -c2 fd12:3456:789a:1:5054:ff:fea1:2
```

**Expected:** `2 packets transmitted, 2 received, 0% packet loss` for both: r1's hand-made ULA and pc2's SLAAC ULA.

**Explain why:** the internet provider changes the global prefix from `2001:db8:a::/64` to another one tomorrow. Which of pc1's addresses change, and why does that matter for a printer or a file server on this LAN?

<details>
<summary>▶ Answer</summary>

Only the global address changes. The link-local and the ULA addresses stay the same, because they do not depend on the provider. If internal users reach the printer or the file server by its ULA address, nothing inside the company has to change. This is the "stable internal addressing" from the ULA slide.
</details>

---

## Part H: Every address has a type and a scope (15 min)

*From today's lecture: Module 2, Address Types & Scopes; Module 2, Special Unicast: Loopback Address and Unspecified Address; Module 3, NAT64/DNS64 (`64:ff9b::/96`).*

:::info
**Why this matters.** A single IPv6 host has many addresses at once: loopback, link-local, global, ULA, and several multicast groups. When you troubleshoot, the first question about any address is "what type is it, and how far does it reach?". A link-local address used where a global one is needed, or a ULA used to reach the Internet, explains many "it works here but not there" problems. You can tell the type from the first hex digits.
:::

### H1. The loopback address

`::1` is the IPv6 loopback address, the match for IPv4 `127.0.0.1`. It sits on the interface `lo`, not on `eth0`.

**Terminal 1 (pc1):**

```
ip -6 addr show dev lo
```

**Expected** (after the first line, which names `lo`):

```
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
```

(Newer Linux versions add `noprefixroute` after `scope host`. It does not change anything here.)

Ping it, then ask the kernel where a packet to `::1` would go. `ip -6 route get` asks the kernel which route it would use for a destination; nothing is sent.

```
ping -6 -c2 ::1
ip -6 route get ::1
```

**Expected:** two replies `from ::1` with a very short time, then:

```
local ::1 dev lo table local proto kernel src ::1 metric 0 pref medium
```

#### How to read this

- `/128`: the prefix is the whole address. Loopback is one single address, not a subnet.
- `scope host`: the address is valid only inside this node.
- `dev lo` and `local`: the packet stays inside pc1. It never reaches eth0, so no capture on the link can see it.

Use `ping -6 ::1` to test the IPv6 software of a host without any network: if it fails, the problem is inside the host.

### H2. List every address on pc1 and name its type

**Terminal 1 (pc1):**

```
ip -6 addr show
ip -6 maddr show dev eth0
```

The first command, without `dev`, lists the addresses of every interface. The second lists the multicast groups of eth0 (Part F).

Fill in this table on paper, one row for each address you see:

| Address | Type | Scope (lecture) | What Linux prints |
|---|---|---|---|
| `::1` | | | |
| `fe80::5054:ff:fea1:1` | | | |
| `2001:db8:a:0:5054:ff:fea1:1` | | | |
| `fd12:3456:789a:1:5054:ff:fea1:1` | | | |
| `ff02::1` | | | |
| `ff02::1:ffa1:1` | | | |

<details>
<summary>▶ Answer</summary>

| Address | Type | Scope (lecture) | What Linux prints |
|---|---|---|---|
| `::1` | Loopback (unicast) | This node only | `scope host` |
| `fe80::5054:ff:fea1:1` | Link-local unicast (LLA) | Link | `scope link` |
| `2001:db8:a:0:5054:ff:fea1:1` | Global unicast (GUA), from the documentation range `2001:db8::/32` | Global | `scope global` |
| `fd12:3456:789a:1:5054:ff:fea1:1` | Unique local (ULA) | Site (inside the organisation) | `scope global` |
| `ff02::1` | Multicast, all nodes | Link (`2` in `ff02`) | listed by `ip -6 maddr` |
| `ff02::1:ffa1:1` | Multicast, solicited-node | Link | listed by `ip -6 maddr` |

pc1 has four unicast addresses but only one solicited-node group, because its link-local, global and ULA addresses all end in `a1:00:01`. (You may also see `ff01::1`: all nodes, but only inside the node itself.)
</details>

**Explain why:** the unspecified address `::` is a special address from the same lecture slide set, but it is not in your list. Why not, and where did you see it today?

<details>
<summary>▶ Answer</summary>

`::` is never assigned to an interface. A node uses it only as a **source** while it has no usable address yet. You saw it in Part E, as the source of the DAD Neighbor Solicitation.
</details>

### H3. Read the type from the first digits

Without running anything, write the type of each address. Use the first hex digits and the special addresses from the lecture.

1. `fe80::a8:1`
2. `2001:db8:a::1`
3. `fd00:1:2:3::5`
4. `ff02::2`
5. `::`
6. `::1`
7. `64:ff9b::198.51.100.10`
8. `fd12:3456:789a:1::`

<details>
<summary>▶ Answers</summary>

1. Link-local unicast: starts with `fe80`.
2. Global unicast: starts with `2` (inside `2000::/3`), here from the documentation range.
3. Unique local: starts with `fd`.
4. Multicast: starts with `ff`. `ff02::2` is all routers on the link.
5. Unspecified address.
6. Loopback address.
7. The NAT64 well-known prefix `64:ff9b::/96` from Module 3. The last 32 bits carry an IPv4 address, `198.51.100.10`. A NAT64 gateway translates packets to this address into IPv4.
8. It looks like an ordinary ULA. In fact it is r1's prefix with an interface ID of all zeros. Part I shows what it is.
</details>

---

## Part I: An anycast address on r1 (15 min)

*From today's lecture: Module 2, Anycast Addresses.*

:::info
**Why this matters.** An **anycast** address is given to several interfaces, usually on different devices, and a packet sent to it reaches the nearest one. It looks exactly like a unicast address: there is no special prefix, only configuration makes it anycast. So you cannot see from the address itself that it is anycast; you must look at the device's configuration. Every IPv6 router has one anycast address on each of its links, and Linux adds it by itself when forwarding is on. It is the **subnet-router anycast** address: the subnet prefix followed by an interface ID of all zeros. A host can send to it to reach "a router on this subnet" without knowing which one.
:::

### I1. Look for r1's anycast addresses

**Predict first:** r1's subnet prefixes are `2001:db8:a::/64`, `fd12:3456:789a:1::/64` and `fe80::/64`. Write down the three subnet-router anycast addresses r1 should have.

<details>
<summary>▶ Answer</summary>

`2001:db8:a::`, `fd12:3456:789a:1::` and `fe80::`: each prefix with an interface ID of all zeros.
</details>

First look where you would look for any address. **Terminal 3 (r1):**

```
ip -6 addr show dev eth0
```

**Expected:** the same three unicast addresses as before (`2001:db8:a::1`, `fd12:3456:789a:1::1`, `fe80::5054:ff:fea1:fe`). No anycast address is listed: `ip addr` shows only unicast addresses.

The kernel keeps a list of every address that the node accepts as its own: the **local routing table**. Show it:

```
ip -6 route show table local
```

**Expected** (the order of the lines may differ):

```
local ::1 dev lo proto kernel metric 0 pref medium
anycast 2001:db8:a:: dev eth0 proto kernel metric 0 pref medium
local 2001:db8:a::1 dev eth0 proto kernel metric 0 pref medium
anycast fd12:3456:789a:1:: dev eth0 proto kernel metric 0 pref medium
local fd12:3456:789a:1::1 dev eth0 proto kernel metric 0 pref medium
anycast fe80:: dev eth0 proto kernel metric 0 pref medium
local fe80::5054:ff:fea1:fe dev eth0 proto kernel metric 0 pref medium
multicast ff00::/8 dev eth0 proto kernel metric 256 pref medium
```

#### How to read this

- `local`: a unicast address of this node. Packets to it are delivered to r1 itself.
- `anycast`: an anycast address of this node. Packets to it are also delivered to r1 itself. Nobody typed these three lines: Linux added them because forwarding is on (C1).
- `multicast ff00::/8`: multicast is sent out of eth0 (Part F).

The anycast addresses also explain the group `ff02::1:ff00:0` you saw on r1 in F1. All three end in `00:00:00`, so they share that one solicited-node group, and pc1 can find r1's MAC for them with Neighbor Discovery.

### I2. Compare with pc1

**Predict first:** will pc1's local table have `anycast` lines?

**Terminal 1 (pc1):**

```
ip -6 route show table local
```

**Expected:** `local` lines for pc1's own four unicast addresses (`::1`, link-local, global, ULA), one `multicast ff00::/8` line, and **no** `anycast` line.

<details>
<summary>▶ Why?</summary>

pc1 is a host: forwarding is off. Only routers get the subnet-router anycast address.
</details>

### I3. Send to the anycast address

**Terminal 1 (pc1):**

```
ping -6 -c2 2001:db8:a::
ip -6 neigh show dev eth0
```

**Expected:** two replies, then a neighbor entry for the anycast address with **r1's MAC**:

```
2001:db8:a:: lladdr 52:54:00:a1:00:fe router REACHABLE
```

(Other entries, for example for pc2 or r1's link-local address, may also be listed.)

#### How to read this

- pc1 found the owner of `2001:db8:a::` with an ordinary Neighbor Solicitation, and r1 answered. The first reply may take up to a second: a node answers an NS for an anycast address after a short random wait, because several nodes may answer at once.
- `router`: the answer came from a node with forwarding on.
- Look at the ping replies: they come `from 2001:db8:a::1`, not from `2001:db8:a::`. Linux does not use a shared anycast address as the source of its reply; it uses its own unicast address instead.

**Explain why:** a second router joins this link and also has forwarding on. What happens to `2001:db8:a::`?

<details>
<summary>▶ Answer</summary>

Both routers now have `2001:db8:a::`. That is what anycast means: one address on several interfaces. A packet to it reaches one of them, and the sender does not need to know which. On a link, the host takes the answer to its Neighbor Solicitation; across a network, routing picks the nearest one. The lecture's examples, DNS root servers and CDNs, use the same idea on the Internet.
</details>

---

## Part J: Write addresses and prefixes (20 min)

*From today's lecture: Module 2, IPv6 Address Structure, Shortening Rules 1 and 2, Prefix Notation & Subnetting; Module 3, NAT64/DNS64 (`64:ff9b::/96`).*

:::info
**Why this matters.** Linux, routers, firewalls and logs all print addresses in short form, and not always the same short form. To compare two addresses, or to check that an address is inside a prefix, you must be able to expand and shorten them by hand. Firewall rules and route entries are written as prefixes, so you also need to read what a `/48` or a `/64` contains. `sipcalc`, installed on every node, checks your work.
:::

### J1. Look at a full address with sipcalc

`sipcalc` prints one address in several forms, so you can see what the short forms hide.

**Terminal 2 (pc2):**

```
sipcalc 2001:db8:a:0:5054:ff:fea1:2/64
```

**Expected** (part of the output):

```
Expanded Address	- 2001:0db8:000a:0000:5054:00ff:fea1:0002
Compressed address	- 2001:db8:a::5054:ff:fea1:2
...
Network range		- 2001:0db8:000a:0000:0000:0000:0000:0000 -
			  2001:0db8:000a:0000:ffff:ffff:ffff:ffff
```

The expanded form shows every hidden zero. `::` in the compressed form stands for one run of zero blocks.

#### How to read this

- `Expanded Address`: all 8 blocks of 4 hex digits, the real 128 bits.
- `Compressed address`: leading zeros removed, the zero block replaced by `::`. Linux wrote the same address as `2001:db8:a:0:5054:...` in C5. Both mean the same; the recommended form writes a single zero block as `0`.
- `Network range`: a `/64` leaves 64 bits for interface IDs, so hosts can choose their own IDs with no central list.

### J2. Expand addresses from today's outputs

Write each address in full: 8 blocks of 4 hex digits. First put back the leading zeros in each block (Rule 1 in reverse), then count the blocks you have and fill `::` with as many `0000` blocks as you need to reach 8 (Rule 2 in reverse).

1. `fe80::5054:ff:fea1:1` (pc1's link-local address)
2. `ff02::1:ffa1:2` (pc2's solicited-node group)
3. `fd12:3456:789a:1::1` (r1's ULA address)
4. `2001:db8:a::` (r1's anycast address)

<details>
<summary>▶ Answers</summary>

1. `fe80:0000:0000:0000:5054:00ff:fea1:0001`
2. `ff02:0000:0000:0000:0000:0001:ffa1:0002`
3. `fd12:3456:789a:0001:0000:0000:0000:0001`
4. `2001:0db8:000a:0000:0000:0000:0000:0000`

In 2, four blocks are written (`ff02`, `1`, `ffa1`, `2`), so `::` stands for 8 - 4 = 4 zero blocks.
</details>

Check each answer. **Terminal 2 (pc2):** for example:

```
sipcalc ff02::1:ffa1:2 | grep Expanded
```

**Expected:**

```
Expanded Address	- ff02:0000:0000:0000:0000:0001:ffa1:0002
```

`grep Expanded` keeps only the line you need. Do the same for the other three addresses.

### J3. Shorten addresses

Write the shortest form. Rule 1: drop leading zeros in each block. Rule 2: replace **one** run of zero blocks with `::`. Use the longest run; if two runs are equally long, use the first. Write a single zero block as `0`.

1. `2001:0db8:0000:0000:0001:0000:0000:0001`
2. `fd12:3456:789a:0001:0000:0000:0000:00fe`
3. `2001:0db8:000a:0000:5054:00ff:fea1:0001`
4. `ff02:0000:0000:0000:0000:0000:0000:0002`
5. `0000:0000:0000:0000:0000:0000:0000:0001`

<details>
<summary>▶ Answers</summary>

1. `2001:db8::1:0:0:1`. Both zero runs have two blocks, so the first one becomes `::`. With two `::` nobody could tell how many zeros each one hides.
2. `fd12:3456:789a:1::fe`
3. `2001:db8:a:0:5054:ff:fea1:1`. The only zero run is one block, so it stays `0`. `2001:db8:a::5054:ff:fea1:1` (what sipcalc printed in J1) is also valid, but not the recommended form.
4. `ff02::2`, the all-routers group.
5. `::1`, the loopback address.
</details>

Check: an address is written correctly if it expands back to the long form. Run sipcalc on your short answer and compare its `Expanded Address` with the address in the list. For example:

```
sipcalc 2001:db8::1:0:0:1 | grep Expanded
```

**Expected:** `Expanded Address	- 2001:0db8:0000:0000:0001:0000:0000:0001`, the same as address 1.

### J4. An IPv4 address inside an IPv6 address

In Module 3, a NAT64 address is the prefix `64:ff9b::/96` plus a 32-bit IPv4 address, for example `64:ff9b::198.51.100.10`. The dotted form is a convenience; the address is still 128 bits of hex.

**Predict first:** write `64:ff9b::198.51.100.10` in normal hex form. Convert each IPv4 byte to two hex digits.

<details>
<summary>▶ Answer</summary>

198 = `c6`, 51 = `33`, 100 = `64`, 10 = `0a`. The last two blocks are `c633:640a`, so the address is `64:ff9b::c633:640a`.
</details>

Check it:

```
sipcalc 64:ff9b::c633:640a | grep Expanded
```

**Expected:** `Expanded Address	- 0064:ff9b:0000:0000:0000:0000:c633:640a`. The last 32 bits are the IPv4 address. `/96` is exactly 128 - 32: the prefix leaves room for one IPv4 address.

### J5. Prefixes and subnets

The ULA prefix of this whole "organisation" is `fd12:3456:789a::/48`: `fd` (8 bits) plus the 40-bit Global ID. The LAN in this lab is one `/64` inside it.

**Terminal 2 (pc2):**

```
sipcalc fd12:3456:789a::/48
```

**Expected** (part of the output):

```
Network range		- fd12:3456:789a:0000:0000:0000:0000:0000 -
			  fd12:3456:789a:ffff:ffff:ffff:ffff:ffff
```

Answer these on paper:

1. How many `/64` subnets fit into this `/48`?
2. Which subnet ID does this lab's LAN, `fd12:3456:789a:1::/64`, use?
3. Write the `/64` with subnet ID `00ff`, and the last `/64` of the `/48`.
4. Is `fd12:3456:789b:1::1` inside the `/48`?

<details>
<summary>▶ Answers</summary>

1. 65,536. A `/48` leaves 64 - 48 = 16 bits for the subnet ID, and 2 to the power of 16 is 65,536. This is the number from the subnetting slide.
2. Subnet ID `0001`, the fourth block.
3. `fd12:3456:789a:ff::/64` and `fd12:3456:789a:ffff::/64`.
4. No. The third block is `789b`, not `789a`, so it is in a different `/48`. Every address in the range above starts with `fd12:3456:789a`.
</details>

Check question 3 with sipcalc:

```
sipcalc fd12:3456:789a:ff::/64
```

**Expected:** `Network range` from `fd12:3456:789a:00ff:0000:0000:0000:0000` to `fd12:3456:789a:00ff:ffff:ffff:ffff:ffff`.

---

## Part K: Privacy addresses (10 min)

*From today's lecture: Module 2, Interface Identifiers (Random/Temporary IIDs, Privacy Extensions, RFC 4941).*

An EUI-64 address carries your MAC address. Every server you talk to can see it and follow your device from network to network. **Temporary addresses** (RFC 4941) fix that with a random interface ID that changes over time.

:::info
**Why this matters.** With temporary addresses on, a host keeps its normal SLAAC address and adds a second one from the same prefix with a **random** interface ID and shorter lifetimes. Before it expires, a new one replaces it. Most laptops and phones do this by default, so on a real network expect several global addresses per device, changing over time. An address in a log then points to a device only for a limited time.
:::

### K1. Turn on temporary addresses on pc2

- `use_tempaddr=2`: `0` = off, `1` = make temporary addresses but prefer the normal one, `2` = make them **and prefer them** for new connections.
- `ip link set eth0 down; ip link set eth0 up`: restarts address configuration with the new setting.

**Predict first:** pc2 gets two prefixes from r1 (Part G). How many global addresses will pc2 have? Will the EUI-64 ones disappear?

<details>
<summary>▶ Answer</summary>

Four. For each prefix, the EUI-64 address stays, because temporary addresses are made from it, and one temporary address is added.
</details>

**Terminal 2 (pc2):** run these lines one after the other:

```
sysctl -w net.ipv6.conf.eth0.use_tempaddr=2
ip link set eth0 down; ip link set eth0 up
sleep 8; ip -6 addr show dev eth0
```

The second line restarts the interface so it picks up the new setting. The `sleep 8` waits for the next Router Advertisement.

**Expected:** for each prefix, one more address marked `temporary`, with a random-looking interface ID:

```
    inet6 fd12:3456:789a:1:6d1c:2b9e:f04a:7c31/64 scope global temporary dynamic
    inet6 fd12:3456:789a:1:5054:ff:fea1:2/64 scope global dynamic mngtmpaddr
    inet6 2001:db8:a:0:8c3e:41f2:9a07:5d1b/64 scope global temporary dynamic
    inet6 2001:db8:a:0:5054:ff:fea1:2/64 scope global dynamic mngtmpaddr
    inet6 fe80::5054:ff:fea1:2/64 scope link
```

Your random parts will be different (lifetime lines are left out here). `mngtmpaddr` marks the EUI-64 address that temporary addresses are made from. With `use_tempaddr=2` pc2 **prefers** the temporary address for connections it starts.

#### How to read this

`temporary dynamic`: a privacy address made from an RA prefix. Its interface ID has no `ff:fe`, so it does not reveal the MAC. All four global addresses work; only the **source** address pc2 chooses for new outgoing connections changes. The link-local address keeps its EUI-64 interface ID: temporary addresses are made only from RA prefixes.

:::warning
No `temporary` address yet? Wait 10 seconds and run `ip -6 addr show dev eth0` again.
:::

**Explain why:** why does pc2 keep the EUI-64 addresses as well?

<details>
<summary>▶ Answer</summary>

Others need an address for pc2 that does not change, for example to connect to it. The temporary one is for connections pc2 starts. (Stretch S4 makes the stable address private too.)
</details>

### K2. Put it back

Part L reads addresses in captures, and the self-check expects no temporary address. Turn temporary addresses off again (`use_tempaddr=0`) and restart the interface.

**Terminal 2 (pc2):**

```
sysctl -w net.ipv6.conf.eth0.use_tempaddr=0
ip link set eth0 down; ip link set eth0 up
sleep 8; ip -6 addr show dev eth0
```

**Expected:** `fd12:3456:789a:1:5054:ff:fea1:2`, `2001:db8:a:0:5054:ff:fea1:2` and `fe80::5054:ff:fea1:2`, and no `temporary` address.

The interface restart removed the old temporary addresses; with the setting at `0`, pc2 makes no new ones.

---

## Part L: Inside the IPv6 header (20 min)

*From today's lecture: Module 3, IPv6 Header Format, IPv6 vs. IPv4 Header Comparison, Extension Headers; Module 0, IPv4 Concepts Review.*

:::info
**Why this matters.** Every IPv6 packet starts with a fixed 40-byte header. Its **Next Header** field says what follows: the payload (ICMPv6 = 58) or an **extension header** (Fragment = 44, Hop-by-Hop Options = 0), added only when needed. You see the Hop-by-Hop Options header in stretch S3. To troubleshoot with a capture, you must read these fields: hop limit shows how far a packet came, Next Header shows what it really carries.
:::

### L1. Read a full header

`-v` makes tcpdump print the header fields. The filter keeps only Echo Requests.

**Terminal 2 (pc2):**

```
tcpdump -vni eth0 'icmp6 and ip6[40] == 128'
```

(128 is Echo Request.)

**Terminal 1 (pc1):**

```
ping -6 -c1 2001:db8:a:0:5054:ff:fea1:2
```

**Expected** in Terminal 2 (pc2):

```
IP6 (flowlabel 0x3a2f1, hlim 64, next-header ICMPv6 (58) payload length: 64) 2001:db8:a:0:5054:ff:fea1:1 > 2001:db8:a:0:5054:ff:fea1:2: [icmp6 sum ok] ICMP6, echo request, id 2, seq 1
```

Find each field of the 40-byte IPv6 header in that line:

| Field | Value in the capture |
|---|---|
| Flow label | `flowlabel 0x...` |
| Hop limit | `hlim 64` |
| Next header | `next-header ICMPv6 (58)` |
| Payload length | `payload length: 64` |
| Source and destination | the two addresses |

There is no header checksum and there are no fragment fields.

#### How to read this

- Flow label: a 20-bit number that marks packets of one flow. Yours will differ.
- Next header 58: ICMPv6 follows directly; no extension headers.
- Payload length 64: only what comes **after** the fixed 40-byte header (8-byte ICMPv6 header + 56 bytes of data).
- Version (always 6) and Traffic Class are in the header too, but not printed here.
- `[icmp6 sum ok]`: ICMPv6 has its own checksum, which also covers the addresses. So IPv6 needs no header checksum, and routers that lower the hop limit have no checksum to recalculate.

### L2. Change the hop limit

`-t 5` sends the ping with hop limit 5 instead of 64.

**Terminal 1 (pc1):**

```
ping -6 -c1 -t 5 2001:db8:a:0:5054:ff:fea1:2
```

**Expected** in Terminal 2 (pc2): `hlim 5`. Hop limit is IPv6's version of the IPv4 TTL.

#### How to read this

The value arrived unchanged because no router was in between. Each router lowers it by 1 and drops the packet at 0, so a packet cannot loop forever. Neighbor Discovery messages are sent with hop limit 255, and receivers ignore them if it is lower: proof they came from the same link.

### L3. The Fragment header

The link carries at most 1500 bytes (`mtu 1500`, A1). A ping with 3000 bytes of data (`-s 3000`) must be split. Only the first piece contains the ICMPv6 header, so you capture everything from pc1, not only echo requests.

In **Terminal 2 (pc2)**, press **Ctrl+C**, then capture everything pc1 sends:

```
tcpdump -vni eth0 'ip6 src 2001:db8:a:0:5054:ff:fea1:1'
```

**Predict first:** into how many packets will pc1 split it?

**Terminal 1 (pc1):** send a ping too big for one packet:

```
ping -6 -c1 -s 3000 2001:db8:a:0:5054:ff:fea1:2
```

**Expected** in Terminal 2 (pc2): three packets with `next-header Fragment (44)`:

```
IP6 (... next-header Fragment (44) payload length: 1456) 2001:db8:a:0:5054:ff:fea1:1 > 2001:db8:a:0:5054:ff:fea1:2: frag (0x...:0|1448) ICMP6, echo request, ...
IP6 (... next-header Fragment (44) payload length: 1456) 2001:db8:a:0:5054:ff:fea1:1 > 2001:db8:a:0:5054:ff:fea1:2: frag (0x...:1448|1448)
IP6 (... next-header Fragment (44) payload length: 120) 2001:db8:a:0:5054:ff:fea1:1 > 2001:db8:a:0:5054:ff:fea1:2: frag (0x...:2896|112)
```

`frag (ID:offset|length)`. pc1 split the packet itself. In IPv6 only the **sending host** fragments, and it uses an extension header to do it. Routers never fragment.

#### How to read this

- The IPv6 header points to a Fragment header (44), which then points to ICMPv6.
- The ID is the same in all three, so pc2 knows they belong together. The offset says where each piece starts.
- `payload length: 1456` = 8-byte Fragment header + 1448 bytes of data; with the 40-byte header, 1496 bytes fit in 1500. Total data: 3000 + 8 (ICMPv6 header) = 1448 + 1448 + 112.

**Explain why:** 1500 - 40 - 8 = 1452. Why only 1448 bytes per piece?

<details>
<summary>▶ Answer</summary>

The offset counts in units of 8 bytes, so every piece except the last must carry a multiple of 8. 1448 is the largest multiple of 8 below 1452.
</details>

### L4. Compare with IPv4

Stop the capture in **Terminal 2 (pc2)** with **Ctrl+C**. You add IPv4 addresses for a few minutes only, to put the two headers side by side. Commands without `-6` use IPv4.

Give pc1 and pc2 temporary IPv4 addresses.

**Terminal 1 (pc1):**

```
ip addr add 10.0.0.1/24 dev eth0
```

**Terminal 2 (pc2):**

```
ip addr add 10.0.0.2/24 dev eth0
tcpdump -vni eth0 icmp
```

**Terminal 1 (pc1):**

```
ping -c1 10.0.0.2
```

**Expected** in Terminal 2 (pc2):

```
IP (tos 0x0, ttl 64, id 41235, offset 0, flags [DF], proto ICMP (1), length 84)
    10.0.0.1 > 10.0.0.2: ICMP echo request, id 3, seq 1, length 64
```

IPv4 carries an ID, flags, a fragment offset and a header checksum in **every** packet. IPv6 dropped the checksum and moved fragmenting into an extension header that appears only when needed.

#### How to read this

| IPv4 (this capture) | IPv6 (L1) |
|---|---|
| `ttl 64` | `hlim 64` |
| `proto ICMP (1)` | `next-header ICMPv6 (58)`, which can also point to an extension header |
| `length 84` includes the 20-byte header | `payload length: 64` excludes the 40-byte header |
| `id`, `offset`, `flags` in every packet | only in a Fragment header, when needed |

Also, pc1 found pc2's MAC for this ping with an ARP broadcast. IPv6 used a solicited-node multicast instead (Part B).

### L5. Put it back: remove the IPv4 addresses

The IPv4 addresses were only for the comparison. Remove them so the lab and the self-check see IPv6 only. The self-check tests that they are gone.

In **Terminal 2 (pc2)**, press **Ctrl+C**, then:

```
ip addr del 10.0.0.2/24 dev eth0
```

**Terminal 1 (pc1):**

```
ip addr del 10.0.0.1/24 dev eth0
```

---

## Check your work

1. In any terminal, go back to the Cloud9 machine: open a **new** terminal (**Window > New Terminal**). Leave the three node terminals as they are.
2. In the new terminal, run:
   ```
   sudo labctl check 1 1
   ```
   **Expected:** sixteen `PASS` lines and:
   ```
   Result: 16 passed, 0 failed
   ```

<details>
<summary>▶ I got a FAIL. What now?</summary>

| FAIL line mentions | Go back to |
|---|---|
| r1 address, forwarding or radvd | Part C, steps C1 to C3 (on r1) |
| SLAAC address or default route | Is radvd running on r1 (`pgrep -a radvd`)? Then C4 and C5 |
| ULA (`fd12:3456:789a:1::`) | Step G2 (on r1), then G4 |
| ping | Check both addresses with `ip -6 addr`, then C6 or G5 |
| leftover test addresses | Steps D2 and E3 (on pc1) |
| temporary address | Step K2 (on pc2) |
| IPv4 test addresses | Step L5 (on pc1 and pc2) |

If you cannot find it, reset Lab 1 (`sudo labctl reset 1 1`) and do Part C and step G2 again. It takes about 15 minutes.
</details>

## Check yourself

1. Why does a link-local ping need `%eth0`?
2. What replaces ARP in IPv6, and which multicast address does it use?
3. Where did pc1 get its default gateway from?
4. A DAD Neighbor Solicitation has an unusual source address. Which one, and why?
5. pc1 has a ULA address, but Linux prints `scope global` for it. What is its scope in the lecture's terms, and who keeps it inside the site?
6. How can you see that r1 has an anycast address, when `ip -6 addr` does not show it?
7. Shorten `2001:0db8:0000:0000:0000:0000:0000:0001`. How many `/64` subnets fit into a `/48`?
8. In IPv6, who fragments a packet that is too big for the link, and which header shows it?

<details>
<summary>▶ Answers</summary>

1. Every interface has an `fe80::/64` address, so the same prefix exists on every link. The zone ID picks the interface to use.
2. Neighbor Discovery: Neighbor Solicitation and Neighbor Advertisement (ICMPv6 types 135 and 136). The solicitation goes to the target's solicited-node multicast address, `ff02::1:ff` plus the last 24 bits of the target address.
3. From r1's Router Advertisement. The gateway is the RA's source address, r1's link-local `fe80::5054:ff:fea1:fe`.
4. The unspecified address `::`. The new address may not be used until DAD has finished, so the node asks without a source address (Part E).
5. Site scope: it must stay inside the organisation. The host does not mark this; the routers and firewalls at the edge of the site must not send ULA traffic to the Internet (Part G).
6. In the local routing table: `ip -6 route show table local` lists it as `anycast` (Part I). Linux adds the subnet-router anycast address on a router when forwarding is on.
7. `2001:db8::1`. A `/48` holds 65,536 `/64` subnets (16 bits of subnet ID).
8. Only the sending host fragments, never a router. The packets carry a Fragment extension header (Next Header 44), as in L3.
</details>

---

# Stretch exercises (about 80 minutes)

Do these after Part L, in order. They use the same three nodes and terminals. Each one starts with a line that ties it to today's lecture; a **New in this exercise** box explains anything the lecture did not cover. Each one ends with the result you should see. If you get lost, steps S2-5, S4-2 and S5-4 put everything back.

The core parts showed **that** each mechanism works. Here you see how it behaves over time, how it fails, and what one more extension header looks like inside.

## S1: Neighbor cache states (15 min)

*Ties to today's Module 3, Neighbor Discovery Protocol: Neighbor Unreachability Detection (NUD) is one of the core NDP functions on the slide. The cache states are covered in detail on Day 3.*

:::info
**New in this exercise.** The **neighbor cache** (`ip -6 neigh`) is IPv6's ARP table. Each entry has a **state**. `REACHABLE`: the neighbor answered very recently. `STALE`: it has not been confirmed for a while; the entry is still used, but checked the next time it is needed. `DELAY` and `PROBE`: that check is running. A `permanent` entry is typed by hand and is never checked.
:::

:::info
**Why this matters.** The check of a `STALE` entry is **Neighbor Unreachability Detection (NUD)**. It is how a host notices that a neighbor, such as its gateway, has died or changed its MAC. A static entry switches NUD off, so a wrong static entry breaks traffic silently.
:::

### S1-1. Watch an entry age

Empty the cache, ping pc2's **global** address once, and look at the new entry for eth0.

**Terminal 1 (pc1):**

```
ip -6 neigh flush dev eth0
ping -6 -c1 2001:db8:a:0:5054:ff:fea1:2
ip -6 neigh show dev eth0
```

**Expected:** pc2's entry is `REACHABLE`:

```
2001:db8:a:0:5054:ff:fea1:2 lladdr 52:54:00:a1:00:02 REACHABLE
```

pc1 knew pc2's MAC for the link-local address, but ran Neighbor Discovery again: each IPv6 address has its own entry. (An entry for r1 marked `router` may also appear.)

**Predict first:** after 45 seconds with no traffic to pc2, what state will the entry be in?

Now wait 45 seconds and look again:

```
sleep 45; ip -6 neigh show dev eth0
```

**Expected:** the same entry, now `STALE`.

:::info
A `STALE` entry is still used. The next time pc1 sends to pc2 it moves to `DELAY`, then `PROBE`, and pc1 checks that pc2 still answers. This is **Neighbor Unreachability Detection (NUD)**.
:::

#### How to read this

`REACHABLE` lasts about 30 seconds, with a random part (roughly 15 to 45), which is why you wait 45. The RA's `Reachable time` was `unspecified` (C4), so pc1 used this default. In `PROBE`, pc1 sends unicast NS messages straight to the stored MAC; if nobody answers, the entry is removed.

**Explain why:** why keep a `STALE` entry instead of deleting it and asking again?

<details>
<summary>▶ Answer</summary>

Usually the neighbor is still there. Keeping the entry lets pc1 send at once, and the check is one small unicast message instead of a multicast question.
</details>

### S1-2. Ask for pc2's MAC the IPv6 way

`ndisc6` does one Neighbor Discovery exchange by hand: one NS for the address on the given interface, and prints the NA.

**Terminal 1 (pc1):**

```
ndisc6 2001:db8:a:0:5054:ff:fea1:2 eth0
```

**Expected:**

```
Soliciting 2001:db8:a:0:5054:ff:fea1:2 (2001:db8:a:0:5054:ff:fea1:2) on eth0...
Target link-layer address: 52:54:00:A1:00:02
 from 2001:db8:a:0:5054:ff:fea1:2
```

`ndisc6` sends one Neighbor Solicitation and prints the answer.

#### How to read this

`Target link-layer address` is pc2's MAC. If a neighbor does not answer `ndisc6`, the problem is in Neighbor Discovery or the link, not higher up.

### S1-3. Break it with a wrong static entry

`ip -6 neigh replace` creates or overwrites an entry. Here it sets a fake MAC (`lladdr 52:54:00:de:ad:00`) with `nud permanent`: a static entry that never ages and is never checked. `-W1` makes ping wait only 1 second per reply.

**Predict first:** pc2 is up and its address is right. Will the ping work?

**Terminal 1 (pc1):**

```
ip -6 neigh replace 2001:db8:a:0:5054:ff:fea1:2 lladdr 52:54:00:de:ad:00 dev eth0 nud permanent
ping -6 -c2 -W1 2001:db8:a:0:5054:ff:fea1:2
```

**Expected:** `2 packets transmitted, 0 received, 100% packet loss`. pc1 sends the frames to a MAC that nobody has, and a `permanent` entry is never checked again.

On real networks this happens when a static entry is not updated after a neighbor's network card is replaced. Deleting the entry lets Neighbor Discovery learn the real MAC again on the next ping.

Fix it:

```
ip -6 neigh del 2001:db8:a:0:5054:ff:fea1:2 dev eth0
ping -6 -c2 2001:db8:a:0:5054:ff:fea1:2
```

**Expected:** `0% packet loss` again.

## S2: Tune the Router Advertisements (25 min)

*Ties to today's Module 3, Neighbor Discovery Protocol: Router Discovery (RS/RA) and address autoconfiguration (SLAAC). You saw the lifetimes in the RA in C4 and C5; here you change them.*

:::info
**New in this exercise.**
- **Valid lifetime** and **preferred lifetime** (from the prefix part of an RA, `valid_lft` and `preferred_lft` in `ip -6 addr`). While an address is preferred, the host uses it for new connections. When the preferred lifetime ends, the address is **deprecated**: it still works for running connections, but the host does not pick it for new ones. When the valid lifetime ends, the address is removed.
- **Router lifetime** (from the router part of an RA): how long hosts may use the router as their default gateway. 0 means "do not use me as a gateway".
- **Source address choice.** When a host has several addresses, the kernel picks one as the source of each new connection. It avoids deprecated addresses, and among the rest it prefers the one that shares the most leading bits with the destination. The full rules (RFC 6724) are part of the Day 2 lecture.
:::

:::info
**Why this matters.** Every value in an RA is an instruction to every host on the link. Lifetimes decide how long hosts keep and prefer addresses and the default route. This is how a company moves a link to a new prefix, for example after changing internet provider, without breaking running connections. It also shows the risk: one wrong value, such as a router lifetime of 0, changes every host at once.
:::

Each step below rewrites `/etc/radvd.conf` on **r1** and restarts radvd. Every file keeps the ULA prefix from Part G. After each step, look at the result on **pc1** with:

```
rdisc6 eth0
ip -6 addr show dev eth0
ip -6 route
```

These show the RA as pc1 receives it, pc1's addresses and its routes (C4, C5). radvd reads its file only at start, so each box ends with `pkill radvd; sleep 1; radvd`: stop it, wait, start it with the new file.

:::info
Each time radvd stops, it sends a last advertisement with a router lifetime of 0. So pc1's default route disappears for a few seconds every time you restart radvd. That is expected.
:::

### S2-1. A second global prefix

The new line is `prefix 2001:db8:a1::/64`; the rest is the Part G file.

**Predict first:** what new global address will pc1 build?

**Terminal 3 (r1):** paste this whole box:

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
    prefix fd12:3456:789a:1::/64 {
        AdvOnLink on;
        AdvAutonomous on;
    };
    prefix 2001:db8:a1::/64 { AdvOnLink on; AdvAutonomous on; };
};
EOF
pkill radvd; sleep 1; radvd
```

**Terminal 1 (pc1)**, after about 10 seconds:

```
ip -6 addr show dev eth0
```

**Expected:** three addresses with `scope global`: `2001:db8:a:0:5054:ff:fea1:1`, `fd12:3456:789a:1:5054:ff:fea1:1` (from Part G) and the new `2001:db8:a1:0:5054:ff:fea1:1`.

SLAAC builds one address per autonomous prefix, with the same interface ID. Each has its own lifetimes.

Which source address does pc1 pick for each prefix?

`ip -6 route get` asks the kernel which route and source address it would use for a destination. Nothing is sent.

```
ip -6 route get 2001:db8:a1::1
ip -6 route get 2001:db8:a::1
```

**Expected:** `src 2001:db8:a1:0:5054:ff:fea1:1` for the first and `src 2001:db8:a:0:5054:ff:fea1:1` for the second. pc1 picks the source address that matches the destination best.

"Best" means the most leading bits in common. The choice matters because replies come back to that source address. (pc1 does not pick its ULA address for these global destinations: the Day 2 rules keep ULA sources for ULA destinations.)

r1 has no address in `2001:db8:a1::/64` yet. Add one. **Terminal 3 (r1):**

```
ip -6 addr add 2001:db8:a1::1/64 dev eth0
```

**Terminal 1 (pc1):**

```
ping -6 -c2 2001:db8:a1::1
```

**Expected:** `0% packet loss`.

pc1 reached `2001:db8:a1::1` directly with Neighbor Discovery, because `AdvOnLink on` told it this prefix is on its own link.

### S2-2. Lifetimes

You ask hosts to keep addresses from the first prefix for 300 seconds and prefer them for 120, instead of the defaults (86400 and 14400).

**Predict first:** what will `valid_lft` and `preferred_lft` show afterwards?

**Terminal 3 (r1):** give the first prefix short lifetimes:

```
cat > /etc/radvd.conf <<'EOF'
interface eth0 {
    AdvSendAdvert on;
    MinRtrAdvInterval 3;
    MaxRtrAdvInterval 10;
    prefix 2001:db8:a::/64 { AdvOnLink on; AdvAutonomous on; AdvValidLifetime 300; AdvPreferredLifetime 120; };
    prefix fd12:3456:789a:1::/64 { AdvOnLink on; AdvAutonomous on; };
    prefix 2001:db8:a1::/64 { AdvOnLink on; AdvAutonomous on; };
};
EOF
pkill radvd; sleep 1; radvd
```

**Terminal 1 (pc1)**, after about 10 seconds:

```
ip -6 addr show dev eth0
```

**Expected** for the `2001:db8:a:0:5054:ff:fea1:1` address: `preferred_lft` about **120** seconds, but `valid_lft` only down to about **7200** seconds, not 300.

#### How to read this

The preferred lifetime followed the RA at once. The valid lifetime went down, but stopped at 2 hours. The `2001:db8:a1:0:...` and `fd12:...` addresses are unchanged, because their prefix settings did not change.

<details>
<summary>▶ Why not 300?</summary>

A host never lets a Router Advertisement cut an address's remaining valid lifetime below 2 hours (7200 seconds) (RFC 4862). One bad or forged advertisement cannot wipe out everyone's addresses at once.
</details>

**Explain why:** why is a short preferred lifetime not protected the same way?

<details>
<summary>▶ Answer</summary>

When the preferred lifetime ends, the address still works; it is just not chosen for new connections. When the valid lifetime ends, the address is removed and its connections break.
</details>

### S2-3. Deprecate an address

Preferred lifetime 0 means "stop using this prefix for new connections now". The address becomes **deprecated**: the first step in moving hosts off a prefix.

**Predict first:** which source will pc1 now use for `2001:db8:a::1`?

**Terminal 3 (r1):** set the preferred lifetime to 0:

```
cat > /etc/radvd.conf <<'EOF'
interface eth0 {
    AdvSendAdvert on;
    MinRtrAdvInterval 3;
    MaxRtrAdvInterval 10;
    prefix 2001:db8:a::/64 { AdvOnLink on; AdvAutonomous on; AdvValidLifetime 300; AdvPreferredLifetime 0; };
    prefix fd12:3456:789a:1::/64 { AdvOnLink on; AdvAutonomous on; };
    prefix 2001:db8:a1::/64 { AdvOnLink on; AdvAutonomous on; };
};
EOF
pkill radvd; sleep 1; radvd
```

**Terminal 1 (pc1)**, after about 10 seconds:

```
ip -6 addr show dev eth0
ip -6 route get 2001:db8:a::1
```

**Expected:** the `2001:db8:a:0:...` address is now marked `deprecated` (with `preferred_lft 0sec`). It still answers, but pc1 no longer picks it for new connections: the `src` in the second command is now the `2001:db8:a1:0:...` address.

#### How to read this

In S2-1 the `2001:db8:a:0:...` source was the best match for this destination. Avoiding a deprecated address is a stronger rule than the best match, so pc1 switched. Running connections would keep working until the valid lifetime ends, so moving to a new prefix this way breaks nothing.

### S2-4. No default router

The router lifetime says how long hosts may use r1 as their **default gateway**. `AdvDefaultLifetime 0` means "I am a router with prefixes, but not your gateway".

**Predict first:** will pc1 lose its addresses, its default route, or both?

**Terminal 3 (r1):** add `AdvDefaultLifetime 0;` inside `interface eth0 { ... }`:

```
cat > /etc/radvd.conf <<'EOF'
interface eth0 {
    AdvSendAdvert on;
    MinRtrAdvInterval 3;
    MaxRtrAdvInterval 10;
    AdvDefaultLifetime 0;
    prefix 2001:db8:a::/64 { AdvOnLink on; AdvAutonomous on; AdvValidLifetime 300; AdvPreferredLifetime 0; };
    prefix fd12:3456:789a:1::/64 { AdvOnLink on; AdvAutonomous on; };
    prefix 2001:db8:a1::/64 { AdvOnLink on; AdvAutonomous on; };
};
EOF
pkill radvd; sleep 1; radvd
```

**Terminal 1 (pc1)**, after about 10 seconds:

```
rdisc6 eth0
ip -6 route
```

**Expected:** `Router lifetime : 0` in the RA. pc1 keeps its addresses, but the `default via fe80::5054:ff:fea1:fe` route is gone. r1 is still on the link; it just tells hosts "do not use me as a gateway".

#### How to read this

Only the router lifetime changed; the prefix part of the RA is the same. Addresses come from prefix information, the default route from the router lifetime: they are separate. pc1 still reaches everything in its three prefixes, but has no gateway for anything else.

### S2-5. Put it back

This returns r1 to the Part G settings for the other stretch exercises and the self-check.

**Terminal 3 (r1):** restore the Part G file and remove the extra address:

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
    prefix fd12:3456:789a:1::/64 {
        AdvOnLink on;
        AdvAutonomous on;
    };
};
EOF
pkill radvd; sleep 1; radvd
ip -6 addr del 2001:db8:a1::1/64 dev eth0
```

pc1 and pc2 keep their `2001:db8:a1:0:...` addresses until the lifetime runs out. Remove them by hand.

A prefix that disappears from the RA is not a signal to delete anything; hosts wait for the valid lifetime (about a day here). That protects them if a router forgets a prefix briefly.

**Terminal 1 (pc1):**

```
ip -6 addr del 2001:db8:a1:0:5054:ff:fea1:1/64 dev eth0
```

**Terminal 2 (pc2):**

```
ip -6 addr del 2001:db8:a1:0:5054:ff:fea1:2/64 dev eth0
```

**Terminal 1 (pc1)**, after about 10 seconds:

```
ip -6 addr show dev eth0
ip -6 route
```

**Expected:** `2001:db8:a:0:5054:ff:fea1:1` (no longer `deprecated`), `fd12:3456:789a:1:5054:ff:fea1:1` and `default via fe80::5054:ff:fea1:fe` are back.

**Explain why:** in S2-2 the host refused to cut the valid lifetime. Why does it accept the return to "preferred" at once?

<details>
<summary>▶ Answer</summary>

Longer lifetimes can never break anything. The restored file uses the defaults again (preferred 14400, router lifetime 30), so the address is preferred again and the default route returns.
</details>

## S3: The Hop-by-Hop Options header (10 min)

*Ties to today's Module 3, Extension Headers: Hop-by-Hop is one of the common types on the slide. Part L showed the Fragment header; here you see the Hop-by-Hop Options header in a real packet.*

:::info
**New in this exercise.**
- **MLD** (Multicast Listener Discovery) is the ICMPv6 message a node sends to say "I join this multicast group". Routers listen to it to learn which groups have members on a link. A node sends one each time it joins a group, for example its solicited-node group (Part B).
- **Router Alert** is an option that tells every router on the path: "look inside this packet, even though it is not addressed to you". MLD reports carry it, in a Hop-by-Hop Options header.
:::

This header carries information that **every** node on the path must look at. It always comes first after the IPv6 header, so `'ip6 proto 0'` (next header 0) catches it. MLD reports use it, so you make pc2 rejoin the link.

**Terminal 1 (pc1):** capture packets whose first header is Hop-by-Hop Options (next header 0):

```
tcpdump -vni eth0 'ip6 proto 0'
```

**Terminal 2 (pc2):** make pc2 leave and rejoin the link:

```
ip link set eth0 down; ip link set eth0 up
```

**Expected** in Terminal 1 (pc1), lines like:

```
IP6 (hlim 1, next-header Options (0) payload length: 36) :: > ff02::16: HBH (rtalert: 0x0000) (padn) [icmp6 sum ok] ICMP6, multicast listener report v2, 1 group record(s) [gaddr ff02::1:ffa1:2 to_ex { }]
```

pc2 announces that it is joining its solicited-node group (Part B). That message (an MLD report, sent to `ff02::16`) carries a Hop-by-Hop Options header with the Router Alert option. pc2 gets its global and ULA addresses back within about 10 seconds.

Press **Ctrl+C** in Terminal 1 (pc1).

#### How to read this

- `next-header Options (0)`: the IPv6 header points to a Hop-by-Hop Options header, which then points to ICMPv6.
- `hlim 1`: must not leave the link.
- `rtalert`: Router Alert, "routers, look inside this packet even though it is not for you". `padn` is padding to a multiple of 8 bytes.
- Source `::`: pc2's link-local address is still tentative (DAD is running), so it cannot use it yet.
- `gaddr ff02::1:ffa1:2 to_ex { }`: an **MLD** report meaning "I join this group, from any sender".

**Explain why:** why must pc2 join its solicited-node group before DAD has finished?

<details>
<summary>▶ Answer</summary>

DAD needs it. If another node is checking or using the same address, its NS goes to that group. pc2 must be listening during DAD, or it would miss the sign of a duplicate.
</details>

## S4: Stable privacy addresses (10 min)

*Ties to today's Module 2, Interface Identifiers: EUI-64 and random/temporary IIDs. This is one more way to build an interface ID.*

EUI-64 puts your MAC in every address. **Stable privacy** addresses (RFC 7217) use a hash instead: the address stays the same on one network but cannot be traced back to the MAC.

:::info
**New in this exercise.** RFC 7217 **stable privacy** addresses were not in the lecture. A **hash** turns its input into a random-looking number, always the same for the same input. Here the input includes the prefix, the interface and a secret on the host. Same network, same address; another network, a different address.
:::

:::info
**Why this matters.** Temporary addresses (Part K) change all the time, which makes logs harder to use. Stable privacy gives the local network a steady address per device, without letting others follow the device between networks.
:::

### S4-1. Turn it on for pc2

`addr_gen_mode` sets how eth0 builds interface IDs: `0` is EUI-64, `3` is stable privacy with a secret the kernel creates. The interface restart rebuilds the addresses.

**Predict first:** will the link-local address change too, or only the global one?

**Terminal 2 (pc2):**

```
sysctl -w net.ipv6.conf.eth0.addr_gen_mode=3
ip link set eth0 down; ip link set eth0 up
sleep 8; ip -6 addr show dev eth0
```

**Expected:** the link-local, `2001:db8:a:0:...` and `fd12:3456:789a:1:...` addresses no longer contain `5054:ff:fe`. They are marked `stable-privacy`.

#### How to read this

- Both changed: the setting applies to every interface ID on eth0.
- The interface IDs differ from each other, because the prefix is part of the hash input.
- There is no `temporary` address, because K2 turned them off. With `use_tempaddr=2` the two features work together.

**Explain why:** could you still work out pc2's link-local address from its MAC, as in A3?

<details>
<summary>▶ Answer</summary>

No. The interface ID now comes from a hash with a secret. Earlier steps rely on `fe80::5054:ff:fea1:2`, which is why S4-2 switches pc2 back.
</details>

### S4-2. Put it back

This restores EUI-64 (`addr_gen_mode=0`) and turns temporary addresses off (`use_tempaddr=0`), as at the start of the lab.

**Terminal 2 (pc2):**

```
sysctl -w net.ipv6.conf.eth0.addr_gen_mode=0
sysctl -w net.ipv6.conf.eth0.use_tempaddr=0
ip link set eth0 down; ip link set eth0 up
sleep 8; ip -6 addr show dev eth0
```

**Expected:** `fe80::5054:ff:fea1:2`, `2001:db8:a:0:5054:ff:fea1:2` and `fd12:3456:789a:1:5054:ff:fea1:2` are back, and there is no `temporary` address.

Run the self-check again (in the Cloud9 terminal): `sudo labctl check 1 1`. **Expected:** `Result: 16 passed, 0 failed`.

## S5: Break it, find it, fix it (20 min)

*Ties to today's Module 3, Neighbor Discovery Protocol: Router Discovery (RS/RA) and SLAAC; and Module 2, Prefix Notation & Subnetting. Everything you need was in Parts C, G and H.*

:::info
**Why this matters.** When SLAAC goes wrong, users do not report "the RA is wrong". They report "my new laptop has no internet". You must go from the symptom to the cause with a few commands: what addresses and routes the host has (`ip -6 addr`, `ip -6 route`), what the router really announces (`rdisc6`), and what the router is configured to do (`pgrep`, `cat /etc/radvd.conf`). This challenge trains that path.
:::

**How it works.** There are three tickets. For each one:

1. Paste the **break** box into **Terminal 3 (r1)**. It changes r1 in a hidden way, as a colleague might have done. Do not decode it yet.
2. Make pc2 join the link again, like a new laptop that has just been switched on. **Terminal 2 (pc2):**
   ```
   ip link set eth0 down; ip link set eth0 up; sleep 8
   ```
3. Find the cause with the commands from the core parts. Write it down, then fix it.
4. Open the hints only if you are stuck. Open the answer to check yourself.

After the answer, you may decode the break box to see exactly what it did: run the same `echo '...' | base64 -d` without `| bash` at the end.

### S5-1. Ticket 1: "The new laptop cannot reach the router"

**Break** (Terminal 3, r1):

```
echo 'Y2F0ID4gL2V0Yy9yYWR2ZC5jb25mIDw8J0VPRicKaW50ZXJmYWNlIGV0aDAgewogICAgQWR2U2VuZEFkdmVydCBvbjsKICAgIE1pblJ0ckFkdkludGVydmFsIDM7CiAgICBNYXhSdHJBZHZJbnRlcnZhbCAxMDsKICAgIHByZWZpeCAyMDAxOmRiODpiOjovNjQgewogICAgICAgIEFkdk9uTGluayBvbjsKICAgICAgICBBZHZBdXRvbm9tb3VzIG9uOwogICAgfTsKICAgIHByZWZpeCBmZDEyOjM0NTY6Nzg5YToxOjovNjQgewogICAgICAgIEFkdk9uTGluayBvbjsKICAgICAgICBBZHZBdXRvbm9tb3VzIG9uOwogICAgfTsKfTsKRU9GCnBraWxsIHJhZHZkOyBzbGVlcCAxOyByYWR2ZAo=' | base64 -d | bash
```

Then make pc2 rejoin (step 2 above).

**Symptom.** On pc2, this fails:

```
ping -6 -c2 -W1 2001:db8:a::1
```

**Expected:** `2 packets transmitted, 0 received, 100% packet loss`. Before the change it worked (C6).

Find the cause.

<details>
<summary>▶ Hint 1</summary>

Look at pc2's global address with `ip -6 addr show dev eth0`. Compare its first 64 bits with r1's address `2001:db8:a::1`.
</details>

<details>
<summary>▶ Hint 2</summary>

Ask r1 what it announces: `rdisc6 eth0` on pc2. Which prefix does the RA carry?
</details>

<details>
<summary>▶ Answer</summary>

pc2 has `2001:db8:b:0:5054:ff:fea1:2` instead of `2001:db8:a:0:5054:ff:fea1:2`, and `rdisc6` shows `Prefix : 2001:db8:b::/64`. On r1, `cat /etc/radvd.conf` shows `prefix 2001:db8:b::/64`: a typo, `b` instead of `a`.

Why the ping fails: pc2 sends from its `2001:db8:b:...` address through its default gateway, r1. r1 receives the request, but r1 has no address in `2001:db8:b::/64`, so it does not know that this prefix is on its own link. It has no route back, so the reply is never sent. A router must announce only prefixes it really has on that link.

**Fix:** paste the Part G radvd file on r1 (the box in G2, without the `ip -6 addr add` line), then make pc2 rejoin. Check that pc2 has `2001:db8:a:0:5054:ff:fea1:2` again and that the ping works. pc1 still has an extra `2001:db8:b:...` address; S5-4 removes it.
</details>

### S5-2. Ticket 2: "Old PCs are fine, the new laptop has no global address"

**Break** (Terminal 3, r1):

```
echo 'Y2F0ID4gL2V0Yy9yYWR2ZC5jb25mIDw8J0VPRicKaW50ZXJmYWNlIGV0aDAgewogICAgQWR2U2VuZEFkdmVydCBvbjsKICAgIE1pblJ0ckFkdkludGVydmFsIDM7CiAgICBNYXhSdHJBZHZJbnRlcnZhbCAxMDsKICAgIHByZWZpeCAyMDAxOmRiODphOjovNjQgewogICAgICAgIEFkdk9uTGluayBvbjsKICAgICAgICBBZHZBdXRvbm9tb3VzIG9mZjsKICAgIH07CiAgICBwcmVmaXggZmQxMjozNDU2Ojc4OWE6MTo6LzY0IHsKICAgICAgICBBZHZPbkxpbmsgb247CiAgICAgICAgQWR2QXV0b25vbW91cyBvbjsKICAgIH07Cn07CkVPRgpwa2lsbCByYWR2ZDsgc2xlZXAgMTsgcmFkdmQK' | base64 -d | bash
```

Then make pc2 rejoin.

**Symptom.** pc2 has a ULA address and a link-local address, but no `2001:db8:a:...` address, so it cannot reach the Internet. pc1 still has its `2001:db8:a:...` address.

Find the cause.

<details>
<summary>▶ Hint 1</summary>

Does pc2 still have the on-link route `2001:db8:a::/64` and the default route (`ip -6 route`)? If yes, pc2 does receive RAs with this prefix.
</details>

<details>
<summary>▶ Hint 2</summary>

Run `rdisc6 eth0` on pc2 and compare the flags of the two prefixes with C4.
</details>

<details>
<summary>▶ Answer</summary>

`rdisc6` shows `Autonomous address conf. : No` for `2001:db8:a::/64`. On r1, `cat /etc/radvd.conf` shows `AdvAutonomous off` for that prefix. The prefix is still announced as on-link, so pc2 has the route, but hosts may not build an address from it: no SLAAC.

pc1 keeps its old address because hosts do not delete an address when the flag changes; they stop renewing it, and it ends when its valid lifetime runs out. That is why only new devices complain at first.

**Fix:** paste the Part G radvd file on r1 again, then make pc2 rejoin and check that `2001:db8:a:0:5054:ff:fea1:2` is back.
</details>

### S5-3. Ticket 3: "The new laptop has only an fe80 address"

**Break** (Terminal 3, r1):

```
echo 'cGtpbGwgcmFkdmQK' | base64 -d | bash
```

Then make pc2 rejoin.

**Symptom.** pc2 has only `fe80::5054:ff:fea1:2`: no global address, no ULA address, no default route.

Find the cause.

<details>
<summary>▶ Hint 1</summary>

Every global address and the default route come from Router Advertisements. Does pc2 get any? Run `rdisc6 eth0` on pc2.
</details>

<details>
<summary>▶ Hint 2</summary>

Which program sends the RAs on r1, and is it running?
</details>

<details>
<summary>▶ Answer</summary>

`rdisc6 eth0` on pc2 prints `Timed out.` three times and `No response.`: no router answers the Router Solicitation. On r1, `pgrep -a radvd` prints nothing: radvd is not running. Without RAs, hosts keep only their link-local address. (When radvd stopped, it also sent a last RA with router lifetime 0, so pc1 lost its default route too.)

**Fix:** on r1, run `radvd`. A new radvd sends RAs at once, so within about 10 seconds pc2 has its global and ULA addresses and its default route back, without rejoining.
</details>

### S5-4. Put it back

The fixes restored r1. pc1 may still have an extra `2001:db8:b:...` address and route from ticket 1. Make both hosts rejoin the link, so they keep only what r1 announces now.

**Terminal 3 (r1):** make sure the Part G file is in place and radvd runs:

```
cat /etc/radvd.conf
pgrep -a radvd
```

**Expected:** the two `prefix` blocks from G2 (`2001:db8:a::/64` and `fd12:3456:789a:1::/64`, both with `AdvAutonomous on`) and a running radvd. If not, paste the G2 radvd box again.

**Terminal 1 (pc1)** and **Terminal 2 (pc2)**:

```
ip link set eth0 down; ip link set eth0 up
sleep 8; ip -6 addr show dev eth0
```

**Expected:** on each host, the link-local, `2001:db8:a:0:...` and `fd12:3456:789a:1:...` addresses, and nothing in `2001:db8:b::/64`.

Run the self-check again (in the Cloud9 terminal): `sudo labctl check 1 1`. **Expected:** `Result: 16 passed, 0 failed`.

## Stretch: check yourself

1. Why does a host need a router lifetime of more than 0 before it adds a default route?
2. What is the difference between a deprecated address and an expired one?
3. Which extension header did the MLD report carry, and how did tcpdump show it?
4. A new laptop gets a link-local address and a ULA address, but no global address. Name two causes on the router that you found in S5.

<details>
<summary>▶ Answers</summary>

1. The router lifetime is how long the router may be used as a default gateway. 0 means "I am a router, but not a default gateway for you" (S2-4).
2. A deprecated address (preferred lifetime 0) still works for existing connections and still answers, but is not picked for new ones. An expired address (valid lifetime 0) is removed.
3. A Hop-by-Hop Options header with the Router Alert option: `next-header Options (0)` and `HBH (rtalert: 0x0000)` (S3).
4. The global prefix is announced with `AdvAutonomous off` (ticket 2), or a wrong prefix is announced instead of the real one (ticket 1: then the laptop gets a global address, but in the wrong prefix). `rdisc6` shows both.
</details>

---

**Next:** **IPv6 Day 2 Lab: Routing and Dual Stack** (tomorrow)
