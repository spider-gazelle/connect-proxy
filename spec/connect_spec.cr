require "spec"
require "../src/connect-proxy"

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
    client = ConnectProxy::HTTPClient.new(host)
    proxy = ConnectProxy.new("51.38.71.101", 8080)
    client.set_proxy(proxy)
    response = client.exec("GET", "/")
    response.success?.should eq(true)
  end
end
