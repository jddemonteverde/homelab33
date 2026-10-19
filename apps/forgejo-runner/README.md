# Forgejo runner

This is where my CI pipelines run. When I push to a repository on [Forgejo](../forgejo/), the
runner picks up the workflow, runs it, and builds the Docker image. The image goes to my
[container registry](../registry/), and the cluster pulls it from there.

There's no limit on minutes. The only limit is how fast the old laptop is.

Workflows use the GitHub Actions format, so `runs-on: ubuntu-latest` works.

The runner has no web page. It connects to Forgejo and waits for jobs.

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
