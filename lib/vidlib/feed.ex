defmodule Vidlib.Feed do
  alias Vidlib.Video

  defstruct [:id, :name, :videos, :video_ids, :youtube_channel, :refreshed_at]

  def new(%Youtube.Channel{} = channel) do
    %__MODULE__{
      id: channel.id,
      name: channel.name,
      video_ids: MapSet.new(Enum.map(channel.videos, & &1.id)),
      videos: Enum.map(channel.videos, &Video.new/1),
      youtube_channel: Youtube.Channel.without_videos(channel)
    }
  end

  def put_video_ids(%__MODULE__{} = feed, ids) do
    %__MODULE__{feed | video_ids: ids}
  end

  def refreshed(%__MODULE__{} = feed, refreshed_at \\ DateTime.utc_now()) do
    %__MODULE__{feed | refreshed_at: refreshed_at}
  end

  def without_videos(%__MODULE__{} = feed) do
    %__MODULE__{feed | videos: :__not_loaded__}
  end
end
