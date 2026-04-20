# frozen_string_literal: true

require 'io/stream'
require 'io/endpoint/host_endpoint'

module Librevox
  class Client
    def self.start(handler, host: "localhost", port: 8021, **options)
      endpoint = IO::Endpoint.tcp(host, port)
      new(handler, endpoint, **options).run
    end

    def initialize(handler, endpoint, **options)
      @handler = handler
      @endpoint = endpoint
      @options = options
    end

    def run
      loop do
        @endpoint.connect { |socket| start_session(socket) }
      rescue IOError, Errno::ECONNREFUSED, Errno::ECONNRESET, ConnectionError, ResponseError => e
        Librevox.logger.error "Connection lost: #{e.message}. Reconnecting in 1s."
        sleep 1
      end
    end

    private

    def start_session(socket)
      connection = Protocol::Connection.new(IO::Stream(socket))
      listener = @handler.new(connection, @options)
      Session.new(connection, listener).run
    end
  end
end
