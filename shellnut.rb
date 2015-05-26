#!/usr/bin/env ruby

require "rubygems"
require "IRC"
require "mumble-ruby"

$LOAD_PATH.unshift File.expand_path './lib', File.dirname(__FILE__)

require "irc_colors"

VERSION = "0.2.2"

APP_CONFIG = YAML.load_file(File.expand_path("config.yml", File.dirname(__FILE__)))

$irc_users = []
$irc_channel = ""

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
    IRCEvent.add_callback('whoreply') { |event|
      unless event.stats[7] == APP_CONFIG['irc']['nickname']
        realname = event.message
        realname.slice! "0 "
        $irc_channel = event.channel
        $irc_users << {nickname: event.stats[7], realname: realname }
      end
    }
    IRCEvent.add_callback('endofwho') { |event|
      sleep(2)
      user_msg = "There are currently #{$irc_users.count} users connected to #{$irc_channel} on #{APP_CONFIG['irc']['server']}<br/>"
      $irc_users.each do |user|
        user_msg += "<b>#{user[:nickname]}</b> (#{user[:realname]}) <br/>"
      end
      mumble.text_channel(APP_CONFIG['mumble']['channel'], user_msg)
      user_msg = ""
      $irc_users = []
      $irc_channel = ""
    }
    IRCEvent.add_callback('privmsg') { |event|
      if event.message.start_with? "+users"
        irc.send_message(event.channel, "There are currently #{mumble.users.count - 1} users connected to #{APP_CONFIG['mumble']['server']}")
        unless mumble.users.count == 0
          mumble.users.each do |user|
            unless user[1].name == APP_CONFIG['mumble']['username']
              irc.send_message(event.channel, "\x02#{user[1].name.sub("\n", '')}\x02 in \x02#{mumble.channels[user[1].channel_id].name} #{"\x034[muted]\x0f" if user[1].self_mute}#{"\x038[deafened]\x0f" if user[1].deafened?}\x02")
            end
          end
        end
      elsif event.message.start_with? "+help"
        irc.send_message(event.channel, "shellnut v#{VERSION} - available commands:")
        APP_CONFIG['help'].each do |cmd|
          irc.send_message(event.channel, "\x02#{cmd['command']}\x02 - #{cmd['description']}")
        end
      elsif event.message.start_with? "+mumble"
        irc_msg = event.message
        irc_msg.slice! "+mumble"
        irc_msg.strip!
        unless irc_msg.empty?
          mumble.text_channel(APP_CONFIG['mumble']['channel'], "<b>#{event.from}(#{event.channel}):</b> #{irc_msg}".irc_colors)
          puts "[IRC->Mumble] #{event.from}(#{event.channel}): #{irc_msg}"
        end
      end
    }
    IRCEvent.add_callback('endofmotd') { |event|
      puts "[IRC] Connected to server #{APP_CONFIG['irc']['server']}"
      APP_CONFIG['irc']['channel'].each do |channel|
        irc.add_channel(channel)
        puts "[IRC] Joined channel: #{channel}"
      end
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
        mumble_msg = mumble_msg.gsub(/\s+/m, ' ').split(" ")
        mumble_chl = mumble_msg[0]
        mumble_msg.delete_at(0)
        mumble_msg = mumble_msg.join " "
        if APP_CONFIG['irc']['channel'].include? mumble_chl
          unless mumble_msg.empty?
            irc.send_message(mumble_chl, "\x02#{mumble.users[msg.actor].name.sub("\n", '')}:\x02 #{mumble_msg}")
            puts "[Mumble->IRC] #{mumble.users[msg.actor].name.sub("\n", '')}: #{mumble_msg}"
          end
        else
          mumble.text_user(msg.actor, "Error: Invalid Channel")
        end
      elsif msg.message.start_with? "+users"
        mumble_chl = msg.message
        mumble_chl.slice! "+users"
        mumble_chl.strip!
        if APP_CONFIG['irc']['channel'].include? mumble_chl
          IRCConnection.send_to_server "WHO #{mumble_chl}"
        else
          mumble.text_user(msg.actor, "Error: Invalid Channel")
        end
      end
    end

    mumble.connect
    puts "[Mumble] Connected to server #{APP_CONFIG['mumble']['server']}"

    mumble.on_connected do
      mumble.me.mute
      mumble.me.deafen
    end

    sleep(2)
    mumble.join_channel(APP_CONFIG['mumble']['channel'])
    puts "[Mumble] Joined channel: #{APP_CONFIG['mumble']['channel']}"
  end

  @irc_thread.join
  @mumble_thread.join
end

start(irc, mumble)
