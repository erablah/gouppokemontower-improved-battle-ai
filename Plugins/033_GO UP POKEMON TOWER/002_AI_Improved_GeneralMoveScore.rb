#===============================================================================
# 1. GeneralMoveScore Handlers
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:smart_setup_move_final,
  proc { |score, move, user, ai, battle|
    next score unless ai.trainer.high_skill?
    next score unless move.statusMove?
    next score unless ai.safe_function_code(move)&.start_with?("RaiseUser")

    battler = user.battler
    next score unless battler

    hp_ratio = battler.hp.to_f / battler.totalhp

    # 기본적으로 랭크업은 위험하다고 가정
    score -= 50
    PBDebug.log_score_change(
      -50,
      "GLOBAL NERF: Setup moves are inherently risky."
    )

    # 1. HP 30% 이하 → 무조건 랭크업 금지
    if hp_ratio <= 0.3
      score -= 100
      PBDebug.log_score_change(
        -100,
        "Setup blocked: HP <= 30%."
      )
      next score
    end

    # 2. 껍질깨기 절대 1회 제한
    if move.id == :SHELLSMASH
      # 껍질깨기의 핵심 상승 스탯 중 하나라도 +2 이상이면 사용 금지
      if battler.stages[:ATTACK] >= 2 ||
         battler.stages[:SPECIAL_ATTACK] >= 2 ||
         battler.stages[:SPEED] >= 2
        score = Battle::AI::MOVE_USELESS_SCORE
        PBDebug.log_score_change(
          score,
          "Shell Smash blocked: boosts already applied."
        )
        next score
      end
    end

    # 2-B. 상대에게 유효타(40% 초과)가 없으면 랭크업 금지
    has_good_damage = false
    has_any_damaging_move = false
    battler.moves.each do |m|
      next unless m.damagingMove?
      has_any_damaging_move = true

      simulated_move = Battle::AI::AIMove.new(ai)
      simulated_move.set_up(m)
      
      ai.each_foe_battler(user.side) do |b, i|
        # Simulate damage from 'user' to opponent 'b' using move 'm'
        predicted_dmg = simulated_move.predicted_damage(move: move, user: user, target: b)
        if predicted_dmg.to_f / b.battler.totalhp.to_f > 0.4
          has_good_damage = true
          break
        end
      end
      break if has_good_damage
    end
    
    if has_any_damaging_move && !has_good_damage
      score -= 50
      PBDebug.log_score_change(
        -50,
        "Setup blocked: No damaging move can do >40% of target HP."
      )
      next score
    end

    # 3. 목표 랭크(총합 기준) 도달 시 추가 랭크업 금지
    IDEAL_TOTAL_BOOST = 2

    total_positive_boosts = 0
    GameData::Stat.each_battle do |s|
      stage = battler.stages[s.id]
      total_positive_boosts += stage if stage > 0
    end

    if total_positive_boosts >= IDEAL_TOTAL_BOOST
      score -= 100
      PBDebug.log_score_change(
        -100,
        "Setup blocked: total boost >= #{IDEAL_TOTAL_BOOST}."
      )
      next score
    end

    score += 40
    PBDebug.log_score_change(
      40,
      "Safe setup: all strict conditions satisfied."
    )

    next score
  }
)

#===============================================================================
# 2. 랭크업 연계 기술(Stored Power 등) 시너지
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:boost_setup_synergy,
  proc { |score, move, user, ai, battle|
    next score if !move.statusMove?

    # user는 AIBattler. battler는 실제 Battle::Battler
    has_stored_power = user.check_for_move do |m|
      ["PowerHigherWithUserPositiveStatStages",
       "PowerIncreasedByTargetStatChanges"].include?(ai.safe_function_code(m))
    end

    if has_stored_power && ai.safe_function_code(move)&.start_with?("RaiseUser")
      score += 80
      PBDebug.log_score_change(80, "2. Setup synergy with Stored Power.")
    end
    next score
  }
)

