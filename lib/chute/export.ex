defmodule Chute.Export do
  alias Chute.{Bundle, Index, Logs, Projector, Resource}

  def write_bundle(%Bundle{} = bundle, output) do
    output = Path.expand(output)
    File.mkdir_p!(output)

    write_json(Path.join(output, "manifest.json"), %{
      "root" => bundle.root,
      "files" => bundle.inventory,
      "parse_errors" => bundle.parse_errors
    })

    write_json(Path.join(output, "index.json"), %{
      "resource_count" => length(bundle.resources),
      "counts_by_kind" => Enum.frequencies_by(bundle.resources, & &1.kind),
      "resources" => Enum.map(bundle.resources, &Resource.summary/1)
    })

    volumes_root = Path.join(output, "volumes")
    File.mkdir_p!(volumes_root)

    Enum.each(Index.longhorn_volumes(bundle.index), fn volume ->
      {:ok, projection} = Projector.volume(bundle.index, volume.name)
      logs = Logs.extract(bundle.root, bundle.inventory, projection.identifiers)
      write_projection(projection, logs, Path.join(volumes_root, safe_name(volume.name)))
    end)

    :ok
  end

  def write_projection(projection, logs, output) do
    output = Path.expand(output)
    File.mkdir_p!(output)

    write_yaml(Path.join(output, "volume.yaml"), projection.volume)
    write_yaml(Path.join(output, "engines.yaml"), projection.engines)
    write_yaml(Path.join(output, "replicas.yaml"), projection.replicas)
    write_yaml(Path.join(output, "pv.yaml"), projection.pv)
    write_yaml(Path.join(output, "pvc.yaml"), projection.pvc)
    write_yaml(Path.join(output, "pods.yaml"), projection.pods)
    write_yaml(Path.join(output, "volume_attachments.yaml"), projection.attachments)
    write_yaml(Path.join(output, "kubernetes_nodes.yaml"), projection.kubernetes_nodes)
    write_yaml(Path.join(output, "longhorn_nodes.yaml"), projection.longhorn_nodes)

    write_json(Path.join(output, "evidence.json"), evidence(projection, logs))
    write_json(Path.join(output, "sources.json"), sources(projection))
    File.write!(Path.join(output, "relevant_logs.log"), render_logs(logs))
    File.write!(Path.join(output, "summary.md"), render_summary(projection, logs))

    :ok
  end

  def safe_name(value), do: String.replace(value, ~r/[^A-Za-z0-9._-]/, "_")

  defp evidence(projection, logs) do
    %{
      "volume" => Resource.summary(projection.volume),
      "observed" => %{
        "state" => get_in(projection.volume.data, ["status", "state"]),
        "robustness" => get_in(projection.volume.data, ["status", "robustness"])
      },
      "related_resource_counts" => %{
        "engines" => length(projection.engines),
        "replicas" => length(projection.replicas),
        "pods" => length(projection.pods),
        "volumeAttachments" => length(projection.attachments),
        "kubernetesNodes" => length(projection.kubernetes_nodes),
        "longhornNodes" => length(projection.longhorn_nodes)
      },
      "identifiers_used_for_log_matching" => projection.identifiers,
      "log_evidence" => %{
        "matched_lines" => logs.matched_lines,
        "included_lines" => logs.included_lines,
        "truncated" => logs.truncated,
        "read_errors" => logs.errors
      }
    }
  end

  defp sources(projection) do
    projection
    |> all_resources()
    |> Enum.map(&Resource.source_ref/1)
    |> Enum.uniq()
  end

  defp all_resources(projection) do
    [
      projection.volume,
      projection.pv,
      projection.pvc,
      projection.engines,
      projection.replicas,
      projection.pods,
      projection.attachments,
      projection.kubernetes_nodes,
      projection.longhorn_nodes
    ]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end

  defp render_logs(logs) do
    body =
      logs.matches
      |> Enum.map_join("\n", fn match ->
        "[#{match["source"]}:#{match["line"]}] #{match["text"]}"
      end)

    truncation =
      if logs.truncated do
        "\n\n# Truncated: #{logs.matched_lines} matching lines found; #{logs.included_lines} included.\n"
      else
        "\n"
      end

    body <> truncation
  end

  defp render_summary(projection, logs) do
    volume = projection.volume
    state = display(get_in(volume.data, ["status", "state"]))
    robustness = display(get_in(volume.data, ["status", "robustness"]))

    """
    # Volume #{volume.name}

    This file is a deterministic summary of observed bundle content. It is not a root-cause determination.

    ## Observed state

    - State: #{state}
    - Robustness: #{robustness}
    - PersistentVolume: #{resource_name(projection.pv)}
    - PersistentVolumeClaim: #{resource_name(projection.pvc)}

    ## Related resources

    - Engines: #{length(projection.engines)}
    - Replicas: #{length(projection.replicas)}
    - Pods: #{length(projection.pods)}
    - VolumeAttachments: #{length(projection.attachments)}
    - Kubernetes nodes: #{length(projection.kubernetes_nodes)}
    - Longhorn nodes: #{length(projection.longhorn_nodes)}

    ## Log evidence

    - Matching identifiers: #{length(projection.identifiers)}
    - Matching lines found: #{logs.matched_lines}
    - Lines included: #{logs.included_lines}
    - Truncated: #{logs.truncated}

    Every exported resource retains its original support-bundle source in sources.json.
    """
  end

  defp resource_name(nil), do: "not observed"
  defp resource_name(resource), do: resource.name

  defp display(nil), do: "not observed"
  defp display(value), do: to_string(value)

  defp write_yaml(path, value) do
    resources =
      value
      |> List.wrap()
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    content =
      case resources do
        [] ->
          "# No matching resources found in bundle.\n"

        resources ->
          resources
          |> Enum.map(& &1.data)
          |> Ymlr.documents!(sort_maps: true)
      end

    File.write!(path, content)
  end

  defp write_json(path, value) do
    File.write!(path, Jason.encode_to_iodata!(value, pretty: true))
  end
end
