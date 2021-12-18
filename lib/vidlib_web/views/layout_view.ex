defmodule VidlibWeb.LayoutView do
  use VidlibWeb, :view

  alias Vidlib.{Database, Video}

  # Phoenix LiveDashboard is available only in development by default,
  # so we instruct Elixir to not warn if the dashboard route is missing.
  @compile {:no_warn_undefined, {Routes, :live_dashboard_path, 2}}

  def download_count do
    Database.all(Video)
    |> Enum.filter(&Video.download_in_progress?/1)
    |> length()
  end

  def nav_tab_class(%{view: view}, view), do: "tab tab-active"
  def nav_tab_class(_, _), do: "tab"
end
