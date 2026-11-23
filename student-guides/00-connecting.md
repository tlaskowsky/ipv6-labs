# IPv6 Labs: Getting Connected

Every student has their own small network made of Linux machines. Nothing is shared with other students, so you can break things freely.

## Open your lab

1. Sign in to the AWS console with the account details from your instructor. Region: Europe (Frankfurt).
2. Open **Cloud9**, find the environment `ipv6-lab` and click **Open**.
3. Use the terminal at the bottom of the screen. If it was asleep, wait about a minute before the next step.

## Pick a lab and a node

Type `lab` and press Enter. Type the lab number, then the node name, for example `1` then `pc1`. The prompt changes to `[s01 pc1]#`. You are root on that node.

Type `exit` to go back to the menu and pick another node.

Shortcut that skips the menu:

```
lab 1 pc1
```

When a lab asks you to watch traffic on one node while you test from another, open a second terminal with **Window > New Terminal** (or Alt+T) and type `lab 1 r1` there. You can have several terminals side by side.

## Commands you will use

| Command | What it does |
|---|---|
| `ip -6 addr` | Show IPv6 addresses |
| `ip -6 route` | Show the IPv6 routing table |
| `ip -6 neigh` | Show the neighbor cache (IPv6's ARP table) |
| `ping -6 ADDRESS` | Ping over IPv6 (`%eth0` after a link-local address) |
| `tcpdump -ni eth0 icmp6` | Watch ICMPv6 packets on eth0 (Ctrl+C to stop) |
| `sysctl -w name=value` | Change a kernel setting |
| `nano FILE` | Edit a file (Ctrl+O save, Ctrl+X exit) |

If you get stuck, ask the instructor to reset your lab. A reset takes a few seconds.
