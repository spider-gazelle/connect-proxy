require "spec"
require "../src/connect-proxy"
require "../src/connect-proxy/ext/*"
require "./proxy_server"

describe "proxy ext" do
  it "connect to a website and get a response" do
    host = URI.parse("https://github.com/")
    response = ::HTTP::Client.new(host) do |client|
      client.exec("GET", "/")
    end
    response.success?.should eq(true)
  end

  it "connect to a website and get a response using explicit proxy" do
    host = URI.parse("https://github.com/")
    expected_count = CONNECTION_COUNT[0] + 1
    client = ::HTTP::Client.new(host, ignore_env: true)
    proxy = ConnectProxy.new("localhost", 22222)
    client.set_proxy(proxy)
    response = client.exec("GET", "/")
    client.close
    response.success?.should eq(true)
    expected_count.should eq(CONNECTION_COUNT[0])
  end

  it "connect to a website with CRL checks disabled" do
    ConnectProxy.verify_tls = true
    ConnectProxy.disable_crl_checks = true

    host = URI.parse("https://github.com/")
    client = ::HTTP::Client.new(host, ignore_env: true)
    proxy = ConnectProxy.new("localhost", 22222)
    client.set_proxy(proxy)
    response = client.exec("GET", "/")
    client.close
    response.success?.should eq(true)
  end

  it "connect to a website with TLS disabled" do
    ConnectProxy.verify_tls = false

    host = URI.parse("https://github.com/")
    client = ::HTTP::Client.new(host, ignore_env: true)
    proxy = ConnectProxy.new("localhost", 22222)
    client.set_proxy(proxy)
    response = client.exec("GET", "/")
    client.close
    response.success?.should eq(true)
  end

  it "connect to a websocket using explicit proxy" do
    received = ""

    expected_count = CONNECTION_COUNT[0] + 1

    host = URI.parse("wss://ws.postman-echo.com/raw")
    proxy = ConnectProxy.new("localhost", 22222)

    ws = ::HTTP::WebSocket.new(host, proxy: proxy)
    ws.on_message do |msg|
      puts msg
      received = msg
      ws.close
    end
    ws.send "test"
    ws.run

    received.should eq("test")
    expected_count.should eq(CONNECTION_COUNT[0])
  end
end
