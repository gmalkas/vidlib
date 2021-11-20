defmodule VidlibWeb.PageControllerTest do
  use VidlibWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, "/")
    assert html_response(conn, 200) =~ "Vidlib"
  end
end
