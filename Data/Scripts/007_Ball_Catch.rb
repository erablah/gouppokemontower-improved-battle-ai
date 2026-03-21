#===============================================================================
# * Ball Catch Game - by FL (Credits will be apreciated)
#===============================================================================
#
# This script is for Pokémon Essentials. It's a simple minigame where the player
# must pick the balls that are falling at screen.
#
#== INSTALLATION ===============================================================
#
# Put it above main or convert into a plugin. Create "Ball Catch" folder at 
# Graphics/UI and put the images (may works with other sizes):
# -  20x20  ball
# - 512x384 bg 
# -  80x44  catcher
#
#== HOW TO USE =================================================================
#
# To call this script, use the script command 'BallCatch.play' This method will 
# return the number of picked balls or nil if cancelled. 
#
#== NOTES ======================================================================
#
# You can pass game parameters using BallCatch::Parameters. Example:
#  
#  params = BallCatch::Parameters.new
#  params.balls = 20
#  params.initial_seconds_per_line = 0.4
#  params.final_seconds_per_line = 0.2
#  params.can_exit = false
#  BallCatch.play(params)
#
# Look at class Parameters for full parameter list.
#
#===============================================================================

if defined?(PluginManager) && !PluginManager.installed?("Ball Catch Game")
  PluginManager.register({                                                 
    :name    => "Ball Catch Game",                                        
    :version => "1.4.1",                                                     
    :link    => "https://www.pokecommunity.com/showthread.php?t=317142",             
    :credits => "FL"
  })
end

