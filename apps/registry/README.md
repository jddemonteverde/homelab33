# Container registry

This is where the images from my [CI](../forgejo-runner/) are stored. Since it's inside the
cluster, pushing and pulling stay on my home network, and my private images aren't on someone
else's server.

Only BuildKit (to push) and the nodes (to pull) can reach it.

## How the nodes pull from it

The nodes pull images with containerd. containerd can't use the cluster's DNS names, and it only
accepts HTTPS with a trusted certificate, unless the registry is on `localhost`. So:

- `registry` is the official `registry` image (3.1.2), with a 5 Gi volume and no login.
- `registry-proxy` runs HAProxy on every node. It listens on `127.0.0.1:5000` and forwards to the
  registry.
- My apps use `localhost:5000/<app>:<tag>` as their image, and every node can pull it.

The proxy only listens on `127.0.0.1`, so the registry isn't open to my home network. No changes
on the nodes themselves were needed.

## Files

```text
manifests/
  deployment.yaml         The registry
  pvc.yaml                Image storage
  service.yaml            Fixed address that CI pushes to
  daemonset-proxy.yaml    HAProxy on every node, on localhost:5000
  configmap-proxy.yaml    HAProxy config
  networkpolicy.yaml      Only lets in the proxy and BuildKit
```

---

Next: [Finance app](../finance-app/), an app that goes through all of this. · [Back to the start](../../)
