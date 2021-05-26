# Connect Proxy

[![CI](https://github.com/spider-gazelle/connect-proxy/actions/workflows/ci.yml/badge.svg)](https://github.com/spider-gazelle/connect-proxy/actions/workflows/ci.yml)

A simple implementation of the [connect method](https://en.wikipedia.org/wiki/HTTP_tunnel#HTTP_CONNECT_method) for HTTP tunnelling.
Most commonly used in [HTTP proxy servers](https://en.wikipedia.org/wiki/Proxy_server#Web_proxy_servers).

# Usage

The most common usage of this shard is to use the crystal `::HTTP::Client` via a proxy server

```crystal
host = URI.parse("https://www.google.com")
response = ConnectProxy::HTTPClient.new(host) do |client|
  client.exec("GET", "/")
end
response.success?
```

By default the HTTP client will pick up the `https_proxy` or `http_proxy` environment variables and use the URLs configured in there.
However you can override the environment or provide your own proxy server.

```crystal
host = URI.parse("https://www.google.com")
client = ConnectProxy::HTTPClient.new(host)
proxy = ConnectProxy.new("134.209.219.234", 80, {username: "admin", password: "pass"})
client.set_proxy(proxy)
response = client.exec("GET", "/")
response.success?
```
