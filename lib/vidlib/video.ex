defmodule Vidlib.Video do
  alias Vidlib.Download

  @minimum_thumbnail_width_px 512

  defstruct [
    :id,
    :feed_id,
    :title,
    :download,
    :thumbnail,
    :thumbnail_resolution,
    :youtube_video,
    :published_at,
    :link,
    :description,
    :duration
  ]

  def download_completed?(%__MODULE__{} = video) do
    !is_nil(video.download) && Download.completed?(video.download)
  end

  def download_in_progress?(%__MODULE__{} = video) do
    !is_nil(video.download) && Download.in_progress?(video.download)
  end

  def download_started?(%__MODULE__{} = video) do
    !is_nil(video.download) && !Download.completed?(video.download)
  end

  def download_paused?(%__MODULE__{} = video) do
    !is_nil(video.download) && Download.paused?(video.download)
  end

  def download_queued?(%__MODULE__{} = video) do
    !is_nil(video.download) &&
      (!Download.started?(video.download) || Download.queued?(video.download))
  end

  def missing_thumbnail?(%__MODULE__{thumbnail: thumbnail}) do
    is_nil(thumbnail)
  end

  def new(%Youtube.Video{} = video) do
    %__MODULE__{
      id: video.id,
      feed_id: video.channel_id,
      title: video.title,
      published_at: video.published_at,
      duration: video.duration,
      description: video.description,
      link: video.link,
      youtube_video: video
    }
  end

  def poor_quality_thumbnail?(%__MODULE__{} = video) do
    is_nil(video.thumbnail_resolution) || low_thumbnail_resolution?(video.thumbnail_resolution)
  end

  def with_download(%__MODULE__{} = video, %Download{} = download) do
    %__MODULE__{video | download: download}
  end

  def with_thumbnail(%__MODULE__{} = video, {resolution, thumbnail_data_url}) do
    %__MODULE__{video | thumbnail: thumbnail_data_url, thumbnail_resolution: resolution}
  end

  def drop_download(%__MODULE__{} = video) do
    %__MODULE__{video | download: nil}
  end

  defp low_thumbnail_resolution?({width, _height}), do: width < @minimum_thumbnail_width_px
end
