# frozen_string_literal: true

require 'async'
require 'async/barrier'

module Librevox
  class Runner
    def self.start(klass = nil, **args, &block)
      Librevox.logger.info "Starting Librevox"

      Async do
        barrier = Async::Barrier.new
        begin
          runner = new(barrier)
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
      Librevox.logger.info "Terminating Librevox"
    end

    def initialize(barrier)
      @barrier = barrier
    end

    def run(klass, **args)
      klass.run(@barrier, **args)
    end
  end
end
