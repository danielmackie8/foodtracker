# Sage — food tracker for iPhone

A personal, native iPhone food tracker built in SwiftUI. You log food quickly, see Day and Week dashboards, and your weight is read from Apple Health. The "Sage Graphite" design is in `docs/HANDOFF.md`, and the original prototype is in `docs/Prototype.dc.html`.

**Requirements:** a Mac with **Xcode 16 or later**, and an iPhone on **iOS 17 or later**.

## Run it on your iPhone

1. Clone the repo on your Mac and open **`Sage.xcodeproj`**.
2. Select the **Sage** target, then open **Signing & Capabilities**:
   - **Team:** pick your Apple ID. If it isn't listed, add it in Xcode › Settings › Accounts.
   - **Bundle Identifier:** if Xcode says `com.sagegraphite.foodtracker` is taken, change it to something unique, such as `com.<yourname>.sage`.
   - **HealthKit** should already be listed, because it comes from `Sage.entitlements`.
3. Plug in your iPhone (or pair it over Wi‑Fi), select it as the run destination, and press **⌘R**.
   - The first time, iOS asks you to trust the developer. On the iPhone, go to Settings › General › VPN & Device Management and trust your Apple ID.
   - Also turn on **Developer Mode** (Settings › Privacy & Security › Developer Mode) if iOS asks for it.
4. In the app, open **Profile** and switch on **Apple Health**. In the system sheet that appears, allow *Weight* (read) and *Dietary Energy, Protein, Carbohydrates, Total Fat* (write).

> With a free Apple ID, apps you install yourself expire after 7 days, and you re-run them from Xcode to renew. A paid Apple Developer account ($99/yr) extends this to a year, and you can install through TestFlight.

The Simulator also works, including HealthKit: add a weight in the Simulator's Health app. The camera scanner needs a real device, but you can type the barcode number instead.

## What's in it

| Screen | What it does |
|---|---|
| **Home** | Greeting, Today card (calorie ring and protein/carbs/fat bars), Weight card (latest reading, change over the range, chart, 1M/3M, Sync, All readings), Last 7 days card (bars and days protein was hit). |
| **Weight** | Large chart, range toggle, every reading with its day‑to‑day change. |
| **Day** | Previous/next day (or swipe), summary ring, Breakfast/Lunch/Snack/Dinner cards with a **+** on each. Tap an entry to change its amount or slot, or to delete it. |
| **Week** | Monday–Sunday navigation, tiles (average kcal, average protein, days on target, weight change), daily bars against a dashed target line, average macro split, and dots for days protein was hit. |
| **Profile** | Apple Health switch, with read/write toggles and goal steppers (default 1,800 kcal · 150 g P · 170 g C · 60 g F). |
| **Log sheet** (centre **+**) | Slot chips; one search box for meals, foods, brands and barcodes; barcode scanner; Quick add; Create a food (per 100 g or per serving); tabs for Your meals / Foods / UK products. The amount screen has a stepper (you can also tap the number to type it), live macros, and an "Afterwards: X kcal left · Y/150 g protein" line. |

Content rules from the handoff are built in. Pasta, rice and oats are logged as **dry** weight. Your usual meals are pre-loaded. There is no fish or seafood.

## Log food with Claude

For meals the app has no data for (restaurants, takeaways, home cooking), you can ask Claude for an estimate and add it in two taps. It uses your normal Claude app, so there's nothing extra to pay.

1. In Sage, go to **Profile › Log with Claude › Copy instructions**.
2. In the Claude app, create a project (for example "Sage") and paste the copied text as its instructions.
3. In that project, tell Claude what you ate, for example *"Wagamama chicken katsu curry for dinner"*.
4. Claude replies with a short breakdown and a JSON code block. Tap **Copy** on the code block, then in Sage open the log sheet and tap **From Claude**.
5. Check the numbers (tap an item to adjust them), then tap **Add**.

The Claude app doesn't open links to other apps, so the copied code block is how food gets into Sage. Sage also understands `sage://log?...` links (one `item=name;kcal;protein;carbs;fat;amount` per food) if you open one from Safari or Notes.

## Cloud backup and export

Sage keeps its working copy on the phone and backs everything up to Supabase. The database lives in the "Christmas Tracker" project, in tables named `sage_foods`, `sage_meals` and `sage_entries`.

