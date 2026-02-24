# frozen_string_literal: true

require 'logger'
require 'librevox/version'
require 'librevox/listener/inbound'
require 'librevox/listener/outbound'
require 'librevox/server'
require 'librevox/client'
require 'librevox/runner'
require 'librevox/command_socket'

module Librevox
  def self.options
    @options ||= {
      log_file: STDOUT,
      log_level: Logger::INFO
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

  # Start a single listener:
  #
  #   Librevox.start MyInbound
  #   Librevox.start MyInbound, host: "1.2.3.4", auth: "secret"
  #
  # Start multiple listeners with a block:
  #
  #   Librevox.start do
  #     run MyInbound
  #     run MyOutbound, port: 8084
  #   end
  def self.start(klass = nil, **args, &block)
    require 'async'
    require 'async/barrier'

    logger.info "Starting Librevox"

    Async do
      barrier = Async::Barrier.new
      begin
        runner = Runner.new(barrier)
        if block_given?
          runner.instance_eval(&block)
        else
          runner.run(klass, **args)
        end
        barrier.wait
      ensure
        barrier.stop
      end
    end
  rescue Interrupt, SignalException
    logger.info "Terminating Librevox"
  end

end
