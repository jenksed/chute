defmodule Chute.Resource do
  @enforce_keys [:api_version, :kind, :name, :source, :data]
  defstruct [:api_version, :kind, :namespace, :name, :uid, :source, :data]

  def from_map(data, source) when is_map(data) do
    metadata = Map.get(data, "metadata", %{})

    with kind when is_binary(kind) <- Map.get(data, "kind"),
         name when is_binary(name) <- Map.get(metadata, "name") do
      {:ok,
       %__MODULE__{
         api_version: Map.get(data, "apiVersion", ""),
         kind: kind,
         namespace: Map.get(metadata, "namespace"),
         name: name,
         uid: Map.get(metadata, "uid"),
         source: source,
         data: data
       }}
    else
      _ -> :ignore
    end
  end

  def from_map(_data, _source), do: :ignore

  def longhorn?(%__MODULE__{api_version: api_version}) do
    String.starts_with?(api_version || "", "longhorn.io/")
  end

  def summary(%__MODULE__{} = resource) do
    %{
      "apiVersion" => resource.api_version,
      "kind" => resource.kind,
      "namespace" => resource.namespace,
      "name" => resource.name,
      "uid" => resource.uid,
      "source" => resource.source
    }
  end

  def source_ref(%__MODULE__{} = resource) do
    %{
      "kind" => resource.kind,
      "namespace" => resource.namespace,
      "name" => resource.name,
      "source" => resource.source
    }
  end
end
