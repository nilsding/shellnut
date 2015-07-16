module Mumble  
  class User < Model
    # ./lib/mumble-ruby/user.rb:35
    def muted?
      !!data['suppress'] || !!data['mute'] || !!self_mute
    end

    # ./lib/mumble-ruby/user.rb:39
    def deafened?
      !!data['deaf'] || !!self_deaf
    end
  end
end 
