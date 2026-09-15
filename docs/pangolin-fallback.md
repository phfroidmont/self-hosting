# Stellaris Pangolin fallback

Stellaris has a dedicated outer WireGuard-over-WSS fallback through `relay1`.
It is an IPv4 Internet tunnel for networks where Pangolin's native tunnel
cannot establish; it is not another path to private resources.

The workstation enables the fallback automatically only when the active
NetworkManager connection has the explicitly designated guest-profile UUID,
and that connection is the primary connection. Native Pangolin connectivity is
the default everywhere else. The workstation repository owns the actual
NetworkManager primary-connection checks and systemd units.

The fallback carries full IPv4 Internet traffic but does not carry IPv6. Its
WireGuard peer uses a separate key, with the client private key stored locally
at `/etc/secrets/wg-stellaris-fallback.key`; it does not reuse the Foyer WSL
peer key. The relay keeps its existing `wg-relay` public identity. The client
address is `10.250.251.2/32`, separate from the existing WSL routes.

Wstunnel bootstraps against `195.201.112.227` while pinning the TLS hostname
`ws.banditlair.com`. WireGuard and wstunnel use fwmark `51871` so the outer WSS
connection cannot route back into the tunnel and loop. Relay WSS remains
restricted to `127.0.0.1:51820`; neither public UDP 51820 nor SSH is opened.

`relay1` forwards and masquerades only `10.250.251.2/32` from `wg-relay` to
`eth0`, permits only established/related return traffic, and drops all other
forwarding. Private, link-local, CGNAT, metadata, multicast, documentation, and
reserved IPv4 destinations are blocked before Internet egress. Consequently
the fallback cannot bypass Foyer/Pangolin resource authorization, and enabling
IPv4 forwarding does not make the WSL peer or another interface a router.

Deploy the relay change over a known-working 5G connection before switching the
workstation to the designated guest profile. Private relay administration
depends on Pangolin, so changing the workstation first can remove the only
working deployment path.
