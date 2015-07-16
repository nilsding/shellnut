module Mumble
  class Client
    alias super_init initialize
    # ./lib/mumble-ruby/client.rb:14
    def initialize(host, port=64738, username="RubyClient", password="")
      @after_callbacks = Hash.new { |h, k| h[k] = [] }
      super_init host, port, username, password
      yield(@config) if block_given?
    end
    
    # Joins the channel with the most users
    # @param default_channel [String] The channel to join if there are no other users on the Mumble server.
    def join_channel_with_most_users(default_channel = APP_CONFIG['mumble']['channel'])
      # this is probably the best one-liner I've ever written in Ruby so far; and it even works!  --nilsding
      chans_with_users = users.values.map{ |x| channels[x.channel_id] unless x == me || x.muted? || x.deafened? }.compact.inject(Hash.new(0)){ |h, c| h[c] += 1; h }.sort_by{ |_k, v| v }.reverse
      if chans_with_users.empty?
        writeln! "[Mumble] Looks like we're alone, joining channel \033[1m#{default_channel}\033[0m."
        join_channel default_channel
        return
      end
      chan_with_most_users = chans_with_users.first
      writeln! "[Mumble] Joining channel \033[1m#{chan_with_most_users[0].name}\033[0m, as there are #{chan_with_most_users[1]} users in it."
      join_channel chan_with_most_users[0]
    end
    
    # Returns the current channel the bot is in.
    # @return [Mumble::Channel] The current channel.
    def current_channel
      channels[me.channel_id]
    end
    
    Messages.all_types.each do |msg_type|
      # I needed a way to guarantee that a block runs after a specific callback finished.
      define_method "after_#{msg_type}" do |&block|
        @after_callbacks[msg_type] << block
      end
    end
    
    private
    # ./lib/mumble-ruby/client.rb:138
    def run_callbacks(sym, *args)
      @callbacks[sym].each { |c| c.call *args }
      @after_callbacks[sym].each { |c| c.call *args }
    end
    
    #  small hack to not spam the console output
    def writeln!(msg)
      puts msg unless msg == @last_message
      @last_message = msg
    end
  end
end
