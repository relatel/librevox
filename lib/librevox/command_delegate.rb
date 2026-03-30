# frozen_string_literal: true

module Librevox
  # In some cases there are both applications and commands with the same
  # name, e.g. fifo. But we can't have two `fifo`-methods, so we include
  # commands in CommandDelegate, and expose all commands through the `api`
  # method, which wraps a CommandDelegate instance.
  class CommandDelegate
    include Librevox::Commands

    def initialize(listener)
      @listener = listener
    end

    def command(*args)
      @listener.send_message(super(*args))
    end
  end
end
