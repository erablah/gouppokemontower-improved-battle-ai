#===============================================================================
# * Apricorn Charm / Kurt Script
#===============================================================================

# Adds a Kurt - The Apricorn Ball Crafter, without all the event pages.
# Call with "apricornToBall"
class KurtEventPage
# ==========  Messages for easy modification ========== #
  def greet # Initial Greeting / Greeting for Apricorn to Ball.
    pbMessage(_INTL("Hello! I'm Kurt!"))
    pbMessage(_INTL("I specialize in turning Apricorns into Poke Balls."))
    pbMessage(_INTL("Which Apricorn would you like me to convert?"))
  end

  def stillMaking # Message for coming back when Ball isn't done yet.
    pbMessage(_INTL("Sorry, I'm still making it."))
    pbMessage(_INTL("Come back later."))
  end
  
  def ballDone # Message for coming back after Ball is finished.
    pbMessage(_INTL("I've been waiting for you."))
    pbMessage(_INTL("I've completed the Poke Ball you asked me to make."))
  end
  
  def noThanks
    pbMessage(_INTL("Let me know when you want me to convert an Apricorn for you."))
    return
  end
  
  # ==========  End Messages ========== #
  
  def initialize
    ballForApricorn ||= nil
    @@newRun ||= Time.now
    $player.ball_for_apricorn ||= nil
    $player.next_run ||= 0
    @conversion_hash = {
      :REDAPRICORN    => :LEVELBALL,
      :YELLOWAPRICORN => :MOONBALL,
      :BLUEAPRICORN   => :LUREBALL,
      :GREENAPRICORN  => :FRIENDBALL,
      :PINKAPRICORN   => :LOVEBALL,
      :WHITEAPRICORN  => :FASTBALL,
      :BLACKAPRICORN  => :HEAVYBALL,
      :YLWAPRICORN    => :MOONBALL,
      :BLUAPRICORN    => :LUREBALL,
      :GRNAPRICORN    => :FRIENDBALL,
      :PNKAPRICORN    => :LOVEBALL,
      :WHTAPRICORN    => :FASTBALL,
      :BLKAPRICORN    => :HEAVYBALL
    }
  end

  def call
    timeNow = Time.now
    $player.next_run ||= @@newRun + DrCharmConfig::APRICORN_TO_BALL_TIME * 60 * 60
    if $player.ball_for_apricorn.is_a?(Symbol) && timeNow >= $player.next_run # Ball is set and done.
      ballDone
      if $player.activeCharm?(:APRICORNCHARM)
        x = 2
      else
        x = 1
      end
      pbReceiveItem($player.ball_for_apricorn, x)
      $player.ball_for_apricorn = nil
      @@newRun = 0
    elsif $player.ball_for_apricorn.is_a?(Symbol) && timeNow <= $player.next_run # Ball is set and not done.
      stillMaking
      timeLeft = $player.next_run - timeNow
      formatted_time_left = format_time(timeLeft)
      pbMessage(_INTL("There's still {1} left on your Ball!", formatted_time_left))
    else # Ball is not set.
      greet
      convert_apricorn
      if $player.ball_for_apricorn
        @@newRun = Time.now
        resetTime = DrCharmConfig::APRICORN_TO_BALL_TIME * 60 * 60
        if $player.activeCharm?(:APRICORNCHARM) && DrCharmConfig::REDUCE_APRICORN_TIME
          resetTime /= 2
        end
        $player.next_run = @@newRun + resetTime
      else
        noThanks
      end
    end
  end

  private
  
  def format_time(seconds)
    hours, remainder = seconds.divmod(3600)
    minutes, seconds = remainder.divmod(60)
    seconds = seconds.to_i
    formatted_time = []
    formatted_time << "#{hours} hour(s)" if hours > 0
    formatted_time << "#{minutes} minute(s)" if minutes > 0
    formatted_time << "#{seconds} second(s)" if seconds > 0
    formatted_time.join(' ')
  end

  def convert_apricorn
    ballForApricorn = pbChooseApricorn(8)
    if pbGet(8) == :NONE
    else
      apricorn = ballForApricorn
      aprBall = @conversion_hash[apricorn]
	  apricorn_data = GameData::Item.get(apricorn)
      aprBall_data = GameData::Item.get(aprBall)
	  ret = pbConfirmMessage(_INTL("Do you want to change your {1} into a {2}?"), apricorn_data.name, aprBall_data.name)
	  if ret
	    $player.ball_for_apricorn = aprBall
		$bag.remove(apricorn)
		pbMessage(_INTL("Okay. I'll turn your {1} into a {2} for you."), apricorn_data.name, aprBall_data.name)
		pbMessage(_INTL("I should be finished by tomorrow."))
	  else
		return nil
	  end
	end
  end
end

def apricornToBall
  apricorn_guy ||= KurtEventPage.new
  apricorn_guy.call
end