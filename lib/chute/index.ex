defmodule Chute.Index do
  alias Chute.Resource

  @enforce_keys [:resources, :by_kind, :by_name]
  defstruct [:resources, :by_kind, :by_name]

  def new(resources) do
    %__MODULE__{
      resources: resources,
      by_kind: Enum.group_by(resources, & &1.kind),
      by_name: Enum.group_by(resources, & &1.name)
    }
  end

  def kind(%__MODULE__{by_kind: by_kind}, kind), do: Map.get(by_kind, kind, [])

  def longhorn(%__MODULE__{} = index, kind) do
    index
    |> kind(kind)
    |> Enum.filter(&Resource.longhorn?/1)
  end

  def longhorn_volumes(%__MODULE__{} = index), do: longhorn(index, "Volume")

  def named(%__MODULE__{by_name: by_name}, name), do: Map.get(by_name, name, [])

  def get(%__MODULE__{} = index, kind, name, namespace \\ nil) do
    index
    |> kind(kind)
    |> Enum.find(fn resource ->
      resource.name == name and (is_nil(namespace) or resource.namespace == namespace)
    end)
  end
end
