# Finance app

A personal finance app I made. It uses everything from the previous pages: the code is on my
[Forgejo](../forgejo/), my [runner](../forgejo-runner/) builds the image and pushes it to my
[registry](../registry/), and changing the image tag here deploys the new version. CI makes that
change itself.

It's only reachable from my tailnet.

## How it's set up

| | |
| --- | --- |
| Image | `localhost:5000/finance-app`, built by my CI |
| Database | SQLite on a volume |
| Web | HTTPS through Traefik, tailnet only |
| Secrets | Session secret, as a Sealed Secret |

- One replica with the `Recreate` strategy, because two pods would open the same SQLite file.
- It runs as a non-root user with no capabilities and no Kubernetes API token, and the namespace
  enforces the `restricted` Pod Security Standard.
- Its root filesystem is read-only. It writes only to its database volume and two small scratch
  folders.
- Its NetworkPolicy only lets in Traefik.
- It has its own Argo CD project, which deploys only into the `finance-app` namespace and creates
  nothing cluster-wide except that namespace. CI commits here, so a bad commit stays inside it.

## Releasing a new version

1. Push a `v*` tag to the app's repository on Forgejo.
2. CI builds and pushes `finance-app:<version>`. Once the image is in the registry, it commits the
   new tag to `manifests/deployment.yaml` here, as `finance-app ci`.
3. Argo CD deploys it.

---

Next: [Portfolio](../portfolio/), which deploys itself from a release tag. · [Back to the start](../../)
