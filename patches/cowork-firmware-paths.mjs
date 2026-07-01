// Make the Cowork VM capability probe find OVMF firmware + virtiofsd on the
// non-Debian distros the official Debian .deb does not target (Fedora/RHEL,
// Arch, ...). The official build hard-codes Debian-only paths; the probe builds
// {qemuPath, firmwarePath, virtiofsdPath, ...} and reports Cowork "unsupported"
// whenever firmwarePath/virtiofsdPath resolve to null. On Fedora/Arch the OVMF
// firmware lives under /usr/share/edk2/... (not Debian's /usr/share/OVMF/...),
// so without this the Download button is inert and the workspace never boots.
//
// Robustness: we splice the extra candidates in RIGHT AFTER the canonical Debian
// path *string literal* (with a leading comma), not by matching the array/ternary
// shape. So the patch does not depend on minified variable names, on the ternary
// arm order, or on the `_4M.fd` variant being present. Inserting `,"x","y"` after
// a quoted element is valid whether that element was followed by `,` or by `]`,
// which is why this survives most re-minification. Debian paths stay FIRST, so
// the resolver (takes the first existing path) behaves byte-for-byte the same on
// Debian/Ubuntu.
//
// VARS files: the app derives the writable VARS path via
// `firmwarePath.replace("OVMF_CODE","OVMF_VARS")`, so every OVMF_CODE path added
// must have a sibling OVMF_VARS file with the same name shape. The edk2 paths
// below satisfy that. openSUSE's `*-code.bin` firmware needs a `-code`->`-vars`
// rule instead and is a deliberate known gap (not added here).
//
// Ported from patches/fix_cowork_firmware_paths_linux.nim of claude-desktop-bin.

export const name = "cowork-firmware-paths";
export const description =
  "adds non-Debian OVMF firmware + virtiofsd search paths (Fedora/RHEL, Arch) so Cowork's VM probe works beyond Debian/Ubuntu";

// x86_64 OVMF_CODE candidates whose sibling OVMF_VARS file matches the app's
// OVMF_CODE -> OVMF_VARS derivation (verified against each distro's edk2 package).
const EXTRA_FIRMWARE = [
  "/usr/share/edk2/ovmf/OVMF_CODE.fd", // Fedora 40+/RHEL 9+ (VARS: OVMF_VARS.fd)
  "/usr/share/edk2/x64/OVMF_CODE.4m.fd", // Arch (VARS: OVMF_VARS.4m.fd)
  "/usr/share/edk2/x64/OVMF_CODE.fd", // Arch alt/older name
];
const EXTRA_VIRTIOFSD = [
  "/usr/lib/virtiofsd", // Arch (virtiofsd package)
  "/usr/lib/qemu/virtiofsd", // some distros
];

// aarch64 needs no additions: the Debian path the app already checks,
// /usr/share/AAVMF/AAVMF_CODE.fd, is also canonical on Fedora/RHEL and Arch.

function countOccurrences(haystack, needle) {
  let n = 0;
  for (let i = haystack.indexOf(needle); i !== -1; i = haystack.indexOf(needle, i + needle.length)) n++;
  return n;
}

// Splice `extra` string literals in right after the quoted `lastPath` literal.
// Idempotent via `marker` (a distro path the patch introduces, absent upstream).
function injectAfter(code, lastPath, extra, marker, label) {
  if (code.includes(`"${marker}"`)) return code; // already patched (end-state present)

  const anchor = `"${lastPath}"`;
  const count = countOccurrences(code, anchor);
  if (count !== 1) {
    throw new Error(
      `${name}: ${label} anchor ${anchor} found ${count} time(s) (expected 1) - upstream shape changed, re-anchor`,
    );
  }
  const injection = extra.map((p) => `,"${p}"`).join("");
  const at = code.indexOf(anchor) + anchor.length; // just past the closing quote
  return code.slice(0, at) + injection + code.slice(at);
}

export function apply(code) {
  let out = code;
  out = injectAfter(out, "/usr/share/OVMF/OVMF_CODE.fd", EXTRA_FIRMWARE, "/usr/share/edk2/x64/OVMF_CODE.4m.fd", "firmware");
  out = injectAfter(out, "/usr/bin/virtiofsd", EXTRA_VIRTIOFSD, "/usr/lib/virtiofsd", "virtiofsd");

  // Positive end-state assertions (never report success on a false premise).
  if (!out.includes(`"/usr/share/edk2/x64/OVMF_CODE.4m.fd"`)) {
    throw new Error(`${name}: firmware end-state missing after patch`);
  }
  if (!out.includes(`"/usr/lib/virtiofsd"`)) {
    throw new Error(`${name}: virtiofsd end-state missing after patch`);
  }
  return out;
}
