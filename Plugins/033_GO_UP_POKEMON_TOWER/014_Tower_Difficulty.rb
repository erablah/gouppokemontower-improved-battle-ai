#===============================================================================
# * 헬퍼 함수: 진화하지 않는 포켓몬인지 확인
# * GameData::Species를 사용하여 Evolutions 항목이 비어있는지 확인합니다.
#===============================================================================
def pbIsNonEvolvingTrainerPokemon?(pokemon)
  species_data = GameData::Species.get(pokemon.species)
  # 진화 목록이 비어 있으면 (즉, 최종 진화체 또는 진화 라인 없음) true 반환
  return species_data.get_evolutions.empty?
end

#===============================================================================
# * Custom Difficulty Plugin - 1단계: 회차 기반 포켓몬 수 조절 (필터링 포함)
# * Variable 67: 회차 정보
#===============================================================================

EventHandlers.add(:on_trainer_load, :difficulty_pokemon_count_with_filter,
  proc { |trainer|
    next unless trainer # 트레이너 객체가 유효한지 확인
    
    # 1. 트레이너 필터링 로직 (제외 대상 확인)
    ttype = trainer.trainer_type.to_s rescue nil

    next if trainer.name.start_with?("test")
    
    # 제외 대상 트레이너 타입 접두사 및 특정 이름 리스트
    EXCLUDED_PREFIXES = ["LEADER_", "NEON_", "CHAMPION_"]
    EXCLUDED_NAMES = [
      "RED", "LEAF", "GOLD", "LYRA", "RUBY", "MAY", "LUCAS", "DAWN", 
      "HILBERT", "HILDA", "NATE", "ROSA", "CALEM", "SERENA", "ELIO", 
      "SELENE", "VICTOR", "GLORIA", "FLORIAN", "JULIANA", "FARHAN", 
      "ELODIE", "VEGA", "ESMERALDA"
    ]
    
    # 제외 대상인지 확인
    is_excluded = false
    if ttype
      is_excluded = EXCLUDED_PREFIXES.any? { |prefix| ttype.start_with?(prefix) }
    end
    # 트레이너 이름도 확인 (트레이너 타입이 이름과 동일할 경우)
    if !is_excluded && ttype
        is_excluded = EXCLUDED_NAMES.include?(ttype)
    end
    
    # 제외 대상이라면 포켓몬 제거 로직을 실행하지 않고 종료 (PASS)
    next if is_excluded 
    
    # 2. 회차 확인 및 제거 로직 실행
    current_cycle = $game_variables[67]

    # 0~3회차일 때만 포켓몬 1마리 제거 로직 적용
    if current_cycle >= 0 && current_cycle <= 3
      
      # 트레이너의 파티 길이가 1보다 클 때만 제거 가능
      if trainer.party.length > 1
        
        non_evolving_indices = []
        # 파티를 돌며 진화하지 않는 포켓몬의 인덱스 수집
        trainer.party.each_with_index do |pkmn, i|
          if pbIsNonEvolvingTrainerPokemon?(pkmn)
            non_evolving_indices.push(i)
          end
        end
        
        index_to_remove = nil
        
        # 진화하지 않는 포켓몬이 있으면 그 중에서 랜덤 선택
        if !non_evolving_indices.empty?
          index_to_remove = non_evolving_indices.sample
        else
          # 없으면 전체 중 랜덤 제거
          all_indices = (0...trainer.party.length).to_a
          index_to_remove = all_indices.sample
        end
        
        # 포켓몬 제거 실행
        if index_to_remove != nil
          trainer.remove_pokemon_at_index(index_to_remove)
        end
      end
    end
    # 4회차 이상일 때는 제거 로직을 건너뛰고 모든 포켓몬을 사용합니다.
  }
)


#===============================================================================
# * Custom Difficulty Plugin - 2단계: 회차 기반 트레이너 아이템 추가 (최종본)
# * 4~6회차: 고급상처약 추가
# * 7회차 이상: 회복약 및 만병통치제 추가
#===============================================================================

