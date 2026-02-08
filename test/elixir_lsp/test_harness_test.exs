defmodule ElixirLsp.TestHarnessTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.{Message, TestHarness}

  defmodule HarnessHandler do
    @behaviour ElixirLsp.Server.Handler

    def init(_), do: {:ok, %{}}
    def handle_request(:shutdown, _params, _id, state), do: {:reply, %{"ok" => true}, state}
    def handle_request(_method, _params, _id, state), do: {:reply, %{}, state}
  end

  test "in-memory harness drives request/response" do
    {:ok, harness} = TestHarness.start_link(handler: HarnessHandler)
    on_exit(fn -> if Process.alive?(harness), do: Process.exit(harness, :shutdown) end)

    assert :ok = TestHarness.request(harness, 1, :shutdown, %{})
    outbound = TestHarness.drain_outbound(harness)

    assert [%Message.Response{id: 1, result: %{"ok" => true}}] = outbound
  end
end
