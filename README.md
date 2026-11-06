# AdmiRank site

Every page has its own HTML, CSS and JS:

| Page | HTML | CSS | JS |
|---|---|---|---|
| Landing | index.html | css/home.css | js/home.js |

Shared by all pages: css/common.css (colors, header, buttons, footer) and js/common.js (theme, language, menu).

## Add a page
1. Copy `_template.html` to e.g. `login.html`.
2. Create `css/login.css` and `js/login.js`; replace PAGENAME in the copy.
3. Put page content inside <main>. Add Bangla text with `AR.add({key:'বাংলা'})` in the page JS.

With `vercel.json`, `/login` opens `login.html` automatically.
