# frozen_string_literal: true

require 'logger'
require 'librevox/version'

module Librevox
  autoload :Client, 'librevox/client'
  autoload :CommandSocket, 'librevox/command_socket'
  autoload :Commands, 'librevox/commands'
  autoload :Applications, 'librevox/applications'
  autoload :Runner, 'librevox/runner'
  autoload :Server, 'librevox/server'

  module Protocol
    autoload :Connection, 'librevox/protocol/connection'
    autoload :Response, 'librevox/protocol/response'
  end

  module Listener
    autoload :Base, 'librevox/listener/base'
    autoload :Inbound, 'librevox/listener/inbound'
    autoload :Outbound, 'librevox/listener/outbound'
  end

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
  def self.start(...) = Runner.start(...)

end
