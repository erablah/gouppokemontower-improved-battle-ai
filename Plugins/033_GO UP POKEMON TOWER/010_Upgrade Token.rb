class Battle
  # 1. alias는 그대로 유지
  alias _gain_money_and_items pbGainMoney 

  # 2. 메서드 정의는 외부 호출을 위해 기본값을 유지
  def pbGainMoney(amount = 0, show_message = true)
    # 3. 원래 기능 실행 시, 인수를 전달하지 않습니다.
    #    (원래 메서드가 인수를 0개 예상한다는 에러 메시지에 따름)
    _gain_money_and_items() # <--- 수정된 부분: 괄호 안에 아무것도 넣지 않음

    # -----------------------------
    # 자동 보상 아이템 지급
    # -----------------------------
    return if !@internalBattle

    give_token = false
    multiplier = 1.0
    ttype = nil
	
	tokenCharmMultiplier = 1.0 # 기본값 1.0 (변동 없음)
    # $player.activeCharm?(:TOKENCHARM)가 true이면, 1.5배 보너스 적용
    if $player.activeCharm?(:TOKENCHARM)
      tokenCharmMultiplier = 1.5 
    end

    if trainerBattle?
      ttype = @opponent[0].trainer_type.to_s rescue nil
      if ttype&.start_with?("LEADER_","NEON_")
        give_token = true
        multiplier = 1.0
      elsif ttype&.start_with?("CHAMPION_","RED","LEAF","GOLD","LYRA","RUBY","MAY","LUCAS","DAWN","HILBERT","HILDA","NATE","ROSA","CALEM","SERENA","ELIO","SELENE","VICTOR","GLORIA","FLORIAN","JULIANA","FARHAN","ELODIE","VEGA","ESMERALDA")
        give_token = true
        multiplier = 1.5
      end
    end

    if give_token
      @opponent.each_with_index do |t, i|
        next unless t&.party&.any?
        max_level = pbMaxLevelInTeam(1, i)
        qty = ((max_level * multiplier) / 3.0).round
        next if qty <= 0

        added = $bag.add(:UPGRADETOKEN, qty)
        trainer_name = t.name rescue "Trainer"

        if added
          pbDisplayPaused(_INTL("{1}에게서 승리해 업그레이드 토큰을 {2}개 얻었다!", trainer_name, qty))
        else
          pbDisplayPaused(_INTL("Couldn't add {1} x{2} to your bag.", :UPGRADETOKEN, qty))
        end
      end
    end
  end
end

#===============================================================================
# PokemonGlobalMetadata 확장 (플러그인용)
# * 이 코드를 TokenMartSystem 모듈보다 먼저 로드되도록 배치해야 합니다.
#===============================================================================

class PokemonGlobalMetadata
  # 재고 관리를 위한 변수를 클래스에 추가합니다.
  # 이 코드는 "NoMethodError: undefined method 'token_mart_stock'" 오류를 해결합니다.
  attr_accessor :token_mart_stock
end

#===============================================================================
# Custom Token Mart System (최종 통합 버전)
#===============================================================================

# TokenMartAdapter 클래스를 정의하여 getDisplayPrice를 오버라이드합니다.
class TokenMartAdapter < PokemonMartAdapter
  def getDisplayPrice(item, selling = false)
    price = getPrice(item, selling).to_s_formatted
    return _INTL("{1}개",price) # 통화 기호 없이 순수한 가격 문자열만 반환
  end
end


module TokenMartSystem
  
  #===============================================================================
  # 1. TokenMart_Scene (z-order 수정)
  #===============================================================================
