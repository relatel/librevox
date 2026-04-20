# frozen_string_literal: true

require 'io/stream'
require 'io/endpoint/host_endpoint'

module Librevox
  class Server
    attr :endpoint

    def self.start(handler, host: "localhost", port: 8084, **options)
      endpoint = IO::Endpoint.tcp(host, port)
      new(handler, endpoint, **options).run
    end

    def initialize(handler, endpoint, **options)
      @handler = handler
      @endpoint = endpoint
      @options = options
    end

    def run
      @endpoint.accept do |socket, _address|
        start_session(socket)
      rescue => e
        Librevox.logger.error "Session error: #{e.full_message}"
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
