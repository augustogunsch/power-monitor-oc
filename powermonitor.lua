local component = require("component")
local event = require("event")
local term = require("term")
local math = require("math")
local os = require("os")
local computer = require("computer")
local string = require("string")
local gpu = component.gpu

local updateCooldown = 1 --seconds
local barHeight = 3
local unit = "RF"
local balanceCooldown = updateCooldown*1 --seconds

local yellow =0xfcdf02
local red = 0xfc0202
local green = 0x43d31f
local gray = 0x3a3a3a

local energyCells = {}
local energyCellsCount = 0

local function updateEnergyCells()
  energyCells = {}
  energyCellsCount = 0
  for address, name in component.list("energy_device", false) do
    table.insert(energyCells, component.proxy(address))
    energyCellsCount = energyCellsCount + 1
  end
end

local function handleSigint()
  local id, _ = event.pull(updateCooldown, "interrupted")
  if (id == "interrupted") then
    os.exit(0)
  end
end

local function getColor(percentage)
  if (percentage <= 0.2) then
    return red
  end
  if (percentage <= 0.5) then
    return yellow
  end
  return green
end

local function getColorBalance(balance)
  if (balance == 0) then
    return yellow
  end
  if (balance < 0) then
    return red
  end
  return green
end

local function drawBar(filledPercentage, width, height, name)
  local pWidth = width-4
  local fWidth = math.modf(pWidth*filledPercentage)

  local function getChAmnt(char, amount)
    local i = 0
    local result = ""
    while (i < amount) do
      result = result .. char
      i = i + 1
    end
    return result
  end
     
  local oldBg = gpu.getBackground()
  local oldFg = gpu.getForeground()
  local color = getColor(filledPercentage)
  local filledChars = getChAmnt(" ", fWidth)
  local unfilledChars = getChAmnt(" ", pWidth-fWidth)
  
  term.write("--- "..name.." power: ")
  gpu.setForeground(color)
  term.write(math.modf(filledPercentage*100).."%\n\n")
  gpu.setForeground(oldFg)

  local i = 0
  while (i < height) do
    term.write("  ")

    gpu.setBackground(color)
    term.write(filledChars)

    gpu.setBackground(gray)
    term.write(unfilledChars)

    gpu.setBackground(oldBg)
    term.write("  ")
    i = i + 1
  end
end

local function getTotalPower()
  local stored, maxStored = 0, 0
  
  for key, value in pairs(energyCells) do
    stored = stored + tonumber(value.getEnergyStored())
    maxStored = maxStored + tonumber(value.getMaxEnergyStored())
  end

  return stored, maxStored
end  

local lastCheckpointTime = computer.uptime()
local lastCheckpointPower = getTotalPower()
local balance = 0
local timeLeft = 0

local function drawMonitor()
  local stored, maxStored = getTotalPower()
  stored = stored / 1000
  maxStored = maxStored / 1000
  local oldFg = gpu.getForeground()
  local width = term.getViewport()
  local filledPercentage = stored/maxStored

  term.clear()
  drawBar(filledPercentage, width, barHeight, "Main")

  term.write("\n\n--- Details:\n\n")
  term.write("Energy cells: "..energyCellsCount.."\n")
  term.write("Absolute power: "..stored.."k "..unit.."\n")
  term.write("Absolute capacity: "..maxStored.."k "..unit.."\n")
  term.write("Balance: ")
  gpu.setForeground(getColorBalance(balance))
  term.write(string.format("%.2f",balance).." "..unit.."/t\n")
  gpu.setForeground(oldFg)

  if not (timeLeft == 0) then
    term.write("Time left: "..
                         math.modf(timeLeft/60).."min "
                       ..math.modf(timeLeft%60).."s\n")
  end
end

local function updateBalance()
  local time = computer.uptime()
  local timeDiff = time - lastCheckpointTime
  if (timeDiff > balanceCooldown) then
    local power, maxPower = getTotalPower()
    local balanceS = (power-lastCheckpointPower)/timeDiff

    lastCheckpointTime = time
    balance = balanceS/20
    lastCheckpointPower = power

    if (balanceS < 0) then
      timeLeft = power/math.abs(balanceS)
    elseif (balanceS > 0) then
      timeLeft = (maxPower-power)/balanceS
    else
      timeLeft = 0
    end
  end
end

while true do
  updateEnergyCells()

  drawMonitor()

  updateBalance()

  handleSigint()
end
