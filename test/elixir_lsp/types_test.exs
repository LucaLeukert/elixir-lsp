defmodule ElixirLsp.TypesTest do
  use ExUnit.Case, async: true

  alias ElixirLsp.Types

  test "builds diagnostic and code action maps" do
    {:ok, start_pos} = Types.Position.new(0, 0)
    {:ok, end_pos} = Types.Position.new(0, 5)
    {:ok, range} = Types.Range.new(start_pos, end_pos)
    {:ok, diagnostic} = Types.Diagnostic.new(range, "Issue", severity: 2, source: "elixir-lsp")
    {:ok, edit} = Types.TextEdit.new(range, "fixed")
    {:ok, ws_edit} = Types.WorkspaceEdit.new(%{"file:///a.ex" => [edit]})

    {:ok, action} =
      Types.CodeAction.new("Fix", kind: "quickfix", diagnostics: [diagnostic], edit: ws_edit)

    assert Types.Diagnostic.to_map(diagnostic)["message"] == "Issue"
    assert Types.WorkspaceEdit.to_map(ws_edit)["changes"]["file:///a.ex"] |> length() == 1
    assert Types.CodeAction.to_map(action)["kind"] == "quickfix"
  end

  test "coerces maps into typed structs" do
    map = %{
      "title" => "Fix",
      "kind" => "quickfix",
      "diagnostics" => [
        %{
          "range" => %{
            "start" => %{"line" => 0, "character" => 0},
            "end" => %{"line" => 0, "character" => 1}
          },
          "message" => "Issue"
        }
      ],
      "edit" => %{
        "changes" => %{
          "file:///a.ex" => [
            %{
              "range" => %{
                "start" => %{"line" => 0, "character" => 0},
                "end" => %{"line" => 0, "character" => 1}
              },
              "newText" => "x"
            }
          ]
        }
      }
    }

    assert {:ok, %Types.CodeAction{} = action} = Types.from_map(Types.CodeAction, map)
    assert action.title == "Fix"
    assert Types.to_map(action)["title"] == "Fix"
  end
end
