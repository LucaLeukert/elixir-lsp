defmodule ElixirLsp.FramingTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.Framing

  test "encodes and decodes one raw map message" do
    encoded =
      IO.iodata_to_binary(
        Framing.encode(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{"ok" => true}})
      )

    assert {:ok, [decoded], ""} = Framing.decode(encoded)
    assert decoded["result"]["ok"] == true
  end

  test "decodes partial chunks" do
    encoded =
      IO.iodata_to_binary(Framing.encode(%{"jsonrpc" => "2.0", "id" => 1, "result" => 42}))

    <<part1::binary-size(10), part2::binary>> = encoded

    assert {:ok, [], rest} = Framing.decode(part1)
    assert {:ok, [decoded], ""} = Framing.decode(part2, rest)
    assert decoded["result"] == 42
  end
end
