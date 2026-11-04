# Flip Calendar – שומר מסך

שעון פליפ בסגנון Fliqlo + לוח השנה בגרפיקה של Calendar 2027, בפריסה רוחבית.

## התקנה ב-Mac
1. פתחו את התיקייה ולחצו לחיצה ימנית על Install.command ← Open (בפעם הראשונה macOS שואל אם לפתוח; אשרו).
2. אם מופיעה בקשה להתקין "Command Line Developer Tools": לחצו Install, חכו לסיום והפעילו שוב את Install.command.
3. ייפתח חלון "Install Flip Calendar?" ← Install.
4. הגדרות המערכת ← Screen Saver ← בחרו Flip Calendar.

## טפט דינמי (שעון ולוח חיים על שולחן העבודה)
בטרמינל, מתוך התיקייה: `bash build-wallpaper.sh`. האפליקציה נכנסת ל-~/Applications ורצה מאחורי כל החלונות.
יציאה: האייקון ◷ בשורת התפריטים. הפעלה אוטומטית: System Settings ← General ← Login Items ← + ← Flip Calendar Wallpaper.

## חלופה בלי בנייה
`brew install --cask webviewscreensaver` → בהגדרות שומר המסך בחרו WebViewScreenSaver → Options →
הוסיפו כתובת: `file:///Users/<שם המשתמש>/…/FlipCalendar/web/index.html`

## בדפדפן (אינטראקטיבי)
פתחו את `web/index.html`. מקשים: 1/2/3 תצוגה (משולב / שעון / לוח), T 12/24, S שניות,
← → מעבר שנה, Home חזרה להיום, D כיוון ימין-שמאל, H סימון חגים, F מסך מלא. ריחוף על יום מציג תאריך עברי וחג.

## פרמטרים בכתובת
`?year=2027` שנה קבועה · `?mode=clock|cal|both` · `?h12` · `?seconds=1`
