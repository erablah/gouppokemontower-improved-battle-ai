#===============================================================================
# Handles the overworld sprites for Raid Den events.
#===============================================================================
class RaidDenSprite
  def initialize(event, style, _viewport)
    @event       = event
    @style       = GameData::RaidType.get(style)
    @disposed    = false
    set_event_graphic
  end

  def dispose
    @event     = nil
    @style     = nil
    @disposed  = true
  end

  def disposed?
    @disposed
  end
  
  def update
    set_event_graphic
  end
  
  #-----------------------------------------------------------------------------
  # Sets the actual graphic for a Max Raid Den event.
  #-----------------------------------------------------------------------------
  def set_event_graphic
    return if !@style
    if pbResolveBitmap(_INTL("Graphics/Characters/") + @style.den_sprite)
      @event.width = @event.height = @style.den_size
      @event.character_name = @style.den_sprite.split("/").last
      pkmn = @event.variable
      case pkmn
      when 0
        @event.turn_down
      when Array
        turnRight = false
        flags = pkmn[0].species_data.flags
        case @style.id
        when :Basic then turnRight = flags.include?("Legendary") || flags.include?("Mythical")
        when :Ultra then turnRight = pkmn[0].ultra? || flags.include?("UltraBeast")
        when :Max   then turnRight = pkmn[0].isSpecies?(:CALYREX)
        when :Tera  then turnRight = pkmn[0].tera_form? || flags.include?("Paradox")
        end
        (turnRight) ? @event.turn_right : @event.turn_left
      else
        @event.turn_up
      end
    end
  end
end

