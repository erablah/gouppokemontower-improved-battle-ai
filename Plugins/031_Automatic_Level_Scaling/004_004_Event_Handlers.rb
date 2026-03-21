#===============================================================================
# Automatic Level Scaling Event Handlers (with group sync and fixed level save)
# 수정됨: 순서 오류 및 메서드 오류 ('reset_moves') 최종 수정 완료.
#===============================================================================

# 🌿 야생 포켓몬 핸들러 수정
EventHandlers.add(:on_wild_pokemon_created, :automatic_wild_scaling_custom,
  proc { |pokemon|
    id = pbGet(LevelScalingSettings::WILD_VARIABLE)
    next if id == 0
    AutomaticLevelScaling.difficulty = id

    # 1. 레벨 스케일링 적용
    if AutomaticLevelScaling.settings[:use_map_level_for_wild_pokemon]
      pokemon.scale(AutomaticLevelScaling.getMapLevel($game_map.map_id))
    else
      pokemon.scale
    end
	
	# 2. 🚀 진화 단계 업데이트 (기술 업데이트보다 반드시 먼저 실행되어야 합니다.)
	AutomaticLevelScaling.setNewStage(pokemon)
    
    # 3. 📚 기술 업데이트 (ALS 스크립트에서 사용하는 'reset_moves' 호출)
    if AutomaticLevelScaling.settings[:update_moves]
      pokemon.reset_moves
    end
  }
)

EventHandlers.add(:on_enter_map, :define_map_level_custom,
  proc { |old_map_id|
    next if !AutomaticLevelScaling.settings[:use_map_level_for_wild_pokemon]
    next if $PokemonGlobal.map_levels.has_key?($game_map.map_id)

    id = pbGet(LevelScalingSettings::WILD_VARIABLE)
    next if id == 0
    AutomaticLevelScaling.difficulty = id

    $PokemonGlobal.map_levels[$game_map.map_id] = AutomaticLevelScaling.getScaledLevel
  }
)

#===============================================================================
# Automatic Level Scaling Event Handlers (with group sync and fixed level save)
#===============================================================================

