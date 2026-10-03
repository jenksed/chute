defmodule Chute.Parser do
  alias Chute.Resource

  def parse(root, inventory) do
    inventory
    |> Enum.filter(&(&1["category"] == "yaml"))
    |> Enum.reduce(%{resources: [], parse_errors: []}, fn entry, acc ->
      source = entry["path"]
      path = Path.join(root, source)

      case YamlElixir.read_all_from_file(path) do
        {:ok, documents} ->
          resources =
            documents
            |> Enum.flat_map(&resources_from_document(&1, source))

          %{acc | resources: Enum.reverse(resources) ++ acc.resources}

        {:error, reason} ->
          error = %{"source" => source, "error" => inspect(reason)}
          %{acc | parse_errors: [error | acc.parse_errors]}
      end
    end)
    |> then(fn result ->
      %{
        resources: Enum.reverse(result.resources),
        parse_errors: Enum.reverse(result.parse_errors)
      }
    end)
  end

  defp resources_from_document(document, source) when is_list(document) do
    Enum.flat_map(document, &resources_from_document(&1, source))
  end

  defp resources_from_document(%{"items" => items} = document, source) when is_list(items) do
    if list_kind?(Map.get(document, "kind")) do
      Enum.flat_map(items, &resources_from_document(&1, source))
    else
      resource_from_map(document, source)
    end
  end

  defp resources_from_document(document, source) when is_map(document) do
    resource_from_map(document, source)
  end

  defp resources_from_document(_document, _source), do: []

  defp resource_from_map(document, source) do
    case Resource.from_map(document, source) do
      {:ok, resource} -> [resource]
      :ignore -> []
    end
  end

  defp list_kind?(kind) when is_binary(kind), do: kind == "List" or String.ends_with?(kind, "List")
  defp list_kind?(_kind), do: false
end
