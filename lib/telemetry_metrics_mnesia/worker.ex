defmodule TelemetryMetricsMnesia.Worker do
  @moduledoc false

  use GenServer, restart: :permanent
  alias Telemetry.Metrics
  alias TelemetryMetricsMnesia.{Db, EventHandler}

  @spec start(TelemetryMetricsMnesia.options()) :: GenServer.on_start()
  def start(options), do: GenServer.start(__MODULE__, options, name: __MODULE__)

  @spec start_link(TelemetryMetricsMnesia.options()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    Db.init(Keyword.get(options, :mnesia, []))

    metrics = options[:metrics]
    handler_ids = EventHandler.attach(metrics)

    {:ok, %{metrics: metrics, handler_ids: handler_ids}}
  end

  @spec fetch(Metrics.metric_name(), %{}) :: TelemetryMetricsMnesia.metric_data()
  def fetch(metric_name, opts \\ %{})
  def fetch(metric_name, opts) when is_list(opts), do: fetch(metric_name, Map.new(opts))
  def fetch(metric_name, %{} = opts), do: GenServer.call(__MODULE__, {:fetch, metric_name, opts})

  @impl true
  def handle_call({:fetch, metric_name, opts}, _from, %{metrics: metrics} = state) do
    reply =
      for %mod{} = metric <- metrics,
          metric.name == metric_name,
          check_type(mod, opts),
          into: %{} do
        {mod, Db.fetch(metric)}
      end
      |> maybe_extract_type(opts)

    {:reply, reply, state}
  end

  @impl true
  def terminate(_reason, state) do
    EventHandler.detach(state.handler_ids)
    :ok
  end

  defp check_type(mod, %{type: type}), do: mod == type
  defp check_type(_mod, _opts), do: true

  defp maybe_extract_type(map, %{type: type}), do: Map.get(map, type)
  defp maybe_extract_type(map, _opts), do: map
end
