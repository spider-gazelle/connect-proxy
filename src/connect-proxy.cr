require "http"
require "socket"
require "base64"
require "openssl"

# see: https://github.com/crystal-lang/crystal/pull/10756
{% if compare_versions(Crystal::VERSION, "1.0.1") < 0 %}
  abstract class OpenSSL::SSL::Context
    def add_x509_verify_flags(flags : OpenSSL::SSL::X509VerifyFlags)
      param = LibSSL.ssl_ctx_get0_param(@handle)
      ret = LibCrypto.x509_verify_param_set_flags(param, flags)
      raise OpenSSL::Error.new("X509_VERIFY_PARAM_set_flags)") unless ret == 1
    end
  end
{% end %}

# Based on https://github.com/net-ssh/net-ssh/blob/master/lib/net/ssh/proxy/http.rb
class ConnectProxy
  class_property username : String? = ENV["PROXY_USERNAME"]?
  class_property password : String? = ENV["PROXY_PASSWORD"]?
  class_property proxy_uri : String? = ENV["https_proxy"]? || ENV["http_proxy"]? || ENV["HTTPS_PROXY"]? || ENV["HTTP_PROXY"]?
  class_property verify_tls : Bool = ENV["PROXY_VERIFY_TLS"]? != "false"
  class_property disable_crl_checks : Bool = ENV["PROXY_DISABLE_CRL_CHECKS"]? == "true"

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
    !!proxy_uri
  end

  # Grab the host, port
  #
  def self.parse_proxy_url
    proxy_url = proxy_uri.not_nil!

    uri = URI.parse(proxy_url)
    user = uri.user || username
    pass = uri.password || password
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
    auth = {username: self.class.username.as(String), password: self.class.password.as(String)} if !auth && self.class.username && self.class.password
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
        if tls.is_a?(Bool) # true, but we want to get rid of the union
          context = OpenSSL::SSL::Context::Client.new
        else
          context = tls
        end

        if !ConnectProxy.verify_tls
          context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
        elsif ConnectProxy.disable_crl_checks
          begin
            context.add_x509_verify_flags OpenSSL::SSL::X509VerifyFlags::IGNORE_CRITICAL
          rescue NotImplementedError
          end
        end

        socket = OpenSSL::SSL::Socket::Client.new(socket, context: context, sync_close: true, hostname: host)
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
    rescue error
      raise IO::Error.new("parsing proxy initialization", cause: error)
    end

    resp
  end
end

require "./connect-proxy/*"
