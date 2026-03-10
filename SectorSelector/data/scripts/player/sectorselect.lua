package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"
include("utility")
include("callable")
local PassageMap = include("passagemap")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace SectorSelector
SectorSelector = {}

-- ─── Shared state ─────────────────────────────────────────────────────────────
local expandLeft  = 10
local expandRight = 10
local expandUp    = 10
local expandDown  = 10
local centerX     = 0
local centerY     = 0
local isSelecting = false

local HIGHLIGHT_KEY = "SectorSelector"

-- ─── Layout constants — mirror mapcommands.lua exactly ────────────────────────
local padding       = 10
local barOffset     = vec2(60, 60)
local portraitWidth = 120
local orderDiameter = 40
local orderPadding  = 10
local CUSTOM_SLOT   = 18

-- ─── Client UI handles ────────────────────────────────────────────────────────
local configWindow    = nil
local winCenterLabel  = nil
local winLeftLabel    = nil
local winRightLabel   = nil
local winUpLabel      = nil
local winDownLabel    = nil
local winFromLabel    = nil
local winToLabel      = nil
local winFactionBtn   = nil
local availableList   = nil
local assignedList    = nil

local selectedShips  = {}
local factionSectors = nil  -- non-nil = faction mode, use setHighlightedSectors

-- ─── Lifecycle ────────────────────────────────────────────────────────────────

function SectorSelector.initialize()
    if onClient() then
        local player = Player()
        player:registerCallback("onShowGalaxyMap",      "onShowGalaxyMap")
        player:registerCallback("onHideGalaxyMap",      "onHideGalaxyMap")
        player:registerCallback("onGalaxyMapUpdate",    "onGalaxyMapUpdate")
        player:registerCallback("onGalaxyMapMouseDown", "onGalaxyMapMouseDown")
        SectorSelector.initUI()
    end
end

function SectorSelector.initUI()
    local res = getResolution()

    local bx = res.x - portraitWidth - 3 * padding - barOffset.x
                     - orderDiameter - orderPadding
    local by = barOffset.y + CUSTOM_SLOT * (orderDiameter + orderPadding)

    local btnContainer = GalaxyMap():createContainer()

    local catchFrame = btnContainer:createFrame(
        Rect(vec2(bx, by), vec2(bx + orderDiameter, by + orderDiameter)))
    catchFrame.catchAllMouseInput = true
    catchFrame.layer = catchFrame.layer - 1

    local iconButton = btnContainer:createRoundButton(
        Rect(vec2(bx, by), vec2(bx + orderDiameter, by + orderDiameter)),
        "expedition-command.png", "onIconPressed")
    iconButton.tooltip = "Select Sector Area"

    local ww, wh = 290, 430
    configWindow = GalaxyMap():createWindow(Rect(vec2(ww, wh)))
    configWindow.caption             = "Area Selection"
    configWindow.showCloseButton     = true
    configWindow.closeableWithEscape = true
    configWindow.moveable            = true
    configWindow:center()
    configWindow:hide()

    local p = 10

    winCenterLabel = configWindow:createLabel(
        Rect(vec2(p, p), vec2(ww - p, p + 20)),
        "Center: --, --", 13)

    local lblW, btnW, valW = 52, 28, 44
    local function dirRow(y, caption, minusCb, plusCb)
        configWindow:createLabel(
            Rect(vec2(p, y), vec2(p + lblW, y + 22)), caption, 12)
        configWindow:createButton(
            Rect(vec2(p + lblW + 4, y), vec2(p + lblW + 4 + btnW, y + 22)),
            "−", minusCb)
        local lbl = configWindow:createLabel(
            Rect(vec2(p + lblW + 4 + btnW + 4, y),
                 vec2(p + lblW + 4 + btnW + 4 + valW, y + 22)),
            "10", 13)
        lbl.centered = true
        configWindow:createButton(
            Rect(vec2(p + lblW + 4 + btnW + 4 + valW + 4, y),
                 vec2(p + lblW + 4 + btnW + 4 + valW + 4 + btnW, y + 22)),
            "+", plusCb)
        return lbl
    end

    local wy = p + 28
    winLeftLabel  = dirRow(wy,      "Left:",  "onWinLeftMinus",  "onWinLeftPlus")
    winRightLabel = dirRow(wy + 28, "Right:", "onWinRightMinus", "onWinRightPlus")
    winUpLabel    = dirRow(wy + 56, "Up:",    "onWinUpMinus",    "onWinUpPlus")
    winDownLabel  = dirRow(wy + 84, "Down:",  "onWinDownMinus",  "onWinDownPlus")

    local infoY = wy + 116
    winFromLabel = configWindow:createLabel(
        Rect(vec2(p, infoY), vec2(ww / 2 - 4, infoY + 18)), "From: --, --", 11)
    winToLabel = configWindow:createLabel(
        Rect(vec2(ww / 2 + 4, infoY), vec2(ww - p, infoY + 18)), "To: --, --", 11)

    local factionY = infoY + 26
    winFactionBtn = configWindow:createButton(
        Rect(vec2(p, factionY), vec2(ww - p, factionY + 26)),
        "Snap to Faction Area", "onFactionAreaPressed")

    local btnY = factionY + 34
    configWindow:createButton(
        Rect(vec2(p, btnY), vec2(ww / 2 - 6, btnY + 30)),
        "Confirm", "onWinConfirm")
    configWindow:createButton(
        Rect(vec2(ww / 2 + 6, btnY), vec2(ww - p, btnY + 30)),
        "Cancel", "onWinCancel")

    local sectY = btnY + 42
    local half  = math.floor((ww - 3 * p) / 2)
    configWindow:createLabel(
        Rect(vec2(p, sectY), vec2(p + half, sectY + 16)), "Available", 11)
    configWindow:createLabel(
        Rect(vec2(p + half + p, sectY), vec2(ww - p, sectY + 16)), "Assigned", 11)

    local listY = sectY + 20
    local listH = wh - listY - p
    availableList = configWindow:createListBox(
        Rect(vec2(p, listY), vec2(p + half, listY + listH)))
    availableList.onSelectFunction = "onAvailableSelected"
    assignedList = configWindow:createListBox(
        Rect(vec2(p + half + p, listY), vec2(ww - p, listY + listH)))
    assignedList.onSelectFunction = "onAssignedSelected"
