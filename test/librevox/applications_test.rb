# frozen_string_literal: true

require_relative '../test_helper'
require 'librevox/applications'

module AppTest
  include Librevox::Applications

  extend self

  def application(name, args = "", params = {})
    {
      :name   => name,
      :args   => args,
      :params => params
    }
  end
end

class TestApplications < Minitest::Test
  def test_answer
    app = AppTest.answer
    assert_equal "answer", app[:name]
  end

  def test_att_xfer
    app = AppTest.att_xfer("user/davis")
    assert_equal "att_xfer", app[:name]
    assert_equal "user/davis", app[:args]
  end

  def test_bind_meta_app
    app = AppTest.bind_meta_app :key => "2",
                          :listen_to => :a,
                          :respond_on => :s,
                          :application => "hangup"

    assert_equal "bind_meta_app", app[:name]
    assert_equal "2 a s hangup", app[:args]
  end

  def test_bind_meta_app_with_parameters
    app = AppTest.bind_meta_app :key => "2",
                          :listen_to => :a,
                          :respond_on => :s,
                          :application => "execute_extension",
                          :parameters => "dx XML features"

    assert_equal "bind_meta_app", app[:name]
    assert_equal "2 a s execute_extension::dx XML features", app[:args]
  end

  def test_bridge_to_endpoints
    app = AppTest.bridge('user/coltrane')
    assert_equal "bridge", app[:name]
    assert_equal 'user/coltrane', app[:args]

    app = AppTest.bridge('user/coltrane', 'user/davis')
    assert_equal 'user/coltrane,user/davis', app[:args]
  end

  def test_bridge_with_variables
    app = AppTest.bridge('user/coltrane', 'user/davis', :foo => 'bar', :lol => 'cat')
    assert_equal "bridge", app[:name]

    # fragile. hashes are not ordered in ruby 1.8
    assert_equal "{foo=bar,lol=cat}user/coltrane,user/davis", app[:args]
  end

  def test_bridge_with_failover
    app = AppTest.bridge(
      ['user/coltrane', 'user/davis'], ['user/sun-ra', 'user/taylor']
    )

    assert_equal "bridge", app[:name]
    assert_equal "user/coltrane,user/davis|user/sun-ra,user/taylor", app[:args]
  end

  def test_deflect
    app = AppTest.deflect "sip:miles@davis.org"
    assert_equal "deflect", app[:name]
    assert_equal "sip:miles@davis.org", app[:args]
  end

  def test_export
    app = AppTest.export 'some_var'
    assert_equal "export", app[:name]
    assert_equal "some_var", app[:args]
  end

  def test_export_only_b_leg
    app = AppTest.export 'some_var', :local => false
    assert_equal "export", app[:name]
    assert_equal "nolocal:some_var", app[:args]
  end

  def test_gentones
    app = AppTest.gentones("%(500,0,800)")
    assert_equal "gentones", app[:name]
    assert_equal "%(500,0,800)", app[:args]
  end

  def test_hangup
    app = AppTest.hangup
    assert_equal "hangup", app[:name]

    app = AppTest.hangup("some cause")
    assert_equal "some cause", app[:args]
  end

  def test_play_and_get_digits_defaults
    app = AppTest.play_and_get_digits "please-enter", "wrong-try-again"
    assert_equal "play_and_get_digits", app[:name]
    assert_equal "1 2 3 5000 # please-enter wrong-try-again read_digits_var \\d+", app[:args]
    assert_equal "read_digits_var", app[:params][:variable]
  end

  def test_play_and_get_digits_with_params
    app = AppTest.play_and_get_digits "please-enter", "invalid-choice",
      :min          => 2,
      :max          => 3,
      :tries        => 4,
      :terminators  => "0",
      :timeout      => 10000,
      :variable     => "other_var",
      :regexp       => "[125]"

    assert_equal "2 3 4 10000 0 please-enter invalid-choice other_var [125]", app[:args]
    assert_equal "other_var", app[:params][:variable]
  end

  def test_playback
    app = AppTest.playback("uri://some/file.wav")
    assert_equal "playback", app[:name]
    assert_equal "uri://some/file.wav", app[:args]
  end

  def test_pre_answer
    app = AppTest.pre_answer
    assert_equal "pre_answer", app[:name]
  end

  def test_read_with_defaults
    app = AppTest.read "please-enter.wav"
    assert_equal "read", app[:name]
    assert_equal "1 2 please-enter.wav read_digits_var 5000 #", app[:args]
    assert_equal "read_digits_var", app[:params][:variable]
  end

  def test_read_with_params
    app = AppTest.read "please-enter.wav",
      :min          => 2,
      :max          => 3,
      :terminators  => "0",
      :timeout      => 10000,
      :variable     => "other_var"

    assert_equal "2 3 please-enter.wav other_var 10000 0", app[:args]
    assert_equal "other_var", app[:params][:variable]
  end

  def test_record
    app = AppTest.record "/path/to/file.mp3"
    assert_equal "record", app[:name]
    assert_equal "/path/to/file.mp3", app[:args]
  end

  def test_record_with_time_limit
    app = AppTest.record "/path/to/file.mp3", :limit => 15
    assert_equal "record", app[:name]
    assert_equal "/path/to/file.mp3 15", app[:args]
  end

  def test_redirect
    app = AppTest.redirect("sip:miles@davis.org")
    assert_equal "redirect", app[:name]
    assert_equal "sip:miles@davis.org", app[:args]
  end

  def test_respond
    app = AppTest.respond 403
    assert_equal "respond", app[:name]
    assert_equal "403", app[:args]
  end

  def test_set
    app = AppTest.set("foo", "bar")
    assert_equal "set", app[:name]
    assert_equal "foo=bar", app[:args]
  end

  def test_multiset
    app = AppTest.multiset("foo" => "1", "bar" => "2")
    assert_equal "multiset", app[:name]
    assert_equal "^^|foo=1|bar=2", app[:args]
  end

  def test_transfer
    app = AppTest.transfer "new_extension"
    assert_equal "transfer", app[:name]
    assert_equal "new_extension", app[:args]
  end

  def test_unbind_meta_app
    app = AppTest.unbind_meta_app 3
    assert_equal "unbind_meta_app", app[:name]
    assert_equal "3", app[:args]
  end

  def test_unset
    app = AppTest.unset('foo')
    assert_equal "unset", app[:name]
    assert_equal "foo", app[:args]
  end
end
