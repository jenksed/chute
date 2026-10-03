defmodule Chute.Bundle do
  @enforce_keys [:root, :inventory, :resources, :parse_errors, :index]
  defstruct [:root, :inventory, :resources, :parse_errors, :index]
end

defmodule Chute do
  alias Chute.{Bundle, Index, Inventory, Parser}

  def load(root) do
    root = Path.expand(root)

    if File.dir?(root) do
      inventory = Inventory.build(root)
      %{resources: resources, parse_errors: parse_errors} = Parser.parse(root, inventory)

      {:ok,
       %Bundle{
         root: root,
         inventory: inventory,
         resources: resources,
         parse_errors: parse_errors,
         index: Index.new(resources)
       }}
    else
      {:error, {:not_a_directory, root}}
    end
  end
end
