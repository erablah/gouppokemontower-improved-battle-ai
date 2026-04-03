class Battle
  AI_FOG_PLACEHOLDER_ITEM = :AIFOGDUMMY
  AI_FOG_ALWAYS_VISIBLE_ITEMS = [:TERAPIECE, :MAXMUSHROOM].freeze

  alias fog_of_war_initialize initialize

  def initialize(scene, p1, p2, player, opponent)
    fog_of_war_initialize(scene, p1, p2, player, opponent)
    @ai_item_fog_of_war = false
    @player_item_hidden = Array.new(@party1.length) do |i|
      pkmn = @party1[i]
      next false if !pkmn || !pkmn.item_id
      !ai_fog_item_always_visible?(pkmn.item_id)
    end
    @ai_fog_hidden_move_index = {}
    @party1.each_with_index do |pkmn, i|
      next if !pkmn
      PBDebug.log_ai("[fog_of_war:init] party index #{i} pokemon=#{pkmn.name} item=#{pkmn.item_id.inspect} hidden=#{@player_item_hidden[i]}")
    end
  end

  def ai_item_fog_of_war?
    return @ai_item_fog_of_war || false
  end

  def set_ai_item_fog_of_war(value)
    @ai_item_fog_of_war = value
  end

  def player_item_hidden?(party_index)
    return false if !party_index || party_index < 0 || party_index >= @player_item_hidden.length
    return @player_item_hidden[party_index]
  end

  def reveal_player_item(party_index)
    return if !party_index || party_index < 0 || party_index >= @player_item_hidden.length
    PBDebug.log_ai("[fog_of_war:reveal] party index #{party_index} hidden_before=#{@player_item_hidden[party_index]}")
    @player_item_hidden[party_index] = false
  end

  def player_item_hidden_for_battler?(battler)
    return false if !battler
    return false if !battler.pbOwnedByPlayer?
    return player_item_hidden?(battler.pokemonIndex)
  end

  def ai_fog_item_always_visible?(item)
    item_data = GameData::Item.try_get(item)
    return false if !item_data
    return true if item_data.has_flag?("MegaStone")
    return true if AI_FOG_ALWAYS_VISIBLE_ITEMS.include?(item_data.id)
    return false
  end

  def ai_fog_acted_ids
    @_foe_acted_ids ||= {}
    return @_foe_acted_ids
  end

  def ai_fog_pokemon_from(obj)
    return nil if !obj
    return obj.pokemon if obj.respond_to?(:pokemon)
    return obj if obj.respond_to?(:personalID)
    return nil
  end

  def mark_ai_fog_acted(battler)
    pkmn = ai_fog_pokemon_from(battler)
    return if !battler || !battler.pbOwnedByPlayer? || !pkmn
    ai_fog_acted_ids[pkmn.personalID] = true
  end

  def ai_fog_acted?(battler_or_pkmn)
    pkmn = ai_fog_pokemon_from(battler_or_pkmn)
    return false if !pkmn
    return ai_fog_acted_ids[pkmn.personalID] || false
  end

  def ai_fog_hidden_move_index_for(battler)
    pkmn = ai_fog_pokemon_from(battler)
    return nil if !pkmn
    key = pkmn.personalID
    hidden_index = @ai_fog_hidden_move_index[key]
    return nil if hidden_index == :none
    return hidden_index if !hidden_index.nil?
    all_moves = battler.moves.compact
    foe_types = battler.pbTypes(true)
    protected_moves = []
    foe_types.each do |type|
      best = all_moves.select { |move| move.type == type && move.damagingMove? }
                      .max_by { |move| move.power }
      protected_moves << best if best
    end
    remaining_indexes = []
    battler.moves.each_with_index do |move, idx|
      next if !move
      next if protected_moves.include?(move)
      remaining_indexes << idx
    end
    if remaining_indexes.length > 0 && pbRandom(100) < 50
      hidden_index = remaining_indexes[pbRandom(remaining_indexes.length)]
      @ai_fog_hidden_move_index[key] = hidden_index
      return hidden_index
    end
    @ai_fog_hidden_move_index[key] = :none
    return nil
  end

  def ai_fog_known_moves_for(battler)
    all_moves = battler.moves.compact
    return all_moves if ai_fog_acted?(battler)
    hidden_index = ai_fog_hidden_move_index_for(battler)
    return all_moves if hidden_index.nil?
    hidden_move = battler.moves[hidden_index]
    return all_moves if !hidden_move
    return all_moves - [hidden_move]
  end
end

Battle::AI::Handlers::ItemRanking.add(:AIFOGDUMMY,
  proc { |item, score, battler, ai|
    next 6
  }
)

