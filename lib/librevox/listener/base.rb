# frozen_string_literal: true

require 'async/barrier'
require 'securerandom'

module Librevox
  module Listener
    class Base
      class << self
        def hooks
          @hooks ||= Hash.new {|hash, key| hash[key] = []}
        end

        def event(event, &block)
          hooks[event] << block
        end
      end

      def initialize(connection)
        @connection = connection
        @reply_promises = []
        @app_promises = {}
        @event_barrier = Async::Barrier.new
      end

      # Exposes an instance of {CommandDelegate}, which includes {Librevox::Commands}.
      # @example
      #   api.status
      #   api.fsctl :pause
      #   api.uuid_park "592567a2-1be4-11df-a036-19bfdab2092f"
      # @see Librevox::Commands
      def api
        @command_delegate ||= CommandDelegate.new(self)
      end

      def send_message(msg)
        promise = Async::Promise.new

        @reply_promises << promise

        @connection.send_data(msg)

        reply = promise.wait
        raise ResponseError, reply.headers[:reply_text] if reply.error?

        reply
      end

      def execute_app(app, uuid, args = nil, **params)
        event_uuid = SecureRandom.uuid

        headers = {
            event_lock:        true,
            call_command:      "execute",
            execute_app_name:  app,
            execute_app_arg:   args,
            event_uuid:        event_uuid,
          }
          .merge(params)
          .map { |key, value| "#{key.to_s.tr('_', '-')}: #{value}" }

        promise = Async::Promise.new
        @app_promises[event_uuid] = promise

        send_message "sendmsg #{uuid}\n#{headers.join("\n")}"

        promise.wait
      end

      def receive_data(response)
        if response.reply?
          @reply_promises.shift&.resolve(response)
          return
        end

        if response.event?
          if response.event == "CHANNEL_EXECUTE_COMPLETE"
            app_uuid = response.content[:application_uuid]
            @app_promises.delete(app_uuid)&.resolve(response)
          end

          @event_barrier.async do
            on_event(response)
            invoke_event_hooks(response)
          end
        end
      end

      def connection_closed
        error = ConnectionError.new("Connection closed")

        @reply_promises.each { |p| p.reject(error) }
        @app_promises.each_value { |p| p.reject(error) }

        @reply_promises.clear
        @app_promises.clear

        @event_barrier.wait
      rescue ConnectionError
        # Expected — event hooks may have been mid-command when disconnected
      end

      def disconnect
        @connection&.close_write
      end

      private

      def on_event(event)
      end

      def run_session
      end

      def invoke_event_hooks(resp)
        event_name = resp.event.downcase.to_sym
        hooks = self.class.hooks[event_name]

        hooks.each do |block|
          instance_exec(resp, &block)
        end
      end
    end
  end
end
