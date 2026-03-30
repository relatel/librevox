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

      def receive_data(response)
        if response.event? && response.event == "CHANNEL_DATA"
          @session = response.content
        end

        super
      end
    end
  end
end
