defmodule Vidlib.Feed do
  alias Vidlib.Video

  defstruct [:id, :name, :videos, :youtube_channel, :refreshed_at]

  def new(%Youtube.Channel{} = channel) do
    %__MODULE__{
      id: channel.id,
      name: channel.name,
      videos: Enum.map(channel.videos, &Video.new/1),
      youtube_channel: Youtube.Channel.without_videos(channel)
    }
  end

  def put_videos(%__MODULE__{} = feed, videos) do
    %__MODULE__{feed | videos: videos}
  end

  def refreshed(%__MODULE__{} = feed, refreshed_at \\ DateTime.utc_now()) do
    %__MODULE__{feed | refreshed_at: refreshed_at}
  end
end
