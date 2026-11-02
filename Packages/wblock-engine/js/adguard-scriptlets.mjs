// AdGuard's scriptlet library (GPL-3.0), for AdGuard-syntax rules that have no
// uBO equivalent. Bundled into scriptlets/adguard.js, which wBlock Scripts
// loads only when a page needs one of these scriptlets.
import { scriptlets } from '@adguard/scriptlets';

globalThis.wbeAdguardScriptlets = scriptlets;
