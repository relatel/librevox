# frozen_string_literal: true

require 'io/endpoint/host_endpoint'

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

      def self.run(barrier, host: "localhost", port: 8021, **options)
        endpoint = IO::Endpoint.tcp(host, port)
        client = Client.new(self, endpoint, **options)
        barrier.async { client.run }
      end

      def initialize(connection, args = {})
        super(connection)
        @auth = args[:auth] || "ClueCon"
      end

      def run_session
        Librevox.logger.info "Connected."

        send_message "auth #{@auth}"

        events = self.class.subscribe_events || ['ALL']
        send_message "event plain #{events.join(' ')}"

        filters = self.class.subscribe_filters || {}
        filters.each do |header, values|
          [*values].each do |value|
            send_message "filter #{header} #{value}"
          end
        end

        connection_completed
      end

      def connection_completed
      end
    end
  end
end
