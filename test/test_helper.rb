# frozen_string_literal: true

require 'minitest/autorun'
require 'async'
require 'librevox'

Librevox.logger.level = Logger::WARN

module Librevox::Test
  module Matchers
    def assert_send_command(obj, command)
      assert_equal "#{command}\n\n", obj.outgoing_data.shift
    end

    def assert_send_nothing(obj)
      assert_nil obj.outgoing_data.shift
    end

    def assert_send_application(obj, app, args = nil)
      parts = ["sendmsg", "call-command: execute", "execute-app-name: #{app}"]
      parts << "execute-app-arg: #{args}" if args
      parts << "event-lock: true"

      assert_equal parts.join("\n") + "\n\n", obj.outgoing_data.shift
    end

    def assert_update_session(obj, session_id = nil)
      if session_id
        assert_equal "api uuid_dump #{session_id}\n\n", obj.outgoing_data.shift
      else
        assert_match(/^api uuid_dump \d+/, obj.outgoing_data.shift)
      end
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

    def channel_data(args = {})
      api_response :body => {
        "Event-Name"  => "CHANNEL_DATA",
        "Session-Var" => "Second"
      }.merge(args)
    end

    def response(args = {})
      body    = args.delete :body
      headers = args

      if body.is_a? Hash
        body = body.map {|k,v| "#{k}: #{v}"}.join "\n"
      end

      headers["Content-Length"] = body.size if body
      header_str = headers.map {|k, v| "#{k}: #{v}"}.join("\n")

      @listener.receive_message(header_str, body.to_s)
      yield_to_fibers
    end

    def event(name)
      body    = "Event-Name: #{name}"
      headers = "Content-Type: text/event-plain\nContent-Length: #{body.size}"

      @listener.receive_message(headers, body)
      yield_to_fibers
    end

    def execute_complete(args = {})
      # sendmsg ack — always arrives before CHANNEL_EXECUTE_COMPLETE
      command_reply "Reply-Text" => "+OK"

      body = {"Event-Name" => "CHANNEL_EXECUTE_COMPLETE"}.merge(args)
      body_str = body.map {|k,v| "#{k}: #{v}"}.join("\n")
      headers = "Content-Type: text/event-plain\nContent-Length: #{body_str.size}"

      @listener.receive_message(headers, body_str)
      yield_to_fibers
    end

    private

    def yield_to_fibers
      Async::Task.current.yield if Async::Task.current?
    end
  end

  # Wraps each test method in Async { } so queue operations work.
  module AsyncTest
    def run(...)
      Sync do
        super
      end
    end
  end
end

require_relative 'support/listener'
