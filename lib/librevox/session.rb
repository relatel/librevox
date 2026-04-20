# frozen_string_literal: true

module Librevox
  # Runs one event-socket session on a connection: spawns a reader fiber that
  # dispatches incoming messages to the listener, runs the listener's session
  # logic in the calling fiber, and joins them on disconnect.
  class Session
    def initialize(connection, listener)
      @connection = connection
      @listener = listener
    end

    def run
      reader = start_reader
      @listener.run_session
      reader.wait
    rescue ConnectionError
      # Expected when the connection drops.
    ensure
      reader&.stop
      @connection.close
    end

    private

    # Reject pending promises inside the reader's ensure (not run's) so a
    # connection drop unblocks run_session via promise rejection. run's
    # ensure can't fire until run_session returns — that would deadlock.
    def start_reader
      Async do
        @connection.each_message do |msg|
          @listener.receive_message(msg)
          break if @listener.session_complete?
        end
      ensure
        @listener.connection_closed
      end
    end
  end
end
