# coding: utf-8

require "uri"
require "java"
%w[httpcore-4.3 httpclient-4.3.1 httpmime-4.3.1 commons-logging-1.1.3].each do |jar|
  require File.expand_path("../../vendor/#{jar}.jar", __FILE__)
end

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

  class Response
    attr_reader :status, :body, :headers

    def initialize(closeable_response)
      @status = closeable_response.status_line.status_code
      @headers = closeable_response.get_all_headers.inject({}) do |headers, header|
        headers[header.name] = header.value
        headers
      end
      @body = read_body(closeable_response)
    end

    def success?
      @status >= 200 && @status <= 206
    end

    def json_body(options = {})
      @json_body ||= JSON.parse(body, options)
    end

  private

    def read_body(closeable_response)
      return "" unless entity = closeable_response.entity
      return "" unless entity.is_chunked? || entity.content_length > 0
      if content_encoding = entity.content_encoding
        entity = case content_encoding.value
          when "gzip", "x-gzip" then
            GzipDecompressingEntity.new(entity)
          when "deflate" then
            DeflateDecompressingEntity.new(entity)
          else
            entity
        end
      end
      EntityUtils.to_string(entity, "UTF-8")
    end
  end

  attr_reader :client, :max_retries, :response_class, :default_request_options

  # Initialize a HttpClient
  #
  # options - The Hash options used to fine tune the client (optional):
  #             :use_connection_pool        - Set this to true if you intend to use a capped connection pool (default: false).
  #             :max_connections            - The maximum number of connections a pool will open (optional, default: 20, only when using a connection pool).
  #             :max_connections_per_route  - The maximum number of connections that can be made to one server (optional, only when using a connection pool).
  #             :max_retries                - The maximum number of retries the client will attempt on retryable exceptions (default: 0).
  #             :response_class             - Use a different class to handle responses (default: HttpClient::Response).
  #             :connection_request_timeout - Max wait time in milliseconds for a request when the connection pool has no free connection (default: 100, only when using a connection pool).
  #             :connect_timeout            - Max wait time in milliseconds for establishing a connection to a server (default: 100).
  #             :socket_timeout             - Max wait time in milliseconds for receiving a response from the server (default: 2000).
  #             :socket_timeout             - Max wait time in milliseconds for receiving a response from the server (default: 2000).
  #             :default_request_options    - Default options (i.e. headers) that apply to each request. (default: {}, see HttpClient#get|post|...).
  #
  #
  def initialize(options = {})
    options = {
      :use_connection_pool => false,
      :max_connections => 20,
      :max_connections_per_route => nil,
      :max_retries => 0,
      :response_class => Response,
      :connection_request_timeout => 100,
      :connect_timeout => 1000,
      :socket_timeout => 2000,
      :default_request_options => {}
    }.merge(options)
    @request_config = create_request_config(options)
    @connection_manager = create_connection_manager(options)
    @client = HttpClients.create_minimal(@connection_manager)
    @max_retries = options[:max_retries]
    @response_class = options[:response_class]
    @default_request_options = options[:default_request_options]
  end

  # Execute a GET request
  #
  # uri - The full URI of the request. May include a query string, but note that a query string here will be overriden by options.
  # options - The Hash options used to set headers and the like (optional):
  #           :headers - A Hash of HTTP headers to send (default: {}).
  #           :params - A Hash of params that will be turned into a query string using URI::encode_www_form. Overrides any query string in the URI (default: {}).
  #
  # Examples
  #
  #   client.get("https://www.google.com/robots.txt")
  #   # => #<HttpClient::Response0xdeadbeef ...>
  #
  # Returns an instance of HttpClient::Response.
  # Raises HttpClient::Timeout if any timeout occurs, retryable.
  # Raises HttpClient::IOError if any IO error occurs, retryable.
  # Raises HttpClient::Error if any HTTP protocol error occurs.
  def get(uri, options = {})
    uri = uri.sub(/\?.+$|$/, "?#{URI.encode_www_form(options[:params])}") if options[:params]
    request = create_request(HttpGet, uri, options)
    execute(request)
  end

  # Execute a POST request
  #
  # uri - The full URI of the request.
  # options - The Hash options used to set headers and the like (optional):
  #           :headers - A Hash of HTTP headers to send, note that a Content-Type header overrides the Content-Type set by :form or :json (default: {}).
  #           :body - A string that will be sent as the request body (optional).
  #           :form - A Hash of params that will be turned into a URI encoded body, sets Content-Type header to "application/x-www-form-urlencoded; charset=UTF-8" (optional).
  #           :json - A Hash of data that will be turned into a JSON body using #to_json, sets Content-Type header to "application/json; charset=UTF-8" (optional).
  #
  # Examples
  #
  #   client.post("http://www.httpbin.org/post", :form => { :foo => "bar" })
  #   # => #<HttpClient::Response0xdeadbeef ...>
  #
  # Returns an instance of HttpClient::Response.
  # Raises HttpClient::Timeout if any timeout occurs, retryable.
  # Raises HttpClient::IOError if any IO error occurs, retryable.
  # Raises HttpClient::Error if any HTTP protocol error occurs.
  def post(uri, options = {})
    request = create_request(HttpPost, uri, options)
    entity = create_entity(options)
    request.set_entity(entity) if entity
    execute(request)
  end

  # Execute a PUT request
  #
  # uri - The full URI of the request.
  # options - The Hash options used to set headers and the like (optional):
  #           :headers - A Hash of HTTP headers to send, note that a Content-Type header overrides the Content-Type set by :form or :json (default: {}).
  #           :body - A string that will be sent as the request body (optional).
  #           :form - A Hash of params that will be turned into a URI encoded body, sets Content-Type header to "application/x-www-form-urlencoded; charset=UTF-8" (optional).
  #           :json - A Hash of data that will be turned into a JSON body using #to_json, sets Content-Type header to "application/json; charset=UTF-8" (optional).
  #
  # Examples
  #
  #   client.put("http://www.httpbin.org/put", :json => { :foo => "bar" })
  #   # => #<HttpClient::Response0xdeadbeef ...>
  #
  # Returns an instance of HttpClient::Response.
  # Raises HttpClient::Timeout if any timeout occurs, retryable.
  # Raises HttpClient::IOError if any IO error occurs, retryable.
  # Raises HttpClient::Error if any HTTP protocol error occurs.
  def put(uri, options = {})
    request = create_request(HttpPut, uri, options)
    entity = create_entity(options)
    request.set_entity(entity) if entity
    execute(request)
  end

  # Execute a PATCH request
  #
  # uri - The full URI of the request.
  # options - The Hash options used to set headers and the like (optional):
  #           :headers - A Hash of HTTP headers to send, note that a Content-Type header overrides the Content-Type set by :form or :json (default: {}).
  #           :body - A string that will be sent as the request body (optional).
  #           :form - A Hash of params that will be turned into a URI encoded body, sets Content-Type header to "application/x-www-form-urlencoded; charset=UTF-8" (optional).
  #           :json - A Hash of data that will be turned into a JSON body using #to_json, sets Content-Type header to "application/json; charset=UTF-8" (optional).
  #
  # Examples
  #
  #   client.patch("http://www.httpbin.org/patch", :body => "foobar")
  #   # => #<HttpClient::Response0xdeadbeef ...>
  #
  # Returns an instance of HttpClient::Response.
  # Raises HttpClient::Timeout if any timeout occurs, retryable.
  # Raises HttpClient::IOError if any IO error occurs, retryable.
  # Raises HttpClient::Error if any HTTP protocol error occurs.
  def patch(uri, options = {})
    request = create_request(HttpPatch, uri, options)
    entity = create_entity(options)
    request.set_entity(entity) if entity
    execute(request)
  end

  # Execute a DELETE request
  #
  # uri - The full URI of the request.
  # options - The Hash options used to set headers and the like (optional):
  #           :headers - A Hash of HTTP headers to send (default: {}).
  #
  # Examples
  #
  #   client.delete("http://www.httpbin.org/delete", :body => "foobar")
  #   # => #<HttpClient::Response0xdeadbeef ...>
  #
  # Returns an instance of HttpClient::Response.
  # Raises HttpClient::Timeout if any timeout occurs, retryable.
  # Raises HttpClient::IOError if any IO error occurs, retryable.
  # Raises HttpClient::Error if any HTTP protocol error occurs.
  def delete(uri, options = {})
    request = create_request(HttpDelete, uri, options)
    execute(request)
  end

  # Execute a HEAD request
  #
  # uri - The full URI of the request.
  # options - The Hash options used to set headers and the like (optional):
  #           :headers - A Hash of HTTP headers to send (default: {}).
  #
  # Examples
  #
  #   client.head("http://www.httpbin.org/delete", :headers => { "X-Auth": "deadbeef42" })
  #   # => #<HttpClient::Response0xdeadbeef ...>
  #
  # Returns an instance of HttpClient::Response.
  # Raises HttpClient::Timeout if any timeout occurs, retryable.
  # Raises HttpClient::IOError if any IO error occurs, retryable.
  # Raises HttpClient::Error if any HTTP protocol error occurs.
  def head(uri, options = {})
    request = create_request(HttpHead, uri, options)
    execute(request)
  end

  # Execute a OPTIONS request
  #
  # uri - The full URI of the request.
  # options - The Hash options used to set headers and the like (optional):
  #           :headers - A Hash of HTTP headers to send (default: {}).
  #
  # Examples
  #
  #   client.head("http://www.httpbin.org/delete")
  #   # => #<HttpClient::Response0xdeadbeef ...>
  #
  # Returns an instance of HttpClient::Response.
  # Raises HttpClient::Timeout if any timeout occurs, retryable.
  # Raises HttpClient::IOError if any IO error occurs, retryable.
  # Raises HttpClient::Error if any HTTP protocol error occurs.
  def options(uri, options = {})
    request = create_request(HttpOptions, uri, options)
    execute(request)
  end

  # Reads stats from the connection pool (only available when using a connection pool).
  #
  # Examples
  #
  #   client.pool_stats
  #   # => {:idle => 0, :in_use => 2, :max => 3, :waiting => 0}
  #
  # Returns a Hash of numbers.
  # Raises RuntimeError if the client is not configured to use a connection pool.
  def pool_stats
    raise "#{self.class.name}#pool_stats is supported only when using a connection pool" unless @connection_manager.is_a?(PoolingHttpClientConnectionManager)
    total_stats = @connection_manager.total_stats
    Hash(
      :idle => total_stats.available,
      :in_use => total_stats.leased,
      :max => total_stats.max,
      :waiting => total_stats.pending
    )
  end

  # Closes idle and expired connections from the pool (only available when using a connection pool).
  # You may want to call this method on a monitor thread when having long time idling Keep-Alive connections.
  # This helps against errors when a server closes Keep-Alive connections unexpectedly or earlier than advertised.
  # And since not all servers send the non-standardized timeout=seconds attribute with a Keep-Alive response,
  # we may not know how long a connection can be kept open idling.
  #
  # max_idle - The maximum time in seconds a connection has been idle.
  #
  # Examples
  #
  #   client.cleanup_connections(3)
  #
  # Returns nothing.
  def cleanup_connections(max_idle = 5)
    @connection_manager.close_idle_connections(max_idle, TimeUnit::SECONDS)
  end

  # Shuts down the connection manager and releases all obtained resources.
  # This method is thread safe but you should keep in mind that it may cause trouble
  # for threads that are in the middle of request execution.
  #
  # Returns nothing.
  def shutdown
    @connection_manager.shutdown
  end

private

  def execute(request)
    retries = max_retries
    begin
      closeable_response = client.execute(request)
      response_class.new(closeable_response)
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
    options = default_request_options.merge(options)
    options[:headers].each do |name, value|
      request.set_header(name.to_s.gsub("_", "-"), value)
    end if options[:headers]
    request
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

  def create_request_config(options)
    config = RequestConfig.custom
    config.set_stale_connection_check_enabled(true)
    config.set_connection_request_timeout(options[:connection_request_timeout])
    config.set_connect_timeout(options[:connect_timeout])
    config.set_socket_timeout(options[:socket_timeout])
    config.build
  end

  def create_connection_manager(options)
    options[:use_connection_pool] ? create_pooling_connection_manager(options) : BasicHttpClientConnectionManager.new
  end

  def create_pooling_connection_manager(options)
    connection_manager = PoolingHttpClientConnectionManager.new
    connection_manager.max_total = options[:max_connections]
    connection_manager.default_max_per_route = options[:max_connections_per_route] || options[:max_connections]
  end

end
