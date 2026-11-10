//! Drops `ignore-previous-rules` that cancel nothing. WebKit applies one to
//! the earlier rules of its own list that match the same load, so an ignore
//! no earlier rule can match together with it changes no verdict, yet it
//! still costs compile time. #836 copies exceptions into every blocker whose
//! blocks they might lift, and shards keep all of a list's exceptions.
//!
//! The test errs toward keeping. Two triggers are disjoint only when their
//! resource types, load types or load contexts share nothing, their page
//! conditions provably exclude each other, or both url-filters are anchored
//! at hosts that cannot be the same. Everything else, including any
//! url-filter not anchored at a whole host, overlaps.
//!
//! Host anchors: `^[a-z]+://([a-z0-9._-]+\.)?host` or `^[a-z]+://host`, then `/`,
//! `:`, `[/:?#]`, `\?` or `$`. In an http, https, ws or wss URL the text
//! between `//` and the first `/` or `:` (the authority, up to a port or
//! password) holds no `?` or `#`, so such a filter matches only when that
//! text is `host` or ends in `.host` (or is exactly `host`). Two anchors meet
//! exactly when one host is the other or, where subdomains match, a
//! subdomain of it. Separator classes (`[^a-zA-Z0-9_.%-]`) can match `@` in
//! a user name, so they do not end an anchor. The same holds for `if-top-url`
//! and `unless-top-url` regexes, which `regex::host_top_url` writes in this
//! form. `if-domain` compiles to an unanchored regex in WebKit, so it is any
//! page.

use crate::webkit::{WkLoadContext, WkLoadType, WkResourceType, WkTrigger};
use rustc_hash::{FxHashMap, FxHashSet};

use super::regex::{EXACT_START, HOST_START};
/// What may follow a host for the filter to end the host there.
const HOST_ENDS: [&str; 5] = ["[/:?#]", "/", ":", "\\?", "$"];

/// A host a url-filter or top-URL regex is anchored at. `star` when its
/// subdomains match too.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub(crate) struct Host {
    name: Box<str>,
    star: bool,
}

/// The pages a trigger fires on.
#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub(crate) enum Page {
    Any,
    /// Only pages on one of these hosts.
    If(Box<[Host]>),
    /// Every page except some on these hosts (a subset of the excluded ones).
    Unless(Box<[Host]>),
}

/// What `prune` needs of one rule.
#[derive(Clone, Debug)]
pub(crate) struct Shape {
    pub(crate) ignore: bool,
    /// None when the url-filter is not anchored at a whole host.
    url: Option<Host>,
    types: u16,
    load: u8,
    context: u8,
    page: Page,
}

const ALL_TYPES: u16 = (1 << 13) - 1;

fn type_bit(t: WkResourceType) -> u16 {
    1 << t as u16
}

impl Shape {
    pub(crate) fn new(
        ignore: bool,
        url: &str,
        types: Option<&[WkResourceType]>,
        load: Option<&[WkLoadType]>,
        context: Option<&[WkLoadContext]>,
        page: Page,
    ) -> Shape {
        Shape {
            ignore,
            url: anchor(url).map(|(host, _)| host),
            types: types.map_or(ALL_TYPES, |t| t.iter().fold(0, |m, &t| m | type_bit(t))),
            load: load.map_or(3, |l| l.iter().fold(0, |m, &l| m | 1 << l as u8)),
            context: context.map_or(3, |c| c.iter().fold(0, |m, &c| m | 1 << c as u8)),
            page,
        }
    }

    pub(crate) fn of_trigger(ignore: bool, t: &WkTrigger) -> Shape {
        let page = if let Some(urls) = &t.if_top_url {
            if_page(urls.iter().map(String::as_str))
        } else if let Some(urls) = &t.unless_top_url {
            unless_page(urls.iter().map(String::as_str))
        } else if let Some(domains) = &t.unless_domain {
            Page::Unless(domains.iter().map(|d| domain_host(d)).collect())
        } else {
            // if-domain, if-frame-url and unless-frame-url: any page.
            Page::Any
        };
        Shape::new(
            ignore,
            &t.url_filter,
            t.resource_type.as_deref(),
            t.load_type.as_deref(),
            t.load_context.as_deref(),
            page,
        )
    }

