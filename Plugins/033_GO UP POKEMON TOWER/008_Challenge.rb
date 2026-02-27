#===============================================================================
# ⚔️ 챌린지 모드 플러그인 (최종 수정: 안전성 강화 버전)
#===============================================================================

# 0. 포켓몬 클래스에 영구 삭제 여부를 저장할 속성 추가
class Pokemon
  attr_accessor :permadeath_deleted
end

# 1. Battle 클래스의 pbEndOfBattle을 Alias하여 종료 시 안전장치 추가
#    (이 부분은 보내주신 파일의 포케러스 에러를 100% 방지합니다)
class Battle
  alias permadeath_pbEndOfBattle pbEndOfBattle

  # pbEndOfBattle이 인수를 받지 않도록 재정의 (given 0)
  def pbEndOfBattle
    # 챌린지 모드가 켜져 있다면
    if $game_switches && $game_switches[310]
      # 배틀 종료 처리를 하기 전에, 파티의 빈 공간(nil)을 정리합니다.
      if $player && $player.party
        $player.party.compact! 
      end
    end
    
    # 원래의 배틀 종료 로직 실행 (인수 없이 호출)
    permadeath_pbEndOfBattle
  end
end

# 2. Battle::Battler 클래스의 pbFaint를 Alias하여 기절 시 삭제 로직 추가
class Battle::Battler
  alias permadeath_pbFaint pbFaint

  def pbFaint(showMessage = true)
    # 1. 원래 게임의 기절 처리를 먼저 수행 (HP 0 처리 등)
    permadeath_pbFaint(showMessage)

    # 2. 챌린지 조건 확인
    # 스위치 310번 ON + 플레이어 포켓몬 + HP 0 이하
    if $game_switches && $game_switches[310] && pbOwnedByPlayer? && @hp <= 0
      
      # 해당 포켓몬이 이미 삭제 처리되었는지 확인 (Pokemon 객체에 플래그 저장)
      # 이렇게 하면 배틀러가 재사용되어도 문제없이 작동합니다.
      return if self.pokemon.permadeath_deleted

      # 삭제 플래그 설정
      self.pokemon.permadeath_deleted = true

      # 3. 메시지 출력
      @battle.pbDisplayPaused(_INTL("노페인트 챌린지 룰에 따라 \\j[{1},은,는] 파티에서 제외되었다!", self.name))

      # 4. 파티에서 '안전하게' 제거 (nil로 설정)
      # 배틀 중에는 배열을 압축(compact)하면 인덱스 오류가 발생하므로,
      # 일단 nil로 만들어 빈 슬롯으로 둡니다.
      
      # 현재 배틀러가 참조하는 실제 파티 배열을 가져옵니다.
      party = @battle.pbParty(self.index)
      
      # 인덱스가 유효한지 확인하고 nil로 설정
      if party[self.pokemonIndex] == self.pokemon
         party[self.pokemonIndex] = nil
         # 실제 플레이어 파티($player.party)도 동일하게 처리 (동기화)
         $player.party[self.pokemonIndex] = nil if $player.party[self.pokemonIndex] == self.pokemon
      end
      
      # 디버그 로그
      PBDebug.log_ai("[Permadeath] #{self.name} deleted (slot set to nil).")
    end
  end
end


#===============================================================================
# 🚫 No Item Challenge (Switch 311 ON)
#   - 몬스터볼만 허용, 모든 다른 아이템 배틀 중 사용 불가
#===============================================================================
class Battle
  alias noitem_old_pbRegisterItem pbRegisterItem

  def pbRegisterItem(idxBattler, item, idxTarget = nil, idxMove = nil)
    # ● 플레이어 측이며, 챌린지 스위치 ON 상태일 때만 동작
    if $game_switches && $game_switches[311] && !opposes?(idxBattler)
      item_data = GameData::Item.get(item) rescue nil
      return nil if item_data.nil?

      # ● 몬스터볼인지 확인
      if item_data.is_poke_ball?
        # 몬스터볼은 정상 사용 허용
        return noitem_old_pbRegisterItem(idxBattler, item, idxTarget, idxMove)
      else
        # ● 몬스터볼 외 아이템은 차단
        pbMessage(_INTL(
          "노아이템 챌린지 룰에 따라 배틀 중에 \\[j{1},을,를] 사용할 수 없습니다.",
          item_data.name
        ))
        return false
      end
    end

    # ● 챌린지가 꺼져있으면 원래 로직
    return noitem_old_pbRegisterItem(idxBattler, item, idxTarget, idxMove)
  end
end
