defmodule Mix.Tasks.Lsp.Gen.Handler do
  use Mix.Task
  import Mix.Generator

  @shortdoc "Generates an LSP handler module and test scaffold"

  @moduledoc """
  Generates an idiomatic handler and matching test template.

      mix lsp.gen.handler Hover
  """

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    case args do
      [name] ->
        create_handler(name)

      _ ->
        Mix.raise("Usage: mix lsp.gen.handler NAME")
    end
  end

  defp create_handler(name) do
    app = Mix.Project.config()[:app] |> to_string()
    app_module = Mix.Project.config()[:app] |> to_string() |> Macro.camelize()
    module_base = Macro.camelize(name)
    module = "#{app_module}.Handlers.#{module_base}Handler"

    lib_path = "lib/#{app}/handlers/#{Macro.underscore(name)}_handler.ex"
    test_path = "test/#{app}/handlers/#{Macro.underscore(name)}_handler_test.exs"

    create_file(lib_path, handler_template(module))
    create_file(test_path, test_template(module, module_base))
  end

  defp handler_template(module) do
    """
    defmodule #{module} do
      use ElixirLsp.Server

      defrequest :initialize do
        ElixirLsp.HandlerContext.reply(ctx, ElixirLsp.Responses.initialize(%{}, name: "#{module}"))
      end
    end
    """
  end

  defp test_template(module, module_base) do
    """
    defmodule #{module}Test do
      use ExUnit.Case, async: true

      alias ElixirLsp.{Message, Protocol, Server}

      test \"#{module_base} handler responds to initialize\" do
        parent = self()

        {:ok, server} =
          Server.start_link(
            handler: #{module},
            send: fn payload -> send(parent, {:outbound, IO.iodata_to_binary(payload)}) end
          )

        req = Protocol.request(1, :initialize, %{}) |> Protocol.encode() |> IO.iodata_to_binary()
        Server.feed(server, req)

        assert_receive {:outbound, payload}, 500
        assert {:ok, [%Message.Response{}], _} = Protocol.decode(payload, Protocol.new_state())
      end
    end
    """
  end
end
