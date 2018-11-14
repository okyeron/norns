--- Arc class
-- @module arc
-- @alias Arc
require 'norns'


---------------------------------
-- Arc device class

local Arc = {}
Arc.devices = {}
Arc.list = {}
Arc.vport = {}
for i=1,4 do
  Arc.vport[i] = {
    name = "none",
    callbacks = {},
    index = 0,
    led = function() end,
    all = function() end,
    refresh = function() end,
    attached = false
  }
end
Arc.__index = Arc

--- constructor
-- @tparam integer id : arbitrary numeric identifier
-- @tparam string serial : serial
-- @tparam string name : name
-- @tparam userdata dev : opaque pointer to device
function Arc.new(id, serial, name, dev)
  local a = setmetatable({}, Arc)
  a.id = id
  a.serial = serial
  name = name .. " " .. serial
  --while tab.contains(Arc.list,name) do
  --  name = name .. "+"
  --end
  a.name = name
  a.dev = dev -- opaque pointer
  a.key = nil -- key event callback
  a.remove = nil -- device unplug callback
  a.encs = arc_encs(dev)
  a.ports = {} -- list of virtual ports this device is attached to

  -- autofill next postiion
  local connected = {}
  for i=1,4 do
    table.insert(connected, Arc.vport[i].name)
  end
  if not tab.contains(connected, name) then
    for i=1,4 do
      if Arc.vport[i].name == "none" then
        Arc.vport[i].name = name
        break
      end
    end
  end

  return a
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
-- @tparam integer enc : encoder index (1-based!)
-- @tparam integer led : led index (1-based!)
-- @tparam integer val : LED brightness in [1, 16]
function Arc:led(enc, led, val)
  arc_set_led(self.dev, enc, led, val)
end

--- set state of all LEDs on this arc device
-- @tparam integer enc : encoder index (1-based!)
-- @tparam integer val : LED brightness in [1, 16]
function Arc:all(enc, val)
  arc_all_led(self.dev, enc, val)
end

--- update any dirty quads on this arc device
function Arc:refresh(enc)
  arc_refresh(self.dev, enc)
end

--- print a description of this arc device
function Arc:print()
  for k,v in pairs(self) do
    print('>> ', k,v)
  end
end


--- create device, returns object with handler and send
function Arc.connect(n)
  local n = n or 1
  if n>4 then n=4 end

  Arc.vport[n].index = Arc.vport[n].index + 1

  local d = {
    index = Arc.vport[n].index,
    port = n,
    encs = function() return Arc.vport[n].encs end,

    event = function(x,y,z)
        print("arc input")
      end,
    attached = function() return Arc.vport[n].attached end,
    led = function(x,y,z) Arc.vport[n].led(x,y,z) end,
    all = function(x,val) Arc.vport[n].all(x,val) end,
    refresh = function(x) Arc.vport[n].refresh(x) end,
    disconnect = function(self)
        self.led = function() end
        self.all = function() end
        self.refresh = function() print("refresh: arc not connected") end
        Arc.vport[self.port].callbacks[self.index] = nil
        self.index = nil
        self.port = nil
      end,
    reconnect = function(self, p)
        p = p or 1
        if self.index then
          Arc.vport[self.port].callbacks[self.index] = nil
        end
        self.attached = function() return Arc.vport[p].attached end
        self.led = function(x,y,z) Arc.vport[p].led(x,y,z) end
        self.all = function(x,val) Arc.vport[p].all(x,val) end
        self.refresh = function(x) Arc.vport[p].refresh(x) end
        Arc.vport[p].index = Arc.vport[p].index + 1
        self.index = Arc.vport[p].index
        self.port = p
        self.encs = function() return Arc.vport[p].encs end

        Arc.vport[p].callbacks[self.index] = function(x,y,z) self.event(x,y,z) end
      end
  }

	Arc.vport[n].callbacks[d.index] = function(x,y,z) d.event(x,y,z) end

  return d
end

--- clear handlers
function Arc.cleanup()
  for i=1,4 do
    Arc.vport[i].callbacks = {}
		Arc.vport[i].index = 0
  end
end

function Arc.update_devices()
  -- build list of available devices
  Arc.list = {}
  for _,device in pairs(Arc.devices) do
    table.insert(Arc.list, device.name)
    device.ports = {}
  end
  -- connect available devices to vports
  for i=1,4 do
    Arc.vport[i].attached = false
    Arc.vport[i].led = function(x,y,val) end
    Arc.vport[i].all = function(x,val) end
    Arc.vport[i].refresh = function(x) end
    for _,device in pairs(Arc.devices) do
      if device.name == Arc.vport[i].name then
        Arc.vport[i].led = function(x,y,val) device:led(x,y,val) end
        Arc.vport[i].all = function(x,val) device:all(x,val) end
        Arc.vport[i].refresh = function(x) device:refresh(x) end
        Arc.vport[i].attached = true
        table.insert(device.ports, i)
      end
    end
  end
end



-- arc devices
norns.arc.add = function(id, serial, name, dev)
  local a = Arc.new(id,serial,name,dev)
  Arc.devices[id] = a
  Arc.update_devices()
  if Arc.add ~= nil then Arc.add(a) end
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


--- redefine global arc enc input handler
norns.arc.enc = function(id, x, delta)
  local a = Arc.devices[id]
  if a ~= nil then
    if a.enc ~= nil then
      a.enc(x, delta)
    end

    for _,n in pairs(a.ports) do
      for _,event in pairs(Arc.vport[n].callbacks) do
        --print("vport " .. n)
        event(x,delta)
      end
    end
  else
    print('>> error: no entry for arc ' .. id)
  end
end

--- redefine global grid key input handler
norns.arc.key = function(id, enc, state)
  local a = Arc.devices[id]
  if a ~= nil then
    if a.key ~= nil then
      a.key(enc, state)
    end

    for _,n in pairs(a.ports) do
      for _,event in pairs(Arc.vport[n].callbacks) do
        --print("vport " .. n)
        event(enc,state)
      end
    end
  else
    print('>> error: no entry for grid ' .. id)
  end
end


return Arc