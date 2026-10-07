# homelab33

GitOps repository for my home Kubernetes cluster: two retired machines, an old desktop PC and an
old laptop, running [k3s](https://k3s.io) at home. [Argo CD](https://argo-cd.readthedocs.io)
watches the `main` branch and applies whatever is committed here, so this repository *is* the
cluster: every merged change goes live, and nothing is changed by hand with `kubectl`.

It's public so others can borrow ideas. Secrets are committed only in encrypted form (see
[Secrets](#secrets)).

## Hardware

| Node | Role | Runs |
| --- | --- | --- |
| Old desktop PC | k3s server (control plane) | Argo CD, Sealed Secrets, cert-manager, Traefik, the Tailscale proxy, monitoring, Pi-hole |
| Old laptop | k3s agent (worker) | Apps and CI (the Forgejo Actions runner and BuildKit) |

Anything that can read every Secret or administer the cluster stays on the control-plane node;
CI, which runs code from workflows, is never allowed there.

## What's running

| Service | What it is | URL |
| --- | --- | --- |
| [Forgejo](https://forgejo.org) | Self-hosted Git forge; this repo's origin | `forgejo.lab.jddemonteverde.com` |
| Forgejo Actions runner | CI for Forgejo, building images on rootless BuildKit | — |
| Registry | In-cluster container registry for images built by CI | — (cluster only) |
| finance-app | A personal finance app, built and deployed from Forgejo | `finance.lab.jddemonteverde.com` |
| portfolio | My portfolio site and blog, built and deployed from Forgejo | `portfolio.lab.jddemonteverde.com` |
| [Pi-hole](https://pi-hole.net) | Network-wide DNS and ad blocking for the home LAN | `pihole.lab.jddemonteverde.com` |
| Grafana + Prometheus | Cluster and node monitoring (kube-prometheus-stack) | `grafana.lab.jddemonteverde.com` |

Every web UI is served over HTTPS and reachable only from my [Tailscale](https://tailscale.com)
tailnet. Nothing is exposed to the internet.

## How it fits together

```text
             tailnet (my devices)                         home LAN
                    │                                         │
                    ▼                                         ▼ DNS :53
           Tailscale proxy pod ──► Traefik (ClusterIP) ──►  Pi-hole
                                       │  *.lab.jddemonteverde.com
                                       │  (Let's Encrypt wildcard cert)
                                       ▼
                         Forgejo · finance-app · portfolio · Grafana · Pi-hole UI

 git push ──► Forgejo ──► GitHub mirror ──► Argo CD ──► cluster
                │
                └─► Actions runner ──► BuildKit ──► registry ──► Deployments
```

- **GitOps.** Two root Argo CD Applications in `bootstrap/` point at `infra/` (sync-wave 0) and
  `apps/` (sync-wave 1). Each child Application syncs automatically with pruning and self-heal,
  so removing something from git uninstalls it from the cluster.
- **Ingress.** k3s's bundled Traefik has no LAN listener. A Tailscale proxy, running unprivileged
  in userspace mode, joins the tailnet and forwards ports 80/443 to Traefik, which redirects
  HTTP to HTTPS.
- **TLS.** cert-manager obtains a wildcard certificate for `*.lab.jddemonteverde.com` from
  Let's Encrypt with a Cloudflare DNS-01 challenge. Traefik serves it as its default
  certificate, so Ingresses need no `tls:` section.
- **DNS.** Pi-hole is the LAN's DNS server, published with a `hostPort` on the control-plane
  node. A CoreDNS override lets pods reach lab hostnames (for example, Forgejo for Actions
  checkouts) without going through Tailscale.
- **CI and images.** Workflows on the Forgejo runner get no Docker socket; they build on a
  rootless BuildKit daemon and push to the in-cluster registry. A small HAProxy DaemonSet on
  each node exposes the registry on `127.0.0.1:5000`, so containerd can pull
  `localhost:5000/<app>:<tag>` with no node configuration.
- **Monitoring.** kube-prometheus-stack (Prometheus, Grafana, node-exporter). Dashboards live in
  `infra/monitoring/manifests/dashboards/` as JSON and are edited through git.

## Repository layout

```text
bootstrap/   Root Argo CD Applications (infra, apps); applied once by hand
infra/       Cluster components
  argocd/          Argo CD, managing itself from its Helm chart
  sealed-secrets/  Controller that decrypts SealedSecrets
  cert-manager/    Let's Encrypt wildcard certificate
  traefik/         Settings for k3s's bundled Traefik
  tailscale-proxy/ Puts Traefik on the tailnet
  coredns-custom/  In-cluster DNS rewrites for lab hostnames
  monitoring/      Prometheus and Grafana
apps/        Workloads, as plain Kustomize manifests
  forgejo/  forgejo-runner/  registry/  finance-app/  pihole/  portfolio/
```

Every directory is a Kustomize base, so any part of the tree can be rendered locally:

```sh
kubectl kustomize apps/forgejo
```

Helm charts (Argo CD, Sealed Secrets, cert-manager, kube-prometheus-stack) are installed as
multi-source Argo CD Applications with pinned versions and values files kept next to them.
Everything else is plain YAML, one object per file.

## Stack

| Component | Version |
| --- | --- |
| Argo CD (argo-cd chart) | 10.9.2 |
| cert-manager | v1.21.2 |
| Sealed Secrets (chart) | 2.20.0 |
| kube-prometheus-stack | 91.9.0 |
| Forgejo | 15.0.9 (rootless) |
| Forgejo runner | 13.2.0 |
| BuildKit | v0.33.0 (rootless) |
| Tailscale | v1.102.4 |
| Pi-hole | 2026.09.0 |

Every image tag and chart version is pinned; nothing uses `latest`.

## Secrets

Secrets are stored as [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets): encrypted
with the controller's public key and decryptable only inside the cluster. A plaintext `Secret`
never touches the repo:

```sh
kubectl create secret generic <name> -n <namespace> --from-literal=KEY=value \
  --dry-run=client -o yaml | kubeseal --format yaml > apps/<app>/manifests/secrets/<name>.yaml
```

The controller's private key is backed up outside this repository.

## Security

- Nothing is reachable from the internet; web UIs are tailnet-only, and the Tailscale node joined
  with a single-use key.
- The only LAN-facing listeners are Pi-hole's DNS and node-exporter, which sits behind
  kube-rbac-proxy and requires a Kubernetes-authorized token.
- Every app namespace has a NetworkPolicy that admits traffic only from Traefik and the sources
  it names; the CI namespace also restricts egress.
- Workloads run rootless with a restricted `securityContext` wherever the image allows.
- CI jobs get no Docker socket and never share a node with cluster controllers.

## Bootstrapping from scratch

1. Install k3s on the desktop (server) and join the laptop as an agent.
2. Install Argo CD once by hand (it then takes over managing itself from `infra/argocd`).
3. Apply the root Applications:

   ```sh
   kubectl apply -k bootstrap
   ```

4. Argo CD installs `infra/`, then `apps/`. Sealed Secrets in this repo are tied to my cluster's
   key; on a new cluster, restore that key or re-seal each secret.

## Making changes

1. Edit manifests on a branch and check they build with `kubectl kustomize <dir>`.
2. Merge to `main`. Argo CD syncs within a few minutes.

Commits follow [Conventional Commits](https://www.conventionalcommits.org), scoped to the
component, e.g. `feat(monitoring): add a dashboard ranking pods and workloads by usage`.
`AGENTS.md` holds the full conventions for anyone (or any AI agent) working in the repo.
