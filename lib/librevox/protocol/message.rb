# frozen_string_literal: true

module Librevox
  module Protocol
    # Builds the text of messages sent to FreeSWITCH.
    module Message
      # A sendmsg asking FreeSWITCH to run +app+ on the channel +uuid+, e.g.
      #
      #   sendmsg 1234-abcd
      #   event-lock: true
      #   call-command: execute
      #   execute-app-name: playback
      #   execute-app-arg: welcome.wav
      #
      # Extra headers are added to the message, and can override the
      # defaults, e.g. event_lock: false.
      def self.execute_app(uuid, app, args = nil, **headers)
        headers = {
          event_lock:       true,
          call_command:     "execute",
          execute_app_name: app,
          execute_app_arg:  args,
          **headers,
        }

        lines = headers.map { |name, value| "#{name.to_s.tr('_', '-')}: #{value}" }

        ["sendmsg #{uuid}", *lines].join("\n")
      end
    end
  end
end
