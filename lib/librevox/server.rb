# frozen_string_literal: true

require 'librevox/protocol/connection'

module Librevox
  class Server
    def initialize(handler, endpoint)
      @handler = handler
      @endpoint = endpoint
    end

    attr :endpoint

    def accept(socket)
      stream = IO::Stream(socket)
      connection = Protocol::Connection.new(stream)

      listener = @handler.new(connection)
      listener.read_loop
    rescue => e
      Librevox.logger.error "Session error: #{e.message}"
    ensure
      connection&.close
    end

    def run(barrier)
      barrier.async do
        @endpoint.accept(&method(:accept))
      end
    end
  end
end