    /// The shape with its page condition replaced.
    pub(crate) fn set_page(&mut self, page: Page) {
        self.page = page;
    }
}

/// `if-top-url` regexes: any page when one of them is not a host anchor.
pub(crate) fn if_page<'a>(urls: impl Iterator<Item = &'a str>) -> Page {
    urls.map(|u| anchor(u).map(|(host, _)| host))
        .collect::<Option<Box<[Host]>>>()
        .map_or(Page::Any, Page::If)
}

/// `unless-top-url` regexes. Only a regex that matches every page of its
/// host (nothing after the host) may stand for that host; the rest are left
/// out, which leaves fewer pages excluded.
pub(crate) fn unless_page<'a>(urls: impl Iterator<Item = &'a str>) -> Page {
    Page::Unless(urls.filter_map(anchor).filter(|(_, whole)| *whole).map(|(host, _)| host).collect())
}

/// An `if-domain`/`unless-domain` entry: `*host` also matches subdomains.
pub(crate) fn domain_host(entry: &str) -> Host {
    match entry.strip_prefix('*') {
        Some(name) => Host { name: name.into(), star: true },
        None => Host { name: entry.into(), star: false },
    }
}

/// The host `filter` is anchored at, and whether nothing but the host's end
/// follows it.
fn anchor(filter: &str) -> Option<(Host, bool)> {
    let (rest, star) = match filter.strip_prefix(HOST_START) {
        Some(rest) => (rest, true),
        None => (filter.strip_prefix(EXACT_START)?, false),
    };
    let bytes = rest.as_bytes();
    let mut name = String::new();
    let mut i = 0;
    while i < bytes.len() {
        match bytes[i] {
            b'\\' if bytes.get(i + 1) == Some(&b'.') => {
                name.push('.');
                i += 2;
            }
            b @ (b'a'..=b'z' | b'0'..=b'9' | b'-') => {
                name.push(b as char);
                i += 1;
            }
            // A case-sensitive filter can name an uppercase host, which no
            // URL has; as lowercase it matches more, which is safe.
            b @ b'A'..=b'Z' => {
                name.push(b.to_ascii_lowercase() as char);
                i += 1;
            }
            _ => break,
        }
    }
    let tail = &rest[i..];
    if name.is_empty() || name.starts_with('.') || name.ends_with('.') || name.contains("..") {
        return None;
    }
    HOST_ENDS.iter().any(|e| tail.starts_with(e)).then(|| (Host { name: name.into(), star }, tail == "[/:?#]"))
}

/// `host` and each parent of it: `a.b.c`, `b.c`, `c`.
fn labels(host: &str) -> impl Iterator<Item = &str> {
    std::iter::once(host).chain(host.match_indices('.').map(|(i, _)| &host[i + 1..]))
}

/// Whether one URL host can match both anchors.
fn hosts_meet(a: &Host, b: &Host) -> bool {
    let under = |x: &Host, y: &Host| {
        y.star && x.name.len() > y.name.len() && x.name.ends_with(&*y.name)
            && x.name.as_bytes()[x.name.len() - y.name.len() - 1] == b'.'
    };
    a.name == b.name || under(a, b) || under(b, a)
}

/// Whether `unless` excludes every page `host` matches.
fn covered(host: &Host, unless: &[Host]) -> bool {
    unless.iter().any(|u| {
        u.name == host.name && (u.star || !host.star)
            || u.star && host.name.len() > u.name.len() && host.name.ends_with(&*u.name)
                && host.name.as_bytes()[host.name.len() - u.name.len() - 1] == b'.'
    })
}

