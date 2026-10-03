defmodule Chute.Projector do
  alias Chute.{Index, Resource}

  def volume(%Index{} = index, volume_name) do
    case Enum.find(Index.longhorn_volumes(index), &(&1.name == volume_name)) do
      nil ->
        {:error, {:volume_not_found, volume_name}}

      volume ->
        {:ok, build_volume_projection(index, volume)}
    end
  end

  defp build_volume_projection(index, volume) do
    pv = find_pv(index, volume)
    pvc = find_pvc(index, volume, pv)
    pods = find_pods(index, pvc)
    attachments = find_attachments(index, pv)
    engines = related_longhorn_resources(index, "Engine", volume.name)
    replicas = related_longhorn_resources(index, "Replica", volume.name)

    node_names =
      (Enum.map(engines, &get_in(&1.data, ["spec", "nodeID"])) ++
         Enum.map(replicas, &get_in(&1.data, ["spec", "nodeID"])) ++
         Enum.map(pods, &get_in(&1.data, ["spec", "nodeName"])) ++
         Enum.map(attachments, &get_in(&1.data, ["spec", "nodeName"])))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    kubernetes_nodes =
      Index.kind(index, "Node")
      |> Enum.reject(&Resource.longhorn?/1)
      |> Enum.filter(&(&1.name in node_names))

    longhorn_nodes =
      Index.longhorn(index, "Node")
      |> Enum.filter(&(&1.name in node_names))

    projection = %{
      volume: volume,
      pv: pv,
      pvc: pvc,
      pods: pods,
      attachments: attachments,
      engines: engines,
      replicas: replicas,
      kubernetes_nodes: kubernetes_nodes,
      longhorn_nodes: longhorn_nodes
    }

    Map.put(projection, :identifiers, identifiers(projection))
  end

  defp find_pv(index, volume) do
    kubernetes_status = get_in(volume.data, ["status", "kubernetesStatus"]) || %{}
    preferred_names = [Map.get(kubernetes_status, "pvName"), volume.name] |> Enum.reject(&is_nil/1)

    Enum.find(Index.kind(index, "PersistentVolume"), fn pv ->
      pv.name in preferred_names or get_in(pv.data, ["spec", "csi", "volumeHandle"]) == volume.name
    end)
  end

  defp find_pvc(index, volume, pv) do
    kubernetes_status = get_in(volume.data, ["status", "kubernetesStatus"]) || %{}
    claim_ref = if pv, do: get_in(pv.data, ["spec", "claimRef"]) || %{}, else: %{}

    namespace = Map.get(claim_ref, "namespace") || Map.get(kubernetes_status, "namespace")
    name = Map.get(claim_ref, "name") || Map.get(kubernetes_status, "pvcName")

    if is_binary(name), do: Index.get(index, "PersistentVolumeClaim", name, namespace), else: nil
  end

  defp find_pods(_index, nil), do: []

  defp find_pods(index, pvc) do
    Index.kind(index, "Pod")
    |> Enum.filter(fn pod ->
      pod.namespace == pvc.namespace and
        Enum.any?(get_in(pod.data, ["spec", "volumes"]) || [], fn pod_volume ->
          get_in(pod_volume, ["persistentVolumeClaim", "claimName"]) == pvc.name
        end)
    end)
  end

  defp find_attachments(_index, nil), do: []

  defp find_attachments(index, pv) do
    Index.kind(index, "VolumeAttachment")
    |> Enum.filter(&(get_in(&1.data, ["spec", "source", "persistentVolumeName"]) == pv.name))
  end

  defp related_longhorn_resources(index, kind, volume_name) do
    Index.longhorn(index, kind)
    |> Enum.filter(fn resource ->
      get_in(resource.data, ["spec", "volumeName"]) == volume_name or
        get_in(resource.data, ["metadata", "labels", "longhornvolume"]) == volume_name
    end)
  end

  defp identifiers(projection) do
    [
      projection.volume,
      projection.pv,
      projection.pvc
      | projection.engines ++
          projection.replicas ++ projection.pods ++ projection.attachments
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.flat_map(fn resource -> [resource.name, resource.uid] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&(String.length(&1) >= 8))
    |> Enum.uniq()
  end
end
