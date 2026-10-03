defmodule ChuteTest do
  use ExUnit.Case

  alias Chute.{Export, Logs, Projector}

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "chute-test-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(Path.join(root, "yamls"))
    File.mkdir_p!(Path.join(root, "logs"))
    File.write!(Path.join(root, "yamls/resources.yaml"), fixture_yaml())
    File.write!(Path.join(root, "logs/manager.log"), fixture_log())

    on_exit(fn -> File.rm_rf(root) end)

    %{root: root}
  end

  test "loads resources and projects a Longhorn volume into related evidence", %{root: root} do
    assert {:ok, bundle} = Chute.load(root)
    assert bundle.parse_errors == []

    assert {:ok, projection} = Projector.volume(bundle.index, "pvc-abc123")
    assert projection.volume.name == "pvc-abc123"
    assert projection.pv.name == "pvc-abc123"
    assert projection.pvc.name == "data"
    assert Enum.map(projection.engines, & &1.name) == ["pvc-abc123-e-0"]
    assert Enum.map(projection.replicas, & &1.name) == ["pvc-abc123-r-1", "pvc-abc123-r-2"]
    assert Enum.map(projection.pods, & &1.name) == ["database-0"]
    assert Enum.map(projection.attachments, & &1.name) == ["csi-attachment-abc123"]
    assert Enum.map(projection.kubernetes_nodes, & &1.name) == ["worker-1"]
    assert Enum.map(projection.longhorn_nodes, & &1.name) == ["worker-1"]
  end

  test "exports a bounded AI-ready volume case with provenance", %{root: root} do
    assert {:ok, bundle} = Chute.load(root)
    assert {:ok, projection} = Projector.volume(bundle.index, "pvc-abc123")

    logs = Logs.extract(bundle.root, bundle.inventory, projection.identifiers)

    output =
      Path.join(
        System.tmp_dir!(),
        "chute-output-#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf(output) end)

    assert :ok = Export.write_projection(projection, logs, output)

    assert File.exists?(Path.join(output, "summary.md"))
    assert File.exists?(Path.join(output, "evidence.json"))
    assert File.exists?(Path.join(output, "sources.json"))
    assert File.exists?(Path.join(output, "replicas.yaml"))

    relevant_logs = File.read!(Path.join(output, "relevant_logs.log"))
    assert relevant_logs =~ "pvc-abc123"
    refute relevant_logs =~ "completely unrelated"
  end

  test "process export creates a manifest, index, and per-volume directory", %{root: root} do
    assert {:ok, bundle} = Chute.load(root)

    output =
      Path.join(
        System.tmp_dir!(),
        "chute-process-#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf(output) end)

    assert :ok = Export.write_bundle(bundle, output)
    assert File.exists?(Path.join(output, "manifest.json"))
    assert File.exists?(Path.join(output, "index.json"))
    assert File.exists?(Path.join(output, "volumes/pvc-abc123/summary.md"))
  end

  defp fixture_log do
    """
    time=2026-10-03T12:00:00Z level=error msg="failed to attach volume pvc-abc123"
    time=2026-10-03T12:00:01Z level=info msg="completely unrelated event"
    """
  end

  defp fixture_yaml do
    """
    apiVersion: v1
    kind: List
    items:
      - apiVersion: longhorn.io/v1beta2
        kind: Volume
        metadata:
          name: pvc-abc123
          uid: volume-uid-abc123
        status:
          state: detached
          robustness: degraded
          kubernetesStatus:
            pvName: pvc-abc123
            namespace: default
            pvcName: data
      - apiVersion: longhorn.io/v1beta2
        kind: Engine
        metadata:
          name: pvc-abc123-e-0
          namespace: longhorn-system
        spec:
          volumeName: pvc-abc123
          nodeID: worker-1
      - apiVersion: longhorn.io/v1beta2
        kind: Replica
        metadata:
          name: pvc-abc123-r-1
          namespace: longhorn-system
        spec:
          volumeName: pvc-abc123
          nodeID: worker-1
      - apiVersion: longhorn.io/v1beta2
        kind: Replica
        metadata:
          name: pvc-abc123-r-2
          namespace: longhorn-system
        spec:
          volumeName: pvc-abc123
          nodeID: worker-2
      - apiVersion: v1
        kind: PersistentVolume
        metadata:
          name: pvc-abc123
        spec:
          claimRef:
            namespace: default
            name: data
          csi:
            driver: driver.longhorn.io
            volumeHandle: pvc-abc123
      - apiVersion: v1
        kind: PersistentVolumeClaim
        metadata:
          namespace: default
          name: data
        spec:
          volumeName: pvc-abc123
      - apiVersion: v1
        kind: Pod
        metadata:
          namespace: default
          name: database-0
        spec:
          nodeName: worker-1
          volumes:
            - name: storage
              persistentVolumeClaim:
                claimName: data
      - apiVersion: storage.k8s.io/v1
        kind: VolumeAttachment
        metadata:
          name: csi-attachment-abc123
        spec:
          nodeName: worker-1
          source:
            persistentVolumeName: pvc-abc123
      - apiVersion: v1
        kind: Node
        metadata:
          name: worker-1
      - apiVersion: longhorn.io/v1beta2
        kind: Node
        metadata:
          namespace: longhorn-system
          name: worker-1
    """
  end
end
