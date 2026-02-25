#-------------------------------------------------------------------------------
# These are used to define what the Follower will say when spoken to under
# specific conditions like Status or Weather or Map names
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Amie Compatibility
#-------------------------------------------------------------------------------
if defined?(PkmnAR)
  EventHandlers.add(:following_pkmn_talk, :amie, proc { |_pkmn, _random_val|
    cmd = pbMessage(_INTL("무엇을 할까?"), [
      _INTL("놀기"),
      _INTL("얘기하기"),
      _INTL("Cancel")
    ])
    PkmnAR.show if cmd == 0
    next true if [0, 2].include?(cmd)
  })
end
#-------------------------------------------------------------------------------
# Special Dialogue when statused
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :status, proc { |pkmn, _random_val|
  case pkmn.status
  when :POISON
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_POISON)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    pbMessage(_INTL("\\j[{1},은,는] 독에 걸려 몸을 떨고 있다.", pkmn.name))
  when :BURN
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ANGRY)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    pbMessage(_INTL("\\j[{1},은,는] 화상으로 고통스러워 하고 있다.", pkmn.name))
  when :FROZEN
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ELIPSES)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    pbMessage(_INTL("\\j[{1},은,는] 얼어붙어 너무 추워하고 있다!", pkmn.name))
  when :SLEEP
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ELIPSES)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    pbMessage(_INTL("\\j[{1},은,는] 굉장히 지쳐보인다.", pkmn.name))
  when :PARALYSIS
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ELIPSES)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    pbMessage(_INTL("\\j[{1},은,는] 가만히 서서 몸을 움찔거리고 있다.", pkmn.name))
  end
  next true if pkmn.status != :NONE
})
#-------------------------------------------------------------------------------
# Specific message if the map has the Pokemon Lab metadata flag
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :pokemon_lab, proc { |pkmn, _random_val|
  if $game_map.metadata&.has_flag?("PokemonLab")
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ELIPSES)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    messages = [
      _INTL("\\j[{1},은,는] 무언가 스위치를 만지고 있다."),
      _INTL("\\j[{1},이,가] 입에 전선을 물고 있다!"),
      _INTL("\\j[{1},은,는] 기계를 만지고 싶어하는 것 같다.")
    ]
    pbMessage(_INTL(messages.sample, pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# Specific message if the map name has the players name in it like the
# Player's House
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :player_house, proc { |pkmn, _random_val|
  if $game_map.name.include?($player.name)
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_HAPPY)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    messages = [
      _INTL("\\j[{1},은,는] 방 안을 킁킁거리며 돌아다니고 있다."),
      _INTL("\\j[{1},은,는] {2}의 엄마가 근처에 있다는 걸 눈치챘다."),
      _INTL("\\j[{1},은,는] 집에서 쉬고 싶은 듯하다.")
    ]
    pbMessage(_INTL(messages.sample, pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# Specific message if the map has Pokecenter metadata flag
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :pokemon_center, proc { |pkmn, _random_val|
  if $game_map.metadata&.has_flag?("PokeCenter")
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_HAPPY)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    messages = [
      _INTL("\\j[{1},은,는] 간호순이를 보고 기뻐하는 것 같다."),
      _INTL("\\j[{1},은,는] 포켓몬센터에만 있어도 조금 나아진 것 같다."),
      _INTL("\\j[{1},은,는] 치료 기계에 흥미를 느끼는 것 같다."),
      _INTL("\\j[{1},은,는] 낮잠을 자고 싶어하는 것 같다."),
      _INTL("\\j[{1},이,가] 간호순이에게 인사하듯이 짹짹거렸다."),
      _INTL("\\j[{1},은,는] 장난기 어린 눈으로 \\j[{2},을,를] 바라보고 있다."),
      _INTL("\\j[{1},은,는] 아주 편안해 보인다."),
      _INTL("\\j[{1},은,는] 편히 자리 잡고 있다."),
      _INTL("\\j[{1},의,의] 얼굴엔 만족스러운 표정이 떠올라 있다.")
    ]
    pbMessage(_INTL(messages.sample, pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# Specific message if the map has the Gym metadata flag
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :gym, proc { |pkmn, _random_val|
  if $game_map.metadata&.has_flag?("GymMap")
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ANGRY)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    messages = [
      _INTL("\\j[{1},은,는] 배틀에 대한 의욕이 넘쳐 보인다!"),
      _INTL("\\j[{1},은,는] 결의에 찬 눈빛으로 \\j[{2},을,를] 바라보고 있다."),
      _INTL("\\j[{1},은,는] 다른 트레이너들을 위협하려 하고 있다."),
      _INTL("\\j[{1},은,는] \\j[{2},이,가] 좋은 전략을 세울 거라 믿고 있다."),
      _INTL("\\j[{1},은,는] 체육관 관장을 주의 깊게 지켜보고 있다."),
      _INTL("\\j[{1},은,는] 누군가와 싸울 준비가 된 것 같다."),
      _INTL("\\j[{1},은,는] 큰 승부를 준비하고 있는 것처럼 보인다!"),
      _INTL("\\j[{1},은,는] 자신의 힘을 자랑하고 싶어하는 것 같다!"),
      _INTL("\\j[{1},이,가] 몸을 풀고 있는... 것 같다?"),
      _INTL("\\j[{1},은,는] 조용히 으르렁거리며 고민하는 중이다...")
    ]
    pbMessage(_INTL(messages.sample, pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# Specific message when the weather is Storm. Pokemon of different types
# have different reactions to the weather.
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :storm_weather, proc { |pkmn, _random_val|
  if :Storm == $game_screen.weather_type
    if pkmn.hasType?(:ELECTRIC)
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_HAPPY)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 하늘을 올려다보고 있다."),
        _INTL("폭풍 때문에 \\j[{1},이,가] 흥분한 것 같다."),
        _INTL("\\j[{1},이,가] 하늘을 올려다보며 크게 소리쳤다!"),
        _INTL("폭풍이 오히려 \\j[{1},을,를] 활기차게 만드는 것 같다!"),
        _INTL("\\j[{1},은,는] 즐겁게 전기를 튀기며 빙글빙글 돌고 있다!"),
        _INTL("번개도 \\j[{1},을,를] 전혀 신경 쓰이게 하지 않는 것 같다.")
      ]
    else
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ELIPSES)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 하늘을 올려다보고 있다."),
        _INTL("폭풍 때문에 \\j[{1},이,가] 조금 긴장한 것 같다."),
        _INTL("번개 소리에 \\j[{1},이,가] 깜짝 놀랐다!"),
        _INTL("비는 \\j[{1},을,를] 크게 신경 쓰이게 하지 않는 것 같다."),
        _INTL("날씨 때문에 \\j[{1},이,가] 예민해진 것 같다."),
        _INTL("번개 소리에 놀란 \\j[{1},은,는] \\j[{2},에게,에게] 바짝 달라붙었다!")
      ]
    end
    pbMessage(_INTL(messages.sample, pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# Specific message when the weather is Snowy. Pokemon of different types
# have different reactions to the weather.
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :snow_weather, proc { |pkmn, _random_val|
  if :Snow == $game_screen.weather_type
    if pkmn.hasType?(:ICE)
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_HAPPY)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 눈이 내리는 걸 바라보고 있다."),
        _INTL("눈이 내려서 \\j[{1},이,가] 신이 났다!"),
        _INTL("\\j[{1},은,는] 미소를 지으며 하늘을 올려다보고 있다."),
        _INTL("눈 때문에 \\j[{1},이,가] 기분이 좋아진 것 같다."),
        _INTL("추운 날씨에 \\j[{1},이,가] 활기를 띠고 있다!")
      ]
    else
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ELIPSES)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 눈이 내리는 걸 바라보고 있다."),
        _INTL("\\j[{1},은,는] 떨어지는 눈송이를 톡톡 깨물고 있다."),
        _INTL("\\j[{1},은,는] 눈송이를 입으로 받아먹고 싶어하는 것 같다."),
        _INTL("\\j[{1},은,는] 눈에 넋을 잃고 있다."),
        _INTL("\\j[{1},의,의] 이가 덜덜 떨리고 있다!"),
        _INTL("추위 때문에 \\j[{1},이,가] 몸을 조금 움츠렸다...")
      ]
    end
    pbMessage(_INTL(messages.sample, pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# Specific message when the weather is Blizzard. Pokemon of different types
# have different reactions to the weather.
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :blizzard_weather, proc { |pkmn, _random_val|
  if :Blizzard == $game_screen.weather_type
    if pkmn.hasType?(:ICE)
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_HAPPY)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 우박이 떨어지는 걸 보고 있다."),
        _INTL("우박도 \\j[{1},을,를] 전혀 신경 쓰이게 하지 않는 것 같다."),
        _INTL("\\j[{1},은,는] 미소를 지으며 하늘을 올려다보고 있다."),
        _INTL("우박 덕분에 \\j[{1},이,가] 기분이 좋아진 것 같다."),
        _INTL("\\j[{1},은,는] 우박 조각을 갉아먹고 있다.")
      ]
    else
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ANGRY)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},이,가] 우박에 맞고 있다!"),
        _INTL("\\j[{1},은,는] 우박을 피하고 싶어하는 것 같다."),
        _INTL("우박이 \\j[{1},을,를] 아프게 때리고 있다."),
        _INTL("\\j[{1},은,는] 기분이 안 좋아 보인다."),
        _INTL("\\j[{1},은,는] 나뭇잎처럼 벌벌 떨고 있다!")
      ]
    end
    pbMessage(_INTL(messages.sample, pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# Specific message when the weather is Sandstorm. Pokemon of different types
# have different reactions to the weather.
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :sandstorm_weather, proc { |pkmn, _random_val|
  if :Sandstorm == $game_screen.weather_type
    if [:ROCK, :GROUND].any? { |type| pkmn.hasType?(type) }
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_HAPPY)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 온몸이 모래투성이가 되었다."),
        _INTL("날씨는 \\j[{1},을,를] 전혀 신경 쓰지 않는 듯하다!"),
        _INTL("모래바람도 \\j[{1},을,를] 멈출 수 없다!"),
        _INTL("\\j[{1},은,는] 날씨를 즐기고 있는 것 같다.")
      ]
    elsif pkmn.hasType?(:STEEL)
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ELIPSES)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 온몸에 모래가 묻었지만, 신경 쓰지 않는 듯하다."),
        _INTL("\\j[{1},은,는] 모래폭풍에도 별로 신경 쓰지 않는 것 같다."),
        _INTL("모래바람은 \\j[{1},을,를] 전혀 방해하지 못한다."),
        _INTL("\\j[{1},은,는] 날씨를 신경 쓰지 않는 듯하다.")
      ]
    else
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ANGRY)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 온몸에 모래가 묻었다..."),
        _INTL("\\j[{1},은,는] 입에 가득한 모래를 퉤 뱉었다!"),
        _INTL("\\j[{1},은,는] 모래폭풍 속에서 눈을 가늘게 뜨고 있다."),
        _INTL("모래가 \\j[{1},을,를] 거슬리게 하는 것 같다.")
      ]
    end
    pbMessage(_INTL(messages.sample, pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# Specific message if the map has the Forest metadata flag
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :forest_map, proc { |pkmn, _random_val|
  if $game_map.metadata&.has_flag?("Forest")
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_MUSIC)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    if [:BUG, :GRASS].any? { |type| pkmn.hasType?(type) }
      messages = [
        _INTL("\\j[{1},은,는] 나무에 깊은 관심을 보이고 있다."),
        _INTL("\\j[{1},은,는] 벌레 포켓몬들의 윙윙거림을 즐기는 것 같다."),
        _INTL("\\j[{1},은,는] 숲 속을 뛰어다니며 안절부절 못하고 있다.")
      ]
    else
      messages = [
        _INTL("\\j[{1},은,는] 나무에 깊은 관심을 보이고 있다."),
        _INTL("\\j[{1},은,는] 벌레 포켓몬들의 윙윙거림을 즐기는 것 같다."),
        _INTL("\\j[{1},은,는] 숲 속을 뛰어다니며 안절부절 못하고 있다."),
        _INTL("\\j[{1},은,는] 이리저리 다니며 다양한 소리를 듣고 있다."),
        _INTL("\\j[{1},은,는] 풀을 우물우물 씹고 있다."),
        _INTL("\\j[{1},은,는] 이리저리 다니며 숲의 경치를 즐기고 있다."),
        _INTL("\\j[{1},은,는] 풀을 쪼아가며 장난치고 있다."),
        _INTL("\\j[{1},은,는] 나뭇잎 사이로 비치는 햇빛을 바라보고 있다."),
        _INTL("\\j[{1},은,는] 나뭇잎을 가지고 놀고 있다!"),
        _INTL("\\j[{1},은,는] 바스락거리는 나뭇잎 소리를 듣고 있는 것 같다."),
        _INTL("\\j[{1},은,는] 나무인 척 하듯이 가만히 서 있다..."),
        _INTL("\\j[{1},은,는] 나뭇가지에 걸려서 넘어질 뻔했다!"),
        _INTL("\\j[{1},은,는] 나뭇가지에 맞고 깜짝 놀랐다!")
      ]
    end
    pbMessage(_INTL(messages.sample, pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# Specific message when the weather is Rainy. Pokemon of different types
# have different reactions to the weather.
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :rainy_weather, proc { |pkmn, _random_val|
  if [:Rain, :HeavyRain].include?($game_screen.weather_type)
    if pkmn.hasType?(:FIRE) || pkmn.hasType?(:GROUND) || pkmn.hasType?(:ROCK)
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ANGRY)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 날씨 때문에 매우 불쾌한 것 같다."),
        _INTL("\\j[{1},은,는] 몸을 부르르 떨고 있다..."),
        _INTL("\\j[{1},은,는] 온몸이 젖은 걸 싫어하는 듯하다..."),
        _INTL("\\j[{1},은,는] 몸을 털며 마르려고 애쓰고 있다..."),
        _INTL("\\j[{1},은,는] 위로를 받기 위해 {2}에게 다가갔다."),
        _INTL("\\j[{1},은,는] 하늘을 올려다보며 찡그린다."),
        _INTL("\\j[{1},은,는] 몸을 움직이기 어려워 보인다.")
      ]
    elsif pkmn.hasType?(:WATER) || pkmn.hasType?(:GRASS)
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_HAPPY)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 날씨를 즐기고 있는 듯하다."),
        _INTL("\\j[{1},은,는] 비가 오는 걸 기뻐하는 것 같다!"),
        _INTL("\\j[{1},은,는] 비가 오는 것에 매우 놀란 것 같다!"),
        _INTL("\\j[{1},은,는] \\j[{2},을,를] 향해 환하게 웃었다!"),
        _INTL("\\j[{1},은,는] 비구름을 올려다보고 있다."),
        _INTL("빗방울이 \\j[{1},에게] 계속 떨어지고 있다."),
        _INTL("\\j[{1},은,는] 입을 벌린 채 하늘을 올려다보고 있다.")
      ]
    else
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ELIPSES)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 하늘을 보며 비를 보고 있다."), # 번역 리스트에 없음. 원문 유지.
        _INTL("\\j[{1},은,는] 비가 오는 걸 보고 약간 놀란 것 같다."),
        _INTL("\\j[{1},은,는] 계속 몸을 털어 말리려 하고 있다."),
        _INTL("\\j[{1},은,는] 비를 신경쓰고 있는 것 같지 않다."), # 번역 리스트에 없음. 원문 유지.
        _INTL("\\j[{1},은,는] 물웅덩이에서 놀고 있다!"),
        _INTL("\\j[{1},은,는] 물에서 미끄러져 넘어질 뻔했다!")
      ]
    end
    pbMessage(_INTL(messages.sample, pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# Specific message if the map has Beach metadata flag
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :beach_map, proc { |pkmn, _random_val|
  if $game_map.metadata&.has_flag?("Beach")
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_HAPPY)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    messages = [
      _INTL("\\j[{1},은,는] 경치를 즐기고 있는 것 같다."),
      _INTL("\\j[{1},은,는] 파도가 모래를 밀어내는 소리를 즐기는 것 같다."),
      _INTL("\\j[{1},은,는] 수영하고 싶어하는 것 같다!"),
      _INTL("\\j[{1},은,는] 바다에서 시선을 떼지 못하고 있다."),
      _INTL("\\j[{1},은,는] 물을 그리운 듯이 바라보고 있다."),
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 물가로 밀어내려 하고 있다."),
      _INTL("\\j[{1},은,는] 바다를 보며 신이 난 것 같다!"),
      _INTL("\\j[{1},은,는] 파도를 기쁘게 바라보고 있다!"),
      _INTL("\\j[{1},은,는] 모래밭에서 놀고 있다!"),
      _INTL("\\j[{1},은,는] {2}의 모래 발자국을 바라보고 있다."),
      _INTL("\\j[{1},은,는] 모래 위를 굴러다니고 있다.")
    ]
    pbMessage(_INTL(messages.sample, pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# Specific message when the weather is Sunny. Pokemon of different types
# have different reactions to the weather.
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :sunny_weather, proc { |pkmn, _random_val|
  if :Sun == $game_screen.weather_type
    if pkmn.hasType?(:GRASS)
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_HAPPY)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 햇빛 아래 나와서 기뻐하는 것 같다."),
        _INTL("\\j[{1},은,는] 햇볕을 흠뻑 받고 있다."),
        _INTL("밝은 햇빛이 \\j[{1},을,를] 전혀 괴롭히지 않는 듯하다."),
        _INTL("\\j[{1},은,는] 고리 모양의 포자 구름을 뿜어냈다!"),
        _INTL("\\j[{1},은,는] 몸을 쭉 뻗고 햇살 속에서 쉬고 있다."),
        _INTL("\\j[{1},은,는] 꽃향기를 풍기고 있다.")
      ]
    elsif pkmn.hasType?(:FIRE)
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_HAPPY)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 좋은 날씨에 기뻐하는 것 같다!"),
        _INTL("밝은 햇빛이 \\j[{1},을,를] 전혀 괴롭히지 않는 듯하다."),
        _INTL("\\j[{1},은,는] 햇살에 신이 난 표정이다!"),
        _INTL("\\j[{1},은,는] 불덩이를 내뿜었다."),
        _INTL("\\j[{1},은,는] 불을 내뿜고 있다!"),
        _INTL("\\j[{1},은,는] 뜨겁고 명랑하다!")
      ]
    elsif pkmn.hasType?(:DARK)
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ANGRY)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 하늘을 노려보고 있다."),
        _INTL("\\j[{1},은,는] 햇빛에 불쾌한 것 같다."),
        _INTL("밝은 햇빛이 \\j[{1},을,를] 괴롭히는 모양이다."),
        _INTL("\\j[{1},은,는] 왠지 언짢아 보인다."),
        _INTL("\\j[{1},은,는] {2}의 그늘에 머무르려 한다."),
        _INTL("\\j[{1},은,는] 햇빛을 피해 쉴 곳을 찾고 있다.")
      ]
    else
      FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ELIPSES)
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
      messages = [
        _INTL("\\j[{1},은,는] 밝은 햇살에 눈을 가늘게 뜨고 있다."),
        _INTL("\\j[{1},은,는] 땀이 나기 시작했다."),
        _INTL("\\j[{1},은,는] 이 날씨가 조금 불편한 듯하다."),
        _INTL("\\j[{1},은,는] 약간 과열된 모습이다."),
        _INTL("\\j[{1},은,는] 아주 더워 보인다..."),
        _INTL("\\j[{1},은,는] 반짝이는 빛을 피해 눈을 가렸다!")
      ]
    end
    pbMessage(_INTL(messages.sample, pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
