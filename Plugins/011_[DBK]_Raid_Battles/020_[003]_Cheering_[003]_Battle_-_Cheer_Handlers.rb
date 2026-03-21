#===============================================================================
# Defines the cheer handler class.
#===============================================================================
class CheerHandlerHash < HandlerHashSymbol
end

module Battle::Cheer
  CheerEffects = CheerHandlerHash.new
  
  def self.trigger(*args, ret: false)
    new_ret = CheerEffects.trigger(*args)
    return (!new_ret.nil?) ? new_ret : ret
  end
end


################################################################################
#
# Cheer handlers.
#
################################################################################


#-------------------------------------------------------------------------------
# Offense Cheer - "Go all-out!"
#-------------------------------------------------------------------------------
# Cheer Lv.1 : The team deals 50% more damage with attacks.
# Cheer Lv.2 : The team's attacks will always deal critical hits and trigger move effects, if able.
# Cheer Lv.3 : The team's attacks will hit through Protect/Substitute, and ignore screens.
#-------------------------------------------------------------------------------
Battle::Cheer::CheerEffects.add(:Offense,
  proc { |cheer, side, owner, battler, battle|
    ret = false
    case battle.cheerLevel[side][owner]
    when 1
      if battler.pbOwnSide.effects[PBEffects::CheerOffense1] == 0
        battler.pbOwnSide.effects[PBEffects::CheerOffense1] = 3
        battle.pbDisplay(_INTL("응원이 {1}에게 더 강한 공격력을 불어넣었다!", battler.pbTeam(true)))
        ret = true
      end
    when 2
      if battler.pbOwnSide.effects[PBEffects::CheerOffense2] == 0
        battler.pbOwnSide.effects[PBEffects::CheerOffense2] = 3
        battle.pbDisplay(_INTL("응원이 {1}에게 더 강력하게 공격할 의지를 불어넣었다!", battler.pbTeam(true)))
        ret = true
      end
    when 3
      if battler.pbOwnSide.effects[PBEffects::CheerOffense3] == 0
        battler.pbOwnSide.effects[PBEffects::CheerOffense3] = 3
        battle.pbDisplay(_INTL("응원이 {1}에게 배리어를 뚫을 의지를 불어넣었다!", battler.pbTeam(true)))
        ret = true
      end
    end
    next ret
  }
)

#-------------------------------------------------------------------------------
# Defense Cheer - "Hang tough!"
#-------------------------------------------------------------------------------
# Cheer Lv.1 : The team takes 50% less damage from attacks.
# Cheer Lv.2 : The team is immune to critical hits and move effects.
# Cheer Lv.3 : The team endures all incoming attacks.
#-------------------------------------------------------------------------------
Battle::Cheer::CheerEffects.add(:Defense,
  proc { |cheer, side, owner, battler, battle|
    ret = false
    case battle.cheerLevel[side][owner]
    when 1
      if battler.pbOwnSide.effects[PBEffects::CheerDefense1] == 0
        battler.pbOwnSide.effects[PBEffects::CheerDefense1] = 3
        battle.pbDisplay(_INTL("응원이 {1}에게 공격을 견뎌낼 의지를 불어넣었다!", battler.pbTeam(true)))
        ret = true
      end
    when 2
      if battler.pbOwnSide.effects[PBEffects::CheerDefense2] == 0
        battler.pbOwnSide.effects[PBEffects::CheerDefense2] = 3
        battle.pbDisplay(_INTL("응원이 {1}에게 급소와 기술 효과에 저항할 의지를 불어넣었다!", battler.pbTeam(true)))
        ret = true
      end
    when 3
      if battler.pbOwnSide.effects[PBEffects::CheerDefense3] == 0
        battler.pbOwnSide.effects[PBEffects::CheerDefense3] = 3
        battle.allSameSideBattlers(side).each { |b| b.effects[PBEffects::Endure] = true }
        battle.pbDisplay(_INTL("응원이 {1}에게 모든 공격을 견뎌낼 의지를 불어넣었다!", battler.pbTeam(true)))
        ret = true
      end
    end
    next ret
  }
)

