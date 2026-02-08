defmodule ElixirLsp.TypesGenerationTest do
  use ExUnit.Case, async: true

  defmodule GeneratedTypes do
    require ElixirLsp.Types

    ElixirLsp.Types.deflsp_type(DemoType, required: [:uri], optional: [:version])
  end

  test "generated type enforces required fields and maps keys" do
    assert {:error, {:missing_required, [:uri]}} = GeneratedTypes.DemoType.new(%{})

    assert {:ok, value} =
             GeneratedTypes.DemoType.from_map(%{"uri" => "file:///x", "version" => 1})

    assert GeneratedTypes.DemoType.to_map(value) == %{"uri" => "file:///x", "version" => 1}
  end

  test "compile-time validation rejects bad field lists" do
    assert_raise ArgumentError, ~r/overlapping|duplicate/, fn ->
      Code.compile_string("""
      defmodule BadTypeRequired do
        require ElixirLsp.Types
        ElixirLsp.Types.deflsp_type X, required: [:ok], optional: [:ok]
      end
      """)
    end
  end
end