end

-- ─── Map callbacks ────────────────────────────────────────────────────────────

function SectorSelector.onShowGalaxyMap()
end

function SectorSelector.onHideGalaxyMap()
    if isSelecting then
        isSelecting = false
        GalaxyMap():removeHighlightedArea(HIGHLIGHT_KEY)
    end
    configWindow:hide()
end

function SectorSelector.onIconPressed()
    if isSelecting then
        isSelecting = false
        GalaxyMap():removeHighlightedArea(HIGHLIGHT_KEY)
    else
        isSelecting = true
        configWindow:hide()
    end
end

function SectorSelector.onGalaxyMapUpdate(timeStep)
    if not isSelecting then return end
    local map    = GalaxyMap()
    local mx, my = map:getHoveredCoordinates()
    map:setHighlightedArea(
        vec2(mx - expandLeft, my - expandUp),
        vec2(mx + expandRight + 1, my + expandDown + 1),
        ColorARGB(0.28, 0.0, 0.55, 1.0),
        HIGHLIGHT_KEY)
end

function SectorSelector.onGalaxyMapMouseDown(button, mx, my, cx, cy)
    if not isSelecting then return end
    if button == MouseButton.Left then
        isSelecting      = false
        centerX, centerY = cx, cy
        factionSectors   = nil
        winFactionBtn.caption = "Snap to Faction Area"
        SectorSelector.refreshHighlight()
        SectorSelector.refreshWindowLabels()
        SectorSelector.refreshShipLists()
        configWindow:show()
    elseif button == MouseButton.Right then
        isSelecting = false
        GalaxyMap():removeHighlightedArea(HIGHLIGHT_KEY)
    end
end

-- ─── Directional expand controls ─────────────────────────────────────────────

local function clearFactionMode()
    if factionSectors then
        factionSectors = nil
        winFactionBtn.caption = "Snap to Faction Area"
    end
end

function SectorSelector.onWinLeftMinus()
    clearFactionMode() ; expandLeft = math.max(0, expandLeft - 1)
    winLeftLabel.caption = tostring(expandLeft)
    SectorSelector.refreshHighlight() ; SectorSelector.refreshWindowLabels()
end
function SectorSelector.onWinLeftPlus()
    clearFactionMode() ; expandLeft = math.min(250, expandLeft + 1)
    winLeftLabel.caption = tostring(expandLeft)
    SectorSelector.refreshHighlight() ; SectorSelector.refreshWindowLabels()
end
function SectorSelector.onWinRightMinus()
    clearFactionMode() ; expandRight = math.max(0, expandRight - 1)
    winRightLabel.caption = tostring(expandRight)
    SectorSelector.refreshHighlight() ; SectorSelector.refreshWindowLabels()
