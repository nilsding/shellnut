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
  #IRC
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

  #Mumble
  @mumble_thread ||= Thread.new do

    mumble.on_text_message do |msg|
      message = msg.message.gsub(/\s+/m, ' ').strip.split(" ")
      command = message[0]
      content = message.drop(1).join(" ")
      prefix = APP_CONFIG['prefix']

      if command.slice!(0) == prefix
        case command
          when 'ping'
            if content.nil? || content.empty?
              mumble.text_channel(APP_CONFIG['mumble']['channel'], "pong")
            else
              mumble.text_channel(APP_CONFIG['mumble']['channel'], content)
            end

          when 'help'
            help_msg = "shellnut v#{VERSION} - available commands:<br/>"
            APP_CONFIG['help'].each do |cmd|
              help_msg += "<b>#{cmd['command']}</b> - #{cmd['description']}<br/>"
            end
            mumble.text_channel(APP_CONFIG['mumble']['channel'], help_msg)

          when 'irc'
            mumble_msg = content.gsub(/\s+/m, ' ').split(" ")
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

          when 'users'
            if APP_CONFIG['irc']['channel'].include? content
              IRCConnection.send_to_server "WHO #{content}"
            else
              mumble.text_user(msg.actor, "Error: Invalid Channel '#{content}'")
            end
        end
      end
    end
    #end of on_text_message

    mumble.on_user_state do |state|
      next unless state.include? "name"
      next unless mumble.connected?
      next unless APP_CONFIG['mumble']['announce_joins']
      name = state['name'].gsub("\n", '')
      puts "[Mumble] user #{name} connected"
      APP_CONFIG['irc']['channel'].each do |channel|
        irc.send_message(channel, "\x039[+]\x0F \x02#{name}\x0f connected to #{APP_CONFIG['mumble']['server']}")
      end
    end
    #end of on_user_state

    mumble.on_user_remove do |x|
      next unless APP_CONFIG['mumble']['announce_joins']
      user = mumble.users[x['session']]
      next if user.nil?
      name = user.name.gsub("\n", '')
      puts "[Mumble] user #{name} disconnected"
      APP_CONFIG['irc']['channel'].each do |channel|
        irc.send_message(channel, "\x034[-]\x0F \x02#{name}\x0f disconnected from #{APP_CONFIG['mumble']['server']}")
      end
    end
    #end of on_user_remove

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

# kate: indent-width 2
