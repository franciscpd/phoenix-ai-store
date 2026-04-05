defmodule PhoenixAI.Store.EventStoreContractTest do
  @moduledoc """
  Shared contract test suite for `PhoenixAI.Store.Adapter.EventStore` implementations.

  Any adapter test module can `use` this module to get a standard set of
  tests that verify the adapter correctly implements all EventStore callbacks.

  ## Usage

      defmodule MyAdapterTest do
        setup do
          # ... set up adapter-specific state ...
          {:ok, opts: [table: table]}
        end

        use PhoenixAI.Store.EventStoreContractTest, adapter: MyAdapter
      end

  The `setup` block MUST run before the `use` call and must return
  `{:ok, opts: opts}` where `opts` is the keyword list passed to
  every adapter callback.
  """

  defmacro __using__(macro_opts) do
    quote do
      alias PhoenixAI.Store.EventLog.Event

      @event_adapter unquote(macro_opts[:adapter])

      defp build_event(attrs \\ %{}) do
        defaults = %{
          id: nil,
          conversation_id: Uniq.UUID.uuid7(),
          user_id: "user_#{System.unique_integer([:positive])}",
          type: :message_sent,
          data: %{content: "hello"},
          metadata: %{},
          inserted_at: nil
        }

        struct(Event, Map.merge(defaults, attrs))
      end

      describe "log_event/2" do
        test "saves and returns an event with id and inserted_at", %{opts: opts} do
          event = build_event()
          assert {:ok, saved} = @event_adapter.log_event(event, opts)
          assert is_binary(saved.id)
          assert %DateTime{} = saved.inserted_at
          assert saved.conversation_id == event.conversation_id
          assert saved.user_id == event.user_id
          assert saved.type == :message_sent
          assert saved.data == %{content: "hello"}
          assert saved.metadata == %{}
        end

        test "assigns an id if none provided", %{opts: opts} do
          event = build_event(%{id: nil})
          assert {:ok, saved} = @event_adapter.log_event(event, opts)
          assert is_binary(saved.id)
        end

        test "preserves provided id", %{opts: opts} do
          id = Uniq.UUID.uuid7()
          event = build_event(%{id: id})
          assert {:ok, saved} = @event_adapter.log_event(event, opts)
          assert saved.id == id
        end
      end

      describe "list_events/2" do
        test "returns events ordered by inserted_at ascending", %{opts: opts} do
          conv_id = Uniq.UUID.uuid7()
          now = DateTime.utc_now()
          earlier = DateTime.add(now, -60, :second)
          later = DateTime.add(now, 60, :second)

          e1 = build_event(%{conversation_id: conv_id, inserted_at: later, type: :later})
          e2 = build_event(%{conversation_id: conv_id, inserted_at: earlier, type: :earlier})
          e3 = build_event(%{conversation_id: conv_id, inserted_at: now, type: :now})

          {:ok, _} = @event_adapter.log_event(e1, opts)
          {:ok, _} = @event_adapter.log_event(e2, opts)
          {:ok, _} = @event_adapter.log_event(e3, opts)

          {:ok, result} = @event_adapter.list_events([conversation_id: conv_id], opts)
          assert Enum.map(result.events, & &1.type) == [:earlier, :now, :later]
        end

        test "filters by conversation_id", %{opts: opts} do
          conv1 = Uniq.UUID.uuid7()
          conv2 = Uniq.UUID.uuid7()

          {:ok, _} = @event_adapter.log_event(build_event(%{conversation_id: conv1}), opts)
          {:ok, _} = @event_adapter.log_event(build_event(%{conversation_id: conv2}), opts)

          {:ok, result} = @event_adapter.list_events([conversation_id: conv1], opts)
          assert length(result.events) == 1
          assert hd(result.events).conversation_id == conv1
        end

        test "filters by user_id", %{opts: opts} do
          user = "event_user_filter"

          {:ok, _} = @event_adapter.log_event(build_event(%{user_id: user}), opts)
          {:ok, _} = @event_adapter.log_event(build_event(%{user_id: "other_user"}), opts)

          {:ok, result} = @event_adapter.list_events([user_id: user], opts)
          assert length(result.events) == 1
          assert hd(result.events).user_id == user
        end

        test "filters by type", %{opts: opts} do
          conv_id = Uniq.UUID.uuid7()

          {:ok, _} =
            @event_adapter.log_event(
              build_event(%{conversation_id: conv_id, type: :message_sent}),
              opts
            )

          {:ok, _} =
            @event_adapter.log_event(
              build_event(%{conversation_id: conv_id, type: :cost_recorded}),
              opts
            )

          {:ok, result} =
            @event_adapter.list_events([conversation_id: conv_id, type: :message_sent], opts)

          assert length(result.events) == 1
          assert hd(result.events).type == :message_sent
        end

        test "filters by time range (after/before)", %{opts: opts} do
          conv_id = Uniq.UUID.uuid7()
          now = DateTime.utc_now()
          yesterday = DateTime.add(now, -86_400, :second)
          tomorrow = DateTime.add(now, 86_400, :second)

          {:ok, _} =
            @event_adapter.log_event(
              build_event(%{conversation_id: conv_id, inserted_at: yesterday, type: :old}),
              opts
            )

          {:ok, _} =
            @event_adapter.log_event(
              build_event(%{conversation_id: conv_id, inserted_at: now, type: :current}),
              opts
            )

          {:ok, _} =
            @event_adapter.log_event(
              build_event(%{conversation_id: conv_id, inserted_at: tomorrow, type: :future}),
              opts
            )

          # after filter (inclusive)
          {:ok, result} = @event_adapter.list_events([conversation_id: conv_id, after: now], opts)
          types = Enum.map(result.events, & &1.type)
          assert :current in types
          assert :future in types
          refute :old in types

          # before filter (inclusive)
          {:ok, result} =
            @event_adapter.list_events([conversation_id: conv_id, before: now], opts)

          types = Enum.map(result.events, & &1.type)
          assert :old in types
          assert :current in types
          refute :future in types
        end

        test "cursor-based pagination: 5 events, limit 2, yields 3 pages", %{opts: opts} do
          conv_id = Uniq.UUID.uuid7()
          base = DateTime.utc_now()

          for i <- 0..4 do
            ts = DateTime.add(base, i * 10, :second)

            {:ok, _} =
              @event_adapter.log_event(
                build_event(%{conversation_id: conv_id, inserted_at: ts, type: :"event_#{i}"}),
                opts
              )
          end

          # Page 1
          {:ok, page1} = @event_adapter.list_events([conversation_id: conv_id, limit: 2], opts)
          assert length(page1.events) == 2
          assert page1.next_cursor != nil

          # Page 2
          {:ok, page2} =
            @event_adapter.list_events(
              [conversation_id: conv_id, limit: 2, cursor: page1.next_cursor],
              opts
            )

          assert length(page2.events) == 2
          assert page2.next_cursor != nil

          # Page 3 (last)
          {:ok, page3} =
            @event_adapter.list_events(
              [conversation_id: conv_id, limit: 2, cursor: page2.next_cursor],
              opts
            )

          assert length(page3.events) == 1
          assert page3.next_cursor == nil

          # All events are distinct and in order
          all_events = page1.events ++ page2.events ++ page3.events
          all_ids = Enum.map(all_events, & &1.id)
          assert length(Enum.uniq(all_ids)) == 5
        end

        test "empty results return empty map structure", %{opts: opts} do
          {:ok, result} =
            @event_adapter.list_events([conversation_id: Uniq.UUID.uuid7()], opts)

          assert result == %{events: [], next_cursor: nil}
        end
      end

      describe "count_events/2" do
        test "counts matching events", %{opts: opts} do
          conv_id = Uniq.UUID.uuid7()

          {:ok, _} = @event_adapter.log_event(build_event(%{conversation_id: conv_id}), opts)
          {:ok, _} = @event_adapter.log_event(build_event(%{conversation_id: conv_id}), opts)

          {:ok, _} =
            @event_adapter.log_event(build_event(%{conversation_id: Uniq.UUID.uuid7()}), opts)

          assert {:ok, 2} = @event_adapter.count_events([conversation_id: conv_id], opts)
        end

        test "returns 0 for no matches", %{opts: opts} do
          assert {:ok, 0} =
                   @event_adapter.count_events([conversation_id: Uniq.UUID.uuid7()], opts)
        end
      end
    end
  end
end
