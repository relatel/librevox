# frozen_string_literal: true

require 'socket'
require 'io/stream'

module Librevox
  class CommandSocket
    include Librevox::Commands

    def initialize(server: "127.0.0.1", port: "8021", auth: "ClueCon", connect: true)
      @server = server
      @port   = port
      @auth   = auth

      self.connect if connect
    end

    def connect
      socket = TCPSocket.open(@server, @port)
      stream = IO::Stream(socket)
      @connection = Protocol::Connection.new(stream)
      send_message "auth #{@auth}"
    end

    def send_message(msg)
      @connection.send_data(msg)
      read_response
    end

    def command(*args)
      send_message(super(*args))
    end

    def read_response
      while (msg = @connection.receive_data)
        return msg if msg.reply?
      end
    end

    def application(app, uuid, args = nil, **params)
      send_message Protocol::Message.execute_app(uuid, app, args, **params)
    end

    def close
      @connection.close
    end
  end
end
