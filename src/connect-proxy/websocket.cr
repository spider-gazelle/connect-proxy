require "../connect-proxy"

# alternative initialization
class HTTP::WebSocket::Protocol
  def self.new(socket, host : String, path : String, port, headers = HTTP::Headers.new)
    begin
      random_key = Base64.strict_encode(StaticArray(UInt8, 16).new { rand(256).to_u8 })

      headers["Host"] = "#{host}:#{port}"
      headers["Connection"] = "Upgrade"
      headers["Upgrade"] = "websocket"
      headers["Sec-WebSocket-Version"] = VERSION
      headers["Sec-WebSocket-Key"] = random_key

      path = "/" if path.empty?
      handshake = HTTP::Request.new("GET", path, headers)
      handshake.to_io(socket)
      socket.flush

      handshake_response = HTTP::Client::Response.from_io(socket, ignore_body: true)
      unless handshake_response.status.switching_protocols?
        raise Socket::Error.new("Handshake got denied. Status code was #{handshake_response.status.code}.")
      end

      challenge_response = Protocol.key_challenge(random_key)
      unless handshake_response.headers["Sec-WebSocket-Accept"]? == challenge_response
        raise Socket::Error.new("Handshake got denied. Server did not verify WebSocket challenge.")
      end
    rescue exc
      socket.close
      raise exc
    end

    new(socket, masked: true)
  end
end

module ConnectProxy::ProxyWebSocket
  macro included
    def self.new(
      uri : URI | String,
      headers = HTTP::Headers.new,
      proxy : ConnectProxy? = nil,
      ignore_env : Bool = false,
    )
      uri = URI.parse(uri) if uri.is_a?(String)

      if (host = uri.hostname) && (path = uri.request_target)
        tls = uri.scheme.in?("https", "wss")
        return new(host, path, uri.port, tls, headers, proxy, ignore_env)
      end

      raise ArgumentError.new("No host or path specified which are required.")
    end

    def self.new(
      host : String,
      path : String,
      port = nil,
      tls : HTTP::Client::TLSContext = nil,
      headers = HTTP::Headers.new,
      proxy : ConnectProxy? = nil,
      ignore_env : Bool = false,
    )
      if proxy.nil? && !ignore_env && ConnectProxy.behind_proxy?
        proxy = ConnectProxy.new(*ConnectProxy.parse_proxy_url)
      end

      ws = if proxy
             port ||= tls ? 443 : 80
             socket = proxy.open(host, port, tls)
             new(HTTP::WebSocket::Protocol.new(socket, host, path, port, headers))
           else
             new(HTTP::WebSocket::Protocol.new(host, path, port, tls, headers))
           end

      case tcp = ws.@ws.@io
      when TCPSocket
        tcp.tcp_keepalive_idle = 60
        tcp.tcp_keepalive_interval = 30
        tcp.tcp_keepalive_count = 3
        tcp.keepalive = true
        tcp.write_timeout = 10.seconds
      when OpenSSL::SSL::Socket::Client
        case sock = tcp.@bio.io
        when TCPSocket
          sock.tcp_keepalive_idle = 60
          sock.tcp_keepalive_interval = 30
          sock.tcp_keepalive_count = 3
          sock.keepalive = true
          sock.write_timeout = 10.seconds
        end
      end
      ws
    end
  end
end

class ConnectProxy::WebSocket < ::HTTP::WebSocket
  include ConnectProxy::ProxyWebSocket
end
