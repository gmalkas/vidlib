defmodule VidlibWeb.FeedLive do
  use VidlibWeb, :live_view

  require Logger

  import VidlibWeb.View.Helpers

  alias Phoenix.LiveView.JS

  alias Vidlib.{
    Database,
    Download,
    Event,
    Feed,
    Feeder,
    Pagination,
    Player,
    Subscription,
    Video
  }

  @preferred_container_format "webm"
  @preferred_video_codec "vp9"
  @preferred_audio_codec "opus"
  @default_page_size 9

  def mount(params, _, socket) do
    :ok = Event.Dispatcher.subscribe(self())

    filters = %{}
    page_number = Map.get(params, "page", "1") |> String.to_integer()
    page = load_video_page(page_number, filters)

    downloads = load_ongoing_downloads()
    refreshed_at = Feeder.last_refreshed_at()

    {:ok,
     assign(socket,
       filters: filters,
       page: page,
       page_number: page_number,
       feeds: Database.all(Feed),
       downloads: downloads,
       refreshed_at: refreshed_at,
       refreshing_feed: nil
     )}
  end

  def handle_params(params, _, socket) do
    filters = Map.get(params, "filters", %{})
    page_number = Map.get(params, "page", "1") |> String.to_integer()
    page = load_video_page(page_number, filters)

    {:noreply,
     assign(socket,
       filters: filters,
       page: page,
       page_number: page_number
     )}
  end

  def handle_event("refresh_feed", _, socket) do
    myself = self()

    Task.start(fn ->
      Feeder.refresh(fn
        {%Feed{}, index, count} -> send(myself, {:feed_refreshed, index, count})
        :done -> send(myself, :feed_refreshed)
      end)
    end)

    {:noreply, assign(socket, refreshing_feed: {0, Database.count(Subscription)})}
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

  def handle_event("download:delete", %{"video_id" => video_id}, socket) do
    :ok = Download.Manager.delete(video_id)

    send(self(), :refresh_downloads)

    {:noreply, socket}
  end

  def handle_event("download:cancel", %{"video_id" => video_id}, socket) do
    :ok = Download.Manager.cancel(video_id)

    send(self(), :refresh_downloads)

    {:noreply, socket}
  end

  def handle_event("download:pause", %{"video_id" => video_id}, socket) do
    :ok = Download.Manager.pause(video_id)

    send(self(), :refresh_downloads)

    {:noreply, socket}
  end

  def handle_event("download:resume", %{"video_id" => video_id}, socket) do
    :ok = Download.Manager.resume(video_id)

    send(self(), :refresh_downloads)

    {:noreply, socket}
  end

  def handle_event("download:retry", %{"video_id" => video_id}, socket) do
    :ok = Download.Manager.resume(video_id)

    send(self(), :refresh_downloads)

    {:noreply, socket}
  end

  def handle_event("video:download", video_details, socket) do
    %{"video_id" => video_id, "format_id" => format_id} = video_details

    video = Database.get(Video, video_id)
    video_format = Enum.find(video.youtube_video.formats, &(&1.id == format_id))

    audio_format =
      Enum.filter(
        video.youtube_video.formats,
        &(&1.audio_codec == @preferred_audio_codec && !&1.video?)
      )
      |> Enum.max_by(& &1.size)

    download =
      Download.new(
        id: video.id,
        video_format: video_format,
        audio_format: audio_format,
        created_at: DateTime.utc_now()
      )

    video = Video.with_download(video, download)

    Database.put(video)

    :ok = Download.Manager.start(video)

    {:noreply, socket}
  end

  def handle_info({:feed_refreshed, index, count}, socket) do
    page = load_video_page(socket.assigns.page_number, socket.assigns.filters)

    {:noreply, assign(socket, page: page, refreshing_feed: {index, count})}
  end

  def handle_info(:refresh_downloads, socket) do
    page = load_video_page(socket.assigns.page_number, socket.assigns.filters)
    downloads = load_ongoing_downloads()

    {:noreply, assign(socket, downloads: downloads, page: page)}
  end

  def handle_info(:feed_refreshed, socket) do
    refreshed_at = Feeder.last_refreshed_at()

    {:noreply, assign(socket, refreshing_feed: nil, refreshed_at: refreshed_at)}
  end

  def handle_info({:video, :new, _}, socket) do
    page = load_video_page(socket.assigns.page_number, socket.assigns.filters)

    {:noreply, assign(socket, page: page)}
  end

  def handle_info({:download, _, _}, socket) do
    page = load_video_page(socket.assigns.page_number, socket.assigns.filters)
    downloads = load_ongoing_downloads()

    {:noreply, assign(socket, downloads: downloads, page: page)}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  def format_filter_label({"channel-id", channel_id}, assigns) do
    feed = Enum.find(assigns.feeds, &(&1.id == channel_id))

    "Channel: " <> feed.name
  end

  def video_overlay_class(video) do
    visible? =
      !is_nil(video.download) && Download.in_progress?(video.download) &&
        !Download.queued?(video.download)

    if visible? do
      "opacity-100"
    else
      "opacity-0"
    end
  end

  def format_video_count(_page_size, 0), do: "No videos"

  def format_video_count(page_size, video_count) do
    video_label =
      if video_count == 1 do
        "video"
      else
        "videos"
      end

    "Showing #{page_size} of #{video_count} #{video_label}"
  end

  def format_refresh_progress(nil), do: ""
  def format_refresh_progress({index, count}), do: "#{index} / #{count}"

  def format_refreshed_at(nil), do: "Click to refresh"

  def format_refreshed_at(refreshed_at) do
    refreshed_ago =
      Timex.diff(DateTime.utc_now(), refreshed_at, :duration)
      |> Timex.format_duration(:humanized)

    "Last refreshed #{refreshed_ago} ago"
  end

  def download_options(formats) do
    formats
    |> Enum.filter(&(&1.video? && interesting_resolution?(&1.resolution)))
    |> Enum.group_by(& &1.resolution)
    |> Enum.map(fn {_, formats} ->
      Enum.find(formats, &(&1.video_codec == @preferred_video_codec)) ||
        Enum.find(formats, &(&1.extension == @preferred_container_format)) ||
        List.first(formats)
    end)
    |> Enum.sort_by(& &1.resolution)
  end

  def thumbnail_url(video) do
    video.thumbnail
  end

  def refresh_button_class(nil), do: "refresh-button"
  def refresh_button_class({_, _}), do: "refresh-button refreshing"

  defp load_video_page(page_number, filters) do
    videos =
      Database.all(Video)
      |> apply_filters(filters)
      |> Enum.map(&{Database.get(Feed, &1.feed_id), &1})
      |> Enum.sort_by(fn {_, video} -> video.published_at end, {:desc, DateTime})

    Pagination.paginate(videos, @default_page_size, page_number)
  end

  defp load_ongoing_downloads do
    Database.all(Video)
    |> Enum.filter(&Video.download_in_progress?/1)
    |> Enum.map(&{Database.get(Feed, &1.feed_id), &1})
    |> Enum.sort_by(fn {_, video} -> video.published_at end, {:desc, DateTime})
    |> Enum.map(fn {feed, video} -> {feed, video, video.download} end)
  end

  defp interesting_resolution?({_, height}) do
    height >= 480
  end

  defp apply_filters(videos, filters) do
    videos
    |> Enum.filter(&match_filters?(&1, filters))
  end

  defp match_filters?(%Video{} = video, filters) do
    Enum.all?(filters, fn
      {"channel-id", channel_id} -> video.feed_id == channel_id
    end)
  end
end
