# Pi-hole

This is the DNS server for my home network. It blocks ads and trackers for every device that
connects to the Wi-Fi, including phones and TVs where I can't install an ad blocker.

Devices at home use it for DNS because the router gives out the desktop's address as the DNS
server. The admin page is only reachable from my tailnet, so I can check it or allow a blocked
site even when I'm not home.

## How it's set up

| | |
| --- | --- |
| Image | `pihole/pihole` 2026.09.0, pinned by digest |
| Upstream DNS | Quad9 (`9.9.9.9`, `149.112.112.112`) |
| Runs on | Always the desktop |
| Storage | Volume for settings, lists and query history |
| Secrets | Admin password, as a Sealed Secret |

- Port 53 (UDP and TCP) is published with a `hostPort` on the desktop's LAN address. It's the only
  thing in the cluster any device on my home network can reach. It's not forwarded to the
  internet.
- The `hostPort` is tied to that one address on purpose. Without it, it would also catch the
  node's own DNS lookups, and the node couldn't resolve anything, not even to pull Pi-hole's
  image.
- The start script runs as root and then switches to a normal user. The container keeps only the
  permissions it needs, and a pod sysctl lets the normal user use port 53.
- Its NetworkPolicy lets in DNS from my home network and the admin page from Traefik.

## Files

```text
manifests/
  deployment.yaml      Pi-hole, with the hostPort for DNS
  pvc.yaml             Settings and query history
  service.yaml         Admin page, for Traefik
  ingress.yaml         HTTPS route, tailnet only
  networkpolicy.yaml   DNS from home, web from Traefik
  secrets/             Admin password (Sealed Secret)
```

---

Next: [Monitoring](../../infra/monitoring/), how I check on my servers. · [Back to the start](../../)
