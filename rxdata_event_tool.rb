# rxdata_event_tool.rb
# Tool for inspecting and batch-copying RPG Maker XP event commands across maps.
#
# Usage:
#   ruby rxdata_event_tool.rb <mode> [options]
#
# Modes:
#   inspect <map_id> <event_id>
#     Show event page structure and commands for the given event.
#     Example: ruby rxdata_event_tool.rb inspect 91 12
#
#   find_by_var <var_id> <value>
#     Find all events with a page condition checking variable >= value.
#     Example: ruby rxdata_event_tool.rb find_by_var 94 15
#
#   copy <src_map> <src_event> <var_id> <value>
#     Copy commands from source event page 1 to all events whose page condition
#     checks variable >= value. Preserves page conditions, graphics, triggers, etc.
#     Example: ruby rxdata_event_tool.rb copy 91 12 94 15
#
#   copy --dry-run <src_map> <src_event> <var_id> <value>
#     Same as copy but only lists what would be changed without writing files.

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

# --- Helpers ---

DATA_DIR = File.join(File.dirname(__FILE__), "Data")

def load_map(map_id)
  path = File.join(DATA_DIR, "Map%03d.rxdata" % map_id)
  Marshal.load(File.binread(path))
end

def save_map(map_id, map)
  path = File.join(DATA_DIR, "Map%03d.rxdata" % map_id)
  File.binwrite(path, Marshal.dump(map))
end

def map_infos
  @map_infos ||= Marshal.load(File.binread(File.join(DATA_DIR, "MapInfos.rxdata")))
end

def map_name(map_id)
  info = map_infos[map_id]
  info ? info.name : "???"
end

def all_map_ids
  Dir.glob(File.join(DATA_DIR, "Map[0-9][0-9][0-9].rxdata")).map { |f|
    File.basename(f)[3, 3].to_i
  }.sort
end

def cmd_desc(cmd)
  case cmd.code
  when 0   then nil
  when 101 then "[Show Text] #{cmd.parameters.inspect}"
  when 401 then "  text: #{cmd.parameters[0]}"
  when 102 then "[Show Choices] #{cmd.parameters.inspect}"
  when 402 then "[When Choice] #{cmd.parameters.inspect}"
  when 404 then "[End Choices]"
  when 108 then "[Comment] #{cmd.parameters[0]}"
  when 408 then "  comment cont: #{cmd.parameters[0]}"
  when 111 then "[Cond Branch] #{cmd.parameters.inspect}"
  when 411 then "[Else]"
  when 412 then "[End Branch]"
  when 112 then "[Loop]"
  when 113 then "[Break Loop]"
  when 413 then "[End Loop]"
  when 117 then "[Call Common Event] #{cmd.parameters[0]}"
  when 121 then "[Control Switch] #{cmd.parameters.inspect}"
  when 122 then "[Control Variable] #{cmd.parameters.inspect}"
  when 201 then "[Transfer Player] #{cmd.parameters.inspect}"
  when 250 then "[Play SE]"
  when 355 then "[Script] #{cmd.parameters[0]}"
  when 655 then "  script cont: #{cmd.parameters[0]}"
  else          "[Code #{cmd.code}] #{cmd.parameters.inspect}"
  end
end

def find_events_by_page_var(var_id, value)
  results = []
  all_map_ids.each do |mid|
    map = load_map(mid)
    next unless map.events
    map.events.each do |eid, ev|
      next unless ev && ev.pages
      ev.pages.each_with_index do |page, pi|
        if page.condition && page.condition.variable_valid &&
           page.condition.variable_id == var_id &&
           page.condition.variable_value >= value
          results << { map_id: mid, event_id: eid, event_name: ev.name, page: pi + 1,
                       var_value: page.condition.variable_value,
                       cmd_count: page.list ? page.list.size : 0 }
        end
      end
    end
  end
  results
end

# --- Modes ---

mode = ARGV.shift

case mode
when "inspect"
  map_id = ARGV.shift.to_i
  event_id = ARGV.shift.to_i
  map = load_map(map_id)
  ev = map.events[event_id]
  abort "Event #{event_id} not found in Map#{"%03d" % map_id}!" unless ev
  puts "=== Map#{"%03d" % map_id} (#{map_name(map_id)}) Event #{ev.id} (#{ev.name}) ==="
  puts "Pages: #{ev.pages.size}"
  ev.pages.each_with_index do |page, i|
    puts "  Page #{i + 1}: #{page.list.size} commands"
    page.list.each_with_index do |cmd, ci|
      desc = cmd_desc(cmd)
      puts "    #{ci}: #{desc}" if desc
    end
  end

when "find_by_var"
  var_id = ARGV.shift.to_i
  value = ARGV.shift.to_i
  results = find_events_by_page_var(var_id, value)
  puts "=== Events with page condition var[#{var_id}] >= #{value} ==="
  results.each do |r|
    puts "  Map#{"%03d" % r[:map_id]} (#{map_name(r[:map_id])}) Event #{r[:event_id]} (#{r[:event_name]}) Page #{r[:page]} [#{r[:cmd_count]} cmds]"
  end
  puts "\nTotal: #{results.size}"

when "copy"
  dry_run = ARGV.include?("--dry-run")
  ARGV.delete("--dry-run")
  src_map_id = ARGV.shift.to_i
  src_event_id = ARGV.shift.to_i
  var_id = ARGV.shift.to_i
  value = ARGV.shift.to_i

  src_map = load_map(src_map_id)
  src_ev = src_map.events[src_event_id]
  abort "Source event #{src_event_id} not found in Map#{"%03d" % src_map_id}!" unless src_ev
  src_commands = Marshal.dump(src_ev.pages[0].list)
  src_cmd_count = src_ev.pages[0].list.size

  targets = find_events_by_page_var(var_id, value)
  targets.reject! { |r| r[:map_id] == src_map_id && r[:event_id] == src_event_id }

  puts dry_run ? "=== Dry Run ===" : "=== Applying Changes ==="
  changed_maps = {}
  targets.each do |r|
    changed_maps[r[:map_id]] ||= load_map(r[:map_id])
    map = changed_maps[r[:map_id]]
    page = map.events[r[:event_id]].pages[r[:page] - 1]
    old_count = page.list ? page.list.size : 0
    page.list = Marshal.load(src_commands) unless dry_run
    puts "  Map#{"%03d" % r[:map_id]} (#{map_name(r[:map_id])}) Event #{r[:event_id]} (#{r[:event_name]}) Page #{r[:page]}: #{old_count} -> #{src_cmd_count} cmds"
  end

  unless dry_run
    changed_maps.each { |mid, map| save_map(mid, map) }
  end
  puts "\nTotal: #{targets.size} event pages #{dry_run ? "would be" : ""} updated"

else
  puts <<~HELP
    Usage: ruby rxdata_event_tool.rb <mode> [options]

    Modes:
      inspect <map_id> <event_id>         Show event structure and commands
      find_by_var <var_id> <value>         Find events with page condition var >= value
      copy <src_map> <src_event> <var_id> <value>          Copy commands to matching events
      copy --dry-run <src_map> <src_event> <var_id> <value>  Preview without writing
  HELP
end
