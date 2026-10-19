# Disaster recovery

What I'd need to rebuild this cluster if a machine died, and how. Everything Argo CD applies is
in git, so most of the cluster comes back by itself. What doesn't come back is data on the
volumes, a few secrets that only exist in the cluster, and the machines themselves.

There are no automated backups yet. The backups below are taken by hand, and I haven't done a
full restore yet. The first real one will correct this page.

## What holds state

All volumes use k3s's `local-path` storage, so each one is a folder on one machine's disk, under
`/var/lib/rancher/k3s/storage/`. If that disk dies, the volume is gone.

| What | Where | If it's lost |
| --- | --- | --- |
| **Sealed Secrets private key** | Secret in `kube-system`, desktop | Every `SealedSecret` in git becomes unreadable. Every secret has to be recreated and resealed |
| Forgejo: repositories, issues, Actions secrets, users | `forgejo-data` (50 Gi), laptop | Repositories on Forgejo only, and everything else in Forgejo |
| finance-app database (SQLite) | `finance-app-data` (2 Gi), laptop | All finance data |
| Pi-hole settings and lists | `pihole-data` (1 Gi), desktop | Custom lists and settings. Query history doesn't matter |
| Tailscale node identity | Secret `tailscale-state`, desktop | The proxy needs a new auth key, and the lab DNS record a new address |
| Registry images | `registry-data` (5 Gi), laptop | Nothing lasting: re-run each app's release workflow |
| Grafana | `monitoring-grafana` (2 Gi), desktop | Nothing: dashboards are in git |
| Prometheus | 20 Gi volume, desktop | Metrics history only |
| Portfolio | `portfolio-data` (1 Gi), laptop | Old data from a contact form the site no longer has |

homelab33 itself is safe even if Forgejo is lost: it's mirrored to GitHub, and Argo CD reads it
from there. The app repositories (finance-app, portfolio, blog) are only on Forgejo and in my
local clones.

## Backing up by hand

Keep these off both machines and out of this repository, for example in a password manager or an
encrypted drive.

**Sealed Secrets key.** This is the one that matters most. The controller adds a new key every 30
days and keeps the old ones, so export it again after each new key:

```sh
kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml \
  > sealed-secrets-keys.yaml
```

**Forgejo.** `forgejo dump` writes repositories, the database and settings to one zip:

```sh
kubectl -n forgejo exec deploy/forgejo -- \
  forgejo dump -c /data/gitea/conf/app.ini --file /tmp/forgejo-dump.zip
kubectl -n forgejo cp "$(kubectl -n forgejo get pod -l app=forgejo -o name | cut -d/ -f2)":/tmp/forgejo-dump.zip forgejo-dump.zip
kubectl -n forgejo exec deploy/forgejo -- rm /tmp/forgejo-dump.zip
```

**finance-app.** On the laptop, with the `sqlite3` package installed. `.backup` is safe while the
app is running:

```sh
sudo sqlite3 /var/lib/rancher/k3s/storage/*_finance-app_finance-app-data/finance-app.db \
  ".backup '/tmp/finance-app.db'"
```

**Pi-hole.** Settings → Teleporter → Export in the admin page.

## Rebuilding from bare metal

1. Install Ubuntu and k3s at the same version on the desktop (server), then join the laptop as an
   agent with the server's node token:

   ```sh
   curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.36.4+k3s1 sh -
   ```

2. Restore the Sealed Secrets keys before anything can create a new one:

   ```sh
   kubectl apply -f sealed-secrets-keys.yaml
   ```

3. Install Argo CD once, from the same chart and values it manages itself with:

   ```sh
   helm install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version 10.9.2 \
     -n argocd --create-namespace -f infra/argocd/values.yaml
   ```

4. Hand everything else to Argo CD:

   ```sh
   kubectl apply -k bootstrap
   ```

   Infra syncs first, then the apps. cert-manager issues a new wildcard certificate by itself.

5. Tailscale: remove the old machine from the tailnet, create a new single-use auth key tagged
   `tag:k8s-ingress`, seal it into `infra/tailscale-proxy/manifests/secrets/tailscale-auth.yaml`,
   and commit. Then point the `*.lab.jddemonteverde.com` DNS record at the proxy's new tailnet
   address.

6. Restore data, one app at a time. Argo CD would undo a manual scale-down, so pause it first:
   - Turn off auto-sync for the app (`argocd app set <app> --sync-policy none`).
   - Scale the app to 0.
   - Copy the data into its folder under `/var/lib/rancher/k3s/storage/` on the right machine.
     For Forgejo, unpack the dump into it (see Forgejo's docs on restoring a dump). For
     finance-app, copy in `finance-app.db`.
   - Scale it back up.
   - Turn auto-sync back on.
   - For Pi-hole, import the Teleporter file in the admin page.

7. Re-run each app's latest release workflow on Forgejo to refill the registry.

If the desktop's LAN address changes, update Pi-hole's `hostIP` in `apps/pihole` and the DNS
server the router hands out.

## Not covered yet

- Automated, off-site backups, on a schedule.
- A tested restore, and how long it takes.
- The exact k3s install options and the Ubuntu setup. Neither is in git.
- The router and Tailscale admin settings. Neither is in git.
