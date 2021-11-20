defmodule Vidlib.Pagination do
  def paginate(all_entries, page_size, page_number \\ 1) when page_number >= 1 do
    entries = Enum.slice(all_entries, page_size * (page_number - 1), page_size)
    total_entry_count = Enum.count(all_entries)
    partial_page? = rem(total_entry_count, page_size) > 0

    partial_page =
      if partial_page? do
        1
      else
        0
      end

    page_count = div(total_entry_count, page_size) + partial_page

    %{
      entries: entries,
      number: page_number,
      count: page_count,
      size: page_size,
      total_entry_count: total_entry_count
    }
  end
end
