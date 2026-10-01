# Brand assets

| File                            | Use                                                                                                     |
| ------------------------------- | ------------------------------------------------------------------------------------------------------- |
| `lbc-logo-full.png`             | Full gold logo with the church name. Login page, public site header and footer. Transparent background. |
| `lbc-mark.png`                  | Gold LBC mark only. Sidebar and small spaces. Transparent background.                                   |
| `favicon.ico`, `favicon-32.png` | Browser tab icon (navy background). Copy into each app's `app/` folder.                                 |
| `apple-touch-icon.png`          | iPhone home screen icon (180px).                                                                        |
| `icon-192.png`, `icon-512.png`  | Android and installable app icons (web manifest).                                                       |

Each app has copies in `src/app/` using the Next.js metadata file convention: `favicon.ico` (from `favicon.ico`), `icon.png` (from `icon-512.png`) and `apple-icon.png` (from `apple-touch-icon.png`). Recopy them there when these files change.

These were extracted from a JPEG of the logo. Replace them with exports from the original vector file (SVG, AI or PDF) when the church can provide it; the file names stay the same.
