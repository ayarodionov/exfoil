defmodule Exfoil do
  alias Exfoil.Utils

  @moduledoc """
  Exfoil converts ETS table entries into dynamically generated modules with function calls.

  For example, an ETS table named `tab1` containing key-value pairs `{:a, 1}` and `{:b, 2}`
  will be converted to a dynamically created module `Tab1` with functions following the Elixir Map API:
  - `Tab1.fetch(:a)` which returns `{:ok, 1}`
  - `Tab1.fetch(:b)` which returns `{:ok, 2}`
  - `Tab1.fetch(:missing)` which returns `:error`
  - `Tab1.fetch!(:a)` which returns `1`
  - `Tab1.fetch!(:b)` which returns `2`
  - `Tab1.fetch!(:missing)` which raises a `KeyError`
  - `Tab1.get(:a)` which returns `1`
  - `Tab1.get(:a, :default)` which returns `1`
  - `Tab1.get(:missing)` which returns `nil`
  - `Tab1.get(:missing, :default)` which returns `:default`

  ## Additional Functionality

  - `Exfoil.Maps` - Convert Elixir maps into dynamically generated modules
  """

  @doc """
  Converts an ETS table into a dynamically generated module with getter functions.

  ## Parameters

  - `table_name_or_ref` - The name of a named ETS table (atom) or a reference to an unnamed table
  - `opts` - Optional keyword list with configuration options
    - `:module_name` - Custom module name (defaults to capitalized table name for named tables or auto-generated for unnamed)

  ## Examples

      # Create an ETS table and populate it
      :ets.new(:tab1, [:named_table])
      :ets.insert(:tab1, {:a, 1})
      :ets.insert(:tab1, {:b, 2})
      :ets.insert(:tab1, {:c, "hello"})

      # Convert to module
      Exfoil.convert(:tab1)

      # Now you can use the generated module with Map API
      Tab1.fetch(:a)   # => {:ok, 1}
      Tab1.fetch(:b)   # => {:ok, 2}
      Tab1.fetch(:c)   # => {:ok, "hello"}
      Tab1.fetch(:d)   # => :error

      Tab1.fetch!(:a)  # => 1
      Tab1.fetch!(:b)  # => 2
      Tab1.fetch!(:c)  # => "hello"
      Tab1.fetch!(:d)  # => raises KeyError

      Tab1.get(:a)   # => 1
      Tab1.get(:b)   # => 2
      Tab1.get(:c)   # => "hello"
      Tab1.get(:d)   # => nil
      Tab1.get(:d, :default)   # => :default

  """
  def convert(table_name_or_ref, opts \\ []) do
    # Validate that the ETS table exists
    case :ets.info(table_name_or_ref) do
      :undefined ->
        {:error, :table_not_found}

      info ->
        module_name = if opts[:module_name] do
          Utils.normalize_module_name(opts[:module_name])
        else
          default_module_name_for_table(table_name_or_ref, info)
        end

        with :ok <- Utils.ensure_available(module_name) do
          # Get all entries from the ETS table
          entries = :ets.tab2list(table_name_or_ref)

          # Generate the module
          module_alias = Utils.create_module(module_name, entries, "ETS table")

          {:ok, module_alias}
        end
    end
  end

  @doc """
  Converts an ETS table and returns the module directly.
  Raises an exception if the table doesn't exist.

  ## Examples

      :ets.new(:tab1, [:named_table])
      :ets.insert(:tab1, {:key, "value"})

      module = Exfoil.convert!(:tab1)
      module.fetch(:key)   # => {:ok, "value"}
      module.fetch!(:key)  # => "value"
      module.get(:key)   # => "value"
      module.get(:key, :default)  # => "value"

  """
  def convert!(table_name, opts \\ []) do
    case convert(table_name, opts) do
      {:ok, module_name} -> module_name
      {:error, reason} -> raise "Failed to convert ETS table #{table_name}: #{reason}"
    end
  end

  # Private functions

  defp default_module_name_for_table(table_name_or_ref, info) do
    cond do
      # If it's an atom (named table), use the table name
      is_atom(table_name_or_ref) ->
        Utils.normalize_module_name(table_name_or_ref)

      # If it's a reference (unnamed table), generate a name based on table info
      is_reference(table_name_or_ref) ->
        # Get the table ID from the info
        table_id = Keyword.get(info, :id, table_name_or_ref)
        # Generate a unique module name based on the reference
        ref_hash = :erlang.phash2(table_id)
        String.to_atom("ExfoilTable#{Integer.to_string(ref_hash, 16)}")

      true ->
        # Fallback to a generic name
        :ExfoilTable
    end
  end

end