# [TokenMartSystem 모듈 내부]
class TokenMart_Scene < PokemonMart_Scene
  
  def initialize
    @sprites = {}
    @adapter = nil 
  end

  # 토큰 개수를 반환하는 메서드
  def token_currency_text
    token_id = :UPGRADETOKEN
    token_name = GameData::Item.get(token_id).name
    token_count = $bag.quantity(token_id)
    return _INTL("{1}: {2}", token_name, token_count.to_s_formatted)
  end
  
  # 💥 핵심 수정 1: pbStartScene을 오버라이드하여 pbSetMartGrid가 호출되도록 보장
  def pbStartScene(stock, adapter)
    @viewport = Viewport.new(0, 0, Graphics.width, Graphics.height)
    @viewport.z = 99999
    @stock = stock
    @scene = self
    @adapter = adapter 
    
    addBackgroundPlane(@sprites, "background", "mart_bg", @viewport)
    
    # 윈도우 생성 (pbSetMartGrid가 itemwindow, moneywindow, helpwindow 등을 생성)
    pbSetMartGrid(false)
    
    # 아이템 설명 윈도우 생성 (이것은 부모 클래스에 없으므로 직접 생성)
    @sprites["itemtextwindow"] = Window_AdvancedText.new("")
    @sprites["itemtextwindow"].z = 200
    @sprites["itemtextwindow"].x = 0
    @sprites["itemtextwindow"].y = Graphics.height - 96
    @sprites["itemtextwindow"].width = Graphics.width
    @sprites["itemtextwindow"].height = 96
    
    # 아이콘 윈도우 생성
    @sprites["icon"] = ItemIconSprite.new(Graphics.width - 70, Graphics.height - 70, nil, @viewport)
    
    # moneywindow가 생성된 후 토큰 정보로 갱신 (pbShowMoney가 drawWallet을 호출)
    pbShowMoney 
    
    pbFadeInAndShow(@sprites)
  end
  
  # 💥 핵심 수정 2: pbSetMartGrid 오버라이드 (Scene 객체 전달)
  def pbSetMartGrid(full_screen)
    winAdapter = BuyAdapter.new(@adapter) 
    
    # Window_PokemonMart에 Scene 객체(self)를 넘겨서 drawItemEntry, drawPrice 오버라이드가 작동하도록 유도
    @sprites["itemwindow"] = Window_PokemonMart.new(
      @stock, winAdapter, 
      Graphics.width - 320, 0, 320, Graphics.height - 96, self # 👈 마지막 인수로 self 전달
    )
    @sprites["itemwindow"].viewport = @viewport
    @sprites["itemwindow"].index = 0
    @sprites["itemwindow"].refresh
    
    # 나머지 윈도우는 부모 클래스처럼 생성
    @sprites["helpwindow"] = Window_UnformattedTextPokemon.new("")
    @sprites["helpwindow"].x = 0; @sprites["helpwindow"].y = 0;
    @sprites["helpwindow"].width = Graphics.width; @sprites["helpwindow"].height = 64;
    @sprites["helpwindow"].visible = false
    
    @sprites["moneywindow"] = Window_AdvancedText.new("")
    @sprites["moneywindow"].x = 0; @sprites["moneywindow"].y = 0;
    @sprites["moneywindow"].width = Graphics.width - @sprites["itemwindow"].width; 
    @sprites["moneywindow"].height = 96;
    @sprites["moneywindow"].visible = false
    @sprites["moneywindow"].windowskin = nil # 배경 투명화
    
    @sprites["quantitywindow"] = Window_UnformattedTextPokemon.new("")
    @sprites["quantitywindow"].x = 0; @sprites["quantitywindow"].y = Graphics.height - 96;
    @sprites["quantitywindow"].width = Graphics.width; @sprites["quantitywindow"].height = 64;
    @sprites["quantitywindow"].visible = false
  end

  # 💥 핵심 수정 3: Moneywindow에 토큰 개수 그리기
  def drawWallet(x, y, width, height)
    # moneywindow 객체를 직접 참조
    target_window = @sprites["moneywindow"] 
    target_contents = target_window.contents
    
    # Window_AdvancedText를 사용하는 경우, clear_rect 대신 text를 갱신
    target_window.text = "<ac>" + self.token_currency_text + "</ac>"
  end
  
  # 💥 핵심 수정 4: pbRefresh 오버라이드 (pbShowMoney 호출)
  def pbRefresh
    itemwindow = @sprites["itemwindow"]
    
    if itemwindow
      current_item = itemwindow.item
      @sprites["icon"].item = current_item
      
      if @sprites["itemtextwindow"]
        @sprites["itemtextwindow"].text =
          (current_item) ? @adapter.getDescription(current_item) : _INTL("취소합니다.")
      end
      itemwindow.refresh
    end
    
    # 토큰 정보를 갱신하기 위해 pbShowMoney를 호출합니다.
    pbShowMoney 
  end
  
  # 💥 핵심 수정 5: pbShowMoney 오버라이드 (토큰 갱신 로직)
  def pbShowMoney
    if @sprites["moneywindow"]
      # moneywindow의 내용을 저희의 drawWallet으로 갱신
      drawWallet(@sprites["moneywindow"].x, @sprites["moneywindow"].y, 
                 @sprites["moneywindow"].width, @sprites["moneywindow"].height)
      @sprites["moneywindow"].visible = true
      
      @sprites["quantitywindow"].visible = false if @sprites["quantitywindow"]
    end
  end

  # 아이템 목록 엔트리 그리기 (Window_PokemonMart가 호출)
  def drawItemEntry(index, rect, item_id, price)
    # 이 메서드는 Window_PokemonMart가 호출하며, self.window가 Window_PokemonMart 객체를 참조합니다.
    token_id = :UPGRADETOKEN
    token_name = GameData::Item.get(token_id).name
    self.window.contents.font.shadow = false
    item_name = GameData::Item.get(item_id).name
    text_pos = []
    text_pos.push([item_name, rect.x + 8, rect.y + 4, 0, Color.new(80, 80, 80), Color.new(160, 160, 160)])
    
    if price > 0
      price_text = _INTL("{1} {2}", price, token_name) 
      text_pos.push([price_text, rect.x + rect.width - 8, rect.y + 4, 2, Color.new(80, 80, 80), Color.new(160, 160, 160)])
    else
      text_pos.push([_INTL("N/A"), rect.x + rect.width - 8, rect.y + 4, 2, Color.new(80, 80, 80), Color.new(160, 160, 160)])
    end
    pbDrawTextPositions(self.window.contents, text_pos)
  end

  # 가격 정보 그리기 (Window_PokemonMart가 호출)
  def drawPrice(item_id, price)
    # 이 메서드는 Window_PokemonMart가 호출하며, self.window가 Window_PokemonMart 객체를 참조합니다.
    token_id = :UPGRADETOKEN
    token_name = GameData::Item.get(token_id).name_plural
    text = _INTL("이 부적은 {2} {1}개로 교환해줄게.", price.to_s, token_name)
    pbDrawTextPositions(
      self.window,
      [[text, self.window.width - 8, self.window.height - 40, 2, Color.new(248, 248, 248), Color.new(40, 48, 48)]]
    )
  end
  
  # 돈/수량 윈도우 제어 메서드
  def pbHideMoney
    @sprites["moneywindow"].visible = false if @sprites["moneywindow"]
  end
  
  def pbShowQuantity; end # 수량 창은 사용하지 않으므로 오버라이드
  def pbHideQuantity; end
