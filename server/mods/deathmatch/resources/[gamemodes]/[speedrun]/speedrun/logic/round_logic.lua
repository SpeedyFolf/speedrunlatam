-- Pure round state machine (no MTA APIs). Lua 5.1 compatible.
RoundLogic = {}
RoundLogic.__index = RoundLogic

function RoundLogic.new(opts)
    opts = opts or {}
    local self = setmetatable({}, RoundLogic)
    self.timeLimitMs = opts.timeLimitMs or 900000
    self.extraAfterFirstMs = opts.extraAfterFirstMs or 180000
    self.state = "waiting"
    self.players = {}
    self.startMs = nil
    self.firstFinishMs = nil
    return self
end

function RoundLogic:addPlayer(id)
    if not self.players[id] then
        self.players[id] = {finishedMs = nil, failures = 0, dnf = false}
    end
end

function RoundLogic:start(nowMs)
    self.state = "countdown"
end

function RoundLogic:go(nowMs)
    self.state = "running"
    self.startMs = nowMs
end

function RoundLogic:fail(id, nowMs)
    local p = self.players[id]
    if self.state ~= "running" or not p then return false end
    p.failures = p.failures + 1
    return true
end

function RoundLogic:finish(id, nowMs)
    local p = self.players[id]
    if self.state ~= "running" or not p then return nil end
    if p.finishedMs ~= nil or p.dnf then return nil end
    p.finishedMs = nowMs - self.startMs
    if self.firstFinishMs == nil then self.firstFinishMs = nowMs end
    return p.finishedMs
end

function RoundLogic:quit(id, nowMs)
    local p = self.players[id]
    if not p then return end
    if p.finishedMs == nil then p.dnf = true end
end

function RoundLogic:deadline()
    if self.startMs == nil then return nil end
    local d = self.startMs + self.timeLimitMs
    if self.firstFinishMs ~= nil then
        local e = self.firstFinishMs + self.extraAfterFirstMs
        if e < d then d = e end
    end
    return d
end

function RoundLogic:tick(nowMs)
    if self.state ~= "running" then return self.state end
    local count, done = 0, 0
    for _, p in pairs(self.players) do
        count = count + 1
        if p.finishedMs ~= nil or p.dnf then done = done + 1 end
    end
    if (count > 0 and done == count) or nowMs >= self:deadline() then
        self.state = "results"
    end
    return self.state
end

return RoundLogic
