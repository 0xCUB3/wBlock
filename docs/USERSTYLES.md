# Userstyles in wBlock

wBlock 3.0.0 and later can install UserCSS userstyles, the `.user.css` themes you find on [userstyles.world](https://userstyles.world) and similar sites. A userstyle is plain CSS with a metadata block at the top, and wBlock injects it into matching pages as CSS. There is no JavaScript wrapper, so a userstyle works even on sites where scripts are blocked.

This guide covers macOS, but the same steps apply on iOS, iPadOS, and visionOS.

## Installing a userstyle

Open wBlock, go to Userscripts in the sidebar, and click the add button (Add Userscript or Userstyle). The sheet has three tabs.

- URL: paste a direct link to the style. The link has to end in `.user.css`, `.css`, `.less`, `.sass`, `.scss`, `.styl`, or `.pcss`. The Install link on a userstyles.world page is the right one. wBlock downloads the file, reads the metadata, and installs it.
- Text: paste or write the style yourself. The editor recognizes the `/* ==UserStyle== */` block and fills in the name and description for you.
- File: import a `.user.css` (or `.less`, `.sass`, `.scss`, `.styl`, `.pcss`) file from disk. Files imported this way do not auto-update; import the file again to replace it.

Click Apply Changes when you are done so Safari picks up the new style. Reload any pages that are already open.

## What the file needs

wBlock only accepts a file as a userstyle when it carries a complete metadata block with at least a `@name`:

```css
/* ==UserStyle==
@name         Example Dark Theme
@namespace    example.com
@version      1.0.0
@description  Darkens example.com
@updateURL    https://example.com/dark.user.css
@preprocessor default
==/UserStyle== */

@-moz-document domain("example.com") {
  body { background: #111; color: #eee; }
}
```

The `@-moz-document` sections decide which pages get the CSS. `domain()`, `url()`, `url-prefix()`, and `regexp()` all work, and CSS written outside any `@-moz-document` block is applied to every page. The file extension only tells wBlock to look for a userstyle; the metadata block is what actually gets parsed, so a `.css` file without the block is rejected.

## Preprocessors and variables

The `@preprocessor` line picks how the style is compiled before injection.

- `default` or no line: plain CSS. `@var` declarations become CSS custom properties.
- `uso`: userstyles.org convention, `/*[[name]]*/` placeholders are substituted textually. `@advanced` variables are supported.
- `less`, `sass`, `scss`, `stylus`, `postcss`: compiled offline on your Mac with a bundled compiler. Nothing is sent over the network.

Variables declared with `@var` or `@advanced` are applied with their default values. There is no per-variable settings UI yet; to change a value, edit the style's source in wBlock and change the default.

A few things are deliberately not supported. Sass `@import`, `@use`, and `@forward` are rejected, as are Stylus imports and plugins and Less inline JavaScript. The PostCSS backend only runs the `postcss-nested` plugin. Source is limited to 2 MiB and compiled output to 10 MiB, and compilation stops after 10 seconds. If a style hits one of these limits, wBlock shows the compiler error on the style's row.

## Updating, disabling, and removing

Styles installed from a URL update along with your filter lists and userscripts, using `@updateURL` when the metadata has one and the original download URL otherwise. Update Now in the toolbar checks them on demand.

Each style has an enable toggle in the Userscripts list, and you can turn all userscripts and userstyles off per site from the Safari toolbar popup. To remove a style, swipe or right-click it in the list and choose Delete.

Userstyles sync through iCloud with the rest of your userscripts when sync is on. The raw UserCSS is what gets stored and synced; the compiled CSS is regenerated on each device.

## Troubleshooting

- "Not a userscript or userstyle: missing metadata block": the file has no `/* ==UserStyle== */` block, or the block has no `@name`.
- "This userstyle needs the ... preprocessor, which isn't supported yet": the `@preprocessor` value is something other than the five listed above.
- The style installs but nothing changes on the page: check the `@-moz-document` conditions match the URL you are on, make sure you clicked Apply Changes, and reload the page. Per-site disabling in the Safari popup also turns styles off.
