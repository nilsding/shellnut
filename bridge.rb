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
client = Mumble::Client.new(APP_CONFIG['mumble']['server'], APP_CONFIG['mumble']['port']) do |conf|
    conf.username = APP_CONFIG['mumble']['username']
end

client.connect

client.on_connected do
    client.me.mute
    client.me.deafen
end

sleep(2)
pp client.users
pp client.channels

client.join_channel(APP_CONFIG['mumble']['channel'])
puts "Joined channel '#{APP_CONFIG['mumble']['channel']}'"

client.on_text_message do |msg|
  puts "#{msg.actor}: #{msg.message}"
end

puts "Press enter to terminate"
gets

client.disconnect
