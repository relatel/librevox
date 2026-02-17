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
        parts = ["sendmsg", "call-command: execute", "execute-app-name: #{app}"]
        parts << "execute-app-arg: #{args}" if args && !args.empty?
        parts << "event-lock: true"

        send_data parts.join("\n") + "\n\n"

        @application_queue.push(proc {
          @session = response.content

          if block
            arg = params[:variable] ? variable(params[:variable]) : nil
            block.call(arg)
          end
        })
      end

      # This should probably be in Application#sendmsg instead.
      def sendmsg(msg)
        send_data "sendmsg\n%s" % msg
      end

      attr_accessor :session

      # Called when a new session is initiated.
      def session_initiated
      end

      def initialize(connection = nil)
        super(connection)
        @session = nil
        @reply_queue = []
        @application_queue = []

        send_data "connect\n\n"
        send_command "myevents\n\n"
        send_command("linger\n\n") { session_initiated }
      end

      def handle_response
        if session.nil?
          @session = response.headers
        elsif response.event? && response.event == "CHANNEL_DATA"
          @session = response.content
        elsif response.event? && response.event == "CHANNEL_EXECUTE_COMPLETE"
          @application_queue.shift.call(response) if @application_queue.any?
        elsif response.command_reply? && !response.event?
          @reply_queue.shift.call(response) if @reply_queue.any?
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

      private

      def send_command(data, &block)
        send_data data
        @reply_queue << (block || proc {})
      end
    end
  end
end
