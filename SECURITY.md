# Security Policy

I'm Alexander Skula ([@0xCUB3](https://github.com/0xCUB3)) and I maintain wBlock. I am also its security contact, so reports come straight to me.

## Reporting a vulnerability

Security problems shouldn't go in a public issue. Please use [Report a vulnerability](https://github.com/0xCUB3/wBlock/security/advisories/new) on GitHub. It opens a private advisory.

A good report has the wBlock version, the platform and Safari version, and either steps to reproduce or a proof of concept.

## What counts

Everything in this repository is in scope. The app and its Safari extensions count. The userscript and userstyle engine counts too, along with the messaging between the extensions and the app and the path that downloads and updates filter lists.

If a filter list misses an ad or breaks a site, that is a normal [issue](https://github.com/0xCUB3/wBlock/issues). If the problem is inside a third-party filter list or userscript, it belongs with the author. The exception is when wBlock's handling of it is what makes it exploitable.

## Supported versions

Only the latest version on the App Store and in GitHub releases is supported. Fixes go into the next release.
