defmodule VidlibWeb.FeedLive.ProgressBarComponent do
  use VidlibWeb, :live_component

  def render(assigns) do
    ~H"""
    <div class="absolute top-0 h-3 w-full rounded-full overflow-hidden z-20">
      <div class={"h-full relative w-px #{@color}"} style={"width: #{round(@progress)}%"}></div>
    </div>
    """
  end
end
