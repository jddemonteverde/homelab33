# Portfolio

My portfolio site: projects, experience, tech stack and my blog. It ships the same way as the
[finance app](../finance-app/), but here nobody touches this repository: tagging a release is
enough.

For now it's only reachable from my tailnet. It's built to face the internet later, so it's
locked down as if it already did.

## How it's set up

| | |
| --- | --- |
| Image | `localhost:5000/portfolio`, built by my CI |
| Storage | None. The site is stateless |
| Web | HTTPS through Traefik, tailnet only |
| Secrets | None |

- The namespace enforces the `restricted` Pod Security Standard, so it refuses any pod that isn't
  unprivileged.
- It runs as a non-root user with no capabilities and no Kubernetes API token, and never on the
  desktop, where the parts that can read every secret live.
- Its root filesystem is read-only. The only writable path is the small scratch folder Next wants
  for its cache.
- Its NetworkPolicy only lets in Traefik, and blocks all outgoing traffic: the site makes no
  outbound calls.
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
  networkpolicy.yaml   Traefik in, nothing out
```

---

Next: [Pi-hole](../pihole/), the ad blocker for my home network. · [Back to the start](../../)
