# Chute

Chute turns an extracted Longhorn support bundle into a smaller, deterministic evidence package organized around the resources an engineer actually investigates.

The first iteration focuses on structure, relationships, provenance, and per-volume evidence projection. It does **not** attempt root-cause diagnosis.

## V1 capability

Given an extracted Longhorn support bundle, Chute can:

- inventory files and classify likely YAML, logs, node data, and unknown artifacts
- parse Kubernetes and Longhorn YAML resources
- index resources by kind, namespace, and name
- connect PVCs, PVs, Pods, VolumeAttachments, Longhorn volumes, engines, replicas, and nodes using explicit identifiers
- emit a per-volume case directory containing related objects and provenance
- conservatively extract log lines that contain identifiers related to the selected volume
- record unclassified files in the manifest without copying the original bundle

## Usage

```bash
mix deps.get
mix escript.build

./chute process /path/to/extracted/supportbundle --output ./processed
./chute volume /path/to/extracted/supportbundle pvc-abc123 --output ./case
```

You can also run it without building the escript:

```bash
mix run -e 'Chute.CLI.main(["process", "/path/to/bundle"])'
```

## Output

```text
processed/
├── manifest.json
├── index.json
└── volumes/
    └── <volume>/
        ├── summary.md
        ├── evidence.json
        ├── sources.json
        ├── volume.yaml
        ├── engines.yaml
        ├── replicas.yaml
        ├── pv.yaml
        ├── pvc.yaml
        ├── pods.yaml
        ├── volume_attachments.yaml
        ├── kubernetes_nodes.yaml
        ├── longhorn_nodes.yaml
        └── relevant_logs.log
```

## Boundary

Chute reports observed bundle content and deterministic relationships. It does not claim that correlation proves cause, does not classify root cause, and does not make support decisions.

The first real support bundle is expected to expose layout/version assumptions. Those should be repaired from observed evidence rather than anticipated with generalized infrastructure.
