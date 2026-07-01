// Make the Quick Entry toggle reachable from outside the app, bypassing the
// broken GNOME Wayland GlobalShortcuts portal. Three mechanisms, all driving the
// app's own Quick Entry show/hide handler:
//   - A Unix domain socket at $XDG_RUNTIME_DIR/claude-desktop-qe[-profile].sock
//     (fast ~5-25 ms toggle, no process spawn) -> the launcher's `--toggle`.
//   - argv "--toggle" checked on the running instance's second-instance event.
//   - argv "--toggle" checked once shortly after a cold start.
//
// The handler is captured into globalThis.__ceQuickEntryShow with a 100 ms
// debounce. Ported from patches/fix_quick_entry_cli_toggle.nim.

export const name = "quick-entry-cli-toggle";

const HANDLER = "globalThis.__ceQuickEntryShow";
const FLAG = "--toggle-quick-entry";
const FLAG_SHORT = "--toggle";

export function apply(code) {
  // A + C + D: capture the QUICK_ENTRY toggle handler, add debounce, expose it
  // globally, schedule the first-instance argv check, and open the trigger socket.
  const qeRe = /([\w$]+)\(([\w$]+)\.QUICK_ENTRY,(\(\)=>\{[\w$]+&&![\w$]+\.isDestroyed\(\)&&[\w$]+\.isFullScreen\(\)\?\([\w$]+\.focus\(\),[\w$]+\([\w$]*\)\):[\w$]+\([\w$]*\)\})\)/g;
  let countA = 0;
  code = code.replace(qeRe, (m, regFn, enumVar, arrow) => {
    countA++;
    const body = arrow.slice("()=>{".length, -1);
    const wrapped =
      "()=>{var __t=Date.now();if(globalThis.__ceQEInvokedAt&&__t-globalThis.__ceQEInvokedAt<100)return;globalThis.__ceQEInvokedAt=__t;" +
      body +
      "}";
    const firstInstance =
      ",setTimeout(()=>{try{if(Array.isArray(process.argv)&&(process.argv.includes(\"" +
      FLAG +
      "\")||process.argv.includes(\"" +
      FLAG_SHORT +
      "\"))&&" +
      HANDLER +
      ")" +
      HANDLER +
      "()}catch(e){}},250)";
    const socket =
      ",(()=>{if(process.platform!==\"linux\")return;try{" +
      "const _qeS=(process.env.XDG_RUNTIME_DIR||(\"/run/user/\"+process.getuid()))+\"/claude-desktop-qe\"+(process.env.CLAUDE_PROFILE?\"-\"+process.env.CLAUDE_PROFILE:\"\")+\".sock\";" +
      "try{require(\"fs\").unlinkSync(_qeS)}catch(e){}" +
      "require(\"net\").createServer(c=>{" +
      "c.on(\"error\",e=>{console.warn(\"[quick-entry] socket connection error:\",e.message)});" +
      "c.end();" +
      "try{if(" + HANDLER + ")" + HANDLER + "()}catch(e){}" +
      "}).on(\"error\",e=>{console.warn(\"[quick-entry] socket server error:\",e.message)}).listen(_qeS);" +
      "if(!globalThis.__qeTriggerLogged){globalThis.__qeTriggerLogged=true;" +
      "console.log(\"[quick-entry] socket trigger ready: \"+_qeS)}" +
      "}catch(e){}})()";
    return `${regFn}(${enumVar}.QUICK_ENTRY,${HANDLER}=${wrapped})${firstInstance}${socket}`;
  });
  if (countA !== 1) {
    throw new Error(`${name}: QUICK_ENTRY handler pattern matched ${countA} times (expected 1)`);
  }

  // B: prepend an argv check to the second-instance handler (warm-start path).
  const siRe = /(\.on\("second-instance",\()([\w$]+),([\w$]+),([\w$]+)(\)=>\{)/g;
  let countB = 0;
  code = code.replace(siRe, (m, head, evt, argv, cwd, tail) => {
    countB++;
    const check =
      `if(Array.isArray(${argv})&&(${argv}.includes("${FLAG}")||${argv}.includes("${FLAG_SHORT}")))` +
      `{try{${HANDLER}&&${HANDLER}()}catch(e){}return}`;
    return `${head}${evt},${argv},${cwd}${tail}${check}`;
  });
  if (countB !== 1) {
    throw new Error(`${name}: second-instance pattern matched ${countB} times (expected 1)`);
  }

  // Positive end-state assertions.
  if (!code.includes(`${HANDLER}=()=>{`)) {
    throw new Error(`${name}: handler-capture marker missing after patch`);
  }
  if (!code.includes("/claude-desktop-qe")) {
    throw new Error(`${name}: socket-trigger marker missing after patch`);
  }
  return code;
}
