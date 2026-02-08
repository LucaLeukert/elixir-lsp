defmodule ElixirLsp.Transport.Stdio do
  @moduledoc """
  Ready-made stdio transport loop for LSP servers.
  """

  @chunk_size 8192

  @spec run(keyword()) :: no_return()
  def run(opts) do
    handler = Keyword.fetch!(opts, :handler)
    handler_arg = Keyword.get(opts, :init)
    middlewares = Keyword.get(opts, :middlewares, [])
    request_timeout = Keyword.get(opts, :request_timeout, 30_000)

    {:ok, server} =
      ElixirLsp.Server.start_link(
        handler: handler,
        handler_arg: handler_arg,
        middlewares: middlewares,
        request_timeout: request_timeout,
        send: fn payload -> IO.binwrite(:stdio, payload) end
      )

    loop_read(server)
  end

  defp loop_read(server) do
    case IO.binread(:stdio, @chunk_size) do
      :eof ->
        Process.sleep(:infinity)

      {:error, _} ->
        Process.sleep(:infinity)

      chunk when is_binary(chunk) ->
        ElixirLsp.Server.feed(server, chunk)
        loop_read(server)
    end
  end
end
