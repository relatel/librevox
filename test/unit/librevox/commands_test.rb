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

  def test_sched_del_returns_how_many_tasks_it_deleted
    assert_equal 1, SchedDelReply.sched_del("1234-abcd")
    assert_equal ["sched_del", "1234-abcd"], SchedDelReply.sent
  end
end
