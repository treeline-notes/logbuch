# Theme Directory

Dieses Verzeichnis enthält die CSS-Styles für das Logbuch.

## Dateien

- **`styles.css`**: Das Haupt-Stylesheet mit allen Theme-Definitionen
- **`preview.html`**: Live-Preview zum Testen der Styles im Browser

## Verwendung

### Styles bearbeiten

Bearbeite einfach `styles.css` in deinem Editor. Du hast:
- Syntax-Highlighting
- CSS-Linting
- Auto-Completion
- Alle IDE-Features

### Styles testen

Öffne `preview.html` im Browser, um deine Änderungen direkt zu sehen:

```bash
open theme/preview.html
```

Nach jeder Änderung an `styles.css` einfach den Browser neu laden (Cmd+R / F5).

### Build-Prozess

Das `build_encrypt.sh`-Script liest automatisch `styles.css` und injiziert es als inline `<style>`-Tag in die finale `index.html`.

```bash
./build_encrypt.sh
```

## CSS-Variablen

Das Theme nutzt CSS Custom Properties für einfache Anpassungen:

```css
:root {
  --bg: #0b0c10;           /* Hintergrundfarbe */
  --panel: rgba(255,255,255,0.06);  /* Panel-Hintergrund */
  --text: rgba(255,255,255,0.92);   /* Textfarbe */
  --link: #7dd3fc;          /* Link-Farbe */
  --maxw: 820px;            /* Maximale Breite */
  /* ... weitere Variablen */
}
```

Das Theme unterstützt automatisch Light/Dark Mode basierend auf System-Präferenzen.

## Tipps

- **Live-Anpassungen**: Öffne die Browser DevTools und ändere CSS-Variablen live
- **Responsive Testing**: Browser DevTools → Device Toolbar für Mobile-Ansicht
- **Print-Ansicht**: Browser → Druckvorschau zeigt die Print-Styles