#===============================================================================
# 9. 해저드/벽 중복 설치 방지
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:prevent_redundant_setup,
  proc { |score, move, user, ai, battle|
    penalty = 0
    case ai.safe_function_code(move)
    when "AddStealthRocksToFoeSide"
      penalty = -200 if user.pbOpposingSide.effects[PBEffects::StealthRock]
    when "AddSpikesToFoeSide"
      penalty = -200 if user.pbOpposingSide.effects[PBEffects::Spikes] >= 3
    when "AddToxicSpikesToFoeSide"
      penalty = -200 if user.pbOpposingSide.effects[PBEffects::ToxicSpikes] >= 2
    when "AddStickyWebToFoeSide"
      penalty = -200 if user.pbOpposingSide.effects[PBEffects::StickyWeb]
    when "UserSideDamageReduction" # Reflect, Light Screen, Aurora Veil
      is_reflect     = (move.id == :REFLECT)
      is_lightscreen = (move.id == :LIGHTSCREEN)
      is_aurora      = (move.id == :AURORAVEIL)

      own_side = user.pbOwnSide
      penalty = -200 if is_reflect     && own_side.effects[PBEffects::Reflect] > 0
      penalty = -200 if is_lightscreen && own_side.effects[PBEffects::LightScreen] > 0
      penalty = -200 if is_aurora      && own_side.effects[PBEffects::AuroraVeil] > 0
    end

    if penalty != 0
      score += penalty
      PBDebug.log_score_change(penalty, "9. Redundant setup prevention.")
    end
    next score
  }
)

#===============================================================================
# 15. 일반 상태 이상 기술 기본 점수 상향
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:boost_general_status_moves,
  proc { |score, move, user, ai, battle|
    next score if !ai.trainer.high_skill?

    if move.statusMove? &&
       !ai.safe_function_code(move)&.start_with?("ProtectUserEvenFromDynamaxMoves")
      score += 10
      PBDebug.log_score_change(10, "10. General Status Move Boost.")
    end
    next score
  }
)

#===============================================================================
# 18. 미부스트 Stored Power 사용 억제
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:suppress_weak_stored_power,
  proc { |score, move, user, ai, battle|
    if ai.safe_function_code(move) == "PowerHigherWithUserPositiveStatStages"
      total_boosts = 0
      battler = user.battler
      if battler
        GameData::Stat.each_battle do |s|
          total_boosts += battler.stages[s.id] if battler.stages[s.id] > 0
        end
      end

      if total_boosts < 2
        score -= 50
        PBDebug.log_score_change(-50, "18. Stored Power without boosts.")
      end
    end
    next score
  }
)

#-------------------------------------------------------------------------------
# [NEW] 비공격 행동 연속 반복 억제
# - 교체/피벗/대타/벽 남용 방지
#-------------------------------------------------------------------------------
Battle::AI::Handlers::GeneralMoveScore.add(
  :discourage_repetitive_non_attack,
  proc { |score, move, user, ai, battle|
    battler = user.battler
    last_fc = battler && battler.lastMoveUsed ? ai.safe_function_code(battler.lastMoveUsed) : nil
    next score unless last_fc

    if !move.damagingMove? &&
       ["RaiseUser",
        "SwitchOutUserDamageTarget",
        "SwitchOutUserStatusTarget",
        "UserSideDamageReduction",
        "Substitute"].any? { |key| last_fc.start_with?(key) }
      score -= 40
    end

    PBDebug.log_ai("비공격 행동 반복 억제")

    next score
  }
)

