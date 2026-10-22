# Forgejo runner

This is where my CI pipelines run. When I push to a repository on [Forgejo](../forgejo/), the
runner picks up the workflow, runs it, and builds the Docker image. The image goes to my
[container registry](../registry/), and the cluster pulls it from there.

There's no limit on minutes. The only limit is how fast the old laptop is.

Workflows use the GitHub Actions format, so `runs-on: ubuntu-latest` works. It's only a label:
jobs run in the runner's `node:24-trixie` image, not Ubuntu.

The runner has no web page. It connects to Forgejo and waits for jobs. Its runs show up in each
repository's Actions tab:

![My portfolio's runs in Forgejo Actions](../../docs/images/forgejo-actions.png)

## How a build goes

```text
git push ──► Forgejo ──► runner starts a job
                              │
                              ▼
                         buildkitd (rootless BuildKit) builds the image
                              │
                              ▼
                         container registry ──► the app pulls localhost:5000/<app>:<tag>
```

In a workflow, I connect Docker Buildx to the shared BuildKit:

```sh
docker buildx create --driver remote tcp://buildkitd.forgejo-runner.svc.cluster.local:1234
```

and push to `10.43.200.10:5000/<app>:<tag>`.

## Keeping CI in its own box

CI runs whatever code is in a workflow, so I keep it locked down:

- Jobs don't get a Docker socket. With one, a job could take over the node. Images are built
  with rootless BuildKit instead.
- CI never runs on the desktop, where the parts that can read every secret live. It only runs on
  the laptop.
- Network policies block everything except DNS, Forgejo, Traefik, BuildKit and the internet.
- The runner runs as non-root with a read-only filesystem. It starts job containers through a
  Docker-in-Docker sidecar that only the runner can reach.

### The one privileged container

The Docker-in-Docker sidecar runs with `privileged: true`, because dockerd needs it to start
containers. It's also why this namespace allows `privileged` pods. Here is how it's fenced in:

- It only runs on the laptop, away from everything that can read secrets.
- Jobs never get its socket, so a workflow can't start a privileged container of its own.
- Only my own repositories run on this runner.
- Its pod can only reach DNS, Forgejo, Traefik, BuildKit and the internet. Through Traefik it
  gets Forgejo; Argo CD, Grafana, Pi-hole and the finance app turn it away.

What I'd like to do next is drop `privileged`. [Sysbox](https://github.com/nestybox/sysbox),
installed on the laptop, would let dockerd run without it. I could also try a rootless dockerd
with the same relaxed profiles that `buildkitd` already uses.

## Files

```text
manifests/
  deployment.yaml               Runner, with its Docker-in-Docker sidecar
  configmap.yaml                Runner config: job labels, no Docker socket for jobs
  deployment-buildkitd.yaml     Rootless BuildKit
  configmap-buildkitd.yaml      BuildKit config
  service-buildkitd.yaml        Lets jobs reach BuildKit
  networkpolicy-*.yaml          What each pod can connect to
  secrets/                      Runner registration (Sealed Secret)
```

---

Next: [Container registry](../registry/), where the images are kept. · [Back to the start](../../)