EventHandlers.add(:on_trainer_load, :difficulty_item_addition_final,
  proc { |trainer|
    next unless trainer
    
    # @items 인스턴스 변수에 직접 접근 및 배열로 처리
    # @items 변수가 정의되어 있지 않으면 빈 배열([])로 초기화 (배열이라고 가정)
    unless trainer.instance_variable_defined?(:@items)
      trainer.instance_variable_set(:@items, [])
    end
    
    # @items의 현재 값을 가져와 item_list 변수에 할당 (현재 item_list는 배열)
    item_list = trainer.instance_variable_get(:@items)
    
    current_cycle = $game_variables[67]
    
    # ----------------------------------------------------------------------
    # 1. 회차 4~6일 때만 고급상처약 추가 (:HYPERPOTION)
    # ----------------------------------------------------------------------
    # 4 <= current_cycle <= 6 일 때만 추가합니다.
    if current_cycle >= 4 && current_cycle <= 4
      item_list.push(:HYPERPOTION)
    end
    
    if current_cycle >= 5 && current_cycle <= 6
      item_list.push(:MAXPOTION)
    end
	
    # ----------------------------------------------------------------------
    # 2 & 3. 회차 7 이상: 회복약 및 만병통치제 추가
    # ----------------------------------------------------------------------
    if current_cycle >= 7
      # 회복약 1개 추가 (모든 트레이너)
      item_list.push(:FULLRESTORE)
      
      # 만병통치제 추가 필터링 로직 (특정 트레이너 제외)
      ttype = trainer.trainer_type.to_s rescue nil
      
      EXCLUDED_PREFIXES = ["LEADER_", "NEON_", "CHAMPION_"]
      EXCLUDED_NAMES = [
        "RED", "LEAF", "GOLD", "LYRA", "RUBY", "MAY", "LUCAS", "DAWN", 
        "HILBERT", "HILDA", "NATE", "ROSA", "CALEM", "SERENA", "ELIO", 
        "SELENE", "VICTOR", "GLORIA", "FLORIAN", "JULIANA", "FARHAN", 
        "ELODIE", "VEGA", "ESMERALDA"
      ]
      
      is_excluded = false
      if ttype
        is_excluded = EXCLUDED_PREFIXES.any? { |prefix| ttype.start_with?(prefix) }
      end
      if !is_excluded && ttype
        is_excluded = EXCLUDED_NAMES.include?(ttype)
      end
      
      unless is_excluded
        # 만병통치제 1개 추가 (필터링되지 않은 트레이너만)
        item_list.push(:FULLHEAL)
      end
    end
    
    # 변경된 item_list (배열)를 @items 인스턴스 변수에 다시 설정
    trainer.instance_variable_set(:@items, item_list)
  }
)

#===============================================================================
# Absolute Egg Hatch Fix (Runs on Player Update)
#===============================================================================

module AbsoluteEggHatchFix
  FORCED_HATCH_STEPS = 1500  # 원하는 숫자
end

class Game_Player < Game_Character
  alias _fastegg_update update
  def update
    _fastegg_update
    absolute_egg_step_tick
  end

  def absolute_egg_step_tick
    return if !$player || !$player.party

    $player.party.each do |pkmn|
      next if !pkmn.egg?
      # 알 생성 즉시 강제 스텝 설정 (원본 PBS 무시)
      if pkmn.steps_to_hatch > AbsoluteEggHatchFix::FORCED_HATCH_STEPS
        pkmn.steps_to_hatch = AbsoluteEggHatchFix::FORCED_HATCH_STEPS
      end
      # 매 프레임 1씩 감소
      if pkmn.steps_to_hatch > 0
        pkmn.steps_to_hatch -= 1
        # 부화 트리거
        if pkmn.steps_to_hatch <= 0
          pkmn.steps_to_hatch = 0
          pbHatch(pkmn)
          break
        end
      end
    end
  end
end
