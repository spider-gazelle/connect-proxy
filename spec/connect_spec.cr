require "spec"
require "../src/connect-proxy"

describe ConnectProxy do
  it "connect to a website and get a response" do
    host = URI.parse("https://www.overclockers.com.au")
    response = ConnectProxy::HTTPClient.new(host) do |client|
      client.exec("GET", "/")
    end
    response.success?.should eq(true)
  end

  it "connect to a website and get a response using explicit proxy" do
    host = URI.parse("https://www.overclockers.com.au")
    client = ConnectProxy::HTTPClient.new(host)
    proxy = ConnectProxy.new("134.209.219.234", 80)
    client.set_proxy(proxy)
    response = client.exec("GET", "/")
    response.success?.should eq(true)
  end
end
