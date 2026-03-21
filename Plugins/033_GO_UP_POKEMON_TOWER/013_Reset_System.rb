#===============================================================================
# ■ Game Data Reset System (Final, Debug-based)
#===============================================================================

def pbResetGameData
#--- 1. 소지 포켓몬 완전 삭제 (최종 수정: $player.party 적용)
  # $player 변수가 정의되어 있고 파티가 있다면 초기화합니다.
  if defined?($player) && $player && $player.party
    # 배열이 비워질 때까지 (포켓몬이 0마리 남을 때까지) 0번 인덱스의 포켓몬을 반복해서 지웁니다.
    while $player.party.length > 0
      $player.party.delete_at(0)
    end
  end

  #--- 2. 박스 포켓몬 초기화 (작동 확인되었으나, 안전을 위해 defined? 추가)
  if defined?($PokemonStorage) && $PokemonStorage
    for i in 0...$PokemonStorage.maxBoxes
      for j in 0...$PokemonStorage.maxPokemon(i)
        $PokemonStorage[i][j] = nil
      end
    end
  end

  #--- 3. 가방 초기화 (중요한 아이템 유지, 구조 완전 보존)
  if defined?($bag) && $bag
    key_pocket_id     = 8
    extra_keep_pocket = 10
    upgrade_token     = :UPGRADETOKEN

    # ● 백업: 8번(Key Items)
    important_items = $bag.pockets[key_pocket_id].map(&:clone)

    # ● 백업: 10번 포켓 
    extra_items = $bag.pockets[extra_keep_pocket].map(&:clone)

    # ● 1번 포켓: 업그레이드 토큰 "모든 슬롯" 유지
    keep_tokens = []
    if $bag.pockets[1]
      keep_tokens = $bag.pockets[1]
        .select { |entry| entry[0] == upgrade_token }
        .map(&:clone)
    end

    # ● 전체 초기화
    for i in 1...$bag.pockets.length
      if i == key_pocket_id
        $bag.pockets[i] = important_items.map(&:clone)

      elsif i == extra_keep_pocket
        $bag.pockets[i] = extra_items.map(&:clone)

      elsif i == 1
        # 업그레이드 토큰 전부 복원
        $bag.pockets[i] = keep_tokens.map(&:clone)

      else
        $bag.pockets[i] = []
      end
    end
  end
end

#===============================================================================
# ■ 배틀 패배 시 자동 초기화
#===============================================================================
class Battle
  alias __reset_on_defeat_endOfBattle pbEndOfBattle unless method_defined?(:__reset_on_defeat_endOfBattle)
  def pbEndOfBattle
    ret = __reset_on_defeat_endOfBattle
    if @decision == 2 || @decision == :lost || @decision == :defeat
      pbResetGameData
    end
    return ret
  end
end





#===============================================================================
# Trainer battle: Override "Run" button to trigger Forfeit menu
#===============================================================================
class Battle
  alias _forfeit_safe_pbRun pbRun
  def pbRun(idxBattler, duringBattle = false)
    battler = @battlers[idxBattler]

    # 플레이어가 트레이너 배틀에서 도망 시도 시
    if trainerBattle? && !battler.opposes?
      # 확인 메시지와 포기 처리 메뉴
      if pbConfirmMessage(_INTL("\\g도전 포기 시 소지금의 절반을 잃게 됩니다.\n정말 도전을 포기하시겠습니까?"))
        # "예" 선택 시만 포기 실행
        pbFadeOutIn {
          pbSEPlay("warp")
          pbResetGameData
          $player.money /= 2

          # 포기 후 이동 위치 설정
          $game_temp.player_new_map_id    = 2   # 예시 맵 ID
          $game_temp.player_new_x         = 18
          $game_temp.player_new_y         = 17
          $game_temp.player_new_direction = 1

          pbDismountBike
          $scene.transfer_player
          $game_map.autoplay
          $game_map.refresh
        }
        @decision = 3  # 배틀 종료
        return 1
      else
        # "아니오" 선택 시 배틀 유지
        return 0
      end
    end

    # 트레이너 배틀이 아니면 원래 도망 로직 그대로
    _forfeit_safe_pbRun(idxBattler, duringBattle)
  end
end


#===============================================================================
# Map transfer auto-save + reset screen tone
#===============================================================================
class Scene_Map
  alias _autosave_transfer_player transfer_player
  def transfer_player(*args)
    _autosave_transfer_player(*args)

    # 화면 톤 리셋
    $game_screen.start_tone_change(Tone.new(0, 0, 0, 0), 10)

    # 일반 스위치 리셋
    [267, 70, 305].each { |id| $game_switches[id] = false }

    # === 이벤트 1~6의 A 셀프 스위치만 안전하게 리셋 ===
    map = $game_map
    if map && map.events
      (1..6).each do |event_id|
        event = map.events[event_id]
        next unless event      # 존재하지 않으면 건너뜀
        key = [map.map_id, event_id, "A"]
        $game_self_switches[key] = false
      end
      # Map 67: 상점 갱신 NPC (이벤트 20) 셀프 스위치 리셋
      if map.map_id == 67
        $game_self_switches[[67, 20, "A"]] = false
      end
      $game_map.need_refresh = true
    end

    # 자동 저장 (실패해도 게임은 계속)
    if defined?(Game) && $player.respond_to?(:save_slot)
      begin
        Game.save($player.save_slot)
      rescue
        # 자동저장 실패는 무시
      end
    end
  end
end


