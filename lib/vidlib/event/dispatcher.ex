defmodule Vidlib.Event.Dispatcher do
  use GenServer

  # API

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def publish(event) do
    GenServer.cast(__MODULE__, {:publish, event})
  end

  def subscribe(subscriber_pid) do
    GenServer.call(__MODULE__, {:subscribe, subscriber_pid})
  end

  # CALLBACKS

  def init(_args) do
    {:ok, []}
  end

  def handle_call({:subscribe, pid}, _from, subscribers) do
    ref = Process.monitor(pid)

    {:reply, :ok, [{ref, pid} | subscribers]}
  end

  def handle_cast({:publish, event}, subscribers) do
    Enum.each(subscribers, fn {_, pid} -> send(pid, event) end)

    {:noreply, subscribers}
  end

  def handle_info({:DOWN, ref, :process, pid, _reason}, subscribers) do
    {:noreply, List.delete(subscribers, {ref, pid})}
  end
end
