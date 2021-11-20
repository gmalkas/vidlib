defmodule Vidlib.Video do
  alias Vidlib.Download

  defstruct [
    :id,
    :title,
    :download,
    :thumbnail,
    :youtube_video,
    :published_at,
    :link,
    :description,
    :duration
  ]

  def new(%Youtube.Video{} = video) do
    %__MODULE__{
      id: video.id,
      title: video.title,
      published_at: video.published_at,
      duration: video.duration,
      description: video.description,
      link: video.link,
      youtube_video: video
    }
  end

  def with_download(%__MODULE__{} = video, %Download{} = download) do
    %__MODULE__{video | download: download}
  end

  def with_thumbnail(%__MODULE__{} = video, thumbnail_data_url) do
    %__MODULE__{video | thumbnail: thumbnail_data_url}
  end
end
