# frozen_string_literal: true

require 'io/endpoint/host_endpoint'

module Librevox
  module Listener
    class Outbound < Base
      include Librevox::Applications

      def self.run(barrier, host: "localhost", port: 8084, **options)
        endpoint = IO::Endpoint.tcp(host, port, **options)
        server = Server.new(self, endpoint)
        barrier.async { server.run }
      end

      def application(app, args = nil, **params)
        variable_name = params.delete(:variable)

        headers = params
          .merge(
            event_lock:        true,
            call_command:      "execute",
            execute_app_name:  app,
            execute_app_arg:   args,
          )
          .map { |key, value| "#{key.to_s.tr('_', '-')}: #{value}" }

        send_message "sendmsg\n#{headers.join("\n")}"

        response = @app_complete_queue.dequeue
        @session = response.content

        variable(variable_name) if variable_name
      end

      attr_accessor :session

      # Called when a new session is initiated.
      def session_initiated
      end

      def initialize(connection)
        super(connection)
        @session = nil
        @app_complete_queue = Async::Queue.new
      end

      def run_session
        @session = send_message("connect").headers
        send_message "myevents"
        send_message "linger"
        session_initiated
        sleep # keep session alive for event hooks and child tasks
      end

      def handle_response
        if response.event? && response.event == "CHANNEL_DATA"
          @session = response.content
        elsif response.event? && response.event == "CHANNEL_EXECUTE_COMPLETE"
          @app_complete_queue.push(response)
        end

        super
      end

      def variable(name)
        session[:"variable_#{name}"]
      end

      def update_session
        response = api.command "uuid_dump", session[:unique_id]
        @session = response.content
      end
    end
  end
end
