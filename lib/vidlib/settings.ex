defmodule Vidlib.Settings do
  alias Vidlib.Database

  defstruct [:file_output_template, :ytdlp_path]

  def file_output_template do
    get().file_output_template
  end

  def ytdlp_path do
    get().ytdlp_path
  end

  def get do
    Database.get(:settings) || %__MODULE__{}
  end

  def put(%__MODULE__{} = settings), do: Database.put(:settings, settings)
end
