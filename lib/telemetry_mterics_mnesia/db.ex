defmodule TelemetryMetricsMnesia.Db do
  @moduledoc false

  require Logger
  require Record

  alias :mnesia, as: Mnesia

  Record.defrecord(:telemetry_events, key: {[], nil}, measurements: %{}, metadata: %{})

  @type t() :: record(:telemetry_events, key: {Telemetry.event_name(), non_neg_integer()}, measurements:
  Telemetry.event_measurements(), metadata: Telemetry.event_metadata())

  def write_event(event, measurements, metadata) do
    transaction = fn() ->
      timestamp =
        DateTime.utc_now()
        |> DateTime.to_unix()
      Mnesia.write(telemetry_events(key: {timestamp, event}, measurements: measurements, metadata: metadata))
    end

    case Mnesia.transaction(transaction) do
      {:atomic, :ok} ->
        :ok
      {:aborted, reason} ->
        Logger.warning("Event #{inspect event} was not written to DB with reason: #{reason}")
        {:error, reason}
    end
  end

  def init() do
    Mnesia.create_table(:telemetry_events, attributes: [:event, :measurements, :metadata], type:
      :ordered_set)
  end

  def fetch(%Telemetry.Metrics.Counter{event_name: event_name}) do
    Mnesia.dirty_match_object(telemetry_events(key: {:_, event_name}))
    |> length()
  end
end
