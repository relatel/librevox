# frozen_string_literal: true

require 'librevox/response'
require 'librevox/commands'

module Librevox
  module Listener
    class Base
      def self.new(connection = nil, *args)
        instance = allocate
        instance.send(:initialize, *args)
        instance.connection = connection
        instance.post_init
        instance
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

        def command(*args, &block)
          @listener.command(super(*args), &block)
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

      def command(msg, &block)
        send_data "#{msg}\n\n"

        @command_queue.push(block)
      end

      attr_accessor :response
      attr_writer :connection
      alias :event :response

      def post_init
        @command_queue = []
      end

      def receive_data(data)
        @buf ||= String.new
        @buf << data
        process_buffer
      end

      def receive_request(header, content)
        @response = Librevox::Response.new(header, content)
        handle_response
      end

      def handle_response
        if response.api_response? && @command_queue.any?
          @command_queue.shift.call(response)
        end

        if response.event?
          on_event(response.dup)
          invoke_event_hooks
        end
      end

      # override
      def on_event(event)
      end

      def send_data(data)
        @connection&.write(data)
      end

      def read_loop
        while data = @connection.read_partial(4096)
          receive_data(data)
        end
      end

      def connection_completed
      end

      def close_connection_after_writing
        @connection&.close
      end

      alias :done :close_connection_after_writing

      private

      def process_buffer
        loop do
          if @content_length
            break if @buf.length < @content_length
            content = @buf.slice!(0, @content_length)
            @content_length = nil
            receive_request(@header_buffer, content)
          else
            idx = @buf.index("\n\n")
            break unless idx

            @header_buffer = @buf.slice!(0, idx)
            @buf.slice!(0, 2) # remove \n\n

            next if @header_buffer.empty?

            if @header_buffer =~ /Content-Length:\s*(\d+)/i
              @content_length = $1.to_i
              if @content_length == 0
                @content_length = nil
                receive_request(@header_buffer, "")
              end
            else
              receive_request(@header_buffer, "")
            end
          end
        end
      end

      def invoke_event_hooks
        event = response.event.downcase.to_sym
        self.class.hooks[event].each {|block|
          instance_exec(response.dup, &block)
        }
      end
    end
  end
end
