# infra

These are the parts that keep the cluster running. You don't use them directly, but every app
depends on them.

| Folder | What it does |
| --- | --- |
| `argocd/` | Argo CD. It watches `main` and updates the cluster to match, including itself |
| `sealed-secrets/` | Decrypts the encrypted secrets stored in this repo. The key never leaves the cluster |
| `cert-manager/` | Gets a Let's Encrypt wildcard certificate for my lab domain and renews it |
| `traefik/` | Settings for Traefik, which comes with k3s and routes HTTPS to the apps |
| `tailscale-proxy/` | Connects Traefik to my tailnet. It's the only way into my apps |
| `coredns-custom/` | Lets pods reach my apps by their hostnames from inside the cluster |
| [`monitoring/`](monitoring/) | Prometheus and Grafana |

Helm charts are pinned to a version and use the `values.yaml` in their folder.

## How I open an app

```text
my phone or laptop, on the tailnet
   │  HTTPS
   ▼
Tailscale proxy ──► Traefik ──► app
```

Traefik isn't open to my home network, only to the Tailscale proxy. It also redirects HTTP to
HTTPS.

## How a change gets to the cluster

```text
push to main ──► Argo CD ──► bootstrap/infra (first) ──► infra/*
                        └──► bootstrap/apps  (second) ──► apps/*
```

Argo CD syncs on its own. If I delete something from git, it's removed from the cluster too.

## Which machine runs what

Anything that can read every secret or manage the cluster (Argo CD, Sealed Secrets,
cert-manager, Traefik, the Tailscale proxy, monitoring) only runs on the desktop. CI only runs on
the laptop.

---

That's the whole tour. [Back to the start](../)
