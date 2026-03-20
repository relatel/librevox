# frozen_string_literal: true

require 'io/stream'

module Librevox
  class Client
    def initialize(handler, endpoint, **options)
      @handler = handler
      @endpoint = endpoint
      @options = options
    end

    def connect(socket)
      stream = IO::Stream(socket)
      connection = Protocol::Connection.new(stream)
      listener = @handler.new(connection, @options)

      handle_session(connection, listener)
    end

    def run
      loop do
        @endpoint.connect(&method(:connect))
      rescue IOError, Errno::ECONNREFUSED, Errno::ECONNRESET, Librevox::ConnectionError => e
        Librevox.logger.error "Connection lost: #{e.message}. Reconnecting in 1s."
        sleep 1
      end
    end

    private

    def handle_session(connection, listener)
      read_task = start_read_loop(connection, listener)

      listener.run_session

      read_task.wait
    ensure
      read_task&.stop
      connection.close
    end

    def start_read_loop(connection, listener)
      Async do
        read_messages(connection, listener)
      ensure
        # Close queues here (not in handle_session's ensure) so that
        # a connection drop unblocks listener.run_session via nil dequeue.
        # handle_session's ensure can't run until run_session returns,
        # creating a deadlock if queues aren't closed from this fiber.
        listener.connection_closed
      end
    end

    def read_messages(connection, listener)
      connection.read_loop do |msg|
        listener.receive_message(msg)
      end
    end
  end
end
