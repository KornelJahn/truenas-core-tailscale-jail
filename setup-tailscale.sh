#!/bin/sh

# Author: Kornel Jahn
# License: BSD-3-Clause

if [ $# -lt 1 ]; then
  echo "usage: $(basename "$0") <tailscale-auth-key>" 1>&2
  exit 1
fi

# Install Tailscale
pkg install -y tailscale

# Enable and bring up Tailscale
service tailscaled enable
service tailscaled start
tailscale up --authkey "$1"

# vim: set ts=2 sw=2 sts=2 et:
