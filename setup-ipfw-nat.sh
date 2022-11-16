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

. ./set-default-ports.sh

target=/etc/sysctl.conf
# Only append if target is unpatched
if ! grep -qxF 'net.inet.tcp.tso=0' "$target"; then
  echo "Appending to $target..."
  {
    echo 'net.inet.tcp.tso=0'
    echo 'net.inet.ip.fw.verbose=0'
  } >> "$target"
  echo
fi

# Enable IPFW with NAT
target=/etc/rc.conf
# Only append if target is unpatched
if ! grep -qxF 'gateway_enable="YES"' "$target"; then
  echo "Appending to $target..."
  {
    echo ''
    echo 'gateway_enable="YES"'
    echo 'firewall_enable="YES"'
    echo 'firewall_nat_enable="YES"'
    echo 'firewall_script="/etc/ipfw.rules"'
    echo 'firewall_logging="YES"'
    echo 'firewall_logif="YES"'
  } >> "$target"
  echo
fi

# Create /etc/ipfw.rules to forward ports
host="$1"
proto_ports="${2:-$DEFAULT_PORTS}"
target=/etc/ipfw.rules
echo "Selected ports: $proto_ports"
echo "Writing to $target..."
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
} > "$target"
echo
chmod a+x "$target"

# WORKAROUND: IPFW NAT rules do not seem to be applied at start-up
# Force restart of IPFW in /etc/rc.local
target=/etc/rc.local
echo "Writing to $target..."
{
  echo 'sleep 2'
  echo 'logger WORKAROUND: forcing restart of IPFW to ensure working NAT...'
  echo 'service ipfw restart'
} > "$target"
echo
chmod a+x "$target"

# vim: set ts=2 sw=2 sts=2 et:
