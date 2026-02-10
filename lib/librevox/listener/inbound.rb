# frozen_string_literal: true

require 'librevox/listener/base'

module Librevox
  module Listener
    class Inbound < Base
      class << self
        attr_reader :subscribe_events
        attr_reader :subscribe_filters

        def events(events)
          @subscribe_events = events
        end

        def filters(filters)
          @subscribe_filters = filters
        end
      end

      def self.start(task, args = {})
        host = args[:host] || "localhost"
        port = args[:port] || 8021

        task.async do
          loop do
            endpoint = Async::IO::Endpoint.tcp(host, port)
            stream = Async::IO::Stream.new(endpoint.connect)
            connection = Librevox::Connection.new(stream)

            listener = new(connection, args)
            listener.connection_completed
            listener.read_loop
          rescue IOError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
            Librevox.logger.error "Connection lost: #{e.message}. Reconnecting in 1s."
            sleep 1
          ensure
            stream&.close
          end
        end
      end

      def initialize(connection = nil, args = {})
        super(connection)
        @auth = args[:auth] || "ClueCon"
        @host, @port = args.values_at(:host, :port)
      end

      def connection_completed
        Librevox.logger.info "Connected."
        super

        send_data "auth #{@auth}\n\n"

        events = self.class.subscribe_events || ['ALL']
        send_data "event plain #{events.join(' ')}\n\n"

        filters = self.class.subscribe_filters || {}
        filters.each do |header, values|
          [*values].each do |value|
            send_data "filter #{header} #{value}\n\n"
          end
        end
      end
    end
  end
end
