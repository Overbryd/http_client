# coding: utf-8

require "uri"
require "base64"
require "java"
%w[httpcore-4.3 httpclient-4.3.1 httpmime-4.3.1 commons-logging-1.1.3].each do |jar|
  require File.expand_path("../../vendor/#{jar}.jar", __FILE__)
end
require "http_client/response"
require "http_client/connection_cleaner"

class HttpClient
  import org.apache.http.impl.client.HttpClients
  import org.apache.http.impl.conn.BasicHttpClientConnectionManager
  import org.apache.http.impl.conn.PoolingHttpClientConnectionManager
  import org.apache.http.client.methods.HttpGet
  import org.apache.http.client.methods.HttpPost
  import org.apache.http.client.methods.HttpPut
  import org.apache.http.client.methods.HttpPatch
  import org.apache.http.client.methods.HttpDelete
  import org.apache.http.client.methods.HttpHead
  import org.apache.http.client.methods.HttpOptions
  import org.apache.http.client.config.RequestConfig
  import org.apache.http.entity.StringEntity
  import org.apache.http.client.entity.UrlEncodedFormEntity
  import org.apache.http.client.entity.GzipDecompressingEntity
  import org.apache.http.client.entity.DeflateDecompressingEntity
  import org.apache.http.message.BasicNameValuePair
  import org.apache.http.entity.ContentType
  import org.apache.http.util.EntityUtils
  import org.apache.http.HttpException
  import org.apache.http.conn.ConnectTimeoutException
  import java.io.IOException
  import java.net.SocketTimeoutException
  import java.util.concurrent.TimeUnit

  class Error < StandardError; end
  class Timeout < Error; end
  class IOError < Error; end

  @lock = Mutex.new
  def self.connection_cleaner
    @lock.synchronize { @connection_cleaner ||= ConnectionCleaner.new }
  end

  attr_reader :client, :config

  def initialize(config = {})
    @config = {
      :use_connection_pool => false,
      :max_connections => 20,
      :max_connections_per_route => nil,
      :max_retries => 0,
      :response_class => Response,
      :connection_request_timeout => 100,
      :connect_timeout => 1000,
      :socket_timeout => 2000,
      :max_idle => 5,
      :use_connection_cleaner => true,
      :default_request_options => {}
    }.merge(config)
    @request_config = create_request_config
    @connection_manager = create_connection_manager
    @client = HttpClients.create_minimal(@connection_manager)
  end

  def get(uri, options = {})
    uri = uri.sub(/\?.+$|$/, "?#{URI.encode_www_form(options[:params])}") if options[:params]
    request = create_request(HttpGet, uri, options)
    execute(request)
  end

  def post(uri, options = {})
    request = create_request(HttpPost, uri, options)
    entity = create_entity(options)
    request.set_entity(entity) if entity
    execute(request)
  end

  def put(uri, options = {})
    request = create_request(HttpPut, uri, options)
    entity = create_entity(options)
    request.set_entity(entity) if entity
    execute(request)
  end

  def patch(uri, options = {})
    request = create_request(HttpPatch, uri, options)
    entity = create_entity(options)
    request.set_entity(entity) if entity
    execute(request)
  end

  def delete(uri, options = {})
    request = create_request(HttpDelete, uri, options)
    execute(request)
  end

  def head(uri, options = {})
    request = create_request(HttpHead, uri, options)
    execute(request)
  end

  def options(uri, options = {})
    request = create_request(HttpOptions, uri, options)
    execute(request)
  end

  def pool_stats
    return unless @connection_manager.is_a?(PoolingHttpClientConnectionManager)
    total_stats = @connection_manager.total_stats
    Hash(
      :idle => total_stats.available,
      :in_use => total_stats.leased,
      :max => total_stats.max,
      :waiting => total_stats.pending
    )
  end

  def cleanup_connections(max_idle = config[:max_idle])
    @connection_manager.close_idle_connections(max_idle, TimeUnit::SECONDS)
  end

  def shutdown
    @connection_manager.shutdown
  end

private

  def execute(request)
    retries = config[:max_retries]
    begin
      closeable_response = client.execute(request)
      config[:response_class].new(closeable_response)
    rescue ConnectTimeoutException, SocketTimeoutException => e
      retry if (retries -= 1) > 0
      raise Timeout, "#{e.message}"
    rescue IOException => e
      retry if (retries -= 1) > 0
      raise IOError, "#{e.message}"
    rescue HttpException => e
      raise Error, "#{e.message}"
    ensure
      closeable_response.close if closeable_response
    end
  end

  def create_request(method_class, uri, options)
    request = method_class.new(uri)
    request.config = @request_config
    options = config[:default_request_options].merge(options)
    set_basic_auth(request, options[:basic_auth])
    options[:headers].each do |name, value|
      request.set_header(name.to_s.gsub("_", "-"), value)
    end if options[:headers]
    request
  end

  def set_basic_auth(request, basic_auth)
    return unless basic_auth.is_a?(Hash)
    credentials = "#{basic_auth[:user]}:#{basic_auth[:password]}"
    request.set_header("Authorization", "Basic #{Base64.strict_encode64(credentials)}")
  end

  def create_entity(options)
    if options[:body]
      StringEntity.new(options[:body], ContentType.create(options[:content_type] || "text/plain", "UTF-8"))
    elsif options[:json]
      json = options[:json].to_json
      StringEntity.new(json, ContentType.create("application/json", "UTF-8"))
    elsif options[:form]
      form = options[:form].map { |k, v| BasicNameValuePair.new(k.to_s, v.to_s) }
      UrlEncodedFormEntity.new(form, "UTF-8")
    else
      nil
    end
  end

  def create_request_config
    request_config = RequestConfig.custom
    request_config.set_stale_connection_check_enabled(true)
    request_config.set_connection_request_timeout(config[:connection_request_timeout])
    request_config.set_connect_timeout(config[:connect_timeout])
    request_config.set_socket_timeout(config[:socket_timeout])
    request_config.build
  end

  def create_connection_manager
    config[:use_connection_pool] ? create_pooling_connection_manager : BasicHttpClientConnectionManager.new
  end

  def create_pooling_connection_manager
    connection_manager = PoolingHttpClientConnectionManager.new
    connection_manager.max_total = config[:max_connections]
    connection_manager.default_max_per_route = config[:max_connections_per_route] || config[:max_connections]
    connection_manager.max_total = config[:max_connections]
    connection_manager.default_max_per_route = config[:max_connections_per_route] || config[:max_connections]
    self.class.connection_cleaner.register(self) if config[:use_connection_cleaner]
    connection_manager
  end

end
