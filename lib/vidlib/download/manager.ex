defmodule Vidlib.Download.Manager do
  alias Vidlib.{Database, Download, Video}

  def download(%Video{} = video) do
    start_worker(video)
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
