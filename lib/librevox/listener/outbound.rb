# frozen_string_literal: true

module Librevox
  module Listener
    class Outbound < Base
      include Librevox::Applications

      def self.start(...)
        Server.start(self, ...)
      end

      attr_accessor :session

      def initialize(connection, options = {})
        super(connection)
        @session = nil
        @disconnecting = false
        @hung_up = false
      end

      def run_session
        @session = send_message("connect").headers

        send_message "myevents"
        send_message "linger"

        session_initiated
      end

      # Called when a new session is initiated.
      def session_initiated
      end

      def application(app, args = nil, **params)
        variable_name = params.delete(:variable)

        response = execute_app(app, session[:unique_id], args, **params)

        @session = response.content

        variable(variable_name) if variable_name
      end

      def variable(name)
        session[:"variable_#{name}"]
      end

      # FreeSWITCH signals end-of-session with disconnect-notice + a final
      # CHANNEL_HANGUP_COMPLETE event. Either may arrive first. Once both
      # have been seen #session_complete? returns true and Session exits
      # the reader loop — after any in-flight event hooks have drained.
      def receive_data(response)
        if response.disconnect_notice?
          @disconnecting = true
        else
          @session = response.content if response.event? && response.event == "CHANNEL_DATA"
          super
          @hung_up = true if response.event? && response.event == "CHANNEL_HANGUP_COMPLETE"
        end
      end

      def session_complete?
        @disconnecting && @hung_up
      end
    end
  end
end
