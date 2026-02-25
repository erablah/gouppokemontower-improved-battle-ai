#===============================================================================
# * Disable Charm
#===============================================================================

class Battle::Battler
  def pbEffectsOnMakingHit(move, user, target)
    if target.damageState.calcDamage > 0 && !target.damageState.substitute
      # Target's ability
      if target.abilityActive?(true)
        oldHP = user.hp
        Battle::AbilityEffects.triggerOnBeingHit(target.ability, user, target, move, @battle)
        user.pbItemHPHealCheck if user.hp < oldHP
      end
      # Cramorant - Gulp Missile
      if target.isSpecies?(:CRAMORANT) && target.ability == :GULPMISSILE &&
         target.form > 0 && !target.effects[PBEffects::Transform]
        oldHP = user.hp
        # NOTE: Strictly speaking, an attack animation should be shown (the
        #       target Cramorant attacking the user) and the ability splash
        #       shouldn't be shown.
        @battle.pbShowAbilitySplash(target)
        target.pbChangeForm(0, nil)
        if user.takesIndirectDamage?(Battle::Scene::USE_ABILITY_SPLASH)
          @battle.scene.pbDamageAnimation(user)
          user.pbReduceHP(user.totalhp / 4, false)
        end
        case target.form
        when 1   # Gulping Form
          user.pbLowerStatStageByAbility(:DEFENSE, 1, target, false)
        when 2   # Gorging Form
          user.pbParalyze(target) if user.pbCanParalyze?(target, false)
        end
        @battle.pbHideAbilitySplash(target)
        user.pbItemHPHealCheck if user.hp < oldHP
      end
      # User's ability
      if user.abilityActive?(true)
        Battle::AbilityEffects.triggerOnDealingHit(user.ability, user, target, move, @battle)
        user.pbItemHPHealCheck
      end
      # Target's item
      if target.itemActive?(true)
        oldHP = user.hp
        Battle::ItemEffects.triggerOnBeingHit(target.item, user, target, move, @battle)
        user.pbItemHPHealCheck if user.hp < oldHP
      end
    end
    if target.opposes?(user)
      # Rage
      if target.effects[PBEffects::Rage] && !target.fainted? &&
         target.pbCanRaiseStatStage?(:ATTACK, target)
        @battle.pbDisplay(_INTL("{1}'s rage is building!", target.pbThis))
        target.pbRaiseStatStage(:ATTACK, 1, target)
      end
      # Beak Blast
      if target.effects[PBEffects::BeakBlast]
        PBDebug.log("[Lingering effect] #{target.pbThis}'s Beak Blast")
        if move.pbContactMove?(user) && user.affectedByContactEffect? &&
           user.pbCanBurn?(target, false, self)
          user.pbBurn(target)
        end
      end
      # Shell Trap (make the trapper move next if the trap was triggered)
      if target.effects[PBEffects::ShellTrap] && move.physicalMove? &&
         @battle.choices[target.index][0] == :UseMove && !target.movedThisRound? &&
         target.damageState.hpLost > 0 && !target.damageState.substitute
        target.tookPhysicalHit              = true
        target.effects[PBEffects::MoveNext] = true
        target.effects[PBEffects::Quash]    = 0
      end
      # Grudge
      if target.effects[PBEffects::Grudge] && target.fainted?
        user.pbSetPP(move, 0)
        @battle.pbDisplay(_INTL("{1}'s {2} lost all of its PP due to the grudge!",
                                user.pbThis, move.name))
      end
      # Destiny Bond (recording that it should apply)
      if target.effects[PBEffects::DestinyBond] && target.fainted? &&
         user.effects[PBEffects::DestinyBondTarget] < 0
        user.effects[PBEffects::DestinyBondTarget] = target.index
      end
    end
    if $player.activeCharm?(:DISABLECHARM) && !user.pbOwnedByPlayer?
      if user.fainted? || user.effects[PBEffects::Disable] > 0
      else
        regularMove = nil
        user.eachMove do |m|
          next if m.id != user.lastRegularMoveUsed
          regularMove = m
          break
        end
        if !regularMove || (regularMove.pp == 0 && regularMove.total_pp > 0) || battle.pbRandom(100) >= 30
        else
          if !move.pbMoveFailedAromaVeil?(target, user, Battle::Scene::USE_ABILITY_SPLASH)
            user.effects[PBEffects::Disable]     = 3
            user.effects[PBEffects::DisableMove] = regularMove.id
            battle.pbDisplay(_INTL("{1}'s {2} was disabled by the Disable Charm!", user.pbThis, regularMove.name))
            user.pbItemStatusCureCheck
          end
        end
      end
    end
  end
end