#-------------------------------------------------------------------------------
# Healing Cheer - "Heal up!"
#-------------------------------------------------------------------------------
# Cheer Lv.1 : Heals the team by 25% HP.
# Cheer Lv.2 : Heals the team by 50% HP and removes harmful conditions.
# Cheer Lv.3 : Heals the team by 100%, removes harmful conditions, and applies the Wish effect.
#-------------------------------------------------------------------------------
Battle::Cheer::CheerEffects.add(:Healing,
  proc { |cheer, side, owner, battler, battle|
    cheerLvl = battle.cheerLevel[side][owner]
    next false if cheerLvl <= 0
    case cheerLvl
    when 1 then hpPortion = 4 # Heals 25% total HP
    when 2 then hpPortion = 2 # Heals 50% total HP
    when 3 then hpPortion = 1 # Heals 100% total HP
    end
    ret = false
    battle.allSameSideBattlers(battler).each do |b|
      if b.canHeal?
        b.pbRecoverHP(b.totalhp / hpPortion)
        battle.pbDisplay(_INTL("{1}의 HP가 회복되었다.", b.pbThis))
        ret = true
      end
      if cheerLvl > 1
        if b.status != :NONE
          b.pbCureStatus
          ret = true
        end
        if b.effects[PBEffects::Confusion] > 0
          b.pbCureConfusion
          battle.pbDisplay(_INTL("\\j[{1},은,는] 혼란에서 벗어났다.", b.pbThis))
          ret = true
        end
        if b.effects[PBEffects::Attract] >= 0
          b.pbCureAttract
          battle.pbDisplay(_INTL("\\j[{1},은,는] 헤롱헤롱 상태에서 벗어났다.", b.pbThis))
          ret = true
        end
        if b.effects[PBEffects::Curse]
          b.effects[PBEffects::Curse] = false
          battle.pbDisplay(_INTL("{1}에게 걸린 저주가 풀렸다.", b.pbThis))
          ret = true
        end
      end
      if cheerLvl == 3 && b.effects[PBEffects::HealBlock] == 0
        battle.positions[b.index].effects[PBEffects::Wish] = 2
        battle.positions[b.index].effects[PBEffects::WishAmount] = (b.totalhp / 2).round
        battle.positions[b.index].effects[PBEffects::WishMaker] = b.pokemonIndex
        battle.pbDisplay(_INTL("응원이 {1}에게 소원을 빌 의지를 불어넣었다!", b.pbThis(true)))
        ret = true
      end
    end
    next ret
  }
)

#-------------------------------------------------------------------------------
# Counter Cheer - "Turn the tables!"
#-------------------------------------------------------------------------------
# Cheer Lv.1 : Reverses stat changes for all battlers.
# Cheer Lv.2 : Swaps the active field effects for both sides.
# Cheer Lv.3 : Removes the Heal Block effect from allies, and applies it to foes.
#-------------------------------------------------------------------------------
Battle::Cheer::CheerEffects.add(:Counter,
  proc { |cheer, side, owner, battler, battle|
    ret = false
    case battle.cheerLevel[side][owner]
    when 1
      battle.allBattlers.each do |b|
        if b.hasAlteredStatStages?
          GameData::Stat.each_battle do |s|
            if b.stages[s.id] > 0
              b.statsLoweredThisRound = true
              b.statsDropped = true
            elsif b.stages[s.id] < 0
              b.statsRaisedThisRound = true
            end
            b.stages[s.id] *= -1
          end
          ret = true
        end
      end
      battle.pbDisplay(_INTL("응원이 모든 포켓몬의 능력치 변화를 역전시켰다!")) if ret
    when 2
      effects = [
        PBEffects::AuroraVeil,
        PBEffects::CheerOffense1,
        PBEffects::CheerOffense2,
        PBEffects::CheerOffense3,
        PBEffects::CheerDefense1,
        PBEffects::CheerDefense2,
        PBEffects::CheerDefense3,
        PBEffects::LightScreen,
        PBEffects::LuckyChant,
        PBEffects::Mist,
        PBEffects::Rainbow,
        PBEffects::Reflect,
        PBEffects::Safeguard,
        PBEffects::SeaOfFire,
        PBEffects::Spikes,
        PBEffects::StealthRock,
        PBEffects::StickyWeb,
        PBEffects::Swamp,
        PBEffects::Tailwind,
        PBEffects::ToxicSpikes
      ]
      effects += [
        PBEffects::Cannonade,  
        PBEffects::Steelsurge,
        PBEffects::VineLash,  
        PBEffects::Volcalith,  
        PBEffects::Wildfire
      ] if PluginManager.installed?("[DBK] Dynamax")
      side0 = battle.sides[0]
      side1 = battle.sides[1]
      effects.each do |e|
        next if [0, false].include?(side0.effects[e]) && [0, false].include?(side1.effects[e])
        side0.effects[e], side1.effects[e] = side1.effects[e], side0.effects[e]
        ret = true
      end
      battle.pbDisplay(_INTL("응원이 각 진영에 영향을 미치는 배틀 효과를 교환했다!")) if ret
    when 3
      battle.allSameSideBattlers(battler).each do |b|
        next if b.effects[PBEffects::HealBlock] == 0
        b.effects[PBEffects::HealBlock] = 0
        battle.pbDisplay(_INTL("응원이 {1}에게 걸린 힐 블록을 제거했다!", b.pbThis(true)))
        ret = true
      end
      battle.allOtherSideBattlers(battler).each do |b|
        next if b.effects[PBEffects::HealBlock] > 0
        b.effects[PBEffects::HealBlock] = 3
        battle.pbDisplay(_INTL("응원이 {1}의 회복을 방해했다!", b.pbThis(true)))
        ret = true
      end
    end
    next ret
  }
)

