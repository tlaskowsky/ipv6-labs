#!/usr/bin/env bash
# host-setup.sh - turn a fresh Ubuntu 22.04 or 24.04 machine into the IPv6 lab host.
# Run from the unpacked ipv6-labs folder:
#   One student per AWS account (Cloud9 or Session Manager, no SSH, no open ports):
#                                             sudo LAB_MODE=single bash scripts/host-setup.sh
#     It builds that one student's labs and rebuilds them every time the machine boots
#     (Cloud9 wakes up from hibernation by booting).
#   Shared host, students log in by SSH:      sudo bash scripts/host-setup.sh
# Safe to run again. Does not touch AWS itself; it only configures this machine.
set -euo pipefail
LAB_MODE=${LAB_MODE:-ssh}
case "$LAB_MODE" in single|cloud9|ssm) LAB_MODE=single ;; ssh) ;; *) echo "LAB_MODE must be single or ssh"; exit 1 ;; esac
cd "$(dirname "$0")/.."
SRC=$(pwd)
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }

echo "== 1/6 packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# Cloud9 images already ship Docker; installing Ubuntu's docker.io over it would clash.
if command -v docker >/dev/null 2>&1; then
  apt-get install -y -qq iproute2 >/dev/null
else
  apt-get install -y -qq docker.io iproute2 >/dev/null
fi
systemctl enable --now docker
docker info >/dev/null || { echo "   Docker is installed but not running"; exit 1; }

echo "== 2/6 kernel modules (containers cannot load these themselves)"
MODS="bridge ip_gre sit ip6_tunnel nf_tables nf_nat tun"   # tun: tayga (NAT64) in Lab 2
for m in $MODS; do modprobe "$m"; done
printf '%s\n' $MODS > /etc/modules-load.d/ipv6lab.conf

echo "== 3/6 lab image"
# Base image: Docker Hub first, then AWS's public mirror of the same image
# (Docker Hub limits anonymous downloads per IP address).
if ! docker image inspect ubuntu:24.04 >/dev/null 2>&1; then
  docker pull -q ubuntu:24.04 >/dev/null 2>&1 \
  || { docker pull -q public.ecr.aws/docker/library/ubuntu:24.04 >/dev/null \
       && docker tag public.ecr.aws/docker/library/ubuntu:24.04 ubuntu:24.04; } \
  || { echo "   could not download the Ubuntu base image; check the instance has internet access"; exit 1; }
fi
docker build -q -t ipv6lab/node:1 "$SRC/image" >/dev/null 2>/tmp/ipv6lab-build.err \
  || { cat /tmp/ipv6lab-build.err; echo "   building the lab image failed"; exit 1; }
docker image ls ipv6lab/node:1 --format '   {{.Repository}}:{{.Tag}} {{.Size}}'

echo "== 4/6 lab files"
mkdir -p /opt/ipv6lab
cp -r "$SRC/labs" /opt/ipv6lab/
install -m 755 "$SRC/scripts/labctl"    /usr/local/sbin/labctl
install -m 755 "$SRC/scripts/lab-enter" /usr/local/sbin/lab-enter
install -m 755 "$SRC/scripts/labsh"     /usr/local/bin/labsh

if [ "$LAB_MODE" = single ]; then
echo "== 5/6 one-student host (type 'lab' to open the menu)"
mkdir -p /etc/ipv6lab
echo 01 > /etc/ipv6lab/student
cat > /usr/local/bin/lab <<'L'
#!/bin/sh
# lab - open the IPv6 lab menu (or: lab 2 r1)
exec /usr/bin/env bash /usr/local/bin/labsh "$@"
L
chmod 755 /usr/local/bin/lab; ln -sf /usr/local/bin/lab /usr/bin/lab
cat > /etc/systemd/system/ipv6lab-deploy.service <<'U'
[Unit]
Description=Build this host's IPv6 lab containers (student 01)
After=docker.service network-online.target
Requires=docker.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c '/usr/local/sbin/labctl destroy all all; /usr/local/sbin/labctl deploy all 1'
[Install]
WantedBy=multi-user.target
U
systemctl daemon-reload
systemctl enable ipv6lab-deploy.service >/dev/null 2>&1
systemctl restart ipv6lab-deploy.service
/usr/local/sbin/labctl status | sed 's/^/   /'
else
echo "== 5/6 student logins (SSH on ports 22 and 443, menu only)"
getent group labstudents >/dev/null || groupadd labstudents
cat > /etc/sudoers.d/ipv6lab <<'S'
%labstudents ALL=(root) NOPASSWD: /usr/local/sbin/lab-enter
S
chmod 440 /etc/sudoers.d/ipv6lab; visudo -cf /etc/sudoers.d/ipv6lab >/dev/null
cat > /etc/ssh/sshd_config.d/99-ipv6lab.conf <<'S'
Port 22
Port 443
Match Group labstudents
    PasswordAuthentication yes
    KbdInteractiveAuthentication yes
    ForceCommand /usr/local/bin/labsh
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
    AllowAgentForwarding no
S
sshd -t
# Ubuntu 24.04 starts sshd from ssh.socket; the ports above are picked up after a reload
systemctl daemon-reload
systemctl restart ssh.socket 2>/dev/null || true
systemctl restart ssh.service
ss -ltn | grep -E ':(22|443) ' | sed 's/^/   /'

fi

echo "== 6/6 done"
if [ "$LAB_MODE" = single ]; then
cat <<'T'
This host serves one student (student 01). Labs 1-3 are built.
  lab                                 open the student menu (or: lab 1 pc1)
  sudo labctl solve 1 1 && sudo labctl check 1 1     instructor test (then: sudo labctl reset 1 1)
After a reboot or a Cloud9 wake-up the labs are rebuilt automatically (about a minute;
fresh labs, student work is lost).
T
exit 0
fi
cat <<'T'
Next:
  sudo labctl accounts 99            # instructor test login (student99)
  sudo labctl deploy all 99          # build labs 1-3 for student 99
  sudo labctl solve 1 99 && sudo labctl check 1 99
When ready for class:
  sudo labctl accounts 1-12
  sudo labctl deploy all 1-12
  sudo cat /root/ipv6lab-accounts.txt
If the host reboots, run:  sudo labctl destroy all all && sudo labctl deploy all <students>
T
