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

    def hupall(cause = nil)
      command "hupall", cause
    end

    # Park call.
    # @example
    #   socket.uuid_park "592567a2-1be4-11df-a036-19bfdab2092f"
    # @see http://wiki.freeswitch.org/wiki/Mod_commands#uuid_park
    def uuid_park(uuid)
      command "uuid_park", uuid
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
