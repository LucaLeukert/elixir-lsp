defmodule ElixirLsp.Server do
  @moduledoc """
  Generic JSON-RPC/LSP protocol server process.

  Supports middleware, request lifecycle control (timeouts and cancellation),
  and typed protocol message dispatch.
  """

  use GenServer

  alias ElixirLsp.{HandlerContext, Keys, Message, Middleware, Protocol, PubSub, Stream}

  @request_cancelled_code -32800
  @internal_error_code -32603
  @pubsub_schema [
    name: [type: :atom, default: ElixirLsp.PubSub],
    topic_prefix: [type: :string, default: "elixir_lsp"]
  ]

  @typedoc """
  A function receiving framed output ready to be written to stdin/stdout/socket.
  """
  @type send_fun :: (iodata() -> any())
  @type pubsub_config :: %{name: atom(), topic_prefix: String.t()}

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

  defmacro __using__(_opts) do
    quote do
      @behaviour ElixirLsp.Server.Handler
      import ElixirLsp.Server, only: [defrequest: 2, defnotification: 2]
      import ElixirLsp.Cancellation, only: [with_cancel: 2, check_cancel!: 1]

      Module.register_attribute(__MODULE__, :lsp_request_routes, accumulate: true)
      Module.register_attribute(__MODULE__, :lsp_notification_routes, accumulate: true)
      @before_compile ElixirLsp.Server

      @impl true
      def init(arg), do: {:ok, arg}

      @impl true
      def handle_request(method, params, id, state) do
        ctx = %ElixirLsp.HandlerContext{server: self(), request_id: id, method: method, meta: %{}}
        handle_request(method, params, id, ctx, state)
      end

      @impl true
      def handle_request(method, params, id, ctx, state),
        do: __lsp_handle_request__(method, params, id, ctx, state)

      @impl true
      def handle_notification(method, params, state) do
        ctx = %ElixirLsp.HandlerContext{server: self(), method: method, meta: %{}}
        handle_notification(method, params, ctx, state)
      end

      @impl true
      def handle_notification(method, params, ctx, state),
        do: __lsp_handle_notification__(method, params, ctx, state)

      @impl true
      def handle_response(_message, state), do: {:ok, state}

      @impl true
      def handle_response(message, _ctx, state), do: handle_response(message, state)

      @impl true
      def terminate(_reason, _state), do: :ok

      defoverridable init: 1,
                     handle_request: 4,
                     handle_request: 5,
                     handle_notification: 3,
                     handle_notification: 4,
                     handle_response: 2,
                     handle_response: 3,
                     terminate: 2
    end
  end

  defmacro defrequest(method_pattern, do: block) do
    quote do
      @lsp_request_routes {unquote(Macro.escape(method_pattern)), unquote(Macro.escape(block))}
    end
  end

  defmacro defnotification(method_pattern, do: block) do
    quote do
      @lsp_notification_routes {unquote(Macro.escape(method_pattern)),
                                unquote(Macro.escape(block))}
    end
  end

  defmacro __before_compile__(env) do
    request_routes = Module.get_attribute(env.module, :lsp_request_routes) |> Enum.reverse()

    notification_routes =
      Module.get_attribute(env.module, :lsp_notification_routes) |> Enum.reverse()

    request_clauses =
      for {method_pattern, block} <- request_routes do
        {method_match, params_match} = route_match(method_pattern)
        params = Macro.var(:params, nil)
        id = Macro.var(:id, nil)
        ctx = Macro.var(:ctx, nil)
        state = Macro.var(:state, nil)

        block =
          bind_vars(block, %{
            params: params,
            _params: params,
            id: id,
            _id: id,
            ctx: ctx,
            _ctx: ctx,
            state: state,
            _state: state
          })

        quote do
          defp __lsp_handle_request__(
                 unquote(method_match),
                 unquote(params_match),
                 unquote(id),
                 unquote(ctx),
                 unquote(state)
               ) do
            _ = {unquote(id), unquote(ctx), unquote(state)}
            unquote(block)
          end
        end
      end

    notification_clauses =
      for {method_pattern, block} <- notification_routes do
        {method_match, params_match} = route_match(method_pattern)
        params = Macro.var(:params, nil)
        ctx = Macro.var(:ctx, nil)
        state = Macro.var(:state, nil)

        block =
          bind_vars(block, %{
            params: params,
            _params: params,
            ctx: ctx,
            _ctx: ctx,
            state: state,
            _state: state
          })

        quote do
          defp __lsp_handle_notification__(
                 unquote(method_match),
                 unquote(params_match),
                 unquote(ctx),
                 unquote(state)
               ) do
            _ = {unquote(ctx), unquote(state)}
            unquote(block)
          end
        end
      end

    quote do
      unquote_splicing(request_clauses)
      unquote_splicing(notification_clauses)

      defp __lsp_handle_request__(_method, _params, _id, _ctx, state),
        do: {:error, -32601, "Method not found", nil, state}

      defp __lsp_handle_notification__(_method, _params, _ctx, state), do: {:ok, state}
    end
  end

  defp route_match({:{}, _, [method_pattern, params_pattern]}),
    do: {method_pattern, params_pattern}

  defp route_match(method_pattern), do: {method_pattern, Macro.var(:params, nil)}

  defp bind_vars(ast, replacements) do
    Macro.prewalk(ast, fn
      {name, _meta, context} = node when is_atom(name) and is_atom(context) ->
        Map.get(replacements, name, node)

      node ->
        node
    end)
  end

  @type inflight_request :: %{
          id: String.t() | integer(),
          task_ref: reference(),
          task_pid: pid(),
          timer_ref: reference(),
          cancel_token: reference(),
          method: atom() | String.t(),
          started_at: integer()
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
          canceled_tokens: MapSet.t(reference()),
          pubsub: pubsub_config() | nil
        }

  @options_schema [
    name: [
      type: :atom,
      required: false,
      doc: "Registered process name for the server GenServer."
    ],
    handler: [
      type: :atom,
      required: true,
      doc: "Module implementing ElixirLsp.Server.Handler."
    ],
    send: [
      type: :any,
      required: true,
      doc: "Function that writes framed payloads."
    ],
    handler_arg: [
      type: :any,
      required: false
    ],
    middlewares: [
      type: {:list, :any},
      default: [],
      doc: "Middleware modules/functions."
    ],
    request_timeout: [
      type: :non_neg_integer,
      default: 30_000
    ],
    pubsub: [
      type: :keyword_list,
      required: false
    ]
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    opts = drop_nil_pubsub(opts)
    validated = NimbleOptions.validate!(opts, @options_schema)
    GenServer.start_link(__MODULE__, validated, Keyword.take(validated, [:name]))
  end

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts = drop_nil_pubsub(opts)
    validated = NimbleOptions.validate!(opts, @options_schema)

    %{
      id: Keyword.get(validated, :name, __MODULE__),
      start: {__MODULE__, :start_link, [validated]},
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

  @spec emit_event(pid(), atom() | String.t(), term()) :: :ok
  def emit_event(pid, event, payload) do
    GenServer.cast(pid, {:emit_event, event, payload})
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
    pubsub = normalize_pubsub(Keyword.get(opts, :pubsub))

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
       canceled_tokens: MapSet.new(),
       pubsub: pubsub
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

  def handle_cast({:emit_event, event, payload}, state) do
    publish_event(state, event, payload)
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
        emit_request_exception(:down, id, inflight, data)

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
        emit_request_exception(:timeout, id, inflight, %{reason: :timeout})

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
    started_at = System.monotonic_time()

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
      method: method,
      started_at: started_at
    }

    :telemetry.execute(
      [:elixir_lsp, :request, :start],
      %{system_time: System.system_time()},
      %{id: id, method: method}
    )

    %{state | inflight: Map.put(state.inflight, id, inflight)}
  end

  defp cancel_request(id, state) do
    case Map.get(state.inflight, id) do
      nil ->
        state

      inflight ->
        Process.exit(inflight.task_pid, :kill)
        emit_request_exception(:cancel, id, inflight, nil)

        state
        |> mark_canceled(inflight.cancel_token)
        |> clear_inflight(id)
        |> emit(Message.error_response(id, @request_cancelled_code, "Request canceled"))
    end
  end

  defp complete_request(id, token, result, state) do
    inflight = Map.get(state.inflight, id)
    state = clear_inflight(state, id)

    if cancel_token?(state, token) do
      state
    else
      case normalize_request_result(result, state.handler_state) do
        {:reply, payload, next_handler_state} ->
          emit_request_stop(id, inflight)

          state
          |> emit(Message.response(id, payload))
          |> then(&%{&1 | handler_state: next_handler_state})

        {:error, code, message, data, next_handler_state} ->
          emit_request_exception(:handler_error, id, inflight, %{code: code, message: message})

          state
          |> emit(Message.error_response(id, code, message, data))
          |> then(&%{&1 | handler_state: next_handler_state})

        {:noreply, next_handler_state} ->
          emit_request_stop(id, inflight)
          %{state | handler_state: next_handler_state}

        {:internal_error, data} ->
          emit_request_exception(:internal_error, id, inflight, data)
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

    publish_outbound(state, message)
    state
  end

  defp publish_outbound(%{pubsub: nil}, _message), do: :ok

  defp publish_outbound(state, %Message.Notification{method: method, params: params} = message) do
    params = Keys.normalize_outbound(params)
    publish(state, "outbound", message)
    publish(state, "notification:#{method}", params)

    case method do
      :text_document_publish_diagnostics ->
        publish(state, "diagnostics", params)

      :progress ->
        publish(state, "progress", params)

      _ ->
        :ok
    end
  end

  defp publish_outbound(state, %Message.Response{} = message),
    do: publish(state, "response", message)

  defp publish_outbound(state, %Message.ErrorResponse{} = message),
    do: publish(state, "response", message)

  defp publish_outbound(_state, _message), do: :ok

  defp publish_event(%{pubsub: nil}, _event, _payload), do: :ok

  defp publish_event(state, event, payload) do
    publish(state, "event:#{event}", Keys.normalize_outbound(payload))
  end

  defp publish(%{pubsub: %{name: name, topic_prefix: prefix}}, topic_suffix, payload) do
    PubSub.broadcast(name, "#{prefix}:#{topic_suffix}", {:elixir_lsp, topic_suffix, payload})
  end

  defp normalize_pubsub(nil), do: nil

  defp normalize_pubsub(opts) do
    opts = NimbleOptions.validate!(opts, @pubsub_schema)
    %{name: opts[:name], topic_prefix: opts[:topic_prefix]}
  end

  defp emit_request_stop(_id, nil), do: :ok

  defp emit_request_stop(id, inflight) do
    :telemetry.execute(
      [:elixir_lsp, :request, :stop],
      %{duration: System.monotonic_time() - inflight.started_at},
      %{id: id, method: inflight.method}
    )
  end

  defp emit_request_exception(kind, _id, nil, _reason), do: kind

  defp emit_request_exception(kind, id, inflight, reason) do
    :telemetry.execute(
      [:elixir_lsp, :request, :exception],
      %{duration: System.monotonic_time() - inflight.started_at},
      %{id: id, method: inflight.method, kind: kind, reason: reason}
    )
  end

  defp drop_nil_pubsub(opts) do
    case Keyword.fetch(opts, :pubsub) do
      {:ok, nil} -> Keyword.delete(opts, :pubsub)
      _ -> opts
    end
  end
end
