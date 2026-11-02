// Incremental path for persistent DOM-token removers. Only compound selectors
// qualify: their matches cannot change when an ancestor or sibling changes.
// Relational/pseudo selectors and other timing modes keep the upstream path.
function removeDOMTokens(kind, raw = '', selector = '', behavior = '', ...extra) {
  if (behavior !== 'stay' || extra.length || typeof raw !== 'string'
    || typeof selector !== 'string' || !selector
    || !/^(?:[a-zA-Z][\w-]*)?(?:[.#][a-zA-Z_][\w-]*)*$/.test(selector)) return false;
  const tokens = raw.split(/\s*\|\s*/);
  if (tokens.some(token => !/^[a-zA-Z_][\w-]*$/.test(token))) return false;
  const classes = kind === 'remove-class';
  const attributes = new Set(classes ? ['class'] : tokens);
  if (selector.includes('.')) attributes.add('class');
  if (selector.includes('#')) attributes.add('id');
  const className = /\.([\w-]+)/.exec(selector)?.[1];
  const tagName = /^[a-zA-Z][\w-]*/.exec(selector)?.[0];
  const remove = element => {
    if (className && !element.classList.contains(className)) return;
    if (!element.matches(selector)) return;
    if (classes) {
      if (tokens.some(token => element.classList.contains(token))) element.classList.remove(...tokens);
    } else {
      for (const token of tokens) if (element.hasAttribute(token)) element.removeAttribute(token);
    }
  };
  const visit = root => {
    if (root.nodeType !== 1 || !root.isConnected) return;
    // Snapshot live collections before removing attributes that determine membership.
    const descendants = Array.from(className ? root.getElementsByClassName(className)
      : tagName ? root.getElementsByTagName(tagName) : root.querySelectorAll(selector));
    remove(root);
    for (const element of descendants) remove(element);
  };
  runAt(() => {
    for (const element of document.querySelectorAll(selector)) remove(element);
    new MutationObserver(records => {
      for (const record of records) {
        if (record.type === 'attributes') {
          if (record.target.isConnected) remove(record.target);
        } else {
          for (const node of record.addedNodes) visit(node);
        }
      }
    }).observe(document, { subtree: true, childList: true, attributes: true, attributeFilter: [...attributes] });
  }, 'loading');
  return true;
}
