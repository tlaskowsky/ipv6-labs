# ipv6lab/node:1 - one image for every lab node (PCs, routers, "inet", switch).
# Plain Ubuntu 24.04 with the usual Linux networking tools. No AWS tools inside.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      iproute2 iputils-ping iputils-tracepath traceroute tcpdump \
      radvd dnsmasq-base isc-dhcp-client nftables ndisc6 sipcalc \
      curl python3 procps less nano vim-tiny bash-completion \
      tayga unbound dnsutils \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /lab

# Prompt shows student and node, e.g.  [s07 r1]#
RUN printf '%s\n' 'PS1="[${LAB_STUDENT:-lab} \h]# "' 'alias ll="ls -l"' >> /root/.bashrc

WORKDIR /root
CMD ["sleep", "infinity"]
