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

  def self.logger=(logger)
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
  #     run OtherListener
  #   end
  def self.start(klass = nil, args = {}, &block)
    require 'async'
    require 'async/io'
    require 'async/io/stream'

    logger.info "Starting Librevox"

    Async do |task|
      trap("TERM") { stop(task) }
      trap("INT") { stop(task) }
      trap("HUP") { reopen_log }

      @task = task
      block_given? ? instance_eval(&block) : run(klass, args)
    end
  end

  def self.run(klass, args = {})
    klass.start(@task, args)
  end

  def self.stop(task = nil)
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
