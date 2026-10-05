# frozen_string_literal: true

require 'async'
require 'io/stream'
require 'io/endpoint/host_endpoint'

module Librevox
  class Server
    attr_reader :endpoint

    def self.start(handler, host: "localhost", port: 8084, **options)
      endpoint = IO::Endpoint.tcp(host, port)
      new(handler, endpoint, **options).run
    end

    def initialize(handler, endpoint, **options)
      @handler = handler
      @endpoint = endpoint
      @options = options
    end

    # Librevox.start runs listeners inside a reactor. Calling MyOutbound.start
    # directly has none, so Sync starts one; inside a reactor it just runs
    # the block.
    def run
      Sync do
        @endpoint.accept(&method(:accept))
      end
    end

    private

    def accept(socket, _address)
      connection = Protocol::Connection.new(IO::Stream(socket))
      listener = @handler.new(connection, **@options)
      Session.new(connection, listener).run
    rescue => e
      Librevox.logger.error "Session error: #{e.message}"
    end
  end
end
