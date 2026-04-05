[
  # Mix.Generator functions are macros — dialyzer can't resolve them
  {"lib/mix/tasks/phoenix_ai_store.gen.migration.ex"},
  # Pattern match coverage in fire-and-forget helpers (intentional catch-all)
  {"lib/phoenix_ai/store/converse_pipeline.ex", :pattern_match_cov}
]
