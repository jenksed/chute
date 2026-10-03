defmodule Chute.CLI do
  alias Chute.{Export, Logs, Projector}

  def main(args) do
    case args do
      ["process", root | rest] ->
        process(root, rest)

      ["volume", root, volume_name | rest] ->
        volume(root, volume_name, rest)

      _ ->
        usage()
        System.halt(1)
    end
  end

  defp process(root, args) do
    {opts, remaining, invalid} = parse_options(args)

    if remaining == [] and invalid == [] do
      output = opts[:output] || Path.join(File.cwd!(), "chute-output")

      case Chute.load(root) do
        {:ok, bundle} ->
          :ok = Export.write_bundle(bundle, output)
          IO.puts("Wrote processed bundle to #{Path.expand(output)}")

        {:error, reason} ->
          fail(reason)
      end
    else
      usage()
      System.halt(1)
    end
  end

  defp volume(root, volume_name, args) do
    {opts, remaining, invalid} = parse_options(args)

    if remaining == [] and invalid == [] do
      output =
        opts[:output] ||
          Path.join(File.cwd!(), "chute-case-#{Export.safe_name(volume_name)}")

      with {:ok, bundle} <- Chute.load(root),
           {:ok, projection} <- Projector.volume(bundle.index, volume_name) do
        logs = Logs.extract(bundle.root, bundle.inventory, projection.identifiers)
        :ok = Export.write_projection(projection, logs, output)
        IO.puts("Wrote volume case to #{Path.expand(output)}")
      else
        {:error, reason} -> fail(reason)
      end
    else
      usage()
      System.halt(1)
    end
  end

  defp parse_options(args) do
    OptionParser.parse(args,
      strict: [output: :string],
      aliases: [o: :output]
    )
  end

  defp fail(reason) do
    IO.puts(:stderr, "chute: #{format_error(reason)}")
    System.halt(2)
  end

  defp format_error({:not_a_directory, path}), do: "not a directory: #{path}"
  defp format_error({:volume_not_found, name}), do: "Longhorn volume not found: #{name}"
  defp format_error(reason), do: inspect(reason)

  defp usage do
    IO.puts(:stderr, """
    Usage:
      chute process BUNDLE_DIR [--output DIR]
      chute volume BUNDLE_DIR VOLUME_NAME [--output DIR]

    BUNDLE_DIR must already be extracted.
    """)
  end
end
