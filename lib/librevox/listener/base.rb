# frozen_string_literal: true

require 'async'
require 'async/promise'
require 'securerandom'
require 'set'

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
        @event_tasks = Set.new
        @write_lock = Thread::Mutex.new
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

        # Send first, then record the reply promise — both under the write lock
        # so @reply_promises order always matches the byte order on the wire,
        # even when concurrent event hooks send commands. Recording only *after*
        # send_data returns is what keeps the queue honest: a sender cancelled
        # (Async::Stop) or failed mid-send never enqueues a promise, so it can
        # never leave an orphaned slot for a later reply to be misrouted onto.
        # There is no yield between the send and the push, so no reply for this
        # command can be observed before its promise is queued. Must not cover
        # promise.wait — holding the lock while awaiting a reply would deadlock
        # every other sender.
        @write_lock.synchronize do
          @connection.send_data(msg)
          @reply_promises << promise
        end

        reply = promise.wait
        raise ResponseError, reply.headers[:reply_text] if reply.error?

        reply
      end

      # Fire an event into FreeSWITCH, for every ESL listener subscribed to it.
      # Returns the Event-UUID FreeSWITCH gives the event, which every listener
      # sees. A line break in a header would end the command early and send
      # the rest as another command, so one raises ArgumentError.
      # @example
      #   sendevent "CUSTOM", "Event-Subclass" => "my::event", "Some-Header" => "value"
      def sendevent(name, headers = {})
        headers = headers.compact
        if [name, *headers.flatten].any? { |part| part.to_s.match?(/[\r\n]/) }
          raise ArgumentError, "sendevent headers can't contain line breaks"
        end

        lines = headers.map { |header, value| "#{header}: #{value}" }
        reply = send_message(["sendevent #{name}", *lines].join("\n"))
        reply.headers[:reply_text].delete_prefix("+OK ")
      end

      def execute_app(app, uuid, args = nil, **params)
        event_uuid = SecureRandom.uuid

        promise = Async::Promise.new
        @app_promises[event_uuid] = promise

        send_message Protocol::Message.execute_app(uuid, app, args, event_uuid:, **params)

        promise.wait
      end

      def receive_message(response)
        # FreeSWITCH answers a connection's commands once each, in order, so a
        # reply belongs to the oldest waiting command (see #send_message).
        if response.reply?
          @reply_promises.shift&.resolve(response)
          return
        end

        if response.event?
          if response.event == "CHANNEL_EXECUTE_COMPLETE"
            app_uuid = response.content[:application_uuid]
            @app_promises.delete(app_uuid)&.resolve(response)
          end

          Async do |task|
            @event_tasks << task
            begin
              on_event(response)
              invoke_event_hooks(response)
            ensure
              @event_tasks.delete(task)
            end
          end
        end
      end

      def connection_closed
        error = ConnectionError.new("Connection closed")

        @reply_promises.each { |p| p.reject(error) }
        @app_promises.each_value { |p| p.reject(error) }

        @reply_promises.clear
        @app_promises.clear

        @event_tasks.each { |task| task.wait rescue nil }
      rescue ConnectionError
        # Expected — event hooks may have been mid-command when disconnected
      end

      def disconnect
        @connection&.close_write
      end

      # Override to signal that the session has ended by protocol (not by
      # socket drop). Polled synchronously by {Session} after every dispatched
      # message — keep it cheap and return +true+ exactly once. When +true+,
      # the reader loop exits cleanly and in-flight event hooks drain before
      # the connection is closed.
      def session_complete?
        false
      end

      private

      def on_event(event)
      end

      def run_session
      end

      def invoke_event_hooks(resp)
        self.class.hooks[resp.event.downcase.to_sym].each do |block|
          instance_exec(resp, &block)
        end
      end
    end
  end
end
