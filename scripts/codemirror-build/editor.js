// Editor entry for wBlock's CodeMirror host. Re-bundled to:
//  - pick the language from the `isUserStyle` flag (CSS vs JavaScript)
//  - keep syntax highlighting on for typical userscripts instead of disabling
//    it whenever a single line exceeds 8192 chars; only drop it for genuinely
//    large documents, and fall back to a stream highlighter rather than none.
import { EditorState, Compartment } from "@codemirror/state";
import {
  EditorView,
  ViewPlugin,
  Decoration,
  keymap,
  drawSelection,
  lineNumbers,
  highlightActiveLine,
  highlightActiveLineGutter,
  highlightSpecialChars,
  dropCursor,
  rectangularSelection,
  crosshairCursor,
} from "@codemirror/view";
import {
  defaultKeymap,
  history,
  historyKeymap,
  undo,
  redo,
} from "@codemirror/commands";
import {
  searchKeymap,
  openSearchPanel,
  search,
  highlightSelectionMatches,
} from "@codemirror/search";
import {
  indentOnInput,
  bracketMatching,
  foldGutter,
  foldKeymap,
  syntaxHighlighting,
  defaultHighlightStyle,
  HighlightStyle,
} from "@codemirror/language";
import { autocompletion, completionKeymap, closeBrackets, closeBracketsKeymap } from "@codemirror/autocomplete";
import { javascript } from "@codemirror/lang-javascript";
import { css } from "@codemirror/lang-css";

const HANDLER = "codeMirror";

// Mirrors CodeMirrorDocumentAnalysis on the Swift side.
function analyze(text) {
  let longest = 0;
  let len = 0;
  let cur = 0;
  for (let i = 0; i < text.length; i += 1) {
    const code = text.charCodeAt(i);
    if (code === 10 || code === 13) {
      if (cur > longest) longest = cur;
      cur = 0;
      if (code === 13 && text.charCodeAt(i + 1) === 10) i += 1;
    } else {
      cur += 1;
    }
    len += 1;
  }
  if (cur > longest) longest = cur;
  // Only disable highlighting for truly huge documents; the old 8192-char
  // long-line cutoff killed coloring for most minified userscripts.
  const isLargeDocument = text.length >= 512_000;
  return {
    isLargeDocument,
    hasLongLine: longest >= 8192,
    longestLine: longest,
  };
}

function theme() {
  return EditorView.theme({
    "&": { height: "100%", backgroundColor: "var(--cm-background)", color: "var(--cm-foreground)", fontSize: "13px" },
    ".cm-scroller": { overflow: "auto", fontFamily: "ui-monospace, SFMono-Regular, SF Mono, Menlo, Monaco, Consolas, monospace", lineHeight: "1.5" },
    ".cm-content": { padding: "12px", minHeight: "100%", caretColor: "var(--cm-caret)" },
    ".cm-cursor, .cm-dropCursor": { borderLeftColor: "var(--cm-caret)" },
    ".cm-selectionBackground": { backgroundColor: "var(--cm-selection)" },
    ".cm-gutters": { backgroundColor: "var(--cm-gutter-background)", color: "var(--cm-gutter-foreground)", border: "none", paddingRight: "8px" },
    ".cm-activeLine": { backgroundColor: "var(--cm-active-line)" },
    ".cm-activeLineGutter": { backgroundColor: "var(--cm-active-line)" },
    ".cm-search": { backgroundColor: "var(--cm-panel-background)", borderBottom: "1px solid var(--cm-border)", padding: "8px 12px", color: "var(--cm-foreground)" },
    ".cm-search input": { backgroundColor: "var(--cm-input-background)", color: "var(--cm-foreground)", border: "1px solid var(--cm-border)", borderRadius: "8px", padding: "6px 8px" },
    ".cm-search button": { backgroundColor: "var(--cm-button-background)", color: "var(--cm-foreground)", border: "1px solid var(--cm-border)", borderRadius: "8px", padding: "6px 10px" },
    ".cm-search button:hover": { backgroundColor: "var(--cm-button-hover)" },
    ".cm-panels": { backgroundColor: "var(--cm-panel-background)", color: "var(--cm-foreground)" },
    ".cm-matchingBracket": { backgroundColor: "var(--cm-bracket-match)", outline: "1px solid var(--cm-border)" },
  });
}

const editableCompartment = new Compartment();
const readOnlyCompartment = new Compartment();
const lineWrappingCompartment = new Compartment();
const lineKindsCompartment = new Compartment();
const languageCompartment = new Compartment();
const phrasesCompartment = new Compartment();

let baselineText = "";
let dirtyKnown = false;
let suppressDirty = false;
let view = null;

function post(message) {
  window.webkit?.messageHandlers?.[HANDLER]?.postMessage(message);
}

// Full-parse highlighting (Lezer tree → tags). Used for normal documents.
function fullHighlight(language) {
  return [
    language,
    bracketMatching(),
    foldGutter(),
    autocompletion(),
    closeBrackets(),
    indentOnInput(),
    syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
    highlightActiveLine(),
    highlightActiveLineGutter(),
    highlightSpecialChars(),
    highlightSelectionMatches(),
  ];
}

// Lightweight stream highlighter for large documents where building a full
// parse tree is too expensive. Still gives colors, no folding/autocomplete.
function streamHighlight(language) {
  return [
    language,
    bracketMatching(),
    syntaxHighlighting(defaultHighlightStyle, { fallback: true }),
    highlightActiveLine(),
    highlightActiveLineGutter(),
    highlightSpecialChars(),
    highlightSelectionMatches(),
  ];
}

