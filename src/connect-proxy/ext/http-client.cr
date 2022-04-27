require "../../connect-proxy"

class ::HTTP::Client
  include ConnectProxy::ProxyHTTP
end
