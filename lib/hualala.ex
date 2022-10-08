defmodule HuaLaLa do
  @moduledoc """
  HuaLaLa SDK for Elixir

  [哗啦啦开放平台 - 接口调用规则](http://open.web.hualala.com/resource/16922)
  """

  @version "3"
  @finch_name HuaLaLa.Finch
  @base_url "https://www-openapi.hualala.com"

  def sign(app_key, secret, timestamp, request_body) do
    md5("#{app_key}#{secret}#{timestamp}#{request_body}")
  end

  defp md5(content) do
    content |> :erlang.md5() |> Base.encode16(case: :lower)
  end

  def start_finch do
    Finch.start_link(name: @finch_name, pools: %{:default => [size: 32, count: 8]})
  end

  def req(path, data, options) do
    options = Map.new(options)
    %{app_key: app_key, secret: secret, headers: headers} = options
    timestamp = System.os_time(:second)
    headers = Map.new(headers)
    group_id = Map.fetch!(headers, :group_id)

    trace_id =
      Map.get_lazy(headers, :trace_id, fn ->
        rand = :crypto.strong_rand_bytes(16) |> Base.encode16()
        "#{timestamp}:#{rand}"
      end)

    headers =
      if shop_id = Map.get(headers, :shop_id) do
        [{"traceID", trace_id}, {"groupID", group_id}, {"shopID", shop_id}]
      else
        [{"traceID", trace_id}, {"groupID", group_id}]
      end

    request_body = Jason.encode!(data)

    body = %{
      timestamp: timestamp,
      appKey: app_key,
      signature: sign(app_key, secret, timestamp, request_body),
      version: @version,
      requestBody: request_body
    }

    [
      {Tesla.Middleware.BaseUrl, @base_url},
      Tesla.Middleware.EncodeFormUrlencoded,
      {Tesla.Middleware.Headers, headers},
      Tesla.Middleware.Logger,
      {Tesla.Middleware.Retry,
       delay: 500,
       max_retries: 3,
       max_delay: 2_000,
       should_retry: fn
         {:ok, %{status: status}} when status in [400, 500] -> true
         {:ok, _} -> false
         {:error, _} -> true
       end}
    ]
    |> Tesla.client(
      {Tesla.Adapter.Finch, name: @finch_name, pool_timeout: 5_000, receive_timeout: 5_000}
    )
    |> Tesla.post(path, body)
  end
end