end
function SectorSelector.onWinRightPlus()
    clearFactionMode() ; expandRight = math.min(250, expandRight + 1)
    winRightLabel.caption = tostring(expandRight)
    SectorSelector.refreshHighlight() ; SectorSelector.refreshWindowLabels()
end
function SectorSelector.onWinUpMinus()
    clearFactionMode() ; expandUp = math.max(0, expandUp - 1)
    winUpLabel.caption = tostring(expandUp)
    SectorSelector.refreshHighlight() ; SectorSelector.refreshWindowLabels()
end
function SectorSelector.onWinUpPlus()
    clearFactionMode() ; expandUp = math.min(250, expandUp + 1)
    winUpLabel.caption = tostring(expandUp)
    SectorSelector.refreshHighlight() ; SectorSelector.refreshWindowLabels()
end
function SectorSelector.onWinDownMinus()
    clearFactionMode() ; expandDown = math.max(0, expandDown - 1)
    winDownLabel.caption = tostring(expandDown)
    SectorSelector.refreshHighlight() ; SectorSelector.refreshWindowLabels()
end
function SectorSelector.onWinDownPlus()
    clearFactionMode() ; expandDown = math.min(250, expandDown + 1)
    winDownLabel.caption = tostring(expandDown)
    SectorSelector.refreshHighlight() ; SectorSelector.refreshWindowLabels()
end

-- ─── Faction area snap — entirely client-side ─────────────────────────────────
-- Uses the same SectorView data the galaxy map renders from, so it matches exactly.

