# frozen_string_literal: true

module Librevox
  module Listener
    class Inbound < Base
      class << self
        attr_reader :subscribe_events
        attr_reader :subscribe_filters

        def events(events)
          @subscribe_events = events
        end

        # The header filters to add on connecting, as a hash, or a block that
        # returns one when the connection starts (for values not known when
        # the class loads).
        # @example
        #   filters "Event-Name" => "CHANNEL_PARK"
        #   filters { { "variable_app" => App.current.name } }
        def filters(filters = nil, &block)
          @subscribe_filters = block || filters
        end
      end

      def self.start(...)
        Client.start(self, ...)
      end

      def initialize(connection, auth: "ClueCon", **)
        super(connection)

        @auth = auth
      end

      def run_session
        Librevox.logger.info "Connected."

        send_message "auth #{@auth}"

        # Filters first: FreeSWITCH sends every subscribed event while a
        # connection has no filters, so subscribing first would let the whole
        # node's events through until the filters land.
        filters = self.class.subscribe_filters || {}
        filters = instance_exec(&filters) if filters.is_a?(Proc)
        filters.each do |header, values|
          Array(values).each do |value|
            send_message "filter #{header} #{value}"
          end
        end

        events = self.class.subscribe_events || ['ALL']

        send_message "event plain #{events.join(' ')}"

        connection_completed
      end

      def connection_completed
      end
    end
  end
end
