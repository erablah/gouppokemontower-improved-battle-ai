#===============================================================================
# 4. GeneralItemScore Handlers
#===============================================================================

#===============================================================================
# ITEM AI SUPPORT – Ace-focused & Switch-aware Item Usage
#  - DBK Improved Item AI를 문어발 수정하지 않음
#  - 아이템 사용 점수를 "조정"하여 행동을 유도
#===============================================================================

Battle::AI::Handlers::GeneralItemScore.add(
  :ai_improved_item_priority_control,
  proc { |score, item, idxPkmn, idxMove, ai, battle|

    user_ai  = ai.user
    battler = user_ai&.battler
    next score unless battler
    next score unless item

    # -------------------------------------------------------------------------
    # 2. HP 안정 구간(초록 피)에서는 회복 아이템 강하게 억제
    # -------------------------------------------------------------------------
    hp_ratio = battler.hp.to_f / battler.totalhp

    if hp_ratio > 0.6
      score -= 120
      PBDebug.log_score_change(
        -120,
        "ITEM AI: HP is healthy (>60%), healing discouraged."
      )
    end

    # -------------------------------------------------------------------------
    # 3. 다음 턴 사망 위험 판단
    # -------------------------------------------------------------------------
    lethal_next = false

    ai.each_foe_battler(user_ai.side) do |b, i|
      b.battler.moves.each do |m|
        next unless m&.damagingMove?

        move = Battle::AI::AIMove.new(ai)
        move.set_up(m)
        
        dmg = move.predicted_damage(move: move, user: b, target: user_ai)
        lethal_next = true if dmg >= battler.hp
      end
    end

    unless lethal_next
      score -= 80
      PBDebug.log_score_change(
        -80,
        "ITEM AI: No lethal threat next turn, healing discouraged."
      )
    end

    can_switch = battle.pbCanChooseNonActive?(battler.index)

    # -------------------------------------------------------------------------
    # 5. 에이스 후보 판정
    # -------------------------------------------------------------------------
    party = battle.pbParty(battler.index)
    party_size = party.length
    ace_candidate = false

    if idxPkmn
      # 파티 후반부 여부
      is_late_party = (idxPkmn >= (party_size * 0.6).floor)

      # 공격 기술 보유 여부
      has_attacks = false
      pkmn = party[idxPkmn]
      if pkmn && pkmn.moves
        damaging_moves = pkmn.moves.count do |m|
          m && GameData::Move.get(m.id).category != 2
        end
        has_attacks = (damaging_moves >= 2)
      end
      
      ace_candidate = is_late_party && has_attacks
    end

    # -------------------------------------------------------------------------
    # 6. 타입 상성 계산
    # -------------------------------------------------------------------------
    type_eff = 1.0
    
    ai.each_foe_battler(user_ai.side) do |b, i|
      b.battler.types.each do |t|
        eff = Effectiveness.calculate(t, *ai.safe_types(battler))
        type_eff *= eff / Effectiveness::NORMAL_EFFECTIVE_MULTIPLIER
      end
    end

    bad_matchup = (type_eff >= 2.0)

    # 상성 불리 + 교체 가능 → 아이템 억제
    if bad_matchup && can_switch
      score -= 60
      PBDebug.log_score_change(
        -60,
        "ITEM AI: Prefer switching over item (bad matchup)."
      )
    end

    # 에이스가 아니면 억제
    unless ace_candidate
      score -= 40
      PBDebug.log_score_change(
        -40,
        "ITEM AI: Non-ace Pokémon, item discouraged."
      )
    end

    # 에이스면 보정
    if ace_candidate
      score += 60
      PBDebug.log_score_change(
        60,
        "ITEM AI: Ace Pokémon preservation priority."
      )
    end

    # -------------------------------------------------------------------------
    # 8. 교체 불가 + 치명적 HP → 아이템 허용
    # -------------------------------------------------------------------------
    if !can_switch && battler.hp < battler.totalhp * 0.25
      score += 30
      PBDebug.log_score_change(
        30,
        "ITEM AI: Forced item (cannot switch, low HP)."
      )
    end

    next score
  }
)

