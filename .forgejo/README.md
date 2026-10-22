# CI for this repository

Argo CD applies every commit on `main` to the cluster, so a broken or unsafe commit goes live right
away. Nobody reviews many of those commits: my apps' CI pushes image bumps here by itself. This
workflow checks every commit, so I find out when one is bad.

It runs on my own [Forgejo runner](../apps/forgejo-runner/), on every push to `main`, on every pull
request, and when I start it by hand.

## What it checks

| Job | Check | Why |
| --- | --- | --- |
| `manifests` | Every Kustomize directory builds | A typo or a file missing from a `kustomization.yaml` makes Argo CD fail to sync |
| `manifests` | The output is valid against the Kubernetes and CRD schemas (kubeconform) | Catches wrong fields and types before the API server does |
| `manifests` | No plaintext `kind: Secret` | Secrets go in only as `SealedSecret`s. This repo is public |
| `manifests` | Every file in a `secrets/` folder is a `SealedSecret`, listed or not | kustomize skips unlisted files, and gitleaks skips sealed ciphertext |
| `manifests` | Every image has a tag or digest, and no tag is `latest` | So nothing changes unless I change it here |
| `secrets` | gitleaks finds no credentials in the full history | A secret removed in a later commit is still public |

## It's an alarm, not a gate

A failed run turns the commit red, but the commit is already on `main` and Argo CD applies it
anyway. To block bad commits, `main` would need branch protection that requires this workflow, and
my apps' CI would have to open pull requests instead of pushing. Not done yet.

## Running it locally

The `manifests` job is one script. Run it from the repository root, with `kubectl` and
`kubeconform` installed:

```sh
./.forgejo/scripts/validate-manifests.sh
gitleaks git --redact --config .gitleaks.toml .
```

## When it fails

- **Build, schema or image failure:** fix the manifest and push again.
- **gitleaks finds a real secret:** rotate it first. Removing it from git doesn't un-publish it.
  Then remove it.
- **gitleaks false positive:** add a narrow rule to [`.gitleaks.toml`](../.gitleaks.toml). It
  already allows SealedSecret ciphertext lines and `checksum/*` annotations.

## Files

```text
workflows/validate.yml          The workflow: two jobs, manifests and secrets
scripts/validate-manifests.sh   Build, schema and policy checks
../.gitleaks.toml               gitleaks rules, with the allowlist
```

kubectl, kubeconform, gitleaks and both schema sources are pinned. kubectl, kubeconform and
gitleaks are checked against a sha256. To update one, change its version and checksum in
`validate.yml`, or the schema commit in the script.

---

[Back to the start](../)
