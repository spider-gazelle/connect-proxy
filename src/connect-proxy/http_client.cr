require "../connect-proxy"

module ConnectProxy::ProxyHTTP
  macro included
    def self.new(uri : URI, tls : TLSContext = nil, ignore_env = false)
      {% if @type.stringify == "HTTP::Client" %}
        inst = previous_def(uri, tls)
      {% else %}
        inst = super(uri, tls)
      {% end %}

      if !ignore_env && ConnectProxy.behind_proxy?
        inst.set_proxy ConnectProxy.new(*ConnectProxy.parse_proxy_url)
      end

      inst
    end

    def self.new(uri : URI, tls : TLSContext = nil, ignore_env = false)
      yield new(uri, tls, ignore_env)
    end
  end

  def set_proxy(proxy : ConnectProxy = nil)
    socket = {% if compare_versions(Crystal::VERSION, "0.36.0") < 0 %} @socket {% else %} @io {% end %}
    return if socket && !socket.closed?

    {% if compare_versions(Crystal::VERSION, "0.36.0") < 0 %}
      begin
        @socket = proxy.open(@host, @port, @tls, **proxy_connection_options)
      rescue IO::Error
        @socket = nil
      end
    {% else %}
      begin
        @io = proxy.open(@host, @port, @tls, **proxy_connection_options)
      rescue IO::Error
        @io = nil
      end
    {% end %}
  end

  def proxy_connection_options
    {
      dns_timeout:     @dns_timeout,
      connect_timeout: @connect_timeout,
      read_timeout:    @read_timeout,
    }
  end
end

class ConnectProxy::HTTPClient < ::HTTP::Client
  include ConnectProxy::ProxyHTTP
end
