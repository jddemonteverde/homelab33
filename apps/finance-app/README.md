# Finance app

A personal finance app I made. It uses everything from the previous pages: the code is on my
[Forgejo](../forgejo/), my [runner](../forgejo-runner/) builds the image and pushes it to my
[registry](../registry/), and changing the image tag here deploys the new version.

It's only reachable from my tailnet.

## How it's set up

| | |
| --- | --- |
| Image | `localhost:5000/finance-app`, built by my CI |
| Database | SQLite on a volume |
| Web | HTTPS through Traefik, tailnet only |
| Secrets | Session secret, as a Sealed Secret |

- One replica with the `Recreate` strategy, because two pods would open the same SQLite file.
- It runs as a non-root user.
- Its NetworkPolicy only lets in Traefik.

## Releasing a new version

1. Push to the app's repository on Forgejo. CI builds and pushes `finance-app:<new tag>`.
2. Change the image tag in `manifests/deployment.yaml` and merge to `main`.
3. Argo CD deploys it.

---

Next: [Pi-hole](../pihole/), the ad blocker for my home network. · [Back to the start](../../)
