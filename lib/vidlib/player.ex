defmodule Vidlib.Player do
  alias Vidlib.Download

  def play(%Download{} = download) do
    if File.exists?(download.path) do
      {_, 0} = System.cmd(player_bin_path(), [download.path])

      :ok
    else
      {:error, :not_found}
    end
  end

  defp player_bin_path, do: "/usr/bin/xdg-open"
end
