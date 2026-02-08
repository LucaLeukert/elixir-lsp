defmodule ElixirLsp.Message do
  @moduledoc """
  Native Elixir structs for JSON-RPC/LSP messages.
  """

  alias ElixirLsp.Method

  defmodule Request do
    @enforce_keys [:id, :method]
    defstruct [:id, :method, :params]

    @type t :: %__MODULE__{
            id: String.t() | integer(),
            method: atom() | String.t(),
            params: term()
          }
  end

  defmodule Notification do
    @enforce_keys [:method]
    defstruct [:method, :params]

    @type t :: %__MODULE__{method: atom() | String.t(), params: term()}
  end

  defmodule Error do
    @enforce_keys [:code, :message]
    defstruct [:code, :message, :data]

    @type t :: %__MODULE__{code: integer(), message: String.t(), data: term() | nil}
  end

  defmodule Response do
    @enforce_keys [:id]
    defstruct [:id, :result]

    @type t :: %__MODULE__{id: String.t() | integer() | nil, result: term()}
  end

  defmodule ErrorResponse do
    @enforce_keys [:id, :error]
    defstruct [:id, :error]

    @type t :: %__MODULE__{id: String.t() | integer() | nil, error: Error.t()}
  end

  @type t :: Request.t() | Notification.t() | Response.t() | ErrorResponse.t()

  @version "2.0"

  @spec request(String.t() | integer(), atom() | String.t(), term()) :: Request.t()
  def request(id, method, params \\ nil),
    do: %Request{id: id, method: normalize_method(method), params: params}

  @spec notification(atom() | String.t(), term()) :: Notification.t()
  def notification(method, params \\ nil),
    do: %Notification{method: normalize_method(method), params: params}

  @spec response(String.t() | integer() | nil, term()) :: Response.t()
  def response(id, result), do: %Response{id: id, result: result}

  @spec error_response(String.t() | integer() | nil, integer(), String.t(), term()) ::
          ErrorResponse.t()
  def error_response(id, code, message, data \\ nil),
    do: %ErrorResponse{id: id, error: %Error{code: code, message: message, data: data}}

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"jsonrpc" => @version, "method" => method, "id" => id} = map)
      when is_binary(method) do
    {:ok, request(id, Method.to_native(method), Map.get(map, "params"))}
  end

  def from_map(%{"jsonrpc" => @version, "method" => method} = map) when is_binary(method) do
    {:ok, notification(Method.to_native(method), Map.get(map, "params"))}
  end

  def from_map(%{"jsonrpc" => @version, "id" => id, "result" => result}) do
    {:ok, response(id, result)}
  end

  def from_map(%{"jsonrpc" => @version, "id" => id, "error" => error}) when is_map(error) do
    with {:ok, normalized_error} <- normalize_error(error) do
      {:ok, %ErrorResponse{id: id, error: normalized_error}}
    end
  end

  def from_map(_), do: {:error, :invalid_jsonrpc_message}

  @spec to_map(t()) :: map()
  def to_map(%Request{id: id, method: method, params: params}) do
    %{"jsonrpc" => @version, "id" => id, "method" => Method.to_wire(method)}
    |> put_optional("params", params)
  end

  def to_map(%Notification{method: method, params: params}) do
    %{"jsonrpc" => @version, "method" => Method.to_wire(method)}
    |> put_optional("params", params)
  end

  def to_map(%Response{id: id, result: result}) do
    %{"jsonrpc" => @version, "id" => id, "result" => result}
  end

  def to_map(%ErrorResponse{id: id, error: %Error{} = error}) do
    %{"jsonrpc" => @version, "id" => id, "error" => error_to_map(error)}
  end

  defp normalize_method(method) when is_atom(method) or is_binary(method), do: method

  defp normalize_error(%{"code" => code, "message" => message} = error)
       when is_integer(code) and is_binary(message) do
    {:ok, %Error{code: code, message: message, data: Map.get(error, "data")}}
  end

  defp normalize_error(_), do: {:error, :invalid_error_object}

  defp error_to_map(%Error{code: code, message: message, data: data}) do
    %{"code" => code, "message" => message}
    |> put_optional("data", data)
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)
end