end
  
  #===============================================================================
  # 2. TokenMartScreen
  #===============================================================================
  class TokenMartScreen < PokemonMartScreen
    # ... (클래스 내부 코드는 변경 없음. 위에서 어댑터만 수정) ...
    def initialize(scene, stock, adapter, token_id = :UPGRADETOKEN)
      super(scene, stock)
      @token_id = token_id
      @adapter = adapter # 외부에서 전달받은 어댑터를 사용합니다.
      @initial_stock = stock.clone
    end

    def pbSellScreen; end
    
    def getMartPrice(item_id)
      return @adapter.getPrice(item_id)
    end

    def pbBuyScreen
      @scene.pbStartBuyScene(@stock, @adapter) 
      item = nil
      loop do
        item = @scene.pbChooseBuyItem
        break if !item
        
        itemname = @adapter.getName(item)
        price = self.getMartPrice(item)
        token_name_plural = GameData::Item.get(@token_id).name_plural
        token_count = $bag.quantity(@token_id)
        
        if token_count < price
          pbDisplayPaused(_INTL("\\j[{2},을,를] 교환하기엔 {1}이 부족한 것 같네.", token_name_plural, itemname))
          next
        end
        
        if !pbConfirm(_INTL("토큰 {1}개와 교환할까?", price.to_s))
          next
        end
        
        $bag.remove(@token_id, price)
        $bag.add(item, 1)
        @scene.pbRefresh
        
        @stock.delete(item)
        pbDisplayPaused(_INTL("\\j[{1},을,를] 얻었다!", itemname)) { pbSEPlay("Mart buy item") }
        
        if @stock.empty?
          @scene.pbEndBuyScene
          break
        end
        
        @scene.pbRefresh
      end
      @scene.pbEndBuyScene
    end
  end
end

#===============================================================================
# pbTokenMart 호출 함수 (어댑터 사용하도록 수정)
#===============================================================================
def pbTokenMart(stock, speech = nil)
  unless Object.const_defined?(:TokenMartSystem)
    if $DEBUG
      pbMessage(_INTL("오류: TokenMartSystem 모듈이 정의되지 않았습니다. 스크립트 순서를 확인하세요."))
    end
    return
  end
  
  $PokemonGlobal.token_mart_stock ||= {}
  
  # 이미 구매한 아이템 제거
  current_stock = stock.reject { |item_id| $PokemonGlobal.token_mart_stock[item_id] }
  
  commands = []
  cmdBuy  = -1
  cmdQuit = -1
  
  commands[cmdBuy = commands.length] = _INTL("교환하기")
  commands[cmdQuit = commands.length] = _INTL("취소")
  
  cmd = pbMessage(speech || _INTL("안녕. 업그레이드 토큰을 부적과 교환해줄까?"), commands, cmdQuit + 1)
  
  loop do
    if cmdBuy >= 0 && cmd == cmdBuy
      scene = TokenMartSystem::TokenMart_Scene.new
      
      # 💥 TokenMartAdapter 인스턴스 생성 및 전달
      adapter = TokenMartAdapter.new 
      screen = TokenMartSystem::TokenMartScreen.new(scene, current_stock, adapter)
      
      screen.pbBuyScreen
      
      # 구매 기록
      stock.each do |item_id|
        unless current_stock.include?(item_id)
          $PokemonGlobal.token_mart_stock[item_id] = true
        end
      end
      
    else
      pbMessage(_INTL("토큰을 더 모으면 다시 와."))
      break
    end
    
    if current_stock.empty?
      pbMessage(_INTL("자, 이 부적을 가져 가."))
      break
    end
    
    cmd = pbMessage(_INTL("다른 부적을 더 구경할래?"), commands, cmdQuit + 1)
  end
  
  $game_temp.clear_mart_prices
end