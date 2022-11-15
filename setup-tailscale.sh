#!/bin/sh

# Author: Kornel Jahn
# License: BSD-3-Clause

# Install Tailscale
pkg install -y tailscale

# Enable and bring up Tailscale
service tailscaled enable
service tailscaled start
tailscale up --authkey "${SETUP_AUTHKEY:?}"

# vim: set ts=2 sw=2 sts=2 et:
