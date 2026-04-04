#===============================================================================
# Debug Utilities
#===============================================================================

#-------------------------------------------------------------------------------
# Override PBDebug to always write to debuglog.txt regardless of $DEBUG.
# Only the latest battle's logs are kept (file cleared at battle start).
# Console output (echoln) still requires $DEBUG.
#-------------------------------------------------------------------------------
module PBDebug
  FLUSH_THRESHOLD = 50   # flush to disk every N buffered lines

  def self.flush
    if @@log.length > 0
      File.open("Data/debuglog.txt", "a+b") { |f| f.write(@@log.join) }
    end
    @@log.clear
  end

  def self.maybe_flush
    PBDebug.flush if @@log.length >= FLUSH_THRESHOLD
  end

  def self.log(msg)
    echoln(msg.gsub("%", "%%")) if $DEBUG
    @@log.push(msg + "\r\n")
    PBDebug.maybe_flush
  end

  def self.log_header(msg)
    echoln(Console.markup_style(msg.gsub("%", "%%"), text: :light_purple)) if $DEBUG
    @@log.push(msg + "\r\n")
    PBDebug.maybe_flush
  end

  def self.log_message(msg)
    msg = "\"" + msg + "\""
    echoln(Console.markup_style(msg.gsub("%", "%%"), text: :dark_gray)) if $DEBUG
    @@log.push(msg + "\r\n")
    PBDebug.maybe_flush
  end

  def self.log_ai(msg)
    msg = "[AI] " + msg
    echoln(msg.gsub("%", "%%")) if $DEBUG
    @@log.push(msg + "\r\n")
    PBDebug.maybe_flush
  end

  def self.log_score_change(amt, msg)
    sign     = (amt > 0) ? "+" : "-"
    amt_text = sprintf("%3d", amt.abs)
    plain    = "     #{sign}#{amt_text}: #{msg}"
    if $DEBUG
      color = (amt > 0) ? :light_green : :light_red
      echoln Console.markup_style(plain.gsub("%", "%%"), text: color)
    end
    @@log.push(plain + "\r\n")
    PBDebug.maybe_flush
  end
end

# Clear debuglog.txt at the start of each battle (keeps only latest battle)
class Battle
  alias _clear_debuglog_pbStartBattle pbStartBattle
  def pbStartBattle
    File.open("Data/debuglog.txt", "w") { |f| }
    _clear_debuglog_pbStartBattle
  end
end

#===============================================================================
# ■ Test Trainers — Debug "Give demo party" Override

#   Loads competitive test parties from trainers.txt (ACETRAINER2_F, test, 1~10)
#   Auto-grants Mega Ring, Tera Orb, Dynamax Band, Z-Ring on party load.
#===============================================================================

TEST_TRAINER_LIST = [
  { label: "1: Hyper Offense",   version: 1  },
  { label: "2: Bulky Stall",     version: 2  },
  { label: "3: Setup Sweeper",   version: 3  },
  { label: "4: Trick Room",      version: 4  },
  { label: "5: Rain Team",       version: 5  },
  { label: "6: Hazard Stack",    version: 6  },
  { label: "7: Pivot VoltTurn",  version: 7  },
  { label: "8: Status Spread",   version: 8  },
  { label: "9: Mixed Attacker",  version: 9  },
  { label: "10: Screen Setup",   version: 10 },
]

TEST_TRAINER_TYPE = :ACETRAINER2_F
TEST_TRAINER_NAME = "test"

# Key items needed for battle mechanics
TEST_PARTY_KEY_ITEMS = [:MEGARING, :TERAORB, :DYNAMAXBAND, :ZRING]

#===============================================================================
# ■ Override: Debug Menu "Give demo party" → Test Trainer Selector (PBS-based)
#===============================================================================
MenuHandlers.add(:debug_menu, :give_demo_party, {
  "name"        => _INTL("Give demo party"),
  "parent"      => :pokemon_menu,
  "description" => _INTL("Choose a test trainer's competitive party from PBS. Overwrites current party."),
  "effect"      => proc {
    commands = TEST_TRAINER_LIST.map { |t| t[:label] }
    cmd = pbShowCommands(nil, commands, -1)
    if cmd >= 0
      entry = TEST_TRAINER_LIST[cmd]
      # Load trainer from PBS (trainers.txt → compiled data)
      trainer = pbLoadTrainer(TEST_TRAINER_TYPE, TEST_TRAINER_NAME, entry[:version])
      if trainer && trainer.party && !trainer.party.empty?
        $player.party.clear
        trainer.party.each do |pkmn|
          cloned = pkmn.clone
          $player.party.push(cloned)
          $player.pokedex.register(cloned)
          $player.pokedex.set_owned(cloned.species)
        end
        #---------------------------------------------------------------
        # Grant key items for battle mechanics (Mega / Tera / Dynamax / Z)
        #---------------------------------------------------------------
        TEST_PARTY_KEY_ITEMS.each do |item|
          next unless GameData::Item.exists?(item)
          $bag.add(item, 1) if !$bag.has?(item)
        end
        # Charge Tera Orb so Terastallization is immediately usable
        $player.tera_charged = true if $player.respond_to?(:tera_charged=)
        pbMessage(_INTL("Loaded party: {1}  ({2} Pokémon)\nMega Ring, Tera Orb, Dynamax Band, Z-Ring granted.",
                         entry[:label], $player.party.length))
      else
        pbMessage(_INTL("Failed to load trainer data for version {1}. Compile PBS first.", entry[:version]))
      end
    end
  }
})

#===============================================================================
# ■ Filtered TrainerBattleLister — filters by name substring
#===============================================================================
class FilteredTrainerBattleLister < TrainerBattleLister
  def initialize(filter, selection = 0)
    super(selection, false)
    @filter = filter.downcase
  end

  def commands
    @commands.clear
    @ids.clear
    cmds = []
    idx = 1
    GameData::Trainer.each do |trainer|
      next unless trainer.real_name.downcase.include?(@filter)
      cmds.push([idx, trainer.trainer_type, trainer.real_name, trainer.version])
      idx += 1
    end
    cmds.sort! do |a, b|
      if a[1] == b[1]
        (a[2] == b[2]) ? a[3] <=> b[3] : a[2].downcase <=> b[2].downcase
      else
        a[1].to_s.downcase <=> b[1].to_s.downcase
      end
    end
    cmds.each do |t|
      if t[3] > 0
        @commands.push(_INTL("{1} {2} ({3}) x{4}",
                             GameData::TrainerType.get(t[1]).name, t[2], t[3],
                             GameData::Trainer.get(t[1], t[2], t[3]).pokemon.length))
      else
        @commands.push(_INTL("{1} {2} x{3}",
                             GameData::TrainerType.get(t[1]).name, t[2],
                             GameData::Trainer.get(t[1], t[2], t[3]).pokemon.length))
      end
      @ids.push([t[1], t[2], t[3]])
    end
    @index = @selection
    @index = @commands.length - 1 if @index >= @commands.length
    @index = 0 if @index < 0
    return @commands
  end
end

#===============================================================================
# ■ Debug Menu: Search trainer by name and start a battle
#===============================================================================
MenuHandlers.add(:debug_menu, :search_trainer_battle, {
  "name"        => _INTL("Search trainer battle"),
  "parent"      => :battle_menu,
  "description" => _INTL("Search trainers by name and start a single battle."),
  "effect"      => proc {
    query = pbMessageFreeText(_INTL("Enter trainer name:"), "", false, 30)
    query = query.strip
    next false if query == ""
    trainerdata = pbListScreen(_INTL("TRAINERS: \"{1}\"", query), FilteredTrainerBattleLister.new(query))
    if trainerdata
      setBattleRule("canLose")
      # Normalize all levels to 50
      EventHandlers.add(:on_trainer_load, :debug_level_normalize,
        proc { |trainer|
          next if !trainer
          trainer.party.each { |p| p.level = 50; p.calc_stats }
        }
      )
      orig_levels = $player.party.map { |p| p.level }
      $player.party.each { |p| p.level = 50; p.calc_stats; p.heal }
      begin
        TrainerBattle.start(trainerdata[0], trainerdata[1], trainerdata[2])
      ensure
        EventHandlers.remove(:on_trainer_load, :debug_level_normalize)
        $player.party.each_with_index do |p, i|
          p.level = orig_levels[i] if orig_levels[i]
          p.calc_stats
        end
      end
    end
    next false
  }
})
