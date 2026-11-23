# Sage Graphite — food tracker handoff

Paste this into Claude Code along with `Prototype.dc.html` (the working prototype, for reference) and `off-uk.json` (671 UK products from Open Food Facts).

## Goal
A personal iPhone food tracker: fast logging, Day and Week dashboards, and weight read from Apple Health. The prototype is a design reference: rebuild it as a real app rather than porting the file. `Prototype.dc.html` is in a canvas-specific format; read its markup for layout and its `<script>` block for the logic.

## Platform decision (pick one in Claude Code)
- **Native SwiftUI + HealthKit (recommended for real Apple Health weight).** Needs a Mac with Xcode.
- **Web app on Vercel + Supabase**, with an iOS Shortcut that posts the daily Health weight to an API route.

## Design system: "Sage Graphite"
- Font: Manrope (400–800). Large numbers 700–800 with tight letter-spacing.
- Colours: background `#F6F3EE`, cards `#FBF9F5` with a 1px `#E7E1D6` border, text `#1E2A23`, muted text `#5F6A63`, tracks and dividers `#E7E1D6`.
- Accent / protein: `#2F5D46`. Carbs: `#B9823A`. Fat: `#94658A`. Over budget: `#B9823A`.
- Card radius 22, page padding 16, gap 12. Touch targets at least 44 px.
- Fixed iOS tab bar (84 px, full width, hairline top border): Home · Day · [+ Log, green circle] · Week · Profile.

## Screens
- **Home:** greeting and date; Today card (a 128 px calorie ring showing kcal left, plus protein, carbs and fat bars); Weight card (latest reading from Apple Health, change over the range, line chart, 1M/3M toggle, Sync button, "All readings"); Last 7 days card (mini calorie bars plus days protein was hit).
- **Weight detail:** large chart, range toggle, list of readings with the day-to-day change.
- **Day:** previous/next day buttons; summary ring and macros; Breakfast/Lunch/Snack/Dinner cards, each with a + button. Tapping an entry lets you edit the amount or slot, or delete it.
- **Week:** Monday–Sunday with navigation; tiles for average kcal, average protein, days on calorie target, and the week's weight change; daily calorie bars against a dashed target line; average macro split; dots for days protein was hit.
- **Profile:** Apple Health connection toggle and permissions (read weight; write dietary energy, protein, carbs and fat); goal steppers (default 1,800 kcal, 150 g protein, 170 g carbs, 60 g fat).
- **Log sheet:** slot chips; one search box for meals, foods, brands and barcodes; Quick add (kcal and optional macros); Create a food (per 100 g or per serving); tabs for Your meals / Foods / UK products. The amount screen has a stepper, live macros and an "Afterwards: X kcal left · Y/150 g protein" line.

## Data model
- `Food { id, name, brand?, unit (g|ml|slice|egg|scoop|serving…), per, step, def, kcal, p, c, f, dry?, source (builtin|custom|off), barcode? }`
- `Meal { id, name, desc, parts: [foodId, amount][] }`, the saved "usuals".
- `Entry { id, date YYYY-MM-DD, slot, kind (food|meal|quick), ref, amount, time }`. A quick-add entry stores its own kcal and macros.
- `WeightReading { date, kg, time, source: AppleHealth }`.
- `Goals { kcal, p, c, f }`.

## Content rules
- Pasta, rice and oats are logged as **dry weight**, labelled "dry".
- Usual meals: whey shake; 4 poached eggs with 1 slice of sourdough; Greek yoghurt bowl (100 g yoghurt at 7 g protein per 100 g, 80 g berries, 15 g peanut butter); mince and pasta (250 g 5% mince, 80 g dry pasta, 120 g sauce); chicken and potatoes (200 g breast, 300 g potato); mince and rice (250 g mince, 75 g dry rice); eggs on toast.
- The user eats only beef, chicken and pork: no fish or seafood.

## Open Food Facts
- Product: `GET https://world.openfoodfacts.org/api/v2/product/{barcode}.json`. Search: `/api/v2/search?countries_tags_en=united-kingdom&...` (limit about 10 searches a minute, so cache results).
- Send a descriptive User-Agent. Credit Open Food Facts (ODbL) on each product.
- `off-uk.json` rows: `[barcode, name, brand, pack, kcal/100g, protein, carbs, fat, servingGrams]`.
- In the real app: barcode scanning with the camera (VisionKit `DataScannerViewController` natively, or a JS barcode library on the web), live lookup and a local cache. Logged products are saved locally so they keep working offline.
