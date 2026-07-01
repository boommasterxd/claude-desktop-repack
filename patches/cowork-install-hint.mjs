// Make the "Cowork requires QEMU" install hint distro-aware. Upstream hard-codes
// a Debian command: `["sudo apt install", ...pkgs].join(" ")`, shown to the user
// as "Install it with '<cmd>', then restart Claude." On Fedora/RHEL/Arch/openSUSE
// that command is wrong (wrong package manager AND wrong package names).
//
// We wrap the joined command string in a small runtime translator: if `apt`
// exists it is returned byte-for-byte (Debian/Ubuntu unchanged); otherwise the
// first of dnf/pacman/zypper found rewrites the manager prefix and maps the
// Debian package names to that distro's equivalents. Everything is in a
// try/catch that falls back to the original string, so a translation failure can
// never break the (cosmetic) hint.
//
// Anchor: the unique `["sudo apt install",` array open + its `].join(" ")` close.
// Non-greedy up to the FIRST `].join(" ")` matches only the outer array (the
// inner arch/virtiofsd sub-arrays are not followed by `.join(" ")`), so this does
// not depend on minified names or the exact package logic in between.

export const name = "cowork-install-hint";
export const description =
  "makes the Cowork 'missing QEMU' install hint distro-aware (dnf/pacman/zypper) instead of hard-coded `sudo apt`";

// Injected IIFE. Kept dependency-free and defensive. `s` is the Debian command
// string, e.g. "sudo apt install qemu-system-x86 ovmf virtiofsd".
const WRAP =
  '(s=>{try{const{execSync:_x}=require("child_process");' +
  'const _has=c=>{try{_x("command -v "+c,{stdio:"ignore"});return!0}catch(_){return!1}};' +
  'if(_has("apt"))return s;' +
  'const _M={dnf:["sudo dnf install",{"qemu-system-x86":"qemu-kvm",ovmf:"edk2-ovmf","qemu-system-arm":"qemu-system-aarch64","qemu-efi-aarch64":"edk2-aarch64"}],' +
  'pacman:["sudo pacman -S",{"qemu-system-x86":"qemu-full",ovmf:"edk2-ovmf","qemu-system-arm":"qemu-full","qemu-efi-aarch64":"edk2-aarch64"}],' +
  'zypper:["sudo zypper install",{"qemu-system-x86":"qemu-x86",ovmf:"qemu-ovmf-x86_64","qemu-system-arm":"qemu-arm","qemu-efi-aarch64":"qemu-uefi-aarch64"}]};' +
  'const _k=["dnf","pacman","zypper"].find(_has);if(!_k)return s;' +
  'const[_pre,_map]=_M[_k];' +
  'return _pre+" "+s.split(" ").slice(3).map(p=>_map[p]||p).join(" ")' +
  '}catch(_){return s}})';

export function apply(code) {
  if (code.includes("sudo dnf install")) return code; // already patched (end-state present)

  const opens = (code.match(/\["sudo apt install",/g) || []).length;
  if (opens !== 1) {
    throw new Error(`${name}: expected exactly 1 "sudo apt install" hint, found ${opens}`);
  }

  let done = 0;
  const out = code.replace(/(\["sudo apt install",[\s\S]*?\]\.join\(" "\))/, (m) => {
    done++;
    return `${WRAP}(${m})`;
  });
  if (done !== 1) {
    throw new Error(`${name}: wrap did not apply (join-close anchor not found)`);
  }
  if (!out.includes("sudo dnf install")) {
    throw new Error(`${name}: end-state marker missing after patch`);
  }
  return out;
}
