defmodule ElixirLsp.MessageTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.Message

  test "builds and serializes request struct" do
    request = Message.request(1, :initialize, %{"processId" => nil})

    assert %Message.Request{id: 1, method: :initialize} = request

    assert Message.to_map(request) == %{
             "jsonrpc" => "2.0",
             "id" => 1,
             "method" => "initialize",
             "params" => %{"processId" => nil}
           }
  end

  test "parses wire request into native method atom" do
    wire = %{"jsonrpc" => "2.0", "id" => 7, "method" => "textDocument/hover", "params" => %{}}

    assert {:ok, %Message.Request{method: :text_document_hover, id: 7}} = Message.from_map(wire)
  end

  test "builds error response" do
    message = Message.error_response(10, -32601, "Method not found")

    assert Message.to_map(message) == %{
             "jsonrpc" => "2.0",
             "id" => 10,
             "error" => %{"code" => -32601, "message" => "Method not found"}
           }
  end
end
