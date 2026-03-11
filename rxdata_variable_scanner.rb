# rxdata_variable_scanner.rb
# Scans all rxdata map files for event commands that write to a specific game variable.
#
# Usage:
#   ruby rxdata_variable_scanner.rb [variable_id]
#
# Examples:
#   ruby rxdata_variable_scanner.rb 51    # Find all writes to variable 51 (trainer ALS difficulty)
#   ruby rxdata_variable_scanner.rb 67    # Find all writes to variable 67 (cycle number)
#   ruby rxdata_variable_scanner.rb       # Defaults to variable 51
#
# Searches for:
#   - Control Variable commands (code 122) that target the variable
#   - Script calls (code 355/655) that reference $game_variables[N]
#
# Control Variable parameter format: [start_var, end_var, operation, operand_type, operand]
#   Operation:    0=Set, 1=Add, 2=Sub, 3=Mul, 4=Div, 5=Mod
#   Operand type: 0=constant, 1=variable reference

# --- RPG Maker XP class stubs for Marshal ---
module RPG
  class Map
    attr_accessor :events, :tileset_id, :autoplay_bgm, :bgm, :autoplay_bgs, :bgs,
                  :encounter_list, :encounter_step, :data, :width, :height
  end
  class Event
    attr_accessor :id, :name, :x, :y, :pages
  end
  class Event::Page
    attr_accessor :condition, :graphic, :move_type, :move_speed, :move_frequency,
                  :move_route, :walk_anime, :step_anime, :direction_fix, :through,
                  :always_on_top, :trigger, :list
  end
  class Event::Page::Condition
    attr_accessor :switch1_valid, :switch2_valid, :variable_valid, :self_switch_valid,
                  :switch1_id, :switch2_id, :variable_id, :variable_value, :self_switch_ch
  end
  class Event::Page::Graphic
    attr_accessor :tile_id, :character_name, :character_hue, :direction, :pattern,
                  :opacity, :blend_type
  end
  class EventCommand
    attr_accessor :code, :indent, :parameters
  end
  class MoveRoute
    attr_accessor :repeat, :skippable, :list
  end
  class MoveCommand
    attr_accessor :code, :parameters
  end
  class AudioFile
    attr_accessor :name, :volume, :pitch
  end
  class MapInfo
    attr_accessor :name, :parent_id, :order, :expanded, :scroll_x, :scroll_y
  end
end

class Table
  attr_accessor :data
  def self._load(data)
    t = Table.new; t.data = data; t
  end
  def _dump(level)
    @data || ""
  end
end

class Tone
  attr_accessor :red, :green, :blue, :gray
  def initialize(r = 0, g = 0, b = 0, gr = 0)
    @red = r; @green = g; @blue = b; @gray = gr
  end
  def self._load(data)
    t = Tone.new; t.red, t.green, t.blue, t.gray = data.unpack("d4"); t
  end
  def _dump(level)
    [@red, @green, @blue, @gray].pack("d4")
  end
end

class Color
  attr_accessor :red, :green, :blue, :alpha
  def initialize(r = 0, g = 0, b = 0, a = 255)
    @red = r; @green = g; @blue = b; @alpha = a
  end
  def self._load(data)
    c = Color.new; c.red, c.green, c.blue, c.alpha = data.unpack("d4"); c
  end
  def _dump(level)
    [@red, @green, @blue, @alpha].pack("d4")
  end
end

# --- Main ---

DATA_DIR = File.join(File.dirname(__FILE__), "Data")
VAR_ID = (ARGV[0] || 51).to_i

OPERATIONS = { 0 => "Set", 1 => "Add", 2 => "Sub", 3 => "Mul", 4 => "Div", 5 => "Mod" }

infos = Marshal.load(File.binread(File.join(DATA_DIR, "MapInfos.rxdata")))

puts "=== Scanning for writes to variable #{VAR_ID} ==="
puts

count = 0
Dir.glob(File.join(DATA_DIR, "Map[0-9][0-9][0-9].rxdata")).sort.each do |f|
  mid = File.basename(f)[3, 3].to_i
  map = Marshal.load(File.binread(f))
  next unless map.events

  map.events.each do |eid, ev|
    next unless ev && ev.pages
    ev.pages.each_with_index do |page, pi|
      next unless page.list
      page.list.each_with_index do |cmd, ci|
        if cmd.code == 122 && cmd.parameters[0] <= VAR_ID && cmd.parameters[1] >= VAR_ID
          mname = infos[mid] ? infos[mid].name : "???"
          op = OPERATIONS[cmd.parameters[2]] || "Op#{cmd.parameters[2]}"
          operand = cmd.parameters[3] == 0 ? cmd.parameters[4].to_s : "var[#{cmd.parameters[4]}]"
          puts "Map#{"%03d" % mid} (#{mname}) Event #{eid} (#{ev.name}) Page #{pi + 1} Cmd #{ci}: #{op} #{operand}  #{cmd.parameters.inspect}"
          count += 1
        end
        if (cmd.code == 355 || cmd.code == 655) && cmd.parameters[0].to_s =~ /variables\[#{VAR_ID}\]/
          mname = infos[mid] ? infos[mid].name : "???"
          puts "Map#{"%03d" % mid} (#{mname}) Event #{eid} (#{ev.name}) Page #{pi + 1} Cmd #{ci}: [Script] #{cmd.parameters[0]}"
          count += 1
        end
      end
    end
  end
end

puts
puts "Total: #{count} commands found."
