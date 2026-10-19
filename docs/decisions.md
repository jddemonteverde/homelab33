# Decisions and lessons

The choices that shaped this cluster, and what I learned on the way. Each one is in the git
history, so you can see the before and after.

## Builds without a Docker socket

**Sept 30 → Oct 2.** CI first built images by mounting the Docker-in-Docker socket into job
containers. That works, but any workflow holding the socket can start a privileged container and
take over the node. I moved builds to a rootless BuildKit daemon that jobs reach over the network,
and set `docker_host: "-"` so jobs get no socket at all. Building an image still works the same in
a workflow: `docker buildx` with the `remote` driver.

What's left is the privileged dockerd that job containers run in. It's documented in
[forgejo-runner](../apps/forgejo-runner/#the-one-privileged-container).

## A registry the nodes pull from `localhost`

**Sept 30 → Oct 4.** Nodes pull images with containerd, on the host, where cluster DNS doesn't
resolve. containerd also refuses plain HTTP unless the registry is `localhost`. The first plan needed a
`registries.yaml` entry on every node for the registry's IP. Instead, I now run HAProxy on every node,
bound to `127.0.0.1:5000`, forwarding to the registry. Nothing is configured on the nodes, so the
same manifests would work on a managed cluster. Binding to `127.0.0.1` keeps the registry off the
LAN.

## Tailnet only, with real HTTPS

**Oct 3 → Oct 4.** Apps started out on `*.homelab.local`, over plain HTTP, on the LAN. Now Traefik
has no LAN listener at all. The only way in is a Tailscale proxy, which runs unprivileged and
joined with a single-use key. cert-manager gets a wildcard Let's Encrypt certificate through a
DNS-01 challenge, so nothing needs to be reachable from the internet to prove I own the domain.
Pods resolve the public names through a CoreDNS rewrite, because publicly they point at a
Tailscale address that pods can't reach.

## Pi-hole: two bugs behind one port

**Oct 5.** Publishing DNS with `hostPort: 53` broke the node's own DNS. The rule also caught
traffic to the node's local resolver (`127.0.0.53`), so the node couldn't resolve anything, not
even to pull Pi-hole's image. Binding the port to the node's LAN address (`hostIP`) fixed it.

Then the TCP port kept losing its `hostIP`. A client-side merge keys container ports by port
number only, so the UDP and TCP entries for 53 collapsed into one. Switching that Application to
server-side diff and apply, which keys ports by port and protocol, fixed it.

## Plain manifests over Helm for my own apps

**Sept 22.** Forgejo began as a Helm chart. A day later I replaced it with about 150 lines of plain
manifests. Now what's in git is exactly what runs, and every app follows the same
one-object-per-file layout. Helm stays for third-party infra (Argo CD, cert-manager, Sealed
Secrets, monitoring), pinned, with values files in git.

## Trust decides where a pod runs

**Oct 2.** Anything that can read every Secret or manage the cluster runs only on the desktop. CI
and the internet-facing portfolio must never run there. A CI job that broke out of its container
would land on the laptop, where nothing holds cluster-wide secrets.

## Make Argo CD tell the truth

**Oct 4 → Oct 6.** An app that always shows "OutOfSync" or "Progressing" trains you to ignore the
dashboard. Two fixes:

- Traefik's Ingresses never got an address, so Argo CD never marked them Healthy. I made Traefik
  publish one.
- node-exporter's ServiceMonitor relabeling left out `action: replace`. The API filled it in, so git and the
  cluster always differed. I wrote the default out in git.

The same week, Grafana was OOMKilled at 512Mi, so I raised its limit. Since then I've sized limits
from measured usage in Prometheus, as I did for Forgejo and CI, instead of guessing.