#-------------------------------------------------------------------------------
# Basic Raid Cheer - "Keep it going!"
#-------------------------------------------------------------------------------
# Cheer Lv.1 : No effect.
# Cheer Lv.2 : Increases the raid turn counter by 2.
# Cheer Lv.3 : Increases the raid turn counter by 2 and the raid KO counter by 2.
#-------------------------------------------------------------------------------
Battle::Cheer::CheerEffects.add(:BasicRaid,
  proc { |cheer, side, owner, battler, battle|
    next false if !battle.raidBattle?
    next false if battle.cheerLevel[side][owner] < 2
    foe = battler.pbDirectOpposing
    count = 5 - battle.pbSideSize(battler.index)
    case battle.cheerLevel[side][owner]
    when 2
      next false if battle.raidRules[:turn_count] < 0
      battle.pbDisplay(_INTL("{1} 주변의 에너지가 약해진 것 같다...", foe.pbThis(true)))
      battle.pbRaidChangeTurnCount(foe, count)
      battle.pbDisplay(_INTL("응원이 남은 턴 수를 늘렸다!"))
      next true
    when 3
      next false if battle.raidRules[:turn_count] < 0 && battle.raidRules[:ko_count] < 0
      battle.pbDisplay(_INTL("{1} 주변의 에너지가 약해진 것 같다...", foe.pbThis(true)))
      battle.pbRaidChangeTurnCount(foe, count)
      battle.pbRaidChangeKOCount(foe, 2, false)
      battle.pbDisplay(_INTL("응원이 남은 턴 수를 늘렸다!"))
      battle.pbDisplay(_INTL("응원이 남은 기절 횟수를 늘렸다!"))
      next true
    end
    next false
  }
)

#-------------------------------------------------------------------------------
# Ultra Raid Cheer - "Let's use Z-Power!"
#-------------------------------------------------------------------------------
# Cheer Lv.1 : No effect.
# Cheer Lv.2 : No effect.
# Cheer Lv.3 : Recharges the trainer's Z-Ring.
#-------------------------------------------------------------------------------
Battle::Cheer::CheerEffects.add(:UltraRaid,
  proc { |cheer, side, owner, battler, battle|
    next false if !battle.raidBattle?
    next false if battle.cheerLevel[side][owner] < 3
    next false if battle.zMove[side][owner] == -1
    next false if !battle.pbHasZRing?(battler.index)
    battle.zMove[0][owner] = -1
    pbSEPlay(sprintf("Anim/Lucky Chant"))
    trainerName = battle.pbGetOwnerName(battler.index)
    itemName = battle.pbGetZRingName(battler.index)
    battle.pbDisplayPaused(_INTL("응원이 {1}의 \\j[{2},을,를] 완전히 충전했다!\n\\j[{1},은,는] 이제 Z기술을 사용할 수 있다!", trainerName, itemName))
    next true
  }
)

#-------------------------------------------------------------------------------
# Max Raid Cheer - "Let's Dynamax!"
#-------------------------------------------------------------------------------
# Cheer Lv.1 : No effect.
# Cheer Lv.2 : No effect.
# Cheer Lv.3 : Recharges the trainer's Dynamax Band.
#-------------------------------------------------------------------------------
Battle::Cheer::CheerEffects.add(:MaxRaid,
  proc { |cheer, side, owner, battler, battle|
    next false if !battle.raidBattle?
    next false if battle.cheerLevel[side][owner] < 3
    next false if battle.dynamax[side].any? { |tr| tr == -1 }
    next false if !battle.pbHasDynamaxBand?(battler.index)
    next false if battle.allSameSideBattlers(battler).any? { |b| b.dynamax? }
    battle.dynamax[0][owner] = -1
    pbSEPlay(sprintf("Anim/Lucky Chant"))
    trainerName = battle.pbGetOwnerName(battler.index)
    itemName = battle.pbGetDynamaxBandName(battler.index)
    battle.pbDisplayPaused(_INTL("응원이 {1}의 \\j[{2},을,를] 완전히 충전했다!\n\\j[{1},은,는] 이제 다이맥스를 사용할 수 있다!", trainerName, itemName))
    next true
  }
)

#-------------------------------------------------------------------------------
# Tera Raid Cheer - "Let's Terastallize!"
#-------------------------------------------------------------------------------
# Cheer Lv.1 : No effect.
# Cheer Lv.2 : No effect.
# Cheer Lv.3 : Recharges the trainer's Tera Orb.
#-------------------------------------------------------------------------------
Battle::Cheer::CheerEffects.add(:TeraRaid,
  proc { |cheer, side, owner, battler, battle|
    next false if !battle.raidBattle?
    next false if battle.cheerLevel[side][owner] < 3
    next false if !battle.pbHasTeraOrb?(battler.index)
    next false if battle.allSameSideBattlers(battler).any? { |b| b.tera? && b.pbOwnedByPlayer? }
    battle.terastallize[0][owner] = -1
    $player.tera_charged = true if side == 0 && owner == 0
    pbSEPlay(sprintf("Anim/Lucky Chant"))
    trainerName = battle.pbGetOwnerName(battler.index)
    itemName = battle.pbGetTeraOrbName(battler.index)
    battle.pbDisplayPaused(_INTL("응원이 {1}의 \\j[{2},을,를] 완전히 충전했다!\n\\j[{1},은,는] 이제 테라스탈을 사용할 수 있다!", trainerName, itemName))
    next true
  }
)