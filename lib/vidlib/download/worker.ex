defmodule Vidlib.Download.Worker do
  use GenServer

  require Logger

  alias Vidlib.{Database, Download, Downloader, Event, Video}

  # API

  def start_link(%Video{} = video) do
    name = {:via, Registry, {Registry.Download.Worker, video.id}}
    GenServer.start_link(__MODULE__, video, name: name)
  end

  def cancel(worker_pid) do
    task = GenServer.call(worker_pid, :get_task)
    Task.Supervisor.terminate_child(Vidlib.Download.TaskSupervisor, task.pid)
  end

  # CALLBACKS

  def child_spec([video] = args) do
    %{
      id: {__MODULE__, video.id},
      start: {__MODULE__, :start_link, args},
      restart: :transient
    }
  end

  def init(video) do
    {:ok, video, {:continue, :start_download}}
  end

  def handle_continue(:start_download, video) do
    myself = self()

    task =
      Task.Supervisor.async(Vidlib.Download.TaskSupervisor, fn ->
        start_download(myself, video)
      end)

    {:noreply, {video, task}}
  end

  def handle_call(:get_task, _, {_, task} = state) do
    {:reply, task, state}
  end

  def handle_cast({:progress, download}, state) do
    Event.Dispatcher.publish({:download, :progress, download.id})

    {:noreply, state}
  end

  def handle_cast({:failed, download}, state) do
    Event.Dispatcher.publish({:download, :failed, download.id})

    {:noreply, state}
  end

  def handle_cast({:done, download}, state) do
    Event.Dispatcher.publish({:download, :done, download.id})

    {:noreply, state}
  end

  def handle_info({_task_ref, :task_exited}, state) do
    {:stop, :normal, state}
  end

  # HELPERS

  defp start_download(parent_pid, video) do
    download = video.download

    %{video_format_id: video_format_id, audio_format_id: audio_format_id} = download

    video_format = Enum.find(video.youtube_video.formats, &(&1.id == video_format_id))
    formatted_resolution = "#{elem(video_format.resolution, 1)}p"

    Logger.info("Downloading '#{video.title}' (#{formatted_resolution})")

    Database.put(Video.with_download(video, Download.started(download)))
    Event.Dispatcher.publish({:download, :started, video.download.id})

    Downloader.download(downloads_path(), video, video_format_id, audio_format_id, fn
      :ok ->
        download = Download.completed(download)

        Database.put(Video.with_download(video, download))
        Database.save()

        GenServer.cast(parent_pid, {:done, download})

        Logger.info(
          "Completed download of '#{video.title}' (#{elem(video_format.resolution, 1)}p)"
        )

      {:error, _status} ->
        download = Download.failed(download)

        Database.put(Video.with_download(video, Download.failed(download)))
        Database.save()

        GenServer.cast(parent_pid, {:failed, download})

        Logger.info("Failed download of '#{video.title}' (#{elem(video_format.resolution, 1)}p)")

      {:progress, progress, filetype, download_speed, eta} ->
        download =
          Download.with_progress(download, %{
            progress: progress,
            filetype: filetype,
            download_speed: download_speed,
            eta: eta
          })

        Database.put(Video.with_download(video, download))
        Database.save()

        GenServer.cast(parent_pid, {:progress, download})

        Logger.info(
          "Downloading '#{video.title}' (#{elem(video_format.resolution, 1)}p) (#{filetype}): #{progress}% at #{download_speed} (ETA #{eta})"
        )
    end)

    :task_exited
  end

  defp downloads_path do
    "/tmp"
  end
end
