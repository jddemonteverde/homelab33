# Forgejo

I host my own Git platform so I can have unlimited pipeline minutes. With
[Forgejo runners](../forgejo-runner/) I build my Docker images and run my CI here on my own
machines, as often as I want, without paying for build minutes.

[Forgejo](https://forgejo.org) is an open-source Git platform. It has what I'd use on GitHub:
repositories, issues, pull requests, and Actions, which use the same workflow format as GitHub
Actions. This repository is hosted on it too.

It's only reachable from my tailnet, so there's no public login page.

## How it's set up

| | |
| --- | --- |
| Image | Forgejo 15.0.9, rootless |
| Storage | 50 Gi volume for repositories, the database and attachments |
| Web | HTTPS through Traefik, tailnet only |
| Secrets | `SECRET_KEY`, `INTERNAL_TOKEN` and others, as a Sealed Secret |

- It runs as a non-root user.
- Its NetworkPolicy only lets in Traefik and the Actions runner, on the web port. Git works over
  HTTPS. There is an SSH Service, but the policy doesn't let SSH traffic in.
- Pods in the cluster reach Forgejo by its normal hostname through a CoreDNS rewrite
  (`infra/coredns-custom`). Actions needs this to check out code.

## Files

```text
manifests/
  deployment.yaml      Forgejo
  pvc.yaml             Storage
  service-http.yaml    Web UI and API
  service-ssh.yaml     Git over SSH (not let in by the policy)
  ingress.yaml         HTTPS route through Traefik
  networkpolicy.yaml   Who can connect
  secrets/             Sealed Secrets
```

---

Next: [Forgejo runner](../forgejo-runner/), where my pipelines run. · [Back to the start](../../)
