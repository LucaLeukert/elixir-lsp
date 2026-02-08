defmodule ElixirLsp.ProtocolTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.{Message, Protocol}

  test "encodes and decodes typed messages through framed stream" do
    encoded =
      Protocol.request(1, :text_document_completion, %{
        "textDocument" => %{"uri" => "file:///a.ex"}
      })
      |> Protocol.encode()
      |> IO.iodata_to_binary()

    <<part1::binary-size(18), part2::binary>> = encoded

    assert {:ok, [], state} = Protocol.decode(part1, Protocol.new_state())
    assert {:ok, [%Message.Request{} = request], _state} = Protocol.decode(part2, state)
    assert request.method == :text_document_completion
  end
end
