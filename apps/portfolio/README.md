# Portfolio

My portfolio site: projects, experience, tech stack and my blog. It ships the same way as the
[finance app](../finance-app/), but here nobody touches this repository: tagging a release is
enough.

It's the one app in this cluster that's open to the internet, at
[jddemonteverde.com](https://jddemonteverde.com), through a Cloudflare Tunnel. The tunnel only
connects out, so no port is open on my router, and it can reach nothing but this site.

## How it's set up

| | |
| --- | --- |
| Image | `localhost:5000/portfolio`, built by my CI |
| Storage | None. The site is stateless |
| Web | Public through a Cloudflare Tunnel; HTTPS through Traefik on my tailnet |
| Secrets | The tunnel's token, as a Sealed Secret |

- The namespace enforces the `restricted` Pod Security Standard, so it refuses any pod that isn't
  unprivileged.
- It runs as a non-root user with no capabilities and no Kubernetes API token, and never on the
  desktop, where the parts that can read every secret live.
- Its root filesystem is read-only. The only writable path is the small scratch folder Next wants
  for its cache.
- Its NetworkPolicy only lets in Traefik and the tunnel, and blocks all outgoing traffic: the site
  makes no outbound calls.
- The tunnel (`cloudflared`) runs locked down the same way. It accepts no connections, and may
  reach only DNS, the site, and Cloudflare on port 7844. Its route to the site is set in
  Cloudflare's dashboard, which also serves the public HTTPS certificate.
- It has its own Argo CD project, which deploys only into the `portfolio` namespace and creates
  nothing cluster-wide except that namespace. CI commits here, so a bad commit stays inside it.

## Releasing a new version

1. Push a `v*` tag to the app's repository on Forgejo.
2. CI builds and pushes `portfolio:<version>`. Once the image is in the registry, it commits the
   new tag to `manifests/deployment.yaml` here, as `portfolio ci`.
3. Argo CD deploys it.

## Files

```text
appproject.yaml        Argo CD project: the portfolio namespace only
application.yaml       Argo CD Application
manifests/
  namespace.yaml       Namespace, restricted Pod Security
  deployment.yaml      The site
  service.yaml         Web port, for Traefik
  ingress.yaml         HTTPS route, tailnet only
  networkpolicy.yaml   Traefik and the tunnel in, nothing out but the tunnel's own
  cloudflared.yaml     The Cloudflare Tunnel
  secrets/             The tunnel's token, sealed
```

---

Next: [Pi-hole](../pihole/), the ad blocker for my home network. · [Back to the start](../../)
