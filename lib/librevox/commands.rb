# frozen_string_literal: true

module Librevox
  # All commands should call `command` with the following parameters:
  #
  #   `name` - name of the command
  #   `args` - arguments as a string (optional)
  module Commands
    # Executes a generic API command, optionally taking arguments as string.
    # @example
    #   socket.command "fsctl", "hupall normal_clearing"
    # @see http://wiki.freeswitch.org/wiki/Mod_commands
    def command(name, args = "")
      parts = ["api", name]
      parts << args if args && !args.empty?
      parts.join(" ")
    end

    def status
      command "status"
    end

    # Access the hash table that comes with FreeSWITCH.
    # @example
    #   socket.hash :insert, :realm, :key, "value"
    #   socket.hash :select, :realm, :key
    #   socket.hash :delete, :realm, :key
    def hash(*args)
      command "hash", args.join("/")
    end

    # Originate a new call.
    # @example Minimum options
    #   socket.originate 'sofia/user/coltrane', extension: "1234"
    # @example With :dialplan and :context
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#originate
    def originate(url, args = {})
      extension = args.delete(:extension)
      dialplan  = args.delete(:dialplan)
      context   = args.delete(:context)

      vars = args.map {|k,v| "#{k}=#{v}"}.join(",")

      arg_string = "{#{vars}}" +
        [url, extension, dialplan, context].compact.join(" ")
      command "originate", arg_string
    end

    # FreeSWITCH control messages.
    # @example
    #   socket.fsctl :hupall, :normal_clearing
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#fsctl
    def fsctl(*args)
      command "fsctl", args.join(" ")
    end

    # Hang up every call, or with a variable and value, every call that has
    # that channel variable set to that value.
    # @example
    #   socket.hupall "NORMAL_CLEARING"
    #   socket.hupall "NORMAL_CLEARING", "queue_owner", "592567a2-1be4-11df-a036-19bfdab2092f"
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#hupall
    def hupall(cause = nil, variable = nil, value = nil)
      command "hupall", [cause, variable, value].compact.join(" ")
    end

    # Park call.
    # @example
    #   socket.uuid_park "592567a2-1be4-11df-a036-19bfdab2092f"
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#uuid_park
    def uuid_park(uuid)
      command "uuid_park", uuid
    end

    # Answer a channel.
    # @example
    #   socket.uuid_answer "592567a2-1be4-11df-a036-19bfdab2092f"
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#uuid_answer
    def uuid_answer(uuid)
      command "uuid_answer", uuid
    end

    # Stop what a channel is playing: the current file, or with all: true,
    # everything it has queued.
    # @example
    #   socket.uuid_break "592567a2-1be4-11df-a036-19bfdab2092f", all: true
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#uuid_break
    def uuid_break(uuid, all: false)
      scope = "all" if all
      command "uuid_break", [uuid, scope].compact.join(" ")
    end

    # Transfer a channel to an extension in the dialplan, or to inline
    # applications.
    # @example
    #   socket.uuid_transfer "592567a2-1be4-11df-a036-19bfdab2092f", "9001", "XML", "default"
    #   socket.uuid_transfer "592567a2-1be4-11df-a036-19bfdab2092f", "playback:hello.wav,park", "inline"
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#uuid_transfer
    def uuid_transfer(uuid, destination, dialplan = nil, context = nil)
      command "uuid_transfer", [uuid, destination, dialplan, context].compact.join(" ")
    end

    # Queue digits on a channel as if the caller had pressed them. FreeSWITCH
    # reports them with DTMF-Source APP.
    # @example
    #   socket.uuid_recv_dtmf "592567a2-1be4-11df-a036-19bfdab2092f", "12"
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#uuid_recv_dtmf
    def uuid_recv_dtmf(uuid, digits)
      command "uuid_recv_dtmf", "#{uuid} #{digits}"
    end

    # Set a channel variable.
    # @example
    #   socket.uuid_setvar "592567a2-1be4-11df-a036-19bfdab2092f", "hold_music", "local_stream://moh"
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#uuid_setvar
    def uuid_setvar(uuid, name, value)
      command "uuid_setvar", "#{uuid} #{name} #{value}"
    end

    # Set several channel variables in one command. FreeSWITCH separates them
    # with ";", so a value can't contain one.
    # @example
    #   socket.uuid_setvar_multi "592567a2-1be4-11df-a036-19bfdab2092f", "call_timeout" => 30, "continue_on_fail" => true
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#uuid_setvar_multi
    def uuid_setvar_multi(uuid, variables)
      if variables.values.any? { |value| value.to_s.include?(";") }
        raise ArgumentError, "uuid_setvar_multi separates variables with \";\", so a value can't contain one"
      end

      assignments = variables
        .map { |name, value| "#{name}=#{value}" }
        .join(";")
      command "uuid_setvar_multi", "#{uuid} #{assignments}"
    end

    # Read a channel variable, or nil when it isn't set: FreeSWITCH answers
    # "_undef_".
    # @example
    #   socket.uuid_getvar "592567a2-1be4-11df-a036-19bfdab2092f", "hold_music" # => "local_stream://moh"
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#uuid_getvar
    def uuid_getvar(uuid, name)
      value = command("uuid_getvar", "#{uuid} #{name}").content
      return if value == "_undef_"

      value
    end

    # Whether FreeSWITCH has a channel with this uuid. It answers "true" or
    # "false".
    # @example
    #   socket.uuid_exists "592567a2-1be4-11df-a036-19bfdab2092f" # => true
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#uuid_exists
    def uuid_exists(uuid)
      command("uuid_exists", uuid).content == "true"
    end

    # Hang up a call, with an optional cause.
    # @example
    #   socket.uuid_kill "592567a2-1be4-11df-a036-19bfdab2092f", "NO_ROUTE_DESTINATION"
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#uuid_kill
    def uuid_kill(uuid, cause = nil)
      command "uuid_kill", [uuid, cause].compact.join(" ")
    end

    # Schedule a hangup. `time` is seconds from now with a leading "+", or an
    # epoch time.
    # @example
    #   socket.sched_hangup "+3600", "592567a2-1be4-11df-a036-19bfdab2092f", "ALLOTTED_TIMEOUT"
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#sched_hangup
    def sched_hangup(time, uuid, cause = nil)
      command "sched_hangup", [time, uuid, cause].compact.join(" ")
    end

    # Delete a scheduled task by its id, or every task in a group. A call's
    # scheduled tasks (sched_hangup, sched_transfer, …) are grouped by its uuid.
    # Returns how many tasks were deleted, from FreeSWITCH's
    # "+OK Deleted: <count>".
    # @example
    #   socket.sched_del "592567a2-1be4-11df-a036-19bfdab2092f" # => 1
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#sched_del
    def sched_del(id)
      command("sched_del", id).content[/\A\+OK Deleted: (\d+)/, 1].to_i
    end

    # Read a global variable (vars.xml). With no name, read them all, as a
    # Hash: FreeSWITCH lists them one name=value per line.
    # @example
    #   socket.global_getvar "hostname" # => "node-1"
    #   socket.global_getvar            # => { "hostname" => "node-1", … }
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#global_getvar
    def global_getvar(name = nil)
      output = command("global_getvar", name).content
      return output.strip if name

      output
        .lines(chomp: true)
        .reject(&:empty?)
        .to_h { |line| line.split("=", 2) }
    end

    # Bridge two call legs together. At least one leg must be answered.
    # @example
    #   socket.uuid_bridge "592567a2-1be4-11df-a036-19bfdab2092f", "58b39c3a-1be4-11df-a035-19bfdab2092f"
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#uuid_bridge
    def uuid_bridge(uuid1, uuid2)
      command "uuid_bridge", "#{uuid1} #{uuid2}"
    end
  end
end