- **Sign in:** Profile › Cloud backup › Sign in with Apple. Your existing log uploads straight away.
- **Sync:** happens automatically when the app opens, a couple of seconds after any change, and every minute while it's open. Anything added on the server (for example by Claude through the Supabase connector) appears within a minute.
- **Privacy:** row level security means a signed-in user can only read or change their own rows.
- **What isn't synced:** weight comes from Apple Health and isn't synced. Goals and settings stay on the phone.
- **Export:** Profile › Export my data creates `Food log.csv`, `Daily totals.csv`, `Foods.csv`, `Meals.csv`, `Weight.csv` and a full JSON backup, then opens the share sheet. You can also download any table as CSV from the Supabase dashboard.

One-time setup: in the Supabase dashboard for the project, go to **Authentication › Sign In / Providers › Apple**, enable it, and add the app's bundle identifier under **Client IDs**.

## How it works

```
Sage/
├── SageApp.swift              App entry, SwiftData container, seeds built-in foods & meals
├── AppState.swift             Tab/day/week navigation, goals & Health settings (UserDefaults), toasts,
│                              EntryActions (add/update/delete + mirror to Apple Health)
├── Model/
│   ├── Models.swift           SwiftData: Food, Meal, Entry, WeightReading; Goals
│   ├── Nutrition.swift        Macros, Catalog (entry → nutrition), Ledger (per-day totals), DayKey dates
│   └── SeedData.swift         Built-in foods and usual meals
├── Services/
│   ├── HealthKitManager.swift Reads body mass; writes energy/protein/carbs/fat per entry
│   ├── ProductDatabase.swift  Bundled UK product database (SQLite), offline search + barcode lookup
│   └── OpenFoodFacts.swift    Live barcode + search API for anything newer, disk cache
├── Theme/Theme.swift          Sage Graphite colours, Manrope fonts, card/button styles
├── Views/                     Home, Weight, Day, Week, Profile, Log sheet, shared components
└── Resources/                 products.sqlite.zlib (UK products), Manrope (OFL)
scripts/update_products.py     Rebuilds the product database from the Open Food Facts export
```

- **Storage:** everything is kept on the device with SwiftData. Nothing goes to a server.
- **Apple Health, weight:** the app syncs automatically when it opens (at most every 15 minutes), and whenever you tap **Sync**. It reads the last year of body-mass samples. A reading you delete in Health also disappears from the app.
- **Apple Health, nutrition:** each entry is written as four samples (energy, protein, carbs and fat) that share a sync identifier based on the entry's ID. When you edit an entry, its samples are replaced. When you delete it, they're removed. You can turn this off in Profile.
- **Open Food Facts:**
  - Every UK product in Open Food Facts with complete nutrition ships inside the app as a compressed SQLite database. It's unpacked on first launch and searched offline as you type. Words can come in any order, and matching ignores case and accents. The most-scanned products come first.
  - A scanned barcode is looked up in the bundled database first, then the disk cache, then live through `GET /api/v2/product/{code}.json`.
  - For products added after the database was built, pressing *Search* (or tapping "Search Open Food Facts online") queries the live API. A client-side limit keeps this under 10 searches a minute, and results are cached.
  - A product you log is saved as a Food, so it keeps working even if the database changes.
  - Every product shows its barcode and an ODbL credit.
  - The User-Agent is `SageFoodTracker/1.0`. If you'd like Open Food Facts to be able to contact you, add an email address to it in `OpenFoodFacts.swift`.
- **Refreshing the products:** run `python3 scripts/update_products.py` from the repo root. It streams the latest Open Food Facts export (about 1.5 GB) and rebuilds `Sage/Resources/products.sqlite.zlib`. Products are kept if they're sold in the UK and have a barcode, a name and complete per-100 g calories, protein, carbs and fat. Rows whose calories don't roughly match their macros are dropped. The original 671-product list in `scripts/off-uk.json` is always merged in.
- **Barcode scanning:** uses VisionKit `DataScannerViewController` and reads EAN-13, EAN-8, UPC-E, Code 128 and ITF-14.

## Notes

- `Sage.xcodeproj` uses Xcode 16's folder-synced groups, so any file you add under `Sage/` is picked up automatically. If you're on an older Xcode, regenerate the project with [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen && xcodegen`.
- Light and dark mode: choose System, Light or Dark in Profile › Appearance.
- Built-in foods are defined in `SeedData.swift`. New built-ins are added on the next launch, and existing data is never overwritten.
- Fonts: Manrope © The Manrope Project Authors, under the SIL Open Font License (`Sage/Resources/Fonts/OFL.txt`).
- Product data: © Open Food Facts contributors, under the [ODbL](https://opendatacommons.org/licenses/odbl/1-0/).
