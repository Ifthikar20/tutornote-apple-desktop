# Loading screen pictures

Pictures for the little computer's screen on the loading screen (`static/loading.html`).
Put the files here and list them in `.slides` in that page, in the order they should play:

```html
<figure class="slide"><img src="loading/first.png" alt="" /></figure>
```

The screen is 3:2 (120 x 80 on screen): make pictures 3:2, e.g. 480 x 320 or larger, to
look sharp on Retina. Any other shape is cropped to fill it. PNG, JPEG, GIF, WebP and SVG
all work; a transparent picture sits on the screen's glass; a file that fails to load is
skipped.

They start once "Welcome to AnotherNote" is written (3.8 s), each for about 2.2 s, then the
smiley comes back (`static/loading.js`). The app opens after every picture has played once,
or when it has finished loading if that is later, and never more than 10 s after launch
(`SPLASH_INTRO_MAX_MS` in `src/main/windows.ts`), so about four pictures fit. A click on
the computer, or Esc, Return or Space, skips the rest.
