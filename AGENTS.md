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
| `infra/` | Cluster components: Argo CD (self-managed from its Helm chart) and Sealed Secrets. Charts are pulled by Argo CD with values from this repo. |
| `apps/` | Workloads (currently Forgejo) as plain Kustomize manifests under `apps/<app>/manifests/`. |

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
- Prefer plain manifests. When a Helm chart is needed, follow `infra/argocd/application.yaml`:
  multi-source Application, pinned chart, values in a `values.yaml` next to it via the `$values`
  ref, no inline values.
- Manifests carry no comments unless something is genuinely non-obvious.
- Hostnames are `<app>.homelab.local` with `ingressClassName: traefik`. Services are plain HTTP
  and only resolvable on the LAN.
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
- Details that identify the home network beyond what is already here: public IPs, WAN domains,
  MAC addresses, router or ISP details. `*.homelab.local` hostnames are fine.

Measures in place:

- Secrets enter the cluster only as `SealedSecret` objects (next section). The decryption key
  never leaves the cluster, so an encrypted secret in git is safe to publish.
- Every image and chart version is pinned, so each deploy is reproducible and reviewable.
- Workloads run rootless where the image supports it.
- Services are published only on `*.homelab.local` hostnames, which resolve on the LAN only.

Rules for agents:

- Any change that widens exposure (`NodePort`, `LoadBalancer`, `hostNetwork`, `privileged`,
  disabling authentication, exposing a service beyond the LAN) must be stated explicitly in your
  response, never slipped into a larger diff.
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
  source on that Application.

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
