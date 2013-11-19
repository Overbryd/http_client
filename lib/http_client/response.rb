class HttpClient

  class Response
    attr_reader :status, :body, :headers

    def initialize(closeable_response)
      @status = closeable_response.status_line.status_code
      @headers = closeable_response.all_headers.inject({}) do |headers, header|
        headers[header.name] = header.value
        headers
      end
      @body = read_body(closeable_response)
    end

    def success?
      status >= 200 && status <= 206
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

end
