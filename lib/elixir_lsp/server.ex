defmodule ElixirLsp.Server do
  @moduledoc """
  Generic JSON-RPC/LSP protocol server process.

  Supports middleware, request lifecycle control (timeouts and cancellation),
  and typed protocol message dispatch.
  """

  use GenServer

  alias ElixirLsp.{HandlerContext, Message, Middleware, Protocol, Stream}

  @request_cancelled_code -32800
  @internal_error_code -32603

  @typedoc """
  A function receiving framed output ready to be written to stdin/stdout/socket.
  """
  @type send_fun :: (iodata() -> any())

  defmodule Handler do
    @moduledoc """
    Behavior used by `ElixirLsp.Server` for domain-specific logic.
    """

    @callback init(term()) :: {:ok, term()}

    @callback handle_request(atom() | String.t(), term(), String.t() | integer(), term()) ::
                {:reply, term(), term()}
                | {:error, integer(), String.t(), term() | nil, term()}
                | {:noreply, term()}

    @callback handle_request(
                atom() | String.t(),
                term(),
                String.t() | integer(),
                HandlerContext.t(),
                term()
              ) ::
                {:reply, term()}
                | {:error, integer(), String.t(), term() | nil}
                | {:noreply}
                | {:reply, term(), term()}
                | {:error, integer(), String.t(), term() | nil, term()}
                | {:noreply, term()}

    @callback handle_notification(atom() | String.t(), term(), term()) :: {:ok, term()}

    @callback handle_notification(atom() | String.t(), term(), HandlerContext.t(), term()) ::
                {:ok} | {:ok, term()}

    @callback handle_response(Message.Response.t() | Message.ErrorResponse.t(), term()) ::
                {:ok, term()}

    @callback handle_response(
                Message.Response.t() | Message.ErrorResponse.t(),
                HandlerContext.t(),
                term()
              ) ::
                {:ok, term()}

    @callback terminate(term(), term()) :: any()

    @optional_callbacks handle_notification: 3,
                        handle_response: 2,
                        terminate: 2,
                        handle_request: 5,
                        handle_notification: 4,
                        handle_response: 3
  end

  @type inflight_request :: %{
          id: String.t() | integer(),
          task_ref: reference(),
          task_pid: pid(),
          timer_ref: reference(),
          cancel_token: reference(),
          method: atom() | String.t()
        }

  @type state :: %{
          handler: module(),
          handler_state: term(),
          send: send_fun(),
          stream: Stream.t(),
          middlewares: [module() | Middleware.middleware()],
          request_timeout: non_neg_integer(),
          task_supervisor: pid(),
          inflight: %{optional(String.t() | integer()) => inflight_request()},
          canceled_tokens: MapSet.t(reference())
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, Keyword.take(opts, [:name]))
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  @spec feed(pid(), binary()) :: :ok
  def feed(pid, chunk) when is_binary(chunk) do
    GenServer.cast(pid, {:feed, chunk})
  end

  @spec send_message(pid(), Message.t()) :: :ok
  def send_message(pid, %_{} = message) do
    GenServer.cast(pid, {:send, message})
  end

  @spec send_notification(pid(), atom() | String.t(), term()) :: :ok
  def send_notification(pid, method, params \\ nil) do
    send_message(pid, Message.notification(method, params))
  end

  @spec canceled?(pid(), reference()) :: boolean()
  def canceled?(pid, token) when is_reference(token) do
    GenServer.call(pid, {:canceled?, token})
  end

  @impl true
  def init(opts) do
    handler = Keyword.fetch!(opts, :handler)
    send_fun = Keyword.fetch!(opts, :send)
    handler_arg = Keyword.get(opts, :handler_arg)
    middlewares = Keyword.get(opts, :middlewares, [])
    request_timeout = Keyword.get(opts, :request_timeout, 30_000)

    {:ok, handler_state} = handler.init(handler_arg)
    {:ok, task_sup} = Task.Supervisor.start_link()

    {:ok,
     %{
       handler: handler,
       handler_state: handler_state,
       send: send_fun,
       stream: Stream.new(),
       middlewares: middlewares,
       request_timeout: request_timeout,
       task_supervisor: task_sup,
       inflight: %{},
       canceled_tokens: MapSet.new()
     }}
  end

  @impl true
  def handle_call({:canceled?, token}, _from, state) do
    {:reply, MapSet.member?(state.canceled_tokens, token), state}
  end

  @impl true
  def handle_cast({:feed, chunk}, %{stream: stream} = state) do
    case Protocol.decode(chunk, stream) do
      {:ok, messages, rest_stream} ->
        new_state = Enum.reduce(messages, %{state | stream: rest_stream}, &process_inbound/2)
        {:noreply, new_state}

      {:error, _reason, rest_stream} ->
        {:noreply, %{state | stream: rest_stream}}
    end
  end

  def handle_cast({:send, message}, state) do
    emit(state, message)
    {:noreply, state}
  end

  @impl true
  def handle_info({ref, {:request_result, id, cancel_token, result}}, state)
      when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, complete_request(id, cancel_token, result, state)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    case find_inflight_by_ref(state.inflight, ref) do
      nil ->
        {:noreply, state}

      {id, inflight} ->
        message = "handler crashed"
        data = %{reason: inspect(reason), method: inflight.method}

        next_state =
          state
          |> clear_inflight(id)
          |> maybe_emit_request_error(
            id,
            cancel_token?(state, inflight.cancel_token),
            message,
            data
          )

        {:noreply, next_state}
    end
  end

  def handle_info({:request_timeout, id, token}, state) do
    case Map.get(state.inflight, id) do
      nil ->
        {:noreply, state}

      inflight when inflight.cancel_token == token ->
        Process.exit(inflight.task_pid, :kill)

        next_state =
          state
          |> mark_canceled(token)
          |> clear_inflight(id)
          |> emit(Message.error_response(id, @request_cancelled_code, "Request timed out"))

        {:noreply, next_state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(reason, %{handler: handler, handler_state: handler_state}) do
    if function_exported?(handler, :terminate, 2) do
      handler.terminate(reason, handler_state)
    end

    :ok
  end

  defp process_inbound(message, state) do
    {message, _ctx} = Middleware.run(state.middlewares, message, %{server: self()})
    dispatch(message, state)
  end

  defp dispatch(%Message.Request{} = request, state), do: schedule_request(request, state)

  defp dispatch(%Message.Notification{method: :cancel_request, params: %{"id" => id}}, state),
    do: cancel_request(id, state)

  defp dispatch(%Message.Notification{} = notification, state),
    do: handle_notification(notification, state)

  defp dispatch(%Message.Response{} = response, state), do: handle_response(response, state)

  defp dispatch(%Message.ErrorResponse{} = error_response, state),
    do: handle_response(error_response, state)

  defp schedule_request(%Message.Request{method: method, params: params, id: id}, state) do
    cancel_token = make_ref()

    ctx = %HandlerContext{
      server: self(),
      request_id: id,
      method: method,
      cancel_token: cancel_token,
      meta: %{}
    }

    task =
      Task.Supervisor.async_nolink(state.task_supervisor, fn ->
        invoke_request_handler(state.handler, method, params, id, ctx, state.handler_state)
      end)

    timer_ref =
      Process.send_after(self(), {:request_timeout, id, cancel_token}, state.request_timeout)

    inflight = %{
      id: id,
      task_ref: task.ref,
      task_pid: task.pid,
      timer_ref: timer_ref,
      cancel_token: cancel_token,
      method: method
    }

    %{state | inflight: Map.put(state.inflight, id, inflight)}
  end

  defp cancel_request(id, state) do
    case Map.get(state.inflight, id) do
      nil ->
        state

      inflight ->
        Process.exit(inflight.task_pid, :kill)

        state
        |> mark_canceled(inflight.cancel_token)
        |> clear_inflight(id)
        |> emit(Message.error_response(id, @request_cancelled_code, "Request canceled"))
    end
  end

  defp complete_request(id, token, result, state) do
    state = clear_inflight(state, id)

    if cancel_token?(state, token) do
      state
    else
      case normalize_request_result(result, state.handler_state) do
        {:reply, payload, next_handler_state} ->
          state
          |> emit(Message.response(id, payload))
          |> then(&%{&1 | handler_state: next_handler_state})

        {:error, code, message, data, next_handler_state} ->
          state
          |> emit(Message.error_response(id, code, message, data))
          |> then(&%{&1 | handler_state: next_handler_state})

        {:noreply, next_handler_state} ->
          %{state | handler_state: next_handler_state}

        {:internal_error, data} ->
          emit(state, Message.error_response(id, @internal_error_code, "Internal error", data))
      end
    end
  end

  defp normalize_request_result(result, handler_state) do
    case result do
      {:reply, payload} ->
        {:reply, payload, handler_state}

      {:reply, payload, next_handler_state} ->
        {:reply, payload, next_handler_state}

      {:error, code, message, data} ->
        {:error, code, message, data, handler_state}

      {:error, code, message, data, next_handler_state} ->
        {:error, code, message, data, next_handler_state}

      {:noreply} ->
        {:noreply, handler_state}

      {:noreply, next_handler_state} ->
        {:noreply, next_handler_state}

      {:internal_error, _} = err ->
        err

      other ->
        {:internal_error, %{invalid_return: inspect(other)}}
    end
  end

  defp maybe_emit_request_error(state, _id, true, _message, _data), do: state

  defp maybe_emit_request_error(state, id, false, message, data) do
    emit(state, Message.error_response(id, @internal_error_code, message, data))
  end

  defp invoke_request_handler(handler, method, params, id, ctx, handler_state) do
    try do
      result =
        if function_exported?(handler, :handle_request, 5) do
          handler.handle_request(method, params, id, ctx, handler_state)
        else
          handler.handle_request(method, params, id, handler_state)
        end

      {:request_result, id, ctx.cancel_token, result}
    rescue
      exception ->
        {:request_result, id, ctx.cancel_token,
         {:internal_error,
          %{
            exception: inspect(exception),
            stacktrace: Exception.format_stacktrace(__STACKTRACE__)
          }}}
    catch
      kind, reason ->
        {:request_result, id, ctx.cancel_token,
         {:internal_error, %{throw_kind: kind, reason: inspect(reason)}}}
    end
  end

  defp handle_notification(%Message.Notification{method: method, params: params}, state) do
    ctx = %HandlerContext{server: self(), method: method, meta: %{}}

    if function_exported?(state.handler, :handle_notification, 4) do
      case state.handler.handle_notification(method, params, ctx, state.handler_state) do
        {:ok} -> state
        {:ok, next_handler_state} -> %{state | handler_state: next_handler_state}
      end
    else
      if function_exported?(state.handler, :handle_notification, 3) do
        {:ok, next_handler_state} =
          state.handler.handle_notification(method, params, state.handler_state)

        %{state | handler_state: next_handler_state}
      else
        state
      end
    end
  end

  defp handle_response(message, state) do
    ctx = %HandlerContext{server: self(), method: nil, meta: %{}}

    cond do
      function_exported?(state.handler, :handle_response, 3) ->
        {:ok, handler_state} = state.handler.handle_response(message, ctx, state.handler_state)
        %{state | handler_state: handler_state}

      function_exported?(state.handler, :handle_response, 2) ->
        {:ok, handler_state} = state.handler.handle_response(message, state.handler_state)
        %{state | handler_state: handler_state}

      true ->
        state
    end
  end

  defp clear_inflight(state, id) do
    case Map.pop(state.inflight, id) do
      {nil, _} ->
        state

      {inflight, next_inflight} ->
        Process.cancel_timer(inflight.timer_ref)
        %{state | inflight: next_inflight}
    end
  end

  defp find_inflight_by_ref(inflight, ref) do
    Enum.find(inflight, fn {_id, data} -> data.task_ref == ref end)
  end

  defp mark_canceled(state, token) do
    %{state | canceled_tokens: MapSet.put(state.canceled_tokens, token)}
  end

  defp cancel_token?(state, token), do: MapSet.member?(state.canceled_tokens, token)

  defp emit(%{} = state, %_{} = message) do
    message
    |> Protocol.encode()
    |> state.send.()

    state
  end
end