module BallCatch
  class Parameters
    # Ball speed when game start and when ends. 
    # The game interpolate between these two values base on spawned ball count
    attr_accessor :initial_ball_speed
    attr_accessor :final_ball_speed
    
    # Bigger values = More time between ball spawn tries.
    # The game interpolate between these two values base on spawned ball count
    attr_accessor :initial_seconds_per_line
    attr_accessor :final_seconds_per_line
    
    # Total balls spawned
    attr_accessor :balls
    
    # The number of positions/columns for the balls/player
    attr_accessor :columns
    
    # Player sprite speed. Lower = move faster. 1 = Instant move
    attr_accessor :player_seconds_to_move
    
    # Lines per ball proportion. Lower = less vertical "gaps" between balls
    attr_accessor :line_per_ball
    
    # If player can exit
    attr_accessor :can_exit
    
    # Set the default values
    def initialize 
      @initial_ball_speed = 400
      @final_ball_speed = 700
      @initial_seconds_per_line = 0.3
      @final_seconds_per_line = 0.3
      @balls = 50
      @columns = 7
      @player_seconds_to_move = 0.1
      @line_per_ball = 3
      @can_exit = true
    end
    
    def total_lines
      return (@line_per_ball*@balls).floor
    end
    
    def ball_speed(ratio)
      return lerp(@initial_ball_speed, @final_ball_speed, ratio) 
    end
    
    def seconds_per_line(ratio)
      # Because this makes no sense 
      if @final_seconds_per_line>@initial_seconds_per_line
        raise "initial_seconds_per_line (#{@initial_seconds_per_line}) should not be lower than final_seconds_per_line (#{@final_seconds_per_line})"
      end
      return lerp(@final_seconds_per_line, @initial_seconds_per_line, 1.0-ratio)
    end
    
    def lerp(a, b, t)
      return a*(1.0-t)+b*t
    end
  end

  class Scene
    X_START=56
    Y_START=-40
    X_GAIN=64
    MAX_DISTANCE_BETWEEN_BALLS = 1
    ROTATE_SPEED=400
    
    def pbStartScene(parameters)
      @params = parameters || Parameters.new
      @sprites={} 
      @viewport=Viewport.new(0,0,Graphics.width,Graphics.height)
      @viewport.z=99999
      @sprites["background"]=IconSprite.new(0,0,@viewport)
      @sprites["background"].setBitmap("Graphics/UI/Ball Catch/bg")
      @sprites["background"].x = (
        Graphics.width-@sprites["background"].bitmap.width
      )/2
      @sprites["background"].y = (
        Graphics.height-@sprites["background"].bitmap.height
      )/2
      @sprites["player"]=IconSprite.new(0,0,@viewport)
      @sprites["player"].setBitmap("Graphics/UI/Ball Catch/catcher")
      @sprites["player"].y=340-@sprites["player"].bitmap.height/2
      @sprites["overlay"] = BitmapSprite.new(
        Graphics.width,Graphics.height,@viewport
      )
      pbSetSystemFont(@sprites["overlay"].bitmap)
      initializeBallsPositions
      @playerColumn=@params.columns/2
      @playerPosition = playerColumnPosition(@playerColumn)
      refreshPlayerPosition
      @ballCount = 0
      @score=0
      @ballsY = [] # Used to calculate balls current Y positions using floats
      pbDrawText
      pbBGMPlay(Bridge.bgm_path)
      pbFadeInAndShow(@sprites) { update }
    end
  
    def pbDrawText
      overlay=@sprites["overlay"].bitmap
      overlay.clear 
      score=_INTL("Score: {1}/{2}",@score,@params.balls)
      textPositions=[[
        score,8,14,false,Color.new(248,248,248),Color.new(112,112,112)
      ]]
      Bridge.drawTextPositions(overlay,textPositions)
    end
    
    def updatePlayerPosition
      targetPosition = playerColumnPosition(@playerColumn)
      return if @playerPosition == targetPosition
      gain = Bridge.delta*X_GAIN/@params.player_seconds_to_move.to_f
      if targetPosition>@playerPosition
        @playerPosition=[@playerPosition+gain, targetPosition].min
      else
        @playerPosition=[@playerPosition-gain, targetPosition].max
      end
      refreshPlayerPosition
    end
        
    def refreshPlayerPosition
      @sprites["player"].x=@playerPosition-@sprites["player"].bitmap.width/2
    end
        
    def playerColumnPosition(column)
      return X_START+X_GAIN*column
    end 
    
    def update
      pbUpdateSpriteHash(@sprites)
    end
    
    def initializeBall(position)
      i=0
      # This method reuse old balls for better performance
      loop do
        if !@sprites["ball#{i}"]
          @sprites["ball#{i}"]=IconSprite.new(0,0,@viewport)
          @sprites["ball#{i}"].setBitmap("Graphics/UI/Ball Catch/ball")
          @sprites["ball#{i}"].ox=@sprites["ball#{i}"].bitmap.width/2
          @sprites["ball#{i}"].oy=@sprites["ball#{i}"].bitmap.height/2
          break
        end  
        if !@sprites["ball#{i}"].visible
          @sprites["ball#{i}"].visible=true
          break
        end
        i+=1
      end
      @sprites["ball#{i}"].x=X_START+X_GAIN*position
      @ballsY[i] = Y_START.to_f
      @sprites["ball#{i}"].y=@ballsY[i].round
    end  
     
    def initializeBallsPositions
      @lineArray=[]
      @lineArray[@params.total_lines-1]=nil # One position for every line
      loop do
        while Bridge.nitems(@lineArray)<@params.balls
          ballIndex = rand(@params.total_lines)
          @lineArray[ballIndex]=rand(@params.columns) if !@lineArray[ballIndex]
        end  
        for i in 0...@lineArray.size
          next if !@lineArray[i]
          # Checks if the ball isn't too distant to pick.
          # If is, remove from the array
          checkRight(i+1,@lineArray[i]+MAX_DISTANCE_BETWEEN_BALLS)
          checkLeft(i+1,@lineArray[i]-MAX_DISTANCE_BETWEEN_BALLS)
        end
        return if Bridge.nitems(@lineArray)==@params.balls
      end
    end  
    
    def checkRight(index, position)
      return if (position>=@params.columns || index>=@lineArray.size)
      if (@lineArray[index] && @lineArray[index]>position)
        @lineArray[index]=nil
      end
      checkRight(index+1,position+MAX_DISTANCE_BETWEEN_BALLS)
    end  
    
    def checkLeft(index, position)
      return if (position<=0 || index>=@lineArray.size)
      if (@lineArray[index] && @lineArray[index]<position)
        @lineArray[index]=nil
      end
      checkLeft(index+1,position-MAX_DISTANCE_BETWEEN_BALLS)
    end  
    
    def applyCollisions
      i=0
      loop do
        break if !@sprites["ball#{i}"]
        if @sprites["ball#{i}"].visible
          @ballsY[i] += Bridge.delta*@params.ball_speed(
            inverseLerp(0, @params.balls, @ballCount)
          )
          @sprites["ball#{i}"].y = @ballsY[i].round
          @sprites["ball#{i}"].angle += (ROTATE_SPEED*Bridge.delta).round
          ballBottomY=@sprites["ball#{i}"].y+@sprites["ball#{i}"].bitmap.height
         
          # Collision with player
          ballPosition = (
            @sprites["ball#{i}"].x-X_START+@sprites["ball#{i}"].bitmap.width/2
          )/X_GAIN
          if ballPosition==@playerColumn
            collisionStartY=-8 
            collisionEndY=10
            # Based at target center
            playerCenterY=@sprites["player"].y+@sprites["player"].bitmap.width/2
            collisionStartY+=playerCenterY
            collisionEndY+=playerCenterY
            if(collisionStartY < ballBottomY && collisionEndY > ballBottomY)
              # The ball was picked  
              @sprites["ball#{i}"].visible=false
              pbSEPlay(Bridge.ball_pick_se_path)
              @score+=1
              pbDrawText # Update score at screen
            end
          end
          
          # Collision with screen limit
          screenLimit = Graphics.height+@sprites["ball#{i}"].bitmap.height
          if(ballBottomY>screenLimit)
            # The ball was out of screen 
            @sprites["ball#{i}"].visible=false
            pbSEPlay(Bridge.ball_out_se_path)
          end
        end  
        i+=1
      end
    end  
    
    def thereBallsInGame?
      i=0
      loop do
        return false if !@sprites["ball#{i}"]
        return true if @sprites["ball#{i}"].visible
        i+=1
      end
    end
      
    def pbMain
      stopBalls = false
      secondsToNextBall = 0.0
      lineIndex = 0
      loop do
        applyCollisions
        if secondsToNextBall<=0 && !stopBalls 
          if @lineArray[lineIndex]
            initializeBall(@lineArray[lineIndex])
            @ballCount+=1
          end
          lineIndex+=1
          stopBalls = lineIndex>=@lineArray.size
          secondsToNextBall += @params.seconds_per_line(
            inverseLerp(0, @params.balls-1, @ballCount)
          )
        end
        Graphics.update
        Input.update
        self.update
        if stopBalls && !thereBallsInGame?
          Bridge.message(_INTL("게임 종료!"))
          break
        end  
        if Input.repeat?(Input::LEFT) && @playerColumn>0
          @playerColumn=@playerColumn-1
        end
        if Input.repeat?(Input::RIGHT) && @playerColumn<(@params.columns-1)
          @playerColumn=@playerColumn+1
        end
        if Input.repeat?(Input::B) && @params.can_exit
          return nil if Bridge.confirmMessage(_INTL("Exit?"))
        end
        updatePlayerPosition      
        secondsToNextBall-=Bridge.delta
      end
      return @score
    end
  
    def pbEndScene
      $game_map.autoplay
      pbFadeOutAndHide(@sprites) { update }
      pbDisposeSpriteHash(@sprites)
      @viewport.dispose
    end
  
    def inverseLerp(a, b, t)
      return (t.to_f-a)/(b-a)
    end
  end
  
  class Screen
    def initialize(scene)
      @scene=scene
    end
  
    def pbStartScreen(parameters)
      @scene.pbStartScene(parameters)
      ret=@scene.pbMain
      @scene.pbEndScene
      return ret
    end
  end
  
  def self.play(parameters = nil)
    ret = nil
    pbFadeOutIn(99999) { 
      scene=Scene.new
      screen=Screen.new(scene)
      ret = screen.pbStartScreen(parameters)
    }
    return ret
  end
  
  # Essentials multiversion layer
  module Bridge
    module_function

    def major_version
      ret = 0
      if defined?(Essentials)
        ret = Essentials::VERSION.split(".")[0].to_i
      elsif defined?(ESSENTIALS_VERSION)
        ret = ESSENTIALS_VERSION.split(".")[0].to_i
      elsif defined?(ESSENTIALSVERSION)
        ret = ESSENTIALSVERSION.split(".")[0].to_i
      end
      return ret
    end

    MAJOR_VERSION = major_version

    def delta
      return 0.025 if MAJOR_VERSION < 21
      return Graphics.delta
    end

    def nitems(array)
      return array.nitems if MAJOR_VERSION < 19
      return array.count{|x| !x.nil?}
    end
    
    def message(string, &block)
      return Kernel.pbMessage(string, &block) if MAJOR_VERSION < 20
      return pbMessage(string, &block)
    end

    def confirmMessage(string, &block)
      return Kernel.pbConfirmMessage(string, &block) if MAJOR_VERSION < 20
      return pbConfirmMessage(string, &block)
    end

    def drawTextPositions(bitmap,textpos)
      if MAJOR_VERSION < 20
        for singleTextPos in textpos
          singleTextPos[2] -= MAJOR_VERSION==19 ? 12 : 6
        end
      end
      return pbDrawTextPositions(bitmap,textpos)
    end

    def ball_pick_se_path
      return "jump" if MAJOR_VERSION < 17
      return "Player jump"
    end

    def ball_out_se_path
      return "balldrop" if MAJOR_VERSION < 17
      return "Battle ball drop"
    end

    def bgm_path
      return "021-Field04" if MAJOR_VERSION < 20
      return "Safari Zone"
    end
  end
end