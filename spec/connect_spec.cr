require "spec"
require "../src/connect-proxy"
require "./proxy_server"

describe ConnectProxy do
  it "connect to a website and get a response" do
    host = URI.parse("https://github.com/")
    response = ConnectProxy::HTTPClient.new(host) do |client|
      client.exec("GET", "/")
    end
    response.success?.should eq(true)
  end

  it "connect to a website and get a response using explicit proxy" do
    host = URI.parse("https://github.com/")
    client = ConnectProxy::HTTPClient.new(host, ignore_env: true)
    proxy = ConnectProxy.new("localhost", 22222)
    client.set_proxy(proxy)
    response = client.exec("GET", "/")
    response.success?.should eq(true)
    client.close
  end

  it "connect to a website with CRL checks disabled" do
    ConnectProxy.verify_tls = true
    ConnectProxy.disable_crl_checks = true

    host = URI.parse("https://github.com/")
    client = ConnectProxy::HTTPClient.new(host, ignore_env: true)
    proxy = ConnectProxy.new("localhost", 22222)
    client.set_proxy(proxy)
    response = client.exec("GET", "/")
    response.success?.should eq(true)
    client.close
  end

  it "connect to a website with TLS disabled" do
    ConnectProxy.verify_tls = false

    host = URI.parse("https://github.com/")
    client = ConnectProxy::HTTPClient.new(host, ignore_env: true)
    proxy = ConnectProxy.new("localhost", 22222)
    client.set_proxy(proxy)
    response = client.exec("GET", "/")
    response.success?.should eq(true)
    client.close
  end

  it "connect to a websocket using explicit proxy" do
    received = ""
    host = URI.parse("wss://echo.websocket.org/")
    proxy = ConnectProxy.new("localhost", 22222)

    ws = ConnectProxy::WebSocket.new(host, proxy: proxy)
    ws.on_message do |msg|
      puts msg
      received = msg
      ws.close
    end
    ws.send "test"
    ws.run

    received.should eq("test")
  end
end
