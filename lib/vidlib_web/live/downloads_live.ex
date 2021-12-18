defmodule VidlibWeb.DownloadsLive do
  use VidlibWeb, :live_view

  import VidlibWeb.View.Helpers

  require Logger

  alias Phoenix.LiveView.JS

  alias Vidlib.{Database, Download, Event, Feed, Player, Video}

  def mount(_params, _, socket) do
    :ok = Event.Dispatcher.subscribe(self())

    downloads = fetch_downloads()

    downloads_by_status =
      Map.merge(
        %{
          in_progress: [],
          completed: [],
          failed: [],
          queued: [],
          paused: []
        },
        group_by_status(downloads)
      )

    {:ok, assign(socket, downloads_by_status: downloads_by_status)}
  end

  def handle_event("video:play", %{"video_id" => video_id}, socket) do
    video = Database.get(Video, video_id)

    if !is_nil(video.download) do
      Task.start(fn ->
        case Player.play(video.download) do
          {:error, :not_found} ->
            Logger.warn("Could not play #{video.title}: file missing at #{video.download.path}")
            Download.Manager.delete(video.id)

            send(self(), :refresh_downloads)

          _ ->
            Logger.info("Playing #{video.title} at #{video.download.path}...")
            :ok
        end
      end)
    end

    {:noreply, socket}
  end

  def handle_event("delete", %{"video_id" => video_id}, socket) do
    :ok = Download.Manager.delete(video_id)

    send(self(), :refresh_downloads)

    {:noreply, socket}
  end

  def handle_event("cancel", %{"video_id" => video_id}, socket) do
    :ok = Download.Manager.cancel(video_id)

    send(self(), :refresh_downloads)

    {:noreply, socket}
  end

  def handle_event("pause", %{"video_id" => video_id}, socket) do
    :ok = Download.Manager.pause(video_id)

    send(self(), :refresh_downloads)

    {:noreply, socket}
  end

  def handle_event("resume", %{"video_id" => video_id}, socket) do
    :ok = Download.Manager.resume(video_id)

    send(self(), :refresh_downloads)

    {:noreply, socket}
  end

  def handle_info(:refresh_downloads, socket) do
    downloads = fetch_downloads()

    downloads_by_status =
      Map.merge(
        %{
          in_progress: [],
          completed: [],
          failed: [],
          queued: [],
          paused: []
        },
        group_by_status(downloads)
      )

    {:noreply, assign(socket, downloads_by_status: downloads_by_status)}
  end

  def handle_info({:download, _, _}, socket) do
    downloads = fetch_downloads()

    downloads_by_status =
      Map.merge(
        %{
          in_progress: [],
          completed: [],
          failed: [],
          queued: [],
          paused: []
        },
        group_by_status(downloads)
      )

    {:noreply, assign(socket, downloads_by_status: downloads_by_status)}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  defp fetch_downloads do
    Database.all(Video)
    |> Enum.filter(&(!is_nil(&1.download)))
    |> Enum.map(&{Database.get(Feed, &1.feed_id), &1, &1.download})
  end

  defp group_by_status(downloads) do
    downloads
    |> Enum.group_by(fn {_, _, download} ->
      cond do
        Download.queued?(download) -> :queued
        Download.paused?(download) -> :paused
        Download.completed?(download) -> :completed
        Download.failed?(download) -> :failed
        Download.in_progress?(download) -> :in_progress
        true -> :queued
      end
    end)
    |> Enum.map(fn {group, downloads} ->
      {
        group,
        Enum.sort_by(
          downloads,
          fn {_, _, download} ->
            case group do
              :completed -> download.completed_at
              _ -> download.created_at
            end
          end,
          {:desc, DateTime}
        )
      }
    end)
    |> Map.new()
  end
end
