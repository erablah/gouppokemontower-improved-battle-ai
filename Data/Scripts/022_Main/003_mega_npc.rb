def mega_npc
  # 1. The list of stones
  new_stones = [:VENUSAURITE, :CHARIZARDITEX, :CHARIZARDITEY, :BLASTOISINITE, :BEEDRILLITE, :PIDGEOTITE, :ALAKAZITE, :SLOWBRONITE, :GENGARITE, :KANGASKHANITE, :PINSIRITE, :GYARADOSITE, :AERODACTYLITE, :AMPHAROSITE, :STEELIXITE, :SCIZORITE, :HERACRONITE, :HOUNDOOMINITE, :TYRANITARITE, :SCEPTILITE, :BLAZIKENITE, :SWAMPERTITE, :GARDEVOIRITE, :SABLENITE, :MAWILITE, :AGGRONITE, :MEDICHAMITE, :MANECTITE, :SHARPEDONITE, :CAMERUPTITE, :ALTARIANITE, :BANETTITE, :ABSOLITE, :GLALITITE, :SALAMENCITE, :METAGROSSITE, :LOPUNNITE, :GARCHOMPITE, :LUCARIONITE, :ABOMASITE, :GALLADITE, :AUDINITE, :CLEFABLITE, :VICTREEBELITE, :STARMINITE, :DRAGONITENITE, :MEGANIUMITE, :FERALIGITE, :SKARMORITE, :FROSLASSITE, :EMBOARITE, :EXCADRITE, :SCOLIPITE, :SCRAFTINITE, :EELEKTROSSITE, :CHANDELURITE, :CHESNAUGHTITE, :DELPHOXITE, :GRENINJITE, :PYROARITE, :MALAMARITE, :BARBARACITE, :DRAGALGITE, :HAWLUCHANITE, :DRAMPANITE, :FALINKSITE, :RAICHUNITEX, :RAICHUNITEY, :CHIMECHITE, :ABSOLITEZ, :STARAPTITE, :GARCHOMPITEZ, :LUCARIONITEZ, :GOLURKITE, :MEOWSTICITE, :CRABOMINITE, :GOLISOPITE, :SCOVILLAINITE, :BAXCALIBRITE, :TATSUGIRINITE, :GLIMMORANITE]

  # 2. Build the commands [cite: 1087, 1095]
  commands = []
  new_stones.each { |s| commands.push(GameData::Item.get(s).name) }
  commands.push(_INTL("Cancel"))

  # 3. Use -1 for the cancel_index
  # Setting the 3rd argument to -1 tells the game: "If they hit back, return -1"
  sel = pbMessage("어떤 메가 스톤을 들고 갈래?", commands, -1)

  # 4. Process the selection
  # Now, pressing 'X' or 'Cancel' will return a value that doesn't trigger the item give
  if sel >= 0 && sel < new_stones.length
    if pbReceiveItem(new_stones[sel])
      # This turns on Self Switch A for the NPC
      pbSetSelfSwitch(@event_id, "A", true)
    end
  else
    # This runs if sel is -1 (back button) or points to "Cancel"
    pbMessage("조금 더 생각해봐.")
  end
end