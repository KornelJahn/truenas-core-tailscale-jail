# Setting up Tailscale on TrueNAS Core

## Introduction

The goal of this guide is to work around the lack of a built-in Tailscale System Service in TrueNAS Core and enable

- accessing your NAS services from your tailnet (tailnet-to-host direction),
- accessing other tailnet machines from the NAS (host-to-tailnet direction).

It is assumed that you already have a Tailscale account and run a TrueNAS Core 13.0 server. Tailscale is going to be installed in a jail.

This solution relies on IPFW, FreeBSD's user interface for firewall & in-kernel NAT. Links to relevant documentation are available here: [handbook section][IPFWHandbook] and [man page][IPFWManPage].

:warning: IPFW NAT does not work for me on TrueNAS Core 12.0-U8.1. It is probably buggy, see section below on [IPFW issues](#ipfw-issues). :warning:

### History

This guide is based upon the great [How-To][AndrewShumateHowTo] by *AndrewShumate* on installing Tailscale in a TrueNAS Core jail. At the end, he recommends to turn the Tailscale client in the jail into a subnet router via the `--advertise-routes` command-line option. This guide, however, takes a different approach by **not** activating the subnet router functionality Tailscale itself, but turns the jail itself into a router using IPFW.

Setting up a functioning IPFW-based solution has proven to be difficult, partially due to my own lack of experience and also due to the [issues](#ipfw-issues) I have encountered. Also, relying on IPFW seems to be a controversial topic in the community according to [this comment][sretallaNginxConfig] by *sretalla*. However, IPFW can provide access in both directions at the layer where this problem should probably be handled.

An alternative (partial) solution would be using a [reverse proxy][sretallaIdea] such as `nginx`, which could replace port forwarding in the tailnet-to-host direction. A crude implementation of this concept is also provided by the script `setup-reverse-proxy.sh`, based on the [example][sretallaNginxConfig] by *sretalla*.

The solution contained in this repo is meant to be temporary until an official Tailscale System Service or Plugin is introduced. Please support the [Jira ticket][JiraTicket] gathering interest for a Tailscale System Service in TrueNAS Core!

### Acknowledgements

Many thanks to *AndrewShumate*, *sretalla*, and *jgreco* for their valuable comments and kind support!

## Setup steps

### Creating a dedicated jail for Tailscale

1. Create a new Jail via *Jails / Add / Advanced Jail Creation*. Name it under *Basic Properties / Name*. By default, the name of the jail will also be its hostname (can be changed in the jail). Tailscale by default associates this hostname with the tailnet machine.

2. For *Release*, currently, `13.1-RELEASE` **must** be chosen. See section below on [IPFW issues](#ipfw-issues) for more information.

3. Check *VNET*. We will not use *NAT* here, so leave it unchecked (the jail will get an IP address on the same subnet as the host). In this guide, we will rely on our local DHCP server to assign an IP address to the jail, so ensure *DHCP Autoconfigure IPV4* is checked. Ensure that the IP address of the jail is stable, by setting up a static DHCP lease. Alternatively, you can leave *DHCP Autoconfigure IPV4* unchecked and simply assign a static IP address to the jail. The *Berkeley Packet Filter* is probably enabled automatically, ensure that it is checked. Note that IPv6 is not covered in this guide.

4. Turn on `Auto-start`.

5. (Optional) Uncheck *Jail Properties / allow_set_hostname* if the automatic setting of jail name as jail hostname is appropriate.

6. Check *Custom Properties / allow_tun*.

7. Save and wait for the jail to be created.

### Setting up the jail

8. In the drop-down section of the jail, start it and request a shell to the jail.

9. Clone this repository into the jail as
   ```
   pkg install -y git
   git clone https://github.com/KornelJahn/truenas-core-tailscale-jail.git
   cd truenas-core-tailscale-jail
   ```

10. On the Tailscale web admin interface, generate an auth key under *Settings / Keys / Auth keys / Generate auth key...*. Enable *Pre-authorized* for a quicker process, click *Generate key*, and copy the auth key.

11. In the jail shell, run the Tailscale setup script as
    ```
    ./setup-tailscale.sh <tailscale-auth-key>
    ```
    Ensure that your tailnet can be accessed by checking
    ```
    tailscale status
    ```
    inside the jail.

12. Next, run the IPFW NAT setup script:
    ```
    ./setup-ipfw-nat.sh <host-ip-address> [<ports>]
    ```
    where the `<ports>` argument is optional. It can be used to configure forwarded ports, and takes the following format: `'proto1/port1 proto2/port2 ...'`. For instance,
    ```
    ./setup-ipfw-nat.sh 192.168.1.2 'tcp/22 tcp/443'
    ```
    would set up forwading SSH and HTTPS connections, respectively, to `192.168.1.2`. For the default port selection, see the helper script [`set-default-ports.sh`](set-default-ports.sh).

13. Restart the jail.

### Configuring TrueNAS routing and DNS for the TrueNAS host

14. The TrueNAS host needs to be configured to route tailnet IP addresses `100.64.0.0/10` through the jail as gateway. If the TrueNAS host has a static IP address, it is enough to add a static route under *Network / Static Routes*, with *Destination* `100.64.0.0/10`, and *Gateway* set to the (stable) IP address of the jail. However, if the TrueNAS host uses DHCP to get its (statically leased) IP address, rather set the jail IP address as the default gateway under *Network / Global Configuration / Default Gateway / IPv4 Default Gateway*. As discussed in [this forum thread][DHCPStaticRouteThread], setting static routes is incompatible with DHCP, since -- as *jgreco* mentioned -- *"when an IP interface is reconfigured, in many cases, IP routes via that interface are cleared by the kernel."* Having configured routing, save the new settings.

15. The tailnet jail then needs to be configured to route traffic from tailnet clients to local addresses. First stop tailscale by typing
```
tailscale down
```
Then bring it back up using the `--advertise-routes` flag
```
tailscale up --advertise-routes=<subnet1>/<netmask>,<subnet2>/<netmask>
```
So if the jail's address was 192.168.0.200 with a subnet mask of 255.255.255.0 and the remote address was 10.0.0.130 with a mask of 255.0.0.0 the command would look like
```
tailscale up --advertise-routes=192.168.0.0/24,10.0.0.0/8
```
16. After advertising the route from the tailscale jail it has to be authorized from the tailscale web admin portal. After approving both subnet connections traffic will be able to be routed between the jail's local network and the rest of your tailnet.

17. (Optional) If MagicDNS is used in Tailscale, you can configure your TrueNAS host to resolve tailnet FQDNs and hostnames. Relying on functioning routing to the jail, do so by adding the MagicDNS of the jail server at `100.100.100.100` under *Network / Global Configuration / DNS Servers / Nameserver 1*. The MagicDNS server will take care of non-tailnet DNS resolution by falling back either to the default DNS servers or to those set up in the Tailscale web admin interface. This setting will let you refer to tailnet machines as `<hostname>.<tailnet-name>.ts.net` (substitute appropriate values). To simply use machine hostnames, the search domain `<tailnet-name>.ts.net` needs to be added under *Network / Global Configuration / Hostname and Domains / Additional Domains*. Save the new settings.

18. Test the new configuration (restart of the host system may be required beforehand, as noted by [@larsyunker](https://github.com/larsyunker/)). In the TrueNAS host shell, try to ping another machine on your tailnet by IP address and by FQDN (if MagicDNS is used). From another machine on your tailnet, try to access the WebUI of TrueNAS via its tailnet IP address and its tailnet FQDN.

## Setup scripts

Setup script `setup-tailscale.sh` installs Tailscale in the jail and activates it using the pre-defined auth key.

Script `setup-ipfw-nat.sh` perfoms the following tasks:

- modifies `/etc/rc.conf` to enable the IPFW firewall & in-kernel NAT services with logging with a dedicated `ipfw0` virtual interface for diagnostics;
- extends `/etc/sysctl.conf` to disable TCP segmentation offload (required) and sets IPFW logging verbosity to 0 to enable inspecting traffic on `ipfw0`;
- generates the `/etc/ipfw.rules` script that sets up IPFW; and
- creates/extends `/etc/rc.local` to create a workaround for the bug that `ipfw nat` is not set up on jail start-up.

Alternative script `setup-reverse-proxy.sh` sets up an `nginx` reverse proxy to forward ports in the tailnet-to-host direction. It takes the same arguments as `setup-ipfw-nat.sh`.

## Diagnostics

### ipfw-related

The active IPFW rules can be checked using
```
ipfw list
```
and the NAT configuration using
```
ipfw nat show config
```
while NAT log counters can be inspected using
```
ipfw nat show log
```
For packet-level diagnostics, `tcpdump` on interface `ipfw0` may be run in the jail, e.g. as
```
tcpdump -ptni ipfw0
```

For more information on IPFW logging, see the *RULE FORMAT / log* section of the [man page][IPFWManPage].

### General

Network interface parameters can be checked using `ifconfig`, the routing table using `netstat -rn`, and DNS resolution using `host -v`. Finally, the kernel message log is found at `/var/log/messages`.

## IPFW issues

When trying to set up NAT through IPFW, I encountered the following issues, probably due to bugs in the implementation of IPFW NAT configuration.

To reproduce them, use the included script `setup-ipfw-nat.sh` to set up `/etc/ipfw.rules` and then run `service ipfw restart`.

The `/sbin/ipfw nat 1 config` command that fails should be correct in principle, as the IPFW man page contains an analogous `redirect_port` example.

Root causes for the errors below are probably found in the `sbin/ipfw/nat.c` [file][IPFWNatC] of previous versions of the FreeBSD source code but I haven't had time to track them down.

### TrueNAS Core 12.0

Error message:
```
ipfw: unknown redir mode
```
Exact TrueNAS Core version was 12.0-U8.1 and FreeBSD 12.3-RELEASE-p8.
A likely related issue [showed up in 2014][IPFWUnknownRedirMode].

### TrueNAS Core 13.0

Error message:
```
ipfw: setsockopt(IP_FW_NAT44_XCONFIG): Invalid argument
```
Exact TrueNAS Core version was 13.0-U3 and FreeBSD 13.0-RELEASE-p13.
A likely related issue [was reported in 2021][IPFWSetsockoptInvalidArg].

Even using FreeBSD 13.1-RELEASE-p3, there is an issue with IPFW NAT rules not being applied on jail start-up which has been worked around as mentioned above.

[AndrewShumateHowTo]: https://www.truenas.com/community/threads/howto-install-tailscale-in-a-jail.98910/
[DHCPStaticRouteThread]: https://www.truenas.com/community/threads/static-routes-only-set-at-boot.99119/post-683814
[JiraTicket]: https://ixsystems.atlassian.net/browse/NAS-110540
[IPFWHandbook]: https://docs.freebsd.org/en/books/handbook/firewalls/#firewalls-ipfw
[IPFWManPage]: https://www.freebsd.org/cgi/man.cgi?ipfw(8)
[IPFWNatC]: https://github.com/freebsd/freebsd-src/blob/main/sbin/ipfw/nat.c
[IPFWSetsockoptInvalidArg]: https://lists.freebsd.org/archives/freebsd-current/2021-September/000605.html
[IPFWUnknownRedirMode]: https://mailing.freebsd.ipfw.narkive.com/LbfKJTOf/does-nat-redirect-port-tcp-works-for-you-on-current
[sretallaIdea]: https://www.truenas.com/community/threads/howto-install-tailscale-in-a-jail.98910/post-684564
[sretallaNginxConfig]: https://www.truenas.com/community/threads/use-jail-to-nat-traffic-from-vpn-to-specific-machine.97557/post-673571
