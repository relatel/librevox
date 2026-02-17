# frozen_string_literal: true

require 'librevox/listener/base'
require 'librevox/applications'
require 'librevox/server'

module Librevox
  module Listener
    class Outbound < Base
      include Librevox::Applications

      def self.start(barrier, host: "localhost", port: 8084)
        endpoint = IO::Endpoint.tcp(host, port)
        Server.new(self, endpoint).run(barrier)
      end

      def application(app, args = nil, params = {}, &block)
        parts = ["call-command: execute", "execute-app-name: #{app}"]
        parts << "execute-app-arg: #{args}" if args && !args.empty?
        parts << "event-lock: true"

        sendmsg parts.join("\n") do
          @session = response.content

          if block
            arg = params[:variable] ? variable(params[:variable]) : nil
            block.call(arg)
          end
        end
      end

      def sendmsg(msg, &block)
        send_data "sendmsg\n#{msg}\n\n"

        @command_queue.push(proc {})
        @application_queue.push(block || proc {})
      end

      attr_accessor :session

      # Called when a new session is initiated.
      def session_initiated
      end

      def initialize(connection = nil)
        super(connection)
        @session = nil
        @application_queue = []

        command("connect") { @session = response.headers }
        command "myevents"
        command("linger") { session_initiated }
      end

      def handle_response
        if response.event? && response.event == "CHANNEL_DATA"
          @session = response.content
        elsif response.event? && response.event == "CHANNEL_EXECUTE_COMPLETE"
          @application_queue.shift.call(response) if @application_queue.any?
        end

        super
      end

      def variable(name)
        session[:"variable_#{name}"]
      end

      def update_session(&block)
        api.command "uuid_dump", session[:unique_id] do |response|
          @session = response.content
          block.call if block
        end
      end
    end
  end
end
