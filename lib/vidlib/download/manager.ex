defmodule Vidlib.Download.Manager do
  use GenServer

  require Logger

  alias Vidlib.{Database, Download, Event, Video}

  @default_pool_size 4

  # API

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start(%Video{} = video) do
    GenServer.call(__MODULE__, {:start_download, video})
  end

  def pause(video_id) do
    with {:ok, worker_pid} <- worker_pid(video_id) do
      :ok = Download.Worker.cancel(worker_pid)
      Event.Dispatcher.publish({:download, :paused, video_id})
    end

    video = Database.get(Video, video_id)
    Database.put(Video.with_download(video, Download.paused(video.download)))

    GenServer.call(__MODULE__, {:drop_from_queue, video.id})

    Database.save()

    :ok
  end

  def resume(video_id) do
    video = Database.get(Video, video_id)

    GenServer.call(__MODULE__, {:start_download, video})
  end

  def cancel(video_id) do
    with {:ok, worker_pid} <- worker_pid(video_id) do
      :ok = Download.Worker.cancel(worker_pid)
      Event.Dispatcher.publish({:download, :cancelled, video_id})
    end

    GenServer.call(__MODULE__, {:drop_from_queue, video_id})

    delete_download(video_id)

    :ok
  end

  def delete(video_id) do
    delete_download(video_id)

    :ok
  end

  # CALLBACKS

  def init(_args) do
    Process.monitor(Vidlib.Download.Supervisor)

    {:ok, nil, {:continue, :resume_downloads}}
  end

  def handle_continue(:resume_downloads, nil) do
    Event.Dispatcher.subscribe(self())

    videos_with_suspended_download =
      Database.all(Video)
      |> Enum.filter(&Video.download_in_progress?/1)

    videos_with_queued_download =
      Database.all(Video)
      |> Enum.filter(&Video.download_queued?/1)

    queue =
      Enum.concat(videos_with_suspended_download, videos_with_queued_download)
      |> Enum.map(& &1.id)
      |> Enum.uniq()

    {:noreply, process_queue(queue)}
  end

  def handle_call({:start_download, video}, _, queue) do
    video_id = video.id
    new_queue = process_queue(queue ++ [video_id])

    case new_queue do
      [^video_id | _] ->
        Database.put(Video.with_download(video, Download.queued(video.download)))
        Database.save()

      _ ->
        :ok
    end

    {:reply, :ok, new_queue}
  end

  def handle_call({:drop_from_queue, video_id}, _, queue) do
    {:reply, :ok, List.delete(queue, video_id)}
  end

  def handle_info({:download, status, _}, queue)
      when status in [:done, :failed, :paused, :cancelled] do
    {:noreply, process_queue(queue)}
  end

  def handle_info(_, queue) do
    {:noreply, queue}
  end

  # HELPERS

  defp process_queue(queue) do
    Logger.debug("Processing download queue...")

    if length(queue) > 0 do
      {video_ids, remaining_queue} = Enum.split(queue, pool_remaining_size())

      Logger.debug(
        "Starting #{length(video_ids)} downloads, #{length(remaining_queue)} remaining in queue"
      )

      Enum.each(video_ids, &({:ok, _} = start_worker(&1)))

      remaining_queue
    else
      queue
    end
  end

  defp pool_remaining_size do
    max(pool_size() - worker_count(), 0)
  end

  defp pool_size, do: @default_pool_size
  defp worker_count, do: length(Task.Supervisor.children(Vidlib.Download.TaskSupervisor))

  defp worker_pid(video_id) do
    case Registry.lookup(Registry.Download.Worker, video_id) do
      [] -> {:error, :not_found}
      [{pid, _}] -> {:ok, pid}
    end
  end

  defp start_worker(video_id) do
    video = Database.get(Video, video_id)

    case DynamicSupervisor.start_child(
           Vidlib.Download.Supervisor,
           {Download.Worker, [video]}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  defp delete_download(video_id) do
    video = Database.get(Video, video_id)
    delete_file(video.download.path)
    Database.put(Video.drop_download(video))
    Database.save()
  end

  defp delete_file(nil), do: :ok

  defp delete_file(file_path) do
    File.rm(file_path)
  end
end
