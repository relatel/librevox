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

        # The header filters to add on connecting. A value can be a lambda,
        # run on the listener when the connection starts, for a value not
        # known when the class loads.
        # @example
        #   filters "Event-Name" => "CHANNEL_PARK"
        #   filters "variable_app" => -> { App.current.name }
        def filters(filters)
          @subscribe_filters = filters
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
        filters.each do |header, values|
          values = instance_exec(&values) if values.is_a?(Proc)
          [*values].each do |value|
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
