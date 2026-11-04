# Flip Calendar — תיעוד פרויקט

שומר מסך + טפט דינמי + אתר: שעון פליפ בסגנון Fliqlo ולוח שנה רוחבי בגרפיקה של Calendar 2027.

## קישורים
| מה | איפה |
|---|---|
| אתר חי | https://flip-calendar.vercel.app |
| עמוד הורדות | https://flip-calendar.vercel.app/downloads/ |
| שומר מסך (ZIP) | https://flip-calendar.vercel.app/downloads/FlipCalendar.saver.zip |
| טפט דינמי (ZIP) | https://flip-calendar.vercel.app/downloads/FlipCalendarWallpaper.zip |
| קוד (GitHub) | https://github.com/Urimazor/flip-calendar |
| Vercel | פרויקט flip-calendar (פריסה אוטומטית מכל push ל-main) |
| שיחת הפרויקט ב-Claude | https://claude.ai/code/project/chan_01VgeE2gFpp4P3NBtqaEgDpD |

## מבנה התיקייה ב-Dropbox
- `repo/` — עותק git של הקוד (מתעדכן ב-`git pull`)
- `builds/` — הקבצים המוכנים להתקנה (FlipCalendar.saver, Flip Calendar Wallpaper.app וה-ZIP-ים)
- `source-files/` — קבצי המקור המקוריים (Fliqlo.saver, Calendar_2027_450mm_v3.pdf) אם נשמרו
- `PROJECT.md` — הקובץ הזה

## מבנה הקוד
- `index.html` / `web/index.html` — הדף עצמו (קובץ אחד, הגופנים מוטמעים). אותו דף משמש את האתר, שומר המסך והטפט.
- `src/FlipCalendarView.swift`, `src/Info.plist`, `build.sh`, `Install.command` — שומר המסך (WKWebView בתוך ScreenSaverView).
- `wallpaper/main.swift`, `wallpaper/Info.plist`, `build-wallpaper.sh` — אפליקציית הטפט (חלון בשכבת שולחן העבודה בכל מסך, תפריט ◷).
- `downloads/` — הקבצים הבנויים ועמוד ההורדות באתר.

## התקנה
- שומר מסך: פותחים את ה-ZIP ← לחיצה כפולה על FlipCalendar.saver ← Install ← בוחרים בהגדרות המערכת ← Screen Saver.
- טפט: פותחים את ה-ZIP ← גוררים ל-Applications ← בפעם הראשונה לחיצה ימנית ← Open. הפעלה אוטומטית: System Settings ← General ← Login Items.
- בפעם הראשונה macOS עשוי לחסום (לא מה-App Store): System Settings ← Privacy & Security ← Open Anyway.

## תפריט הטפט (◷)
- Size — גודל כללי 40–100% (השוליים שחורים)
- Show on This Desktop (⌘D) / Show on All Desktops — הפעלה לפי שולחן עבודה (Spaces)
- Reload / Quit

## בדפדפן
מקשים: 1/2/3 תצוגה, T 12/24, S שניות, ← → שנה, Home היום, D כיוון, H חגים, F מסך מלא. פרמטרים: `?year=2027`, `?mode=clock|cal|both`, `?h12`, `?seconds=1`, `?scale=0.8`.

## החלטות עיצוב
- צבעי הפוסטר: שחור, אוף-וויט #E8E2E0, אדום #E43321 לימי ראשון, קווים דקים.
- לוח רוחבי: חודשים בשורות (J–D), ימים מימין לשמאל מיושרים לשורת ימי השבוע (37 עמודות).
- ספרות השעון באפור (#8C8887), לא בלבן.
- השנה, התאריך, התאריך העברי, שורת השבוע והפס — ברוחב השנה, בפינה הימנית העליונה.
- השנה מתעדכנת אוטומטית לשנה הנוכחית.
- הגופן של Fliqlo לא הועתק; הסגנון נבנה מחדש (Inter Display מוטמע).

## בעיות שנפתרו
- מסך שחור אחרי 2–5 שניות (macOS 26): WebKit הקפיא את הדף כי חלון שומר המסך מדווח "מוסתר". נפתר בכיבוי זיהוי ההסתרה וההאטה של WebKit.
- הרשאות הרצה שאבדו ב-ZIP: Install.command מריץ את build.sh דרך bash.
- ריחוף בטפט: חלון שקוף של ה-Dock נחשב ככיסוי; מדלגים עליו.

## יומן שינויים
- 2026-11-04 — גרסה ראשונה: שעון פליפ + לוח רוחבי, תאריך עברי, חגים, ריחוף.
- 2026-11-04 — שעון גדול, שנה קטנה, תאריך ופס התקדמות ברוחב השנה.
- 2026-11-04 — תיקון מסך שחור בשומר המסך; התקנה ב-Mac במשרד.
- 2026-11-04 — ספרות שעון באפור; שורת השבוע מתחת לתאריך; טפט דינמי; GitHub + Vercel.
- 2026-11-04 — עמוד הורדות עם קבצים בנויים.
- 2026-11-04 — הגדרת גודל בטפט.
- 2026-11-04 — הפעלה/כיבוי לפי שולחן עבודה.
- 2026-11-04 — ריחוף על תאריך בטפט מציג תאריך עברי וחג.
- 2026-11-04 — תיעוד וגיבוי ב-Dropbox.
