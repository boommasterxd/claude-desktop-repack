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
// Ported from patches/fix_quick_entry_app_id.nim of the claude-desktop-bin project.

export const name = "quick-entry-app-id";

const QE_APP_ID = "claude-quick-entry";
const MAIN_APP_ID = "claude";

export function apply(code) {
  // 1. Pre-create: swap CHROME_DESKTOP to the Quick Entry id.
  //    Anchor: `W||(W=new E.BrowserWindow({titleBarStyle:"hidden` where the
  //    short-circuit target and the assignment LHS are the same var (== the
  //    upstream `Po||(Po=new ...)` guard, unique to the Quick Entry window).
  const preRe = /([\w$]+)\|\|\(([\w$]+)=new ([\w$]+)\.BrowserWindow\(\{titleBarStyle:"hidden/g;
  let preCount = 0;
  code = code.replace(preRe, (m, w1, w2, ev) => {
    if (w1 !== w2) return m; // not the QE constructor, leave untouched
    preCount++;
    return (
      `${w1}||(process.env.CHROME_DESKTOP="${QE_APP_ID}.desktop",` +
      `(typeof ${ev}.app.setDesktopName==="function"&&${ev}.app.setDesktopName("${QE_APP_ID}.desktop")),` +
      `${w2}=new ${ev}.BrowserWindow({titleBarStyle:"hidden`
    );
  });
  if (preCount !== 1) {
    throw new Error(`${name}: pre-create pattern matched ${preCount} times (expected 1)`);
  }

  // 2. Post-create: reset CHROME_DESKTOP on the window's ready-to-show, so later
  //    windows (dialogs, settings) get the normal app_id again. Honours a
  //    per-profile CLAUDE_PROFILE suffix if the launcher exports one.
  const loadRe = /([\w$]+)\.loadFile\(([\w$]+)\.join\(([\w$]+)\.app\.getAppPath\(\),"\.vite\/renderer\/quick_window\/quick-window\.html"\)\)/g;
  let postCount = 0;
  code = code.replace(loadRe, (m, winVar, joinVar, ev) => {
    postCount++;
    return (
      `${m},${winVar}.once("ready-to-show",()=>{try{` +
      `const _mid="${MAIN_APP_ID}"+(process.env.CLAUDE_PROFILE?"-"+process.env.CLAUDE_PROFILE:"")+".desktop";` +
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
  return code;
}
