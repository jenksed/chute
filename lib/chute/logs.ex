defmodule Chute.Logs do
  @max_matches 20_000

  def extract(root, inventory, identifiers) do
    identifiers = Enum.reject(identifiers, &(&1 == ""))

    inventory
    |> Enum.filter(&(&1["category"] == "log"))
    |> Enum.reduce(
      %{matches: [], matched_lines: 0, included_lines: 0, errors: []},
      fn entry, acc -> scan_file(root, entry, identifiers, acc) end
    )
    |> then(fn result ->
      %{
        result
        | matches: Enum.reverse(result.matches),
          errors: Enum.reverse(result.errors)
      }
      |> Map.put(:truncated, result.matched_lines > result.included_lines)
    end)
  end

  defp scan_file(root, entry, identifiers, acc) do
    source = entry["path"]
    path = Path.join(root, source)

    case File.open(path, [:read]) do
      {:ok, device} ->
        result =
          device
          |> IO.stream(:line)
          |> Stream.with_index(1)
          |> Enum.reduce(acc, fn {line, line_number}, file_acc ->
            if line_matches?(line, identifiers) do
              include_match(file_acc, source, line_number, line)
            else
              file_acc
            end
          end)

        File.close(device)
        result

      {:error, reason} ->
        %{acc | errors: [%{"source" => source, "error" => inspect(reason)} | acc.errors]}
    end
  end

  defp line_matches?(_line, []), do: false

  defp line_matches?(line, identifiers) do
    Enum.any?(identifiers, &String.contains?(line, &1))
  end

  defp include_match(acc, source, line_number, line) do
    matched_lines = acc.matched_lines + 1

    if acc.included_lines < @max_matches do
      match = %{
        "source" => source,
        "line" => line_number,
        "text" => String.trim_trailing(line)
      }

      %{
        acc
        | matches: [match | acc.matches],
          matched_lines: matched_lines,
          included_lines: acc.included_lines + 1
      }
    else
      %{acc | matched_lines: matched_lines}
    end
  end
end