fn pages_meet(a: &Page, b: &Page) -> bool {
    match (a, b) {
        (Page::Any, _) | (_, Page::Any) | (Page::Unless(_), Page::Unless(_)) => true,
        (Page::If(a), Page::If(b)) => a.iter().any(|x| b.iter().any(|y| hosts_meet(x, y))),
        (Page::If(hosts), Page::Unless(unless)) | (Page::Unless(unless), Page::If(hosts)) => {
            !hosts.iter().all(|h| covered(h, unless))
        }
    }
}

/// A rule without its url, with its page interned in `Pages`.
#[derive(Clone, Copy, PartialEq, Eq, Hash)]
struct Sig {
    types: u16,
    load: u8,
    context: u8,
    page: u32,
}

/// Interned page conditions and which pairs of them meet.
#[derive(Default)]
struct Pages {
    ids: FxHashMap<Page, u32>,
    list: Vec<Page>,
    meets: FxHashMap<(u32, u32), bool>,
}

impl Pages {
    fn sig(&mut self, shape: &Shape) -> Sig {
        let page = match self.ids.get(&shape.page) {
            Some(&id) => id,
            None => {
                let id = self.list.len() as u32;
                self.ids.insert(shape.page.clone(), id);
                self.list.push(shape.page.clone());
                id
            }
        };
        Sig { types: shape.types, load: shape.load, context: shape.context, page }
    }

    fn meet(&mut self, a: Sig, b: Sig) -> bool {
        if a.types & b.types == 0 || a.load & b.load == 0 || a.context & b.context == 0 {
            return false;
        }
        let key = (a.page.min(b.page), a.page.max(b.page));
        let list = &self.list;
        *self.meets.entry(key).or_insert_with(|| pages_meet(&list[a.page as usize], &list[b.page as usize]))
    }
}

/// The rules seen so far, indexed by the host their url-filter is anchored at.
#[derive(Default)]
pub(crate) struct Seen {
    pages: Pages,
    /// Every rule's signature.
    all: FxHashSet<Sig>,
    /// Rules not anchored at a host.
    floating: FxHashSet<Sig>,
    /// Cosmetic hides, which only the page exceptions meant for them cancel.
    hides: FxHashSet<Sig>,
    /// Host -> (subdomains too, signature) of the rules anchored there.
    hosts: FxHashMap<Box<str>, FxHashSet<(bool, Sig)>>,
    /// Host -> signatures of the rules anchored strictly below it.
    below: FxHashMap<Box<str>, FxHashSet<Sig>>,
}

impl Seen {
    /// Records a rule that is not an ignore.
    pub(crate) fn add(&mut self, shape: &Shape) {
        let sig = self.pages.sig(shape);
        self.all.insert(sig);
        match &shape.url {
            None => {
                self.floating.insert(sig);
            }
            Some(host) => {
                self.hosts.entry(host.name.clone()).or_default().insert((host.star, sig));
                for parent in labels(&host.name).skip(1) {
                    self.below.entry(parent.into()).or_default().insert(sig);
                }
            }
        }
    }

    /// Records a cosmetic hide. A network exception on a load of the page
    /// also keeps that load from adding the hides, which uBO's exception
    /// does not do and every other load of the page undoes, so a hide alone
    /// keeps no network exception (`overlaps`).
    pub(crate) fn add_hide(&mut self, shape: &Shape) {
        let sig = self.pages.sig(shape);
        self.hides.insert(sig);
    }

