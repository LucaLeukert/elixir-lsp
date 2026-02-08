defmodule ElixirLsp.PipelineTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.{Pipeline, Protocol, Stream}

  test "decodes chunk enumerable into collectable stream" do
    chunk =
      Protocol.notification(:window_log_message, %{message: "hello"})
      |> Protocol.encode()
      |> IO.iodata_to_binary()

    stream = Pipeline.decode_chunks([chunk], Stream.new())
    assert Enum.count(Pipeline.messages(stream)) == 1
  end
end
