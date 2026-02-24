# frozen_string_literal: true

require 'librevox/protocol/connection'

module Librevox
  class Client
    def initialize(handler, endpoint, **options)
      @handler = handler
      @endpoint = endpoint
      @options = options
    end

    attr :endpoint

    def connect(socket)
      stream = IO::Stream(socket)
      connection = Protocol::Connection.new(stream)

      listener = @handler.new(connection, @options)

      session_task = Async { listener.run_session }
      listener.read_loop
      session_task.wait
    ensure
      session_task&.stop
      connection.close
    end

    def run(barrier)
      barrier.async do
        loop do
          @endpoint.connect do |socket|
            connect(socket)
          end
        rescue IOError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
          Librevox.logger.error "Connection lost: #{e.message}. Reconnecting in 1s."
          sleep 1
        end
      end
    end
  end
end
