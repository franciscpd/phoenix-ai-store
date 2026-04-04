defmodule PhoenixAI.Store.LongTermMemory.Injector do
  @moduledoc """
  Formats facts and profile as pinned system messages for injection
  into a conversation's message list.

  This is a pure module — no side effects, no IO. It receives data
  and returns a modified message list.

  Facts are formatted as a single system message with a key-value list.
  Profile is formatted as a separate system message with the summary text.
  Both messages have `pinned: true` and appear before existing messages.
  """

  alias PhoenixAI.Store.LongTermMemory.{Fact, Profile}
  alias PhoenixAI.Store.Message

  @spec inject([Fact.t()], Profile.t() | nil, [Message.t()]) :: [Message.t()]
  def inject([], nil, messages), do: messages
  def inject([], %Profile{summary: nil}, messages), do: messages

  def inject(facts, profile, messages) do
    []
    |> maybe_add_profile(profile)
    |> maybe_add_facts(facts)
    |> Kernel.++(messages)
  end

  defp maybe_add_profile(acc, nil), do: acc
  defp maybe_add_profile(acc, %Profile{summary: nil}), do: acc

  defp maybe_add_profile(acc, %Profile{summary: summary}) do
    msg = %Message{
      role: :system,
      content: "User profile:\n#{summary}",
      pinned: true
    }

    acc ++ [msg]
  end

  defp maybe_add_facts(acc, []), do: acc

  defp maybe_add_facts(acc, facts) do
    lines =
      facts
      |> Enum.map(fn %Fact{key: key, value: value} -> "- #{key}: #{value}" end)
      |> Enum.join("\n")

    msg = %Message{
      role: :system,
      content: "User context:\n#{lines}",
      pinned: true
    }

    acc ++ [msg]
  end
end
