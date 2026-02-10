# frozen_string_literal: true

require 'logger'
require 'librevox/version'
require 'librevox/listener/inbound'
require 'librevox/listener/outbound'
require 'librevox/command_socket'

module Librevox
  def self.options
    @options ||= {
      :log_file   => STDOUT,
      :log_level  => Logger::INFO
    }
  end

  def self.logger
    @logger ||= logger!
  end

  def self.logger= logger
    @logger = logger
  end

  def self.logger!
    logger = Logger.new(options[:log_file])
    logger.level = options[:log_level]
    logger
  end

  def self.reopen_log
    @logger = logger!
  end

  # When called without a block, it will start the listener that is passed as
  # first argument:
  #
  #   Librevox.start SomeListener
  #
  # To start multiple listeners, call with a block and use `run`:
  #
  #   Librevox.start do
  #     run SomeListener
  #     run OtherListner
  #   end
  def self.start klass=nil, args={}, &block
    require 'async'
    require 'async/io'
    require 'async/io/stream'

    logger.info "Starting Librevox"

    Async do |task|
      trap("TERM") {stop(task)}
      trap("INT") {stop(task)}
      trap("HUP") {reopen_log}

      @task = task
      block_given? ? instance_eval(&block) : run(klass, args)
    end
  end

  def self.run klass, args={}
    args[:host] ||= "localhost"

    if klass.ancestors.include? Librevox::Listener::Inbound
      args[:port] ||= 8021
      @task.async do
        loop do
          begin
            socket = Async::IO::Endpoint.tcp(args[:host], args[:port]).connect
            stream = Async::IO::Stream.new(socket)
            connection = Connection.new(stream)

            listener = klass.allocate
            listener.send(:initialize, args)
            listener.instance_variable_set(:@connection, connection)
            listener.post_init
            listener.connection_completed
            listener.read_loop
          rescue IOError, Errno::ECONNREFUSED, Errno::ECONNRESET => e
            logger.error "Connection lost: #{e.message}. Reconnecting in 1s."
            sleep 1
          ensure
            stream&.close
          end
        end
      end
    elsif klass.ancestors.include? Librevox::Listener::Outbound
      args[:port] ||= 8084
      @task.async do
        endpoint = Async::IO::Endpoint.tcp(args[:host], args[:port])
        endpoint.accept do |socket|
          stream = Async::IO::Stream.new(socket)
          connection = Connection.new(stream)

          listener = klass.allocate
          listener.instance_variable_set(:@connection, connection)
          listener.post_init
          listener.read_loop
        rescue => e
          logger.error "Session error: #{e.message}"
        ensure
          stream&.close
        end
      end
    end
  end

  def self.stop task=nil
    logger.info "Terminating Librevox"
    task&.stop
  end

  # Wraps an Async::IO::Stream for production use.
  class Connection
    def initialize(stream)
      @stream = stream
    end

    def write(data)
      @stream.write(data)
      @stream.flush
    end

    def read_partial(size)
      @stream.read_partial(size)
    end

    def close
      @stream.close
    end
  end
end
