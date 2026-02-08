defmodule ElixirLsp.Framing do
  @moduledoc """
  LSP wire framing utilities.

  LSP messages are JSON-RPC payloads framed as:

      Content-Length: <bytes>\r\n
      \r\n
      <json body>
  """

  @separator "\r\n\r\n"

  @spec encode(map()) :: iodata()
  def encode(message) when is_map(message) do
    body = Jason.encode!(message)
    ["Content-Length: ", Integer.to_string(byte_size(body)), @separator, body]
  end

  @spec decode(binary(), binary()) :: {:ok, [map()], binary()} | {:error, term()}
  def decode(chunk, buffer \\ "") when is_binary(chunk) and is_binary(buffer) do
    parse(buffer <> chunk, [])
  end

  defp parse(data, acc) do
    case :binary.match(data, @separator) do
      :nomatch ->
        {:ok, Enum.reverse(acc), data}

      {header_end, _len} ->
        header = binary_part(data, 0, header_end)
        body_start = header_end + byte_size(@separator)

        with {:ok, body_len} <- content_length(header),
             true <- byte_size(data) - body_start >= body_len do
          body = binary_part(data, body_start, body_len)
          rest = binary_part(data, body_start + body_len, byte_size(data) - body_start - body_len)

          case Jason.decode(body) do
            {:ok, decoded} when is_map(decoded) ->
              parse(rest, [decoded | acc])

            {:ok, other} ->
              {:error, {:invalid_message, other}}

            {:error, reason} ->
              {:error, {:invalid_json, reason}}
          end
        else
          {:error, reason} ->
            {:error, reason}

          false ->
            {:ok, Enum.reverse(acc), data}
        end
    end
  end

  defp content_length(header) do
    header
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
end
