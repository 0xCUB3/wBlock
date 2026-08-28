# App Store review notes

Paste the ATS paragraph into App Store Connect when submitting.

## App Transport Security

wBlock sets `NSAllowsArbitraryLoads` on the app and on the FilterUpdate helper targets (`FilterUpdateAgent`, `FilterUpdateService`, `FilterUpdateLoginItem`).

Users can subscribe to filter lists and userscripts from URLs they provide. Some of those sources are HTTP. The helpers fetch the same lists in the background so Safari rules stay current. The exception is limited to those downloads. Page content in Safari is still loaded by Safari under its own ATS rules.
