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

      def application(app, args = nil, params = {})
        parts = ["call-command: execute", "execute-app-name: #{app}"]
        parts << "execute-app-arg: #{args}" if args && !args.empty?
        parts << "event-lock: true"

        response = sendmsg parts.join("\n")
        @session = response.content

        params[:variable] ? variable(params[:variable]) : nil
      end

      def sendmsg(msg)
        @command_mutex.acquire do
          send_data "sendmsg\n#{msg}\n\n"
          @reply_queue.dequeue          # command/reply ack
        end
        @app_complete_queue.dequeue     # CHANNEL_EXECUTE_COMPLETE
      end

      attr_accessor :session

      # Called when a new session is initiated.
      def session_initiated
      end

      def initialize(connection = nil)
        super(connection)
        @session = nil
        @app_complete_queue = Async::Queue.new
      end

      def run_session
        @session = command("connect").headers
        command "myevents"
        command "linger"
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
