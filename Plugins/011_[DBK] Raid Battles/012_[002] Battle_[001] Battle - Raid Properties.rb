#===============================================================================
# General additions to the Battle class.
#===============================================================================
class Battle
  attr_accessor :raidRules
  
  #-----------------------------------------------------------------------------
  # Aliased to initialize new battle properties.
  #-----------------------------------------------------------------------------
  alias raid_initialize initialize
  def initialize(*args)
    raid_initialize(*args)
    @raidRules = {}
  end
  
  #-----------------------------------------------------------------------------
  # Utility for updating the raid turn counter.
  #-----------------------------------------------------------------------------
def pbRaidChangeTurnCount(battler, amt)
  return if !battler || battler.fainted? || !battler.isRaidBoss?
  return if !@raidRules[:turn_count] || @raidRules[:turn_count] < 0
  oldCount = @raidRules[:turn_count]
  @raidRules[:turn_count] += amt if @raidRules[:turn_count] > 0
  @raidRules[:turn_count] = 0 if @raidRules[:turn_count] < 0
  @raidRules[:raid_turnCount] = @turnCount
  PBDebug.log("[Raid mechanics] Raid turn counter changed (#{oldCount} => #{@raidRules[:turn_count]})")
  @scene.pbRefreshOne(battler.index)
  return if @raidRules[:turn_count] > 0
  return if pbAllFainted? || @decision > 0
  pbDisplayPaused(_INTL("{1} 주변의 에너지가 통제 불능이 되었다!", battler.pbThis(true)))
  pbDisplay(_INTL("덴 밖으로 날려졌다!"))
  pbRaidAdventureState.hearts = 0 if pbInRaidAdventure?
  @scene.pbAnimateFleeFromRaid
  @decision = 3
end
  
  #-----------------------------------------------------------------------------
  # Utility for updating the raid KO counter.
  #-----------------------------------------------------------------------------
def pbRaidChangeKOCount(battler, amt, done_fainting)
  return if !battler || battler.fainted? || !battler.isRaidBoss?
  return if !@raidRules[:ko_count] || @raidRules[:ko_count] < 0
  oldCount = @raidRules[:ko_count]
  @raidRules[:ko_count] += amt if @raidRules[:ko_count] > 0
  @raidRules[:ko_count] = 0 if @raidRules[:ko_count] < 0
  if pbInRaidAdventure?
    pbRaidAdventureState.hearts = @raidRules[:ko_count]
    if pbRaidAdventureState.hearts > pbRaidAdventureState.max_hearts
      pbRaidAdventureState.max_hearts = @raidRules[:ko_count]
    end
  end
  PBDebug.log("[Raid mechanics] Raid KO counter changed (#{oldCount} => #{@raidRules[:ko_count]})")
  @scene.pbRefreshOne(battler.index)
  return if amt > 0 || !done_fainting
  case @raidRules[:ko_count]
  when 0 then pbDisplayPaused(_INTL("{1} 주변의 에너지가 통제 불능으로 폭주했다!", battler.pbThis(true)))
  when 1 then pbDisplay(_INTL("{1} 주변의 에너지가 너무 강해져 버티기 힘들다!", battler.pbThis(true)))
  else        pbDisplay(_INTL("{1} 주변의 에너지가 점점 강해지고 있다!", battler.pbThis(true)))
  end
  return if @raidRules[:ko_count] > 0 || pbAllFainted? || @decision > 0
  pbDisplay(_INTL("레이드굴 밖으로 날려졌다!"))
  @scene.pbAnimateFleeFromRaid
  @decision = 3
end
end

#===============================================================================
# Aliases how Raid Pokemon are captured and stored.
#===============================================================================
module Battle::CatchAndStoreMixin
  alias raid_pbStorePokemon pbStorePokemon
  # FIX 1: pbStorePokemon 호출 시 pkmn 인수가 누락되지 않도록 수정
  def pbStorePokemon(pkmn)
    if pkmn.immunities.include?(:RAIDBOSS) && @raidStyleCapture && !@caughtPokemon.empty?
      pkmn.makeUnmega
      pkmn.makeUnprimal
      pkmn.makeUnUltra if pkmn.ultra?
      pkmn.dynamax       = false if pkmn.dynamax?
      pkmn.terastallized = false if pkmn.tera?
      pkmn.hp_level = 0
      pkmn.immunities = nil
      pkmn.name = nil if pkmn.nicknamed?
      pkmn.level = 75 if pkmn.level > 75
      pkmn.resetLegacyData if defined?(pkmn.legacy_data)
      case @raidRules[:style]
      when :Ultra
        pkmn.form_simple = 0 if pkmn.isSpecies?(:NECROZMA)
        if pkmn.item && GameData::Item.get(pkmn.item_id).is_zcrystal?
          pkmn.item = nil if !pbInRaidAdventure?
        end
      when :Max
        pkmn.dynamax_lvl = @raidRules[:rank] + rand(3)
      when :Tera
        pkmn.forced_form = nil if pkmn.isSpecies?(:OGERPON)
      end
      if pbInRaidAdventure?
        if pbRaidAdventureState.endlessMode? || !pbRaidAdventureState.boss_battled
          ev_stats = [nil, :DEFENSE, :SPECIAL_DEFENSE]
          ev_stats.push(:ATTACK) if pkmn.moves.any? { |m| m.physical_move? }
          ev_stats.push(:SPECIAL_ATTACK) if pkmn.moves.any? { |m| m.special_move? }
          ev_stats.push(:SPEED) if pkmn.baseStats[:SPEED] > 60
          stat = ev_stats.sample
          pkmn.ev[:HP] = Pokemon::EV_STAT_LIMIT
          if GameData::Stat.exists?(stat)
            pkmn.ev[stat] = Pokemon::EV_STAT_LIMIT
          else
            GameData::Stat.each_main_battle do |s|
              pkmn.ev[s.id] = (Pokemon::EV_STAT_LIMIT / 5).floor
            end
          end
        end
        pkmn.heal
        pkmn.calc_stats
        pbRaidAdventureState.captures.push(pkmn)
        pbDisplay(_INTL("잡은 {1}!", pkmn.name))
      else
        pkmn.heal
        pkmn.reset_moves
        pkmn.calc_stats
        stored_box = $PokemonStorage.pbStoreCaught(pkmn)
        box_name = @peer.pbBoxName(stored_box)
        pbDisplayPaused(_INTL("\\j[{1},이,가] 박스 \"{2}\"로 전송되었다!", pkmn.name, box_name))
      end
    else
      # [FIX 1 적용] 일반 포켓몬 저장 시 인수를 다음 Alias로 전달
      raid_pbStorePokemon(pkmn) 
    end
  end
  
  alias raid_pbRecordAndStoreCaughtPokemon pbRecordAndStoreCaughtPokemon
  # FIX 2: *args를 추가하여 호출자가 전달하는 모든 인수를 받고 저장합니다.
  def pbRecordAndStoreCaughtPokemon(*args) 
    if pbInRaidAdventure?
      @caughtPokemon.each { |pkmn| pbStorePokemon(pkmn) }
      @caughtPokemon.clear
    else
      # [FIX 2 적용] 일반 포획 로직 실행 시 인수를 다음 Alias로 전달
      raid_pbRecordAndStoreCaughtPokemon(*args)
    end
  end
end