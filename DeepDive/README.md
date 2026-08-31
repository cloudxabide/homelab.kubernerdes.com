# README - DeepDive

This directory will contain a number of "Deep Dive" that will be narrative form reviewing a particular topic associated with the homelab content.

| File | Purpose |
|:-----|:----------------|
| Airgap_Overview.md | How to build an air-gapped Kubernetes/container environment — mirroring images and Helm charts into Harbor, rewriting registry references, and node trust/auth. |
| Load_Balancer-Harvester.md | One way to configure Harvester load balancers for a Rancher-provisioned cluster — IP pools, listeners, and backend server label selectors per machine pool. |
| GitOps_Fleet_Overview.md | Concept/architecture deep dive on GitOps with Fleet in Rancher — object model (GitRepo → Bundle → BundleDeployment), fleet.yaml, cluster targeting, and a podinfo example. |
| Security_Demo.md | Live SUSE Security (NeuVector) demo walkthrough — observe egress from the `chell-test`/`aperture-sci` workload in Monitor mode, then flip to Protect and watch enforcement block it. |
| Security_Demo_Distroless.md | Companion NeuVector demo using a true distroless workload (`wheatley`) — `kubectl exec` fails at the image layer, `kubectl debug` gets a foothold anyway, and runtime enforcement still catches it. |
| Security_Discussion.md | Narrative talking points on why distroless ("no-shell") containers aren't immune — attack pivots that remain, and where SUSE Security's runtime behavioral enforcement fits. |
