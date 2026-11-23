# IPv6 Container Labs

Three hands-on IPv6 labs that run on plain Linux containers. Each student gets their own private copy of every lab. Each student gets one AWS Cloud9 environment (Ubuntu 22.04) and types `lab` in its terminal.

| Lab | Topic | Nodes |
|---|---|---|
| 1 | Link-local, Neighbor Discovery, SLAAC, DAD, privacy addresses | pc1, pc2, r1 |
| 2 | Routing between two LANs, dual stack, Path MTU (Day 1-2 topics only) | pc1, r1, r2, pc2 |
| 3 | IPv6 over IPv4: GRE and 6in4 tunnels, MTU and Packet Too Big; bonus: ICMPv6 errors, DHCPv6, firewalls, rogue RA (Day 3 topics) | pc1, r1, inet, r2, pc2 |

## How it works

- One Ubuntu 24.04 EC2 instance runs Docker.
- Every lab node is a small container (`ipv6lab/node:1`, Ubuntu with iproute2, tcpdump, radvd, dnsmasq, nftables, ndisc6). About 13 containers per student, 128 MB cap each, mostly idle.
- Containers have no Docker network. Lab links are veth pairs wired straight between containers, and Lab 1's switch is a Linux bridge inside a hidden container. The labs behave the same on any host and never touch the host's network.
- Fixed MAC addresses give every student the same EUI-64 addresses, so the guides can show the expected answers.
- Students SSH in on port 22 or 443 as `student01`, `student02`, ... and get a menu. They can only reach their own containers.

## Files

| Path | What |
|---|---|
| `image/Dockerfile` | The one node image |
| `scripts/host-setup.sh` | One-time host setup (packages, kernel modules, image, logins) |
| `scripts/labctl` | Deploy, reset, solve, check, destroy labs |
| `scripts/lab-enter`, `scripts/labsh` | Student login menu and its safe helper |
| `labs/lab1.sh` ... `lab3.sh` | Topology, pre-config, answer key and checks per lab |
| `student-guides/` | Student handouts (Markdown, ready for HackMD) |

## Quick start (on the EC2 instance)

```
tar xzf ipv6-labs.tar.gz && cd ipv6-labs
sudo bash scripts/host-setup.sh
sudo labctl accounts 99
sudo labctl deploy all 99
sudo labctl solve 1 99 && sudo labctl check 1 99
```

## Instance

- Ubuntu Server 24.04 LTS, x86_64. A t3.large (2 vCPU, 8 GB) is plenty for about 20 students; t3.medium for 10 or fewer.
- 20 GB gp3 disk.
- Security group: inbound TCP 22 and 443 from anywhere (or the class's IP ranges). No other ports.
- An Elastic IP or a DNS name is optional but makes the student handout stable if the instance is stopped and started.

## Teardown

- After class: `sudo labctl destroy all all`, then terminate the instance and release any Elastic IP and its security group.
- Between days you can stop the instance to save cost. After a start, rerun `sudo labctl destroy all all && sudo labctl deploy all <students>` because the lab wiring does not survive a reboot. Student work is lost, so stop only after the day's labs are done.

## Commands you'll use in class

```
sudo labctl status                  # what is running
sudo labctl reset 2 07              # fresh Lab 2 for student 07
sudo labctl check 2 07              # see where student 07 is stuck
sudo labctl enter 2 07 r1           # look at their r1
sudo cat /root/ipv6lab-accounts.txt # logins to hand out
```
