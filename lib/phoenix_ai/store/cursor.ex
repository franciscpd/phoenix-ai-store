defmodule PhoenixAI.Store.Cursor do
  @moduledoc """
  Shared keyset cursor encoding and decoding for paginated queries.

  Used by both EventLog and CostStore to produce opaque cursor strings
  for cursor-based pagination. The cursor encodes a `(DateTime, id)` pair
  as a Base64URL string.
  """

  @doc """
  Encodes a timestamp and id into an opaque cursor string.
  """
  @spec encode(DateTime.t(), String.t()) :: String.t()
  def encode(%DateTime{} = ts, id) when is_binary(id) do
    Base.url_encode64("#{DateTime.to_iso8601(ts)}|#{id}", padding: false)
  end

  @doc """
  Decodes a cursor string back into `{DateTime.t(), String.t()}`.

  Returns `{:error, :invalid_cursor}` if the cursor is malformed.
  """
  @spec decode(String.t()) :: {:ok, {DateTime.t(), String.t()}} | {:error, :invalid_cursor}
  def decode(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [ts_str, id] when id != "" <- String.split(decoded, "|", parts: 2),
         {:ok, ts, _} <- DateTime.from_iso8601(ts_str) do
      {:ok, {ts, id}}
    else
      _ -> {:error, :invalid_cursor}
    end
  end
end
