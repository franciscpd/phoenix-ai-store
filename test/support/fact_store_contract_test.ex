defmodule PhoenixAI.Store.FactStoreContractTest do
  @moduledoc """
  Shared contract test suite for `PhoenixAI.Store.Adapter.FactStore` implementations.

  Any adapter test module can `use` this module to get a standard set of
  tests that verify the adapter correctly implements all FactStore callbacks.

  ## Usage

      defmodule MyAdapterTest do
        setup do
          # ... set up adapter-specific state ...
          {:ok, opts: [table: table]}
        end

        use PhoenixAI.Store.FactStoreContractTest, adapter: MyAdapter
      end

  The `setup` block MUST run before the `use` call and must return
  `{:ok, opts: opts}` where `opts` is the keyword list passed to
  every adapter callback.
  """

  defmacro __using__(macro_opts) do
    quote do
      alias PhoenixAI.Store.LongTermMemory.Fact

      @fact_adapter unquote(macro_opts[:adapter])

      defp build_fact(attrs \\ %{}) do
        defaults = %{
          id: Uniq.UUID.uuid7(),
          user_id: "user_#{System.unique_integer([:positive])}",
          key: "favorite_color",
          value: "blue"
        }

        struct(Fact, Map.merge(defaults, attrs))
      end

      describe "save_fact/2" do
        test "saves a new fact", %{opts: opts} do
          fact = build_fact(%{user_id: "user_sf_new", key: "lang", value: "elixir"})

          assert {:ok, saved} = @fact_adapter.save_fact(fact, opts)
          assert saved.user_id == "user_sf_new"
          assert saved.key == "lang"
          assert saved.value == "elixir"
          assert %DateTime{} = saved.inserted_at
          assert %DateTime{} = saved.updated_at
        end

        test "upserts existing fact — same user_id + key overwrites value, only 1 fact remains",
             %{opts: opts} do
          user_id = "user_sf_upsert_#{System.unique_integer([:positive])}"
          fact = build_fact(%{user_id: user_id, key: "color", value: "blue"})
          {:ok, saved} = @fact_adapter.save_fact(fact, opts)
          original_inserted_at = saved.inserted_at

          updated_fact = %{fact | value: "red"}
          {:ok, upserted} = @fact_adapter.save_fact(updated_fact, opts)

          assert upserted.value == "red"
          assert upserted.inserted_at == original_inserted_at

          {:ok, facts} = @fact_adapter.get_facts(user_id, opts)
          assert length(facts) == 1
          assert hd(facts).value == "red"
        end
      end

      describe "get_facts/2" do
        test "returns empty list for unknown user", %{opts: opts} do
          assert {:ok, []} = @fact_adapter.get_facts("unknown_user_#{Uniq.UUID.uuid7()}", opts)
        end

        test "returns all facts for a user ordered by inserted_at asc", %{opts: opts} do
          user_id = "user_gf_order_#{System.unique_integer([:positive])}"

          fact1 = build_fact(%{user_id: user_id, key: "key1", value: "val1"})
          {:ok, _} = @fact_adapter.save_fact(fact1, opts)
          Process.sleep(1)
          fact2 = build_fact(%{user_id: user_id, key: "key2", value: "val2"})
          {:ok, _} = @fact_adapter.save_fact(fact2, opts)
          Process.sleep(1)
          fact3 = build_fact(%{user_id: user_id, key: "key3", value: "val3"})
          {:ok, _} = @fact_adapter.save_fact(fact3, opts)

          {:ok, facts} = @fact_adapter.get_facts(user_id, opts)
          assert length(facts) == 3
          assert Enum.map(facts, & &1.key) == ["key1", "key2", "key3"]
        end

        test "does not return other users' facts", %{opts: opts} do
          user_a = "user_gf_a_#{System.unique_integer([:positive])}"
          user_b = "user_gf_b_#{System.unique_integer([:positive])}"

          {:ok, _} = @fact_adapter.save_fact(build_fact(%{user_id: user_a, key: "k", value: "v"}), opts)
          {:ok, _} = @fact_adapter.save_fact(build_fact(%{user_id: user_b, key: "k", value: "v"}), opts)

          {:ok, facts_a} = @fact_adapter.get_facts(user_a, opts)
          assert length(facts_a) == 1
          assert hd(facts_a).user_id == user_a
        end
      end

      describe "delete_fact/3" do
        test "deletes an existing fact", %{opts: opts} do
          user_id = "user_df_#{System.unique_integer([:positive])}"
          fact = build_fact(%{user_id: user_id, key: "to_delete", value: "bye"})
          {:ok, _} = @fact_adapter.save_fact(fact, opts)

          assert :ok = @fact_adapter.delete_fact(user_id, "to_delete", opts)

          {:ok, facts} = @fact_adapter.get_facts(user_id, opts)
          assert facts == []
        end

        test "returns :ok for non-existent fact", %{opts: opts} do
          assert :ok =
                   @fact_adapter.delete_fact(
                     "no_such_user_#{Uniq.UUID.uuid7()}",
                     "no_such_key",
                     opts
                   )
        end
      end

      describe "count_facts/2" do
        test "returns 0 for unknown user", %{opts: opts} do
          assert {:ok, 0} = @fact_adapter.count_facts("unknown_count_#{Uniq.UUID.uuid7()}", opts)
        end

        test "returns correct count", %{opts: opts} do
          user_id = "user_cf_#{System.unique_integer([:positive])}"

          {:ok, _} = @fact_adapter.save_fact(build_fact(%{user_id: user_id, key: "k1", value: "v1"}), opts)
          {:ok, _} = @fact_adapter.save_fact(build_fact(%{user_id: user_id, key: "k2", value: "v2"}), opts)
          {:ok, _} = @fact_adapter.save_fact(build_fact(%{user_id: user_id, key: "k3", value: "v3"}), opts)

          assert {:ok, 3} = @fact_adapter.count_facts(user_id, opts)
        end

        test "does not double count on upsert", %{opts: opts} do
          user_id = "user_cf_upsert_#{System.unique_integer([:positive])}"
          fact = build_fact(%{user_id: user_id, key: "color", value: "blue"})

          {:ok, _} = @fact_adapter.save_fact(fact, opts)
          {:ok, _} = @fact_adapter.save_fact(%{fact | value: "green"}, opts)
          {:ok, _} = @fact_adapter.save_fact(%{fact | value: "red"}, opts)

          assert {:ok, 1} = @fact_adapter.count_facts(user_id, opts)
        end
      end
    end
  end
end
