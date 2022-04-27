require "../../connect-proxy"

class ::HTTP::WebSocket
  include ConnectProxy::ProxyWebSocket
end