class Battle::AI
  def with_item_fog_of_war
    old_value = @battle.ai_item_fog_of_war?
    @battle.set_ai_item_fog_of_war(true)
    return yield
  ensure
    @battle.set_ai_item_fog_of_war(old_value)
  end

  alias fog_of_war_pbDefaultChooseEnemyCommand pbDefaultChooseEnemyCommand
  def pbDefaultChooseEnemyCommand(idxBattler)
    return with_item_fog_of_war { fog_of_war_pbDefaultChooseEnemyCommand(idxBattler) }
  end

  alias fog_of_war_pbDefaultChooseNewEnemy pbDefaultChooseNewEnemy
  def pbDefaultChooseNewEnemy(idxBattler)
    return with_item_fog_of_war { fog_of_war_pbDefaultChooseNewEnemy(idxBattler) }
  end
end

class Battle::Battler
  alias fog_of_war_pbProcessTurn pbProcessTurn
  def pbProcessTurn(choice, tryFlee = true)
    ret = fog_of_war_pbProcessTurn(choice, tryFlee)
    if choice[0] == :UseMove && pbOwnedByPlayer?
      @battle.mark_ai_fog_acted(self)
    end
    return ret
  end

  alias fog_of_war_item_id item_id
  def item_id
    if @battle.ai_item_fog_of_war? && @battle.player_item_hidden_for_battler?(self)
      return nil if !fog_of_war_item_id
      return Battle::AI_FOG_PLACEHOLDER_ITEM
    end
    return fog_of_war_item_id
  end

  alias fog_of_war_item item
  def item
    if @battle.ai_item_fog_of_war? && @battle.player_item_hidden_for_battler?(self)
      return nil if !fog_of_war_item
      return GameData::Item.try_get(Battle::AI_FOG_PLACEHOLDER_ITEM)
    end
    return fog_of_war_item
  end

  alias fog_of_war_itemActive? itemActive?
  def itemActive?(ignoreFainted = false)
    if @battle.ai_item_fog_of_war? && @battle.player_item_hidden_for_battler?(self)
      return false
    end
    return fog_of_war_itemActive?(ignoreFainted)
  end

  alias fog_of_war_hasActiveItem? hasActiveItem?
  def hasActiveItem?(check_item, ignore_fainted = false)
    if @battle.ai_item_fog_of_war? && @battle.player_item_hidden_for_battler?(self)
      return false
    end
    return fog_of_war_hasActiveItem?(check_item, ignore_fainted)
  end

  alias fog_of_war_pbEndTurn pbEndTurn
  def pbEndTurn(choice)
    fog_of_war_pbEndTurn(choice)
    return if !pbOwnedByPlayer?
    return if !@battle.ai_fog_acted?(self)
    return if !hasActiveItem?([:CHOICEBAND, :CHOICESPECS, :CHOICESCARF])
    return if !@effects[PBEffects::ChoiceBand]
    @battle.reveal_player_item(pokemonIndex)
  end
end

class Battle::AI::AIBattler
  def hidden_item_from_ai?
    return false if !@ai.user
    return false if !battler.pbOwnedByPlayer?
    return false if !opposes?(@ai.user)
    return @ai.battle.player_item_hidden?(battler.pokemonIndex)
  end

  def item_id
    if hidden_item_from_ai?
      return nil if !battler.item_id
      return Battle::AI_FOG_PLACEHOLDER_ITEM
    end
    return battler.item_id
  end

  def item
    if hidden_item_from_ai?
      return nil if !battler.item
      return GameData::Item.try_get(Battle::AI_FOG_PLACEHOLDER_ITEM)
    end
    return battler.item
  end

  def item_active?
    if hidden_item_from_ai?
      return false
    end
    return battler.itemActive?
  end

  def has_active_item?(item)
    if hidden_item_from_ai?
      return false
    end
    return battler.hasActiveItem?(item)
  end

  def rough_stat(stat)
    return battler.pbSpeed if stat == :SPEED && @ai.trainer.high_skill? && !hidden_item_from_ai?
    stage_mul = Battle::Battler::STAT_STAGE_MULTIPLIERS
    stage_div = Battle::Battler::STAT_STAGE_DIVISORS
    if [:ACCURACY, :EVASION].include?(stat)
      stage_mul = Battle::Battler::ACC_EVA_STAGE_MULTIPLIERS
      stage_div = Battle::Battler::ACC_EVA_STAGE_DIVISORS
    end
    stage = battler.stages[stat] + Battle::Battler::STAT_STAGE_MAXIMUM
    value = base_stat(stat)
    return (value.to_f * stage_mul[stage] / stage_div[stage]).floor
  end
end

class Battle::AI
  def known_foe_moves(foe_ai_battler)
    visible_moves = @battle.ai_fog_known_moves_for(foe_ai_battler)
    return visible_moves
  end
end

