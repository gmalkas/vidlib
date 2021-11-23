defmodule Vidlib.Settings do
  alias Vidlib.Database

  defstruct [:file_output_template]

  def file_output_template do
    get().file_output_template
  end

  def get do
    Database.get(:settings)
  end

  def put(%__MODULE__{} = settings), do: Database.put(:settings, settings)
end
