ExUnit.start()

{:ok, _} = PhoenixAI.Store.Test.Repo.start_link()
Ecto.Adapters.SQL.Sandbox.mode(PhoenixAI.Store.Test.Repo, :manual)

# Start the TestProvider registry globally so it outlives individual test processes.
# Tests that use PhoenixAI.Providers.TestProvider (which registers per-PID via this
# registry) must not start their own copy — a per-test start links the registry to
# the test process, causing it to die when that process exits and breaking concurrent
# async tests that are still using it.
{:ok, _} = Registry.start_link(keys: :unique, name: PhoenixAI.TestRegistry)
