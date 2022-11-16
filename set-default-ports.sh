#!/bin/sh

# Author: Kornel Jahn
# License: BSD-3-Clause

# To be sourced by the setup scripts

DEFAULT_PORTS=
DEFAULT_PORTS="$DEFAULT_PORTS tcp/22"     # SSH
DEFAULT_PORTS="$DEFAULT_PORTS tcp/443"    # WebUI HTTPS
DEFAULT_PORTS="$DEFAULT_PORTS tcp/2049"   # NFSv4
DEFAULT_PORTS="$DEFAULT_PORTS tcp/5201"   # iperf3
DEFAULT_PORTS="$DEFAULT_PORTS tcp/28757"  # WebUI VM VNC