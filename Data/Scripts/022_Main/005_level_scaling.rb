def adjust_levels(min, max)
  return if !$player
  $game_variables[84] = []

  $player.party.each do |pkmn|
    next if pkmn.nil?
    next if pkmn.level >= min && pkmn.level <= max

    id_str = pkmn.personalID.to_s
    level_str = pkmn.level.to_s
    $game_variables[84].push("#{id_str},#{level_str}")

    pkmn.level = (pkmn.level > max) ? max : min
    pkmn.calc_stats
  end
end

def return_levels_back
  return if !$player || !$game_variables[84].is_a?(Array)

  $game_variables[84].each do |data|
    id_str, level_str = data.split(',')
    next if !id_str || !level_str

    $player.party.each do |pkmn|
      next if pkmn.nil?
      if pkmn.personalID.to_s == id_str
        pkmn.level = level_str.to_i
        pkmn.calc_stats
        break
      end
    end
  end

  $game_variables[84] = []
end
