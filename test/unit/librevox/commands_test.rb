# frozen_string_literal: true

require_relative '../../test_helper'
require 'librevox/commands'

module CommandTest
  include Librevox::Commands

  extend self

  def command(name, args = "")
    {
      name: name,
      args: args
    }
  end
end

C = CommandTest

class TestCommands < Minitest::Test
  def test_status
    cmd = C.status
    assert_equal "status", cmd[:name]
  end

  def test_originate_url_to_extension
    cmd = C.originate "user/coltrane", extension: 4000
    assert_equal "originate", cmd[:name]
    assert_equal "{}user/coltrane 4000", cmd[:args]
  end

  def test_originate_send_variables
    cmd = C.originate 'user/coltrane',
                      extension: 1234,
                      ignore_early_media: true,
                      other_option: "value"

    assert_match %r|^\{\S+\}user/coltrane 1234$|, cmd[:args]
    assert_match(/ignore_early_media=true/, cmd[:args])
    assert_match(/other_option=value/, cmd[:args])
  end

  def test_originate_take_dialplan_and_context
    cmd = C.originate "user/coltrane",
                      extension: "4000",
                      dialplan: "XML",
                      context: "public"
    assert_equal "originate", cmd[:name]
    assert_equal "{}user/coltrane 4000 XML public", cmd[:args]
  end

  def test_fsctl
    cmd = C.fsctl :hupall, :normal_clearing
    assert_equal "fsctl", cmd[:name]
    assert_equal "hupall normal_clearing", cmd[:args]
  end

  def test_hupall
    cmd = C.hupall
    assert_equal "hupall", cmd[:name]

    cmd = C.hupall("some_cause")
    assert_equal "hupall", cmd[:name]
    assert_equal "some_cause", cmd[:args]
  end

  def test_hupall_matching_a_variable
    cmd = C.hupall "NORMAL_CLEARING", "queue_owner", "1234-abcd"
    assert_equal "hupall", cmd[:name]
    assert_equal "NORMAL_CLEARING queue_owner 1234-abcd", cmd[:args]
  end

  def test_uuid_answer
    cmd = C.uuid_answer "1234-abcd"
    assert_equal "uuid_answer", cmd[:name]
    assert_equal "1234-abcd", cmd[:args]
  end

  def test_uuid_break
    assert_equal "1234-abcd", C.uuid_break("1234-abcd")[:args]
    assert_equal "1234-abcd all", C.uuid_break("1234-abcd", all: true)[:args]
  end

  def test_uuid_transfer
    cmd = C.uuid_transfer "1234-abcd", "9001", "XML", "default"
    assert_equal "uuid_transfer", cmd[:name]
    assert_equal "1234-abcd 9001 XML default", cmd[:args]

    cmd = C.uuid_transfer "1234-abcd", "playback:hello.wav,park", "inline"
    assert_equal "1234-abcd playback:hello.wav,park inline", cmd[:args]
  end

  def test_uuid_setvar
    cmd = C.uuid_setvar "1234-abcd", "hold_music", "local_stream://moh"
    assert_equal "uuid_setvar", cmd[:name]
    assert_equal "1234-abcd hold_music local_stream://moh", cmd[:args]
  end

  def test_uuid_setvar_multi
    cmd = C.uuid_setvar_multi "1234-abcd", "call_timeout" => 30, "continue_on_fail" => true
    assert_equal "uuid_setvar_multi", cmd[:name]
    assert_equal "1234-abcd call_timeout=30;continue_on_fail=true", cmd[:args]
  end

  # FreeSWITCH splits the variables on ";".
  def test_uuid_setvar_multi_refuses_a_value_with_a_semicolon
    assert_raises(ArgumentError) { C.uuid_setvar_multi "1234-abcd", "a" => "1;2" }
  end

  def test_hash_insert
    cmd = C.hash :insert, :firmafon, :foo, "some value or other"
    assert_equal "hash", cmd[:name]
    assert_equal "insert/firmafon/foo/some value or other", cmd[:args]
  end

  def test_hash_select
    cmd = C.hash :select, :firmafon, :foo
    assert_equal "hash", cmd[:name]
    assert_equal "select/firmafon/foo", cmd[:args]
  end

  def test_hash_delete
    cmd = C.hash :delete, :firmafon, :foo
    assert_equal "hash", cmd[:name]
    assert_equal "delete/firmafon/foo", cmd[:args]
  end

  def test_uuid_park
    cmd = C.uuid_park "1234-abcd"
    assert_equal "uuid_park", cmd[:name]
    assert_equal "1234-abcd", cmd[:args]
  end

  def test_uuid_bridge
    cmd = C.uuid_bridge "1234-abcd", "9090-ffff"
    assert_equal "uuid_bridge", cmd[:name]
    assert_equal "1234-abcd 9090-ffff", cmd[:args]
  end

  def test_uuid_kill
    cmd = C.uuid_kill "1234-abcd"
    assert_equal "uuid_kill", cmd[:name]
    assert_equal "1234-abcd", cmd[:args]

    cmd = C.uuid_kill "1234-abcd", "NO_ROUTE_DESTINATION"
    assert_equal "1234-abcd NO_ROUTE_DESTINATION", cmd[:args]
  end

  def test_sched_hangup
    cmd = C.sched_hangup "+3600", "1234-abcd", "ALLOTTED_TIMEOUT"
    assert_equal "sched_hangup", cmd[:name]
    assert_equal "+3600 1234-abcd ALLOTTED_TIMEOUT", cmd[:args]
  end

  # sched_del reads its count from FreeSWITCH's reply.
  module SchedDelReply
    include Librevox::Commands

    extend self

    attr_accessor :sent

    def command(name, args = "")
      self.sent = [name, args]
      Librevox::Protocol::Response.new("Content-Type: api/response", "+OK Deleted: 1\n")
    end
  end

  # global_getvar reads its value, or every value, from FreeSWITCH's reply.
  module UuidExistsReply
    include Librevox::Commands

    extend self

    attr_accessor :output, :sent

    def command(name, args = "")
      self.sent = [name, args]
      Librevox::Protocol::Response.new("Content-Type: api/response", output)
    end
  end

  module UuidGetvarReply
    include Librevox::Commands

    extend self

    attr_accessor :output, :sent

    def command(name, args = "")
      self.sent = [name, args]
      Librevox::Protocol::Response.new("Content-Type: api/response", output)
    end
  end

  def test_uuid_getvar_reads_a_value
    UuidGetvarReply.output = "local_stream://moh"
    assert_equal "local_stream://moh", UuidGetvarReply.uuid_getvar("1234-abcd", "hold_music")
    assert_equal ["uuid_getvar", "1234-abcd hold_music"], UuidGetvarReply.sent
  end

  # FreeSWITCH answers "_undef_" for a variable that isn't set.
  def test_uuid_getvar_is_nil_when_unset
    UuidGetvarReply.output = "_undef_"
    assert_nil UuidGetvarReply.uuid_getvar("1234-abcd", "nope")
  end

  module GlobalGetvarReply
    include Librevox::Commands

    extend self

    attr_accessor :output

    def command(_name, _args = "")
      Librevox::Protocol::Response.new("Content-Type: api/response", output)
    end
  end

  def test_global_getvar_reads_one
    GlobalGetvarReply.output = "node-1\n"
    assert_equal "node-1", GlobalGetvarReply.global_getvar("hostname")
  end

  def test_global_getvar_reads_them_all
    GlobalGetvarReply.output = "hostname=node-1\ndomain=a=b\n\n"
    assert_equal({ "hostname" => "node-1", "domain" => "a=b" }, GlobalGetvarReply.global_getvar)
  end

  def test_uuid_exists_reads_true_and_false
    UuidExistsReply.output = "true"
    assert UuidExistsReply.uuid_exists("1234-abcd")
    assert_equal ["uuid_exists", "1234-abcd"], UuidExistsReply.sent

    UuidExistsReply.output = "false"
    refute UuidExistsReply.uuid_exists("1234-abcd")
  end

  def test_sched_del_returns_how_many_tasks_it_deleted
    assert_equal 1, SchedDelReply.sched_del("1234-abcd")
    assert_equal ["sched_del", "1234-abcd"], SchedDelReply.sent
  end
end
