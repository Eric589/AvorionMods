# Auto Mining Mod for Avorion

A comprehensive auto-mining system that intelligently assigns fighters to asteroids based on resource density and distance.

## Features

- **Individual Fighter Control**: Each fighter is assigned separately to optimize mining efficiency
- **Smart Resource Allocation**: Automatically calculates fighter requirements (1 fighter per 1000 resources, minimum 1)
- **Distance Prioritization**: Targets nearest asteroids first to minimize travel time
- **Real-time UI**: Monitor and control mining operations with an intuitive interface
- **Automatic Cargo Management**: Stops when cargo is full or no asteroids remain
- **Configurable Settings**: Adjust resources per fighter and maximum range

## Installation

1. **Copy Files to Avorion Mods Directory**:
   ```
   <Avorion>/data/scripts/commands/autominer.lua
   <Avorion>/data/scripts/entity/autominingcontroller.lua
   <Avorion>/data/scripts/player/init.lua
   ```

2. **File Structure**:
   ```
   Avorion/
   └── data/
       └── scripts/
           ├── commands/
           │   └── autominer.lua
           ├── entity/
           │   └── autominingcontroller.lua
           └── player/
               └── init.lua
   ```

## Usage

### Quick Start

1. **Board your mining ship** with deployed fighters
2. **Open the Auto Miner UI**:
   - Press `TAB` to open the System menu
   - Look for the "Auto Mining Controller" button (pick icon)
   - Click to open the interface

3. **Enable Mining**:
   - Click "Enable Auto Mining" button
   - Alternatively, use command: `/autominer on`

4. **Watch it work**:
   - Fighters will automatically target nearby asteroids
   - The UI shows real-time statistics
   - Mining stops automatically when cargo is full

### Commands

```
/autominer on       - Activates auto-mining
/autominer off      - Deactivates auto-mining
/autominer status   - Shows current status
```

### UI Controls

The Auto Mining Controller UI provides:

- **Status Display**: Shows if system is active/inactive
- **Live Statistics**:
  - Number of assigned fighters
  - Number of targeted asteroids
  - Current cargo capacity percentage
- **Configuration**:
  - Resources per Fighter: Adjust how many resources trigger assignment of one fighter
  - Max Range (km): Set maximum distance to consider asteroids

### How It Works

1. **Asteroid Scanning**: System scans for asteroids within range
2. **Distance Sorting**: Asteroids are sorted by proximity (nearest first)
3. **Resource Analysis**: Each asteroid's resource count is evaluated
4. **Fighter Assignment**: 
   - Calculates: `fighters_needed = max(1, resources / resources_per_fighter)`
   - Assigns available fighters up to the calculated amount
   - Each fighter targets a different asteroid when possible
5. **Continuous Operation**: 
   - Reassigns fighters when asteroids are depleted
   - Stops when cargo is full or no asteroids remain

## Configuration

### Default Settings

- **Update Interval**: 3 seconds (checks for new assignments)
- **Resources per Fighter**: 1000 (adjustable via UI)
- **Max Range**: 50 km (adjustable via UI)
- **Min Resource Threshold**: 50 (asteroids with less are ignored)

### Adjusting Settings

1. Open the Auto Mining Controller UI
2. Modify values in the Settings section:
   - **Resources per Fighter**: Higher = fewer fighters per asteroid
   - **Max Range**: Limits how far the system looks for asteroids

## Tips for Best Results

1. **Fighter Count**: Deploy 5-10 fighters for optimal efficiency
2. **Ship Position**: Stay relatively centered in asteroid fields
3. **Cargo Space**: Ensure adequate cargo capacity before starting
4. **Fighter Equipment**: Use fighters with mining lasers for best results
5. **Dense Fields**: System works best in resource-rich sectors

## Troubleshooting

### Fighters Not Mining

- **Check**: Are fighters deployed? (press `H` to deploy)
- **Check**: Do fighters have mining equipment?
- **Check**: Is the system enabled? (check UI status)

### No Asteroids Found

- **Check**: Max range setting - increase if needed
- **Check**: Are there asteroids with resources nearby?
- **Solution**: Move to a sector with more asteroids

### Command Not Working

- **Check**: Are you in a ship? (not a station)
- **Check**: Does your ship have the controller script?
- **Solution**: Use `/autominer on` to add it

### UI Not Appearing

- **Check**: Are you the pilot of the ship?
- **Solution**: Make sure you're in the pilot seat
- **Fallback**: Use `/autominer on` command instead

## Performance Notes

- System updates every 3 seconds to balance efficiency and responsiveness
- Fighter assignments are cached to reduce computational overhead
- Only nearby asteroids (within max range) are considered
- Minimal impact on game performance

## Compatibility

- **Avorion Version**: 2.0+
- **Multiplayer**: Compatible (server-side logic)
- **Other Mods**: Should be compatible with most mods
- **Vanilla Fighters**: Works with all fighter types

## Known Limitations

- Fighters must be pre-deployed (system doesn't launch them automatically)
- System prioritizes distance over resource density
- No pathfinding around obstacles (fighters use direct routes)

## Future Enhancements (Possible)

- Auto-deploy fighters when needed
- Avoid depleted asteroids
- Formation flying options
- Return-to-ship when damaged
- Integration with refinery systems

## Credits

Based on Avorion's vanilla harvesting AI and inspired by the community's need for better automated mining solutions.

## License

Free to use and modify. Attribution appreciated.

## Support

For issues or suggestions, please provide:
- Avorion version
- Mod version
- Steps to reproduce issue
- Any error messages from console

---

**Happy Mining!**
