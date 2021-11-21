defmodule Vidlib.Download.Manager do
  use GenServer

  require Logger

  alias Vidlib.{Database, Download, Video}

  # API

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def start(%Video{} = video) do
    start_worker(video)
  end

  def pause(video_id) do
    with {:ok, worker_pid} <- worker_pid(video_id) do
      :ok = Download.Worker.cancel(worker_pid)
    end

    video = Database.get(Video, video_id)
    Database.put(Video.with_download(video, Download.paused(video.download)))
    Database.save()

    :ok
  end

  def resume(video_id) do
    video = Database.get(Video, video_id)
    video = Video.with_download(video, Download.resumed(video.download))

    Database.put(video)
    Database.save()

    with {:ok, _} <- start_worker(video) do
      :ok
    end
  end

  def cancel(video_id) do
    with {:ok, worker_pid} <- worker_pid(video_id) do
      :ok = Download.Worker.cancel(worker_pid)
    end

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

  def handle_continue(:resume_downloads, state) do
    videos_with_suspended_download =
      Database.all(Video)
      |> Enum.filter(&(Video.download_started?(&1) && !Video.download_paused?(&1)))

    video_count = length(videos_with_suspended_download)

    if video_count > 0 do
      Logger.info("Resuming downloads for #{video_count} videos...")

      Enum.each(videos_with_suspended_download, fn video ->
        {:ok, _} = start_worker(video)
      end)
    end

    {:noreply, state}
  end

  # HELPERS

  defp worker_pid(video_id) do
    case Registry.lookup(Registry.Download.Worker, video_id) do
      [] -> {:error, :not_found}
      [{pid, _}] -> {:ok, pid}
    end
  end

  defp start_worker(video) do
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
    Database.put(Video.drop_download(video))
    Database.save()
  end
end
