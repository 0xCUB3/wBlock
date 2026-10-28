// Calibration cases for the WebKit simulator. Each case is one rule list and one
// page (app.localtest.me) whose resources are loaded from several origins. The
// driver (calibrate.ts) records which resources reached the server in real
// WKWebView, and the test suite checks simulate() against that recording.
//
// Hosts resolve to 127.0.0.1 through public wildcard DNS, which gives real
// registrable-domain boundaries: localtest.me (top and first party) and lvh.me
// (third party).

import type { WkResourceType } from './webkit.ts';

export const PORT = 8799;

export const HOSTS = {
    top: 'app.localtest.me',
    first: 'static.localtest.me',
    third: 'ads.lvh.me',
} as const;

export type HostKey = keyof typeof HOSTS;

export interface CalResource {
    id: string;
    // WebKit resource type the request should be classified as.
    type: WkResourceType;
    host: HostKey;
    path: string;
    // Child-document resource this resource lives in. Absent for the top page.
    frame?: string;
    // How the page requests it when the default element does not fit.
    via?: 'xhr';
}

export interface CalibrationCase {
    id: string;
    what: string;
    rules: unknown[];
    resources: CalResource[];
    // Class names (without "cs-") of elements placed in the top page, for css-display-none.
    hide?: string[];
}

const block = (urlFilter: string, trigger: Record<string, unknown> = {}) => ({
    trigger: { 'url-filter': urlFilter, ...trigger },
    action: { type: 'block' },
});

const css = (urlFilter: string, selector: string, trigger: Record<string, unknown> = {}) => ({
    trigger: { 'url-filter': urlFilter, ...trigger },
    action: { type: 'css-display-none', selector },
});

const ignorePrevious = (urlFilter: string, trigger: Record<string, unknown> = {}) => ({
    trigger: { 'url-filter': urlFilter, ...trigger },
    action: { type: 'ignore-previous-rules' },
});

const ignoreFollowing = (urlFilter: string, trigger: Record<string, unknown> = {}) => ({
    trigger: { 'url-filter': urlFilter, ...trigger },
    action: { type: 'ignore-following-rules' },
});

const img = (id: string, host: HostKey, path: string, frame?: string): CalResource => ({ id, type: 'image', host, path, frame });
const script = (id: string, host: HostKey, path: string, frame?: string): CalResource => ({ id, type: 'script', host, path, frame });

// A child document that holds the resources whose `frame` is its id.
const frameDoc = (id: string, host: HostKey, path: string): CalResource => ({ id, type: 'child-document', host, path });

const CHILD_IN_LIB = 'lib/in.js';

