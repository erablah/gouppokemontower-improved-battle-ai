#===============================================================================
# * Healing Charm
#===============================================================================
# 스크립트 파일 맨 위에 추가
$LastHealingCharmSteps = 0 if !$LastHealingCharmSteps

def pbItemRestoreHP(pkmn, restoreHP)
  healingCharmMultiply = DrCharmConfig::HEALING_CHARM_MULTIPLY
  restoreHP *= healingCharmMultiply if $player.activeCharm?(:HEALINGCHARM)
  newHP = pkmn.hp + restoreHP
  newHP = pkmn.totalhp if newHP > pkmn.totalhp
  hpGain = newHP - pkmn.hp
  pkmn.hp = newHP
  return hpGain
end

EventHandlers.add(:on_player_step_taken, :gain_HP,
  proc {
    # 🚨 필수 검증 추가: $player, $PokemonGlobal, $Trainer 객체가 유효한지 확인
    next if !$player || !$PokemonGlobal || !$Trainer

    healingCharmHealOnStep = DrCharmConfig::HEALING_CHARM_HEAL_ON_STEP
    
    if $player.activeCharm?(:HEALINGCHARM)
      recovery_interval = healingCharmHealOnStep # e.g., 20
      steps_taken = $PokemonGlobal.happinessSteps
      
      # [$LastHealingCharmSteps가 nil인 경우 0으로 초기화]
      $LastHealingCharmSteps = 0 if $LastHealingCharmSteps.nil?
      
      # 1. 현재까지 발생했어야 할 총 회복 간격 수(HP)와 마지막 회복 간격 수를 계산합니다.
      current_intervals = steps_taken / recovery_interval
      last_recovered_intervals = $LastHealingCharmSteps / recovery_interval
      
      # 2. 마지막 회복 이후 새로 회복해야 할 증분량(HP)을 계산합니다.
      intervals_to_recover = current_intervals - last_recovered_intervals
      
      # 3. 회복이 필요한지 확인
      if intervals_to_recover > 0 && $Trainer.party.any? { |pkmn| pkmn.able? && pkmn.hp < pkmn.totalhp }
        
        hp_to_recover_per_pkmn = intervals_to_recover
        
        $Trainer.party.each do |pkmn|
          if pkmn.able? && pkmn.hp < pkmn.totalhp
            # 🎯 [핵심 수정]: hp_to_recover_per_pkmn 만큼 모든 포켓몬이 회복 (공유하지 않음)
            recovered_hp = [hp_to_recover_per_pkmn, pkmn.totalhp - pkmn.hp].min 
            pkmn.hp += recovered_hp
            pkmn.hp = pkmn.totalhp if pkmn.hp > pkmn.totalhp
          end
        end
        
        # 4. 마지막 회복 스텝을 현재 걸음 수의 가장 가까운 배수로 업데이트합니다.
        # 이렇게 해야 다음 회복이 정확히 다음 recovery_interval 후에 시작됩니다.
        $LastHealingCharmSteps = current_intervals * recovery_interval
        
        # 5. (선택 사항) 화면 갱신을 위해 플래그 설정
        # $game_temp.party_change = true 
      end
    end
  }
)
