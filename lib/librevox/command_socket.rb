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
      @socket = TCPSocket.open(@server, @port)
      stream = IO::Stream(@socket)
      @connection = Protocol::Connection.new(stream)
      @connection.write "auth #{@auth}\n\n"
      read_response
    end

    def command(*args)
      @connection.write "#{super(*args)}\n\n"
      read_response
    end

    def read_response
      while msg = @connection.read_message
        return msg if msg.command_reply? || msg.api_response?
      end
    end

    def close
      @connection.close
    end
  end
end