module Battle::ItemEffects
  class << self
    alias fog_of_war_trigger trigger
    alias fog_of_war_triggerPriorityBracketUse triggerPriorityBracketUse
    alias fog_of_war_triggerOnBeingHit triggerOnBeingHit
    alias fog_of_war_triggerAfterMoveUseFromTarget triggerAfterMoveUseFromTarget
    alias fog_of_war_triggerAfterMoveUseFromUser triggerAfterMoveUseFromUser
    alias fog_of_war_triggerEndOfRoundHealing triggerEndOfRoundHealing
    alias fog_of_war_triggerEndOfRoundEffect triggerEndOfRoundEffect
    alias fog_of_war_triggerOnSwitchIn triggerOnSwitchIn
  end

  FOG_OF_WAR_REVEALABLE_TRIGGERS = [
    HPHeal,
    StatusCure,
    PriorityBracketUse,
    OnBeingHit,
    OnBeingHitPositiveBerry,
    AfterMoveUseFromTarget,
    AfterMoveUseFromUser,
    OnEndOfUsingMove,
    OnEndOfUsingMoveStatRestore,
    TerrainStatBoost,
    EndOfRoundHealing,
    EndOfRoundEffect,
    CertainSwitching,
    TrappingByTarget,
    OnSwitchIn,
    OnIntimidated,
    CertainEscapeFromBattle
  ].freeze

  def self.trigger(hash, *args, ret: false)
    new_ret = fog_of_war_trigger(hash, *args, ret: ret)
    fog_of_war_reveal_item(hash, args) if FOG_OF_WAR_REVEALABLE_TRIGGERS.include?(hash)
    return (!new_ret.nil?) ? new_ret : ret
  end

  def self.triggerPriorityBracketUse(item, battler, battle)
    fog_of_war_triggerPriorityBracketUse(item, battler, battle)
    fog_of_war_reveal_item(PriorityBracketUse, [item, battler, battle])
  end

  def self.triggerOnBeingHit(item, user, target, move, battle)
    fog_of_war_triggerOnBeingHit(item, user, target, move, battle)
    fog_of_war_reveal_item(OnBeingHit, [item, user, target, move, battle])
  end

  def self.triggerAfterMoveUseFromTarget(item, battler, user, move, switched_battlers, battle)
    fog_of_war_triggerAfterMoveUseFromTarget(item, battler, user, move, switched_battlers, battle)
    fog_of_war_reveal_item(AfterMoveUseFromTarget, [item, battler, user, move, switched_battlers, battle])
  end

  def self.triggerAfterMoveUseFromUser(item, user, targets, move, num_hits, battle)
    fog_of_war_triggerAfterMoveUseFromUser(item, user, targets, move, num_hits, battle)
    fog_of_war_reveal_item(AfterMoveUseFromUser, [item, user, targets, move, num_hits, battle])
  end

  def self.triggerEndOfRoundHealing(item, battler, battle)
    old_hp = battler&.hp
    old_item = battler&.item_id
    fog_of_war_triggerEndOfRoundHealing(item, battler, battle)
    if battler && (battler.hp != old_hp || battler.item_id != old_item)
      fog_of_war_reveal_item(EndOfRoundHealing, [item, battler, battle])
    end
  end

  def self.triggerEndOfRoundEffect(item, battler, battle)
    old_hp = battler&.hp
    old_status = battler&.status
    old_status_count = battler&.statusCount
    old_item = battler&.item_id
    fog_of_war_triggerEndOfRoundEffect(item, battler, battle)
    if battler &&
       (battler.hp != old_hp ||
        battler.status != old_status ||
        battler.statusCount != old_status_count ||
        battler.item_id != old_item)
      fog_of_war_reveal_item(EndOfRoundEffect, [item, battler, battle])
    end
  end

  def self.triggerOnSwitchIn(item, battler, battle)
    fog_of_war_triggerOnSwitchIn(item, battler, battle)
    fog_of_war_reveal_item(OnSwitchIn, [item, battler, battle])
  end

  def self.fog_of_war_reveal_item(hash, args)
    item = GameData::Item.try_get(args[0])&.id
    return if !item || !hash[item]
    battler = fog_of_war_holder_from_trigger(hash, args)
    battle = args.find { |arg| arg.is_a?(Battle) } || battler&.battle
    return if !battler || !battle || battle.ai_item_fog_of_war? || !battler.pbOwnedByPlayer?
    battle.reveal_player_item(battler.pokemonIndex)
  end

  def self.fog_of_war_holder_from_trigger(hash, args)
    case hash
    when SpeedCalc, WeightCalc, HPHeal, OnStatLoss, StatusCure,
         PriorityBracketChange, PriorityBracketUse, OnBeingHitPositiveBerry,
         AfterMoveUseFromTarget, AfterMoveUseFromUser, OnEndOfUsingMove,
         OnEndOfUsingMoveStatRestore, WeatherExtender, TerrainExtender,
         TerrainStatBoost, EndOfRoundHealing, EndOfRoundEffect,
         CertainSwitching, OnSwitchIn, OnIntimidated, CertainEscapeFromBattle
      return args[1]
    when AccuracyCalcFromTarget, DamageCalcFromTarget, CriticalCalcFromTarget,
         OnBeingHit, TrappingByTarget
      return args[2]
    when AccuracyCalcFromUser, DamageCalcFromUser, CriticalCalcFromUser,
         OnMissingTarget
      return args[1]
    end
    return args.find { |arg| arg.is_a?(Battle::Battler) }
  end
end
