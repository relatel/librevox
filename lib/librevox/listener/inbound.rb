# frozen_string_literal: true

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

      def self.start(barrier, host: "localhost", port: 8021, **options)
        endpoint = IO::Endpoint.tcp(host, port)
        Client.new(self, endpoint, **options).run(barrier)
      end

      def initialize(connection = nil, args = {})
        super(connection)
        @auth = args[:auth] || "ClueCon"
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
