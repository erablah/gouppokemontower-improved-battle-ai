#===============================================================================
# 2. GeneralMoveAgainstTargetScore Handlers
#===============================================================================

#===============================================================================
# override predicted_damage more score for predicted KO move
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:predicted_damage,
  proc { |score, move, user, target, ai, battle|
    if move.damagingMove?
      dmg = move.rough_damage
      old_score = score
      if target.effects[PBEffects::Substitute] > 0
        target_hp = target.effects[PBEffects::Substitute]
        score += ([15.0 * dmg / target.effects[PBEffects::Substitute], 20].min).to_i
        PBDebug.log_score_change(score - old_score, "damaging move (predicted damage #{dmg} = #{100 * dmg / target.hp}% of target's Substitute)")
      else
        score += ([25.0 * dmg / target.hp, 30].min).to_i
        PBDebug.log_score_change(score - old_score, "damaging move (predicted damage #{dmg} = #{100 * dmg / target.hp}% of target's HP)")
        if ai.trainer.has_skill_flag?("HPAware") && dmg > target.hp * 1.1   # Predicted to KO the target
          old_score = score
          score += 40
          PBDebug.log_score_change(score - old_score, "predicted to KO the target")
          if move.move.multiHitMove? && target.hp == target.totalhp &&
             (target.has_active_ability?(:STURDY) || target.has_active_item?(:FOCUSSASH))
            old_score = score
            score += 8
            PBDebug.log_score_change(score - old_score, "predicted to overcome the target's Sturdy/Focus Sash")
          end
        end
      end
    end
    next score
  }
)

#===============================================================================
# 6. 능동적 피벗 기술(U-turn, Volt Switch 등) 점수 상향
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:boost_pivot_moves,
  proc { |score, move, user, target, ai, battle|
    next score if !ai.trainer.high_skill?
    next score if !battle.pbCanChooseNonActive?(user.battler.index)

    is_pivot = [
      "SwitchOutUserDamagingMove"
    ].include?(ai.safe_function_code(move))
    next score unless is_pivot

    score += 10

    # Prefer if target is slower than a foe
    if !user.faster_than?(target)
      score += 5
      PBDebug.log_score_change(5, "6. Slow Pivot preference.")
    end

    PBDebug.log_score_change(10, "6. Active Pivot move boost.")
    next score
  }
)

#===============================================================================
# 16. 단일 랭크 하락 기술 감점
#===============================================================================
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:nerf_weak_debuffs,
  proc { |score, move, user, target, ai, battle|
    if move.statusMove? &&
       ai.safe_function_code(move)&.include?("LowerTarget") &&
       ai.safe_function_code(move)&.end_with?("1")
      score -= 20
    end
    next score
  }
)

#-------------------------------------------------------------------------------
# [NEW] 쓸모없는 기술(저데미지) 감점
#-------------------------------------------------------------------------------
Battle::AI::Handlers::GeneralMoveAgainstTargetScore.add(:penalize_useless_moves,
  proc { |score, move, user, target, ai, battle|
    if move.damagingMove?
      pct_dmg = move.rough_damage.to_f / target.totalhp.to_f
      will_ko = move.rough_damage.to_f >= target.hp.to_f
      next if will_ko

      if pct_dmg < 0.20
        score -= 100
        PBDebug.log_score_change(-100, "Penalize useless move: very low predicted damage (#{(pct_dmg * 100).round(1)}%).")
      elsif pct_dmg < 0.40
        score -= 20
        PBDebug.log_score_change(-20, "Penalize weak move: consider switching (#{(pct_dmg * 100).round(1)}%).")
      end
    end
    next score
  }
)


