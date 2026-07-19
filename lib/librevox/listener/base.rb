# frozen_string_literal: true

require 'async/promise'
require 'async/semaphore'
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
        # Event hooks run in fire-and-forget tasks. We only need to *count* the
        # in-flight ones (so a disconnect can drain them) — not hold references to
        # them. A count is one integer regardless of how many events pass through;
        # an Async::Barrier, by contrast, retains a node per task until #wait, so
        # it grew without bound on a long-lived connection (one node per event for
        # the life of the socket — a slow memory leak).
        @event_tasks = 0
        @drained = Async::Promise.new
        @closing = false
        @write_lock = Async::Semaphore.new(1)
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
        @write_lock.acquire do
          @connection.send_data(msg)
          @reply_promises << promise
        end

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

      def receive_message(response)
        if response.reply?
          @reply_promises.shift&.resolve(response)
          return
        end

        if response.event?
          if response.event == "CHANNEL_EXECUTE_COMPLETE"
            app_uuid = response.content[:application_uuid]
            @app_promises.delete(app_uuid)&.resolve(response)
          end

          @event_tasks += 1
          Async do
            on_event(response)
            invoke_event_hooks(response)
          ensure
            @event_tasks -= 1
            # The last hook to finish during a drain rings the bell.
            @drained.resolve(true) if @closing && @event_tasks.zero?
          end
        end
      end

      def connection_closed
        error = ConnectionError.new("Connection closed")

        @reply_promises.each { |p| p.reject(error) }
        @app_promises.each_value { |p| p.reject(error) }

        @reply_promises.clear
        @app_promises.clear

        # Drain in-flight event hooks: wait until the count hits zero. If nothing
        # is in flight, resolve immediately so #wait returns at once; otherwise the
        # last hook's ensure resolves it. Promise (not Condition) so a resolve that
        # races ahead of the wait is still delivered.
        @closing = true
        @drained.resolve(true) if @event_tasks.zero?
        @drained.wait
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
        event_name = resp.event.downcase.to_sym
        hooks = self.class.hooks[event_name]

        hooks.each do |block|
          instance_exec(resp, &block)
        end
      end
    end
  end
end
