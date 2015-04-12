#!/usr/bin/env ruby

require "rubygems"
require "IRC"
require "mumble-ruby"
require "pp"

APP_CONFIG = YAML.load_file(File.expand_path("config.yml", File.dirname(__FILE__)))

# Configure all clients globally
Mumble.configure do |conf|
  # sample rate of sound (48 khz recommended)
  conf.sample_rate = 48000

  # bitrate of sound (32 kbit/s recommended)
  conf.bitrate = 32000

  # directory to store user's ssl certs
  conf.ssl_cert_opts[:cert_dir] = File.expand_path("./certs")
end

# Create client instance for your server
mumble = Mumble::Client.new(APP_CONFIG['mumble']['server'], APP_CONFIG['mumble']['port']) do |conf|
    conf.username = APP_CONFIG['mumble']['username']
end

irc = IRC.new(APP_CONFIG['irc']['nickname'], APP_CONFIG['irc']['server'], APP_CONFIG['irc']['port'], APP_CONFIG['irc']['realname'])

def start(irc, mumble)
  @irc_thread ||= Thread.new do
    IRCEvent.add_callback('privmsg') { |event| mumble.text_channel(APP_CONFIG['mumble']['channel'], "#{event.from}: #{event.message}")}
    IRCEvent.add_callback('endofmotd') { |event| irc.add_channel('#lobby') }
    irc.connect
  end

  @mumble_thread ||= Thread.new do
    mumble.connect

    mumble.on_connected do
      mumble.me.mute
      mumble.me.deafen
    end

    sleep(2)
    mumble.join_channel(APP_CONFIG['mumble']['channel'])

    mumble.on_text_message do |msg|
      mumble_msg = "#{mumble.users[msg.actor].name.sub("\n", '')}: #{msg.message}"
      irc.send_message(APP_CONFIG['irc']['channel'], mumble_msg)
    end
  end

  @irc_thread.join
  @mumble_thread.join
end

start(irc, mumble)

sleep(2)
pp mumble.users
pp mumble.channels
puts "Joined channel '#{APP_CONFIG['mumble']['channel']}'"



puts "Press enter to terminate"
gets

mumble.disconnect
