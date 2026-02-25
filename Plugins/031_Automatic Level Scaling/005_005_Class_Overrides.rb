#===============================================================================
# Automatic Level Scaling Class Overrides
# By Benitex
#===============================================================================

class Trainer
  def key
    return [@trainer_type, self.name, @version]
  end

  def party_avarage_level
    avarage_level = 0
    self.party.each { |pokemon| avarage_level += pokemon.level }
    avarage_level /= self.party.length

    return avarage_level
  end
end

class Pokemon
  # Constants to make the get_evolutions method array more readable
  # [Species, Method, Parameter]
  EVOLUTION_SPECIES = 0
  EVOLUTION_METHOD = 1
  EVOLUTION_PARAMETER = 2

  def scale(new_level = nil)
    new_level = AutomaticLevelScaling.getScaledLevel if new_level.nil?
    new_level = new_level.clamp(1, GameData::GrowthRate.max_level)
    return if !AutomaticLevelScaling.shouldScaleLevel?(self.level, new_level)

    self.level = new_level
    self.scaleEvolutionStage if AutomaticLevelScaling.settings[:automatic_evolutions]
    self.calc_stats
    self.reset_moves if AutomaticLevelScaling.settings[:update_moves]
  end

  def scaleEvolutionStage
    original_species = self.species
    original_form = self.form   # regional form
    
    # 🌟 Basculin (Form 2) -> Basculegion (Form 0/1) 예외 처리 시작 🌟
    saved_basculegion_form = -1
    
    # 🚨 중요: original_form이 훼손되었더라도, BASCULIN이라면 Form 2였음을 가정합니다.
    # getPossibleEvolutions가 Form 2 데이터를 가져왔기 때문에, 여기서는 final form만 처리합니다.
    is_original_basculin_white_striped = (original_species == :BASCULIN)
    
    if is_original_basculin_white_striped
      # 진화 후 유효한 폼 ID를 미리 계산 (폼 충돌 해결)
      if self.male?
        saved_basculegion_form = 0 # Male Basculegion (Form 0)
      else # Female
        saved_basculegion_form = 1 # Female Basculegion (Form 1)
      end
    end
    # 🌟 예외 처리 종료 🌟
    
    evolution_stage = 0

    if AutomaticLevelScaling.settings[:include_previous_stages]
      self.species = GameData::Species.get_species_form(self.species, self.form).get_baby_species # Reverts to the first evolution stage
    else
      # Checks if the pokemon has evolved
      if self.species != GameData::Species.get_species_form(self.species, self.form).get_baby_species
        evolution_stage = 1
      end
    end

    (2 - evolution_stage).times do |_|
      possible_evolutions = self.getPossibleEvolutions
      return if possible_evolutions.length == 0
      return if !AutomaticLevelScaling.settings[:include_next_stages] && self.species == original_species

      evolution_level = getEvolutionLevel(evolution_stage > 0)

      # Evolution
      if self.level >= evolution_level
        if possible_evolutions.length == 1
          self.species = possible_evolutions[0][EVOLUTION_SPECIES]

        elsif possible_evolutions.length > 1
          self.species = possible_evolutions.sample[EVOLUTION_SPECIES]

          # If the original species is a specific evolution, uses it instead of the random one
          for evolution in possible_evolutions do
            if evolution[EVOLUTION_SPECIES] == original_species
              self.species = evolution[EVOLUTION_SPECIES]
            end
          end
        end
      end

      # 🔄 폼 재설정 로직 수정 (Basculegion만 예외 처리) 🔄
      if self.species == :BASCULEGION && saved_basculegion_form != -1
        # BASCULEGION으로 진화했다면 유효한 폼(0 또는 1)을 적용
        setForm(saved_basculegion_form)
      else
        # 다른 모든 포켓몬은 원래 폼으로 재설정 (BASCULIN의 경우 훼손된 0/1로 돌아감)
        setForm(original_form)
      end
      # 🔄 수정 종료 🔄
      
      evolution_stage += 1
    end
  end
  
  # @param has_evolved [Boolean] is necessary to determine the default evolution level for pokemon with non natural evolution methods
  def getEvolutionLevel(has_evolved)
    # Default evolution levels according to the pokemon evolution stage
    evolution_level = AutomaticLevelScaling.settings[has_evolved ? :second_evolution_level : :first_evolution_level]
    possible_evolutions = self.getPossibleEvolutions

    if possible_evolutions.length == 1
      # Updates the evolution level if the evolution is by a natural method
      if possible_evolutions[0][EVOLUTION_PARAMETER].is_a?(Integer) && LevelScalingSettings::NATURAL_EVOLUTION_METHODS.include?(possible_evolutions[0][EVOLUTION_METHOD])
        evolution_level = possible_evolutions[0][EVOLUTION_PARAMETER]
      end

    elsif possible_evolutions.length > 1
      # Updates the evolution level if one of the evolutions is a natural evolution method. If there's more than one, uses the lowest one
      level = GameData::GrowthRate.max_level + 1
      for evolution in possible_evolutions do
        if evolution[EVOLUTION_PARAMETER].is_a?(Integer) && LevelScalingSettings::NATURAL_EVOLUTION_METHODS.include?(evolution[EVOLUTION_METHOD])
          level = evolution[EVOLUTION_PARAMETER] if evolution[EVOLUTION_PARAMETER] < level
        end
      end
      evolution_level = level if level < GameData::GrowthRate.max_level + 1
    end

    return evolution_level
  end

  def getPossibleEvolutions
    possible_evolutions = []
    
    # 🚨 BASCULIN (Form 2) 강제 진화 데이터 주입 로직 시작 🚨
    is_basculin = (self.species == :BASCULIN)
    
    if is_basculin
      # 폼 ID가 훼손되었더라도 BASCULIN, Form 2의 진화 목록을 강제로 가져옵니다.
      basculegion_evolutions = GameData::Species.get_species_form(:BASCULIN, 2)&.get_evolutions || []
      
      if basculegion_evolutions.any? { |evo| evo[EVOLUTION_SPECIES] == :BASCULEGION }
        # BASCULEGION으로의 진화 경로가 있다면 그 데이터를 사용합니다.
        possible_evolutions = basculegion_evolutions
      else
        # BASCULEGION으로의 경로가 없다면, 원래의 훼손된 폼 데이터(0/1)를 사용합니다.
        possible_evolutions = GameData::Species.get_species_form(self.species, self.form).get_evolutions
      end
    else
      # BASCULIN이 아니면 원래의 폼 데이터를 사용합니다.
      possible_evolutions = GameData::Species.get_species_form(self.species, self.form).get_evolutions
    end
    # 🚨 BASCULIN (Form 2) 강제 진화 데이터 주입 로직 끝 🚨

    possible_evolutions = possible_evolutions.delete_if { |evolution|\
      # Regional evolutions of pokemon not in their regional forms
      evolution[EVOLUTION_METHOD] == :None ||\
      # Remove non natural evolutions evolutions if include_non_natural_evolutions is false
      !AutomaticLevelScaling.settings[:include_non_natural_evolutions] && !LevelScalingSettings::NATURAL_EVOLUTION_METHODS.include?(evolution[EVOLUTION_METHOD])\
    }

    return possible_evolutions
  end
end

class PokemonGlobalMetadata
  def previous_trainer_parties
    @previous_trainer_parties = {} if !@previous_trainer_parties
    return @previous_trainer_parties
  end

  def map_levels
    @map_levels = {} if !@map_levels
    return @map_levels
  end
end
