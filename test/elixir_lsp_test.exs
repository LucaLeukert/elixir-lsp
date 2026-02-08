defmodule ElixirLspTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.Message

  test "top-level API builds native structs and stream decodes" do
    payload =
      ElixirLsp.request(1, :shutdown, %{})
      |> ElixirLsp.encode()
      |> IO.iodata_to_binary()

    assert {:ok, [%Message.Request{} = request], _state} = ElixirLsp.recv(payload)
    assert request.method == :shutdown
  end
end
