defmodule Vidlib.Subscription do
  defstruct [:id, :feed_url]

  def new(id, feed_url) do
    %__MODULE__{id: id, feed_url: feed_url}
  end
end
