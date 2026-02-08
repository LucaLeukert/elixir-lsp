defmodule ElixirLsp.Router do
  @moduledoc """
  DSL for declarative request/notification routing.
  """

  defmacro __using__(_opts) do
    quote do
      import ElixirLsp.Router

      Module.register_attribute(__MODULE__, :lsp_requests, accumulate: true)
      Module.register_attribute(__MODULE__, :lsp_notifications, accumulate: true)
      Module.register_attribute(__MODULE__, :lsp_catch_all_request, persist: true)
      Module.register_attribute(__MODULE__, :lsp_catch_all_notification, persist: true)
      Module.register_attribute(__MODULE__, :lsp_capabilities, persist: true)

      @before_compile ElixirLsp.Router
      @behaviour ElixirLsp.Server.Handler

      @impl true
      def init(arg), do: {:ok, arg}
      defoverridable init: 1
    end
  end

  defmacro on_request(method, do: block) do
    quote do
      @lsp_requests {unquote(method), unquote(Macro.escape(block))}
    end
  end

  defmacro on_notification(method, do: block) do
    quote do
      @lsp_notifications {unquote(method), unquote(Macro.escape(block))}
    end
  end

  defmacro catch_all_request(do: block) do
    quote do
      @lsp_catch_all_request unquote(Macro.escape(block))
    end
  end

  defmacro catch_all_notification(do: block) do
    quote do
      @lsp_catch_all_notification unquote(Macro.escape(block))
    end
  end

  defmacro capabilities(do: block) do
    quote do
      @lsp_capabilities ElixirLsp.Capabilities.from_ast(unquote(Macro.escape(block)))
    end
  end

  defmacro __before_compile__(env) do
    requests = Module.get_attribute(env.module, :lsp_requests) |> Enum.reverse()
    notifications = Module.get_attribute(env.module, :lsp_notifications) |> Enum.reverse()
    catch_req = Module.get_attribute(env.module, :lsp_catch_all_request)
    catch_notif = Module.get_attribute(env.module, :lsp_catch_all_notification)
    caps = Module.get_attribute(env.module, :lsp_capabilities) || %{}

    request_clauses =
      for {method, block} <- requests do
        params = Macro.var(:params, nil)
        ctx = Macro.var(:ctx, nil)
        state = Macro.var(:state, nil)
        block = bind_vars(block, %{params: params, ctx: ctx, state: state})

        quote do
          defp __route_request__(unquote(method), unquote(params), unquote(ctx), unquote(state)),
            do: unquote(block)
        end
      end

    notification_clauses =
      for {method, block} <- notifications do
        params = Macro.var(:params, nil)
        ctx = Macro.var(:ctx, nil)
        state = Macro.var(:state, nil)
        block = bind_vars(block, %{params: params, ctx: ctx, state: state})

        quote do
          defp __route_notification__(
                 unquote(method),
                 unquote(params),
                 unquote(ctx),
                 unquote(state)
               ),
               do: unquote(block)
        end
      end

    catch_req_block =
      if catch_req do
        bind_vars(catch_req, %{
          method: Macro.var(:method, nil),
          params: Macro.var(:params, nil),
          ctx: Macro.var(:ctx, nil),
          state: Macro.var(:state, nil)
        })
      else
        quote do
          ElixirLsp.HandlerContext.error(ctx, -32601, "Method not found")
        end
      end

    catch_notif_block =
      if catch_notif do
        bind_vars(catch_notif, %{
          method: Macro.var(:method, nil),
          params: Macro.var(:params, nil),
          ctx: Macro.var(:ctx, nil),
          state: Macro.var(:state, nil)
        })
      else
        quote do
          {:ok, state}
        end
      end

    quote do
      unquote_splicing(request_clauses)
      unquote_splicing(notification_clauses)

      defp __route_request__(method, params, ctx, state), do: unquote(catch_req_block)
      defp __route_notification__(method, params, ctx, state), do: unquote(catch_notif_block)

      @impl true
      def handle_request(method, params, id, state) do
        ctx = %ElixirLsp.HandlerContext{server: self(), request_id: id, method: method, meta: %{}}
        handle_request(method, params, id, ctx, state)
      end

      @impl true
      def handle_request(method, params, _id, ctx, state) do
        case __route_request__(method, params, ctx, state) do
          {:reply, result} -> {:reply, result, state}
          {:error, code, message, data} -> {:error, code, message, data, state}
          {:noreply} -> {:noreply, state}
          {:reply, result, next_state} -> {:reply, result, next_state}
          {:error, code, message, data, next_state} -> {:error, code, message, data, next_state}
          {:noreply, next_state} -> {:noreply, next_state}
          other -> raise ArgumentError, "unsupported on_request return: #{inspect(other)}"
        end
      end

      @impl true
      def handle_notification(method, params, state) do
        ctx = %ElixirLsp.HandlerContext{server: self(), method: method, meta: %{}}
        handle_notification(method, params, ctx, state)
      end

      @impl true
      def handle_notification(method, params, ctx, state) do
        case __route_notification__(method, params, ctx, state) do
          {:ok, next_state} -> {:ok, next_state}
          {:ok} -> {:ok, state}
          other -> raise ArgumentError, "unsupported on_notification return: #{inspect(other)}"
        end
      end

      def server_capabilities, do: unquote(Macro.escape(caps))
    end
  end

  defp bind_vars(ast, replacements) do
    Macro.prewalk(ast, fn
      {name, _meta, context} = node when is_atom(name) and is_atom(context) ->
        Map.get(replacements, name, node)

      node ->
        node
    end)
  end
end