# 🥊 트레이너 핸들러 수정 및 중복 코드 제거
EventHandlers.add(:on_trainer_load, :automatic_level_scaling_and_custom,
  proc { |trainer|
    id = pbGet(LevelScalingSettings::TRAINER_VARIABLE)
    next if !trainer || id == 0
    AutomaticLevelScaling.difficulty = id

  next if trainer.name == "test"

  # 🌟🌟🌟 [수정된 기능 3: 회차별 + 스위치 306 제어 + 트레이너 타입별 update_moves 설정] 🌟🌟🌟
  current_cycle = $game_variables[67]
  force_update_moves = $game_switches[306]   # ← 중요: 스위치 306 읽기

  # 🔥🔥🔥 스위치 306이 켜져 있다면 → 무조건 true (절대 false 되지 않음)
  if force_update_moves
    AutomaticLevelScaling.settings[:update_moves] = true

  else
    # 0~3회차일 경우 → 무조건 true
    if current_cycle < 3
      AutomaticLevelScaling.settings[:update_moves] = true
    
    else
      # 4회차 이상 → 특정 트레이너들만 false
      ttype = trainer.trainer_type.to_s rescue nil
      
      EXCLUDED_PREFIXES = ["LEADER_", "NEON_", "CHAMPION_", "ELITEFOUR_"]
      EXCLUDED_NAMES = [
        "RED", "LEAF", "GOLD", "LYRA", "RUBY", "MAY", "LUCAS", "DAWN",
        "HILBERT", "HILDA", "NATE", "ROSA", "CALEM", "SERENA", "ELIO",
        "SELENE", "VICTOR", "GLORIA", "FLORIAN", "JULIANA", "FARHAN",
        "ELODIE", "VEGA", "ESMERALDA", "LUCIEN",
      ]

      is_excluded = false
      if ttype
        is_excluded = EXCLUDED_PREFIXES.any? { |prefix| ttype.start_with?(prefix) }
        is_excluded ||= EXCLUDED_NAMES.include?(ttype)
      end


      if is_excluded
        AutomaticLevelScaling.settings[:update_moves] = false
      else
        AutomaticLevelScaling.settings[:update_moves] = true
      end
    end
  end
  # 🌟🌟🌟 [삽입 끝] 🌟🌟🌟


    #--------------------------------------------------------------------------
  # Group key extractor (for 1~3 or 1~4 sync)
  def extract_sync_keys(trainer)
    ttype = trainer.trainer_type.to_s
    name = trainer.name
    return nil if !ttype || !name

    number = nil
    if trainer.respond_to?(:version)
      number = trainer.version
    elsif trainer.instance_variable_defined?(:@version)
      number = trainer.instance_variable_get(:@version)
    end

    core_key = [ttype, name]
    version_key = number || 0

    if ttype =~ /^(LEADER|ELITEFOUR|CHAMPION)_/ && version_key > 0
      sync_range =
        if ttype.start_with?("LEADER_Goldie") || ttype.start_with?("LEADER_Melon")
          (1..4)
        else
          (1..3)
        end
      return sync_range.map { |v| [ttype, name, v] }, core_key
    end

    return [[ttype, name, version_key]], nil
  end

  #--------------------------------------------------------------------------
  # Try restore saved trainer levels first
  if AutomaticLevelScaling.settings[:save_trainer_parties] &&
      $PokemonGlobal.previous_trainer_party_levels

    keys, sync_key = extract_sync_keys(trainer)
    restored = false

    keys.each do |key|
      saved_party = $PokemonGlobal.previous_trainer_party_levels[key]
      next if !saved_party || saved_party.length != trainer.party.length

      sorted_saved = saved_party.sort_by { |pkmn| pkmn.respond_to?(:species_id) ? pkmn.species_id : 0 }
      sorted_current = trainer.party.sort_by { |pkmn| pkmn.respond_to?(:species_id) ? pkmn.species_id : 0 }

      for i in 0...sorted_current.length
        next unless sorted_saved[i]&.respond_to?(:level) && sorted_current[i]&.respond_to?(:level)
        sorted_current[i].level = sorted_saved[i].level
        sorted_current[i].calc_stats
      end
      trainer.heal_party
      restored = true
      puts "[ALS] 저장된 레벨 복원 성공: #{key.inspect}"
      break
    end
    next if restored
  end

  #--------------------------------------------------------------------------
  # ALS scaling (레벨 조정, 진화 단계, 기술 업데이트) - 중복 블록 통합 및 수정
  average_level = trainer.party_avarage_level rescue 1
  trainer.party.each do |pkmn|
    next if !pkmn || !pkmn.respond_to?(:level)
    
    # 1. 레벨 스케일링 적용
    if AutomaticLevelScaling.settings[:proportional_scaling]
      diff = pkmn.level - average_level
      pkmn.scale(AutomaticLevelScaling.getScaledLevel + diff)
    else
      pkmn.scale
    end
    
    # 2. 🚀 자동 진화 단계 업데이트 (AUTOMATIC_EVOLUTIONS 적용)
    # 레벨 스케일링 후 먼저 진화 단계를 조정합니다. (순서 수정)
    AutomaticLevelScaling.setNewStage(pkmn) 
    
    # 3. 📚 기술 업데이트 (update_moves 적용)
    # 조정된 진화 단계와 레벨을 기준으로 기술을 배웁니다.
    if AutomaticLevelScaling.settings[:update_moves]
      pkmn.reset_moves # <-- 올바른 메서드 적용
    end
  end

  #--------------------------------------------------------------------------
  # Bonus scaling
  ttype = trainer.trainer_type.to_s
  bonus = 0
  if ["LEADER_", "ELITEFOUR_", "NEON_", "FARHAN", "ELODIE", "ESMERALDA", "VEGA"].any? { |prefix| ttype.start_with?(prefix) }
    bonus = 1
  elsif ttype.start_with?("CHAMPION_") || ttype == "LUCIEN"
    bonus = 3
  end
  if bonus > 0
    trainer.party.each do |pkmn|
      next unless pkmn&.respond_to?(:level)
      pkmn.level += bonus
      pkmn.calc_stats
    end
  end
  }
)