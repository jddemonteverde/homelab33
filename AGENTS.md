# AI agent instructions

`AGENTS.md` is the canonical instruction file for every AI coding agent working in this
repository (Codex, Claude Code, and others). `CLAUDE.md` only imports it.

This is a **public** GitOps repository for a home Kubernetes cluster. Argo CD watches the `main`
branch and applies whatever is committed there, so every merged change is live and every
committed byte is public.

## Repository layout

| Path | Purpose |
| --- | --- |
| `bootstrap/` | The two root Argo CD Applications (`infra` at sync-wave 0, `apps` at wave 1). Applied once by hand with `kubectl apply -k bootstrap`; not synced by Argo CD itself. |
| `infra/` | Cluster components: Argo CD (self-managed from its Helm chart), Sealed Secrets, cert-manager, the Tailscale proxy that puts Traefik on the tailnet, the CoreDNS override, and Traefik settings. Charts are pulled by Argo CD with values from this repo; k3s's bundled Traefik is tuned through a `HelmChartConfig`. |
| `apps/` | Workloads (Forgejo, its Actions runner, finance-app, the in-cluster registry, Pi-hole) as plain Kustomize manifests under `apps/<app>/manifests/`. |

Each directory is a Kustomize base whose `kustomization.yaml` explicitly lists its children, so
any part of the tree can be built with `kubectl kustomize <dir>`.

## Conventions

- One Kubernetes object per file, named after the kind (`deployment.yaml`, `service-http.yaml`,
  `pvc.yaml`).
- Every directory has a `kustomization.yaml`; adding a file means adding it to that list.
- New app: create `apps/<name>/application.yaml`, `apps/<name>/kustomization.yaml` and
  `apps/<name>/manifests/`, then add `- <name>` to `apps/kustomization.yaml`. Infra components
  follow the same shape under `infra/`.
- Removing an app: delete its line from the parent `kustomization.yaml`. Applications sync with
  `prune: true`, so this uninstalls it from the cluster. Deleting a PVC from git deletes the
  volume and its data.
- Pin every image tag and every chart `targetRevision`. Never `latest`.
- Prefer rootless images and set `securityContext` (see `apps/forgejo/manifests/deployment.yaml`).
- Node placement: anything that can read every Secret or administer the cluster (Argo CD, Sealed
  Secrets, Traefik, cert-manager) runs only on the control-plane node
  (`nodeSelector: node-role.kubernetes.io/control-plane: "true"`). CI (`forgejo-runner`,
  `buildkitd`) runs code from workflows and must never run there (required node affinity:
  `node-role.kubernetes.io/control-plane` `DoesNotExist`). New components follow the same split.
  The Tailscale proxy (`infra/tailscale-proxy`) also runs on the control plane, because it holds
  the cluster's tailnet identity. It runs unprivileged (userspace networking) in a namespace that
  enforces the `restricted` Pod Security Standard; keep it that way.
- NetworkPolicies: each app namespace has a policy that selects all its pods and allows ingress
  only from Traefik on the app's port, plus any source it names. `forgejo-runner` also denies
  egress except DNS, Forgejo, Traefik, `buildkitd` and the internet. `tailscale` accepts nothing
  and may reach only DNS, Traefik, the Kubernetes API, the internet, and UDP on the LAN. The
  registry admits only `registry-proxy`, which relays the nodes' image pulls, and `buildkitd`.
  `pihole` also admits DNS (port 53) from the LAN.
- LAN DNS: Pi-hole (`apps/pihole`) is the home network's DNS server and the cluster's only LAN
  listener. Its pod publishes `hostPort` 53 (UDP and TCP) on the control-plane node's LAN
  address (`hostIP`), which the router hands out as the DNS server, so never drop its
  `nodeSelector`. Keep the `hostIP`: without it the rule also captures the node's own resolver
  (`127.0.0.53`), and the node can't resolve names, not even to pull Pi-hole's image. The
  official image's start script runs as root and drops FTL to an unprivileged user; the
  container keeps only the capabilities that script needs,
  `allowPrivilegeEscalation: false` keeps FTL at none, and the pod sysctl
  `net.ipv4.ip_unprivileged_port_start` lets it bind port 53. Like `registry`, its namespace
  can't enforce the `baseline` Pod Security Standard, which forbids `hostPort`. Its admin UI is
  an ordinary tailnet-only Ingress.
