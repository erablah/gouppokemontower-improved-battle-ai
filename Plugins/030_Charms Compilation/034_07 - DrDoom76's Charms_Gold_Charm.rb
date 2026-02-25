#===============================================================================
# * Gold Charm
#===============================================================================

class Battle
 def pbGainMoney
    return if !@internalBattle || !@moneyGain
    goldCharmPayDay = DrCharmConfig::GOLD_CHARM_PAY_DAY
    goldCharmGetGold = DrCharmConfig::GOLD_CHARM_GET_GOLD
    # Money rewarded from opposing trainers
    if trainerBattle?
      tMoney = 0
      @opponent.each_with_index do |t, i|
        tMoney += pbMaxLevelInTeam(1, i) * t.base_money
      end
      tMoney *= 2 if @field.effects[PBEffects::AmuletCoin]
      tMoney *= 2 if @field.effects[PBEffects::HappyHour]
      # Gold Charm multiples Trainer Battle gain by 2.
      tMoney *= goldCharmPayDay if $player.activeCharm?(:GOLDCHARM)
      oldMoney = pbPlayer.money
      pbPlayer.money += tMoney
      moneyGained = pbPlayer.money - oldMoney
      if moneyGained > 0
        $stats.battle_money_gained += moneyGained
        pbDisplayPaused(_INTL("You got ${1} for winning!", moneyGained.to_s_formatted))
      end
    end
    # Pick up money scattered by Pay Day
    if @field.effects[PBEffects::PayDay] > 0
      @field.effects[PBEffects::PayDay] *= 2 if @field.effects[PBEffects::AmuletCoin]
      @field.effects[PBEffects::PayDay] *= 2 if @field.effects[PBEffects::HappyHour]
      @field.effects[PBEffects::PayDay] += goldCharmGetGold if $player.activeCharm?(:GOLDCHARM)
      oldMoney = pbPlayer.money
      pbPlayer.money += @field.effects[PBEffects::PayDay]
      moneyGained = pbPlayer.money - oldMoney
      if moneyGained > 0
        $stats.battle_money_gained += moneyGained
        pbDisplayPaused(_INTL("You picked up ${1}!", moneyGained.to_s_formatted))
      end
    end
  end
end