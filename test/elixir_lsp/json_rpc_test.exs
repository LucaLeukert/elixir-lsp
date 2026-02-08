defmodule ElixirLsp.JsonRpcTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.JsonRpc

  test "classifies message types" do
    assert JsonRpc.message_type(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"}) ==
             :request

    assert JsonRpc.message_type(%{"jsonrpc" => "2.0", "method" => "initialized"}) == :notification

    assert JsonRpc.message_type(%{"jsonrpc" => "2.0", "id" => 1, "result" => %{}}) == :response

    assert JsonRpc.message_type(%{"jsonrpc" => "2.0", "id" => 1, "error" => %{"code" => -1}}) ==
             :invalid
  end
end