function baseExtensions() {
  return [
    history(),
    lineNumbers(),
    drawSelection(),
    highlightActiveLine(),
    highlightActiveLineGutter(),
    highlightSpecialChars(),
    dropCursor(),
    rectangularSelection(),
    crosshairCursor(),
    EditorState.allowMultipleSelections.of(true),
    EditorView.contentAttributes.of({
      spellcheck: "false",
      autocorrect: "off",
      autocapitalize: "off",
      autocomplete: "off",
    }),
    keymap.of([
      ...closeBracketsKeymap,
      ...defaultKeymap,
      ...searchKeymap,
      ...historyKeymap,
      ...foldKeymap,
      ...completionKeymap,
    ]),
    search({ top: true }),
    theme(),
    EditorView.updateListener.of((update) => {
      if (!update.docChanged || suppressDirty) return;
      post({ type: "documentChanged" });
      if (!dirtyKnown) {
        dirtyKnown = true;
        post({ type: "dirtyStateChanged", isDirty: true });
        return;
      }
      if (update.state.doc.length !== baselineText.length) return;
      const nowDirty = update.state.doc.toString() !== baselineText;
      if (nowDirty !== dirtyKnown) {
        dirtyKnown = nowDirty;
        post({ type: "dirtyStateChanged", isDirty: nowDirty });
      }
    }),
  ];
}

function languageFor(isUserStyle) {
  return isUserStyle ? css() : javascript();
}

function highlightBlock(analysis, isUserStyle) {
  const language = languageFor(isUserStyle);
  if (analysis.isLargeDocument) {
    return streamHighlight(language);
  }
  return fullHighlight(language);
}

const RULE_KINDS = new Set(["comment", "supported", "advanced", "removeParam", "unsupported", "duplicate"]);

function visibleRuleDecorations(editorView, lineKinds) {
  const ranges = [];
  const seen = new Set();
  for (const visible of editorView.visibleRanges) {
    let line = editorView.state.doc.lineAt(visible.from);
    const lastLine = editorView.state.doc.lineAt(visible.to);
    while (line.number <= lastLine.number) {
      const kind = lineKinds[String(line.number - 1)];
      if (kind && RULE_KINDS.has(kind) && !seen.has(line.number)) {
        ranges.push(Decoration.line({
          attributes: { class: `wblock-rule-${kind}` },
        }).range(line.from));
        seen.add(line.number);
      }
      if (line.number === lastLine.number) break;
      line = editorView.state.doc.line(line.number + 1);
    }
  }
  return Decoration.set(ranges, true);
}

function categoryDecorations(lineKinds) {
  if (!lineKinds || Object.keys(lineKinds).length === 0) return [];
  return ViewPlugin.fromClass(class {
    constructor(editorView) {
      this.decorations = visibleRuleDecorations(editorView, lineKinds);
    }
    update(update) {
      if (update.docChanged || update.viewportChanged) {
        this.decorations = visibleRuleDecorations(update.view, lineKinds);
      }
    }
  }, { decorations: (plugin) => plugin.decorations });
}

function reconfigure(compartment, extension) {
  if (view) view.dispatch({ effects: compartment.reconfigure(extension) });
}

window.wblockEditor = {
  boot(config) {
    const text = config.text ?? "";
    const analysis = analyze(text);
    const lineWrapping = !!config.lineWrapping;
    const editable = !!config.editable;
    const phrases = config.phrases ?? {};
    const isUserStyle = !!config.isUserStyle;
    const lineKinds = config.lineKinds ?? {};
    baselineText = text;
    dirtyKnown = false;

    const extensions = [
      ...baseExtensions(),
      editableCompartment.of(EditorView.editable.of(editable)),
      readOnlyCompartment.of(EditorState.readOnly.of(!editable)),
      lineWrappingCompartment.of(lineWrapping ? EditorView.lineWrapping : []),
      lineKindsCompartment.of(categoryDecorations(lineKinds)),
      languageCompartment.of(highlightBlock(analysis, isUserStyle)),
      phrasesCompartment.of(EditorState.phrases.of(phrases)),
    ];

    const state = EditorState.create({ doc: text, extensions });
    const parent = document.getElementById("editor");
    view?.destroy();
    view = new EditorView({ state, parent });
    post({
      type: "ready",
      analysis: {
        ...analysis,
        lineWrapping,
        syntaxHighlightingEnabled: !analysis.isLargeDocument,
      },
    });
    post({ type: "dirtyStateChanged", isDirty: false });
  },
  setEditable(editable) {
    reconfigure(editableCompartment, EditorView.editable.of(!!editable));
    reconfigure(readOnlyCompartment, EditorState.readOnly.of(!editable));
    if (editable) view?.focus();
  },
  setLineWrapping(enabled) {
    reconfigure(lineWrappingCompartment, enabled ? EditorView.lineWrapping : []);
    document.body.classList.toggle("cm-wrap-lines", !!enabled);
  },
  setDocument(text, markClean = false, lineKinds = {}) {
    if (!view) return;
    const nextText = text ?? "";
    suppressDirty = true;
    view.dispatch({
      changes: { from: 0, to: view.state.doc.length, insert: nextText },
      effects: lineKindsCompartment.reconfigure(categoryDecorations(lineKinds)),
    });
    suppressDirty = false;
    if (markClean) {
      baselineText = nextText;
      dirtyKnown = false;
      post({ type: "dirtyStateChanged", isDirty: false });
    }
  },
  getDocument() {
    return view ? view.state.doc.toString() : "";
  },
  undo() {
    return view && !view.state.readOnly ? undo(view) : false;
  },
  redo() {
    return view && !view.state.readOnly ? redo(view) : false;
  },
  openSearch() {
    if (!view) return false;
    return openSearchPanel(view);
  },
  focus() {
    view?.focus();
  },
};
