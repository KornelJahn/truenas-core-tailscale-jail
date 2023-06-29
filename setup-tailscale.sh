#!/bin/sh

# Author: Kornel Jahn
# License: BSD-3-Clause

if [ $# -lt 1 ]; then
  echo "usage: $(basename "$0") <tailscale-auth-key> [extra-tailscale-up-flags]" 1>&2
  exit 1
fi

# Install Tailscale
pkg install -y tailscale

# Enable and bring up Tailscale
service tailscaled enable
service tailscaled start
authkey="$1"
shift
tailscale up --authkey "$authkey" $@

# vim: set ts=2 sw=2 sts=2 et:
