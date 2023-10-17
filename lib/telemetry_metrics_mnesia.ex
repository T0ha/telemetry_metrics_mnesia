defmodule TelemetryMetricsMnesia do

  use GenServer
  alias TelemetryMetricsMnesia.{Db, EventHandler}

  @type options() :: [option()]
  @type option() :: {:metrics, Telemetry.Metrics.t()}

  @spec start_link(options()) :: GenServer.on_start()
  def start_link(options), do: GenServer.start_link(__MODULE__, options, name: __MODULE__)

  @impl true
  def init(options) do
    Process.flag(:trap_exit, true)
    Db.init()

    metrics = options[:metrics]
    handler_ids = EventHandler.attach(metrics)

    {:ok, %{metrics: metrics, handler_ids: handler_ids}}
  end

  def fetch(metric_name, opts \\ %{}), do:
    GenServer.call(__MODULE__, {:fetch, metric_name, opts})

  @impl true
  def handle_call({:fetch, metric_name, opts}, _from, %{metrics: metrics} = state) do
    reply =
      for metric <- metrics, metric.name == metric_name, into: %{} do
        {metric.name, Db.fetch(metric)}
      end
    {:reply, reply, state} 
  end

  @impl true
  def terminate(_reason, state) do
    EventHandler.detach(state.handler_ids)

    :ok
  end


  defp keep?(%{keep: keep}, metadata) when keep != nil, do: keep.(metadata)
  defp keep?(_metric, _metadata), do: true


  def extract_tags(metric, metadata) do
    tag_values = metric.tag_values.(metadata)
    Map.take(tag_values, metric.tags)
  end
end
