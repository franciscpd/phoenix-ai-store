defmodule PhoenixAI.Store.CostStoreContractTest do
  @moduledoc """
  Shared contract test suite for `PhoenixAI.Store.Adapter.CostStore` implementations.

  Any adapter test module can `use` this module to get a standard set of
  tests that verify the adapter correctly implements all CostStore callbacks.

  ## Usage

      defmodule MyAdapterTest do
        setup do
          # ... set up adapter-specific state ...
          {:ok, opts: [table: table]}
        end

        use PhoenixAI.Store.CostStoreContractTest, adapter: MyAdapter
      end

  The `setup` block MUST run before the `use` call and must return
  `{:ok, opts: opts}` where `opts` is the keyword list passed to
  every adapter callback.
  """

  defmacro __using__(macro_opts) do
    quote do
      alias PhoenixAI.Store.CostTracking.CostRecord

      @cost_adapter unquote(macro_opts[:adapter])

      defp build_cost_record(attrs \\ %{}) do
        defaults = %{
          id: Uniq.UUID.uuid7(),
          conversation_id: nil,
          user_id: "user_#{System.unique_integer([:positive])}",
          provider: :openai,
          model: "gpt-4",
          input_tokens: 100,
          output_tokens: 50,
          input_cost: Decimal.new("0.003"),
          output_cost: Decimal.new("0.006"),
          total_cost: Decimal.new("0.009"),
          metadata: %{},
          recorded_at: DateTime.utc_now()
        }

        struct(CostRecord, Map.merge(defaults, attrs))
      end

      describe "save_cost_record/2" do
        test "saves and returns a CostRecord with correct Decimal values", %{opts: opts} do
          conv = build_conversation()
          {:ok, saved_conv} = @adapter.save_conversation(conv, opts)

          record =
            build_cost_record(%{
              conversation_id: saved_conv.id,
              input_cost: Decimal.new("0.0050000000"),
              output_cost: Decimal.new("0.0100000000"),
              total_cost: Decimal.new("0.0150000000")
            })

          assert {:ok, saved} = @cost_adapter.save_cost_record(record, opts)
          assert saved.conversation_id == saved_conv.id
          assert saved.provider == :openai
          assert saved.model == "gpt-4"
          assert saved.input_tokens == 100
          assert saved.output_tokens == 50
          assert Decimal.equal?(saved.input_cost, Decimal.new("0.005"))
          assert Decimal.equal?(saved.output_cost, Decimal.new("0.01"))
          assert Decimal.equal?(saved.total_cost, Decimal.new("0.015"))
          assert %DateTime{} = saved.recorded_at
        end

        test "assigns an id if none provided", %{opts: opts} do
          conv = build_conversation()
          {:ok, saved_conv} = @adapter.save_conversation(conv, opts)

          record = build_cost_record(%{id: nil, conversation_id: saved_conv.id})
          assert {:ok, saved} = @cost_adapter.save_cost_record(record, opts)
          assert is_binary(saved.id)
        end
      end

      describe "get_cost_records/2" do
        test "returns records ordered by recorded_at", %{opts: opts} do
          conv = build_conversation()
          {:ok, saved_conv} = @adapter.save_conversation(conv, opts)

          now = DateTime.utc_now()
          earlier = DateTime.add(now, -60, :second)
          later = DateTime.add(now, 60, :second)

          r1 = build_cost_record(%{conversation_id: saved_conv.id, recorded_at: later, model: "gpt-4-later"})
          r2 = build_cost_record(%{conversation_id: saved_conv.id, recorded_at: earlier, model: "gpt-4-earlier"})
          r3 = build_cost_record(%{conversation_id: saved_conv.id, recorded_at: now, model: "gpt-4-now"})

          {:ok, _} = @cost_adapter.save_cost_record(r1, opts)
          {:ok, _} = @cost_adapter.save_cost_record(r2, opts)
          {:ok, _} = @cost_adapter.save_cost_record(r3, opts)

          {:ok, records} = @cost_adapter.get_cost_records(saved_conv.id, opts)
          assert length(records) == 3
          assert Enum.map(records, & &1.model) == ["gpt-4-earlier", "gpt-4-now", "gpt-4-later"]
        end

        test "returns empty list for nonexistent conversation", %{opts: opts} do
          assert {:ok, []} = @cost_adapter.get_cost_records(Uniq.UUID.uuid7(), opts)
        end
      end

      describe "sum_cost/2" do
        setup %{opts: opts} do
          conv1 = build_conversation(%{user_id: "cost_user_a"})
          {:ok, conv1} = @adapter.save_conversation(conv1, opts)

          conv2 = build_conversation(%{user_id: "cost_user_b"})
          {:ok, conv2} = @adapter.save_conversation(conv2, opts)

          now = DateTime.utc_now()
          yesterday = DateTime.add(now, -86_400, :second)
          tomorrow = DateTime.add(now, 86_400, :second)

          r1 =
            build_cost_record(%{
              conversation_id: conv1.id,
              user_id: "cost_user_a",
              provider: :openai,
              model: "gpt-4",
              total_cost: Decimal.new("0.01"),
              recorded_at: now
            })

          r2 =
            build_cost_record(%{
              conversation_id: conv1.id,
              user_id: "cost_user_a",
              provider: :anthropic,
              model: "claude-3",
              total_cost: Decimal.new("0.02"),
              recorded_at: yesterday
            })

          r3 =
            build_cost_record(%{
              conversation_id: conv2.id,
              user_id: "cost_user_b",
              provider: :openai,
              model: "gpt-3.5",
              total_cost: Decimal.new("0.005"),
              recorded_at: tomorrow
            })

          {:ok, _} = @cost_adapter.save_cost_record(r1, opts)
          {:ok, _} = @cost_adapter.save_cost_record(r2, opts)
          {:ok, _} = @cost_adapter.save_cost_record(r3, opts)

          {:ok,
           conv1: conv1,
           conv2: conv2,
           now: now,
           yesterday: yesterday,
           tomorrow: tomorrow}
        end

        test "filters by user_id", %{opts: opts} do
          {:ok, total} = @cost_adapter.sum_cost([user_id: "cost_user_a"], opts)
          assert Decimal.equal?(total, Decimal.new("0.03"))
        end

        test "filters by conversation_id", %{opts: opts, conv1: conv1} do
          {:ok, total} = @cost_adapter.sum_cost([conversation_id: conv1.id], opts)
          assert Decimal.equal?(total, Decimal.new("0.03"))
        end

        test "filters by provider", %{opts: opts} do
          {:ok, total} = @cost_adapter.sum_cost([provider: :openai], opts)
          assert Decimal.equal?(total, Decimal.new("0.015"))
        end

        test "filters by model", %{opts: opts} do
          {:ok, total} = @cost_adapter.sum_cost([model: "gpt-4"], opts)
          assert Decimal.equal?(total, Decimal.new("0.01"))
        end

        test "filters by after (DateTime)", %{opts: opts, now: now} do
          {:ok, total} = @cost_adapter.sum_cost([after: now], opts)
          # now record (0.01) + tomorrow record (0.005)
          assert Decimal.equal?(total, Decimal.new("0.015"))
        end

        test "filters by before (DateTime)", %{opts: opts, now: now} do
          {:ok, total} = @cost_adapter.sum_cost([before: now], opts)
          # yesterday record (0.02) + now record (0.01)
          assert Decimal.equal?(total, Decimal.new("0.03"))
        end

        test "combines multiple filters", %{opts: opts, now: now} do
          {:ok, total} =
            @cost_adapter.sum_cost(
              [user_id: "cost_user_a", provider: :openai, after: now],
              opts
            )

          assert Decimal.equal?(total, Decimal.new("0.01"))
        end

        test "returns Decimal.new(\"0\") for no matches", %{opts: opts} do
          {:ok, total} = @cost_adapter.sum_cost([user_id: "nonexistent_user_xyz"], opts)
          assert Decimal.equal?(total, Decimal.new("0"))
        end
      end
    end
  end
end
