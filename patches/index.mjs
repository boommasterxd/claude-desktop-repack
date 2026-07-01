// Single source of truth for the set of patches applied to app.asar. Both the
// build (patch-payload.mjs) and the release notes (render-notes.mjs) read this,
// so the changelog always lists exactly the patches that were applied.

import * as quickEntryCliToggle from "./quick-entry-cli-toggle.mjs";
import * as quickEntryAppId from "./quick-entry-app-id.mjs";

export const patches = [quickEntryCliToggle, quickEntryAppId];