export const CALIBRATION_CASES: CalibrationCase[] = [
    {
        id: 'k01', what: 'url-filter substring, default case-insensitive: matches path',
        rules: [block('banner')],
        resources: [img('a', 'top', 'img/banner.png'), img('b', 'top', 'img/logo.png'), script('c', 'third', 'lib/app.js')],
    },
    {
        id: 'k02', what: 'url-filter is case-insensitive by default',
        rules: [block('banner')],
        resources: [img('a', 'top', 'img/BANNER.png'), img('b', 'top', 'img/Banner.png')],
    },
    {
        id: 'k03', what: 'url-filter-is-case-sensitive: uppercase pattern only matches uppercase URL',
        rules: [block('BANNER', { 'url-filter-is-case-sensitive': true })],
        resources: [img('a', 'top', 'img/banner.png'), img('b', 'top', 'img/BANNER.png')],
    },
    {
        id: 'k04', what: '^ anchors at the start of the URL',
        rules: [block('^http://ads\\.lvh\\.me')],
        resources: [script('a', 'third', 'x.js'), script('b', 'top', 'ads.lvh.me/x.js')],
    },
    {
        id: 'k05', what: '$ anchors at the end; the id query string follows the path',
        rules: [block('\\.js$')],
        resources: [script('a', 'top', 'lib/app.js'), script('b', 'top', 'lib/app.json')],
    },
    {
        id: 'k06', what: '.* between literals',
        rules: [block('ads.*banner')],
        resources: [img('a', 'top', 'ads/x/banner.png'), img('b', 'top', 'banner/ads.png')],
    },
    {
        id: 'k07', what: '? makes the preceding character optional',
        rules: [block('colou?r')],
        resources: [img('a', 'top', 'colour.png'), img('b', 'top', 'color.png'), img('c', 'top', 'colr.png')],
    },
    {
        id: 'k08', what: 'character class with + quantifier',
        rules: [block('/[0-9]+\\.gif')],
        resources: [img('a', 'top', 'pix/12.gif'), img('b', 'top', 'pix/a.gif')],
    },
    {
        id: 'k09', what: 'group with + quantifier',
        rules: [block('(ab)+c')],
        resources: [img('a', 'top', 'x/ababc.png'), img('b', 'top', 'x/abx.png')],
    },
    {
        id: 'k10', what: 'brace quantifier {2,}',
        rules: [block('x{2,}y')],
        resources: [img('a', 'top', 'xxxy.png'), img('b', 'top', 'xy.png')],
    },
    {
        id: 'k11', what: 'alternation | is rejected',
        rules: [block('a|b')],
        resources: [img('a', 'top', 'a.png')],
    },
    {
        id: 'k12', what: '\\d is rejected',
        rules: [block('\\d+')],
        resources: [img('a', 'top', 'a.png')],
    },
    {
        id: 'k13', what: 'resource-type image only',
        rules: [block('lib', { 'resource-type': ['image'] })],
        resources: [img('a', 'top', 'lib/a.png'), script('b', 'top', 'lib/b.js')],
    },
    {
        id: 'k14', what: 'resource-type document blocks child frames, not images',
        rules: [block('frame', { 'resource-type': ['document'] })],
        resources: [frameDoc('f', 'third', 'frame/x.html'), img('a', 'top', 'frame/y.png')],
    },
    {
        id: 'k15', what: 'resource-type list of script and style-sheet',
        rules: [block('x', { 'resource-type': ['script', 'style-sheet'] })],
        resources: [script('a', 'top', 'x/a.js'), { id: 'b', type: 'style-sheet', host: 'top', path: 'x/b.css' }, img('c', 'top', 'x/c.png')],
    },
    {
        id: 'k16', what: 'resource-type font',
        rules: [block('fonts', { 'resource-type': ['font'] })],
        resources: [{ id: 'a', type: 'font', host: 'top', path: 'fonts/f.woff2' }, img('b', 'top', 'fonts/i.png')],
    },
    {
        id: 'k17', what: 'resource-type media',
        rules: [block('av', { 'resource-type': ['media'] })],
        resources: [{ id: 'a', type: 'media', host: 'top', path: 'av/clip.mp4' }, img('b', 'top', 'av/poster.png')],
    },
    {
        id: 'k18', what: 'resource-type fetch covers fetch() and XMLHttpRequest',
        rules: [block('api', { 'resource-type': ['fetch'] })],
        resources: [{ id: 'a', type: 'fetch', host: 'top', path: 'api/a.json' }, { id: 'b', type: 'fetch', host: 'top', path: 'api/b.json', via: 'xhr' }, img('c', 'top', 'api/c.png')],
    },
    {
        id: 'k19', what: 'resource-type ping covers navigator.sendBeacon',
        rules: [block('beacon', { 'resource-type': ['ping'] })],
        resources: [{ id: 'a', type: 'other', host: 'top', path: 'beacon/a' }, { id: 'b', type: 'fetch', host: 'top', path: 'beacon/b' }],
    },
    {
        id: 'k51', what: 'navigator.sendBeacon is typed other, not ping',
        rules: [block('beacon', { 'resource-type': ['other'] })],
        resources: [{ id: 'a', type: 'other', host: 'top', path: 'beacon/a' }, { id: 'b', type: 'fetch', host: 'top', path: 'beacon/b' }],
    },
    {
        id: 'k20', what: 'resource-type raw covers fetch and beacon',
        rules: [block('zz', { 'resource-type': ['raw'] })],
        resources: [{ id: 'a', type: 'fetch', host: 'top', path: 'zz/a' }, { id: 'b', type: 'ping', host: 'top', path: 'zz/b' }, img('c', 'top', 'zz/c.png')],
    },
    {
        id: 'k21', what: 'load-type third-party',
        rules: [block('lib', { 'load-type': ['third-party'] })],
        resources: [script('a', 'third', 'lib/a.js'), script('b', 'first', 'lib/b.js'), script('c', 'top', 'lib/c.js')],
    },
    {
        id: 'k22', what: 'load-type first-party',
        rules: [block('lib', { 'load-type': ['first-party'] })],
        resources: [script('a', 'third', 'lib/a.js'), script('b', 'first', 'lib/b.js'), script('c', 'top', 'lib/c.js')],
    },
    {
        id: 'k23', what: 'load-context child-frame blocks only subresources of child frames',
        rules: [block('lib', { 'load-context': ['child-frame'] })],
        resources: [frameDoc('f', 'first', 'frame/f23.html'), script('a', 'top', 'lib/top.js'), script('b', 'first', CHILD_IN_LIB, 'f')],
    },
    {
        id: 'k24', what: 'load-context top-frame blocks main-frame subresources, not child-frame ones',
        rules: [block('lib', { 'load-context': ['top-frame'] })],
        resources: [frameDoc('f', 'first', 'frame/f24.html'), script('a', 'top', 'lib/top.js'), script('b', 'first', CHILD_IN_LIB, 'f')],
    },
    {
        id: 'k25', what: 'child document initiated from the main frame has load-context top-frame',
        rules: [block('lib', { 'load-context': ['top-frame'] })],
        resources: [frameDoc('f', 'first', 'lib/frame.html')],
    },
    {
        id: 'k26', what: 'child document initiated from the main frame is not child-frame',
        rules: [block('lib', { 'load-context': ['child-frame'] })],
        resources: [frameDoc('f', 'first', 'lib/frame.html')],
    },
    {
        id: 'k27', what: 'if-domain matches the top URL, so it blocks third-party loads on the page',
        rules: [block('lib', { 'if-domain': ['app.localtest.me'] })],
        resources: [script('a', 'third', 'lib/a.js'), script('b', 'top', 'lib/b.js')],
    },
    {
        id: 'k28', what: 'if-domain with a non-matching domain blocks nothing',
        rules: [block('lib', { 'if-domain': ['example.org'] })],
        resources: [script('a', 'third', 'lib/a.js')],
    },
    {
        id: 'k29', what: 'if-domain without * does not match subdomains of the domain',
        rules: [block('lib', { 'if-domain': ['localtest.me'] })],
        resources: [script('a', 'third', 'lib/a.js')],
    },
    {
        id: 'k30', what: 'if-domain with * matches subdomains',
        rules: [block('lib', { 'if-domain': ['*localtest.me'] })],
        resources: [script('a', 'third', 'lib/a.js')],
    },
    {
        id: 'k31', what: 'unless-domain on the top URL',
        rules: [block('lib', { 'unless-domain': ['app.localtest.me'] })],
        resources: [script('a', 'third', 'lib/a.js')],
    },
    {
        id: 'k32', what: 'unless-domain on a non-matching domain blocks',
        rules: [block('lib', { 'unless-domain': ['example.org'] })],
        resources: [script('a', 'third', 'lib/a.js')],
    },
    {
        id: 'k33', what: 'if-top-url substring of the page URL',
        rules: [block('lib', { 'if-top-url': ['/c/k33/index'] })],
        resources: [script('a', 'third', 'lib/a.js')],
    },
    {
        id: 'k34', what: 'unless-top-url substring of the page URL',
        rules: [block('lib', { 'unless-top-url': ['/c/k34/index'] })],
        resources: [script('a', 'third', 'lib/a.js')],
    },
    {
        id: 'k35', what: 'if-frame-url matches the initiating frame, not the top page',
        rules: [block('lib', { 'if-frame-url': ['frame/f35'] })],
        resources: [frameDoc('f', 'first', 'frame/f35.html'), script('a', 'first', CHILD_IN_LIB, 'f'), script('b', 'top', 'lib/top.js')],
    },
    {
        id: 'k36', what: 'unless-frame-url',
        rules: [block('lib', { 'unless-frame-url': ['frame/f36'] })],
        resources: [frameDoc('f', 'first', 'frame/f36.html'), script('a', 'first', CHILD_IN_LIB, 'f'), script('b', 'top', 'lib/top.js')],
    },
    {
        id: 'k37', what: 'ignore-previous-rules cancels earlier matches',
        rules: [block('img'), ignorePrevious('keep')],
        resources: [img('a', 'top', 'img/keep.png'), img('b', 'top', 'img/other.png')],
    },
    {
        id: 'k38', what: 'ignore-following-rules stops evaluation when it matches',
        rules: [ignoreFollowing('lib'), block('lib')],
        resources: [script('a', 'top', 'lib/x.js')],
    },
    {
        id: 'k39', what: 'ignore-following-rules that does not match leaves later rules active',
        rules: [ignoreFollowing('keep'), block('lib')],
        resources: [script('a', 'top', 'lib/x.js')],
    },
    {
        id: 'k40', what: 'css-display-none on the top document',
        rules: [css('k40/index', '.cs-A'), css('.*', '.cs-B', { 'if-domain': ['app.localtest.me'] })],
        resources: [],
        hide: ['A', 'B', 'C'],
    },
    {
        id: 'k41', what: 'css-display-none with ignore-previous-rules cancels the selector',
        rules: [css('k41/index', '.cs-A'), ignorePrevious('k41/index')],
        resources: [],
        hide: ['A', 'B'],
    },
    {
        id: 'k42', what: 'css-display-none with non-matching if-domain',
        rules: [css('.*', '.cs-A', { 'if-domain': ['example.org'] })],
        resources: [],
        hide: ['A'],
    },
    {
        id: 'k43', what: 'url-filter matches the id query string',
        rules: [block('r=zz43')],
        resources: [img('zz43', 'top', 'img/a.png'), img('b', 'top', 'img/b.png')],
    },
    {
        id: 'k44', what: 'load-type is relative to the top URL, not the initiating frame',
        rules: [block('lib', { 'load-type': ['third-party'] })],
        resources: [frameDoc('f', 'third', 'frame/f44.html'), script('a', 'first', CHILD_IN_LIB, 'f'), script('b', 'third', 'lib/b.js', 'f')],
    },
    {
        id: 'k45', what: 'top-document resource-type blocks the page',
        rules: [block('index', { 'resource-type': ['top-document'] })],
        resources: [img('a', 'top', 'img/a.png')],
    },
    {
        id: 'k46', what: 'rule list with a domain that is not lowercase is rejected',
        rules: [block('lib', { 'if-domain': ['App.LocalTest.me'] })],
        resources: [script('a', 'third', 'lib/a.js')],
    },
    {
        id: 'k47', what: 'empty url-filter is rejected',
        rules: [block('')],
        resources: [img('a', 'top', 'img/a.png')],
    },
    {
        id: 'k48', what: 'unknown action type is rejected',
        rules: [{ trigger: { 'url-filter': 'lib' }, action: { type: 'redirect-all' } }],
        resources: [img('a', 'top', 'img/a.png')],
    },
    {
        id: 'k49', what: 'two conditions in one trigger are rejected',
        rules: [block('lib', { 'if-domain': ['app.localtest.me'], 'unless-top-url': ['x'] })],
        resources: [script('a', 'third', 'lib/a.js')],
    },
    {
        id: 'k50', what: 'load-type from the top URL when the frame is on a third-party host',
        rules: [block('lib', { 'load-type': ['first-party'] })],
        resources: [frameDoc('f', 'third', 'frame/f50.html'), script('a', 'first', CHILD_IN_LIB, 'f'), script('b', 'third', 'lib/b.js', 'f')],
    },
    {
        id: 'k52', what: 'child document: if-frame-url matches its own URL',
        rules: [block('frame', { 'resource-type': ['child-document'], 'if-frame-url': ['frame/f52'] })],
        resources: [frameDoc('f', 'first', 'frame/f52.html')],
    },
    {
        id: 'k53', what: 'child document: if-frame-url matches the parent (top page) URL',
        rules: [block('frame', { 'resource-type': ['child-document'], 'if-frame-url': ['/c/k53/index'] })],
        resources: [frameDoc('f', 'first', 'frame/f53.html')],
    },
    {
        id: 'k54', what: 'child document: if-top-url matches the main frame URL',
        rules: [block('frame', { 'resource-type': ['child-document'], 'if-top-url': ['/c/k54/index'] })],
        resources: [frameDoc('f', 'first', 'frame/f54.html')],
    },
    {
        id: 'k55', what: 'child document: load-type is relative to the main frame',
        rules: [block('frame', { 'resource-type': ['child-document'], 'load-type': ['third-party'] })],
        resources: [frameDoc('f', 'third', 'frame/f55.html'), frameDoc('g', 'first', 'frame/g55.html')],
    },
    {
        id: 'k56', what: 'child document: if-domain matches the main frame URL',
        rules: [block('frame', { 'resource-type': ['child-document'], 'if-domain': ['app.localtest.me'] })],
        resources: [frameDoc('f', 'first', 'frame/f56.html')],
    },
    {
        id: 'k57', what: 'child document: if-frame-url is evaluated against about:blank',
        rules: [block('frame', { 'resource-type': ['child-document'], 'if-frame-url': ['about:blank'] })],
        resources: [frameDoc('f', 'first', 'frame/f57.html')],
    },
    {
        id: 'k58', what: 'subresource of a child frame: if-frame-url is the frame document',
        rules: [block('lib', { 'if-frame-url': ['frame/f58'] })],
        resources: [frameDoc('f', 'first', 'frame/f58.html'), script('a', 'first', CHILD_IN_LIB, 'f')],
    },
];
