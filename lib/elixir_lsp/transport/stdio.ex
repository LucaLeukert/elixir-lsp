defmodule ElixirLsp.Transport.Stdio do
  @moduledoc """
  Production-safe stdio transport loop for LSP servers.

  Defaults to `:content_length` mode, which reads one LSP frame at a time
  using headers/body boundaries. This avoids fixed-size read edge cases.

  `:chunk` mode is available for simple stream forwarding.
  """

  @chunk_size 8192

  @type mode :: :content_length | :chunk

  @spec run(keyword()) :: no_return()
  def run(opts) do
    handler = Keyword.fetch!(opts, :handler)
    handler_arg = Keyword.get(opts, :init)
    middlewares = Keyword.get(opts, :middlewares, [])
    request_timeout = Keyword.get(opts, :request_timeout, 30_000)
    mode = Keyword.get(opts, :mode, :content_length)

    {:ok, server} =
      ElixirLsp.Server.start_link(
        handler: handler,
        handler_arg: handler_arg,
        middlewares: middlewares,
        request_timeout: request_timeout,
        send: fn payload -> IO.binwrite(:stdio, payload) end
      )

    loop_read(server, mode)
  end

  @spec read_message(atom() | pid()) :: {:ok, binary()} | :eof | {:error, term()}
  def read_message(device \\ :stdio) do
    with {:ok, headers} <- read_headers(device),
         {:ok, length} <- content_length(headers),
         {:ok, body} <- read_exact(device, length) do
      {:ok, [headers, "\r\n\r\n", body] |> IO.iodata_to_binary()}
    end
  end

  defp loop_read(server, :content_length) do
    case read_message(:stdio) do
      {:ok, payload} ->
        ElixirLsp.Server.feed(server, payload)
        loop_read(server, :content_length)

      :eof ->
        Process.sleep(:infinity)

      {:error, _reason} ->
        Process.sleep(:infinity)
    end
  end

  defp loop_read(server, :chunk) do
    case IO.binread(:stdio, @chunk_size) do
      :eof ->
        Process.sleep(:infinity)

      {:error, _} ->
        Process.sleep(:infinity)

      chunk when is_binary(chunk) ->
        ElixirLsp.Server.feed(server, chunk)
        loop_read(server, :chunk)
    end
  end

  defp read_headers(device), do: read_headers(device, [])

  defp read_headers(device, acc) do
    case IO.read(device, :line) do
      :eof ->
        :eof

      {:error, reason} ->
        {:error, reason}

      line when is_binary(line) ->
        normalized = String.trim_trailing(line, "\n") |> String.trim_trailing("\r")

        if normalized == "" do
          {:ok, Enum.reverse(acc) |> Enum.join("\r\n")}
        else
          read_headers(device, [normalized | acc])
        end
    end
  end

  defp content_length(headers) do
    headers
    |> String.split("\r\n", trim: true)
    |> Enum.find_value(fn line ->
      case String.split(line, ":", parts: 2) do
        [name, value] ->
          if String.downcase(String.trim(name)) == "content-length" do
            value
            |> String.trim()
            |> Integer.parse()
            |> case do
              {n, ""} when n >= 0 -> {:ok, n}
              _ -> {:error, {:invalid_content_length, value}}
            end
          end

        _ ->
          nil
      end
    end)
    |> case do
      nil -> {:error, :missing_content_length}
      value -> value
    end
  end

  defp read_exact(_device, 0), do: {:ok, ""}

  defp read_exact(device, bytes) when bytes > 0 do
    case IO.binread(device, bytes) do
      :eof -> :eof
      {:error, reason} -> {:error, reason}
      data when is_binary(data) and byte_size(data) == bytes -> {:ok, data}
      data when is_binary(data) -> {:error, {:short_read, byte_size(data), bytes}}
    end
  end
end
