# frozen_string_literal: true

module Librevox
  class Runner
    def initialize(barrier)
      @barrier = barrier
    end

    def run(klass, **args)
      klass.start(@barrier, **args)
    end
  end
end
