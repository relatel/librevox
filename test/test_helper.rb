# frozen_string_literal: true

Warning[:experimental] = false
require 'minitest/autorun'
require 'async'
require 'librevox'

Librevox.logger.level = Logger::WARN

module Librevox::Test
  module Matchers
    def assert_send_command(obj, command)
      assert_equal command, obj.outgoing_data.shift
    end

    def assert_send_nothing(obj)
      assert_nil obj.outgoing_data.shift
    end

    def assert_execute_app(obj, app, uuid, args = nil, **params)
      headers = params
        .merge(
          event_lock:       true,
          call_command:     "execute",
          execute_app_name: app,
          execute_app_arg:  args,
        )
        .map { |key, value| "#{key.to_s.tr('_', '-')}: #{value}" }

      assert_equal "sendmsg #{uuid}\n#{headers.join("\n")}", obj.outgoing_data.shift
    end
  end

  module ListenerHelpers
    def command_reply(args = {})
      args["Content-Type"] = "command/reply"
      response args
    end

    def api_response(args = {})
      args["Content-Type"] = "api/response"
      response args
    end

    def response(args = {})
      body    = args.delete :body
      headers = args

      if body.is_a? Hash
        body = body.map {|k,v| "#{k}: #{v}"}.join "\n"
      end

      headers["Content-Length"] = body.size if body
      header_str = headers.map {|k, v| "#{k}: #{v}"}.join("\n")

      @listener.receive_data(Librevox::Protocol::Response.new(header_str, body.to_s))
      yield_to_fibers
    end

    def event(name)
      body    = "Event-Name: #{name}"
      headers = "Content-Type: text/event-plain\nContent-Length: #{body.size}"

      @listener.receive_data(Librevox::Protocol::Response.new(headers, body))
      yield_to_fibers
    end

    def execute_complete(args = {})
      # sendmsg ack — always arrives before CHANNEL_EXECUTE_COMPLETE
      command_reply "Reply-Text" => "+OK"

      body = {"Event-Name" => "CHANNEL_EXECUTE_COMPLETE"}.merge(args)
      body_str = body.map {|k,v| "#{k}: #{v}"}.join("\n")
      headers = "Content-Type: text/event-plain\nContent-Length: #{body_str.size}"

      @listener.receive_data(Librevox::Protocol::Response.new(headers, body_str))
      yield_to_fibers
    end

    private

    def yield_to_fibers
      Async::Task.current.yield if Async::Task.current?
    end
  end

  # Wraps each test method in Async { } so promise operations work.
  module AsyncTest
    def run(...)
      Sync do
        super
      end
    end
  end
end

require_relative 'support/listener'
