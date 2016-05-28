#!/usr/bin/env ruby

require "rubygems"
require "IRC"
require "mumble-ruby"

$LOAD_PATH.unshift File.expand_path './lib', File.dirname(__FILE__)

require "irc_colors"
require "ext/mumble-ruby"

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

# Optional: Twitter support (only if consumer key is given)
twitter_client = nil
unless APP_CONFIG['twitter']['consumer_key'].empty?
  twitter_client = Twitter::REST::Client.new do |config|
    config.consumer_key        = APP_CONFIG['twitter']['consumer_key']
    config.consumer_secret     = APP_CONFIG['twitter']['consumer_secret']
    config.access_token        = APP_CONFIG['twitter']['access_token']
    config.access_token_secret = APP_CONFIG['twitter']['access_token_secret']
  end
end

irc = IRC.new(APP_CONFIG['irc']['nickname'],
              APP_CONFIG['irc']['server'],
              APP_CONFIG['irc']['port'],
              APP_CONFIG['irc']['realname'])

def start(irc, mumble, twitter_client)
  #IRC
  @irc_thread ||= Thread.new do
    IRCEvent.add_callback('whoreply') do |event|
      unless event.stats[7] == APP_CONFIG['irc']['nickname']
        realname = event.message
        realname.slice! "0 "
        $irc_channel = event.channel
        $irc_users << {nickname: event.stats[7], realname: realname }
      end
    end # add_callback 'whoreply'

    IRCEvent.add_callback 'endofwho' do |event|
      sleep(2)
      user_msg = "There are currently #{$irc_users.count} users connected to #{$irc_channel} on #{APP_CONFIG['irc']['server']}<br/>"
      $irc_users.each do |user|
        user_msg += "<b>#{user[:nickname]}</b> (#{user[:realname]}) <br/>"
      end
      mumble.text_channel(mumble.current_channel, user_msg)
      user_msg = ""
      $irc_users = []
      $irc_channel = ""
    end # add_callback 'endofwho'

    IRCEvent.add_callback 'join' do |event|
      next unless APP_CONFIG['irc']['announce_joins']
      unless event.from == APP_CONFIG['irc']['nickname']
        puts "[IRC] #{event.from} joined #{event.channel}"
        mumble.text_channel(mumble.current_channel, "<b>#{event.from}</b> joined #{event.channel}")
      end
    end # add_callback 'join'

    IRCEvent.add_callback 'part' do |event|
      next unless APP_CONFIG['irc']['announce_joins']
      unless event.from == APP_CONFIG['irc']['nickname']
        puts "[IRC] #{event.from} left #{event.channel}"
        mumble.text_channel(mumble.current_channel, "<b>#{event.from}</b> left #{event.channel}")
      end
    end # add_callback 'part'

    IRCEvent.add_callback 'quit' do |event|
      next unless APP_CONFIG['irc']['announce_joins']
      unless event.from == APP_CONFIG['irc']['nickname']
        puts "[IRC] #{event.from} disconnected from the server"
        mumble.text_channel(mumble.current_channel, "<b>#{event.from}</b> disconnected from #{APP_CONFIG['irc']['server']}")
      end
    end # add_callback 'quit'

    IRCEvent.add_callback 'nick' do |event|
      next unless APP_CONFIG['irc']['announce_nicks']
      puts "[IRC] #{event.from} is now known as #{event.channel}"
       mumble.text_channel(mumble.current_channel, "<i>#{event.from}</i> is now known as <b>#{event.channel}</b>")
    end # add_callback 'nick'

    IRCEvent.add_callback 'privmsg' do |event|
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
          irc.send_message(event.channel, "I'm currently in the channel \x02#{mumble.current_channel.name}\x0f.")
          unless mumble.users.count == 0
            mumble.users.each do |user|
              unless user[1].name == APP_CONFIG['mumble']['username']
                channel_name = if mumble.channels[user[1].channel_id].nil?
                                 "Server Root"
                               else
                                 mumble.channels[user[1].channel_id].name
                               end
                irc.send_message(event.channel, "\x02#{user[1].name.sub("\n", '')}\x02 in \x02#{channel_name} #{"\x034[muted]\x0f" if user[1].muted?}#{"\x038[deafened]\x0f" if user[1].deafened?}\x02")
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
              mumble.text_channel(mumble.current_channel, "<b>#{event.from}(#{event.channel}):</b> #{content}".irc_colors)
              puts "[IRC->Mumble] #{event.from}[#{event.channel}]: #{content}"
            end
        end
      end
    end # add_callback 'privmsg'

    IRCEvent.add_callback 'endofmotd' do |event|
      puts "[IRC] Connected to server #{APP_CONFIG['irc']['server']}"
      APP_CONFIG['irc']['channel'].each do |channel|
        irc.add_channel(channel)
        puts "[IRC] Joined channel: #{channel}"
      end
    end # add_callback 'endofmotd'

    irc.connect
  end

  #Mumble
  @mumble_thread ||= Thread.new do

    mumble.on_text_message do |msg|
      message = msg.message.gsub(/\s+/m, ' ').strip.split(" ")
      command = message[0]
      next if command.nil?
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
            mumble.text_channel(mumble.current_channel, help_msg)
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
          when 'tweet'
            if twitter_client.nil?
              mumble.text_channel(mumble.current_channel, "Error: Twitter support is not enabled.")
              next
            end
            tweet_text = content.strip
            unless APP_CONFIG['twitter']['hashtag'].strip.empty?
              tweet_text += " ##{APP_CONFIG['twitter']['hashtag'].strip}"
            end
            actual_length = tweet_text.gsub(%r(https?://\S+), 'x' * 23).length
            if actual_length > 140
              hashtag_length = APP_CONFIG['twitter']['hashtag'].strip.empty? ? 0 : APP_CONFIG['twitter']['hashtag'].strip.length + 2
              mumble.text_channel(mumble.current_channel, "Tweet text too long, keep it under #{140 - hashtag_length} characters!")
              next
            end
            begin
              tweet = twitter_client.update tweet_text
              mumble.text_channel(mumble.current_channel, "==> <a href=\"#{tweet.url}\">#{tweet.url}</a>")
            rescue => e
              mumble.text_channel(mumble.current_channel, "Error: Twitter returned an error -- <font face=\"Comic Sans MS\">#{e.message}</font>")
            end
        end
      end
    end # on_text_message

    mumble.on_user_state do |state|
      next unless mumble.connected?
      next if mumble.users[state['actor']] == mumble.me
      if state.include? "name"
        next unless APP_CONFIG['mumble']['announce_joins']
        name = state['name'].gsub("\n", '')
        puts "[Mumble] #{name} connected"
        APP_CONFIG['irc']['channel'].each do |channel|
          irc.send_message(channel, "\x039[+]\x0F \x02#{name}\x0f connected to #{APP_CONFIG['mumble']['server']}")
        end
      end
    end # on_user_state
    
    mumble.after_user_state do |state|
      next unless mumble.connected?
      next if mumble.users[state['actor']] == mumble.me
      mumble.join_channel_with_most_users
    end # after_user_state

    mumble.on_user_remove do |x|
      next unless APP_CONFIG['mumble']['announce_joins']
      user = mumble.users[x['session']]
      next if user.nil?
      name = user.name.gsub("\n", '')
      puts "[Mumble] #{name} disconnected"
      APP_CONFIG['irc']['channel'].each do |channel|
        irc.send_message(channel, "\x034[-]\x0F \x02#{name}\x0f disconnected from #{APP_CONFIG['mumble']['server']}")
      end
    end # on_user_remove
    
    mumble.after_user_remove do
      mumble.join_channel_with_most_users
    end # after_user_remove

    mumble.on_connected do
      mumble.me.mute
      mumble.me.deafen
    end # on_connected

    mumble.on_server_sync do
      puts "[Mumble] Connected to server #{APP_CONFIG['mumble']['server']}"
      mumble.join_channel_with_most_users
    end # on_server_sync

    mumble.connect
  end

  @irc_thread.join
  @mumble_thread.join
end

start(irc, mumble, twitter_client)