- CI builds: jobs get no Docker socket (`docker_host: "-"`). Workflows build and push images on
  the rootless `buildkitd` in `forgejo-runner`, using
  `docker buildx create --driver remote tcp://buildkitd.forgejo-runner.svc.cluster.local:1234`.
  They push to the in-cluster registry as `10.43.200.10:5000/<app>:<tag>`, over plain HTTP.
- Container images: Deployments use `localhost:5000/<app>:<tag>`. containerd pulls on the node,
  where cluster DNS doesn't resolve and only HTTPS with a trusted certificate is accepted, except
  from `localhost`, which it accepts over plain HTTP with no node config. `registry-proxy` (a
  DaemonSet in `apps/registry`, official `haproxy` image) runs on every node and forwards
  `127.0.0.1:5000` to the registry (official `registry` image, no authentication, so no pull
  secrets). Its `hostPort` is bound to `127.0.0.1`; never drop that `hostIP`, or the registry is
  open to the LAN. Don't add node config (`registries.yaml`); manifests must work on a managed
  cluster too. Forgejo's container registry is not used: its token URL comes from Forgejo's
  `ROOT_URL`, which nodes can't reach.
- When a ConfigMap mounted by a Deployment changes, set that Deployment's `checksum/config`
  annotation to the output of `shasum -a 256 <configmap file>` so its pods restart.
- Prefer plain manifests. When a Helm chart is needed, follow `infra/argocd/application.yaml`:
  multi-source Application, pinned chart, values in a `values.yaml` next to it via the `$values`
  ref, no inline values.
- Manifests carry no comments unless something is genuinely non-obvious.
- Hostnames are `<app>.lab.jddemonteverde.com` with `ingressClassName: traefik`, served over
  HTTPS and reachable only from the tailnet. Traefik has no LAN listener (its Service is
  `ClusterIP`, set in `infra/traefik`) and redirects HTTP to HTTPS. An app that pods call by its
  lab name (Forgejo, for Actions checkouts) also needs a rewrite in `infra/coredns-custom`,
  because publicly the name points at a Tailscale address pods can't reach.
- Traefik serves the Let's Encrypt wildcard certificate for `*.lab.jddemonteverde.com` as its
  default (the `TLSStore` named `default` in `infra/traefik`), so an Ingress under that name
  needs no `tls:` section.
- Before committing, run `kubectl kustomize <dir>` for every directory you touched and confirm it
  builds.

## Security

The repository is public. Treat every commit as permanently published: rewriting history does not
un-leak anything, only rotating the credential does.

Never commit:

- Passwords, tokens, API keys, or SSH/TLS/private keys.
- Kubeconfigs, `.env` files, or Helm values that contain credentials.
- Plaintext `kind: Secret` objects (`data` or `stringData`), including `kubectl get secret` output.
- Argo CD's `argocd-initial-admin-secret`, Forgejo's `SECRET_KEY` / `INTERNAL_TOKEN` /
  `JWT_SECRET` / `LFS_JWT_SECRET`, or any other generated credential.
- Secret values in commit messages, comments, or file names.
- Details that identify the home network beyond what is already here: public IPs, MAC
  addresses, router or ISP details, or domains other than the ones below. `*.homelab.local` and
  `*.lab.jddemonteverde.com` hostnames are fine; the latter appear in public certificate logs
  anyway. The one LAN address allowed is the control-plane node's, in `apps/pihole` (Pi-hole's
  `hostIP`); don't add other LAN addresses.

Measures in place:

- Secrets enter the cluster only as `SealedSecret` objects (next section). The decryption key
  never leaves the cluster, so an encrypted secret in git is safe to publish.
- Every image and chart version is pinned, so each deploy is reproducible and reviewable.
- Workloads run rootless where the image supports it.
- Services are published only on `*.lab.jddemonteverde.com`, over HTTPS. Traefik has no LAN
  listener; it is reachable only from the tailnet, through the Tailscale proxy (tagged
  `tag:k8s-ingress`), which
  the tailnet policy grants only to tailnet members, on ports 80 and 443. It joined with a
  single-use key, so no reusable Tailscale credential is stored anywhere. Nothing is exposed to
  the internet; never enable Tailscale Funnel.
