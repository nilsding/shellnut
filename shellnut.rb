#!/usr/bin/env ruby

require "rubygems"
require "IRC"
require "mumble-ruby"

$LOAD_PATH.unshift File.expand_path './lib', File.dirname(__FILE__)

require "irc_colors"

APP_CONFIG = YAML.load_file(File.expand_path("config.yml", File.dirname(__FILE__)))

Mumble.configure do |conf|
  # directory to store user's ssl certs
  conf.ssl_cert_opts[:cert_dir] = File.expand_path("./certs")
end

# Create client instance for your server
mumble = Mumble::Client.new(APP_CONFIG['mumble']['server'], APP_CONFIG['mumble']['port']) do |conf|
    conf.username = APP_CONFIG['mumble']['username']
end

irc = IRC.new(APP_CONFIG['irc']['nickname'], 
              APP_CONFIG['irc']['server'], 
              APP_CONFIG['irc']['port'], 
              APP_CONFIG['irc']['realname'])

def start(irc, mumble)
  @irc_thread ||= Thread.new do
    IRCEvent.add_callback('privmsg') { |event|
      if event.message.start_with? "!mumble"
        irc.send_message(APP_CONFIG['irc']['channel'], "There are currently #{mumble.users.count} users connected to #{APP_CONFIG['mumble']['server']}")
        unless mumble.users.count == 0
          mumble.users.each do |user|
            irc.send_message(APP_CONFIG['irc']['channel'], "\x02#{user[1].name.sub("\n", '')}\x02 in \x02#{mumble.channels[user[1].channel_id].name} #{"\x034[muted]\x0f" if user[1].self_mute?}#{"\x038[deafened]\x0f" if user[1].deafened?}\x02") 
          end
        end
      else
        mumble.text_channel(APP_CONFIG['mumble']['channel'], "<b>#{event.from}:</b> #{event.message}".irc_colors)
      end
    }
    IRCEvent.add_callback('endofmotd') { |event|
      irc.add_channel(APP_CONFIG['irc']['channel']) 
    }
    irc.connect
  end

  @mumble_thread ||= Thread.new do
    mumble.on_text_message do |msg|
      mumble_msg = "\x02#{mumble.users[msg.actor].name.sub("\n", '')}:\x02 #{msg.message}"
      irc.send_message(APP_CONFIG['irc']['channel'], mumble_msg)
    end

    mumble.connect

    mumble.on_connected do
      mumble.me.mute
      mumble.me.deafen
    end

    sleep(2)
    mumble.join_channel(APP_CONFIG['mumble']['channel'])
  end

  @irc_thread.join
  @mumble_thread.join
end

start(irc, mumble)