#===============================================================================
# [NEW] 전술적 대타출동 (SUBSTITUTE) 활용 AI
#===============================================================================
Battle::AI::Handlers::GeneralMoveScore.add(:tactical_substitute,
  proc { |score, move, user, ai, battle|
    # 대타출동 아니면 패스
    next score unless move.id == :SUBSTITUTE

    battler = user.battler
    next score unless battler

    # 이미 대타가 있으면 사용 안 함
    next Battle::AI::MOVE_USELESS_SCORE if battler.effects[PBEffects::Substitute] > 0

    # HP가 충분하지 않으면 사용 안 함 (대략 60% 이상 필요)
    hp_ratio = battler.hp.to_f / battler.totalhp
    next Battle::AI::MOVE_USELESS_SCORE if hp_ratio < 0.60

    # 이번 턴에 공격하면 바로 KO 가능하면 대타 불필요
    can_ko_target = false
    user.battler.moves.each do |m|
      next unless m.damagingMove?

      simulated_move = Battle::AI::AIMove.new(ai)
      simulated_move.set_up(m)
      ai.each_foe_battler(user.side) do |b, i|
        predicted_dmg = simulated_move.predicted_damage(move: move, user: user, target: b)
        if predicted_dmg >= b.hp
          can_ko_target = true
          break
        end
      end
      break if can_ko_target
    end
    next Battle::AI::MOVE_USELESS_SCORE if can_ko_target

    # -------------------------------------------------------------------------
    # B. 상대 압박 분석
    # -------------------------------------------------------------------------
    threatened = false
    ai.each_foe_battler(user.side) do |b, i|
      b.battler.moves.each do |m|
        next unless m.damagingMove?
        eff = Effectiveness.calculate(m.type, *ai.safe_types(battler))
        threatened = true if Effectiveness.super_effective?(eff)
      end
      break if threatened
    end

    # 약점 맞는 상황에서 대타는 오히려 손해
    next Battle::AI::MOVE_USELESS_SCORE if threatened

    # -------------------------------------------------------------------------
    # C. 대타 이후 계획 판단
    # -------------------------------------------------------------------------

    future_value = 0

    # 1) 랭크업 기술이 있으면 대타 가치 상승
    if user.check_for_move { |m| ai.safe_function_code(m)&.start_with?("RaiseUser") }
      future_value += 40
    end

    # 2) 상태이상 기술이 있으면 가치 상승
    if user.check_for_move { |m|
         ["SleepTarget", "PoisonTarget", "BurnTarget", "ParalyzeTarget"].include?(ai.safe_function_code(m))
       }
      future_value += 30
    end

    # 3) 명중 불안정 기술 / 준비 턴이 필요한 기술
    if user.check_for_move { |m| m.accuracy < 100 }
      future_value += 15
    end

    # 기본 가중치 (너무 높지 않게)
    bonus = 40 + future_value

    score += bonus
    PBDebug.log_score_change(
      bonus,
      "Tactical Substitute (HP=#{(hp_ratio * 100).to_i}%)."
    )

    next score
  }
)


Battle::AI::Handlers::GeneralMoveScore.add(:evade_knockout,
  proc { |score, move, user, ai, battle|
    # Skip if move has >= 2 priority (e.g. Extreme Speed)
    next score if move.move.priority >= 2

    # Skip if user has Sturdy, Focus Sash, or an active Substitute
    has_substitute = user.effects[PBEffects::Substitute] > 0
    has_focus_sash = user.has_active_item?(:FOCUSSASH)
    has_sturdy = user.has_active_ability?(:STURDY)
    next score if has_substitute || has_focus_sash || has_sturdy

    max_foe_speed = 0
    foe_can_ko = false
    
    ai.each_foe_battler(user.side) do |b, i|
      next if !b.can_attack?
      max_foe_speed = [max_foe_speed, b.rough_stat(:SPEED)].max
      
      if b.check_for_move { |m|
          will_ko = false
           if m.damagingMove?
            simulated_move = Battle::AI::AIMove.new(ai)
            simulated_move.set_up(m)

            predicted_dmg = simulated_move.predicted_damage(move: move, user: b, target: user)
            PBDebug.log("checking foe damage #{m.name} #{predicted_dmg} = #{100 * predicted_dmg / [1, user.hp].max}%")
            will_ko = (predicted_dmg >= user.hp * 0.9)
           end
           will_ko
         }
        foe_can_ko = true
      end
    end
    
    user_speed = [user.rough_stat(:SPEED), 1].max

    if user_speed < max_foe_speed && foe_can_ko
      speed_ratio = max_foe_speed.to_f / user_speed.to_f
      # speed chance should check for 1.2 instead of 1.5 
      chance = ((speed_ratio - 1.0) / 0.2 * 100).to_i.clamp(0, 100)
      PBDebug.log("evade KO switch chance is #{chance}%")
      
      if ai.pbAIRandom(100) <= chance
        score -= 100
        PBDebug.log_score_change(-100, "Penalize move: user is slower than a foe who can KO. (Speed ratio: #{speed_ratio.round(2)}, Chance: #{chance}%)")
      end
    end

    next score
  }
)


