defmodule Chute.Inventory do
  @yaml_extensions ~w(.yaml .yml)
  @log_extensions ~w(.log .txt)

  def build(root) do
    root
    |> walk()
    |> Enum.sort()
    |> Enum.map(&entry(root, &1))
  end

  defp walk(dir) do
    dir
    |> File.ls!()
    |> Enum.flat_map(fn name ->
      path = Path.join(dir, name)

      case File.lstat(path) do
        {:ok, %File.Stat{type: :directory}} -> walk(path)
        {:ok, %File.Stat{type: :regular}} -> [path]
        _ -> []
      end
    end)
  end

  defp entry(root, path) do
    stat = File.stat!(path)
    relative_path = Path.relative_to(path, root)

    %{
      "path" => relative_path,
      "bytes" => stat.size,
      "category" => classify(relative_path)
    }
  end

  defp classify(path) do
    lower = String.downcase(path)
    extension = Path.extname(lower)

    cond do
      extension in @yaml_extensions -> "yaml"
      String.contains?(lower, "/logs/") or extension in @log_extensions -> "log"
      String.contains?(lower, "/nodes/") -> "node_data"
      true -> "unknown"
    end
  end
end
