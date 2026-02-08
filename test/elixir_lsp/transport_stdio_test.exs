defmodule ElixirLsp.Transport.StdioTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.Transport.Stdio

  test "read_message reads one content-length framed payload" do
    payload = "{\"jsonrpc\":\"2.0\",\"method\":\"initialize\",\"params\":{}}"
    framed = "Content-Length: #{byte_size(payload)}\r\n\r\n" <> payload

    {:ok, device} = StringIO.open(framed)

    assert {:ok, message} = Stdio.read_message(device)
    assert message == framed
    assert :eof == Stdio.read_message(device)
  end

  test "read_message errors on missing content-length" do
    {:ok, device} = StringIO.open("X-Test: 1\r\n\r\n{}")
    assert {:error, :missing_content_length} = Stdio.read_message(device)
  end
end
