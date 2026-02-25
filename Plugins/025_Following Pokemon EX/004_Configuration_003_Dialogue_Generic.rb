#-------------------------------------------------------------------------------
# These are used to define what the Follower will say when spoken to in general
#-------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# All dialogues with the Music Note animation
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :music_generic, proc { |pkmn, random_val|
  if random_val == 0
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_MUSIC)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    messages = [
      _INTL("\\j[{1},은,는] \\j[{2},과,와] 놀고 싶어 하는 것 같다."),
      _INTL("\\j[{1},은,는] 노래를 부르고 콧노래를 흥얼거린다."),
      _INTL("\\j[{1},은,는] 즐거운 표정으로 \\j[{2},을,를] 올려다본다."),
      _INTL("\\j[{1},은,는] 마음 내키는 대로 흔들리고 춤을 췄다."),
      _INTL("\\j[{1},은,는] 걱정 없이 폴짝폴짝 뛰어다닌다!"),
      _INTL("\\j[{1},은,는] 민첩함을 뽐내고 있다!"),
      _INTL("\\j[{1},은,는] 즐겁게 움직이고 있다!"),
      _INTL("와! \\j[{1},은,는] 갑자기 기뻐서 춤을 추기 시작했다!"),
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 꾸준히 따라가고 있다!"),
      _INTL("\\j[{1},은,는] 기쁘게 깡충깡충 뛰고 있다."),
      _INTL("\\j[{1},은,는] 장난스럽게 땅을 깨물고 있다."),
      _INTL("\\j[{1},은,는] {2}의 발을 장난스럽게 물고 있다!"),
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 아주 바짝 따라가고 있다!"),
      _INTL("\\j[{1},은,는] 돌아서서 \\j[{2},을,를] 바라본다."),
      _INTL("\\j[{1},은,는] 강력한 힘을 보여 주기 위해 열심히 노력하고 있다!"),
      _INTL("\\j[{1},은,는] 뛰어다니고 싶어 하는 것 같다!"),
      _INTL("\\j[{1},은,는] 경치를 즐기며 돌아다니고 있다."),
      _INTL("\\j[{1},은,는] 이걸 조금 즐기고 있는 것 같다!"),
      _INTL("\\j[{1},은,는] 명랑하다!"),
      _INTL("\\j[{1},은,는] 뭔가 노래하는 것 같다?"),
      _INTL("\\j[{1},은,는] 즐겁게 춤추고 있다!"),
      _INTL("\\j[{1},은,는] 신나게 경쾌한 춤을 추고 있다!"),
      _INTL("\\j[{1},은,는] 너무 기뻐서 노래를 부르기 시작했다!"),
      _INTL("\\j[{1},은,는] 위를 쳐다보며 울부짖었다!"),
      _INTL("\\j[{1},은,는] 낙관적인 기분인 것 같다."),
      _INTL("\\j[{1},은,는] 춤추고 싶어 하는 것 같다!"),
      _INTL("\\j[{1},은,는] 갑자기 노래를 부르기 시작했다! 기분이 좋은 모양이다."),
      _INTL("\\j[{1},은,는] \\j[{2},과,와] 함께 춤추고 싶어 하는 것 같다!")
    ]
    value = rand(messages.length)
    case value
    # Special move route to go along with some of the dialogue
    when 3, 9
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 80])
      FollowingPkmn.move_route([
        PBMoveRoute::TURN_RIGHT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::JUMP, 0, 0,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::TURN_UP,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::JUMP, 0, 0,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::TURN_LEFT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::JUMP, 0, 0,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::TURN_DOWN,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::JUMP, 0, 0
      ])
    when 4, 5
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 40])
      FollowingPkmn.move_route([
        PBMoveRoute::JUMP, 0, 0,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::JUMP, 0, 0,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::JUMP, 0, 0
      ])
    when 6, 17
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 40])
      FollowingPkmn.move_route([
        PBMoveRoute::TURN_RIGHT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_DOWN,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_LEFT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_UP
      ])
    when 7, 28
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 60])
      FollowingPkmn.move_route([
        PBMoveRoute::TURN_RIGHT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_UP,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_LEFT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_DOWN,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_RIGHT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_UP,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_LEFT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_DOWN,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::JUMP, 0, 0,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::JUMP, 0, 0
      ])
    when 21, 22
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 50])
      FollowingPkmn.move_route([
        PBMoveRoute::TURN_RIGHT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_UP,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_LEFT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_DOWN,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::JUMP, 0, 0,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::JUMP, 0, 0
      ])
    end
    pbMessage(_INTL(messages[value], pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# All dialogues with the Angry animation
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :angry_generic, proc { |pkmn, random_val|
  if random_val == 1
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ANGRY)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    messages = [
      _INTL("\\j[{1},은,는] 포효했다!"),
      _INTL("\\j[{1},은,는] 화난 표정을 짓고 있다!"),
      _INTL("\\j[{1},은,는] 왠지 화가 난 것 같다."),
      _INTL("\\j[{1},은,는] {2}의 발을 물었다."),
      _INTL("\\j[{1},은,는] 돌아서서 도전적인 표정을 지었다."),
      _INTL("\\j[{1},은,는] {2}의 적을 위협하려 한다!"),
      _INTL("\\j[{1},은,는] 싸움을 걸고 싶어 한다!"),
      _INTL("\\j[{1},은,는] 싸울 준비가 되어 있다!"),
      _INTL("\\j[{1},은,는] 지금이라면 누구와도 싸울 태세다!"),
      _INTL("\\j[{1},은,는] 거의 말하는 듯한 으르렁거림을 내고 있다...")
    ]
    value = rand(messages.length)
    # Special move route to go along with some of the dialogue
    case value
    when 6, 7, 8
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 25])
      FollowingPkmn.move_route([
        PBMoveRoute::JUMP, 0, 0,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::JUMP, 0, 0
      ])
    end
    pbMessage(_INTL(messages[value], pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# All dialogues with the Neutral Animation
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :ellipses_generic, proc { |pkmn, random_val|
  if random_val == 2
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_ELIPSES)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    messages = [
      _INTL("\\j[{1},은,는] 꾸준히 아래를 바라보고 있다."),
      _INTL("\\j[{1},은,는] 냄새를 맡으며 돌아다닌다."),
      _INTL("\\j[{1},은,는] 깊이 집중하고 있다."),
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 마주 보고 고개를 끄덕였다."),
      _INTL("\\j[{1},은,는] {2}의 눈을 똑바로 노려본다."),
      _INTL("\\j[{1},은,는] 주변을 살펴보고 있다."),
      _INTL("\\j[{1},은,는] 날카로운 시선으로 집중했다!"),
      _INTL("\\j[{1},은,는] 멍하니 주위를 둘러본다."),
      _INTL("\\j[{1},은,는] 크게 하품했다!"),
      _INTL("\\j[{1},은,는] 편안하게 쉬고 있다."),
      _INTL("\\j[{1},은,는] {2}의 관심을 끌려 하고 있다."),
      _INTL("\\j[{1},은,는] 아무것도 없는 곳을 뚫어지게 바라본다."),
      _INTL("\\j[{1},은,는] 집중하고 있다."),
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 마주 보고 고개를 끄덕였다."), # 이전과 중복된 문장
      _INTL("\\j[{1},은,는] {2}의 발자국을 보고 있다."),
      _INTL("\\j[{1},은,는] 놀고 싶어 하는 듯 \\j[{2},을,를] 기대하며 바라보고 있다."),
      _INTL("\\j[{1},은,는] 뭔가 깊이 생각에 잠긴 것 같다."),
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 신경 쓰지 않고 있다… 딴 생각에 잠긴 듯하다."),
      _INTL("\\j[{1},은,는] 진지한 표정이다."),
      _INTL("\\j[{1},은,는] 무관심한 것 같다."),
      _INTL("\\j[{1},은,는] 딴 데 정신이 팔린 듯하다."),
      _INTL("\\j[{1},은,는] {2}가 아닌 주변을 둘러보고 있다."),
      _INTL("\\j[{1},은,는] 조금 지루해 보인다."),
      _INTL("\\j[{1},은,는] 강한 눈빛을 띠고 있다."),
      _INTL("\\j[{1},은,는] 먼 곳을 응시하고 있다."),
      _INTL("\\j[{1},은,는] {2}의 얼굴을 자세히 살펴보는 것 같다."),
      _INTL("\\j[{1},은,는] 눈빛으로 소통하려 하는 듯하다."),
      _INTL("...\\j[{1},은,는] 재채기를 한 것 같다!"),
      _INTL("...\\j[{1},은,는] {2}의 신발이 좀 더럽다는 걸 알아챘다."),
      _INTL("\\j[{1},은,는] 이상한 걸 주워 먹은 듯 표정을 찡그리고 있다…"),
      _INTL("\\j[{1},은,는] 좋은 냄새를 맡는 것 같다."),
      _INTL("\\j[{1},은,는] {2}의 가방에 약간의 먼지가 묻어 있다는 걸 눈치챘다…"),
      _INTL("...... ...... ...... ...... ...... ...... ...... ...... ...... ...... ...... \\j[{1},은,는] 조용히 고개를 끄덕였다!")
    ]
    value = rand(messages.length)
    # Special move route to go along with some of the dialogue
    case value
    when 1, 5, 7, 20, 21
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 35])
      FollowingPkmn.move_route([
        PBMoveRoute::TURN_RIGHT,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::TURN_UP,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::TURN_LEFT,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::TURN_DOWN
      ])
    end
    pbMessage(_INTL(messages[value], pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# All dialogues with the Happy animation
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :happy_generic, proc { |pkmn, random_val|
  if random_val == 3
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_HAPPY)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    messages = [
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 콕콕 찌르기 시작했다."),
      _INTL("\\j[{1},은,는] 매우 기뻐 보인다."),
      _INTL("\\j[{1},은,는] 기쁘게 {2}에게 기대어 안겼다."),
      _INTL("\\j[{1},은,는] 너무 기뻐서 가만히 있지 못한다."),
      _INTL("\\j[{1},은,는] 주도하고 싶어 하는 듯하다!"),
      _INTL("\\j[{1},은,는] 신나게 따라오고 있다."),
      _INTL("\\j[{1},은,는] \\j[{2},과,와] 함께 걷는 걸 즐거워하는 것 같다!"),
      _INTL("\\j[{1},은,는] 건강이 충만한 듯 빛나고 있다."),
      _INTL("\\j[{1},은,는] 매우 기뻐 보인다."), # 이전과 중복된 문장
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 위해 힘을 내고 있다!"),
      _INTL("\\j[{1},은,는] 주변 공기를 맡고 있다."),
      _INTL("\\j[{1},은,는] 기쁨에 뛰어오르고 있다!"),
      _INTL("\\j[{1},은,는] 여전히 기분 좋아 보인다!"),
      _INTL("\\j[{1},은,는] 몸을 쭉 뻗고 편안히 쉬고 있다."),
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 따라가기 위해 최선을 다하고 있다."),
      _INTL("\\j[{1},은,는] 즐겁게 {2}에게 기대어 안기고 있다!"),
      _INTL("\\j[{1},은,는] 에너지로 가득 차 있다!"),
      _INTL("\\j[{1},은,는] 행복한 기분에 드러누워 버렸다!"),
      _INTL("\\j[{1},은,는] 들려오는 소리에 몸을 움직이고 있다."), # 번역 리스트에 없음. 원문 유지.
      _INTL("\\j[{1},은,는] {2}에게 행복한 눈빛과 미소를 보낸다."),
      _INTL("\\j[{1},은,는] 흥분해 코로 거칠게 숨을 쉬기 시작했다!"),
      _INTL("\\j[{1},은,는] 열의에 몸이 떨리고 있다!"),
      _INTL("\\j[{1},은,는] 너무 기뻐서 뒹굴기 시작했다."),
      _INTL("\\j[{1},은,는] {2}의 관심을 받아 매우 신난 듯하다."),
      _INTL("\\j[{1},은,는] {2}가 자신을 알아봐줘서 매우 기뻐하는 것 같다!"),
      _INTL("\\j[{1},은,는] 신나서 온몸을 꿈틀거리기 시작했다!"),
      _INTL("\\j[{1},은,는] 거의 \\j[{2},을,를] 껴안으려 하는 것 같다!"),
      _INTL("\\j[{1},은,는] {2}의 발에 바짝 붙어 있다.")
    ]
    value = rand(messages.length)
    # Special move route to go along with some of the dialogue
    case value
    when 3
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 45])
      FollowingPkmn.move_route([
        PBMoveRoute::TURN_RIGHT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_UP,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_LEFT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_DOWN,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::JUMP, 0, 0,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::JUMP, 0, 0
      ])
    when 11, 16, 17, 24
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 40])
      FollowingPkmn.move_route([
        PBMoveRoute::JUMP, 0, 0,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::JUMP, 0, 0,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::JUMP, 0, 0
      ])
    end
    pbMessage(_INTL(messages[value], pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# All dialogues with the Heart animation
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :heart_generic, proc { |pkmn, random_val|
  if random_val == 4
    FollowingPkmn.animation(FollowingPkmn::ANIMATION_EMOTE_HEART)
    pbMoveRoute($game_player, [PBMoveRoute::WAIT, 20])
    messages = [
      _INTL("\\j[{1},은,는] 갑자기 {2}에게 더 가까이 걸어가기 시작했다."),
      _INTL("와우! \\j[{1},은,는] 갑자기 \\j[{2},을,를] 안아버렸다."),
      _INTL("\\j[{1},은,는] {2}에게 몸을 비비고 있다."),
      _INTL("\\j[{1},은,는] {2}에게 가까이 다가왔다."),
      _INTL("\\j[{1},은,는] 얼굴이 붉어졌다."),
      _INTL("\\j[{1},은,는] \\j[{2},과,와] 함께 있는 걸 정말 좋아한다!"),
      _INTL("\\j[{1},은,는] 갑자기 장난기 가득해졌다!"),
      _INTL("\\j[{1},은,는] {2}의 다리에 몸을 부비고 있다!"),
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 사랑스럽게 바라보고 있다!"),
      _INTL("\\j[{1},은,는] {2}에게 애정을 받고 싶어하는 것 같다."),
      _INTL("\\j[{1},은,는] {2}의 관심을 받고 싶어하는 것 같다."),
      _INTL("\\j[{1},은,는] \\j[{2},과,와] 함께 여행하는 걸 즐거워하는 것 같다."),
      _INTL("\\j[{1},은,는] {2}에게 애정을 느끼는 것 같다."),
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 사랑의 눈길로 바라보고 있다."),
      _INTL("\\j[{1},은,는] {2}에게 간식을 받고 싶어 하는 것 같다."),
      _INTL("\\j[{1},은,는] {2}가 쓰다듬어 주길 원하는 것 같다!"),
      _INTL("\\j[{1},은,는] 애정 가득하게 {2}에게 몸을 비비고 있다."),
      _INTL("\\j[{1},은,는] {2}의 손에 살며시 머리를 부딪쳤다."),
      _INTL("\\j[{1},은,는] 기대 가득한 눈빛으로 몸을 뒤집으며 \\j[{2},을,를] 바라본다."),
      _INTL("\\j[{1},은,는] 믿음 어린 눈빛으로 \\j[{2},을,를] 바라보고 있다."),
      _INTL("\\j[{1},은,는] {2}에게 애정을 갈구하는 것 같다!"),
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 흉내 냈다!")
    ]
    value = rand(messages.length)
    case value
    when 1, 6
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 10])
      FollowingPkmn.move_route([
        PBMoveRoute::JUMP, 0, 0
      ])
    end
    pbMessage(_INTL(messages[value], pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
# All dialogues with no animation
#-------------------------------------------------------------------------------
EventHandlers.add(:following_pkmn_talk, :generic,  proc { |pkmn, random_val|
  if random_val == 5
    messages = [
      _INTL("\\j[{1},은,는] 빙글빙글 돌았다!"),
      _INTL("\\j[{1},은,는] 전투 함성을 내질렀다!"),
      _INTL("\\j[{1},은,는] 주위를 경계하고 있다!"),
      _INTL("\\j[{1},은,는] 조용히 기다리고 있다."),
      _INTL("\\j[{1},은,는] 조용히 주위를 살피고 있다."),
      _INTL("\\j[{1},은,는] 어슬렁거리며 돌아다니고 있다."),
      _INTL("\\j[{1},은,는] 크게 하품했다!"),
      _INTL("\\j[{1},은,는] {2}의 발 주변 땅을 조용히 파고 있다."),
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 보고 미소 짓고 있다."),
      _INTL("\\j[{1},은,는] 멀리 응시하고 있다."),
      _INTL("\\j[{1},은,는] \\j[{2},을,를] 잘 따라가고 있다."),
      _INTL("\\j[{1},은,는] 자기 자신에게 만족한 표정이다."),
      _INTL("\\j[{1},은,는] 아직도 힘이 넘치고 있다!"),
      _INTL("\\j[{1},은,는] \\j[{2},과,와] 발맞춰 걷고 있다."),
      _INTL("\\j[{1},은,는] 원을 그리며 빙글돌기 시작했다."),
      _INTL("\\j[{1},은,는] 기대에 찬 얼굴로 \\j[{2},을,를] 본다."),
      _INTL("\\j[{1},은,는] 넘어져 조금 당황해 보인다."),
      _INTL("\\j[{1},은,는] {2}가 무얼 할지 기다리고 있다."),
      _INTL("\\j[{1},은,는] 차분하게 \\j[{2},을,를] 지켜보고 있다."),
      _INTL("\\j[{1},은,는] {2}의 신호를 기다리며 바라보고 있다."),
      _INTL("\\j[{1},은,는] 제자리에 서서 {2}의 움직임을 기다리고 있다."),
      _INTL("\\j[{1},은,는] {2}의 발가락에 충실히 앉았다."),
      _INTL("\\j[{1},은,는] 깜짝 놀라 뛰어올랐다!"),
      _INTL("\\j[{1},은,는] 살짝 뛰었다!")
    ]
    value = rand(messages.length)
    # Special move route to go along with some of the dialogue
    case value
    when 0
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 15])
      FollowingPkmn.move_route([
        PBMoveRoute::TURN_RIGHT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_UP,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_LEFT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_DOWN
      ])
    when 2, 4
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 35])
      FollowingPkmn.move_route([
        PBMoveRoute::TURN_RIGHT,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::TURN_UP,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::TURN_LEFT,
        PBMoveRoute::WAIT, 10,
        PBMoveRoute::TURN_DOWN
      ])
    when 14
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 50])
      FollowingPkmn.move_route([
        PBMoveRoute::TURN_RIGHT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_UP,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_LEFT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_DOWN,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_RIGHT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_UP,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_LEFT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_DOWN,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_RIGHT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_UP,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_LEFT,
        PBMoveRoute::WAIT, 4,
        PBMoveRoute::TURN_DOWN
      ])
    when 22, 23
      pbMoveRoute($game_player, [PBMoveRoute::WAIT, 10])
      FollowingPkmn.move_route([
        PBMoveRoute::JUMP, 0, 0
      ])
    end
    pbMessage(_INTL(messages[value], pkmn.name, $player.name))
    next true
  end
})
#-------------------------------------------------------------------------------
