#!/bin/sh
# Builds every Kustomize directory, validates the output against Kubernetes and CRD schemas, and
# rejects plaintext Secrets and unpinned images. Runs in CI and locally from the repository root.
set -eu

KUBERNETES_VERSION="${KUBERNETES_VERSION:-1.36.4}"
# Schema sources pinned by commit, so a change upstream can't change what passes here.
K8S_SCHEMAS="https://raw.githubusercontent.com/yannh/kubernetes-json-schema/8df8a883b68a24a104b4a9e43c1288090ae60b3b"
CRDS_CATALOG="https://raw.githubusercontent.com/datreeio/CRDs-catalog/d373c2da9702bc9509a004db83e57263fe3bdfc1"

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

failed=0
for kustomization in $(find . -name kustomization.yaml -not -path './.git/*' | sort); do
  dir="$(dirname "$kustomization")"
  rendered="$out/$(printf '%s' "${dir#./}" | tr '/' '_').yaml"

  if ! kubectl kustomize "$dir" > "$rendered"; then
    echo "FAIL $dir: kustomize build" >&2
    failed=1
    continue
  fi

  if grep -q '^kind: Secret$' "$rendered"; then
    echo "FAIL $dir: plaintext Secret; seal it with kubeseal" >&2
    failed=1
  fi

  # An image must carry a tag or digest, and the tag must not be latest.
  unpinned="$(sed -n 's/^[[:space:]-]*image:[[:space:]]*//p' "$rendered" | tr -d "\"'" |
    awk '/@sha256:/ { next } { n = split($0, p, "/"); if (p[n] !~ /:/ || p[n] ~ /:latest$/) print }')"
  if [ -n "$unpinned" ]; then
    echo "FAIL $dir: unpinned image(s): $unpinned" >&2
    failed=1
  fi
done

# Every file in a secrets/ folder must be a SealedSecret, listed in a kustomization.yaml or not:
# kustomize only renders listed files, and gitleaks skips SealedSecret ciphertext.
for file in $(find . -path '*/secrets/*' -type f -not -path './.git/*' -not -name kustomization.yaml | sort); do
  if ! grep -q '^kind: SealedSecret$' "$file" || grep -qE '^kind: Secret$|^[[:space:]]*(data|stringData):' "$file"; then
    echo "FAIL $file: not a SealedSecret; seal it with kubeseal" >&2
    failed=1
  fi
done

kubeconform -strict -summary \
  -kubernetes-version "$KUBERNETES_VERSION" \
  -schema-location "$K8S_SCHEMAS/{{.NormalizedKubernetesVersion}}-standalone{{.StrictSuffix}}/{{.ResourceKind}}{{.KindSuffix}}.json" \
  -schema-location "$CRDS_CATALOG/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
  "$out" || failed=1

exit "$failed"
