# frozen_string_literal: true

require_relative '../../test_helper'

class TestMessage < Minitest::Test
  Message = Librevox::Protocol::Message

  def test_execute_app
    text = Message.execute_app("1234-abcd", "playback", "welcome.wav", event_uuid: "e-1")

    assert_equal <<~TEXT.chomp, text
      sendmsg 1234-abcd
      event-lock: true
      call-command: execute
      execute-app-name: playback
      execute-app-arg: welcome.wav
      event-uuid: e-1
    TEXT
  end

  def test_execute_app_headers_can_override_the_defaults
    text = Message.execute_app("1234-abcd", "playback", "welcome.wav", event_lock: false)

    assert_includes text, "event-lock: false"
    refute_includes text, "event-lock: true"
  end

  def test_sendevent_leaves_out_headers_without_a_value
    text = Message.sendevent("CUSTOM", "Event-Subclass" => "my::event", "Skipped" => nil)

    assert_equal "sendevent CUSTOM\nEvent-Subclass: my::event", text
  end

  # A line break would end the sendmsg early and send the rest as a command
  # of its own, here "event plain ALL".
  def test_execute_app_refuses_a_line_break_in_an_argument
    assert_raises(ArgumentError) do
      Message.execute_app("1234-abcd", "set", "note=a\n\nevent plain ALL")
    end
  end

  def test_refuses_a_carriage_return
    assert_raises(ArgumentError) { Message.sendevent("CUSTOM", "Some-Header" => "x\rbgapi status") }
    assert_raises(ArgumentError) { Message.execute_app("1234-abcd", "set", "note=a\r") }
  end
end
