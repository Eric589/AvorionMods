# AutoTrader Mod - TODO

## Phase 1: Scout Drones (Data Collection)
- [ ] Drone script that jumps to sector, scans all stations for goods/prices/stock
- [ ] Serialize trade data to string, write to `Server():setValue("tradescan_x_y", data)`
- [ ] Drone self-destructs after scan
- [ ] Controller dispatches drones to sectors within jump range (reuse FastExploration circle pattern)

## Phase 2: Route Calculation
- [ ] Controller reads all `tradescan_*` values after drones finish
- [ ] Parse serialized data back into tables
- [ ] For each good: find cheapest buy sector and highest sell sector
- [ ] Calculate profit = (sellPrice - buyPrice) * min(buyStock, sellCapacity, cargoSpace)
- [ ] Sort routes by profit, pick best

## Phase 3: Trade Execution
- [ ] Ship jumps to buy sector, docks, buys goods
- [ ] Ship jumps to sell sector, docks, sells goods
- [ ] Repeat with next best route or rescan

## Phase 4: UI
- [ ] HUD button + window (scan button, route list, start/stop trading)
- [ ] Display top routes with profit, good name, from/to sectors

## Notes
- `TradingUtility.getBuyableAndSellableGoods()` is the core scan function
- Merchant scripts: factory, consumer, seller, tradingpost, planetarytradingpost, casino, habitat, biotope
- `Server():setValue()` for cross-sector drone->controller communication
- Serialize format: "goodName:stock:maxStock:buyPrice:sellPrice:stationName;..."
