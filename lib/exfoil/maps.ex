defmodule Exfoil.Maps do
  alias Exfoil.Utils

  @moduledoc """
  Exfoil.Maps converts Elixir maps into dynamically generated modules with function calls.

  For example, a map `%{a: 1, b: 2}` will be converted to a dynamically created module
  with functions following the Elixir Map API:
  - `YourModule.fetch(:a)` which returns `{:ok, 1}`
  - `YourModule.fetch(:b)` which returns `{:ok, 2}`
  - `YourModule.fetch(:missing)` which returns `:error`
  - `YourModule.fetch!(:a)` which returns `1`
  - `YourModule.fetch!(:b)` which returns `2`
  - `YourModule.fetch!(:missing)` which raises a `KeyError`
  - `YourModule.get(:a)` which returns `1`
  - `YourModule.get(:a, :default)` which returns `1`
  - `YourModule.get(:missing)` which returns `nil`
  - `YourModule.get(:missing, :default)` which returns `:default`
  """

  @doc """
  Converts a map into a dynamically generated module with getter functions.

  ## Parameters

  - `map` - The map to convert
  - `module_name` - The name for the generated module (atom)
  - `opts` - Optional keyword list with configuration options

  ## Examples

      # Create a map |> :erlang.phash2()
      data = %{a: 1, b: 2, c: "hello"}

      # Convert to module
      Exfoil.Maps.convert(data, :MyData)

      # Now you can use the generated module with Map API
      MyData.fetch(:a)   # => {:ok, 1}
      MyData.fetch(:b)   # => {:ok, 2}
      MyData.fetch(:c)   # => {:ok, "hello"}
      MyData.fetch(:d)   # => :error

      MyData.fetch!(:a)  # => 1
      MyData.fetch!(:b)  # => 2
      MyData.fetch!(:c)  # => "hello"
      MyData.fetch!(:d)  # => raises KeyError

      MyData.get(:a)   # => 1
      MyData.get(:b)   # => 2
      MyData.get(:c)   # => "hello"
      MyData.get(:d)   # => nil
      MyData.get(:d, :default)   # => :default

  """
  def convert(map, module_name, _opts \\ []) when is_map(map) and is_atom(module_name) do
    # Convert map to list of key-value tuples for consistency with ETS format
    entries = Map.to_list(map)

    # Normalize the module name to ensure proper capitalization
    normalized_module_name = Utils.normalize_module_name(module_name)

    # Define extra functions specific to map-based modules
    extra_functions = [
      quote do
        @doc """
        Returns the original data as a map.
        """
        def to_map do
          unquote(Macro.escape(Map.new(entries)))
        end
      end,
      quote do
        @doc """
        Checks if a key exists in this module.
        """
        def has_key?(key) do
          key in unquote(Macro.escape(Enum.map(entries, fn {key, _value} -> key end)))
        end
      end,
      quote do
        @doc """
        Returns a list of all values.
        """
        def values do
          unquote(Macro.escape(Enum.map(entries, fn {_key, value} -> value end)))
        end
      end
    ]

    # Generate the module
    with :ok <- Utils.ensure_available(normalized_module_name) do
      module_alias = Utils.create_module(normalized_module_name, entries, "map", extra_functions)

      {:ok, module_alias}
    end
  end

  @doc """
  Converts a map and returns the module directly.
  Raises an exception if conversion fails.

  ## Examples

      data = %{key: "value"}

      module = Exfoil.Maps.convert!(data, :MyModule)
      module.fetch(:key)   # => {:ok, "value"}
      module.fetch!(:key)  # => "value"
      module.get(:key)   # => "value"
      module.get(:key, :default)  # => "value"

  """
  def convert!(map, module_name, opts \\ []) do
    case convert(map, module_name, opts) do
      {:ok, module_name} -> module_name
      {:error, reason} -> raise "Failed to convert map to module #{module_name}: #{reason}"
    end
  end

  @doc """
  Converts a map into a dynamically generated module with an auto-generated name.

  The module name is generated based on a hash of the map contents to ensure uniqueness.

  ## Examples

      data = %{a: 1, b: 2}
      {:ok, module_name} = Exfoil.Maps.convert_with_auto_name(data)

      # Use the returned module name
      module_name.fetch(:a)   # => {:ok, 1}
      module_name.fetch!(:a)  # => 1
      module_name.get(:a)   # => 1
      module_name.get(:a, :default)  # => 1

  """
  def convert_with_auto_name(map, opts \\ []) when is_map(map) do
    module_name = generate_module_name(map)
    convert(map, module_name, opts)
  end

  # Private functions

  defp generate_module_name(map) do
    # Create a unique module name based on optimized map hash
    # Use phash2 directly on the map for better performance than term_to_binary
    hash =
      map
      |> :erlang.phash2()
      |> Integer.to_string(16)

    String.to_atom("ExfoilMap#{hash}")
  end

end