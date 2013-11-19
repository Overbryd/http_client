require "weakref"

class HttpClient

  class ConnectionCleaner

    attr_reader :min_idle

    def initialize
      @lock = Mutex.new
      @references = []
      @thread = Thread.new { work until @shutdown }
      @min_idle = 5
      @shutdown = false
    end

    def register(client)
      @lock.synchronize do
        @min_idle = [@min_idle, [1, client.config[:max_idle]].max].min
        @references.push(WeakRef.new(client))
      end
    end

    def work
      sleep min_idle
      @lock.synchronize do
        @references = @references.map do |client|
          begin
            client.cleanup_connections
            client
          rescue
            nil
          end
        end.compact
      end
    end

    def shutdown
      @shutdown = true
    end

  end

end
