# 🗺️ SheolHelper (v2.0) 

**Tired of looking at BG-Wiki spreadsheets on your second monitor while an Agon Beastman is actively chewing on your face?** Welcome to **SheolHelper**. This is a Windower 4 addon designed to make your Final Fantasy XI Odyssey segment runs infinitely less smooth-brain. It tracks your segments, auto-updates your maps, and dynamically displays the exact physical, magical, and Cruel Joke weaknesses of whatever you're targeting.

No more guessing. No more alt-tabbing. Just pure, unadulterated segment farming. 💰

---

## ✨ Dank Features

* 🧠 **Big Brain Resistance Tracker:** Target a mob and instantly see its elemental weaknesses, physical vulnerabilities (Slashing/Piercing/Blunt), and whether it's susceptible to **Cruel Joke**. Dynamically adjusts based on whether you are in Sheol A, B, or C. 
* 🗺️ **Auto-Updating GPS:** Reads incoming packets to automatically detect which zone and floor you are on. The on-screen map updates the second you touch a Conflux or Translocator.
* 🧮 **Segment Counter:** Automatically counts your hard-earned segments. It's built with packet-loss protection, so even if the server lags, your segment count catches up the moment you drop the next mob.
* 🕹️ **Fully Customizable UI:** Drag the UI boxes anywhere on your screen, adjust the background opacity, scale the maps, and toggle features on or off on the fly.
* 🛡️ **Manual Overrides:** Game acting weird? You can manually force the addon into Sheol A, B, or C mode with a simple command.

---

## 🛠️ Installation

1. Download the `sheolhelper` folder.
2. Drop it into your Windower 4 addons folder: `Windower4\addons\sheolhelper`
3. Load it up in game: `//lua load sheolhelper`
   * *(Pro-tip: Add `lua load sheolhelper` to your `init.txt` so you don't forget it!)*
4. Ensure you load the addon **before** entering the Odyssey instance (Rabao is the safest place) so it can catch the entry packets.

---

## 🎮 Commands

Use `//sheolhelper`, `//sheol`, or just `//shh` to interact with the addon.

### ⚙️ Core Toggles
* `//shh zone [a/b/c]` - Manually forces the addon into Sheol A, B, or C. (Must be inside Odyssey to use).
* `//shh toggle segments` - Shows or hides the Segment Tracker.
* `//shh toggle resistances` - Shows or hides the Target Resistance box.
* `//shh toggle joke` - Shows or hides the Cruel Joke susceptibility indicator.
* `//shh conserve` - Toggles whether your final segment count stays on screen when you zone back to Rabao to flex on your LS.

### 🗺️ Map Controls
* `//shh map` - Toggles the floor map on/off.
* `//shh map center` - Snaps the map directly to the center of your screen.
* `//shh map size [size]` - Adjusts the map size (e.g., `//shh map size 400`).
* `//shh map floor [floor]` - Manually forces the map to display a specific floor (1-7).

### 🎨 UI & Aesthetics
* `//shh bg all [0-255]` - Sets the background transparency for all UI elements (0 is invisible, 255 is solid black).
* `//shh bg segments [0-255]` - Sets the background transparency for just the Segment Tracker.
* `//shh bg resistances [0-255]` - Sets the background transparency for just the Resistance box.

---

## ⚠️ Important Disclaimers

* **Lag Happens:** Segments might get "lost" to severe packet lag, but the counter is designed to catch up if you keep killing mobs. If you lag out on the very last mob of the run, it might not register. Use the tracker as a highly accurate orientation, not a legal contract.
* **The "Unknowns":** FFXI doesn't explicitly broadcast weaknesses. The resistances table is compiled from extensive community testing (shoutout to the spreadsheet warriors). 
* **Standby Mode:** If you type commands outside of Odyssey (or Rabao), the addon will go into "Standby" mode to prevent UI clutter while you're doing other content.

---

## 📜 Credits & License

* Originally created by **Marian Arlt (Deridjian)**. 
* Heavily updated, debugged, and mathematically corrected for maximum dankness and crash-prevention.
* Released under the BSD 3-Clause License. See `LICENSE` for details. 

*Now get in there and cap those segments, gamer.* ⚔️