#!/bin/sh

# Author: Kornel Jahn
# License: BSD-3-Clause

if [ $# -lt 1 ]; then
  {
    echo "usage: $(basename "$0") <host-ip-address> [<ports>]"
    echo ''
    echo 'where <ports> takes the form "proto1/port1 proto2/port2 ..."'
  } 1>&2
  exit 1
fi

# Append to /etc/sysctl.conf if unpatched
grep -qxF 'net.inet.tcp.tso=0' /etc/sysctl.conf ||
{
  echo 'net.inet.tcp.tso=0'
  echo 'net.inet.ip.fw.verbose=0'
} >> /etc/sysctl.conf

# Enable ipfw with NAT
# Append to /etc/rc.conf if unpatched
grep -qxF 'gateway_enable="YES"' /etc/rc.conf ||
{
  echo ''
  echo 'gateway_enable="YES"'
  echo 'firewall_enable="YES"'
  echo 'firewall_nat_enable="YES"'
  echo 'firewall_script="/etc/ipfw.rules"'
  echo 'firewall_logging="YES"'
  echo 'firewall_logif="YES"'
} >> /etc/rc.conf

# Create /etc/ipfw.rules to forward ports
# Default selection:
#   TCP 22: SSH
#   TCP 443: WebUI HTTPS
#   TCP 2049: NFS4
#   TCP 5201: iperf3
#   TCP 28757: WebUI VNC
host="$1"
proto_ports="${2:-tcp/22 tcp/443 tcp/2049 tcp/5201 tcp/28757}"
{
  echo '#!/bin/sh'
  echo 'tun=tailscale0'
  echo 'cmd=/sbin/ipfw'
  echo "host=$host"
  echo ''
  echo '$cmd -q -f flush'
  echo ''
  echo '$cmd disable one_pass'
  echo '$cmd nat 1 config if $tun same_ports log \'
  for proto_port in $proto_ports; do
    proto="${proto_port%%/*}"
    port="${proto_port##*/}"
    echo "  redirect_port $proto"' $host:'"$port $port"' \'
  done
  unset proto port
  echo ''
  echo '$cmd add 100 nat 1 log ip4 from any to me in via $tun'
  echo '$cmd add 200 nat 1 log ip4 from $host/24 to any out via $tun'
  echo '$cmd add allow ip from any to any'
} > /etc/ipfw.rules
chmod a+x /etc/ipfw.rules

# WORKAROUND: ipfw nat rules do not seem to be applied at start-up
# Force restart of ipfw in /etc/rc.local
{
  echo 'sleep 2'
  echo 'logger WORKAROUND: forcing restart of ipfw to ensure working NAT...'
  echo 'service ipfw restart'
} > /etc/rc.local
chmod a+x /etc/rc.local

# vim: set ts=2 sw=2 sts=2 et:
