defmodule Exfoil.RegressionsTest do
  # Regressions found by a contract-first review (differential check against a plain Map).
  use ExUnit.Case, async: false

  defp name, do: :"Regression#{:erlang.unique_integer([:positive])}"

  describe "keys that are not simple literals" do
    test "tuples of three or more elements, the empty tuple, and nested combinations" do
      for key <- [{1, 2, 3}, {:user, 7, :name}, {}, [{1, 2, 3}], {{1, 2, 3}, :x}] do
        {:ok, m} = Exfoil.Maps.convert(%{key => :v}, name())
        assert m.fetch(key) == {:ok, :v}, "fetch #{inspect(key)}"
        assert m.fetch!(key) == :v
        assert m.get(key) == :v
        assert m.fetch(:__missing__) == :error
      end
    end

    test "an ETS table with composite keys" do
      tab = :ets.new(:composite, [:public])
      :ets.insert(tab, [{{:user, 1, :name}, "ann"}, {{:user, 1, :age}, 31}])
      {:ok, m} = Exfoil.convert(tab, module_name: name())
      assert m.fetch({:user, 1, :name}) == {:ok, "ann"}
      assert m.fetch({:user, 1, :age}) == {:ok, 31}
      assert m.fetch({:user, 2, :name}) == :error
    end

    test "map keys match exactly, not as sub-maps" do
      {:ok, m} = Exfoil.Maps.convert(%{%{a: 1} => :one, %{} => :empty, [%{b: 2}] => :nested}, name())

      assert m.fetch(%{a: 1}) == {:ok, :one}
      assert m.fetch(%{}) == {:ok, :empty}
      assert m.fetch([%{b: 2}]) == {:ok, :nested}

      # a map that merely contains the key's pairs is a different key
      assert m.fetch(%{a: 1, b: 2}) == :error
      assert m.fetch(%{c: 3}) == :error
      assert m.fetch([%{b: 2, c: 3}]) == :error
      assert m.get(%{a: 1, b: 2}, :default) == :default
    end

    test "the generated module agrees with the map it was built from" do
      :rand.seed(:exsss, {5, 5, 5})
      leaf = fn -> Enum.random([:a, :b, nil, true, 0, 7, -3, "", "k", 1.5, []]) end

      term = fn ->
        case :rand.uniform(4) do
          1 -> leaf.()
          2 -> List.to_tuple(for _ <- 1..:rand.uniform(5), do: leaf.())
          3 -> for _ <- 1..:rand.uniform(3), do: leaf.()
          4 -> Map.new([{leaf.(), leaf.()}])
        end
      end

      for _ <- 1..300 do
        key = term.()
        {:ok, m} = Exfoil.Maps.convert(%{key => 1}, name())
        assert m.fetch(key) == Map.fetch(%{key => 1}, key), "key #{inspect(key)}"
        assert m.fetch(:__absent__) == :error
      end
    end
  end

  describe "a module that Exfoil did not generate is never replaced" do
    defmodule Victim do
      def real, do: :original
    end

    test "Maps.convert returns an error and leaves the module alone" do
      assert Exfoil.Maps.convert(%{a: 1}, Victim) == {:error, :module_exists}
      assert Victim.real() == :original
    end

    test "ETS and DETS conversion do the same" do
      :ets.new(:victim_ets, [:named_table, :public])
      :ets.insert(:victim_ets, {:a, 1})
      assert Exfoil.convert(:victim_ets, module_name: Victim) == {:error, :module_exists}

      path = Path.join(System.tmp_dir!(), "exfoil_victim_#{System.unique_integer([:positive])}.dets")
      {:ok, _} = :dets.open_file(:victim_dets, type: :set, file: String.to_charlist(path))
      :dets.insert(:victim_dets, {:a, 1})
      assert Exfoil.Dets.convert(:victim_dets, module_name: Victim) == {:error, :module_exists}
      :dets.close(:victim_dets)
      File.rm(path)

      assert Victim.real() == :original
    end

    test "standard library modules are protected" do
      assert Exfoil.Maps.convert(%{a: 1}, :String) == {:error, :module_exists}
      assert Exfoil.Maps.convert(%{a: 1}, :Enum) == {:error, :module_exists}
      assert String.upcase("ok") == "OK"
    end

    test "calling create_module directly raises instead of replacing" do
      assert_raise ArgumentError, fn -> Exfoil.Utils.create_module(Victim, [a: 1]) end
      assert Victim.real() == :original
    end

    test "re-converting a module Exfoil generated still refreshes it" do
      n = name()
      assert {:ok, m} = Exfoil.Maps.convert(%{a: 1}, n)
      assert m.fetch(:a) == {:ok, 1}
      assert {:ok, ^m} = Exfoil.Maps.convert(%{a: 2}, n)
      assert m.fetch(:a) == {:ok, 2}
    end
  end
end
