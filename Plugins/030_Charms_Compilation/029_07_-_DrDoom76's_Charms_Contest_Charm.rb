#===============================================================================
# * Bug Contest Charm
#===============================================================================

class BugContestState
  def pbStart(ballcount)
    old_ball = ballcount
    ballcount *= 1.5 if $player.activeCharm?(:CONTESTCHARM)
    @ballcount = ballcount
    @inProgress = true
    @otherparty = []
    @lastPokemon = nil
    @lastContest = nil
    @timer_start = System.uptime
    @places = []
    chosenpkmn = $player.party[@chosenPokemon]
    $player.party.length.times do |i|
      @otherparty.push($player.party[i]) if i != @chosenPokemon
    end
    @contestants = []
    [5, CONTESTANT_NAMES.length].min.times do
      loop do
        value = rand(CONTESTANT_NAMES.length)
        next if @contestants.include?(value)
        @contestants.push(value)
        break
      end
    end
    $player.party = [chosenpkmn]
    @decision = 0
    @ended = false
    $stats.bug_contest_count += 1
    if $player.activeCharm?(:CONTESTCHARM)
      balldif = ballcount - old_ball
      balldif = balldif.to_i
      pbMessage(_INTL("{1} Balls have been added due to Contest Charm!", balldif))
    end
  end
end

# Returns a score for this Pokemon in the Bug Catching Contest.
# Not exactly the HGSS calculation, but it should be decent enough.
def pbBugContestScore(pkmn)
  levelscore = pkmn.level * 4
  ivscore = 0
  pkmn.iv.each_value { |iv| ivscore += iv.to_f / Pokemon::IV_STAT_LIMIT }
  ivscore = (ivscore * 100).floor
  hpscore = (100.0 * pkmn.hp / pkmn.totalhp).floor
  catch_rate = pkmn.species_data.catch_rate
  rarescore = 60
  rarescore += 20 if catch_rate <= 120
  rarescore += 20 if catch_rate <= 60
  rarescore *= 1.1 if $player.activeCharm?(:CONTESTCHARM)
  return levelscore + ivscore + hpscore + rarescore
end