- The one LAN listener is Pi-hole's DNS on port 53 of the control-plane node. It answers any LAN
  device; never forward port 53 to it from the internet.
- CI is contained: jobs have no Docker socket, images build on rootless BuildKit, and CI pods
  never share a node with the controllers that can read every Secret.
- App namespaces accept traffic only from Traefik and the sources their NetworkPolicy names.

Rules for agents:

- Any change that widens exposure (`NodePort`, `LoadBalancer`, `hostNetwork`, `privileged`,
  mounting a Docker socket, loosening a NetworkPolicy or the node placement rules, disabling
  authentication, exposing a service beyond the LAN) must be stated explicitly in your response,
  never slipped into a larger diff.
- Do not run cluster-mutating commands (`kubectl apply`, `delete`, `edit`, `argocd app sync`).
  The cluster is changed only through git. Read-only commands (`kubectl get`, `kubectl kustomize`)
  are fine when the task calls for them.
- If a secret is committed by accident, tell the owner immediately so it can be rotated, then
  remove it.

Optional hardening not yet added: a `.gitignore` for `.env*`, `*.pem`, `*.key`, `kubeconfig*`,
and a gitleaks pre-commit hook or GitHub Action.

## Secrets: Sealed Secrets

The Sealed Secrets controller runs in `kube-system` as `sealed-secrets-controller`, installed from
`infra/sealed-secrets/`. It holds the private key; `kubeseal` encrypts with the matching public
certificate, and the resulting `SealedSecret` is safe to publish. The controller decrypts it into
a normal `Secret` in the cluster.

- The private key exists only in the cluster. Back it up outside this repository
  (`kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml`).
  Losing it makes every `SealedSecret` in git unrecoverable. The public certificate
  (`kubeseal --fetch-cert`) is safe to share.
- Location: `apps/<app>/manifests/secrets/<secret-name>.yaml`, one `kind: SealedSecret` per file,
  listed in `secrets/kustomization.yaml`, which the app's `manifests/kustomization.yaml` includes.
  Nothing but `SealedSecret` objects belongs in a `secrets/` directory.
- Create one with a pipe so the plaintext `Secret` is never written to disk inside the repo:

  ```sh
  kubectl create secret generic <name> -n <namespace> --from-literal=KEY=value \
    --dry-run=client -o yaml | kubeseal --format yaml > apps/<app>/manifests/secrets/<name>.yaml
  ```

  `kubeseal` needs cluster access (`brew install kubeseal`). With the controller name and
  namespace above it needs no extra flags.
- Sealed Secrets use `strict` scope: the `SealedSecret`'s `metadata.name` and `namespace` must
  match the target `Secret`. Re-seal if either changes.
- Workloads consume the decrypted `Secret` by name (`secretKeyRef`, `envFrom`, or a volume),
  never by inlining values.
- Infra components installed from Helm charts have no manifests path. If one ever needs a
  `SealedSecret`, add `infra/<component>/secrets/` and reference it as an additional `path:`
  source on that Application. Objects that use the chart's own CRDs (cert-manager's issuers and
  certificate) go in `infra/<component>/manifests/`, another `path:` source, annotated
  `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource=true`.

## Commit messages

Conventional Commits, **one line only**:

```text
<type>(<scope>): <subject>
```

- Types: `feat`, `fix`, `chore`, `refactor`, `style`, `docs`, `ci`, `revert`.
- Scope: the app or component directory (`forgejo`, `argocd`, `sealed-secrets`, `bootstrap`).
  Omit it for repo-wide changes.
- Subject: imperative mood, lowercase, no trailing period, at most 72 characters, describing
  what changed in the repository (not what happened in the conversation).
- No body, no footer, no trailers. Do not add `Co-Authored-By` or any other attribution line.
- One logical change per commit. Read `git diff --cached` before writing the message.

Examples from this repository's history:

```text
chore(forgejo): bump PVC to 50Gi for container registry storage
fix(forgejo): drop oci:// scheme from Helm repoURL
refactor: one object per file, per-app dirs under bootstrap
```

Messages such as `update`, `fix stuff`, `wip`, `changes`, or `misc` are not acceptable.

Do not commit or push unless the owner asks.
