# Air‑gapped Kubernetes & Containers — Quick Guide

This document explains how to implement an air-gapped Kubernetes and container image environment. It covers the minimal TL;DR steps, detailed explanations, mirroring containers (using an acquisition/hauler workflow, Harbor as the internal registry), mirroring Helm charts, how to update registry references, and whether Helm chart changes are required.

---

## TL;DR — What needs to happen

1. Mirror all upstream container images into your air‑gapped Harbor registry (use an acquisition/hauler workflow or tools like skopeo/crane/regsync to copy images).  
2. Mirror Helm charts into an internal chart repository or as OCI charts in Harbor.  
3. Update Kubernetes/Helm inputs so image references and chart repositories point to your internal registry/chart repo (use values override, post‑render rewrite, or fork charts if needed).  
4. Ensure cluster nodes and CI/CD can authenticate to and resolve the internal registry (TLS CA, DNS, imagePullSecrets, runtime config).  
5. Validate by deploying from the internal registry and chart repo and testing image pulls and installations.

---

## 1) Mirroring container images (overview)

Goal: every image the cluster might pull must be available inside the air‑gapped environment and served by your internal registry (Harbor).

Common approaches

- Harbor import/replication / "hauler" workflow (recommended when using Harbor):
  - Use a connected "acquisition" host to pull images from upstream public registries and either push them directly into your air‑gapped Harbor or produce an import bundle that you transfer and import into Harbor. Some Harbor distributions or operational patterns call this step "hauler" or "export/import."  
- Registry-to-registry copy with open tools (skopeo, crane, regsync):
  - Example (conceptual):

```
skopeo copy --all docker://docker.io/library/nginx:1.23 docker://harbor.internal/project/nginx:1.23
```

Important details

- Mirror all referenced images: application images, operator images, init containers, sidecars, tooling images referenced by charts, and CI/build images if those run in the air‑gapped environment.
- Preserve tags and digests. Prefer immutable digests (image@sha256:...) in your deployments.
- For multi‑arch images, mirror the manifest list and all platform manifests (`--all` or equivalent).
- Keep a Bill of Materials (BOM) listing upstream image, tag, and digest that maps to your internal image.

---

## 2) Mirroring Helm charts

Two options to host charts inside Harbor:

- Traditional chart repo (ChartMuseum-style): store `.tgz` chart files and an `index.yaml` that clients `helm repo add` against.  
- OCI-based charts: Helm 3 supports OCI charts; Harbor supports storing charts as OCI artifacts. This is often easier for automation.

How to mirror

- Pull chart from upstream:

```
helm pull / --version x.y.z --destination ./charts
```

- Push to Harbor (chart repo): upload the `.tgz` and update `index.yaml` (via ChartMuseum API or CI script), or for OCI charts:

```
helm chart save ./charts/mychart-1.2.3.tgz harbor.internal/library/mychart:1.2.3
helm chart push harbor.internal/library/mychart:1.2.3
```

- Mirror chart dependencies: if Chart.yaml lists dependencies with `repository` URLs, mirror those dependent charts as well and either update Chart.yaml references or make the internal repo available to `helm` before running `helm dependency update`.

---

## 3) Updating registry references (manifests / Helm values)

Most well-designed charts parameterize image repository/name/tag in `values.yaml` (e.g., `image.repository`, `image.tag`, or `global.registry`). If so, updating values is sufficient.

Options to point images at internal registry

- Helm values override at install/upgrade:

```
helm upgrade --install myapp ./chart \
  --set image.repository=harbor.internal/project/nginx \
  --set image.tag=1.23
```

- Use a values file for air‑gapped deployments (a maintained `airgap-values.yaml`) and pass it with `-f`.
- CI/CD render step: rewrite image repositories during a templating/render stage (Helmfile, jsonnet, templating scripts).
- Post‑render rewrite: use Helm’s post‑renderer facility or a small transformer (kustomize image transformer, sed script, or custom post‑renderer) to replace upstream registry prefixes with your internal prefix in the rendered manifests.
- Admission or mutating webhook: rewrite image pull URLs at pod creation time (cluster‑level solution if you can operate and trust such a webhook).

When an override is sufficient

- If the chart templates use values for repository/tag (the common case), then overriding those values is sufficient and there is no need to change the chart templates.

When you must change a chart

