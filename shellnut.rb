#!/usr/bin/env ruby

require "rubygems"
require "IRC"
require "mumble-ruby"

$LOAD_PATH.unshift File.expand_path './lib', File.dirname(__FILE__)

require "irc_colors"

VERSION = "0.2.4"

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
    IRCEvent.add_callback('join') { |event|
      next unless APP_CONFIG['irc']['announce_joins']
      unless event.from == APP_CONFIG['irc']['nickname']
        puts "[IRC] #{event.from} joined #{event.channel}"
        mumble.text_channel(APP_CONFIG['mumble']['channel'], "<b>#{event.from}</b> joined #{event.channel}")
      end
    }
    IRCEvent.add_callback('part') { |event|
      next unless APP_CONFIG['irc']['announce_joins']
      unless event.from == APP_CONFIG['irc']['nickname']
        puts "[IRC] #{event.from} left #{event.channel}"
        mumble.text_channel(APP_CONFIG['mumble']['channel'], "<b>#{event.from}</b> left #{event.channel}")
      end
    }
    IRCEvent.add_callback('quit') { |event|
      next unless APP_CONFIG['irc']['announce_joins']
      unless event.from == APP_CONFIG['irc']['nickname']
        puts "[IRC] #{event.from} disconnected from the server"
        mumble.text_channel(APP_CONFIG['mumble']['channel'], "<b>#{event.from}</b> disconnected from #{APP_CONFIG['irc']['server']}")
      end
    }
    IRCEvent.add_callback('nick') { |event|
      next unless APP_CONFIG['irc']['announce_nicks']
      puts "[IRC] #{event.from} is now known as #{event.channel}"
       mumble.text_channel(APP_CONFIG['mumble']['channel'], "<i>#{event.from}</i> is now known as <b>#{event.channel}</b>")
    }
    IRCEvent.add_callback('privmsg') { |event|
      message = event.message.gsub(/\s+/m, ' ').strip.split(" ")
      command = message[0]
      next if command.nil?
      content = message.drop(1).join(" ")
      prefix_config = APP_CONFIG['prefix']
      prefix_current = command.slice!(0)
      command.downcase!

      if prefix_current == prefix_config
        case command
          when 'users'
          irc.send_message(event.channel, "There are currently #{mumble.users.count - 1} users connected to #{APP_CONFIG['mumble']['server']}")
          unless mumble.users.count == 0
            mumble.users.each do |user|
              unless user[1].name == APP_CONFIG['mumble']['username']
                channel_name = if mumble.channels[user[1].channel_id].nil?
                                 "Server Root"
                               else
                                 mumble.channels[user[1].channel_id].name
                               end
                irc.send_message(event.channel, "\x02#{user[1].name.sub("\n", '')}\x02 in \x02#{channel_name} #{"\x034[muted]\x0f" if user[1].self_mute}#{"\x038[deafened]\x0f" if user[1].deafened?}\x02")
              end
            end
          end
          when 'help'
            irc.send_message(event.channel, "shellnut v#{VERSION} - available commands:")
            APP_CONFIG['help'].each do |cmd|
              irc.send_message(event.channel, "\x02#{prefix_config}#{cmd['command']}\x02 - #{cmd['description']}")
            end
          when 'mumble'
            unless content.empty?
              mumble.text_channel(APP_CONFIG['mumble']['channel'], "<b>#{event.from}(#{event.channel}):</b> #{content}".irc_colors)
              puts "[IRC->Mumble] #{event.from}[#{event.channel}]: #{content}"
            end
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
      prefix_config = APP_CONFIG['prefix']
      prefix_current = command.slice!(0)
      command.downcase!

      if prefix_current == prefix_config
        case command
          when 'help'
            help_msg = "shellnut v#{VERSION} - available commands:<br/>"
            APP_CONFIG['help'].each do |cmd|
              help_msg += "<b>#{prefix_config}#{cmd['command']}</b> - #{cmd['description']}<br/>"
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
      puts "[Mumble] #{name} connected"
      APP_CONFIG['irc']['channel'].each do |channel|
        irc.send_message(channel, "\x039[+]\x0F \x02#{name}\x0f connected to #{APP_CONFIG['mumble']['server']}")
      end
    end

    mumble.on_user_remove do |x|
      next unless APP_CONFIG['mumble']['announce_joins']
      user = mumble.users[x['session']]
      next if user.nil?
      name = user.name.gsub("\n", '')
      puts "[Mumble] #{name} disconnected"
      APP_CONFIG['irc']['channel'].each do |channel|
        irc.send_message(channel, "\x034[-]\x0F \x02#{name}\x0f disconnected from #{APP_CONFIG['mumble']['server']}")
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
