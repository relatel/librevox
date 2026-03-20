# frozen_string_literal: true

require 'async/queue'
require 'async/semaphore'
require 'async/barrier'

module Librevox
  module Listener
    class Base
      def initialize(connection)
        @connection = connection
        @reply_queue = Async::Queue.new
        @command_mutex = Async::Semaphore.new(1)
        @event_barrier = Async::Barrier.new
      end

      class << self
        def hooks
          @hooks ||= Hash.new {|hash, key| hash[key] = []}
        end

        def event(event, &block)
          hooks[event] << block
        end
      end

      # In some cases there are both applications and commands with the same
      # name, e.g. fifo. But we can't have two `fifo`-methods, so we include
      # commands in CommandDelegate, and expose all commands through the `api`
      # method, which wraps a CommandDelegate instance.
      class CommandDelegate
        include Librevox::Commands

        def initialize(listener)
          @listener = listener
        end

        def command(*args)
          @listener.send_message(super(*args))
        end
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
        @command_mutex.acquire do
          @connection.send_message(msg)
          reply = @reply_queue.dequeue
          raise ConnectionError, "Connection closed" if reply.nil?
          raise ResponseError, reply.headers[:reply_text] if reply.error?
          reply
        end
      end

      attr_accessor :response

      def receive_message(response)
        @response = response
        handle_response
      end

      def handle_response
        if response.reply?
          @reply_queue.push(response)
          return
        end

        if response.event?
          resp = response
          @event_barrier.async do
            on_event(resp)
            invoke_event_hooks(resp)
          end
        end
      end

      # override
      def on_event(event)
      end

      def run_session
      end

      def connection_closed
        @reply_queue.close
      end

      def disconnect
        @connection&.close_write
      end

      private

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
