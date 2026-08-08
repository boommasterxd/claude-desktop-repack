// Give the Quick Entry BrowserWindow its own Wayland app_id (X11 WM_CLASS) so
// GNOME shell-extension users can blacklist just the Quick Entry pill without
// disabling effects on the main chat window.
//
// Chromium's Ozone-Wayland backend derives the app_id from $CHROME_DESKTOP
// (basename minus ".desktop") and re-reads it at every new BrowserWindow. So we
// swap CHROME_DESKTOP to "claude-quick-entry.desktop" right before the Quick
// Entry window is constructed, and reset it back on the window's ready-to-show
// (which guarantees Chromium already sent xdg_toplevel.set_app_id).
//
// The reset target must match the app's own real default app id (package.json's
// `desktopName`, which is also what its shipped .desktop file's StartupWMClass
// says) or every window opened after the first Quick Entry use gets the wrong
// WM_CLASS until restart - breaking taskbar/dock grouping and any per-app
// window-manager rule (including the very GNOME exclusion rules this patch
// exists for). That name is not a stable literal across releases (Claude
// Desktop 1.19367.0 renamed it from "claude" to "com.anthropic.Claude"), so it
// is read from the app's own package.json at runtime instead of hardcoded; the
// old literal is kept only as a last-resort fallback if that read ever fails.
//
// Ported from patches/fix_quick_entry_app_id.nim of the claude-desktop-bin project.

export const name = "quick-entry-app-id";
export const description =
  "gives the Quick Entry window its own WM_CLASS (`claude-quick-entry`) so GNOME corner/shadow extensions can exclude just it";

const QE_APP_ID = "claude-quick-entry";
const MAIN_APP_ID_FALLBACK = "com.anthropic.Claude";

export function apply(code) {
  // 1. Pre-create: swap CHROME_DESKTOP to the Quick Entry id.
  //    Anchor: `W||(W=new E.BrowserWindow({titleBarStyle:"hidden` where the
  //    short-circuit target and the assignment LHS are the same var (== the
  //    upstream `Po||(Po=new ...)` guard, unique to the Quick Entry window).
  //    Quote-agnostic on "hidden" since upstream has shipped both `"hidden`
  //    and `` `hidden` `` (backtick) string literals across releases.
  const preRe = /([\w$]+)\|\|\(([\w$]+)=new ([\w$]+)\.BrowserWindow\(\{titleBarStyle:(["'`])hidden/g;
  let preCount = 0;
  code = code.replace(preRe, (m, w1, w2, ev, quote) => {
    if (w1 !== w2) return m; // not the QE constructor, leave untouched
    preCount++;
    return (
      `${w1}||(process.env.CHROME_DESKTOP="${QE_APP_ID}.desktop",` +
      `(typeof ${ev}.app.setDesktopName==="function"&&${ev}.app.setDesktopName("${QE_APP_ID}.desktop")),` +
      // Replay the matched tail with the SAME quote character upstream used -
      // the closing quote after "hidden" is untouched original text, so ours
      // must match it or the literal is left unbalanced.
      `${w2}=new ${ev}.BrowserWindow({titleBarStyle:${quote}hidden`
    );
  });
  if (preCount !== 1) {
    throw new Error(`${name}: pre-create pattern matched ${preCount} times (expected 1)`);
  }

  // 2. Post-create: reset CHROME_DESKTOP on the window's ready-to-show, so later
  //    windows (dialogs, settings) get the normal app_id again. Honours a
  //    per-profile CLAUDE_PROFILE suffix if the launcher exports one. The base
  //    name is read from the app's own package.json (falling back to the last
  //    known-good literal if that ever fails) rather than hardcoded - see the
  //    module comment above.
  // `joinVar` allows an optional one-level `.default` since upstream's `path`
  // import is sometimes accessed through its ESM-interop default export
  // (`p.default.join(...)`) rather than directly (`p.join(...)`). The path
  // string itself is matched quote-agnostically (", ' or `).
  const loadRe =
    /([\w$]+)\.loadFile\(((?:[\w$]+\.)?[\w$]+)\.join\(([\w$]+)\.app\.getAppPath\(\),["'`]\.vite\/renderer\/quick_window\/quick-window\.html["'`]\)\)/g;
  let postCount = 0;
  code = code.replace(loadRe, (m, winVar, joinVar, ev) => {
    postCount++;
    return (
      `${m},${winVar}.once("ready-to-show",()=>{try{` +
      `const _mid=(()=>{let _b="${MAIN_APP_ID_FALLBACK}";try{` +
      `const _dn=require(${joinVar}.join(${ev}.app.getAppPath(),"package.json")).desktopName;` +
      `if(typeof _dn==="string"&&_dn)_b=_dn.replace(/\\.desktop$/,"")` +
      `}catch(__qeReadErr){}` +
      `return _b+(process.env.CLAUDE_PROFILE?"-"+process.env.CLAUDE_PROFILE:"")+".desktop"})();` +
      `process.env.CHROME_DESKTOP=_mid;` +
      `typeof ${ev}.app.setDesktopName==="function"&&${ev}.app.setDesktopName(_mid);` +
      `}catch(__qeAppIdErr){}})`
    );
  });
  if (postCount !== 1) {
    throw new Error(`${name}: loadFile pattern matched ${postCount} times (expected 1)`);
  }

  // Positive end-state assertions (never report success on a false premise).
  if (!code.includes(`process.env.CHROME_DESKTOP="${QE_APP_ID}.desktop"`)) {
    throw new Error(`${name}: CHROME_DESKTOP swap marker missing after patch`);
  }
  if (!code.includes(`let _b="${MAIN_APP_ID_FALLBACK}"`)) {
    throw new Error(`${name}: main app id fallback marker missing after patch`);
  }
  return code;
}
