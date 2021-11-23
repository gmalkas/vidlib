defmodule Vidlib.Download.Worker do
  use GenServer

  require Logger

  alias Vidlib.{Database, Download, Downloader, Event, Settings, Video}

  # API

  def start_link(%Video{} = video) do
    name = {:via, Registry, {Registry.Download.Worker, video.id}}
    GenServer.start_link(__MODULE__, video.id, name: name)
  end

  def cancel(worker_pid) do
    task = GenServer.call(worker_pid, :get_task)
    Task.Supervisor.terminate_child(Vidlib.Download.TaskSupervisor, task.pid)
  end

  # CALLBACKS

  def child_spec([video_id] = args) do
    %{
      id: {__MODULE__, video_id},
      start: {__MODULE__, :start_link, args},
      restart: :transient
    }
  end

  def init(video_id) do
    {:ok, video_id, {:continue, :start_download}}
  end

  def handle_continue(:start_download, video_id) do
    task =
      Task.Supervisor.async(Vidlib.Download.TaskSupervisor, fn ->
        start_download(video_id)
      end)

    {:noreply, {video_id, task}}
  end

  def handle_call(:get_task, _, {_, task} = state) do
    {:reply, task, state}
  end

  def handle_info({_task_ref, :task_exited}, state) do
    {:stop, :normal, state}
  end

  # HELPERS

  defp start_download(video_id) do
    video = Database.get(Video, video_id)
    download = video.download

    %{video_format: video_format, audio_format: audio_format} = download

    formatted_resolution = "#{elem(video_format.resolution, 1)}p"

    Logger.info("Downloading '#{video.title}' (#{formatted_resolution})")

    Database.put(Video.with_download(video, Download.started(download)))
    Database.save()

    Event.Dispatcher.publish({:download, :started, video.download.id})

    Downloader.download(
      Settings.file_output_template(),
      video,
      video_format.id,
      audio_format.id,
      fn
        {:ok, file_path} ->
          video = Database.get(Video, video_id)
          download = Download.completed(video.download, file_path)

          Database.put(Video.with_download(video, download))
          Database.save()

          Event.Dispatcher.publish({:download, :done, download.id})

          Logger.info(
            "Completed download of '#{video.title}' (#{elem(video_format.resolution, 1)}p)"
          )

        {:error, _status} ->
          video = Database.get(Video, video_id)
          download = Download.failed(video.download)

          Database.put(Video.with_download(video, Download.failed(download)))
          Database.save()

          Event.Dispatcher.publish({:download, :failed, download.id})

          Logger.info(
            "Failed download of '#{video.title}' (#{elem(video_format.resolution, 1)}p)"
          )

        {:progress, progress, filetype, download_speed, eta} ->
          video = Database.get(Video, video_id)

          download =
            Download.with_progress(video.download, %{
              progress: progress,
              filetype: filetype,
              download_speed: download_speed,
              eta: eta
            })

          Database.put(Video.with_download(video, download))
          Database.save()

          Event.Dispatcher.publish({:download, :progress, download.id})

          Logger.info(
            "Downloading '#{video.title}' (#{elem(video_format.resolution, 1)}p) (#{filetype}): #{progress}% at #{download_speed} (ETA #{eta})"
          )
      end
    )

    :task_exited
  end
end