#===============================================================================
# Raid Den call used to initiate a raid battle.
#===============================================================================
def pbRaidDen(pkmn = {}, rules = {})
  interp = pbMapInterpreter
  event = interp.get_self
  return if !event
  GameData::RaidType.each_available do |r|
    name = r.event_name.downcase
    next if !event.name[/#{name}/i]
    rules[:style] = r.id
    break
  end
  rules[:raid_den] = true
  raid_pkmn = interp.getVariable
  case raid_pkmn
  when 0
    if pbRaidDenReset(interp, event)
      return RaidBattle.start(pkmn, rules)
    else
      $game_temp.clear_battle_rules
      return false
    end
  when Array
    interp.setVariable(0)
	setBattleRule("editWildPokemon", {})
    return RaidBattle.start(*raid_pkmn)
  else
    interp.setVariable(nil)
    return RaidBattle.start(pkmn, rules)
  end
end

#===============================================================================
# Called when the player interacts with an empty den to manually reset it.
#===============================================================================
def pbRaidDenReset(interp, this_event)
  if $DEBUG && Input.press?(Input::CTRL)
    pbMessage(_INTL("새로운 포켓몬이 나타났다!"))
    interp.setVariable(nil)
    this_event.turn_up
    return true
  else
    item = GameData::Item.get(:RAIDBAIT)
    pbMessage(_INTL("여기에는 아무것도 없는 것 같다..."))
    if pbConfirmMessage(_INTL("포켓몬을 유인하기 위해 미끼를 던져볼까?", item.portion_name))
      if $bag.has?(item.id)
        pbMessage(_INTL("미끼를 던졌다!", item.portion_name))
        $bag.remove(item.id)
        interp.setVariable(nil)
        this_event.turn_up
        return true
      else
        pbMessage(_INTL("하지만 미끼가 없다...", item.portion_name_plural))
      end
    end
  end
  return false
end

#===============================================================================
# Utility to empty or reset all Raid Dens on all maps.
#===============================================================================
def pbClearAllRaids(reset = false)
  set = (reset) ? nil : 0
  name = GameData::RaidType::RAID_DEN_SUFFIX.downcase 
  $PokemonGlobal.eventvars = {} if !$PokemonGlobal.eventvars
  GameData::MapMetadata.each do |map_data|
    file = sprintf("Data/Map%03d.rxdata", map_data.id)
    next if !FileTest.exist?(file)
    map = load_data(file)
    for event_id in 1..map.events.length
      event = map.events[event_id]
      next if !event || !event.name[/#{name}/i]
      $PokemonGlobal.eventvars[[map_data.id, event_id]] = set
    end
  end 
  # $PokemonGlobal.raid_timer = Time.now
  $game_map.update
end

#===============================================================================
# Defines when the last Raid Den update was to naturally reset dens each day.
# (이 클래스는 더 이상 사용되지 않지만 기존 스크립트 구조 유지를 위해 남겨둡니다.)
#===============================================================================
#class PokemonGlobalMetadata
#  def raid_timer
#    @raid_timer = Time.now if !@raid_timer
#    return @raid_timer
#  end
#  
#  def raid_timer=(value)
#    @raid_timer = Time.now if !@raid_timer
#    @raid_timer = value
#  end
#end

#-------------------------------------------------------------------------------
# Handler used to automatically reset all Raid Den events when the map changes.
# (맵 이동 시 초기화 로직으로 변경됨)
#-------------------------------------------------------------------------------
EventHandlers.add(:on_map_transfer, :raid_den_reset_on_map_change,
  proc {
    pbClearAllRaids(true)
  }
)

#-------------------------------------------------------------------------------
# Handler used to update the sprites of all Raid Den events on a map.
#-------------------------------------------------------------------------------
EventHandlers.add(:on_new_spriteset_map, :add_raid_den_graphics,
  proc { |spriteset, viewport|
    dens = []
    GameData::RaidType.each_available { |r| dens.push([r.id, r.event_name.downcase]) }
    spriteset.map.events.each do |event|
      char = event[1]
      dens.each do |den|
        next if !char.name[/#{den[1]}/i]
        spriteset.addUserSprite(RaidDenSprite.new(char, den[0], viewport))
      end
    end
  }
)

#===============================================================================
# Stores the schema used to translate a pastebin link into Raid Den data.
#===============================================================================
module LiveRaidEvent
  SCHEMA = {
    "Species"             => [:species,        "e",    :Species],
    "Form"                => [:form,           "v"],
    "Gender"              => [:gender,         "e",    {"M" => 0, "m" => 0, "Male" => 0, "male" => 0, "0" => 0,
                                                         "F" => 1, "f" => 1, "Female" => 1, "female" => 1, "1" => 1}],
    "AbilityIndex"        => [:ability_index,  "u"],
    "Moves"               => [:moves,          "*e",  :Move],
    "Item"                => [:item,           "e",    :Item],
    "Nature"              => [:nature,         "e",    :Nature],
    "IV"                  => [:iv,             "uUUUUU"],
    "EV"                  => [:ev,             "uUUUUU"],
    "Shiny"               => [:shiny,          "b"],
    "SuperShiny"          => [:super_shiny,    "b"],
    "GmaxFactor"          => [:gmax_factor,    "b"],
    "TeraType"            => [:tera_type,      "e",    :Type],
    "Memento"             => [:memento,        "e",    :Ribbon],
    "Scale"               => [:scale,          "u"],
    "HPLevel"             => [:hp_level,       "v"],
    "Immunities"          => [:immunities,     "*m"],
    "RaidStyle"           => [:style,          "e",    :RaidType],
    "RaidRank"            => [:rank,           "v"],
    "RaidSize"            => [:size,           "v"],
    "RaidPartner"         => [:partner,        "esUB", :TrainerType],
    "RaidTurns"           => [:turn_count,     "i"],
    "RaidKOs"             => [:ko_count,       "i"],
    "RaidShield"          => [:shield_hp,      "i"],
    "RaidActions"         => [:extra_actions,  "*m"],
    "RaidSupportMoves"    => [:support_moves,  "*e",  :Move],
    "RaidSpreadMoves"     => [:spread_moves,   "*e",  :Move],
    "RaidLoot"            => [:loot,           "*ev", :Item],
  }
end

#===============================================================================
# Reads a pastebin URL to acquire Raid Den data over the internet.
#===============================================================================
def pbLoadLiveRaidData
  lineno = 1
  species = [nil, 0]
  pkmn_data = {}
  raid_data = {
    :style   => :Basic,
    :online  => true,
    :raid_den => true
  }
  if nil_or_empty?(Settings::LIVE_RAID_EVENT_URL)
    return species, pkmn_data, raid_data
  end
  schema = LiveRaidEvent::SCHEMA
  data = pbDownloadToString(Settings::LIVE_RAID_EVENT_URL)
  data.each_line do |line|
    if lineno == 1 && line[0].ord == 0xEF && line[1].ord == 0xBB && line[2].ord == 0xBF
      line = line[3, line.length - 3]
    end
    line.force_encoding(Encoding::UTF_8)
    line = Compiler.prepline(line)
    FileLineData.setLine(line, lineno) if !line[/^\#/] && !line[/^\s*$/]
    next if !line[/^\s*(\w+)\s*=\s*(.*)$/]
    key = $~[1]
    property_value = Compiler.get_csv_record($~[2], schema[key])
    if ["IV", "EV"].include?(key)
      property_value = property_value.compact!
      property_value = property_value.first if property_value.length < 6
    end
    case key
    when "Species" then species[0] = property_value
    when "Form"    then species[1] = property_value
    else
      if key.include?("Raid")
        raid_data[schema[key][0]] = property_value
      else
        pkmn_data[schema[key][0]] = property_value
      end
    end
    lineno += 1
  end
  return species, pkmn_data, raid_data
end
#===============================================================================
# Main raid battle call.
#-------------------------------------------------------------------------------
# The "pkmn" hash accepts the following keys:
#-------------------------------------------------------------------------------
#   :type            => Filter by species type.
#   :habitat         => Filter by species habitat.
#   :generation      => Filter by species generation.
#   :encounter       => Filter by map encounter table.
#-------------------------------------------------------------------------------
# The "rules" hash accepts the following keys:
#-------------------------------------------------------------------------------
#   :rank            => Sets the raid rank.
#   :style           => Sets the raid type (Raid Dens ignore this).
#   :size            => Sets the battle size on the player's size.
#   :partner         => Sets a partner trainer.
#   :turn_count      => Sets the raid turn counter.
#   :ko_count        => Sets the raid KO counter.
#   :shield_hp       => Sets the raid shield HP.
#   :extra_actions   => Sets extra raid actions.
#   :support_moves   => Sets extra support moves.
#   :spread_moves    => Sets extra spread moves.
#   :loot            => Sets bonus loot (Raid Den only).
#   :online          => Sets the online status (Raid Den only).
#===============================================================================
class RaidBattle
  def self.start(pkmn = {}, rules = {})
    try_raid = GameData::RaidType.try_get(rules[:style])
    rules[:style] = :Basic if !try_raid || !try_raid.available
    #---------------------------------------------------------------------------
    # Checks for online Raid Den data.
    if rules[:raid_den] && !pkmn.is_a?(Pokemon)
      useOnlineData = (rules.has_key?(:online)) ? rules[:online] : rand(3) == 0
      rules[:online] = false
      if useOnlineData
        species, pkmn_data, raid_data = pbLoadLiveRaidData
        if !species[0].nil? && rules[:style] == raid_data[:style] && pbHasBadgesForRank(raid_data[:rank])
          setBattleRule("editWildPokemon", pkmn_data)
          pkmn = GameData::Species.get_species_form(*species).id
          rules = raid_data
        end
      end
    end
    #---------------------------------------------------------------------------
    # Sets up and validates general raid properties.
    rules[:rank] = pbDefaultRaidProperty(pkmn, :rank, rules) if !rules[:rank]
    # 🌟 FIX: rules[:rank].to_i를 사용하여 nil일 경우 안전하게 0으로 처리
    rules[:rank] = (rules[:rank].to_i > 0) ? [rules[:rank].to_i, 7].min : 1
    if rules[:partner]
      rules[:size] = 1
      setBattleRule("2v1")
    else
      if rules[:size]
        rules[:size] = 1 if rules[:size] <= 0
        rules[:size] = 3 if rules[:size] > 3
      else
        rules[:size] = (Settings::RAID_BASE_PARTY_SIZE > 0) ? [Settings::RAID_BASE_PARTY_SIZE, 3].min : 1
      end
      rules[:size] = $player.able_pokemon_count if $player.able_pokemon_count < rules[:size]
      setBattleRule(sprintf("%dv1", rules[:size]))
    end
    pkmn = self.generate_raid_foe(pkmn, rules)
    #---------------------------------------------------------------------------
    # Battle start.
    old_partner = $PokemonGlobal.partner
    pbDeregisterPartner
    if rules[:raid_den]
      decision = pbRaidDenEntry(pkmn, rules)
    else
      rules[:pokemon] = pkmn
      pbSetRaidProperties(rules)
      pbFadeOutIn { decision = WildBattle.start_core(pkmn) }
    end
    #---------------------------------------------------------------------------
    # Battle end.
    $PokemonGlobal.partner = old_partner
    $game_temp.transition_animation_data = nil
    if rules[:pokemon]
      EventHandlers.trigger(:on_wild_battle_end, 
        rules[:pokemon].species_data.id, rules[:pokemon].level, decision)
    end
    return [1, 4].include?(decision)
  end

  #-----------------------------------------------------------------------------
  # Generates the raid Pokemon based on entered data.
  #-----------------------------------------------------------------------------
  def self.generate_raid_foe(pkmn, rules)
    return pkmn if pkmn.is_a?(Pokemon)
    if pkmn.nil? || pkmn.is_a?(Hash)
      pkmn = {} if pkmn.nil?
      filter = []
      enc_list = $PokemonEncounters.get_encounter_list(pkmn[:encounter])
      raidRanks = GameData::Species.generate_raid_lists(rules[:style])
      raidRanks[rules[:rank]].each do |s|
        sp = GameData::Species.get(s)
        next if pkmn[:type]       && !sp.types.include?(pkmn[:type])
        next if pkmn[:habitat]    && sp.habitat != pkmn[:habitat]
        next if pkmn[:generation] && sp.generation != pkmn[:generation]
        next if pkmn[:encounter]  && !enc_list.include?(sp.id)
        filter.push(s)
      end
      pkmn = filter.sample
    end
    species = pbDefaultRaidProperty(pkmn, :species, rules)
    level = pbDefaultRaidProperty(species, :level, rules)
    pkmn = Pokemon.new(species, level)
    pkmn.setRaidBossAttributes(rules)
    return pkmn
  end
end

#===============================================================================
# Generates a list of eligible raid species when :encounter is set in "pkmn" hash.
#===============================================================================
class PokemonEncounters
  def get_encounter_list(enc_type)
    enc_list = []
    return enc_list if !enc_type
    species = []
    enc_type = find_valid_encounter_type_for_time(enc_type, pbGetTimeNow)
    return enc_list if !@encounter_tables[enc_type]
    @encounter_tables[enc_type].each do |enc| 
      next if species.include?(enc[1])
      species.push(enc[1])
    end
    species.each do |sp|
      sp_data = GameData::Species.get(sp)
      if MultipleForms.hasFunction?(sp, "getForm")
        try_pkmn = Pokemon.new(sp, 1)
        check_form = try_pkmn.form
      else
        check_form = sp_data.form
      end
      sp_data.get_family_species.each do |fam|
        if fam == sp
          enc_list.push(fam)
        else
          id = GameData::Species.get_species_form(fam, check_form).id
          base_form = GameData::Species.get(id).base_form
          next if base_form > 0 && base_form != check_form
          enc_list.push(id)
        end
      end
    end
    return enc_list
  end
end

#===============================================================================
# Returns whether the player has enough badges for a certain raid rank.
#===============================================================================
def pbHasBadgesForRank(rank)
  badges = $player.badge_count
  return true if !rank || badges >= 8
  return true if rank == 4 && badges >= 6
  return true if rank == 3 && badges >= 3
  return true if rank <= 2
  return false
end

#===============================================================================
# Applies all raid attributes to Pokemon in a raid setting.
#===============================================================================
class Pokemon

  #-----------------------------------------------------------------------------
  # Applies raid attributes to rental Pokemon.
  #-----------------------------------------------------------------------------
  def setRaidRentalAttributes(style = :Basic, rank = 4)
    self.shadow = nil if self.shadow
    #---------------------------------------------------------------------------
    # Various settings related to the raid style.
    self.dynamax_able = false if defined?(dynamax_able) && style != :Max
    self.terastal_able = false if defined?(terastal_able) && style != :Tera
    case style
    when :Ultra
      self.makeUnUltra
    when :Max
      self.dynamax_lvl = 1
      if species_data.gmax_move
        self.gmax_factor = true
        self.form = species_data.ungmax_form
      end
    when :Tera
      self.makeUnterastal
      self.tera_type = :Random if rank > 2
    end
    self.form
    #---------------------------------------------------------------------------
    # Compiles a moveset suited for raid battles.
    self.moves.clear
    moves_to_learn = []
    raid_moves = self.getRaidMoves(style, true).clone
    move_categories = [:other, :primary, :status]
    loop do
      move_categories.length.times do |i|
        category = move_categories[i]
        if !raid_moves.has_key?(category) || raid_moves[category].empty?
          move_categories[i] = nil
        else
          m = raid_moves[category].sample
          moves_to_learn.push(m) if !moves_to_learn.include?(m)
          raid_moves[category].delete(m)
          move_categories[i] = nil if raid_moves[category].empty?
          break if moves_to_learn.length >= MAX_MOVES
        end
      end
      move_categories.compact!
      break if move_categories.empty?
      break if moves_to_learn.length >= MAX_MOVES
    end
    moves_to_learn.each { |m| self.learn_move(m) }
    if style == :Ultra
      self.item = GameData::Item.get_compatible_crystal(self)
    end
    #---------------------------------------------------------------------------
    # May randomly set Hidden Ability.
    if !species_data.hidden_abilities.empty? && rank >= 3
      self.ability_index = 2 if rand(10) < rank
    end
    #---------------------------------------------------------------------------
    # Sets the IV's. (난이도 상향 IV 적용)
    case rank
    when 1 then maxIVs = 2 # 1 -> 2
    when 2 then maxIVs = 2 # 1 -> 2
    when 3 then maxIVs = 3 # 2 -> 3
    when 4 then maxIVs = 4 # 3 -> 4
    when 5 then maxIVs = 5 # 4 -> 5
    when 6 then maxIVs = 6 # 5 -> 6
    when 7 then maxIVs = 6
    end
    iv_stats = []
    GameData::Stat.each_main do |s|
      next if self.iv[s.id] == IV_STAT_LIMIT
      iv_stats.push(s.id)
    end
    tries = 0
    iv_stats.shuffle.each do |stat|
      break if tries >= maxIVs
      self.iv[stat] = IV_STAT_LIMIT
      tries += 1
    end
    #---------------------------------------------------------------------------
    # Sets the EV's.
    ev_stats = [nil, :DEFENSE, :SPECIAL_DEFENSE]
    ev_stats.push(:ATTACK) if self.moves.any? { |m| m.physical_move? }
    ev_stats.push(:SPECIAL_ATTACK) if self.moves.any? { |m| m.special_move? }
    ev_stats.push(:SPEED) if self.baseStats[:SPEED] > 60
    stat = ev_stats.sample
    self.ev[:HP] = EV_STAT_LIMIT
    if GameData::Stat.exists?(stat)
      self.ev[stat] = EV_STAT_LIMIT
    else
      GameData::Stat.each_main_battle do |s|
        self.ev[s.id] = (EV_STAT_LIMIT / 5).floor
      end
    end
    self.calc_stats
    self.heal
  end
  
  #-----------------------------------------------------------------------------
  # Applies raid attributes to wild Pokemon.
  #-----------------------------------------------------------------------------
# [000] Raid Battle - Setup.rb 파일 내의 Pokemon 클래스 내부를 수정하세요.

  def setRaidBossAttributes(rules)
    return if !species_data.raid_species?(rules[:style])
    editedPkmn = $game_temp.battle_rules["editWildPokemon"].clone
    #---------------------------------------------------------------------------
    # Sets default values for various attributes related to form and cosmetics.
    EventHandlers.trigger(:on_wild_pokemon_created, self)
    if pbInRaidAdventure?
      self.shiny = false
      self.super_shiny = false
    end
    self.shadow = nil if self.shadow
    self.form #if !species_data.raid_species?(rules[:style])
    #---------------------------------------------------------------------------
    # Applies various attributes related to the raid style.
    case rules[:style]
    when :Ultra
      if MultipleForms.hasFunction?(self, "getUltraItem")
        self.form_simple = 1 if isSpecies?(:NECROZMA)
        self.item = MultipleForms.call("getUltraItem", self)
        self.makeUltra
      elsif !self.hasZCrystal? && editedPkmn && editedPkmn[:moves]
        self.item = GameData::Item.get_compatible_crystal(self)
      end
    when :Max
      self.gmax_factor = true if species_data.gmax_move
      self.dynamax_lvl = 10
      self.dynamax = true
    when :Tera
      self.tera_type = :Random if rules[:rank] > 2 && !(editedPkmn && editedPkmn[:tera_type])
      self.terastallized = true
      self.forced_form = @form + 4 if isSpecies?(:OGERPON)
    end
    #---------------------------------------------------------------------------
    # Determines the max number of IV's and the amount of HP scaling to apply.
    case rules[:rank] # <<< 난이도 상향 IV 및 HP Boost 적용 (클린 코드)
    when 1 then maxIVs = 2; hpBoost = 6
    when 2 then maxIVs = 2; hpBoost = 8
    when 3 then maxIVs = 3; hpBoost = 10
    when 4 then maxIVs = 4; hpBoost = 14
    when 5 then maxIVs = 5; hpBoost = 22
    when 6 then maxIVs = 6; hpBoost = 26
    when 7 then maxIVs = 6; hpBoost = 32
    end
    hpBoost -= ((GameData::GrowthRate.max_level - self.level) / 10).floor - 1
    hpBoost = (hpBoost / 2).floor if rules[:style] == :Max
    hpBoost = 2 if hpBoost < 1
    #---------------------------------------------------------------------------
    # Forces required boss immunities if other immunities are already set.
    if editedPkmn && editedPkmn[:immunities]
      self.immunities.push(:RAIDBOSS, :FLINCH, :PPLOSS, :ITEMREMOVAL, :OHKO, :SELFKO, :ESCAPE)
      self.immunities.uniq!
    end
    #---------------------------------------------------------------------------
    # Forces the Mightiest Mark memento on Rank 7 raid bosses if no memento is set.
    if rules[:rank] == 7 && defined?(self.memento) && !(editedPkmn && editedPkmn[:memento])
      self.memento = :MIGHTIESTMARK
    end
    #---------------------------------------------------------------------------
    # Applies values if unset via the "editWildPokemon" battle rule.
    [:hp_level, :immunities, :ability_index, :iv, :moves].each do |property|
      next if editedPkmn && editedPkmn[property]
      case property
      #-------------------------------------------------------------------------
      # Applies boss HP scaling.
      when :hp_level
        self.hp_level = hpBoost
      #-------------------------------------------------------------------------
      # Applies boss immunities.
      when :immunities
        self.immunities = [:RAIDBOSS, :FLINCH, :PPLOSS, :ITEMREMOVAL, :OHKO, :SELFKO, :ESCAPE]
      #-------------------------------------------------------------------------
      # Has a chance to set Hidden Ability, based on rank.
      when :ability_index
        if !species_data.hidden_abilities.empty? && rules[:rank] >= 3
          self.ability_index = 2 if rand(10) < rules[:rank]
        end
      #-------------------------------------------------------------------------
      # Compiles moves suited for a raid boss.
      when :moves
        self.moves.clear
        moves_to_learn = []
        move_categories = [:primary, :secondary, :other, :status]
        raid_moves = self.getRaidMoves(rules[:style]).clone
        loop do
          move_categories.length.times do |i|
            category = move_categories[i]
            if !raid_moves.has_key?(category) || raid_moves[category].empty?
              move_categories[i] = nil
            else
              m = raid_moves[category].sample
              moves_to_learn.push(m) if !moves_to_learn.include?(m)
              raid_moves[category].delete(m)
              move_categories[i] = nil if raid_moves[category].empty?
              break if moves_to_learn.length >= MAX_MOVES
            end
          end
          move_categories.compact!
          break if move_categories.empty?
          break if moves_to_learn.length >= MAX_MOVES
        end
        moves_to_learn.each { |m| self.learn_move(m) }
        if raid_moves.has_key?(:support) && !rules.has_key?(:support_moves)
          rules[:support_moves] = raid_moves[:support]
        end
        if raid_moves.has_key?(:spread) && !rules.has_key?(:spread_moves)
          rules[:spread_moves] = raid_moves[:spread]
        end
        if rules[:style] == :Ultra && !self.hasZCrystal? && !self.ultra?
          self.item = GameData::Item.get_compatible_crystal(self)
        end
      #-------------------------------------------------------------------------
      # Sets the necessary number of max IV's, based on rank.
      when :iv
        stats = []
        GameData::Stat.each_main do |s|
          next if self.iv[s.id] == IV_STAT_LIMIT
          stats.push(s.id)
        end
        tries = 0
        stats.shuffle.each do |stat|
          break if tries >= maxIVs
          self.iv[stat] = IV_STAT_LIMIT
          tries += 1
        end
      end
    end
    self.calc_stats
  end
 end

#===============================================================================
# General utility for setting default raid property values.
#===============================================================================
def pbDefaultRaidProperty(pkmn, property, rules)
  rank = rules[:rank]
  case property
  #-----------------------------------------------------------------------------
  # Determines the species of the raid Pokemon in this raid battle.
  when :species
    species_data = GameData::Species.try_get(pkmn)
    return :DITTO if !species_data
    if species_data.form > 0 && !species_data.raid_species?(rules[:style])
      pkmn = species_data.species
      species_data = GameData::Species.get(pkmn)
      rules[:rank] = species_data.raid_ranks.sample if !species_data.raid_ranks.include?(rules[:rank])
    end
    pkmn = :DITTO if !species_data.raid_species?(rules[:style])
    return pkmn
  #-----------------------------------------------------------------------------
  # Determines the level of the raid Pokemon in this raid battle. (MAX LEVEL 300 반영 및 난이도 상향)
  when :level
    if rank.nil?
      case pkmn
      when Integer then rank = pkmn
      when Pokemon then rank = pkmn.species_data.raid_ranks.sample
      when Symbol  then rank = GameData::Species.get(pkmn).raid_ranks.sample
      end
    end
    case rank
    when 1 then return 15 + rand(6) # 10->15
    when 2 then return 25 + rand(6) # 20->25
    when 3 then return 35 + rand(6) # 30->35
    when 4 then return 45 + rand(6) # 40->45
    when 5 then return 70 + rand(6) # 65->70
    when 6 then return 80 + rand(6) # 75->80
    when 7 then return 100 # 100 -> 300 (최대 레벨 반영)
    else       return 1
    end
#-----------------------------------------------------------------------------
# Determines the rank for this raid battle.
when :rank
  case pkmn
  when Pokemon
    case pkmn.level
    when 0..19 then return 1
    when 20..29 then return 2
    when 30..39 then return 3
    when 40..64 then return 4
    when 65..74 then return 5
    when 75..99 then return 6
    else return 7
    end
  when Symbol
    pkmn = GameData::Species.try_get(pkmn)
    if pkmn && pkmn.raid_species?(rules[:style])
      raid_ranks = pkmn.raid_ranks
      return (rank && raid_ranks.include?(rank)) ? rank : raid_ranks.sample
    end
  end
  
  # --- **이 부분이 회차(Variable 67)를 사용하는 새로운 로직입니다** ---
  # Variable 67 (회차) 값 가져오기 (0부터 9까지)
  cycle = $game_variables[67] 
  
  odds = rand(100) # 난이도 변동을 위한 확률
  
  case cycle
  when 0
    # 회차 0: 주로 랭크 1, 가끔 랭크 2
    return (odds < 80) ? 1 : 2 
  when 1
    # 회차 1: 랭크 1, 2, 가끔 랭크 3
    return (odds < 80) ? 2 : 3
  when 2
    # 회차 2: 랭크 2, 가끔 랭크 3
    return (odds < 80) ? 3 : 4
  when 3
    # 회차 3: 랭크 2, 3, 가끔 랭크 4
    return (odds < 80) ? 4 : 5
  when 4
    # 회차 4: 주로 랭크 3, 가끔 랭크 4
    return (odds < 40) ? 4 : 5
  when 5
    # 회차 5: 주로 랭크 4, 가끔 랭크 5
    return (odds < 80) ? 5 : 6
  when 6
    # 회차 6: 주로 랭크 5, 가끔 랭크 6
    return (odds < 40) ? 5 : 6
  when 7
    # 회차 7: 랭크 5, 6 중 선택
    return (odds < 80) ? 6 : 7
  when 8
    # 회차 8: 주로 랭크 6, 아주 가끔 랭크 7
    return (odds < 40) ? 6 : 7
  when 9
    # 회차 9: 주로 랭크 7 (최고 난이도)
    return 7
  else
    # 회차가 0-9 범위를 벗어날 경우 기본값으로 랭크 1
    return 1 
  end
  # -----------------------------------------------------------------------------
  #-----------------------------------------------------------------------------
  # Determines the initial KO counter for this raid battle. (난이도 상향 KO 감소)
  when :ko_count
    size = (rules[:partner]) ? 2 : rules[:size]
    return 1 if size == 1
    return rules[:ko_count] if rules.has_key?(:ko_count)
    count = Settings::RAID_BASE_KNOCK_OUTS
    # count += 1 if size == 2 # 2인 파티 보너스 제거 (주석 처리로 난이도 상승)
    count += 1 if rank && rank > 5
    return count
  #-----------------------------------------------------------------------------
  # Determines the initial turn counter for this raid battle. (난이도 상향 턴 감소)
  when :turn_count
    return rules[:turn_count] if rules.has_key?(:turn_count)
    count = Settings::RAID_BASE_TURN_LIMIT
    size = ((rules[:partner]) ? 2 : rules[:size]) || Settings::RAID_BASE_PARTY_SIZE
    # count += size if size < 3 # 파티 크기에 따른 턴 보너스 제거 (주석 처리로 난이도 상승)
    count += (rank / 2).ceil if rank
    return count
  #-----------------------------------------------------------------------------
  # Determines the amount of HP raid Pokemon's shields will have in this raid battle. (난이도 상향 실드 HP 증가)
  when :shield_hp
    count = rules.has_key?(:shield_hp)
    return nil if count && !rules[:shield_hp]
    count = rules[:shield_hp]
    if rank && !count
      case rank
      when 1, 2 then count = 5 # 4->5
      when 3    then count = 6 # 5->6
      when 4    then count = 7 # 6->7
      when 5    then count = 8 # 7->8
      when 6, 7 then count = 9 # 8->9 (최대 8 제한 로직을 따름)
      end
      size = ((rules[:partner]) ? 2 : rules[:size]) || Settings::RAID_BASE_PARTY_SIZE
      count -= [2, 1, 0][size - 1]
    else
      count = 0 if !count
    end
    return (count > 8) ? 8 : count
  #-----------------------------------------------------------------------------
  # Determines the kinds of extra actions the raid Pokemon may perform.
  when :extra_actions
    return rules[:extra_actions] if rules.has_key?(:extra_actions)
    actions = []
    actions.push(:reset_drops)  if rank && rank >= 3
    actions.push(:reset_boosts) if rank && rank >= 4
    actions.push(:drain_cheer)  if rank && rank >= 5
    return actions
  end
end

#===============================================================================
# Applies all relevant battle rules and properties for a raid battle.
#===============================================================================
def pbSetRaidProperties(rules)
  $game_temp.transition_animation_data = [rules[:pokemon], rules[:style]]
  [:ko_count, :turn_count, :shield_hp, :extra_actions].each do |r|
    rules[r] = pbDefaultRaidProperty(rules[:pokemon], r, rules)
  end
  rules[:max_koCount] = rules[:ko_count]
  rules[:max_turnCount] = rules[:turn_count]
  raidType = GameData::RaidType.get(rules[:style])
  setBattleRule("raidBattle", rules)
  battleRules = $game_temp.battle_rules
  if !battleRules["backdrop"]
    bg = base = nil
    case battleRules["environment"]
    when raidType.battle_environ      then bg = raidType.battle_bg
    when :None                        then bg = "city"
    when :Grass, :TallGrass, :Puddle then bg = "field"
    when :MovingWater, :StillWater    then bg = "water"
    when :Underwater                  then bg = "underwater"
    when :Cave                        then bg = "cave3"
    when :Rock, :Volcano, :Sand       then bg = "rocky"
    when :Forest, :ForestGrass        then bg = "forest"
    when :Snow, :Ice                  then bg = "snow"
    when :Graveyard                   then bg = "distortion"
    end
    case battleRules["environment"]
    when raidType.battle_environ      then base = raidType.battle_base
    when :Grass, :TallGrass           then base = "grass"
    when :Sand                        then base = "sand"
    when :Ice                         then base = "ice"
    else                                   base = bg
    end
    setBattleRule("base", base) if base
    setBattleRule("backdrop", bg) if bg
  end
  if !battleRules["battleBGM"]
    bgm = raidType.battle_bgm
    if rules[:rank] == 7 || pbInRaidAdventure? && pbRaidAdventureState.boss_battled
      track = bgm[1]
    else
      track = bgm[0]
    end
    species = (rules[:pokemon]) ? rules[:pokemon].species_data.id : nil
    case rules[:style]
    when :Ultra then track = bgm[2] if [:NECROZMA_3, :NECROZMA_4].include?(species)
    when :Max   then track = bgm[2] if species == :ETERNATUS_1
    when :Tera  then track = bgm[2] if species == :TERAPAGOS_2
    end 
    if pbResolveAudioFile(track)
      setBattleRule("battleBGM", track)
      setBattleRule("lowHealthBGM", "")
    end
  end
  setBattleRule("canLose")
  setBattleRule("setSlideSprite", "still") if !battleRules["slideSpriteStyle"]
  setBattleRule("databoxStyle", :Long) if !battleRules["databoxStyle"]
  pbRegisterPartner(*rules[:partner][0..2]) if rules[:partner]
  case rules[:style]
  when :Ultra then setBattleRule("noZMoves", :Player)
  when :Max   then setBattleRule("noDynamax", :Player)
  when :Tera  then setBattleRule("noTerastallize", :Player)
  end
end

#===============================================================================
# Handler for scaling a partner trainer's attributes to suit a particular raid.
#===============================================================================
EventHandlers.add(:on_trainer_load, :raid_partner,
  proc { |trainer|
    next if !trainer
    if pbInRaidAdventure?
      rules = {:rank  => 5,
               :style => pbRaidAdventureState.style}
    else
      rules = $game_temp.battle_rules["raidBattle"]
      next if !rules || rules[:partner][3]
    end
    items = {
      :Basic => [:MEGARING],
      :Ultra => [:ZRING], 
      :Max   => [:DYNAMAXBAND], 
      :Tera  => [:TERAORB]
    }
    trainer.items = items[rules[:style]]
    pkmn = trainer.party.last
    pkmn.level = pbDefaultRaidProperty(pkmn, :level, rules)
    raid_moves = pkmn.getRaidMoves(rules[:style], true)
    [:primary, :secondary, :status, :other].each do |key|
      next if !raid_moves.has_key?(key)
      m = raid_moves[key].sample
      next if pkmn.hasMove?(m)
      pkmn.learn_move(m)
    end
    if rules[:style] == :Ultra
      pkmn.item = GameData::Item.get_compatible_crystal(pkmn)
    elsif rules[:style] != :Basic
      pkmn.item = nil if pkmn.hasItem? && GameData::Item.get(pkmn.item_id).is_mega_stone?
    end
    pkmn.calc_stats
    trainer.party = [pkmn]
  }
)