# frozen_string_literal: true

require 'librevox/listener/base'
require 'librevox/applications'

module Librevox
  module Listener
    class Outbound < Base
      include Librevox::Applications

      def self.start(task, args = {})
        host = args[:host] || "localhost"
        port = args[:port] || 8084

        task.async do
          endpoint = IO::Endpoint.tcp(host, port)
          endpoint.accept do |socket|
            stream = IO::Stream(socket)

            listener = new(stream)
            listener.read_loop
          rescue => e
            Librevox.logger.error "Session error: #{e.message}"
          ensure
            stream&.close
          end
        end
      end

      def application(app, args = nil, params = {}, &block)
        parts = ["sendmsg", "call-command: execute", "execute-app-name: #{app}"]
        parts << "execute-app-arg: #{args}" if args && !args.empty?
        parts << "event-lock: true"

        send_data parts.join("\n") + "\n\n"

        @application_queue.push(proc {
          update_session do
            arg = params[:variable] ? variable(params[:variable]) : nil
            block.call(arg) if block
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
        @application_queue = []

        send_data "connect\n\n"
        send_data "myevents\n\n"
        @application_queue << proc {}
        send_data "linger\n\n"
        @application_queue << proc { session_initiated }
      end

      def handle_response
        if session.nil?
          @session = response.headers
        elsif response.event? && response.event == "CHANNEL_DATA"
          @session = response.content
        elsif response.command_reply? && !response.event?
          @application_queue.shift.call(response) if @application_queue.any?
        end

        super
      end

      def variable(name)
        session[:"variable_#{name}"]
      end

      def update_session(&block)
        api.command "uuid_dump", session[:unique_id], &block
      end
    end
  end
end
