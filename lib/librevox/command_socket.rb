# frozen_string_literal: true

require 'socket'
require 'io/stream'

module Librevox
  class CommandSocket
    include Librevox::Commands

    def initialize(args = {})
      @server   = args[:server] || "127.0.0.1"
      @port     = args[:port] || "8021"
      @auth     = args[:auth] || "ClueCon"

      connect unless args[:connect] == false
    end

    def connect
      socket = TCPSocket.open(@server, @port)
      stream = IO::Stream(socket)
      @connection = Protocol::Connection.new(stream)
      send_message "auth #{@auth}"
    end

    def send_message(msg)
      @connection.send_message(msg)
      read_response
    end

    def command(*args)
      send_message(super(*args))
    end

    def read_response
      while msg = @connection.read_message
        return msg if msg.command_reply? || msg.api_response?
      end
    end

    def application(uuid, app, args = nil, **params)
      headers = params
        .merge(
          event_lock:       true,
          call_command:     "execute",
          execute_app_name: app,
          execute_app_arg:  args,
        )
        .map { |key, value| "#{key.to_s.tr('_', '-')}: #{value}" }

      send_message "sendmsg #{uuid}\n#{headers.join("\n")}"
    end

    def close
      @connection.close
    end
  end
end
