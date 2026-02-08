defmodule ElixirLsp.StateTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.State

  test "applies didOpen/didChange/didClose with incremental edits" do
    uri = "file:///tmp/test.ex"

    state =
      State.new()
      |> State.apply_notification(:text_document_did_open, %{
        "textDocument" => %{"uri" => uri, "text" => "hello\nworld", "version" => 1}
      })
      |> State.apply_notification(:text_document_did_change, %{
        "textDocument" => %{"uri" => uri, "version" => 2},
        "contentChanges" => [
          %{
            "range" => %{
              "start" => %{"line" => 1, "character" => 0},
              "end" => %{"line" => 1, "character" => 5}
            },
            "text" => "elixir"
          }
        ]
      })

    assert State.get_document(state, uri).text == "hello\nelixir"
    assert State.get_document(state, uri).version == 2

    state =
      State.apply_notification(state, :text_document_did_close, %{
        "textDocument" => %{"uri" => uri}
      })

    assert State.get_document(state, uri) == nil
  end
end