function SectorSelector.onFactionAreaPressed()
    -- Look up the faction at the clicked sector from known sector data
    local sv = Player():getKnownSector(centerX, centerY)
    if not sv then
        winFactionBtn.caption = "Sector unknown"
        return
    end

    local fi = sv.factionIndex
    if not fi or fi == 0 then
        winFactionBtn.caption = "No faction here"
        return
    end

    -- getKnownSectorsOfFaction returns every explored sector whose local faction
    -- is this one — identical to what the galaxy map colors green/amber/etc.
    local views = {Player():getKnownSectorsOfFaction(fi)}
    if #views == 0 then
        winFactionBtn.caption = "No sectors found"
        return
    end

    local RADIUS = 3

    -- Build list of our faction's known coords
    local ourSeeds = {}
    for _, view in ipairs(views) do
        local x, y = view:getCoordinates()
        ourSeeds[#ourSeeds + 1] = {x = x, y = y}
    end

    -- Phase 1: diamond expansion from each known faction sector
    local seen    = {}
    local sectors = {}
    local minX, maxX = math.huge, -math.huge
    local minY, maxY = math.huge, -math.huge
    for _, seed in ipairs(ourSeeds) do
        for dx = -RADIUS, RADIUS do
            for dy = -RADIUS, RADIUS do
                if math.abs(dx) <= 2 and math.abs(dy) <= 2
                        and math.abs(dx) + math.abs(dy) <= RADIUS then
                    local x, y = seed.x + dx, seed.y + dy
                    local key   = x .. "," .. y
                    if not seen[key] then
                        seen[key] = true
                        sectors[#sectors + 1] = {x = x, y = y, color = "4800cc77"}
                        if x < minX then minX = x end
                        if x > maxX then maxX = x end
                        if y < minY then minY = y end
                        if y > maxY then maxY = y end
                    end
                end
            end
        end
    end

    -- Phase 1.5: close small gaps (≤ 3 unmarked sectors) between marked sectors
    -- on the same row or column, then update the bounding box for phase 2.
    local GAP = 3
    local byRow = {}
    local byCol = {}
    for _, s in ipairs(sectors) do
        if not byRow[s.y] then byRow[s.y] = {} end
        byRow[s.y][#byRow[s.y] + 1] = s.x
        if not byCol[s.x] then byCol[s.x] = {} end
        byCol[s.x][#byCol[s.x] + 1] = s.y
    end

    local function fillBetween(ax, ay, bx, by)
        for x = ax, bx do
            for y = ay, by do
                local key = x .. "," .. y
                if not seen[key] then
                    seen[key] = true
                    sectors[#sectors + 1] = {x = x, y = y, color = "4800cc77"}
                    if x < minX then minX = x end ; if x > maxX then maxX = x end
                    if y < minY then minY = y end ; if y > maxY then maxY = y end
                end
            end
        end
    end

    for y, xs in pairs(byRow) do
        table.sort(xs)
        for i = 1, #xs - 1 do
            if xs[i+1] - xs[i] - 1 <= GAP then
                fillBetween(xs[i] + 1, y, xs[i+1] - 1, y)
            end
        end
    end
    for x, ys in pairs(byCol) do
        table.sort(ys)
        for i = 1, #ys - 1 do
            if ys[i+1] - ys[i] - 1 <= GAP then
                fillBetween(x, ys[i] + 1, x, ys[i+1] - 1)
            end
        end
    end

    -- Phase 2: flood-fill from one cell outside the bounding box through unmarked
    -- sectors. Any unmarked cell that cannot be reached is enclosed → add to faction.
    local dirs    = {{-1,0},{1,0},{0,-1},{0,1}}
    local outside = {}
    local queue   = {}
    local x0, x1  = minX - 1, maxX + 1
    local y0, y1  = minY - 1, maxY + 1

    local function tryOutside(x, y)
        if x < x0 or x > x1 or y < y0 or y > y1 then return end
        local key = x .. "," .. y
        if seen[key] or outside[key] then return end
        outside[key] = true
        queue[#queue + 1] = {x = x, y = y}
    end

    -- seed the flood fill from the entire border of the padded bounding box
    for x = x0, x1 do tryOutside(x, y0) ; tryOutside(x, y1) end
    for y = y0 + 1, y1 - 1 do tryOutside(x0, y) ; tryOutside(x1, y) end

    local i = 1
    while i <= #queue do
        local cur = queue[i] ; i = i + 1
        for _, d in ipairs(dirs) do tryOutside(cur.x + d[1], cur.y + d[2]) end
    end

    -- Any interior cell that is neither marked nor reachable from outside is enclosed
    for x = x0 + 1, x1 - 1 do
        for y = y0 + 1, y1 - 1 do
            local key = x .. "," .. y
            if not seen[key] and not outside[key] then
                seen[key] = true
                sectors[#sectors + 1] = {x = x, y = y, color = "4800cc77"}
            end
        end
    end

    -- Remove void (impassable) sectors — ships cannot jump into these
    local pm     = PassageMap(Seed(GameSettings().seed))
    local result = {}
    for _, s in ipairs(sectors) do
        if pm:passable(s.x, s.y) then
            result[#result + 1] = s
        end
    end

    factionSectors = result
    winFactionBtn.caption = string.format("Faction (%d sectors)", #result)
    SectorSelector.refreshHighlight()
end

-- ─── Confirm / Cancel ─────────────────────────────────────────────────────────

function SectorSelector.onWinConfirm()
    configWindow:hide()
end

function SectorSelector.onWinCancel()
    GalaxyMap():removeHighlightedArea(HIGHLIGHT_KEY)
    configWindow:hide()
end

-- ─── Ship lists ───────────────────────────────────────────────────────────────

function SectorSelector.refreshShipLists()
    availableList:clear()
    assignedList:clear()
    local names = {Player():getShipNames()}
    table.sort(names)
    for _, name in ipairs(names) do
        if selectedShips[name] then
            assignedList:addEntry(name, name)
        else
            availableList:addEntry(name, name)
        end
    end
end

function SectorSelector.onAvailableSelected()
    local name = availableList.selectedValue
    if not name then return end
    selectedShips[name] = true
    SectorSelector.refreshShipLists()
end

function SectorSelector.onAssignedSelected()
    local name = assignedList.selectedValue
    if not name then return end
    selectedShips[name] = nil
    SectorSelector.refreshShipLists()
end

-- ─── Helpers ──────────────────────────────────────────────────────────────────

function SectorSelector.refreshHighlight()
    local map = GalaxyMap()
    if factionSectors then
        map:setHighlightedSectors(factionSectors, HIGHLIGHT_KEY)
    else
        local lx = centerX - expandLeft
        local ly = centerY - expandUp
        map:setHighlightedArea(
            vec2(lx, ly),
            vec2(lx + expandLeft + expandRight + 1, ly + expandUp + expandDown + 1),
            ColorARGB(0.30, 0.0, 0.88, 0.35),
            HIGHLIGHT_KEY)
    end
end

function SectorSelector.refreshWindowLabels()
    local lx = centerX - expandLeft
    local ly = centerY - expandUp
    winCenterLabel.caption = string.format("Center:  %d, %d", centerX, centerY)
    winFromLabel.caption   = string.format("From:  %d, %d", lx, ly)
    winToLabel.caption     = string.format("To:  %d, %d", centerX + expandRight, centerY + expandDown)
end
