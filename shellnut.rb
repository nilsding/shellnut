#!/usr/bin/env ruby

require "rubygems"
require "IRC"
require "mumble-ruby"

$LOAD_PATH.unshift File.expand_path './lib', File.dirname(__FILE__)

require "irc_colors"

VERSION = "0.1.1"

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
      if event.message.start_with? "+users"
        irc.send_message(APP_CONFIG['irc']['channel'], "There are currently #{mumble.users.count - 1} users connected to #{APP_CONFIG['mumble']['server']}")
        unless mumble.users.count == 0
          mumble.users.each do |user|
            unless user[1].name == APP_CONFIG['mumble']['username']
              irc.send_message(APP_CONFIG['irc']['channel'], "\x02#{user[1].name.sub("\n", '')}\x02 in \x02#{mumble.channels[user[1].channel_id].name} #{"\x034[muted]\x0f" if user[1].self_mute}#{"\x038[deafened]\x0f" if user[1].deafened?}\x02") 
            end
          end
        end
      elsif event.message.start_with? "+help"
        irc.send_message(APP_CONFIG['irc']['channel'], "shellnut v#{VERSION} - available commands:")
        APP_CONFIG['help'].each do |cmd|
          irc.send_message(APP_CONFIG['irc']['channel'], "\x02#{cmd['command']}\x02 - #{cmd['description']}")
        end
      elsif event.message.start_with? "+mumble"
        irc_msg = event.message
        irc_msg.slice! "+mumble"
        irc_msg.strip!
        unless irc_msg.empty?
          mumble.text_channel(APP_CONFIG['mumble']['channel'], "<b>#{event.from}:</b>#{irc_msg}".irc_colors)
        end
      end
    }
    IRCEvent.add_callback('endofmotd') { |event|
      irc.add_channel(APP_CONFIG['irc']['channel']) 
    }
    irc.connect
  end

  @mumble_thread ||= Thread.new do
    mumble.on_text_message do |msg|
      if msg.message.start_with? "+help"
        help_msg = "shellnut v#{VERSION} - available commands:<br/>"
        APP_CONFIG['help'].each do |cmd|
          help_msg += "<b>#{cmd['command']}</b> - #{cmd['description']}<br/>"
        end
        mumble.text_channel(APP_CONFIG['mumble']['channel'], help_msg)
      elsif msg.message.start_with? "+irc"
        mumble_msg = msg.message
        mumble_msg.slice! "+irc"
        mumble_msg.strip!
        unless mumble_msg.empty?
          irc.send_message(APP_CONFIG['irc']['channel'], "\x02#{mumble.users[msg.actor].name.sub("\n", '')}:\x02#{mumble_msg}")
        end
      end
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