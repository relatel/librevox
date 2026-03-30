# frozen_string_literal: true

require 'io/stream'
require 'io/endpoint/host_endpoint'

module Librevox
  class Server
    attr :endpoint

    def self.start(handler, host: "localhost", port: 8084, **options)
      endpoint = IO::Endpoint.tcp(host, port, **options)
      new(handler, endpoint).run
    end

    def initialize(handler, endpoint, **options)
      @handler = handler
      @endpoint = endpoint
      @options = options
    end

    def accept(socket, _address)
      stream = IO::Stream(socket)
      connection = Protocol::Connection.new(stream)
      listener = @handler.new(connection, @options)

      handle_session(connection, listener)
    rescue => e
      Librevox.logger.error "Session error: #{e.full_message}"
    end

    def run
      Async do |task|
        @endpoint.accept(&method(:accept))
        task.children.each(&:wait)
      end
    end

    private

    def handle_session(connection, listener)
      read_task = start_read_loop(connection, listener)

      listener.run_session

      read_task.wait
    rescue ConnectionError
      # Expected when the connection drops
    ensure
      read_task&.stop
      connection.close
    end

    def start_read_loop(connection, listener)
      Async do
        read_messages(connection, listener)
      ensure
        # Reject pending promises here (not in handle_session's ensure) so
        # that a connection drop unblocks listener.run_session via rejection.
        # handle_session's ensure can't run until run_session returns,
        # creating a deadlock if promises aren't rejected from this fiber.
        listener.connection_closed
      end
    end

    def read_messages(connection, listener)
      disconnecting = false
      hung_up = false

      connection.read_loop do |msg|
        if msg.disconnect_notice?
          disconnecting = true
        else
          listener.receive_data(msg)
          hung_up = true if msg.event? && msg.event == "CHANNEL_HANGUP_COMPLETE"
        end
        break if disconnecting && hung_up
      end
    end
  end
end
