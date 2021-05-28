require "http"
require "socket"
require "base64"
require "openssl"

# Based on https://github.com/net-ssh/net-ssh/blob/master/lib/net/ssh/proxy/http.rb
class ConnectProxy
  PROXY_PASS = ENV["PROXY_PASSWORD"]?
  PROXY_USER = ENV["PROXY_USERNAME"]?

  # The hostname or IP address of the HTTP proxy.
  getter proxy_host : String

  # The port number of the proxy.
  getter proxy_port : Int32

  # The map of additional options that were given to the object at
  # initialization.
  getter tls : OpenSSL::SSL::Context::Client?

  # Simple check for relevant environment
  #
  def self.behind_proxy?
    !!(ENV["https_proxy"]? || ENV["http_proxy"]? || ENV["HTTP_PROXY"]? || ENV["HTTPS_PROXY"]?)
  end

  # Grab the host, port
  #
  def self.parse_proxy_url
    proxy_url = ENV["https_proxy"]? || ENV["http_proxy"]? || ENV["HTTP_PROXY"]? || ENV["HTTPS_PROXY"]

    uri = URI.parse(proxy_url)
    user = uri.user || PROXY_USER
    pass = uri.password || PROXY_PASS
    host = uri.host.not_nil!
    port = uri.port || URI.default_port(uri.scheme.not_nil!).not_nil!
    creds = {username: user, password: pass} if user && pass
    {host, port, creds}
  rescue
    raise "Missing/malformed $http_proxy or $https_proxy in environment"
  end

  # Create a new socket factory that tunnels via the given host and
  # port. The +options+ parameter is a hash of additional settings that
  # can be used to tweak this proxy connection. Specifically, the following
  # options are supported:
  #
  # * :user => the user name to use when authenticating to the proxy
  # * :password => the password to use when authenticating
  def initialize(host, port, auth : NamedTuple(username: String, password: String)? = nil)
    auth = {username: PROXY_USER.as(String), password: PROXY_PASS.as(String)} if !auth && PROXY_USER && PROXY_PASS
    @credentials = Base64.strict_encode("#{auth[:username]}:#{auth[:password]}").gsub(/\s/, "") if auth
    @proxy_host = host.gsub(/^http[s]?\:\/\//, "")
    @proxy_port = port
  end

  @credentials : String? = nil

  # Return a new socket connected to the given host and port via the
  # proxy that was requested when the socket factory was instantiated.
  def open(host, port, tls = nil, **connection_options)
    dns_timeout = connection_options.fetch(:dns_timeout, nil)
    connect_timeout = connection_options.fetch(:connect_timeout, nil)
    read_timeout = connection_options.fetch(:read_timeout, nil)

    socket = TCPSocket.new @proxy_host, @proxy_port, dns_timeout, connect_timeout
    socket.read_timeout = read_timeout if read_timeout
    socket.sync = true

    host = host.gsub(/^http[s]?\:\/\//, "")

    socket << "CONNECT #{host}:#{port} HTTP/1.0\r\n"
    socket << "Host: #{host}:#{port}\r\n"
    socket << "Proxy-Authorization: Basic #{@credentials}\r\n" if @credentials
    socket << "\r\n"
    resp = parse_response(socket)

    if resp[:code]? == 200
      if tls
        tls_socket = OpenSSL::SSL::Socket::Client.new(socket, context: tls, sync_close: true, hostname: host)
        socket = tls_socket
      end

      socket
    else
      socket.close
      raise IO::Error.new(resp.inspect)
    end
  end

  private def parse_response(socket)
    resp = {} of Symbol => Int32 | String | Hash(String, String)

    begin
      version, code, reason = socket.gets.as(String).chomp.split(/ /, 3)

      headers = {} of String => String

      while (line = socket.gets.as(String)) && (line.chomp != "")
        name, value = line.split(/:/, 2)
        headers[name.strip] = value.strip
      end

      resp[:version] = version
      resp[:code] = code.to_i
      resp[:reason] = reason
      resp[:headers] = headers
    rescue
    end

    resp
  end

  class HTTPClient < ::HTTP::Client
    def self.new(uri : URI, tls = nil, ignore_env = false)
      inst = super(uri, tls)
      if !ignore_env && ConnectProxy.behind_proxy?
        inst.set_proxy ConnectProxy.new(*ConnectProxy.parse_proxy_url)
      end

      inst
    end

    def self.new(uri : URI, tls = nil, ignore_env = false)
      yield new(uri, tls, ignore_env)
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
end
