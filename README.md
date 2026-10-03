# voltIQ for iOS

A native SwiftUI port of [voltIQ](https://github.com/PrahasM/voltIQ), for iPhone and iPad running **iOS 16 or later**. Calculations, profiles, operators, history and receipt processing run on-device. No server, web view, package dependencies or login.

## Run

1. Open `VoltIQ.xcodeproj` in **Xcode 15 or later**.
2. Choose the **VoltIQ** scheme and an iPhone / iPad simulator, then Run.
3. For a physical device, select your Apple development team in Signing & Capabilities and use a unique bundle identifier if necessary. Simulator builds need no signing team.

```sh
xcodebuild -project VoltIQ.xcodeproj -scheme VoltIQ \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

xcodebuild -project VoltIQ.xcodeproj -scheme VoltIQ \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test

swift test # Foundation-only engine, log/schema and persistence tests on macOS
git diff --check # whitespace lint; Xcode build typechecks all SwiftUI sources
```

Use `xcrun simctl list devices available` to substitute an installed simulator name. CI builds the app and runs both the portable core tests and the app-hosted Simulator tests.

## App

- **Calculator:** target %, ₹ budget or time; current-charge steppers; 80/85/90/100/custom targets; ₹5–₹40 rate slider in ₹0.50 steps; AC/DC presets and custom power/type; car power limits; DC taper above 80%; copyable rounded-up charger kWh; phase timing and collapsible GST cost breakdown.
- **Settings:** per-driver efficiencies (DC 92%, AC 87%), max AC/DC power (11/150 kW), DC taper (40%), operator CRUD with GST and session/idle fees, learned efficiencies and a system/light/dark appearance override.
- **History:** editable receipt values in a prefilled or blank charge form, optional receipt photo from Photos, totals, deletion, CSV export, and an opt-in learning prompt after 3 eligible charges of a type.
- **Chargers:** finds nearby EV charging stations (5 km, up to 20; defaults in `ChargerDiscoveryConfig`) on a map and list using when-in-use location. With a Google Places API key, selecting a station shows its connector groups (type, max kW, count, and live availability where Google provides it). **Charge Here** preselects the fastest available connector that fits your car (set "My car's connector" in Settings), estimates time and cost to your target, and shows the driving route from your location inside the app (MapKit) and offers Open provider app when a URL is known. Provider, price and fees show as unavailable until a provider supplies them; voltIQ never starts a session or payment. Without a key it falls back to Apple MapKit and shows "Connector details unavailable". This is the only feature that uses the network: the search location is sent to Google (or Apple); everything else stays on-device.
- **Who's charging?:** normalized local driver names with independent preferences, operators and logs. Deleting a driver removes their receipts too. Names are a convenience on a shared device, not authenticated accounts.

### Calculation parity

The engine follows the web `script.js`:

```
energy_added = capacity × (end% − start%) / 100
energy_bought = energy_added / efficiency
effective_power = min(charger_kW, car_limit_for_type)
DC_power_above_80 = effective_power × taper_fraction
phase_time = phase_energy_bought / phase_power
```

GST ON means the rate is inclusive: total = bought × rate, base = total / 1.18. GST OFF with an operator means +18%; OFF with manual rate means no GST. Budget mode divides by the gross rate. Time mode integrates the same taper phases. Reverse modes cap energy, cost and time at 100%. `Enter kWh` uses the web rounding rule `ceil(round(bought × 1000) / 1000)`; the headline is shown in every mode, with final % also shown for reverse modes.

Session and idle fees are shown separately from the energy estimate. Logged `cost` is the energy amount paid before these separate fees. Effective rate is `(paid + session + idle_fee × idle_minutes) / billed_kWh`, matching the web. History average is total spent / battery energy added, also matching the web. Learning is the arithmetic mean of at least three real efficiencies in 50–100% for each charger type; declining the prompt keeps manual values, and Settings lets you opt in later.

### Local data

`UserDefaults["voltiq-state-v1"]` holds a versioned Codable JSON envelope: selected driver UUID and profiles containing preferences, car settings, operators and logs. This replaces the web `voltiq-*` localStorage keys. Unlike the web's device-global car settings, the native app keeps **all settings per driver**. Each driver keeps the latest 500 logs sorted by charge date; old receipts are pruned with their entries. Data survives app restarts; uninstalling the app removes it. The web's browser storage is not automatically imported.

Charge entries retain the compact web keys: `t,e,c,r,g,k,b,s,f,y,o,oi,d,m,fe,x,q,p`. `t` is Unix milliseconds; `g` is 1 inclusive / 2 added / 0 none; `p=1` means a local receipt exists. Optional fields are omitted when absent. Legacy entries containing only `t,e,c,r,g,k` decode and export; an empty-string `k` decodes as missing power. Operators use `id,n,r,g,s,f` and a numeric `g` flag.

Receipts are compressed to a maximum 1280px edge and stored as JPEG files in Application Support, scoped by driver UUID and timestamp, with iOS complete file protection. Photo bytes never go into UserDefaults. A failed receipt write prevents saving the charge so it can be retried. Photos already on-device work offline; an iCloud-only photo must be downloaded through Photos first. CSV export uses the standard Files exporter and the same 16 columns as the web. There is no built-in sync or network request; destinations chosen in Files are controlled by iOS.

### Google Places key

Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` (gitignored) and set `GOOGLE_PLACES_API_KEY`. Restrict the key to this app's bundle ID in Google Cloud and set a quota/budget alert, since Nearby Search with EV charging fields is a higher billing tier. The key is passed in the `X-Goog-Api-Key` header and is exposed to the app through `Info.plist`, so treat it as restrictable, not secret.

### Design & maintenance

SwiftUI uses system SF Pro, SF Symbols, monospaced numeric outputs, ≥48pt custom control targets, 24pt cards and soft shadows. Light/dark accents and backgrounds match the web hex colors. The opaque 1024px app icon reproduces the `favicon.svg` bolt on a green gradient; iOS applies its own corner mask.

Core code is in `VoltIQ/Core`; views are in `VoltIQ/Views`; `AppStore` coordinates persisted profile changes. The Xcode project and shared scheme are checked in. After adding/removing source files, regenerate them using `python3 tools/generate_project.py` (no third-party modules). To regenerate artwork, install Pillow and run `python3 tools/generate_icon.py`. The app itself has no external dependencies.
