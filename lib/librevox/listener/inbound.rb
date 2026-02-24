# frozen_string_literal: true

require 'io/endpoint/host_endpoint'
require 'librevox/listener/base'
require 'librevox/client'

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

      def initialize(connection = nil, args = {})
        super(connection)
        @auth = args[:auth] || "ClueCon"
      end

      def run_session
        Librevox.logger.info "Connected."

        command "auth #{@auth}"

        events = self.class.subscribe_events || ['ALL']
        command "event plain #{events.join(' ')}"

        filters = self.class.subscribe_filters || {}
        filters.each do |header, values|
          [*values].each do |value|
            command "filter #{header} #{value}"
          end
        end

        connection_completed
        sleep # keep session alive for event hooks and child tasks
      end

      def connection_completed
      end
    end
  end
end