    /// Whether some rule seen so far can match a load `ignore` matches. The
    /// hides count when `hides`: for `$generichide`, `$elemhide` and
    /// `$document` exceptions.
    pub(crate) fn overlaps(&mut self, ignore: &Shape, hides: bool) -> bool {
        let Seen { pages, all, floating, hosts, below, hides: hidden } = self;
        let sig = pages.sig(ignore);
        if hides && hidden.iter().any(|&s| pages.meet(sig, s)) {
            return true;
        }
        let Some(host) = &ignore.url else {
            return all.iter().any(|&s| pages.meet(sig, s));
        };
        if floating.iter().any(|&s| pages.meet(sig, s)) {
            return true;
        }
        // Rules at the host, or at a parent of it when they take subdomains.
        let at = labels(&host.name).any(|name| {
            let exact = name.len() == host.name.len();
            hosts.get(name).is_some_and(|set| set.iter().any(|&(star, s)| (exact || star) && pages.meet(sig, s)))
        });
        // Rules at a subdomain, when the ignore takes subdomains.
        at || host.star && below.get(&*host.name).is_some_and(|set| set.iter().any(|&s| pages.meet(sig, s)))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::webkit::WkResourceType as T;

    fn url(f: &str) -> Shape {
        Shape::new(false, f, None, None, None, Page::Any)
    }

    fn host(name: &str, star: bool) -> Host {
        Host { name: name.into(), star }
    }

    fn overlaps(block: Shape, mut ignore: Shape) -> bool {
        ignore.ignore = true;
        let mut seen = Seen::default();
        seen.add(&block);
        seen.overlaps(&ignore, false)
    }

    const HS: &str = "^[a-z]+://([a-z0-9._-]+\\.)?";

    #[test]
    fn anchors_are_whole_hosts_only() {
        let a = |f: &str| anchor(f).map(|(h, whole)| (h.name.to_string(), h.star, whole));
        assert_eq!(a(&format!("{HS}ads\\.com[/:?#]")), Some(("ads.com".into(), true, true)));
        assert_eq!(a(&format!("{HS}ads\\.com/x\\.js")), Some(("ads.com".into(), true, false)));
        assert_eq!(a(&format!("{HS}ads\\.com:8080")), Some(("ads.com".into(), true, false)));
        assert_eq!(a("^[a-z]+://ads\\.com[/:?#]"), Some(("ads.com".into(), false, true)));
        assert_eq!(a(&format!("{HS}Ads\\.com/")), Some(("ads.com".into(), true, false)));
        // A host prefix, a wildcard, a separator class or an entity is not one.
        assert_eq!(a(&format!("{HS}ads\\.com")), None);
        assert_eq!(a(&format!("{HS}ads\\..*/x")), None);
        assert_eq!(a(&format!("{HS}ads\\.com([^a-zA-Z0-9_.%-].*)?$")), None);
        assert_eq!(a(&format!("{HS}google\\.(com?\\.)?[^:/.]+[/:?#]")), None);
        assert_eq!(a("/ads/"), None);
        assert_eq!(a("^https://ads\\.com/"), None);
    }

    #[test]
    fn hosts_meet_by_suffix() {
        assert!(hosts_meet(&host("a.com", true), &host("a.com", false)));
        assert!(hosts_meet(&host("x.a.com", false), &host("a.com", true)));
        assert!(!hosts_meet(&host("x.a.com", false), &host("a.com", false)));
        assert!(!hosts_meet(&host("xa.com", true), &host("a.com", true)));
        assert!(!hosts_meet(&host("b.com", true), &host("a.com", true)));
    }

    #[test]
    fn url_overlap() {
        let ads = format!("{HS}ads\\.com[/:?#]");
        let sub = format!("{HS}cdn\\.ads\\.com/x");
        let other = format!("{HS}other\\.com/x");
        assert!(overlaps(url(&ads), url(&sub)));
        assert!(overlaps(url(&sub), url(&ads)));
        assert!(!overlaps(url(&other), url(&ads)));
        // Unanchored blocks match a path of any host.
        assert!(overlaps(url("/ads/"), url(&ads)));
        assert!(overlaps(url(&format!("{HS}ads\\.com")), url(&format!("{HS}ads\\.com\\.evil\\.net/"))));
        // An unanchored exception meets any block.
        assert!(overlaps(url(&other), url("/x\\.js")));
        // Exact hosts do not reach subdomains.
        assert!(!overlaps(url("^[a-z]+://cdn\\.ads\\.com/"), url("^[a-z]+://ads\\.com/")));
        assert!(overlaps(url("^[a-z]+://cdn\\.ads\\.com/"), url(&ads)));
    }

    #[test]
    fn types_load_types_and_contexts() {
        let with = |types: &[T], load: Option<WkLoadType>, context: Option<WkLoadContext>| {
            Shape::new(false, ".*", Some(types), load.as_ref().map(std::slice::from_ref), context.as_ref().map(std::slice::from_ref), Page::Any)
        };
        assert!(!overlaps(with(&[T::Image], None, None), with(&[T::Script], None, None)));
        assert!(overlaps(with(&[T::Image, T::Script], None, None), with(&[T::Script], None, None)));
        assert!(overlaps(url(".*"), with(&[T::Script], None, None)));
        let (first, third) = (Some(WkLoadType::FirstParty), Some(WkLoadType::ThirdParty));
        assert!(!overlaps(with(&[T::Script], first, None), with(&[T::Script], third, None)));
        assert!(overlaps(with(&[T::Script], None, None), with(&[T::Script], third, None)));
        let (top, child) = (Some(WkLoadContext::TopFrame), Some(WkLoadContext::ChildFrame));
        assert!(!overlaps(with(&[T::Document], None, top), with(&[T::Document], None, child)));
    }

    #[test]
    fn page_conditions() {
        let on = |page: Page| Shape::new(false, ".*", None, None, None, page);
        let top = |h: &str| format!("{HS}{}[/:?#]", h.replace('.', "\\."));
        let a = || if_page([top("a.com")].iter().map(String::as_str));
        let b = || if_page([top("b.com")].iter().map(String::as_str));
        let sub_a = || if_page([top("x.a.com")].iter().map(String::as_str));
        assert!(!overlaps(on(a()), on(b())));
        assert!(overlaps(on(a()), on(sub_a())));
        assert!(overlaps(on(Page::Any), on(a())));
        // Excluded pages: an exception only on a.com cannot meet a block
        // everywhere but a.com, and can on pages the block keeps.
        let not_a = || unless_page([top("a.com")].iter().map(String::as_str));
        assert!(!overlaps(on(not_a()), on(a())));
        assert!(!overlaps(on(not_a()), on(sub_a())));
        assert!(overlaps(on(not_a()), on(b())));
        assert!(overlaps(on(not_a()), on(not_a())));
        // A top URL with a path excludes only some of the host's pages.
        let not_path = unless_page([format!("{HS}a\\.com/x")].iter().map(String::as_str));
        assert!(overlaps(on(not_path), on(a())));
        // An entity or if-domain is any page.
        let entity = if_page([format!("{HS}a\\.(com?\\.)?[^:/.]+[/:?#]")].iter().map(String::as_str));
        assert!(overlaps(on(entity), on(b())));
        let domain = Shape::of_trigger(false, &WkTrigger { url_filter: ".*".into(), if_domain: Some(vec!["*a.com".into()]), ..Default::default() });
        assert!(overlaps(domain, on(b())));
        let unless = Shape::of_trigger(false, &WkTrigger { url_filter: ".*".into(), unless_domain: Some(vec!["*a.com".into()]), ..Default::default() });
        assert!(!overlaps(unless, on(sub_a())));
    }

    #[test]
    fn only_earlier_non_ignores_count() {
        let mut seen = Seen::default();
        let mut ignore = url(&format!("{HS}ads\\.com/"));
        ignore.ignore = true;
        assert!(!seen.overlaps(&ignore, false));
        seen.add(&url(&format!("{HS}other\\.com[/:?#]")));
        assert!(!seen.overlaps(&ignore, false));
        seen.add(&url(&format!("{HS}com/x")));
        assert!(seen.overlaps(&ignore, false));
    }
}
