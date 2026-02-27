#===============================================================================
# 5. ShouldSwitch / ShouldNotSwitch Handlers
#===============================================================================

Battle::AI::Handlers::ShouldSwitch.add(:high_damage_from_foe,
  proc { |user, reserves, ai, battle|
    next false
  }
)

# 베이스 엔진의 :battler_has_super_effective_move 비활성화
# — 효과 발군 기술이 있다는 이유만으로 교체를 막으면
#   상대 랭크업에 대한 교체 판단(:escape_boosted_foe)이 무시됨
Battle::AI::Handlers::ShouldNotSwitch.add(:battler_has_super_effective_move,
  proc { |battler, reserves, ai, battle|
    next false
  }
)

#===============================================================================
# [NEW] Trigger a switch when a foe has >= 2 positive stat stages,
# but only if at least one reserve has a meaningful answer to the threat.
#===============================================================================
Battle::AI::Handlers::ShouldSwitch.add(:escape_boosted_foe,
  proc { |user, reserves, ai, battle|
    next false unless ai.trainer.high_skill?

    # Find a threatening foe with > 2 cumulative positive stat stages
    threatening_foe  = nil
    foe_total_boosts = 0
    ai.each_foe_battler(user.side) do |b, i|
      boosts = 0
      GameData::Stat.each_battle { |s| boosts += b.stages[s.id] if b.stages[s.id] > 0 }
      if boosts >= 2
        threatening_foe  = b
        foe_total_boosts = boosts
        break
      end
    end
    next false unless threatening_foe

    # Only trigger if at least one reserve can answer the threat
    answer_codes = [
      "SwitchOutTargetStatusMove",  # Whirlwind, Roar
      "SwitchOutTargetDamagingMove", # Dragon Tail, Circle Throw
      "ResetAllBattlersStatStages",  # Haze
      "ResetTargetStatStages",       # Clear Smog
      "DisableTargetStatusMoves",    # Taunt
      "EncoreTarget"                 # Encore
    ]
    has_reserve_answer = reserves.any? do |pkmn|
      next false unless pkmn
      next true if pkmn.hasAbility?(:UNAWARE)
      pkmn.moves.any? { |m| answer_codes.include?(m.function_code) }
    end
    next false unless has_reserve_answer

    PBDebug.log_ai(
      "#{user.name}: foe has #{foe_total_boosts} positive boosts, reserves have answers — should switch."
    )
    next true
  }
)

#===============================================================================
# [NEW] Cancel the switch if the current Pokémon can handle the boosted foe
# itself. Checked after ShouldSwitch returns true.
#
# Move-based answers only count when the user can act first
# (foe cannot OHKO, or foe can OHKO but user is faster).
# Focus Sash / Sturdy only counts when the foe can OHKO (making the item
# relevant) and there is effective counterplay on the surviving turn.
#===============================================================================
Battle::AI::Handlers::ShouldNotSwitch.add(:current_can_answer_boosted_foe,
  proc { |user, reserves, ai, battle|
    # Only relevant when there is a boosted foe
    threatening_foe  = nil
    foe_total_boosts = 0
    ai.each_foe_battler(user.side) do |b, i|
      boosts = 0
      GameData::Stat.each_battle { |s| boosts += b.stages[s.id] if b.stages[s.id] > 0 }
      if boosts >= 2
        threatening_foe  = b
        foe_total_boosts = boosts
        break
      end
    end
    next false unless threatening_foe

    # 1. Unaware: passive, always valid regardless of speed/OHKO
    next true if user.has_active_ability?(:UNAWARE)

    # Pre-compute OHKO threat for both move-based and sash checks
    foe_can_ohko        = false
    foe_ohko_and_faster = false
    ai.each_foe_battler(user.side) do |b, _i|
      if ai.damage_moves(b, user).values.any? { |md| md[:dmg] >= user.battler.hp }
        foe_can_ohko = true
        faster = b.rough_stat(:SPEED) > user.rough_stat(:SPEED)
        foe_ohko_and_faster = true if faster
        PBDebug.log("[should_not_switch] #{b.name} can OHKO #{user.name}#{faster ? ' (faster)' : ' (slower)'}")
      end
    end
    can_act_first = !foe_ohko_and_faster

    # 2–6. Move-based answers: only valid when we can act before being KO'd
    if can_act_first || user.has_active_ability?(:STURDY) || user.has_active_item?(:FOCUSSASH)
      # 2. Phazing (Whirlwind, Roar, Dragon Tail, Circle Throw)
      next true if user.check_for_move { |m|
        ["SwitchOutTargetStatusMove",
         "SwitchOutTargetDamagingMove"].include?(ai.safe_function_code(m))
      }

      # 3. Haze / Clear Smog
      next true if user.check_for_move { |m|
        ["ResetAllBattlersStatStages",
         "ResetTargetStatStages"].include?(ai.safe_function_code(m))
      }

      # 4. Taunt: stops further setup
      next true if user.check_for_move { |m|
        ai.safe_function_code(m) == "DisableTargetStatusMoves"
      }

      # 5. Encore: locks foe into its current move
      next true if user.check_for_move { |m|
        ai.safe_function_code(m) == "EncoreTarget"
      }

      # 6. Pivot (U-turn, Volt Switch, Parting Shot, etc.):
      #    use the pivot itself to bring in a better answer
      next true if user.check_for_move { |m|
        ai.safe_function_code(m)&.start_with?("SwitchOutUser")
      }

      # 7. Status move that can actually land on the foe.
      status_func_pairs = [
        ["BadPoisonTarget", :BAD_POISON],
        ["PoisonTarget",    :POISON],
        ["BurnTarget",      :BURN],
        ["ParalyzeTarget",  :PARALYSIS],
        ["SleepTarget",     :SLEEP],
        ["FreezeTarget",    :FROZEN]
      ]
      user.battler.moves.each do |m|
        next unless m&.statusMove?
        func   = ai.safe_function_code(m)
        next unless func
        status = status_func_pairs.find { |key, _| func.include?(key) }&.last
        next unless status
        next true if threatening_foe.battler.pbCanInflictStatus?(status, user.battler, false, m)
      end

      # 8. Can KO or deal significant damage (any move, since we can act first)
      best_dmg = ai.damage_moves(user, threatening_foe).values.map { |md| md[:dmg] }.max || 0
      if best_dmg >= threatening_foe.hp
        PBDebug.log_ai("[should_not_switch] #{user.name} can KO #{threatening_foe.name} (#{best_dmg} >= #{threatening_foe.hp} hp)")
        next true
      elsif best_dmg >= threatening_foe.totalhp * 0.5
        PBDebug.log_ai("[should_not_switch] #{user.name} can deal #{best_dmg} (>=50%) to #{threatening_foe.name}")
        next true
      end
    end

    # 9. Priority moves let the user act first regardless of speed/OHKO threat
    priority_dmg = ai.damage_moves(user, threatening_foe).values
      .select { |md| md[:move].priority > 0 }
      .map { |md| md[:dmg] }.max || 0
    if priority_dmg >= threatening_foe.hp
      PBDebug.log_ai("[should_not_switch] #{user.name} can KO #{threatening_foe.name} with priority (#{priority_dmg} >= #{threatening_foe.hp} hp)")
      next true
    elsif priority_dmg >= threatening_foe.totalhp * 0.5
      PBDebug.log_ai("[should_not_switch] #{user.name} can deal #{priority_dmg} (>=50%) to #{threatening_foe.name} with priority")
      next true
    end

    next false
  }
)
