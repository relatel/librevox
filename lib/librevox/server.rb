# frozen_string_literal: true

require 'io/stream'

module Librevox
  class Server
    def initialize(handler, endpoint)
      @handler = handler
      @endpoint = endpoint
    end

    attr :endpoint

    def accept(socket, _address)
      stream = IO::Stream(socket)
      connection = Protocol::Connection.new(stream)

      listener = @handler.new(connection)

      session_task = Async { listener.run_session }
      connection.read_loop { |msg| listener.receive_message(msg) }
    rescue => e
      Librevox.logger.error "Session error: #{e.full_message}"
    ensure
      session_task&.stop
      connection&.close
    end

    def run
      Async do |task|
        @endpoint.accept(&method(:accept))
        task.children.each(&:wait)
      end
    end
  end
end
