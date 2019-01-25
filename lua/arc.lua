--- Arc class
-- @module arc
-- @alias Arc
require 'norns'


---------------------------------
-- Arc device class

local Arc = {}
Arc.__index = Arc

Arc.devices = {}
Arc.vports = {}

for i=1,4 do
  Arc.vports[i] = {
    name = "none",
    device = nil,
    delta = nil,
    key = nil,
    led = function(self, ...) if self.device then self.device:led(...) end end,
    all = function(self, ...) if self.device then self.device:all(...) end end,
    refresh = function(self, ...) if self.device then self.device:refresh(...) end end,
    segment = function(self, ...) if self.device then self.device:segment(...) end end,
  }
end

--- constructor
-- @tparam integer id : arbitrary numeric identifier
-- @tparam string serial : serial
-- @tparam string name : name
-- @tparam userdata dev : opaque pointer to device
function Arc.new(id, serial, name, dev)
  local device = setmetatable({}, Arc)
  
  device.id = id
  device.serial = serial
  device.name = name.." "..serial
  device.dev = dev -- opaque pointer
  device.delta = nil -- delta event callback
  device.key = nil -- key event callback
  device.remove = nil -- device unplug callback
  device.port = nil

  -- autofill next postiion
  local connected = {}
  for i=1,4 do
    table.insert(connected, Arc.vports[i].name)
  end
  if not tab.contains(connected, device.name) then
    for i=1,4 do
      if Arc.vports[i].name == "none" then
        Arc.vports[i].name = name
        break
      end
    end
  end

  return device
end

--- static callback when any arc device is added;
-- user scripts can redefine
-- @param dev : a Arc table
function Arc.add(dev)
  print("arc added:", dev.id, dev.name, dev.serial)
end

--- scan device list and grab one, redefined later
function Arc.reconnect() end

--- static callback when any arc device is removed;
-- user scripts can redefine
-- @param dev : a Arc table
function Arc.remove(dev) end

--- set state of single LED on this arc device
-- @tparam integer ring : ring index (1-based!)
-- @tparam integer x : led index (1-based!)
-- @tparam integer val : LED brightness in [0, 15]
function Arc:led(ring, x, val)
  arc_set_led(self.dev, ring, x, val)
end

--- set state of all LEDs on this arc device
-- @tparam integer val : LED brightness in [0, 15]
function Arc:all(val)
  arc_all_led(self.dev, val)
end

--- update any dirty quads on this arc device
function Arc:refresh()
  monome_refresh(self.dev)
end

--- draw anti-aliased point to point arc
-- @tparam integer ring : ring index (1-based)
-- @tparam number from : from angle in radians
-- @tparam number to : to angle in radians
-- @tparam integer level: LED brightness in [0, 15]
function Arc:segment(ring, from, to, level)
  local tau = math.pi * 2

  local function overlap(a, b, c, d)
    if a > b then
       return overlap(a, tau, c, d) + overlap(0, b, c, d)
    elseif c > d then
       return overlap(a, b, c, tau) + overlap(a, b, 0, d)
    else
       return math.max(0, math.min(b, d) - math.max(a, c))
     end
  end

  local function overlap_segments(a, b, c, d)
    a = a % tau
    b = b % tau
    c = c % tau
    d = d % tau

    return overlap(a, b, c, d)
  end

  local m = {}
  local sl = tau / 64

  for i=1, 64 do
    local sa = tau / 64 * (i - 1)
    local sb = tau / 64 * i

    local o = overlap_segments(from, to, sa, sb)
    m[i] = util.round(o / sl * level)
    self:led(ring, i, m[i])
  end
end

--- create device, returns object with handler and send
function Arc.connect(n)
  local n = n or 1
  return Arc.vports[n]
end

--- clear handlers
function Arc.cleanup()
  for i=1,4 do
    Arc.vports[i].delta = nil
    Arc.vports[i].key = nil
  end
end

function Arc.update_devices()
  -- reset vports for existing devices
  for _, device in pairs(Arc.devices) do
    device.port = nil
  end

  -- connect available devices to vports
  for i=1,4 do
    Arc.vports[i].device = nil
    
    for _, device in pairs(Arc.devices) do
      if device.name == Arc.vports[i].name then
        Arc.vports[i].device = device
        device.port = i
      end
    end
  end
end

norns.arc = {}

-- arc devices
norns.arc.add = function(id, serial, name, dev)
  local g = Arc.new(id, serial, name, dev)
  Arc.devices[id] = g
  Arc.update_devices()
  if Arc.add ~= nil then Arc.add(g) end
end

norns.arc.remove = function(id)
  if Arc.devices[id] then
    if Arc.remove ~= nil then
      Arc.remove(Arc.devices[id])
    end
    if Arc.devices[id].remove then
      Arc.devices[id].remove()
    end
  end
  Arc.devices[id] = nil
  Arc.update_devices()
end

norns.arc.delta = function(id, n, delta)
  local device = Arc.devices[id]

  if device ~= nil then
    if device.delta then
      device.delta(n, delta)
    end
    if device.port then
      if Arc.vports[device.port].delta then
        Arc.vports[device.port].delta(n, delta)
      end
    end
  else
    error('no entry for arc '..id)
  end
end

norns.arc.key = function(id, n, s)
  local device = Arc.devices[id]

  if device ~= nil then
    if device.key then
      device.key(n, s)
    end
    if device.port then
       if Arc.vports[device.port].key then
         Arc.vports[device.port].key(n, s)
       end
    end  
  else
    error('no entry for arc '..id)
  end
end

return Arc
