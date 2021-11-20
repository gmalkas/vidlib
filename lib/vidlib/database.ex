defmodule Vidlib.Database do
  use GenServer

  # API

  def start_link(_args) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def all(schema) do
    :ets.tab2list(__MODULE__)
    |> Enum.filter(fn
      {{^schema, _}, _} -> true
      _ -> false
    end)
    |> Enum.map(fn {_, v} -> v end)
  end

  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  def count(schema), do: Enum.count(all(schema))

  def get(%schema{id: id}) do
    get({schema, id})
  end

  def get(key) do
    case :ets.lookup(__MODULE__, key) do
      [{_, data}] -> data
      [] -> nil
    end
  end

  def drop(schema) do
    all(schema)
    |> Enum.each(&delete/1)
  end

  def delete(%schema{id: id}) do
    delete({schema, id})
  end

  def delete(key) do
    GenServer.call(__MODULE__, {:delete, key})
  end

  def merge(key, value) when is_map(value) do
    GenServer.call(__MODULE__, {:merge, key, value})
  end

  def put(%schema{id: id} = value) do
    put({schema, id}, value)
  end

  def put(key, value) do
    GenServer.call(__MODULE__, {:put, key, value})
  end

  def save do
    GenServer.call(__MODULE__, :save_to_file)
  end

  # CALLBACKS

  def init(_args) do
    tid =
      case restore_from_file() do
        {:ok, tid} -> tid
        {:error, :not_found} -> :ets.new(__MODULE__, [:named_table])
      end

    {:ok, tid}
  end

  def handle_call(:clear, _from, tid) do
    :ets.delete_all_objects(tid)
    store_cache_file(tid)

    {:reply, :ok, tid}
  end

  def handle_call({:delete, key}, _from, tid) do
    :ets.delete(tid, key)

    {:reply, :ok, tid}
  end

  def handle_call({:put, key, value}, _from, tid) do
    put_in_cache(tid, key, value)

    {:reply, :ok, tid}
  end

  def handle_call({:merge, key, value}, _from, tid) do
    merge_in_cache(tid, key, value)

    {:reply, :ok, tid}
  end

  def handle_call(:save_to_file, _from, tid) do
    store_cache_file(tid)

    {:reply, :ok, tid}
  end

  # HELPERS

  defp restore_from_file do
    file_path = file_path()

    if File.exists?(file_path) do
      :ets.file2tab(String.to_charlist(file_path))
    else
      {:error, :not_found}
    end
  end

  defp merge_in_cache(tid, key, value) do
    case get(key) do
      {:ok, data} -> put_in_cache(tid, key, Map.merge(data, value))
      {:error, :not_found} -> put_in_cache(tid, key, value)
    end
  end

  defp put_in_cache(tid, key, value), do: :ets.insert(tid, {key, value})

  defp store_cache_file(tid),
    do: :ets.tab2file(tid, String.to_charlist(file_path()), sync: true)

  defp file_path() do
    Path.join(
      Application.get_env(:vidlib, :cache_path, "/tmp"),
      "vidlib.ets"
    )
  end
end