- If the chart hardcodes fully qualified upstream image references in templates (not configurable), you must either:
  - Fork and patch the chart to make images configurable, or
  - Use an automated rewrite/post‑renderer to replace image references after Helm renders the manifests, or
  - Use an admission/mutating controller to rewrite pod specs on creation.

Recommended pattern

- Prefer to use values overrides and `global.registry` conventions. For third‑party charts that do not follow conventions, maintain a small fork or overlay that parametrizes images.

---

## 4) Do Helm charts themselves need changes?

Short answer: usually no — if charts are parameterized for images.  

Details:

- Parameterized charts: update values.yaml or pass overrides; no chart code change needed.
- Charts with hardcoded image URIs: must be patched (fork) or have images rewritten at render time or by an admission controller.
- Chart dependencies: update dependency repository URLs or ensure the Helm client has the internal chart repo added before dependency operations.

---

## 5) Kubernetes node & runtime configuration (practical requirements)

- TLS and CA trust: if Harbor uses an internal CA, install the CA certificate on every node and configure the container runtime (containerd, CRI‑O, Docker) to trust the registry’s TLS certificate. For containerd you typically add `/etc/containerd/certs.d/harbor.internal/ca.crt` and configure `/etc/containerd/config.toml` as needed.
- Authentication:
  - Use Kubernetes imagePullSecrets and reference them in Pod specs or attach them to ServiceAccounts used by workloads.
  - Alternatively configure node-level credentials for the runtime if you want pulls to work without per-pod secrets.
- DNS & networking: ensure registry hostnames resolve inside the air‑gapped environment and firewall rules allow node → registry traffic.

---

## 6) Best practices & operational recommendations

- Prefer digests over tags in production: `image: harbor.internal/project/app@sha256:...` for immutability and repeatability.
- Keep an automated BOM that records upstream versions, tags, and digests mapped to internal artifacts.
- Automate mirroring and validation: use scripts or CI to pull, mirror, scan, and push images and charts.
- Vulnerability scanning and signing: scan mirrored images in Harbor and optionally sign images before allowing them in production.
- Use an acquisition/transfer pipeline if Harbor cannot reach the internet: connected acquisition host → pull & package → encrypted transfer → import into air‑gapped Harbor.

---

## 7) Example commands and quick workflows

- Mirror single image with skopeo:

```
skopeo copy --all docker://docker.io/library/nginx:1.23 docker://harbor.internal/library/nginx:1.23
```

- Mirror chart as OCI and push to Harbor:

```
helm pull stable/mychart --version 1.2.3 --destination ./charts
helm chart save ./charts/mychart-1.2.3.tgz harbor.internal/library/mychart:1.2.3
helm chart push harbor.internal/library/mychart:1.2.3
```

- Deploy using internal image via Helm values override:

```
helm upgrade --install myapp ./chart \
  --set image.repository=harbor.internal/library/nginx \
  --set image.tag=1.23
```

- If a chart hardcodes an image, approach options:
  - Fork the chart and update templates to read images from values.
  - Use a post‑renderer that replaces `docker.io/` with `harbor.internal/` in the rendered manifests.

---

## 8) Cutover checklist before going air‑gapped

1. Inventory: list all images, tags, digests, charts, and chart dependencies that the environment uses.
2. Mirror: import all identified images and charts into Harbor.
3. TLS & auth: ensure CA certs and imagePullSecrets are distributed to nodes and service accounts.
4. Values/overrides: prepare air‑gapped Helm values files and CI/CD changes that rewrite image references.
5. Test: deploy test namespaces and validate that pods pull images successfully and apps run.
6. Monitor: enable Harbor scanning, retention, and monitor registry disk usage and health.

---

## Summary (short and practical)

- Mirror images and Helm charts into Harbor using either the Harbor import/hauler workflow or open tools like skopeo/crane.  
- Point Helm/install inputs to your internal registry by overriding image values or using a post‑render rewrite. In most cases chart value overrides are sufficient; if charts hardcode image URIs, patch the chart or apply a rewrite step.  
- Ensure node runtime trusts the registry TLS, that authentication is provisioned, and prefer digests for stable deployments. Automate the process and keep a BOM.

---

## Next steps & offers

- I can draft example automation scripts (skopeo + Helm OCI push flow) tuned to your environment.  
- I can review a sample Helm chart you use to see whether its image references are parameterized (so we can confirm if value overrides will be sufficient).

If you want one of those, tell me which and share a sample chart or your target registry hostnames.
