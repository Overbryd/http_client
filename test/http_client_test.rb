# coding: utf-8

require "rubygems"
gem "minitest"
require "minitest/pride"
require "minitest/autorun"

require "json"
require_relative "../lib/http_client"

module Minitest
  class Test
    def self.test(name, &block)
      define_method("test_#{name.gsub(" ", " ")}", &block)
    end
  end
end

class HttpClientTest < Minitest::Test
  attr_reader :client

  def setup
    @client = HttpClient.new
  end

  test "GET request with params in uri" do
    response = client.get("http://httpbin.org/get?foo=bar")
    assert_equal Hash("foo" => "bar"), response.json_body["args"]
  end

  test "GET request with params in options" do
    response = client.get("http://httpbin.org/get", :params => { :foo => "bar" })
    assert_equal Hash("foo" => "bar"), response.json_body["args"]
  end

  test "GET request with headers" do
    response = client.get("http://httpbin.org/get", :headers => { "X-Send-By" => "foobar" })
    assert_equal "foobar", response.json_body["headers"]["X-Send-By"]
  end

  test "GET request with gzipped response" do
    response = client.get("http://httpbin.org/gzip")
    assert_equal true, response.json_body["gzipped"]
    assert_nil response.json_body["headers"]["Content-Encoding"]
  end

  test "POST request with string body" do
    response = client.post("http://httpbin.org/post", :body => "foo:bar|zig:zag")
    assert_equal "text/plain; charset=UTF-8", response.json_body["headers"]["Content-Type"]
    assert_equal "foo:bar|zig:zag", response.json_body["data"]
  end

  test "POST request with form data" do
    response = client.post("http://httpbin.org/post", :form => { :foo => "bar"})
    assert_equal "application/x-www-form-urlencoded; charset=UTF-8", response.json_body["headers"]["Content-Type"]
    assert_equal Hash("foo" => "bar"), response.json_body["form"]
  end

  test "POST request with json data" do
    response = client.post("http://httpbin.org/post", :json => { :foo => "bar"})
    assert_equal "application/json; charset=UTF-8", response.json_body["headers"]["Content-Type"]
    assert_equal Hash("foo" => "bar"), response.json_body["json"]
  end

  test "POST request Content-Type in header takes precedence" do
    response = client.post("http://httpbin.org/post",
      :json => { "foo" => "bar" },
      :headers => { "Content-Type" => "application/x-json" }
    )
    assert_equal "application/x-json", response.json_body["headers"]["Content-Type"]
  end
end

# # Content-Type precedence
# 
# client.post("http://httpbin.org/post",
#   :headers => {
#     :content_type => "application/xml"
#   },
#   :body => %Q'<?xml version="1.0" encoding="utf-8"?><foo>bar</foo>'
# )
# client.post("http://httpbin.org/post",
#   :content_type => "application/xml+foo",
#   :headers => {
#     :content_type => "application/xml"
#   },
#   :body => %Q'<?xml version="1.0" encoding="utf-8"?><foo>bar</foo>'
# )
# client.post("http://httpbin.org/post",
#   :content_type => "application/xml+foo",
#   :headers => {
#     :content_type => "application/xml"
#   },
#   :json => %Q'{"foo":"bar"}'
# )
