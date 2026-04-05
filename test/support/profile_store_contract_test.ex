defmodule PhoenixAI.Store.ProfileStoreContractTest do
  @moduledoc """
  Shared contract test suite for `PhoenixAI.Store.Adapter.ProfileStore` implementations.

  Any adapter test module can `use` this module to get a standard set of
  tests that verify the adapter correctly implements all ProfileStore callbacks.

  ## Usage

      defmodule MyAdapterTest do
        setup do
          # ... set up adapter-specific state ...
          {:ok, opts: [table: table]}
        end

        use PhoenixAI.Store.ProfileStoreContractTest, adapter: MyAdapter
      end

  The `setup` block MUST run before the `use` call and must return
  `{:ok, opts: opts}` where `opts` is the keyword list passed to
  every adapter callback.
  """

  defmacro __using__(macro_opts) do
    quote do
      alias PhoenixAI.Store.LongTermMemory.Profile

      @profile_adapter unquote(macro_opts[:adapter])

      defp build_profile(attrs \\ %{}) do
        defaults = %{
          id: Uniq.UUID.uuid7(),
          user_id: "user_#{System.unique_integer([:positive])}",
          summary: "A helpful assistant user.",
          metadata: %{}
        }

        struct(Profile, Map.merge(defaults, attrs))
      end

      describe "save_profile/2" do
        test "saves a new profile", %{opts: opts} do
          profile =
            build_profile(%{
              user_id: "user_sp_new_#{System.unique_integer([:positive])}",
              summary: "New user"
            })

          assert {:ok, saved} = @profile_adapter.save_profile(profile, opts)
          assert saved.user_id == profile.user_id
          assert saved.summary == "New user"
          assert %DateTime{} = saved.inserted_at
          assert %DateTime{} = saved.updated_at
        end

        test "upserts existing profile — same user_id overwrites", %{opts: opts} do
          user_id = "user_sp_upsert_#{System.unique_integer([:positive])}"
          profile = build_profile(%{user_id: user_id, summary: "Original summary"})

          {:ok, saved} = @profile_adapter.save_profile(profile, opts)
          original_inserted_at = saved.inserted_at

          updated_profile = %{profile | summary: "Updated summary"}
          {:ok, upserted} = @profile_adapter.save_profile(updated_profile, opts)

          assert upserted.summary == "Updated summary"
          assert upserted.inserted_at == original_inserted_at
        end
      end

      describe "load_profile/2" do
        test "returns {:error, :not_found} for unknown user", %{opts: opts} do
          assert {:error, :not_found} =
                   @profile_adapter.load_profile("unknown_user_#{Uniq.UUID.uuid7()}", opts)
        end

        test "returns profile for user", %{opts: opts} do
          user_id = "user_lp_#{System.unique_integer([:positive])}"
          profile = build_profile(%{user_id: user_id, summary: "Loves Elixir"})
          {:ok, _} = @profile_adapter.save_profile(profile, opts)

          assert {:ok, loaded} = @profile_adapter.load_profile(user_id, opts)
          assert loaded.user_id == user_id
          assert loaded.summary == "Loves Elixir"
        end
      end

      describe "delete_profile/2" do
        test "deletes an existing profile", %{opts: opts} do
          user_id = "user_dp_#{System.unique_integer([:positive])}"
          profile = build_profile(%{user_id: user_id, summary: "To be deleted"})
          {:ok, _} = @profile_adapter.save_profile(profile, opts)

          assert :ok = @profile_adapter.delete_profile(user_id, opts)
          assert {:error, :not_found} = @profile_adapter.load_profile(user_id, opts)
        end

        test "returns :ok for non-existent profile", %{opts: opts} do
          assert :ok =
                   @profile_adapter.delete_profile("no_such_user_#{Uniq.UUID.uuid7()}", opts)
        end
      end
    end
  end
end
