# homelab33

This is my homelab. It runs on an old desktop PC and an old laptop at home, using
[k3s](https://k3s.io), a small version of Kubernetes.

This repository is the setup of the whole cluster. I don't log into the servers to install or
change things. I change the files here, push to `main`, and [Argo CD](https://argo-cd.readthedocs.io)
updates the cluster to match. This way of working is called GitOps.

Let me walk you through it.

## 1. The machines

| Machine | What it does |
| --- | --- |
| Old desktop PC | Runs the parts that manage the cluster, and the DNS for my home network |
| Old laptop | Runs my apps and my CI builds |

Both were sitting unused before this. Now they run all the time.

| | Desktop | Laptop |
| --- | --- | --- |
| Model | Dell OptiPlex 9010 | Dell Latitude 7290 |
| Role | k3s server (control plane) | k3s agent (worker) |
| CPU | 4 threads | 4 threads |
| Memory | 8 GB | 8 GB |
| Disk | 250 GB | 250 GB |
| OS | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |
| k3s | v1.36.4 | v1.36.4 |

## 2. How I reach my apps

None of my apps are open to the internet. They are only reachable through my
[Tailscale](https://tailscale.com) network (a tailnet), a private network made up of my own
devices. So I can open them from my phone or laptop wherever I am, but nobody else can.

## 3. What's running

| App | What it's for | Read more |
| --- | --- | --- |
| Forgejo | My own Git platform, like GitHub | [apps/forgejo](apps/forgejo/) |
| Forgejo runner | Runs my CI pipelines and builds Docker images | [apps/forgejo-runner](apps/forgejo-runner/) |
| Container registry | Stores the images my CI builds | [apps/registry](apps/registry/) |
| Finance app | A personal finance app I made | [apps/finance-app](apps/finance-app/) |
| Pi-hole | Blocks ads for every device at home | [apps/pihole](apps/pihole/) |
| Monitoring | Lets me check on my servers when I'm away | [infra/monitoring](infra/monitoring/) |

If you want to follow along, start with [Forgejo](apps/forgejo/). Each page links to the next one
at the bottom.

## 4. How the repository is laid out

```text
bootstrap/   Two starting Argo CD apps. I applied these once by hand; they pull in everything else
infra/       What keeps the cluster running: Argo CD, certificates, Tailscale, DNS, monitoring
apps/        My apps, one folder each
```

If you want to see how the pieces connect, [infra/](infra/) explains it.

## 5. A few things I made sure of

- Every app uses HTTPS with a Let's Encrypt certificate that renews by itself.
- Passwords and keys are stored here only in encrypted form (Sealed Secrets), so this repo can
  be public.
- Apps run without root where they can, and each one only accepts connections it needs.
- Every image and chart version is pinned, so nothing changes unless I change it here.
