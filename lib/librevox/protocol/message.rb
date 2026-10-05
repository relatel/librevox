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

        command "sendmsg #{uuid}", headers.transform_keys { |name| name.to_s.tr('_', '-') }
      end

      # A sendevent firing a +name+ event into FreeSWITCH, e.g.
      #
      #   sendevent CUSTOM
      #   Event-Subclass: my::event
      #
      # Header names are passed as FreeSWITCH spells them. Headers without a
      # value are left out.
      def self.sendevent(name, headers = {})
        command "sendevent #{name}", headers.compact
      end

      # A command line followed by "Name: value" header lines. A line break
      # inside one of them would end the message early and send the rest as
      # a command of its own, so one raises ArgumentError.
      def self.command(line, headers)
        lines = [line, *headers.map { |name, value| "#{name}: #{value}" }]

        if lines.any? { |part| part.include?("\n") }
          raise ArgumentError, "a message to FreeSWITCH can't contain line breaks"
        end

        lines.join("\n")
      end
    end
  end
end
