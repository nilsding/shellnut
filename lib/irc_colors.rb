#!/usr/bin/env ruby
 
BOLD  = '\x02'
COLOR = '\x03'
RESET = '\x0f'
 
COLORS = {
   0 => '#ffffff', # white
   1 => '#000000', # black
   2 => '#00007f', # blue
   3 => '#009300', # green
   4 => '#ff0000', # light red
   5 => '#7f0000', # brown
   6 => '#9c009c', # purple
   7 => '#fc7f00', # orange
   8 => '#ffff00', # yellow
   9 => '#00fc00', # light green
  10 => '#009393', # cyan
  11 => '#00ffff', # light cyan
  12 => '#0000fc', # light blue
  13 => '#ff00ff', # pink
  14 => '#7f7f7f', # grey
  15 => '#d2d2d2', # light grey
}
 
class String
  def irc_colors
    self.gsub! /#{COLOR}(\d{1,2})?(?:,(\d{1,2}))?/ do
      if $1
        "<font style='color: #{COLORS[$1.to_i]};#{$2 ? "background-color: #{COLORS[$2.to_i]}" : nil}'>"
      else
        "</font>"
      end
    end
 
    bold = false
    self.gsub! /#{BOLD}/ do
      if bold
        bold = false
        "</strong>"
      else
        bold = true
        "<strong>"
      end
    end
    self.gsub! /#{RESET}/ do "</font></strong>" end
 
    self 
  end
end
