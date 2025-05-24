function _defineProperty2(e, r, t) { return (r = _toPropertyKey(r)) in e ? Object.defineProperty(e, r, { value: t, enumerable: !0, configurable: !0, writable: !0 }) : e[r] = t, e; }
function _toPropertyKey(t) { var i = _toPrimitive(t, "string"); return "symbol" == typeof i ? i : i + ""; }
function _toPrimitive(t, r) { if ("object" != typeof t || !t) return t; var e = t[Symbol.toPrimitive]; if (void 0 !== e) { var i = e.call(t, r || "default"); if ("object" != typeof i) return i; throw new TypeError("@@toPrimitive must return a primitive value."); } return ("string" === r ? String : Number)(t); }
/*
 * AppExtension v1.0.0 (build date: Thu, 17 Apr 2025 16:47:56 GMT)
 * (c) 2025 ameshkov
 * Released under the ISC license
 * https://github.com/ameshkov/safari-blocker
 */
(function () {
  'use strict';

  /*
   * SafariExtension v3.0.0 (build date: Thu, 17 Apr 2025 16:44:26 GMT)
   * (c) 2025 Adguard Software Ltd.
   * Released under the GPL-3.0 license
   * https://github.com/AdguardTeam/SafariConverterLib/tree/master/Extension
   */
  /**
   * @adguard/extended-css - v2.1.1 - Thu Dec 19 2024
   * https://github.com/AdguardTeam/ExtendedCss#homepage
   * Copyright (c) 2024 AdGuard. Licensed GPL-3.0
   */
  function _defineProperty(obj, key, value) {
    if (key in obj) {
      Object.defineProperty(obj, key, {
        value: value,
        enumerable: true,
        configurable: true,
        writable: true
      });
    } else {
      obj[key] = value;
    }
    return obj;
  }

  /**
   * Possible ast node types.
   *
   * IMPORTANT: it is used as 'const' instead of 'enum' to avoid side effects
   * during ExtendedCss import into other libraries.
   */
  const NODE = {
    SELECTOR_LIST: 'SelectorList',
    SELECTOR: 'Selector',
    REGULAR_SELECTOR: 'RegularSelector',
    EXTENDED_SELECTOR: 'ExtendedSelector',
    ABSOLUTE_PSEUDO_CLASS: 'AbsolutePseudoClass',
    RELATIVE_PSEUDO_CLASS: 'RelativePseudoClass'
  };

  /**
   * Class needed for creating ast nodes while selector parsing.
   * Used for SelectorList, Selector, ExtendedSelector.
   */
  class AnySelectorNode {
    /**
     * Creates new ast node.
     *
     * @param type Ast node type.
     */
    constructor(type) {
      _defineProperty(this, "children", []);
      this.type = type;
    }
    /**
     * Adds child node to children array.
     *
     * @param child Ast node.
     */

    addChild(child) {
      this.children.push(child);
    }
  }
  /**
   * Class needed for creating RegularSelector ast node while selector parsing.
   */

  class RegularSelectorNode extends AnySelectorNode {
    /**
     * Creates RegularSelector ast node.
     *
     * @param value Value of RegularSelector node.
     */
    constructor(value) {
      super(NODE.REGULAR_SELECTOR);
      this.value = value;
    }
  }
  /**
   * Class needed for creating RelativePseudoClass ast node while selector parsing.
   */

  class RelativePseudoClassNode extends AnySelectorNode {
    /**
     * Creates RegularSelector ast node.
     *
     * @param name Name of RelativePseudoClass node.
     */
    constructor(name) {
      super(NODE.RELATIVE_PSEUDO_CLASS);
      this.name = name;
    }
  }
  /**
   * Class needed for creating AbsolutePseudoClass ast node while selector parsing.
   */

  class AbsolutePseudoClassNode extends AnySelectorNode {
    /**
     * Creates AbsolutePseudoClass ast node.
     *
     * @param name Name of AbsolutePseudoClass node.
     */
    constructor(name) {
      super(NODE.ABSOLUTE_PSEUDO_CLASS);
      _defineProperty(this, "value", '');
      this.name = name;
    }
  }
  const LEFT_SQUARE_BRACKET = '[';
  const RIGHT_SQUARE_BRACKET = ']';
  const LEFT_PARENTHESIS = '(';
  const RIGHT_PARENTHESIS = ')';
  const LEFT_CURLY_BRACKET = '{';
  const RIGHT_CURLY_BRACKET = '}';
  const BRACKET = {
    SQUARE: {
      LEFT: LEFT_SQUARE_BRACKET,
      RIGHT: RIGHT_SQUARE_BRACKET
    },
    PARENTHESES: {
      LEFT: LEFT_PARENTHESIS,
      RIGHT: RIGHT_PARENTHESIS
    },
    CURLY: {
      LEFT: LEFT_CURLY_BRACKET,
      RIGHT: RIGHT_CURLY_BRACKET
    }
  };
  const SLASH = '/';
  const BACKSLASH = '\\';
  const SPACE = ' ';
  const COMMA = ',';
  const DOT = '.';
  const SEMICOLON = ';';
  const COLON = ':';
  const SINGLE_QUOTE = '\'';
  const DOUBLE_QUOTE = '"'; // do not consider hyphen `-` as separated mark
  // to avoid pseudo-class names splitting
  // e.g. 'matches-css' or 'if-not'

  const CARET = '^';
  const DOLLAR_SIGN = '$';
  const EQUAL_SIGN = '=';
  const TAB = '\t';
  const CARRIAGE_RETURN = '\r';
  const LINE_FEED = '\n';
  const FORM_FEED = '\f';
  const WHITE_SPACE_CHARACTERS = [SPACE, TAB, CARRIAGE_RETURN, LINE_FEED, FORM_FEED]; // for universal selector and attributes

  const ASTERISK = '*';
  const ID_MARKER = '#';
  const CLASS_MARKER = DOT;
  const DESCENDANT_COMBINATOR = SPACE;
  const CHILD_COMBINATOR = '>';
  const NEXT_SIBLING_COMBINATOR = '+';
  const SUBSEQUENT_SIBLING_COMBINATOR = '~';
  const COMBINATORS = [DESCENDANT_COMBINATOR, CHILD_COMBINATOR, NEXT_SIBLING_COMBINATOR, SUBSEQUENT_SIBLING_COMBINATOR];
  const SUPPORTED_SELECTOR_MARKS = [LEFT_SQUARE_BRACKET, RIGHT_SQUARE_BRACKET, LEFT_PARENTHESIS, RIGHT_PARENTHESIS, LEFT_CURLY_BRACKET, RIGHT_CURLY_BRACKET, SLASH, BACKSLASH, SEMICOLON, COLON, COMMA, SINGLE_QUOTE, DOUBLE_QUOTE, CARET, DOLLAR_SIGN, ASTERISK, ID_MARKER, CLASS_MARKER, DESCENDANT_COMBINATOR, CHILD_COMBINATOR, NEXT_SIBLING_COMBINATOR, SUBSEQUENT_SIBLING_COMBINATOR, TAB, CARRIAGE_RETURN, LINE_FEED, FORM_FEED];
  const SUPPORTED_STYLE_DECLARATION_MARKS = [
  // divider between property and value in declaration
  COLON,
  // divider between declarations
  SEMICOLON,
  // sometimes is needed for value wrapping
  // e.g. 'content: "-"'
  SINGLE_QUOTE, DOUBLE_QUOTE,
  // needed for quote escaping inside the same-type quotes
  BACKSLASH,
  // whitespaces
  SPACE, TAB, CARRIAGE_RETURN, LINE_FEED, FORM_FEED]; // absolute:

  const CONTAINS_PSEUDO = 'contains';
  const HAS_TEXT_PSEUDO = 'has-text';
  const ABP_CONTAINS_PSEUDO = '-abp-contains';
  const MATCHES_CSS_PSEUDO = 'matches-css';
  const MATCHES_CSS_BEFORE_PSEUDO = 'matches-css-before';
  const MATCHES_CSS_AFTER_PSEUDO = 'matches-css-after';
  const MATCHES_ATTR_PSEUDO_CLASS_MARKER = 'matches-attr';
  const MATCHES_PROPERTY_PSEUDO_CLASS_MARKER = 'matches-property';
  const XPATH_PSEUDO_CLASS_MARKER = 'xpath';
  const NTH_ANCESTOR_PSEUDO_CLASS_MARKER = 'nth-ancestor';
  const CONTAINS_PSEUDO_NAMES = [CONTAINS_PSEUDO, HAS_TEXT_PSEUDO, ABP_CONTAINS_PSEUDO];
  /**
   * Pseudo-class :upward() can get number or selector arg
   * and if the arg is selector it should be standard, not extended
   * so :upward pseudo-class is always absolute.
   */

  const UPWARD_PSEUDO_CLASS_MARKER = 'upward';
  /**
   * Pseudo-class `:remove()` and pseudo-property `remove`
   * are used for element actions, not for element selecting.
   *
   * Selector text should not contain the pseudo-class
   * so selector parser should consider it as invalid
   * and both are handled by stylesheet parser.
   */

  const REMOVE_PSEUDO_MARKER = 'remove'; // relative:

  const HAS_PSEUDO_CLASS_MARKER = 'has';
  const ABP_HAS_PSEUDO_CLASS_MARKER = '-abp-has';
  const HAS_PSEUDO_CLASS_MARKERS = [HAS_PSEUDO_CLASS_MARKER, ABP_HAS_PSEUDO_CLASS_MARKER];
  const IS_PSEUDO_CLASS_MARKER = 'is';
  const NOT_PSEUDO_CLASS_MARKER = 'not';
  const ABSOLUTE_PSEUDO_CLASSES = [CONTAINS_PSEUDO, HAS_TEXT_PSEUDO, ABP_CONTAINS_PSEUDO, MATCHES_CSS_PSEUDO, MATCHES_CSS_BEFORE_PSEUDO, MATCHES_CSS_AFTER_PSEUDO, MATCHES_ATTR_PSEUDO_CLASS_MARKER, MATCHES_PROPERTY_PSEUDO_CLASS_MARKER, XPATH_PSEUDO_CLASS_MARKER, NTH_ANCESTOR_PSEUDO_CLASS_MARKER, UPWARD_PSEUDO_CLASS_MARKER];
  const RELATIVE_PSEUDO_CLASSES = [...HAS_PSEUDO_CLASS_MARKERS, IS_PSEUDO_CLASS_MARKER, NOT_PSEUDO_CLASS_MARKER];
  const SUPPORTED_PSEUDO_CLASSES = [...ABSOLUTE_PSEUDO_CLASSES, ...RELATIVE_PSEUDO_CLASSES]; // these pseudo-classes should be part of RegularSelector value
  // if its arg does not contain extended selectors.
  // the ast will be checked after the selector is completely parsed

  const OPTIMIZATION_PSEUDO_CLASSES = [NOT_PSEUDO_CLASS_MARKER, IS_PSEUDO_CLASS_MARKER];
  /**
   * ':scope' is used for extended pseudo-class :has(), if-not(), :is() and :not().
   */

  const SCOPE_CSS_PSEUDO_CLASS = ':scope';
  /**
   * ':after' and ':before' are needed for :matches-css() pseudo-class
   * all other are needed for :has() limitation after regular pseudo-elements.
   *
   * @see {@link https://bugs.chromium.org/p/chromium/issues/detail?id=669058#c54} [case 3]
   */

  const REGULAR_PSEUDO_ELEMENTS = {
    AFTER: 'after',
    BACKDROP: 'backdrop',
    BEFORE: 'before',
    CUE: 'cue',
    CUE_REGION: 'cue-region',
    FIRST_LETTER: 'first-letter',
    FIRST_LINE: 'first-line',
    FILE_SELECTION_BUTTON: 'file-selector-button',
    GRAMMAR_ERROR: 'grammar-error',
    MARKER: 'marker',
    PART: 'part',
    PLACEHOLDER: 'placeholder',
    SELECTION: 'selection',
    SLOTTED: 'slotted',
    SPELLING_ERROR: 'spelling-error',
    TARGET_TEXT: 'target-text'
  }; // ExtendedCss does not support at-rules
  // https://developer.mozilla.org/en-US/docs/Web/CSS/At-rule

  const AT_RULE_MARKER = '@';
  const CONTENT_CSS_PROPERTY = 'content';
  const PSEUDO_PROPERTY_POSITIVE_VALUE = 'true';
  const DEBUG_PSEUDO_PROPERTY_GLOBAL_VALUE = 'global';
  const NO_SELECTOR_ERROR_PREFIX = 'Selector should be defined';
  const STYLE_ERROR_PREFIX = {
    NO_STYLE: 'No style declaration found',
    NO_SELECTOR: `${NO_SELECTOR_ERROR_PREFIX} before style declaration in stylesheet`,
    INVALID_STYLE: 'Invalid style declaration',
    UNCLOSED_STYLE: 'Unclosed style declaration',
    NO_PROPERTY: 'Missing style property in declaration',
    NO_VALUE: 'Missing style value in declaration',
    NO_STYLE_OR_REMOVE: 'Style should be declared or :remove() pseudo-class should used',
    NO_COMMENT: 'Comments are not supported'
  };
  const NO_AT_RULE_ERROR_PREFIX = 'At-rules are not supported';
  const REMOVE_ERROR_PREFIX = {
    INVALID_REMOVE: 'Invalid :remove() pseudo-class in selector',
    NO_TARGET_SELECTOR: `${NO_SELECTOR_ERROR_PREFIX} before :remove() pseudo-class`,
    MULTIPLE_USAGE: 'Pseudo-class :remove() appears more than once in selector',
    INVALID_POSITION: 'Pseudo-class :remove() should be at the end of selector'
  };
  const MATCHING_ELEMENT_ERROR_PREFIX = 'Error while matching element';
  const MAX_STYLE_PROTECTION_COUNT = 50;

  /**
   * Regexp that matches backward compatible syntaxes.
   */

  const REGEXP_VALID_OLD_SYNTAX = /\[-(?:ext)-([a-z-_]+)=(["'])((?:(?=(\\?))\4.)*?)\2\]/g;
  /**
   * Marker for checking invalid selector after old-syntax normalizing by selector converter.
   */

  const INVALID_OLD_SYNTAX_MARKER = '[-ext-';
  /**
   * Complex replacement function.
   * Undo quote escaping inside of an extended selector.
   *
   * @param match     Whole matched string.
   * @param name      Group 1.
   * @param quoteChar Group 2.
   * @param rawValue  Group 3.
   *
   * @returns Converted string.
   */

  const evaluateMatch = (match, name, quoteChar, rawValue) => {
    // Unescape quotes
    const re = new RegExp(`([^\\\\]|^)\\\\${quoteChar}`, 'g');
    const value = rawValue.replace(re, `$1${quoteChar}`);
    return `:${name}(${value})`;
  }; // ':scope' pseudo may be at start of :has() argument
  // but ExtCssDocument.querySelectorAll() already use it for selecting exact element descendants

  const SCOPE_MARKER_REGEXP = /\(:scope >/g;
  const SCOPE_REPLACER = '(>';
  const MATCHES_CSS_PSEUDO_ELEMENT_REGEXP = /(:matches-css)-(before|after)\(/g;
  const convertMatchesCss = (match, extendedPseudoClass, regularPseudoElement) => {
    // ':matches-css-before('  -->  ':matches-css(before, '
    // ':matches-css-after('   -->  ':matches-css(after, '
    return `${extendedPseudoClass}${BRACKET.PARENTHESES.LEFT}${regularPseudoElement}${COMMA}`;
  };
  /**
   * Handles old syntax and :scope inside :has().
   *
   * @param selector Trimmed selector to normalize.
   *
   * @returns Normalized selector.
   * @throws An error on invalid old extended syntax selector.
   */

  const normalize = selector => {
    const normalizedSelector = selector.replace(REGEXP_VALID_OLD_SYNTAX, evaluateMatch).replace(SCOPE_MARKER_REGEXP, SCOPE_REPLACER).replace(MATCHES_CSS_PSEUDO_ELEMENT_REGEXP, convertMatchesCss); // validate old syntax after normalizing
    // e.g. '[-ext-matches-css-before=\'content:  /^[A-Z][a-z]'

    if (normalizedSelector.includes(INVALID_OLD_SYNTAX_MARKER)) {
      throw new Error(`Invalid extended-css old syntax selector: '${selector}'`);
    }
    return normalizedSelector;
  };
  /**
   * Prepares the rawSelector before tokenization:
   * 1. Trims it.
   * 2. Converts old syntax `[-ext-pseudo-class="..."]` to new one `:pseudo-class(...)`.
   * 3. Handles :scope pseudo inside :has() pseudo-class arg.
   *
   * @param rawSelector Selector with no style declaration.
   * @returns Prepared selector with no style declaration.
   */

  const convert = rawSelector => {
    const trimmedSelector = rawSelector.trim();
    return normalize(trimmedSelector);
  };

  /**
   * Possible token types.
   *
   * IMPORTANT: it is used as 'const' instead of 'enum' to avoid side effects
   * during ExtendedCss import into other libraries.
   */
  const TOKEN_TYPE = {
    MARK: 'mark',
    WORD: 'word'
  };

  /**
   * Splits `input` string into tokens.
   *
   * @param input Input string to tokenize.
   * @param supportedMarks Array of supported marks to considered as `TOKEN_TYPE.MARK`;
   * all other will be considered as `TOKEN_TYPE.WORD`.
   *
   * @returns Array of tokens.
   */
  const tokenize = (input, supportedMarks) => {
    // buffer is needed for words collecting while iterating
    let wordBuffer = ''; // result collection

    const tokens = [];
    const selectorSymbols = input.split(''); // iterate through selector chars and collect tokens

    selectorSymbols.forEach(symbol => {
      if (supportedMarks.includes(symbol)) {
        // if anything was collected to the buffer before
        if (wordBuffer.length > 0) {
          // now it is time to stop buffer collecting and save is as "word"
          tokens.push({
            type: TOKEN_TYPE.WORD,
            value: wordBuffer
          }); // reset the buffer

          wordBuffer = '';
        } // save current symbol as "mark"

        tokens.push({
          type: TOKEN_TYPE.MARK,
          value: symbol
        });
        return;
      } // otherwise collect symbol to the buffer

      wordBuffer += symbol;
    }); // save the last collected word

    if (wordBuffer.length > 0) {
      tokens.push({
        type: TOKEN_TYPE.WORD,
        value: wordBuffer
      });
    }
    return tokens;
  };

  /**
   * Prepares `rawSelector` and splits it into tokens.
   *
   * @param rawSelector Raw css selector.
   *
   * @returns Array of tokens supported for selector.
   */

  const tokenizeSelector = rawSelector => {
    const selector = convert(rawSelector);
    return tokenize(selector, SUPPORTED_SELECTOR_MARKS);
  };
  /**
   * Splits `attribute` into tokens.
   *
   * @param attribute Input attribute.
   *
   * @returns Array of tokens supported for attribute.
   */

  const tokenizeAttribute = attribute => {
    // equal sigh `=` in attribute is considered as `TOKEN_TYPE.MARK`
    return tokenize(attribute, [...SUPPORTED_SELECTOR_MARKS, EQUAL_SIGN]);
  };

  /**
   * Some browsers do not support Array.prototype.flat()
   * e.g. Opera 42 which is used for browserstack tests.
   *
   * @see {@link https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Array/flat}
   *
   * @param input Array needed to be flatten.
   *
   * @returns Flatten array.
   * @throws An error if array cannot be flatten.
   */
  const flatten = input => {
    const stack = [];
    input.forEach(el => stack.push(el));
    const res = [];
    while (stack.length) {
      // pop value from stack
      const next = stack.pop();
      if (!next) {
        throw new Error('Unable to make array flat');
      }
      if (Array.isArray(next)) {
        // push back array items, won't modify the original input
        next.forEach(el => stack.push(el));
      } else {
        res.push(next);
      }
    } // reverse to restore input order

    return res.reverse();
  };
  /**
   * Returns first item from `array`.
   *
   * @param array Input array.
   *
   * @returns First array item, or `undefined` if there is no such item.
   */

  const getFirst = array => {
    return array[0];
  };
  /**
   * Returns last item from array.
   *
   * @param array Input array.
   *
   * @returns Last array item, or `undefined` if there is no such item.
   */

  const getLast = array => {
    return array[array.length - 1];
  };
  /**
   * Returns array item which is previous to the last one
   * e.g. for `[5, 6, 7, 8]` returns `7`.
   *
   * @param array Input array.
   *
   * @returns Previous to last array item, or `undefined` if there is no such item.
   */

  const getPrevToLast = array => {
    return array[array.length - 2];
  };
  /**
   * Takes array of ast node `children` and returns the child by the `index`.
   *
   * @param array Array of ast node children.
   * @param index Index of needed child in the array.
   * @param errorMessage Optional error message to throw.
   *
   * @returns Array item at `index` position.
   * @throws An error if there is no child with specified `index` in array.
   */

  const getItemByIndex = (array, index, errorMessage) => {
    const indexChild = array[index];
    if (!indexChild) {
      throw new Error(errorMessage || `No array item found by index ${index}`);
    }
    return indexChild;
  };
  const NO_REGULAR_SELECTOR_ERROR = 'At least one of Selector node children should be RegularSelector';
  /**
   * Checks whether the type of `astNode` is SelectorList.
   *
   * @param astNode Ast node.
   *
   * @returns True if astNode.type === SelectorList.
   */

  const isSelectorListNode = astNode => {
    return (astNode === null || astNode === void 0 ? void 0 : astNode.type) === NODE.SELECTOR_LIST;
  };
  /**
   * Checks whether the type of `astNode` is Selector.
   *
   * @param astNode Ast node.
   *
   * @returns True if astNode.type === Selector.
   */

  const isSelectorNode = astNode => {
    return (astNode === null || astNode === void 0 ? void 0 : astNode.type) === NODE.SELECTOR;
  };
  /**
   * Checks whether the type of `astNode` is RegularSelector.
   *
   * @param astNode Ast node.
   *
   * @returns True if astNode.type === RegularSelector.
   */

  const isRegularSelectorNode = astNode => {
    return (astNode === null || astNode === void 0 ? void 0 : astNode.type) === NODE.REGULAR_SELECTOR;
  };
  /**
   * Checks whether the type of `astNode` is ExtendedSelector.
   *
   * @param astNode Ast node.
   *
   * @returns True if astNode.type === ExtendedSelector.
   */

  const isExtendedSelectorNode = astNode => {
    return astNode.type === NODE.EXTENDED_SELECTOR;
  };
  /**
   * Checks whether the type of `astNode` is AbsolutePseudoClass.
   *
   * @param astNode Ast node.
   *
   * @returns True if astNode.type === AbsolutePseudoClass.
   */

  const isAbsolutePseudoClassNode = astNode => {
    return (astNode === null || astNode === void 0 ? void 0 : astNode.type) === NODE.ABSOLUTE_PSEUDO_CLASS;
  };
  /**
   * Checks whether the type of `astNode` is RelativePseudoClass.
   *
   * @param astNode Ast node.
   *
   * @returns True if astNode.type === RelativePseudoClass.
   */

  const isRelativePseudoClassNode = astNode => {
    return (astNode === null || astNode === void 0 ? void 0 : astNode.type) === NODE.RELATIVE_PSEUDO_CLASS;
  };
  /**
   * Returns name of `astNode`.
   *
   * @param astNode AbsolutePseudoClass or RelativePseudoClass node.
   *
   * @returns Name of `astNode`.
   * @throws An error on unsupported ast node or no name found.
   */

  const getNodeName = astNode => {
    if (astNode === null) {
      throw new Error('Ast node should be defined');
    }
    if (!isAbsolutePseudoClassNode(astNode) && !isRelativePseudoClassNode(astNode)) {
      throw new Error('Only AbsolutePseudoClass or RelativePseudoClass ast node can have a name');
    }
    if (!astNode.name) {
      throw new Error('Extended pseudo-class should have a name');
    }
    return astNode.name;
  };
  /**
   * Returns value of `astNode`.
   *
   * @param astNode RegularSelector or AbsolutePseudoClass node.
   * @param errorMessage Optional error message if no value found.
   *
   * @returns Value of `astNode`.
   * @throws An error on unsupported ast node or no value found.
   */

  const getNodeValue = (astNode, errorMessage) => {
    if (astNode === null) {
      throw new Error('Ast node should be defined');
    }
    if (!isRegularSelectorNode(astNode) && !isAbsolutePseudoClassNode(astNode)) {
      throw new Error('Only RegularSelector ot AbsolutePseudoClass ast node can have a value');
    }
    if (!astNode.value) {
      throw new Error(errorMessage || 'Ast RegularSelector ot AbsolutePseudoClass node should have a value');
    }
    return astNode.value;
  };
  /**
   * Returns only RegularSelector nodes from `children`.
   *
   * @param children Array of ast node children.
   *
   * @returns Array of RegularSelector nodes.
   */

  const getRegularSelectorNodes = children => {
    return children.filter(isRegularSelectorNode);
  };
  /**
   * Returns the first RegularSelector node from `children`.
   *
   * @param children Array of ast node children.
   * @param errorMessage Optional error message if no value found.
   *
   * @returns Ast RegularSelector node.
   * @throws An error if no RegularSelector node found.
   */

  const getFirstRegularChild = (children, errorMessage) => {
    const regularSelectorNodes = getRegularSelectorNodes(children);
    const firstRegularSelectorNode = getFirst(regularSelectorNodes);
    if (!firstRegularSelectorNode) {
      throw new Error(errorMessage || NO_REGULAR_SELECTOR_ERROR);
    }
    return firstRegularSelectorNode;
  };
  /**
   * Returns the last RegularSelector node from `children`.
   *
   * @param children Array of ast node children.
   *
   * @returns Ast RegularSelector node.
   * @throws An error if no RegularSelector node found.
   */

  const getLastRegularChild = children => {
    const regularSelectorNodes = getRegularSelectorNodes(children);
    const lastRegularSelectorNode = getLast(regularSelectorNodes);
    if (!lastRegularSelectorNode) {
      throw new Error(NO_REGULAR_SELECTOR_ERROR);
    }
    return lastRegularSelectorNode;
  };
  /**
   * Returns the only child of `node`.
   *
   * @param node Ast node.
   * @param errorMessage Error message.
   *
   * @returns The only child of ast node.
   * @throws An error if none or more than one child found.
   */

  const getNodeOnlyChild = (node, errorMessage) => {
    if (node.children.length !== 1) {
      throw new Error(errorMessage);
    }
    const onlyChild = getFirst(node.children);
    if (!onlyChild) {
      throw new Error(errorMessage);
    }
    return onlyChild;
  };
  /**
   * Takes ExtendedSelector node and returns its only child.
   *
   * @param extendedSelectorNode ExtendedSelector ast node.
   *
   * @returns AbsolutePseudoClass or RelativePseudoClass.
   * @throws An error if there is no specific pseudo-class ast node.
   */

  const getPseudoClassNode = extendedSelectorNode => {
    return getNodeOnlyChild(extendedSelectorNode, 'Extended selector should be specified');
  };
  /**
   * Takes RelativePseudoClass node and returns its only child
   * which is relative SelectorList node.
   *
   * @param pseudoClassNode RelativePseudoClass.
   *
   * @returns Relative SelectorList node.
   * @throws An error if no selector list found.
   */

  const getRelativeSelectorListNode = pseudoClassNode => {
    if (!isRelativePseudoClassNode(pseudoClassNode)) {
      throw new Error('Only RelativePseudoClass node can have relative SelectorList node as child');
    }
    return getNodeOnlyChild(pseudoClassNode, `Missing arg for :${getNodeName(pseudoClassNode)}() pseudo-class`);
  };
  const ATTRIBUTE_CASE_INSENSITIVE_FLAG = 'i';
  /**
   * Limited list of available symbols before slash `/`
   * to check whether it is valid regexp pattern opening.
   */

  const POSSIBLE_MARKS_BEFORE_REGEXP = {
    COMMON: [
    // e.g. ':matches-attr(/data-/)'
    BRACKET.PARENTHESES.LEFT,
    // e.g. `:matches-attr('/data-/')`
    SINGLE_QUOTE,
    // e.g. ':matches-attr("/data-/")'
    DOUBLE_QUOTE,
    // e.g. ':matches-attr(check=/data-v-/)'
    EQUAL_SIGN,
    // e.g. ':matches-property(inner./_test/=null)'
    DOT,
    // e.g. ':matches-css(height:/20px/)'
    COLON,
    // ':matches-css-after( content  :   /(\\d+\\s)*me/  )'
    SPACE],
    CONTAINS: [
    // e.g. ':contains(/text/)'
    BRACKET.PARENTHESES.LEFT,
    // e.g. `:contains('/text/')`
    SINGLE_QUOTE,
    // e.g. ':contains("/text/")'
    DOUBLE_QUOTE]
  };
  /**
   * Checks whether the passed token is supported extended pseudo-class.
   *
   * @param tokenValue Token value to check.
   *
   * @returns True if `tokenValue` is one of supported extended pseudo-class names.
   */

  const isSupportedPseudoClass = tokenValue => {
    return SUPPORTED_PSEUDO_CLASSES.includes(tokenValue);
  };
  /**
   * Checks whether the passed pseudo-class `name` should be optimized,
   * i.e. :not() and :is().
   *
   * @param name Pseudo-class name.
   *
   * @returns True if `name` is one if pseudo-class which should be optimized.
   */

  const isOptimizationPseudoClass = name => {
    return OPTIMIZATION_PSEUDO_CLASSES.includes(name);
  };
  /**
   * Checks whether next to "space" token is a continuation of regular selector being processed.
   *
   * @param nextTokenType Type of token next to current one.
   * @param nextTokenValue Value of token next to current one.
   *
   * @returns True if next token seems to be a part of current regular selector.
   */

  const doesRegularContinueAfterSpace = (nextTokenType, nextTokenValue) => {
    // regular selector does not continues after the current token
    if (!nextTokenType || !nextTokenValue) {
      return false;
    }
    return COMBINATORS.includes(nextTokenValue) || nextTokenType === TOKEN_TYPE.WORD // e.g. '#main *:has(> .ad)'
    || nextTokenValue === ASTERISK || nextTokenValue === ID_MARKER || nextTokenValue === CLASS_MARKER // e.g. 'div :where(.content)'
    || nextTokenValue === COLON // e.g. "div[class*=' ']"
    || nextTokenValue === SINGLE_QUOTE // e.g. 'div[class*=" "]'
    || nextTokenValue === DOUBLE_QUOTE || nextTokenValue === BRACKET.SQUARE.LEFT;
  };
  /**
   * Checks whether the regexp pattern for pseudo-class arg starts.
   * Needed for `context.isRegexpOpen` flag.
   *
   * @param context Selector parser context.
   * @param prevTokenValue Value of previous token.
   * @param bufferNodeValue Value of bufferNode.
   *
   * @returns True if current token seems to be a start of regexp pseudo-class arg pattern.
   * @throws An error on invalid regexp pattern.
   */

  const isRegexpOpening = (context, prevTokenValue, bufferNodeValue) => {
    const lastExtendedPseudoClassName = getLast(context.extendedPseudoNamesStack);
    if (!lastExtendedPseudoClassName) {
      throw new Error('Regexp pattern allowed only in arg of extended pseudo-class');
    } // for regexp pattens the slash should not be escaped
    // const isRegexpPatternSlash = prevTokenValue !== BACKSLASH;
    // regexp pattern can be set as arg of pseudo-class
    // which means limited list of available symbols before slash `/`;
    // for :contains() pseudo-class regexp pattern should be at the beginning of arg

    if (CONTAINS_PSEUDO_NAMES.includes(lastExtendedPseudoClassName)) {
      return POSSIBLE_MARKS_BEFORE_REGEXP.CONTAINS.includes(prevTokenValue);
    }
    if (prevTokenValue === SLASH && lastExtendedPseudoClassName !== XPATH_PSEUDO_CLASS_MARKER) {
      const rawArgDesc = bufferNodeValue ? `in arg part: '${bufferNodeValue}'` : 'arg';
      throw new Error(`Invalid regexp pattern for :${lastExtendedPseudoClassName}() pseudo-class ${rawArgDesc}`);
    } // for other pseudo-classes regexp pattern can be either the whole arg or its part

    return POSSIBLE_MARKS_BEFORE_REGEXP.COMMON.includes(prevTokenValue);
  };
  /**
   * Checks whether the attribute starts.
   *
   * @param tokenValue Value of current token.
   * @param prevTokenValue Previous token value.
   *
   * @returns True if combination of current and previous token seems to be **a start** of attribute.
   */

  const isAttributeOpening = (tokenValue, prevTokenValue) => {
    return tokenValue === BRACKET.SQUARE.LEFT && prevTokenValue !== BACKSLASH;
  };
  /**
   * Checks whether the attribute ends.
   *
   * @param context Selector parser context.
   *
   * @returns True if combination of current and previous token seems to be **an end** of attribute.
   * @throws An error on invalid attribute.
   */

  const isAttributeClosing = context => {
    var _getPrevToLast;
    if (!context.isAttributeBracketsOpen) {
      return false;
    } // valid attributes may have extra spaces inside.
    // we get rid of them just to simplify the checking and they are skipped only here:
    //   - spaces will be collected to the ast with spaces as they were declared is selector
    //   - extra spaces in attribute are not relevant to attribute syntax validity
    //     e.g. 'a[ title ]' is the same as 'a[title]'
    //          'div[style *= "MARGIN" i]' is the same as 'div[style*="MARGIN"i]'

    const noSpaceAttr = context.attributeBuffer.split(SPACE).join(''); // tokenize the prepared attribute string

    const attrTokens = tokenizeAttribute(noSpaceAttr);
    const firstAttrToken = getFirst(attrTokens);
    const firstAttrTokenType = firstAttrToken === null || firstAttrToken === void 0 ? void 0 : firstAttrToken.type;
    const firstAttrTokenValue = firstAttrToken === null || firstAttrToken === void 0 ? void 0 : firstAttrToken.value; // signal an error on any mark-type token except backslash
    // e.g. '[="margin"]'

    if (firstAttrTokenType === TOKEN_TYPE.MARK // backslash is allowed at start of attribute
    // e.g. '[\\:data-service-slot]'
    && firstAttrTokenValue !== BACKSLASH) {
      // eslint-disable-next-line max-len
      throw new Error(`'[${context.attributeBuffer}]' is not a valid attribute due to '${firstAttrTokenValue}' at start of it`);
    }
    const lastAttrToken = getLast(attrTokens);
    const lastAttrTokenType = lastAttrToken === null || lastAttrToken === void 0 ? void 0 : lastAttrToken.type;
    const lastAttrTokenValue = lastAttrToken === null || lastAttrToken === void 0 ? void 0 : lastAttrToken.value;
    if (lastAttrTokenValue === EQUAL_SIGN) {
      // e.g. '[style=]'
      throw new Error(`'[${context.attributeBuffer}]' is not a valid attribute due to '${EQUAL_SIGN}'`);
    }
    const equalSignIndex = attrTokens.findIndex(token => {
      return token.type === TOKEN_TYPE.MARK && token.value === EQUAL_SIGN;
    });
    const prevToLastAttrTokenValue = (_getPrevToLast = getPrevToLast(attrTokens)) === null || _getPrevToLast === void 0 ? void 0 : _getPrevToLast.value;
    if (equalSignIndex === -1) {
      // if there is no '=' inside attribute,
      // it must be just attribute name which means the word-type token before closing bracket
      // e.g. 'div[style]'
      if (lastAttrTokenType === TOKEN_TYPE.WORD) {
        return true;
      }
      return prevToLastAttrTokenValue === BACKSLASH // some weird attribute are valid too
      // e.g. '[class\\"ads-article\\"]'
      && (lastAttrTokenValue === DOUBLE_QUOTE // e.g. "[class\\'ads-article\\']"
      || lastAttrTokenValue === SINGLE_QUOTE);
    } // get the value of token next to `=`

    const nextToEqualSignToken = getItemByIndex(attrTokens, equalSignIndex + 1);
    const nextToEqualSignTokenValue = nextToEqualSignToken.value; // check whether the attribute value wrapper in quotes

    const isAttrValueQuote = nextToEqualSignTokenValue === SINGLE_QUOTE || nextToEqualSignTokenValue === DOUBLE_QUOTE; // for no quotes after `=` the last token before `]` should be a word-type one
    // e.g. 'div[style*=margin]'
    //      'div[style*=MARGIN i]'

    if (!isAttrValueQuote) {
      if (lastAttrTokenType === TOKEN_TYPE.WORD) {
        return true;
      } // otherwise signal an error
      // e.g. 'table[style*=border: 0px"]'

      throw new Error(`'[${context.attributeBuffer}]' is not a valid attribute`);
    } // otherwise if quotes for value are present
    // the last token before `]` can still be word-type token
    // e.g. 'div[style*="MARGIN" i]'

    if (lastAttrTokenType === TOKEN_TYPE.WORD && (lastAttrTokenValue === null || lastAttrTokenValue === void 0 ? void 0 : lastAttrTokenValue.toLocaleLowerCase()) === ATTRIBUTE_CASE_INSENSITIVE_FLAG) {
      return prevToLastAttrTokenValue === nextToEqualSignTokenValue;
    } // eventually if there is quotes for attribute value and last token is not a word,
    // the closing mark should be the same quote as opening one

    return lastAttrTokenValue === nextToEqualSignTokenValue;
  };
  /**
   * Checks whether the `tokenValue` is a whitespace character.
   *
   * @param tokenValue Token value.
   *
   * @returns True if `tokenValue` is a whitespace character.
   */

  const isWhiteSpaceChar = tokenValue => {
    if (!tokenValue) {
      return false;
    }
    return WHITE_SPACE_CHARACTERS.includes(tokenValue);
  };

  /**
   * Checks whether the passed `str` is a name of supported absolute extended pseudo-class,
   * e.g. :contains(), :matches-css() etc.
   *
   * @param str Token value to check.
   *
   * @returns True if `str` is one of absolute extended pseudo-class names.
   */

  const isAbsolutePseudoClass = str => {
    return ABSOLUTE_PSEUDO_CLASSES.includes(str);
  };
  /**
   * Checks whether the passed `str` is a name of supported relative extended pseudo-class,
   * e.g. :has(), :not() etc.
   *
   * @param str Token value to check.
   *
   * @returns True if `str` is one of relative extended pseudo-class names.
   */

  const isRelativePseudoClass = str => {
    return RELATIVE_PSEUDO_CLASSES.includes(str);
  };

  /**
   * Returns the node which is being collected
   * or null if there is no such one.
   *
   * @param context Selector parser context.
   *
   * @returns Buffer node or null.
   */

  const getBufferNode = context => {
    if (context.pathToBufferNode.length === 0) {
      return null;
    } // buffer node is always the last in the pathToBufferNode stack

    return getLast(context.pathToBufferNode) || null;
  };
  /**
   * Returns the parent node to the 'buffer node' — which is the one being collected —
   * or null if there is no such one.
   *
   * @param context Selector parser context.
   *
   * @returns Parent node of buffer node or null.
   */

  const getBufferNodeParent = context => {
    // at least two nodes should exist — the buffer node and its parent
    // otherwise return null
    if (context.pathToBufferNode.length < 2) {
      return null;
    } // since the buffer node is always the last in the pathToBufferNode stack
    // its parent is previous to it in the stack

    return getPrevToLast(context.pathToBufferNode) || null;
  };
  /**
   * Returns last RegularSelector ast node.
   * Needed for parsing of the complex selector with extended pseudo-class inside it.
   *
   * @param context Selector parser context.
   *
   * @returns Ast RegularSelector node.
   * @throws An error if:
   * - bufferNode is absent;
   * - type of bufferNode is unsupported;
   * - no RegularSelector in bufferNode.
   */

  const getContextLastRegularSelectorNode = context => {
    const bufferNode = getBufferNode(context);
    if (!bufferNode) {
      throw new Error('No bufferNode found');
    }
    if (!isSelectorNode(bufferNode)) {
      throw new Error('Unsupported bufferNode type');
    }
    const lastRegularSelectorNode = getLastRegularChild(bufferNode.children);
    context.pathToBufferNode.push(lastRegularSelectorNode);
    return lastRegularSelectorNode;
  };
  /**
   * Updates needed buffer node value while tokens iterating.
   * For RegularSelector also collects token values to context.attributeBuffer
   * for proper attribute parsing.
   *
   * @param context Selector parser context.
   * @param tokenValue Value of current token.
   *
   * @throws An error if:
   * - no bufferNode;
   * - bufferNode.type is not RegularSelector or AbsolutePseudoClass.
   */

  const updateBufferNode = (context, tokenValue) => {
    const bufferNode = getBufferNode(context);
    if (bufferNode === null) {
      throw new Error('No bufferNode to update');
    }
    if (isAbsolutePseudoClassNode(bufferNode)) {
      bufferNode.value += tokenValue;
    } else if (isRegularSelectorNode(bufferNode)) {
      bufferNode.value += tokenValue;
      if (context.isAttributeBracketsOpen) {
        context.attributeBuffer += tokenValue;
      }
    } else {
      // eslint-disable-next-line max-len
      throw new Error(`${bufferNode.type} node cannot be updated. Only RegularSelector and AbsolutePseudoClass are supported`);
    }
  };
  /**
   * Adds SelectorList node to context.ast at the start of ast collecting.
   *
   * @param context Selector parser context.
   */

  const addSelectorListNode = context => {
    const selectorListNode = new AnySelectorNode(NODE.SELECTOR_LIST);
    context.ast = selectorListNode;
    context.pathToBufferNode.push(selectorListNode);
  };
  /**
   * Adds new node to buffer node children.
   * New added node will be considered as buffer node after it.
   *
   * @param context Selector parser context.
   * @param type Type of node to add.
   * @param tokenValue Optional, defaults to `''`, value of processing token.
   *
   * @throws An error if no bufferNode.
   */

  const addAstNodeByType = function (context, type) {
    let tokenValue = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : '';
    const bufferNode = getBufferNode(context);
    if (bufferNode === null) {
      throw new Error('No buffer node');
    }
    let node;
    if (type === NODE.REGULAR_SELECTOR) {
      node = new RegularSelectorNode(tokenValue);
    } else if (type === NODE.ABSOLUTE_PSEUDO_CLASS) {
      node = new AbsolutePseudoClassNode(tokenValue);
    } else if (type === NODE.RELATIVE_PSEUDO_CLASS) {
      node = new RelativePseudoClassNode(tokenValue);
    } else {
      // SelectorList || Selector || ExtendedSelector
      node = new AnySelectorNode(type);
    }
    bufferNode.addChild(node);
    context.pathToBufferNode.push(node);
  };
  /**
   * The very beginning of ast collecting.
   *
   * @param context Selector parser context.
   * @param tokenValue Value of regular selector.
   */

  const initAst = (context, tokenValue) => {
    addSelectorListNode(context);
    addAstNodeByType(context, NODE.SELECTOR); // RegularSelector node is always the first child of Selector node

    addAstNodeByType(context, NODE.REGULAR_SELECTOR, tokenValue);
  };
  /**
   * Inits selector list subtree for relative extended pseudo-classes, e.g. :has(), :not().
   *
   * @param context Selector parser context.
   * @param tokenValue Optional, defaults to `''`, value of inner regular selector.
   */

  const initRelativeSubtree = function (context) {
    let tokenValue = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : '';
    addAstNodeByType(context, NODE.SELECTOR_LIST);
    addAstNodeByType(context, NODE.SELECTOR);
    addAstNodeByType(context, NODE.REGULAR_SELECTOR, tokenValue);
  };
  /**
   * Goes to closest parent specified by type.
   * Actually updates path to buffer node for proper ast collecting of selectors while parsing.
   *
   * @param context Selector parser context.
   * @param parentType Type of needed parent node in ast.
   */

  const upToClosest = (context, parentType) => {
    for (let i = context.pathToBufferNode.length - 1; i >= 0; i -= 1) {
      var _context$pathToBuffer;
      if (((_context$pathToBuffer = context.pathToBufferNode[i]) === null || _context$pathToBuffer === void 0 ? void 0 : _context$pathToBuffer.type) === parentType) {
        context.pathToBufferNode = context.pathToBufferNode.slice(0, i + 1);
        break;
      }
    }
  };
  /**
   * Returns needed buffer node updated due to complex selector parsing.
   *
   * @param context Selector parser context.
   *
   * @returns Ast node for following selector parsing.
   * @throws An error if there is no upper SelectorNode is ast.
   */

  const getUpdatedBufferNode = context => {
    // it may happen during the parsing of selector list
    // which is an argument of relative pseudo-class
    // e.g. '.banner:has(~span, ~p)'
    // parser position is here  ↑
    // so if after the comma the buffer node type is SelectorList and parent type is RelativePseudoClass
    // we should simply return the current buffer node
    const bufferNode = getBufferNode(context);
    if (bufferNode && isSelectorListNode(bufferNode) && isRelativePseudoClassNode(getBufferNodeParent(context))) {
      return bufferNode;
    }
    upToClosest(context, NODE.SELECTOR);
    const selectorNode = getBufferNode(context);
    if (!selectorNode) {
      throw new Error('No SelectorNode, impossible to continue selector parsing by ExtendedCss');
    }
    const lastSelectorNodeChild = getLast(selectorNode.children);
    const hasExtended = lastSelectorNodeChild && isExtendedSelectorNode(lastSelectorNodeChild) // parser position might be inside standard pseudo-class brackets which has space
    // e.g. 'div:contains(/а/):nth-child(100n + 2)'
    && context.standardPseudoBracketsStack.length === 0;
    const supposedPseudoClassNode = hasExtended && getFirst(lastSelectorNodeChild.children);
    let newNeededBufferNode = selectorNode;
    if (supposedPseudoClassNode) {
      // name of pseudo-class for last extended-node child for Selector node
      const lastExtendedPseudoName = hasExtended && supposedPseudoClassNode.name;
      const isLastExtendedNameRelative = lastExtendedPseudoName && isRelativePseudoClass(lastExtendedPseudoName);
      const isLastExtendedNameAbsolute = lastExtendedPseudoName && isAbsolutePseudoClass(lastExtendedPseudoName);
      const hasRelativeExtended = isLastExtendedNameRelative && context.extendedPseudoBracketsStack.length > 0 && context.extendedPseudoBracketsStack.length === context.extendedPseudoNamesStack.length;
      const hasAbsoluteExtended = isLastExtendedNameAbsolute && lastExtendedPseudoName === getLast(context.extendedPseudoNamesStack);
      if (hasRelativeExtended) {
        // return relative selector node to update later
        context.pathToBufferNode.push(lastSelectorNodeChild);
        newNeededBufferNode = supposedPseudoClassNode;
      } else if (hasAbsoluteExtended) {
        // return absolute selector node to update later
        context.pathToBufferNode.push(lastSelectorNodeChild);
        newNeededBufferNode = supposedPseudoClassNode;
      }
    } else if (hasExtended) {
      // return selector node to add new regular selector node later
      newNeededBufferNode = selectorNode;
    } else {
      // otherwise return last regular selector node to update later
      newNeededBufferNode = getContextLastRegularSelectorNode(context);
    } // update the path to buffer node properly

    context.pathToBufferNode.push(newNeededBufferNode);
    return newNeededBufferNode;
  };
  /**
   * Checks values of few next tokens on colon token `:` and:
   *  - updates buffer node for following standard pseudo-class;
   *  - adds extended selector ast node for following extended pseudo-class;
   *  - validates some cases of `:remove()` and `:has()` usage.
   *
   * @param context Selector parser context.
   * @param selector Selector.
   * @param tokenValue Value of current token.
   * @param nextTokenValue Value of token next to current one.
   * @param nextToNextTokenValue Value of token next to next to current one.
   *
   * @throws An error on :remove() pseudo-class in selector
   * or :has() inside regular pseudo limitation.
   */

  const handleNextTokenOnColon = (context, selector, tokenValue, nextTokenValue, nextToNextTokenValue) => {
    if (!nextTokenValue) {
      throw new Error(`Invalid colon ':' at the end of selector: '${selector}'`);
    }
    if (!isSupportedPseudoClass(nextTokenValue.toLowerCase())) {
      if (nextTokenValue.toLowerCase() === REMOVE_PSEUDO_MARKER) {
        // :remove() pseudo-class should be handled before
        // as it is not about element selecting but actions with elements
        // e.g. 'body > div:empty:remove()'
        throw new Error(`${REMOVE_ERROR_PREFIX.INVALID_REMOVE}: '${selector}'`);
      } // if following token is not an extended pseudo
      // the colon should be collected to value of RegularSelector
      // e.g. '.entry_text:nth-child(2)'

      updateBufferNode(context, tokenValue); // check the token after the pseudo and do balance parentheses later
      // only if it is functional pseudo-class (standard with brackets, e.g. ':lang()').
      // no brackets balance needed for such case,
      // parser position is on first colon after the 'div':
      // e.g. 'div:last-child:has(button.privacy-policy__btn)'

      if (nextToNextTokenValue && nextToNextTokenValue === BRACKET.PARENTHESES.LEFT // no brackets balance needed for parentheses inside attribute value
      // e.g. 'a[href="javascript:void(0)"]'   <-- parser position is on colon `:`
      // before `void`           ↑
      && !context.isAttributeBracketsOpen) {
        context.standardPseudoNamesStack.push(nextTokenValue);
      }
    } else {
      // it is supported extended pseudo-class.
      // Disallow :has() inside the pseudos accepting only compound selectors
      // https://bugs.chromium.org/p/chromium/issues/detail?id=669058#c54 [2]
      if (HAS_PSEUDO_CLASS_MARKERS.includes(nextTokenValue) && context.standardPseudoNamesStack.length > 0) {
        // eslint-disable-next-line max-len
        throw new Error(`Usage of :${nextTokenValue}() pseudo-class is not allowed inside regular pseudo: '${getLast(context.standardPseudoNamesStack)}'`);
      } else {
        // stop RegularSelector value collecting
        upToClosest(context, NODE.SELECTOR); // add ExtendedSelector to Selector children

        addAstNodeByType(context, NODE.EXTENDED_SELECTOR);
      }
    }
  };

  // e.g. ':is(.page, .main) > .banner' or '*:not(span):not(p)'

  const IS_OR_NOT_PSEUDO_SELECTING_ROOT = `html ${ASTERISK}`;
  /**
   * Checks if there are any ExtendedSelector node in selector list.
   *
   * @param selectorList Ast SelectorList node.
   *
   * @returns True if `selectorList` has any inner ExtendedSelector node.
   */

  const hasExtendedSelector = selectorList => {
    return selectorList.children.some(selectorNode => {
      return selectorNode.children.some(selectorNodeChild => {
        return isExtendedSelectorNode(selectorNodeChild);
      });
    });
  };
  /**
   * Converts selector list of RegularSelector nodes to string.
   *
   * @param selectorList Ast SelectorList node.
   *
   * @returns String representation for selector list of regular selectors.
   */

  const selectorListOfRegularsToString = selectorList => {
    // if there is no ExtendedSelector in relative SelectorList
    // it means that each Selector node has single child — RegularSelector node
    // and their values should be combined to string
    const standardCssSelectors = selectorList.children.map(selectorNode => {
      const selectorOnlyChild = getNodeOnlyChild(selectorNode, 'Ast Selector node should have RegularSelector node');
      return getNodeValue(selectorOnlyChild);
    });
    return standardCssSelectors.join(`${COMMA}${SPACE}`);
  };
  /**
   * Updates children of `node` replacing them with `newChildren`.
   * Important: modifies input `node` which is passed by reference.
   *
   * @param node Ast node to update.
   * @param newChildren Array of new children for ast node.
   *
   * @returns Updated ast node.
   */

  const updateNodeChildren = (node, newChildren) => {
    node.children = newChildren;
    return node;
  };
  /**
   * Recursively checks whether the ExtendedSelector node should be optimized.
   * It has to be recursive because RelativePseudoClass has inner SelectorList node.
   *
   * @param currExtendedSelectorNode Ast ExtendedSelector node.
   *
   * @returns True is ExtendedSelector should be optimized.
   */

  const shouldOptimizeExtendedSelector = currExtendedSelectorNode => {
    if (currExtendedSelectorNode === null) {
      return false;
    }
    const extendedPseudoClassNode = getPseudoClassNode(currExtendedSelectorNode);
    const pseudoName = getNodeName(extendedPseudoClassNode);
    if (isAbsolutePseudoClass(pseudoName)) {
      return false;
    }
    const relativeSelectorList = getRelativeSelectorListNode(extendedPseudoClassNode);
    const innerSelectorNodes = relativeSelectorList.children; // simple checking for standard selectors in arg of :not() or :is() pseudo-class
    // e.g. 'div > *:is(div, a, span)'

    if (isOptimizationPseudoClass(pseudoName)) {
      const areAllSelectorNodeChildrenRegular = innerSelectorNodes.every(selectorNode => {
        try {
          const selectorOnlyChild = getNodeOnlyChild(selectorNode, 'Selector node should have RegularSelector'); // it means that the only child is RegularSelector and it can be optimized

          return isRegularSelectorNode(selectorOnlyChild);
        } catch (e) {
          return false;
        }
      });
      if (areAllSelectorNodeChildrenRegular) {
        return true;
      }
    } // for other extended pseudo-classes than :not() and :is()

    return innerSelectorNodes.some(selectorNode => {
      return selectorNode.children.some(selectorNodeChild => {
        if (!isExtendedSelectorNode(selectorNodeChild)) {
          return false;
        } // check inner ExtendedSelector recursively
        // e.g. 'div:has(*:not(.header))'

        return shouldOptimizeExtendedSelector(selectorNodeChild);
      });
    });
  };
  /**
   * Returns optimized ExtendedSelector node if it can be optimized
   * or null if ExtendedSelector is fully optimized while function execution
   * which means that value of `prevRegularSelectorNode` is updated.
   *
   * @param currExtendedSelectorNode Current ExtendedSelector node to optimize.
   * @param prevRegularSelectorNode Previous RegularSelector node.
   *
   * @returns Ast node or null.
   */

  const getOptimizedExtendedSelector = (currExtendedSelectorNode, prevRegularSelectorNode) => {
    if (!currExtendedSelectorNode) {
      return null;
    }
    const extendedPseudoClassNode = getPseudoClassNode(currExtendedSelectorNode);
    const relativeSelectorList = getRelativeSelectorListNode(extendedPseudoClassNode);
    const hasInnerExtendedSelector = hasExtendedSelector(relativeSelectorList);
    if (!hasInnerExtendedSelector) {
      // if there is no extended selectors for :not() or :is()
      // e.g. 'div:not(.content, .main)'
      const relativeSelectorListStr = selectorListOfRegularsToString(relativeSelectorList);
      const pseudoName = getNodeName(extendedPseudoClassNode); // eslint-disable-next-line max-len

      const optimizedExtendedStr = `${COLON}${pseudoName}${BRACKET.PARENTHESES.LEFT}${relativeSelectorListStr}${BRACKET.PARENTHESES.RIGHT}`;
      prevRegularSelectorNode.value = `${getNodeValue(prevRegularSelectorNode)}${optimizedExtendedStr}`;
      return null;
    } // eslint-disable-next-line @typescript-eslint/no-use-before-define

    const optimizedRelativeSelectorList = optimizeSelectorListNode(relativeSelectorList);
    const optimizedExtendedPseudoClassNode = updateNodeChildren(extendedPseudoClassNode, [optimizedRelativeSelectorList]);
    return updateNodeChildren(currExtendedSelectorNode, [optimizedExtendedPseudoClassNode]);
  };
  /**
   * Combines values of `previous` and `current` RegularSelector nodes.
   * It may happen during the optimization when ExtendedSelector between RegularSelector node was optimized.
   *
   * @param current Current RegularSelector node.
   * @param previous Previous RegularSelector node.
   */

  const optimizeCurrentRegularSelector = (current, previous) => {
    previous.value = `${getNodeValue(previous)}${SPACE}${getNodeValue(current)}`;
  };
  /**
   * Optimizes ast Selector node.
   *
   * @param selectorNode Ast Selector node.
   *
   * @returns Optimized ast node.
   * @throws An error while collecting optimized nodes.
   */

  const optimizeSelectorNode = selectorNode => {
    // non-optimized list of SelectorNode children
    const rawSelectorNodeChildren = selectorNode.children; // for collecting optimized children list

    const optimizedChildrenList = [];
    let currentIndex = 0; // iterate through all children in non-optimized ast Selector node

    while (currentIndex < rawSelectorNodeChildren.length) {
      const currentChild = getItemByIndex(rawSelectorNodeChildren, currentIndex, 'currentChild should be specified'); // no need to optimize the very first child which is always RegularSelector node

      if (currentIndex === 0) {
        optimizedChildrenList.push(currentChild);
      } else {
        const prevRegularChild = getLastRegularChild(optimizedChildrenList);
        if (isExtendedSelectorNode(currentChild)) {
          // start checking with point is null
          let optimizedExtendedSelector = null; // check whether the optimization is needed

          let isOptimizationNeeded = shouldOptimizeExtendedSelector(currentChild); // update optimizedExtendedSelector so it can be optimized recursively
          // i.e. `getOptimizedExtendedSelector(optimizedExtendedSelector)` below

          optimizedExtendedSelector = currentChild;
          while (isOptimizationNeeded) {
            // recursively optimize ExtendedSelector until no optimization needed
            // e.g. div > *:is(.banner:not(.block))
            optimizedExtendedSelector = getOptimizedExtendedSelector(optimizedExtendedSelector, prevRegularChild);
            isOptimizationNeeded = shouldOptimizeExtendedSelector(optimizedExtendedSelector);
          } // if it was simple :not() of :is() with standard selector arg
          // e.g. 'div:not([class][id])'
          // or   '.main > *:is([data-loaded], .banner)'
          // after the optimization the ExtendedSelector node become part of RegularSelector
          // so nothing to save eventually
          // otherwise the optimized ExtendedSelector should be saved
          // e.g. 'div:has(:not([class]))'

          if (optimizedExtendedSelector !== null) {
            optimizedChildrenList.push(optimizedExtendedSelector); // if optimization is not needed

            const optimizedPseudoClass = getPseudoClassNode(optimizedExtendedSelector);
            const optimizedPseudoName = getNodeName(optimizedPseudoClass); // parent element checking is used to apply :is() and :not() pseudo-classes as extended.
            // as there is no parentNode for root element (html)
            // so element selection should be limited to it's children
            // e.g. '*:is(:has(.page))' -> 'html *:is(has(.page))'
            // or   '*:not(:has(span))' -> 'html *:not(:has(span))'

            if (getNodeValue(prevRegularChild) === ASTERISK && isOptimizationPseudoClass(optimizedPseudoName)) {
              prevRegularChild.value = IS_OR_NOT_PSEUDO_SELECTING_ROOT;
            }
          }
        } else if (isRegularSelectorNode(currentChild)) {
          // in non-optimized ast, RegularSelector node may follow ExtendedSelector which should be optimized
          // for example, for 'div:not(.content) > .banner' schematically it looks like
          // non-optimized ast: [
          //   1. RegularSelector: 'div'
          //   2. ExtendedSelector: 'not(.content)'
          //   3. RegularSelector: '> .banner'
          // ]
          // which after the ExtendedSelector looks like
          // partly optimized ast: [
          //   1. RegularSelector: 'div:not(.content)'
          //   2. RegularSelector: '> .banner'
          // ]
          // so second RegularSelector value should be combined with first one
          // optimized ast: [
          //   1. RegularSelector: 'div:not(.content) > .banner'
          // ]
          // here we check **children of selectorNode** after previous optimization if it was
          const lastOptimizedChild = getLast(optimizedChildrenList) || null;
          if (isRegularSelectorNode(lastOptimizedChild)) {
            optimizeCurrentRegularSelector(currentChild, prevRegularChild);
          }
        }
      }
      currentIndex += 1;
    }
    return updateNodeChildren(selectorNode, optimizedChildrenList);
  };
  /**
   * Optimizes ast SelectorList node.
   *
   * @param selectorListNode SelectorList node.
   *
   * @returns Optimized ast node.
   */

  const optimizeSelectorListNode = selectorListNode => {
    return updateNodeChildren(selectorListNode, selectorListNode.children.map(s => optimizeSelectorNode(s)));
  };
  /**
   * Optimizes ast:
   * If arg of :not() and :is() pseudo-classes does not contain extended selectors,
   * native Document.querySelectorAll() can be used to query elements.
   * It means that ExtendedSelector ast nodes can be removed
   * and value of relevant RegularSelector node should be updated accordingly.
   *
   * @param ast Non-optimized ast.
   *
   * @returns Optimized ast.
   */

  const optimizeAst = ast => {
    // ast is basically the selector list of selectors
    return optimizeSelectorListNode(ast);
  };

  // https://github.com/AdguardTeam/ExtendedCss/issues/115

  const XPATH_PSEUDO_SELECTING_ROOT = 'body';
  const NO_WHITESPACE_ERROR_PREFIX = 'No white space is allowed before or after extended pseudo-class name in selector';
  /**
   * Parses selector into ast for following element selection.
   *
   * @param selector Selector to parse.
   *
   * @returns Parsed ast.
   * @throws An error on invalid selector.
   */

  const parse = selector => {
    const tokens = tokenizeSelector(selector);
    const context = {
      ast: null,
      pathToBufferNode: [],
      extendedPseudoNamesStack: [],
      extendedPseudoBracketsStack: [],
      standardPseudoNamesStack: [],
      standardPseudoBracketsStack: [],
      isAttributeBracketsOpen: false,
      attributeBuffer: '',
      isRegexpOpen: false,
      shouldOptimize: false
    };
    let i = 0;
    while (i < tokens.length) {
      const token = tokens[i];
      if (!token) {
        break;
      } // Token to process

      const {
        type: tokenType,
        value: tokenValue
      } = token; // needed for SPACE and COLON tokens checking

      const nextToken = tokens[i + 1];
      const nextTokenType = nextToken === null || nextToken === void 0 ? void 0 : nextToken.type;
      const nextTokenValue = nextToken === null || nextToken === void 0 ? void 0 : nextToken.value; // needed for limitations
      // - :not() and :is() root element
      // - :has() usage
      // - white space before and after pseudo-class name

      const nextToNextToken = tokens[i + 2];
      const nextToNextTokenValue = nextToNextToken === null || nextToNextToken === void 0 ? void 0 : nextToNextToken.value; // needed for COLON token checking for none-specified regular selector before extended one
      // e.g. 'p, :hover'
      // or   '.banner, :contains(ads)'

      const previousToken = tokens[i - 1];
      const prevTokenType = previousToken === null || previousToken === void 0 ? void 0 : previousToken.type;
      const prevTokenValue = previousToken === null || previousToken === void 0 ? void 0 : previousToken.value; // needed for proper parsing of regexp pattern arg
      // e.g. ':matches-css(background-image: /^url\(https:\/\/example\.org\//)'

      const previousToPreviousToken = tokens[i - 2];
      const prevToPrevTokenValue = previousToPreviousToken === null || previousToPreviousToken === void 0 ? void 0 : previousToPreviousToken.value;
      let bufferNode = getBufferNode(context);
      switch (tokenType) {
        case TOKEN_TYPE.WORD:
          if (bufferNode === null) {
            // there is no buffer node only in one case — no ast collecting has been started
            initAst(context, tokenValue);
          } else if (isSelectorListNode(bufferNode)) {
            // add new selector to selector list
            addAstNodeByType(context, NODE.SELECTOR);
            addAstNodeByType(context, NODE.REGULAR_SELECTOR, tokenValue);
          } else if (isRegularSelectorNode(bufferNode)) {
            updateBufferNode(context, tokenValue);
          } else if (isExtendedSelectorNode(bufferNode)) {
            // No white space is allowed between the name of extended pseudo-class
            // and its opening parenthesis
            // https://www.w3.org/TR/selectors-4/#pseudo-classes
            // e.g. 'span:contains (text)'
            if (isWhiteSpaceChar(nextTokenValue) && nextToNextTokenValue === BRACKET.PARENTHESES.LEFT) {
              throw new Error(`${NO_WHITESPACE_ERROR_PREFIX}: '${selector}'`);
            }
            const lowerCaseTokenValue = tokenValue.toLowerCase(); // save pseudo-class name for brackets balance checking

            context.extendedPseudoNamesStack.push(lowerCaseTokenValue); // extended pseudo-class name are parsed in lower case
            // as they should be case-insensitive
            // https://www.w3.org/TR/selectors-4/#pseudo-classes

            if (isAbsolutePseudoClass(lowerCaseTokenValue)) {
              addAstNodeByType(context, NODE.ABSOLUTE_PSEUDO_CLASS, lowerCaseTokenValue);
            } else {
              // if it is not absolute pseudo-class, it must be relative one
              // add RelativePseudoClass with tokenValue as pseudo-class name to ExtendedSelector children
              addAstNodeByType(context, NODE.RELATIVE_PSEUDO_CLASS, lowerCaseTokenValue); // for :not() and :is() pseudo-classes parsed ast should be optimized later

              if (isOptimizationPseudoClass(lowerCaseTokenValue)) {
                context.shouldOptimize = true;
              }
            }
          } else if (isAbsolutePseudoClassNode(bufferNode)) {
            // collect absolute pseudo-class arg
            updateBufferNode(context, tokenValue);
          } else if (isRelativePseudoClassNode(bufferNode)) {
            initRelativeSubtree(context, tokenValue);
          }
          break;
        case TOKEN_TYPE.MARK:
          switch (tokenValue) {
            case COMMA:
              if (!bufferNode || typeof bufferNode !== 'undefined' && !nextTokenValue) {
                // consider the selector is invalid if there is no bufferNode yet (e.g. ', a')
                // or there is nothing after the comma while bufferNode is defined (e.g. 'div, ')
                throw new Error(`'${selector}' is not a valid selector`);
              } else if (isRegularSelectorNode(bufferNode)) {
                if (context.isAttributeBracketsOpen) {
                  // the comma might be inside element attribute value
                  // e.g. 'div[data-comma="0,1"]'
                  updateBufferNode(context, tokenValue);
                } else {
                  // new Selector should be collected to upper SelectorList
                  upToClosest(context, NODE.SELECTOR_LIST);
                }
              } else if (isAbsolutePseudoClassNode(bufferNode)) {
                // the comma inside arg of absolute extended pseudo
                // e.g. 'div:xpath(//h3[contains(text(),"Share it!")]/..)'
                updateBufferNode(context, tokenValue);
              } else if (isSelectorNode(bufferNode)) {
                // new Selector should be collected to upper SelectorList
                // if parser position is on Selector node
                upToClosest(context, NODE.SELECTOR_LIST);
              }
              break;
            case SPACE:
              // it might be complex selector with extended pseudo-class inside it
              // and the space is between that complex selector and following regular selector
              // parser position is on ` ` before `span` now:
              // e.g. 'div:has(img).banner span'
              // so we need to check whether the new ast node should be added (example above)
              // or previous regular selector node should be updated
              if (isRegularSelectorNode(bufferNode) // no need to update the buffer node if attribute value is being parsed
              // e.g. 'div:not([id])[style="position: absolute; z-index: 10000;"]'
              // parser position inside attribute    ↑
              && !context.isAttributeBracketsOpen) {
                bufferNode = getUpdatedBufferNode(context);
              }
              if (isRegularSelectorNode(bufferNode)) {
                // standard selectors with white space between colon and name of pseudo
                // are invalid for native document.querySelectorAll() anyway,
                // so throwing the error here is better
                // than proper parsing of invalid selector and passing it further.
                // first of all do not check attributes
                // e.g. div[style="text-align: center"]
                if (!context.isAttributeBracketsOpen // check the space after the colon and before the pseudo
                // e.g. '.block: nth-child(2)
                && (prevTokenValue === COLON && nextTokenType === TOKEN_TYPE.WORD // or after the pseudo and before the opening parenthesis
                // e.g. '.block:nth-child (2)
                || prevTokenType === TOKEN_TYPE.WORD && nextTokenValue === BRACKET.PARENTHESES.LEFT)) {
                  throw new Error(`'${selector}' is not a valid selector`);
                } // collect current tokenValue to value of RegularSelector
                // if it is the last token or standard selector continues after the space.
                // otherwise it will be skipped

                if (!nextTokenValue || doesRegularContinueAfterSpace(nextTokenType, nextTokenValue) // we also should collect space inside attribute value
                // e.g. `[onclick^="window.open ('https://example.com/share?url="]`
                // parser position             ↑
                || context.isAttributeBracketsOpen) {
                  updateBufferNode(context, tokenValue);
                }
              }
              if (isAbsolutePseudoClassNode(bufferNode)) {
                // space inside extended pseudo-class arg
                // e.g. 'span:contains(some text)'
                updateBufferNode(context, tokenValue);
              }
              if (isRelativePseudoClassNode(bufferNode)) {
                // init with empty value RegularSelector
                // as the space is not needed for selector value
                // e.g. 'p:not( .content )'
                initRelativeSubtree(context);
              }
              if (isSelectorNode(bufferNode)) {
                // do NOT add RegularSelector if parser position on space BEFORE the comma in selector list
                // e.g. '.block:has(> img) , .banner)'
                if (doesRegularContinueAfterSpace(nextTokenType, nextTokenValue)) {
                  // regular selector might be after the extended one.
                  // extra space before combinator or selector should not be collected
                  // e.g. '.banner:upward(2) .block'
                  //      '.banner:upward(2) > .block'
                  // so no tokenValue passed to addAnySelectorNode()
                  addAstNodeByType(context, NODE.REGULAR_SELECTOR);
                }
              }
              break;
            case DESCENDANT_COMBINATOR:
            case CHILD_COMBINATOR:
            case NEXT_SIBLING_COMBINATOR:
            case SUBSEQUENT_SIBLING_COMBINATOR:
            case SEMICOLON:
            case SLASH:
            case BACKSLASH:
            case SINGLE_QUOTE:
            case DOUBLE_QUOTE:
            case CARET:
            case DOLLAR_SIGN:
            case BRACKET.CURLY.LEFT:
            case BRACKET.CURLY.RIGHT:
            case ASTERISK:
            case ID_MARKER:
            case CLASS_MARKER:
            case BRACKET.SQUARE.LEFT:
              // it might be complex selector with extended pseudo-class inside it
              // and the space is between that complex selector and following regular selector
              // e.g. 'div:has(img).banner'   // parser position is on `.` before `banner` now
              //      'div:has(img)[attr]'    // parser position is on `[` before `attr` now
              // so we need to check whether the new ast node should be added (example above)
              // or previous regular selector node should be updated
              if (COMBINATORS.includes(tokenValue)) {
                if (bufferNode === null) {
                  // cases where combinator at very beginning of a selector
                  // e.g. '> div'
                  // or   '~ .banner'
                  // or even '+js(overlay-buster)' which not a selector at all
                  // but may be validated by FilterCompiler so error message should be appropriate
                  throw new Error(`'${selector}' is not a valid selector`);
                }
                bufferNode = getUpdatedBufferNode(context);
              }
              if (bufferNode === null) {
                // no ast collecting has been started
                // e.g. '.banner > p'
                // or   '#top > div.ad'
                // or   '[class][style][attr]'
                // or   '*:not(span)'
                initAst(context, tokenValue);
                if (isAttributeOpening(tokenValue, prevTokenValue)) {
                  // e.g. '[class^="banner-"]'
                  context.isAttributeBracketsOpen = true;
                }
              } else if (isRegularSelectorNode(bufferNode)) {
                if (tokenValue === BRACKET.CURLY.LEFT && !(context.isAttributeBracketsOpen || context.isRegexpOpen)) {
                  // e.g. 'div { content: "'
                  throw new Error(`'${selector}' is not a valid selector`);
                } // collect the mark to the value of RegularSelector node

                updateBufferNode(context, tokenValue);
                if (isAttributeOpening(tokenValue, prevTokenValue)) {
                  // needed for proper handling element attribute value with comma
                  // e.g. 'div[data-comma="0,1"]'
                  context.isAttributeBracketsOpen = true;
                }
              } else if (isAbsolutePseudoClassNode(bufferNode)) {
                // collect the mark to the arg of AbsolutePseudoClass node
                updateBufferNode(context, tokenValue); // 'isRegexpOpen' flag is needed for brackets balancing inside extended pseudo-class arg

                if (tokenValue === SLASH && context.extendedPseudoNamesStack.length > 0) {
                  if (prevTokenValue === SLASH && prevToPrevTokenValue === BACKSLASH) {
                    // it may be specific url regexp pattern in arg of pseudo-class
                    // e.g. ':matches-css(background-image: /^url\(https:\/\/example\.org\//)'
                    // parser position is on final slash before `)`                        ↑
                    context.isRegexpOpen = false;
                  } else if (prevTokenValue && prevTokenValue !== BACKSLASH) {
                    if (isRegexpOpening(context, prevTokenValue, getNodeValue(bufferNode))) {
                      context.isRegexpOpen = !context.isRegexpOpen;
                    } else {
                      // otherwise force `isRegexpOpen` flag to `false`
                      context.isRegexpOpen = false;
                    }
                  }
                }
              } else if (isRelativePseudoClassNode(bufferNode)) {
                // add SelectorList to children of RelativePseudoClass node
                initRelativeSubtree(context, tokenValue);
                if (isAttributeOpening(tokenValue, prevTokenValue)) {
                  // besides of creating the relative subtree
                  // opening square bracket means start of attribute
                  // e.g. 'div:not([class="content"])'
                  //      'div:not([href*="window.print()"])'
                  context.isAttributeBracketsOpen = true;
                }
              } else if (isSelectorNode(bufferNode)) {
                // after the extended pseudo closing parentheses
                // parser position is on Selector node
                // and regular selector can be after the extended one
                // e.g. '.banner:upward(2)> .block'
                // or   '.inner:nth-ancestor(1)~ .banner'
                if (COMBINATORS.includes(tokenValue)) {
                  addAstNodeByType(context, NODE.REGULAR_SELECTOR, tokenValue);
                } else if (!context.isRegexpOpen) {
                  // it might be complex selector with extended pseudo-class inside it.
                  // parser position is on `.` now:
                  // e.g. 'div:has(img).banner'
                  // so we need to get last regular selector node and update its value
                  bufferNode = getContextLastRegularSelectorNode(context);
                  updateBufferNode(context, tokenValue);
                  if (isAttributeOpening(tokenValue, prevTokenValue)) {
                    // handle attribute in compound selector after extended pseudo-class
                    // e.g. 'div:not(.top)[style="z-index: 10000;"]'
                    // parser position    ↑
                    context.isAttributeBracketsOpen = true;
                  }
                }
              } else if (isSelectorListNode(bufferNode)) {
                // add Selector to SelectorList
                addAstNodeByType(context, NODE.SELECTOR); // and RegularSelector as it is always the first child of Selector

                addAstNodeByType(context, NODE.REGULAR_SELECTOR, tokenValue);
                if (isAttributeOpening(tokenValue, prevTokenValue)) {
                  // handle simple attribute selector in selector list
                  // e.g. '.banner, [class^="ad-"]'
                  context.isAttributeBracketsOpen = true;
                }
              }
              break;
            case BRACKET.SQUARE.RIGHT:
              if (isRegularSelectorNode(bufferNode)) {
                // unescaped `]` in regular selector allowed only inside attribute value
                if (!context.isAttributeBracketsOpen && prevTokenValue !== BACKSLASH) {
                  // e.g. 'div]'
                  // eslint-disable-next-line max-len
                  throw new Error(`'${selector}' is not a valid selector due to '${tokenValue}' after '${getNodeValue(bufferNode)}'`);
                } // needed for proper parsing regular selectors after the attributes with comma
                // e.g. 'div[data-comma="0,1"] > img'

                if (isAttributeClosing(context)) {
                  context.isAttributeBracketsOpen = false; // reset attribute buffer on closing `]`

                  context.attributeBuffer = '';
                } // collect the bracket to the value of RegularSelector node

                updateBufferNode(context, tokenValue);
              }
              if (isAbsolutePseudoClassNode(bufferNode)) {
                // :xpath() expended pseudo-class arg might contain square bracket
                // so it should be collected
                // e.g. 'div:xpath(//h3[contains(text(),"Share it!")]/..)'
                updateBufferNode(context, tokenValue);
              }
              break;
            case COLON:
              // No white space is allowed between the colon and the following name of the pseudo-class
              // https://www.w3.org/TR/selectors-4/#pseudo-classes
              // e.g. 'span: contains(text)'
              if (isWhiteSpaceChar(nextTokenValue) && nextToNextTokenValue && SUPPORTED_PSEUDO_CLASSES.includes(nextToNextTokenValue)) {
                throw new Error(`${NO_WHITESPACE_ERROR_PREFIX}: '${selector}'`);
              }
              if (bufferNode === null) {
                // no ast collecting has been started
                if (nextTokenValue === XPATH_PSEUDO_CLASS_MARKER) {
                  // limit applying of "naked" :xpath pseudo-class
                  // https://github.com/AdguardTeam/ExtendedCss/issues/115
                  initAst(context, XPATH_PSEUDO_SELECTING_ROOT);
                } else if (nextTokenValue === UPWARD_PSEUDO_CLASS_MARKER || nextTokenValue === NTH_ANCESTOR_PSEUDO_CLASS_MARKER) {
                  // selector should be specified before :nth-ancestor() or :upward()
                  // e.g. ':nth-ancestor(3)'
                  // or   ':upward(span)'
                  throw new Error(`${NO_SELECTOR_ERROR_PREFIX} before :${nextTokenValue}() pseudo-class`);
                } else {
                  // make it more obvious if selector starts with pseudo with no tag specified
                  // e.g. ':has(a)' -> '*:has(a)'
                  // or   ':empty'  -> '*:empty'
                  initAst(context, ASTERISK);
                } // bufferNode should be updated for following checking

                bufferNode = getBufferNode(context);
              }
              if (isSelectorListNode(bufferNode)) {
                // bufferNode is SelectorList after comma has been parsed.
                // parser position is on colon now:
                // e.g. 'img,:not(.content)'
                addAstNodeByType(context, NODE.SELECTOR); // add empty value RegularSelector anyway as any selector should start with it
                // and check previous token on the next step

                addAstNodeByType(context, NODE.REGULAR_SELECTOR); // bufferNode should be updated for following checking

                bufferNode = getBufferNode(context);
              }
              if (isRegularSelectorNode(bufferNode)) {
                // it can be extended or standard pseudo
                // e.g. '#share, :contains(share it)'
                // or   'div,:hover'
                // of   'div:has(+:contains(text))'  // position is after '+'
                if (prevTokenValue && COMBINATORS.includes(prevTokenValue) || prevTokenValue === COMMA) {
                  // case with colon at the start of string - e.g. ':contains(text)'
                  // is covered by 'bufferNode === null' above at start of COLON checking
                  updateBufferNode(context, ASTERISK);
                }
                handleNextTokenOnColon(context, selector, tokenValue, nextTokenValue, nextToNextTokenValue);
              }
              if (isSelectorNode(bufferNode)) {
                // e.g. 'div:contains(text):'
                if (!nextTokenValue) {
                  throw new Error(`Invalid colon ':' at the end of selector: '${selector}'`);
                } // after the extended pseudo closing parentheses
                // parser position is on Selector node
                // and there is might be another extended selector.
                // parser position is on colon before 'upward':
                // e.g. 'p:contains(PR):upward(2)'

                if (isSupportedPseudoClass(nextTokenValue.toLowerCase())) {
                  // if supported extended pseudo-class is next to colon
                  // add ExtendedSelector to Selector children
                  addAstNodeByType(context, NODE.EXTENDED_SELECTOR);
                } else if (nextTokenValue.toLowerCase() === REMOVE_PSEUDO_MARKER) {
                  // :remove() pseudo-class should be handled before
                  // as it is not about element selecting but actions with elements
                  // e.g. '#banner:upward(2):remove()'
                  throw new Error(`${REMOVE_ERROR_PREFIX.INVALID_REMOVE}: '${selector}'`);
                } else {
                  // otherwise it is standard pseudo after extended pseudo-class in complex selector
                  // and colon should be collected to value of previous RegularSelector
                  // e.g. 'body *:not(input)::selection'
                  //      'input:matches-css(padding: 10):checked'
                  bufferNode = getContextLastRegularSelectorNode(context);
                  handleNextTokenOnColon(context, selector, tokenValue, nextTokenType, nextToNextTokenValue);
                }
              }
              if (isAbsolutePseudoClassNode(bufferNode)) {
                // :xpath() pseudo-class should be the last of extended pseudo-classes
                if (getNodeName(bufferNode) === XPATH_PSEUDO_CLASS_MARKER && nextTokenValue && SUPPORTED_PSEUDO_CLASSES.includes(nextTokenValue) && nextToNextTokenValue === BRACKET.PARENTHESES.LEFT) {
                  throw new Error(`:xpath() pseudo-class should be the last in selector: '${selector}'`);
                } // collecting arg for absolute pseudo-class
                // e.g. 'div:matches-css(width:400px)'

                updateBufferNode(context, tokenValue);
              }
              if (isRelativePseudoClassNode(bufferNode)) {
                if (!nextTokenValue) {
                  // e.g. 'div:has(:'
                  throw new Error(`Invalid pseudo-class arg at the end of selector: '${selector}'`);
                } // make it more obvious if selector starts with pseudo with no tag specified
                // parser position is on colon inside :has() arg
                // e.g. 'div:has(:contains(text))'
                // or   'div:not(:empty)'

                initRelativeSubtree(context, ASTERISK);
                if (!isSupportedPseudoClass(nextTokenValue.toLowerCase())) {
                  // collect the colon to value of RegularSelector
                  // e.g. 'div:not(:empty)'
                  updateBufferNode(context, tokenValue); // parentheses should be balanced only for functional pseudo-classes
                  // e.g. '.yellow:not(:nth-child(3))'

                  if (nextToNextTokenValue === BRACKET.PARENTHESES.LEFT) {
                    context.standardPseudoNamesStack.push(nextTokenValue);
                  }
                } else {
                  // add ExtendedSelector to Selector children
                  // e.g. 'div:has(:contains(text))'
                  upToClosest(context, NODE.SELECTOR);
                  addAstNodeByType(context, NODE.EXTENDED_SELECTOR);
                }
              }
              break;
            case BRACKET.PARENTHESES.LEFT:
              // start of pseudo-class arg
              if (isAbsolutePseudoClassNode(bufferNode)) {
                // no brackets balancing needed inside
                // 1. :xpath() extended pseudo-class arg
                // 2. regexp arg for other extended pseudo-classes
                if (getNodeName(bufferNode) !== XPATH_PSEUDO_CLASS_MARKER && context.isRegexpOpen) {
                  // if the parentheses is escaped it should be part of regexp
                  // collect it to arg of AbsolutePseudoClass
                  // e.g. 'div:matches-css(background-image: /^url\\("data:image\\/gif;base64.+/)'
                  updateBufferNode(context, tokenValue);
                } else {
                  // otherwise brackets should be balanced
                  // e.g. 'div:xpath(//h3[contains(text(),"Share it!")]/..)'
                  context.extendedPseudoBracketsStack.push(tokenValue); // eslint-disable-next-line max-len

                  if (context.extendedPseudoBracketsStack.length > context.extendedPseudoNamesStack.length) {
                    updateBufferNode(context, tokenValue);
                  }
                }
              }
              if (isRegularSelectorNode(bufferNode)) {
                // continue RegularSelector value collecting for standard pseudo-classes
                // e.g. '.banner:where(div)'
                if (context.standardPseudoNamesStack.length > 0) {
                  updateBufferNode(context, tokenValue);
                  context.standardPseudoBracketsStack.push(tokenValue);
                } // parentheses inside attribute value should be part of RegularSelector value
                // e.g. 'div:not([href*="window.print()"])'   <-- parser position
                // is on the `(` after `print`       ↑

                if (context.isAttributeBracketsOpen) {
                  updateBufferNode(context, tokenValue);
                }
              }
              if (isRelativePseudoClassNode(bufferNode)) {
                // save opening bracket for balancing
                // e.g. 'div:not()'  // position is on `(`
                context.extendedPseudoBracketsStack.push(tokenValue);
              }
              break;
            case BRACKET.PARENTHESES.RIGHT:
              if (isAbsolutePseudoClassNode(bufferNode)) {
                // no brackets balancing needed inside
                // 1. :xpath() extended pseudo-class arg
                // 2. regexp arg for other extended pseudo-classes
                if (getNodeName(bufferNode) !== XPATH_PSEUDO_CLASS_MARKER && context.isRegexpOpen) {
                  // if closing bracket is part of regexp
                  // simply save it to pseudo-class arg
                  updateBufferNode(context, tokenValue);
                } else {
                  // remove stacked open parentheses for brackets balance
                  // e.g. 'h3:contains((Ads))'
                  // or   'div:xpath(//h3[contains(text(),"Share it!")]/..)'
                  context.extendedPseudoBracketsStack.pop();
                  if (getNodeName(bufferNode) !== XPATH_PSEUDO_CLASS_MARKER) {
                    // for all other absolute pseudo-classes except :xpath()
                    // remove stacked name of extended pseudo-class
                    context.extendedPseudoNamesStack.pop(); // eslint-disable-next-line max-len

                    if (context.extendedPseudoBracketsStack.length > context.extendedPseudoNamesStack.length) {
                      // if brackets stack is not empty yet,
                      // save tokenValue to arg of AbsolutePseudoClass
                      // parser position on first closing bracket after 'Ads':
                      // e.g. 'h3:contains((Ads))'
                      updateBufferNode(context, tokenValue);
                    } else if (context.extendedPseudoBracketsStack.length >= 0 && context.extendedPseudoNamesStack.length >= 0) {
                      // assume it is combined extended pseudo-classes
                      // parser position on first closing bracket after 'advert':
                      // e.g. 'div:has(.banner, :contains(advert))'
                      upToClosest(context, NODE.SELECTOR);
                    }
                  } else {
                    // for :xpath()
                    // eslint-disable-next-line max-len
                    if (context.extendedPseudoBracketsStack.length < context.extendedPseudoNamesStack.length) {
                      // remove stacked name of extended pseudo-class
                      // if there are less brackets than pseudo-class names
                      // with means last removes bracket was closing for pseudo-class
                      context.extendedPseudoNamesStack.pop();
                    } else {
                      // otherwise the bracket is part of arg
                      updateBufferNode(context, tokenValue);
                    }
                  }
                }
              }
              if (isRegularSelectorNode(bufferNode)) {
                if (context.isAttributeBracketsOpen) {
                  // parentheses inside attribute value should be part of RegularSelector value
                  // e.g. 'div:not([href*="window.print()"])'   <-- parser position
                  // is on the `)` after `print(`       ↑
                  updateBufferNode(context, tokenValue);
                } else if (context.standardPseudoNamesStack.length > 0 && context.standardPseudoBracketsStack.length > 0) {
                  // standard pseudo-class was processing.
                  // collect the closing bracket to value of RegularSelector
                  // parser position is on bracket after 'class' now:
                  // e.g. 'div:where(.class)'
                  updateBufferNode(context, tokenValue); // remove bracket and pseudo name from stacks

                  context.standardPseudoBracketsStack.pop();
                  const lastStandardPseudo = context.standardPseudoNamesStack.pop();
                  if (!lastStandardPseudo) {
                    // standard pseudo should be in standardPseudoNamesStack
                    // as related to standardPseudoBracketsStack
                    throw new Error(`Parsing error. Invalid selector: ${selector}`);
                  } // Disallow :has() after regular pseudo-elements
                  // https://bugs.chromium.org/p/chromium/issues/detail?id=669058#c54 [3]

                  if (Object.values(REGULAR_PSEUDO_ELEMENTS).includes(lastStandardPseudo) // check token which is next to closing parentheses and token after it
                  // parser position is on bracket after 'foo' now:
                  // e.g. '::part(foo):has(.a)'
                  && nextTokenValue === COLON && nextToNextTokenValue && HAS_PSEUDO_CLASS_MARKERS.includes(nextToNextTokenValue)) {
                    // eslint-disable-next-line max-len
                    throw new Error(`Usage of :${nextToNextTokenValue}() pseudo-class is not allowed after any regular pseudo-element: '${lastStandardPseudo}'`);
                  }
                } else {
                  // extended pseudo-class was processing.
                  // e.g. 'div:has(h3)'
                  // remove bracket and pseudo name from stacks
                  context.extendedPseudoBracketsStack.pop();
                  context.extendedPseudoNamesStack.pop();
                  upToClosest(context, NODE.EXTENDED_SELECTOR); // go to upper selector for possible selector continuation after extended pseudo-class
                  // e.g. 'div:has(h3) > img'

                  upToClosest(context, NODE.SELECTOR);
                }
              }
              if (isSelectorNode(bufferNode)) {
                // after inner extended pseudo-class bufferNode is Selector.
                // parser position is on last bracket now:
                // e.g. 'div:has(.banner, :contains(ads))'
                context.extendedPseudoBracketsStack.pop();
                context.extendedPseudoNamesStack.pop();
                upToClosest(context, NODE.EXTENDED_SELECTOR);
                upToClosest(context, NODE.SELECTOR);
              }
              if (isRelativePseudoClassNode(bufferNode)) {
                // save opening bracket for balancing
                // e.g. 'div:not()'  // position is on `)`
                // context.extendedPseudoBracketsStack.push(tokenValue);
                if (context.extendedPseudoNamesStack.length > 0 && context.extendedPseudoBracketsStack.length > 0) {
                  context.extendedPseudoBracketsStack.pop();
                  context.extendedPseudoNamesStack.pop();
                }
              }
              break;
            case LINE_FEED:
            case FORM_FEED:
            case CARRIAGE_RETURN:
              // such characters at start and end of selector should be trimmed
              // so is there is one them among tokens, it is not valid selector
              throw new Error(`'${selector}' is not a valid selector`);
            case TAB:
              // allow tab only inside attribute value
              // as there are such valid rules in filter lists
              // e.g. 'div[style^="margin-right: auto;	text-align: left;',
              // parser position                      ↑
              if (isRegularSelectorNode(bufferNode) && context.isAttributeBracketsOpen) {
                updateBufferNode(context, tokenValue);
              } else {
                // otherwise not valid
                throw new Error(`'${selector}' is not a valid selector`);
              }
          }
          break;
        // no default statement for Marks as they are limited to SUPPORTED_SELECTOR_MARKS
        // and all other symbol combinations are tokenized as Word
        // so error for invalid Word will be thrown later while element selecting by parsed ast

        default:
          throw new Error(`Unknown type of token: '${tokenValue}'`);
      }
      i += 1;
    }
    if (context.ast === null) {
      throw new Error(`'${selector}' is not a valid selector`);
    }
    if (context.extendedPseudoNamesStack.length > 0 || context.extendedPseudoBracketsStack.length > 0) {
      // eslint-disable-next-line max-len
      throw new Error(`Unbalanced brackets for extended pseudo-class: '${getLast(context.extendedPseudoNamesStack)}'`);
    }
    if (context.isAttributeBracketsOpen) {
      throw new Error(`Unbalanced attribute brackets in selector: '${selector}'`);
    }
    return context.shouldOptimize ? optimizeAst(context.ast) : context.ast;
  };
  const natives = {
    MutationObserver: window.MutationObserver || window.WebKitMutationObserver
  };
  /**
   * Class NativeTextContent is needed to intercept and save the native Node textContent getter
   * for proper work of :contains() pseudo-class as it may be mocked.
   *
   * @see {@link https://github.com/AdguardTeam/ExtendedCss/issues/127}
   */

  class NativeTextContent {
    /**
     * Native Node.
     */

    /**
     * Native Node textContent getter.
     */

    /**
     * Stores native node.
     */
    constructor() {
      this.nativeNode = window.Node || Node;
    }
    /**
     * Sets native Node textContext getter to `getter` class field.
     */

    setGetter() {
      var _Object$getOwnPropert;
      this.getter = (_Object$getOwnPropert = Object.getOwnPropertyDescriptor(this.nativeNode.prototype, 'textContent')) === null || _Object$getOwnPropert === void 0 ? void 0 : _Object$getOwnPropert.get;
    }
  }
  const nativeTextContent = new NativeTextContent();

  /**
   * Returns textContent of passed domElement.
   *
   * @param domElement DOM element.
   *
   * @returns DOM element textContent.
   */

  const getNodeTextContent = domElement => {
    if (nativeTextContent.getter) {
      return nativeTextContent.getter.apply(domElement);
    } // if ExtendedCss.init() has not been executed and there is no nodeTextContentGetter,
    // use simple approach, especially when init() is not really needed, e.g. local tests

    return domElement.textContent || '';
  };
  /**
   * Returns element selector text based on it's tagName and attributes.
   *
   * @param element DOM element.
   *
   * @returns String representation of `element`.
   */

  const getElementSelectorDesc = element => {
    let selectorText = element.tagName.toLowerCase();
    selectorText += Array.from(element.attributes).map(attr => {
      return `[${attr.name}="${element.getAttribute(attr.name)}"]`;
    }).join('');
    return selectorText;
  };
  /**
   * Returns path to a DOM element as a selector string.
   *
   * @param inputEl Input element.
   *
   * @returns String path to a DOM element.
   * @throws An error if `inputEl` in not instance of `Element`.
   */

  const getElementSelectorPath = inputEl => {
    if (!(inputEl instanceof Element)) {
      throw new Error('Function received argument with wrong type');
    }
    let el;
    el = inputEl;
    const path = []; // we need to check '!!el' first because it is possible
    // that some ancestor of the inputEl was removed before it

    while (!!el && el.nodeType === Node.ELEMENT_NODE) {
      let selector = el.nodeName.toLowerCase();
      if (el.id && typeof el.id === 'string') {
        selector += `#${el.id}`;
        path.unshift(selector);
        break;
      }
      let sibling = el;
      let nth = 1;
      while (sibling.previousElementSibling) {
        sibling = sibling.previousElementSibling;
        if (sibling.nodeType === Node.ELEMENT_NODE && sibling.nodeName.toLowerCase() === selector) {
          nth += 1;
        }
      }
      if (nth !== 1) {
        selector += `:nth-of-type(${nth})`;
      }
      path.unshift(selector);
      el = el.parentElement;
    }
    return path.join(' > ');
  };
  /**
   * Checks whether the element is instance of HTMLElement.
   *
   * @param element Element to check.
   *
   * @returns True if `element` is HTMLElement.
   */

  const isHtmlElement = element => {
    return element instanceof HTMLElement;
  };
  /**
   * Takes `element` and returns its parent element.
   *
   * @param element Element.
   * @param errorMessage Optional error message to throw.
   *
   * @returns Parent of `element`.
   * @throws An error if element has no parent element.
   */

  const getParent = (element, errorMessage) => {
    const {
      parentElement
    } = element;
    if (!parentElement) {
      throw new Error(errorMessage || 'Element does no have parent element');
    }
    return parentElement;
  };

  /**
   * Checks whether the `error` has `message` property which type is string.
   *
   * @param error Error object.
   *
   * @returns True if `error` has message.
   */
  const isErrorWithMessage = error => {
    return typeof error === 'object' && error !== null && 'message' in error && typeof error.message === 'string';
  };
  /**
   * Converts `maybeError` to error object with message.
   *
   * @param maybeError Possible error.
   *
   * @returns Error object with defined `message` property.
   */

  const toErrorWithMessage = maybeError => {
    if (isErrorWithMessage(maybeError)) {
      return maybeError;
    }
    try {
      return new Error(JSON.stringify(maybeError));
    } catch {
      // fallback in case if there is an error happened during the maybeError stringifying
      // like with circular references for example
      return new Error(String(maybeError));
    }
  };
  /**
   * Returns error message from `error`.
   * May be helpful to handle caught errors.
   *
   * @param error Error object.
   *
   * @returns Message of `error`.
   */

  const getErrorMessage = error => {
    return toErrorWithMessage(error).message;
  };
  const logger = {
    /**
     * Safe console.error version.
     */
    error: typeof console !== 'undefined' && console.error && console.error.bind ? console.error.bind(window.console) : console.error,
    /**
     * Safe console.info version.
     */
    info: typeof console !== 'undefined' && console.info && console.info.bind ? console.info.bind(window.console) : console.info
  };

  /**
   * Returns string without suffix.
   *
   * @param str Input string.
   * @param suffix Needed to remove.
   *
   * @returns String without suffix.
   */

  const removeSuffix = (str, suffix) => {
    const index = str.indexOf(suffix, str.length - suffix.length);
    if (index >= 0) {
      return str.substring(0, index);
    }
    return str;
  };
  /**
   * Replaces all `pattern`s with `replacement` in `input` string.
   * String.replaceAll() polyfill because it is not supported by old browsers, e.g. Chrome 55.
   *
   * @see {@link https://caniuse.com/?search=String.replaceAll}
   *
   * @param input Input string to process.
   * @param pattern Find in the input string.
   * @param replacement Replace the pattern with.
   *
   * @returns Modified string.
   */

  const replaceAll = (input, pattern, replacement) => {
    if (!input) {
      return input;
    }
    return input.split(pattern).join(replacement);
  };
  /**
   * Converts string pattern to regular expression.
   *
   * @param str String to convert.
   *
   * @returns Regular expression converted from pattern `str`.
   */

  const toRegExp = str => {
    if (str.startsWith(SLASH) && str.endsWith(SLASH)) {
      return new RegExp(str.slice(1, -1));
    }
    const escaped = str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    return new RegExp(escaped);
  };
  /**
   * Converts any simple type value to string type,
   * e.g. `undefined` -> `'undefined'`.
   *
   * @param value Any type value.
   *
   * @returns String representation of `value`.
   */

  const convertTypeIntoString = value => {
    let output;
    switch (value) {
      case undefined:
        output = 'undefined';
        break;
      case null:
        output = 'null';
        break;
      default:
        output = value.toString();
    }
    return output;
  };
  /**
   * Converts instance of string value into other simple types,
   * e.g. `'null'` -> `null`, `'true'` -> `true`.
   *
   * @param value String-type value.
   *
   * @returns Its own type representation of string-type `value`.
   */

  const convertTypeFromString = value => {
    const numValue = Number(value);
    let output;
    if (!Number.isNaN(numValue)) {
      output = numValue;
    } else {
      switch (value) {
        case 'undefined':
          output = undefined;
          break;
        case 'null':
          output = null;
          break;
        case 'true':
          output = true;
          break;
        case 'false':
          output = false;
          break;
        default:
          output = value;
      }
    }
    return output;
  };
  const SAFARI_USER_AGENT_REGEXP = /\sVersion\/(\d{2}\.\d)(.+\s|\s)(Safari)\//;
  const isSafariBrowser = SAFARI_USER_AGENT_REGEXP.test(navigator.userAgent);
  /**
   * Checks whether the browser userAgent is supported.
   *
   * @param userAgent User agent of browser.
   *
   * @returns False only for Internet Explorer.
   */

  const isUserAgentSupported = userAgent => {
    // do not support Internet Explorer
    if (userAgent.includes('MSIE') || userAgent.includes('Trident/')) {
      return false;
    }
    return true;
  };
  /**
   * Checks whether the current browser is supported.
   *
   * @returns False for Internet Explorer, otherwise true.
   */

  const isBrowserSupported = () => {
    return isUserAgentSupported(navigator.userAgent);
  };

  /**
   * CSS_PROPERTY is needed for style values normalization.
   *
   * IMPORTANT: it is used as 'const' instead of 'enum' to avoid side effects
   * during ExtendedCss import into other libraries.
   */

  const CSS_PROPERTY = {
    BACKGROUND: 'background',
    BACKGROUND_IMAGE: 'background-image',
    CONTENT: 'content',
    OPACITY: 'opacity'
  };
  const REGEXP_ANY_SYMBOL = '.*';
  const REGEXP_WITH_FLAGS_REGEXP = /^\s*\/.*\/[gmisuy]*\s*$/;

  /**
   * Removes quotes for specified content value.
   *
   * For example, content style declaration with `::before` can be set as '-' (e.g. unordered list)
   * which displayed as simple dash `-` with no quotes.
   * But CSSStyleDeclaration.getPropertyValue('content') will return value
   * wrapped into quotes, e.g. '"-"', which should be removed
   * because filters maintainers does not use any quotes in real rules.
   *
   * @param str Input string.
   *
   * @returns String with no quotes for content value.
   */
  const removeContentQuotes = str => {
    return str.replace(/^(["'])([\s\S]*)\1$/, '$2');
  };
  /**
   * Adds quotes for specified background url value.
   *
   * If background-image is specified **without** quotes:
   * e.g. 'background: url(data:image/gif;base64,R0lGODlhAQA7)'.
   *
   * CSSStyleDeclaration.getPropertyValue('background-image') may return value **with** quotes:
   * e.g. 'background: url("data:image/gif;base64,R0lGODlhAQA7")'.
   *
   * So we add quotes for compatibility since filters maintainers might use quotes in real rules.
   *
   * @param str Input string.
   *
   * @returns String with unified quotes for background url value.
   */

  const addUrlPropertyQuotes = str => {
    if (!str.includes('url("')) {
      const re = /url\((.*?)\)/g;
      return str.replace(re, 'url("$1")');
    }
    return str;
  };
  /**
   * Adds quotes to url arg for consistent property value matching.
   */

  const addUrlQuotesTo = {
    regexpArg: str => {
      // e.g. /^url\\([a-z]{4}:[a-z]{5}/
      // or /^url\\(data\\:\\image\\/gif;base64.+/
      const re = /(\^)?url(\\)?\\\((\w|\[\w)/g;
      return str.replace(re, '$1url$2\\(\\"?$3');
    },
    noneRegexpArg: addUrlPropertyQuotes
  };
  /**
   * Escapes regular expression string.
   *
   * @see {@link https://developer.mozilla.org/en/JavaScript/Reference/Global_Objects/regexp}
   *
   * @param str Input string.
   *
   * @returns Escaped regular expression string.
   */

  const escapeRegExp = str => {
    // should be escaped . * + ? ^ $ { } ( ) | [ ] / \
    // except of * | ^
    const specials = ['.', '+', '?', '$', '{', '}', '(', ')', '[', ']', '\\', '/'];
    const specialsRegex = new RegExp(`[${specials.join('\\')}]`, 'g');
    return str.replace(specialsRegex, '\\$&');
  };
  /**
   * Converts :matches-css() arg property value match to regexp.
   *
   * @param rawValue Style match value pattern.
   *
   * @returns Arg of :matches-css() converted to regular expression.
   */

  const convertStyleMatchValueToRegexp = rawValue => {
    let value;
    if (rawValue.startsWith(SLASH) && rawValue.endsWith(SLASH)) {
      // For regex patterns double quotes `"` and backslashes `\` should be escaped
      value = addUrlQuotesTo.regexpArg(rawValue);
      value = value.slice(1, -1);
    } else {
      // For non-regex patterns parentheses `(` `)` and square brackets `[` `]`
      // should be unescaped, because their escaping in filter rules is required
      value = addUrlQuotesTo.noneRegexpArg(rawValue);
      value = value.replace(/\\([\\()[\]"])/g, '$1');
      value = escapeRegExp(value); // e.g. div:matches-css(background-image: url(data:*))

      value = replaceAll(value, ASTERISK, REGEXP_ANY_SYMBOL);
    }
    return new RegExp(value, 'i');
  };
  /**
   * Makes some properties values compatible.
   *
   * @param propertyName Name of style property.
   * @param propertyValue Value of style property.
   *
   * @returns Normalized values for some CSS properties.
   */

  const normalizePropertyValue = (propertyName, propertyValue) => {
    let normalized = '';
    switch (propertyName) {
      case CSS_PROPERTY.BACKGROUND:
      case CSS_PROPERTY.BACKGROUND_IMAGE:
        // sometimes url property does not have quotes
        // so we add them for consistent matching
        normalized = addUrlPropertyQuotes(propertyValue);
        break;
      case CSS_PROPERTY.CONTENT:
        normalized = removeContentQuotes(propertyValue);
        break;
      case CSS_PROPERTY.OPACITY:
        // https://bugs.webkit.org/show_bug.cgi?id=93445
        normalized = isSafariBrowser ? (Math.round(parseFloat(propertyValue) * 100) / 100).toString() : propertyValue;
        break;
      default:
        normalized = propertyValue;
    }
    return normalized;
  };
  /**
   * Returns domElement style property value
   * by css property name and standard pseudo-element.
   *
   * @param domElement DOM element.
   * @param propertyName CSS property name.
   * @param regularPseudoElement Standard pseudo-element — '::before', '::after' etc.
   *
   * @returns String containing the value of a specified CSS property.
   */

  const getComputedStylePropertyValue = (domElement, propertyName, regularPseudoElement) => {
    const style = window.getComputedStyle(domElement, regularPseudoElement);
    const propertyValue = style.getPropertyValue(propertyName);
    return normalizePropertyValue(propertyName, propertyValue);
  };

  /**
   * Parses arg of absolute pseudo-class into 'name' and 'value' if set.
   *
   * Used for :matches-css() - with COLON as separator,
   * for :matches-attr() and :matches-property() - with EQUAL_SIGN as separator.
   *
   * @param pseudoArg Arg of pseudo-class.
   * @param separator Divider symbol.
   *
   * @returns Parsed 'matches' pseudo-class arg data.
   */
  const getPseudoArgData = (pseudoArg, separator) => {
    const index = pseudoArg.indexOf(separator);
    let name;
    let value;
    if (index > -1) {
      name = pseudoArg.substring(0, index).trim();
      value = pseudoArg.substring(index + 1).trim();
    } else {
      name = pseudoArg;
    }
    return {
      name,
      value
    };
  };

  /**
   * Parses :matches-css() pseudo-class arg
   * where regular pseudo-element can be a part of arg
   * e.g. 'div:matches-css(before, color: rgb(255, 255, 255))'    <-- obsolete `:matches-css-before()`.
   *
   * @param pseudoName Pseudo-class name.
   * @param rawArg Pseudo-class arg.
   *
   * @returns Parsed :matches-css() pseudo-class arg data.
   * @throws An error on invalid `rawArg`.
   */
  const parseStyleMatchArg = (pseudoName, rawArg) => {
    const {
      name,
      value
    } = getPseudoArgData(rawArg, COMMA);
    let regularPseudoElement = name;
    let styleMatchArg = value; // check whether the string part before the separator is valid regular pseudo-element,
    // otherwise `regularPseudoElement` is null, and `styleMatchArg` is rawArg

    if (!Object.values(REGULAR_PSEUDO_ELEMENTS).includes(name)) {
      regularPseudoElement = null;
      styleMatchArg = rawArg;
    }
    if (!styleMatchArg) {
      throw new Error(`Required style property argument part is missing in :${pseudoName}() arg: '${rawArg}'`);
    } // if regularPseudoElement is not `null`

    if (regularPseudoElement) {
      // pseudo-element should have two colon marks for Window.getComputedStyle() due to the syntax:
      // https://www.w3.org/TR/selectors-4/#pseudo-element-syntax
      // ':matches-css(before, content: ads)' ->> '::before'
      regularPseudoElement = `${COLON}${COLON}${regularPseudoElement}`;
    }
    return {
      regularPseudoElement,
      styleMatchArg
    };
  };
  /**
   * Checks whether the domElement is matched by :matches-css() arg.
   *
   * @param argsData Pseudo-class name, arg, and dom element to check.
   *
   @returns True if DOM element is matched.
   * @throws An error on invalid pseudo-class arg.
   */

  const isStyleMatched = argsData => {
    const {
      pseudoName,
      pseudoArg,
      domElement
    } = argsData;
    const {
      regularPseudoElement,
      styleMatchArg
    } = parseStyleMatchArg(pseudoName, pseudoArg);
    const {
      name: matchName,
      value: matchValue
    } = getPseudoArgData(styleMatchArg, COLON);
    if (!matchName || !matchValue) {
      throw new Error(`Required property name or value is missing in :${pseudoName}() arg: '${styleMatchArg}'`);
    }
    let valueRegexp;
    try {
      valueRegexp = convertStyleMatchValueToRegexp(matchValue);
    } catch (e) {
      logger.error(getErrorMessage(e));
      throw new Error(`Invalid argument of :${pseudoName}() pseudo-class: '${styleMatchArg}'`);
    }
    const value = getComputedStylePropertyValue(domElement, matchName, regularPseudoElement);
    return valueRegexp && valueRegexp.test(value);
  };
  /**
   * Validates string arg for :matches-attr() and :matches-property().
   *
   * @param arg Pseudo-class arg.
   *
   * @returns True if 'matches' pseudo-class string arg is valid.
   */

  const validateStrMatcherArg = arg => {
    if (arg.includes(SLASH)) {
      return false;
    }
    if (!/^[\w-]+$/.test(arg)) {
      return false;
    }
    return true;
  };
  /**
   * Returns valid arg for :matches-attr() and :matcher-property().
   *
   * @param rawArg Arg pattern.
   * @param [isWildcardAllowed=false] Flag for wildcard (`*`) using as pseudo-class arg.
   *
   * @returns Valid arg for :matches-attr() and :matcher-property().
   * @throws An error on invalid `rawArg`.
   */

  const getValidMatcherArg = function (rawArg) {
    let isWildcardAllowed = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : false;
    // if rawArg is missing for pseudo-class
    // e.g. :matches-attr()
    // error will be thrown before getValidMatcherArg() is called:
    // name or arg is missing in AbsolutePseudoClass
    let arg;
    if (rawArg.length > 1 && rawArg.startsWith(DOUBLE_QUOTE) && rawArg.endsWith(DOUBLE_QUOTE)) {
      rawArg = rawArg.slice(1, -1);
    }
    if (rawArg === '') {
      // e.g. :matches-property("")
      throw new Error('Argument should be specified. Empty arg is invalid.');
    }
    if (rawArg.startsWith(SLASH) && rawArg.endsWith(SLASH)) {
      // e.g. :matches-property("//")
      if (rawArg.length > 2) {
        arg = toRegExp(rawArg);
      } else {
        throw new Error(`Invalid regexp: '${rawArg}'`);
      }
    } else if (rawArg.includes(ASTERISK)) {
      if (rawArg === ASTERISK && !isWildcardAllowed) {
        // e.g. :matches-attr(*)
        throw new Error(`Argument should be more specific than ${rawArg}`);
      }
      arg = replaceAll(rawArg, ASTERISK, REGEXP_ANY_SYMBOL);
      arg = new RegExp(arg);
    } else {
      if (!validateStrMatcherArg(rawArg)) {
        throw new Error(`Invalid argument: '${rawArg}'`);
      }
      arg = rawArg;
    }
    return arg;
  };

  /**
   * Parses pseudo-class argument and returns parsed data.
   *
   * @param pseudoName Extended pseudo-class name.
   * @param pseudoArg Extended pseudo-class argument.
   *
   * @returns Parsed pseudo-class argument data.
   * @throws An error if attribute name is missing in pseudo-class arg.
   */
  const getRawMatchingData = (pseudoName, pseudoArg) => {
    const {
      name: rawName,
      value: rawValue
    } = getPseudoArgData(pseudoArg, EQUAL_SIGN);
    if (!rawName) {
      throw new Error(`Required attribute name is missing in :${pseudoName} arg: ${pseudoArg}`);
    }
    return {
      rawName,
      rawValue
    };
  };
  /**
   * Checks whether the domElement is matched by :matches-attr() arg.
   *
   * @param argsData Pseudo-class name, arg, and dom element to check.
   *
   @returns True if DOM element is matched.
   * @throws An error on invalid arg of pseudo-class.
   */

  const isAttributeMatched = argsData => {
    const {
      pseudoName,
      pseudoArg,
      domElement
    } = argsData;
    const elementAttributes = domElement.attributes; // no match if dom element has no attributes

    if (elementAttributes.length === 0) {
      return false;
    }
    const {
      rawName: rawAttrName,
      rawValue: rawAttrValue
    } = getRawMatchingData(pseudoName, pseudoArg);
    let attrNameMatch;
    try {
      attrNameMatch = getValidMatcherArg(rawAttrName);
    } catch (e) {
      const errorMessage = getErrorMessage(e);
      logger.error(errorMessage);
      throw new SyntaxError(errorMessage);
    }
    let isMatched = false;
    let i = 0;
    while (i < elementAttributes.length && !isMatched) {
      const attr = elementAttributes[i];
      if (!attr) {
        break;
      }
      const isNameMatched = attrNameMatch instanceof RegExp ? attrNameMatch.test(attr.name) : attrNameMatch === attr.name;
      if (!rawAttrValue) {
        // for rules with no attribute value specified
        // e.g. :matches-attr("/regex/") or :matches-attr("attr-name")
        isMatched = isNameMatched;
      } else {
        let attrValueMatch;
        try {
          attrValueMatch = getValidMatcherArg(rawAttrValue);
        } catch (e) {
          const errorMessage = getErrorMessage(e);
          logger.error(errorMessage);
          throw new SyntaxError(errorMessage);
        }
        const isValueMatched = attrValueMatch instanceof RegExp ? attrValueMatch.test(attr.value) : attrValueMatch === attr.value;
        isMatched = isNameMatched && isValueMatched;
      }
      i += 1;
    }
    return isMatched;
  };
  /**
   * Parses raw :matches-property() arg which may be chain of properties.
   *
   * @param input Argument of :matches-property().
   *
   * @returns Arg of :matches-property() as array of strings or regular expressions.
   * @throws An error on invalid chain.
   */

  const parseRawPropChain = input => {
    if (input.length > 1 && input.startsWith(DOUBLE_QUOTE) && input.endsWith(DOUBLE_QUOTE)) {
      input = input.slice(1, -1);
    }
    const chainChunks = input.split(DOT);
    const chainPatterns = [];
    let patternBuffer = '';
    let isRegexpPattern = false;
    let i = 0;
    while (i < chainChunks.length) {
      const chunk = getItemByIndex(chainChunks, i, `Invalid pseudo-class arg: '${input}'`);
      if (chunk.startsWith(SLASH) && chunk.endsWith(SLASH) && chunk.length > 2) {
        // regexp pattern with no dot in it, e.g. /propName/
        chainPatterns.push(chunk);
      } else if (chunk.startsWith(SLASH)) {
        // if chunk is a start of regexp pattern
        isRegexpPattern = true;
        patternBuffer += chunk;
      } else if (chunk.endsWith(SLASH)) {
        isRegexpPattern = false; // restore dot removed while splitting
        // e.g. testProp./.{1,5}/

        patternBuffer += `.${chunk}`;
        chainPatterns.push(patternBuffer);
        patternBuffer = '';
      } else {
        // if there are few dots in regexp pattern
        // so chunk might be in the middle of it
        if (isRegexpPattern) {
          patternBuffer += chunk;
        } else {
          // otherwise it is string pattern
          chainPatterns.push(chunk);
        }
      }
      i += 1;
    }
    if (patternBuffer.length > 0) {
      throw new Error(`Invalid regexp property pattern '${input}'`);
    }
    const chainMatchPatterns = chainPatterns.map(pattern => {
      if (pattern.length === 0) {
        // e.g. '.prop.id' or 'nested..test'
        throw new Error(`Empty pattern '${pattern}' is invalid in chain '${input}'`);
      }
      let validPattern;
      try {
        validPattern = getValidMatcherArg(pattern, true);
      } catch (e) {
        logger.error(getErrorMessage(e));
        throw new Error(`Invalid property pattern '${pattern}' in property chain '${input}'`);
      }
      return validPattern;
    });
    return chainMatchPatterns;
  };

  /**
   * Checks if the property exists in the base object (recursively).
   *
   * @param base Element to check.
   * @param chain Array of objects - parsed string property chain.
   * @param [output=[]] Result acc.
   *
   * @returns Array of parsed data — representation of `base`-related `chain`.
   */
  const filterRootsByRegexpChain = function (base, chain) {
    let output = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : [];
    const tempProp = getFirst(chain);
    if (chain.length === 1) {
      let key;
      for (key in base) {
        if (tempProp instanceof RegExp) {
          if (tempProp.test(key)) {
            output.push({
              base,
              prop: key,
              value: base[key]
            });
          }
        } else if (tempProp === key) {
          output.push({
            base,
            prop: tempProp,
            value: base[key]
          });
        }
      }
      return output;
    } // if there is a regexp prop in input chain
    // e.g. 'unit./^ad.+/.src' for 'unit.ad-1gf2.src unit.ad-fgd34.src'),
    // every base keys should be tested by regexp and it can be more that one results

    if (tempProp instanceof RegExp) {
      const nextProp = chain.slice(1);
      const baseKeys = [];
      for (const key in base) {
        if (tempProp.test(key)) {
          baseKeys.push(key);
        }
      }
      baseKeys.forEach(key => {
        var _Object$getOwnPropert;
        const item = (_Object$getOwnPropert = Object.getOwnPropertyDescriptor(base, key)) === null || _Object$getOwnPropert === void 0 ? void 0 : _Object$getOwnPropert.value;
        filterRootsByRegexpChain(item, nextProp, output);
      });
    }
    if (base && typeof tempProp === 'string') {
      var _Object$getOwnPropert2;
      const nextBase = (_Object$getOwnPropert2 = Object.getOwnPropertyDescriptor(base, tempProp)) === null || _Object$getOwnPropert2 === void 0 ? void 0 : _Object$getOwnPropert2.value;
      chain = chain.slice(1);
      if (nextBase !== undefined) {
        filterRootsByRegexpChain(nextBase, chain, output);
      }
    }
    return output;
  };
  /**
   * Checks whether the domElement is matched by :matches-property() arg.
   *
   * @param argsData Pseudo-class name, arg, and dom element to check.
   *
   @returns True if DOM element is matched.
   * @throws An error on invalid prop in chain.
   */

  const isPropertyMatched = argsData => {
    const {
      pseudoName,
      pseudoArg,
      domElement
    } = argsData;
    const {
      rawName: rawPropertyName,
      rawValue: rawPropertyValue
    } = getRawMatchingData(pseudoName, pseudoArg); // chained property name cannot include '/' or '.'
    // so regex prop names with such escaped characters are invalid

    if (rawPropertyName.includes('\\/') || rawPropertyName.includes('\\.')) {
      throw new Error(`Invalid :${pseudoName} name pattern: ${rawPropertyName}`);
    }
    let propChainMatches;
    try {
      propChainMatches = parseRawPropChain(rawPropertyName);
    } catch (e) {
      const errorMessage = getErrorMessage(e);
      logger.error(errorMessage);
      throw new SyntaxError(errorMessage);
    }
    const ownerObjArr = filterRootsByRegexpChain(domElement, propChainMatches);
    if (ownerObjArr.length === 0) {
      return false;
    }
    let isMatched = true;
    if (rawPropertyValue) {
      let propValueMatch;
      try {
        propValueMatch = getValidMatcherArg(rawPropertyValue);
      } catch (e) {
        const errorMessage = getErrorMessage(e);
        logger.error(errorMessage);
        throw new SyntaxError(errorMessage);
      }
      if (propValueMatch) {
        for (let i = 0; i < ownerObjArr.length; i += 1) {
          var _ownerObjArr$i;
          const realValue = (_ownerObjArr$i = ownerObjArr[i]) === null || _ownerObjArr$i === void 0 ? void 0 : _ownerObjArr$i.value;
          if (propValueMatch instanceof RegExp) {
            isMatched = propValueMatch.test(convertTypeIntoString(realValue));
          } else {
            // handle 'null' and 'undefined' property values set as string
            if (realValue === 'null' || realValue === 'undefined') {
              isMatched = propValueMatch === realValue;
              break;
            }
            isMatched = convertTypeFromString(propValueMatch) === realValue;
          }
          if (isMatched) {
            break;
          }
        }
      }
    }
    return isMatched;
  };
  /**
   * Checks whether the textContent is matched by :contains arg.
   *
   * @param argsData Pseudo-class name, arg, and dom element to check.
   *
   @returns True if DOM element is matched.
   * @throws An error on invalid arg of pseudo-class.
   */

  const isTextMatched = argsData => {
    const {
      pseudoName,
      pseudoArg,
      domElement
    } = argsData;
    const textContent = getNodeTextContent(domElement);
    let isTextContentMatched;
    let pseudoArgToMatch = pseudoArg;
    if (pseudoArgToMatch.startsWith(SLASH) && REGEXP_WITH_FLAGS_REGEXP.test(pseudoArgToMatch)) {
      // regexp arg
      const flagsIndex = pseudoArgToMatch.lastIndexOf('/');
      const flagsStr = pseudoArgToMatch.substring(flagsIndex + 1);
      pseudoArgToMatch = pseudoArgToMatch.substring(0, flagsIndex + 1).slice(1, -1).replace(/\\([\\"])/g, '$1');
      let regex;
      try {
        regex = new RegExp(pseudoArgToMatch, flagsStr);
      } catch (e) {
        throw new Error(`Invalid argument of :${pseudoName}() pseudo-class: ${pseudoArg}`);
      }
      isTextContentMatched = regex.test(textContent);
    } else {
      // none-regexp arg
      pseudoArgToMatch = pseudoArgToMatch.replace(/\\([\\()[\]"])/g, '$1');
      isTextContentMatched = textContent.includes(pseudoArgToMatch);
    }
    return isTextContentMatched;
  };

  /**
   * Validates number arg for :nth-ancestor() and :upward() pseudo-classes.
   *
   * @param rawArg Raw arg of pseudo-class.
   * @param pseudoName Pseudo-class name.
   *
   * @returns Valid number arg for :nth-ancestor() and :upward().
   * @throws An error on invalid `rawArg`.
   */
  const getValidNumberAncestorArg = (rawArg, pseudoName) => {
    const deep = Number(rawArg);
    if (Number.isNaN(deep) || deep < 1 || deep >= 256) {
      throw new Error(`Invalid argument of :${pseudoName} pseudo-class: '${rawArg}'`);
    }
    return deep;
  };
  /**
   * Returns nth ancestor by 'deep' number arg OR undefined if ancestor range limit exceeded.
   *
   * @param domElement DOM element to find ancestor for.
   * @param nth Depth up to needed ancestor.
   * @param pseudoName Pseudo-class name.
   *
   * @returns Ancestor element found in DOM, or null if not found.
   * @throws An error on invalid `nth` arg.
   */

  const getNthAncestor = (domElement, nth, pseudoName) => {
    let ancestor = null;
    let i = 0;
    while (i < nth) {
      ancestor = domElement.parentElement;
      if (!ancestor) {
        throw new Error(`Out of DOM: Argument of :${pseudoName}() pseudo-class is too big — '${nth}'.`);
      }
      domElement = ancestor;
      i += 1;
    }
    return ancestor;
  };
  /**
   * Validates standard CSS selector.
   *
   * @param selector Standard selector.
   *
   * @returns True if standard CSS selector is valid.
   */

  const validateStandardSelector = selector => {
    let isValid;
    try {
      document.querySelectorAll(selector);
      isValid = true;
    } catch (e) {
      isValid = false;
    }
    return isValid;
  };

  /**
   * Wrapper to run matcher `callback` with `args`
   * and throw error with `errorMessage` if `callback` run fails.
   *
   * @param callback Matcher callback.
   * @param argsData Args needed for matcher callback.
   * @param errorMessage Error message.
   *
   * @returns True if `callback` returns true.
   * @throws An error if `callback` fails.
   */
  const matcherWrapper = (callback, argsData, errorMessage) => {
    let isMatched;
    try {
      isMatched = callback(argsData);
    } catch (e) {
      logger.error(getErrorMessage(e));
      throw new Error(errorMessage);
    }
    return isMatched;
  };
  /**
   * Generates common error message to throw while matching element `propDesc`.
   *
   * @param propDesc Text to describe what element 'prop' pseudo-class is trying to match.
   * @param pseudoName Pseudo-class name.
   * @param pseudoArg Pseudo-class arg.
   *
   * @returns Generated error message string.
   */

  const getAbsolutePseudoError = (propDesc, pseudoName, pseudoArg) => {
    // eslint-disable-next-line max-len
    return `${MATCHING_ELEMENT_ERROR_PREFIX} ${propDesc}, may be invalid :${pseudoName}() pseudo-class arg: '${pseudoArg}'`;
  };
  /**
   * Checks whether the domElement is matched by absolute extended pseudo-class argument.
   *
   * @param domElement Page element.
   * @param pseudoName Pseudo-class name.
   * @param pseudoArg Pseudo-class arg.
   *
   * @returns True if `domElement` is matched by absolute pseudo-class.
   * @throws An error on unknown absolute pseudo-class.
   */

  const isMatchedByAbsolutePseudo = (domElement, pseudoName, pseudoArg) => {
    let argsData;
    let errorMessage;
    let callback;
    switch (pseudoName) {
      case CONTAINS_PSEUDO:
      case HAS_TEXT_PSEUDO:
      case ABP_CONTAINS_PSEUDO:
        callback = isTextMatched;
        argsData = {
          pseudoName,
          pseudoArg,
          domElement
        };
        errorMessage = getAbsolutePseudoError('text content', pseudoName, pseudoArg);
        break;
      case MATCHES_CSS_PSEUDO:
      case MATCHES_CSS_AFTER_PSEUDO:
      case MATCHES_CSS_BEFORE_PSEUDO:
        callback = isStyleMatched;
        argsData = {
          pseudoName,
          pseudoArg,
          domElement
        };
        errorMessage = getAbsolutePseudoError('style', pseudoName, pseudoArg);
        break;
      case MATCHES_ATTR_PSEUDO_CLASS_MARKER:
        callback = isAttributeMatched;
        argsData = {
          domElement,
          pseudoName,
          pseudoArg
        };
        errorMessage = getAbsolutePseudoError('attributes', pseudoName, pseudoArg);
        break;
      case MATCHES_PROPERTY_PSEUDO_CLASS_MARKER:
        callback = isPropertyMatched;
        argsData = {
          domElement,
          pseudoName,
          pseudoArg
        };
        errorMessage = getAbsolutePseudoError('properties', pseudoName, pseudoArg);
        break;
      default:
        throw new Error(`Unknown absolute pseudo-class :${pseudoName}()`);
    }
    return matcherWrapper(callback, argsData, errorMessage);
  };
  const findByAbsolutePseudoPseudo = {
    /**
     * Returns list of nth ancestors relative to every dom node from domElements list.
     *
     * @param domElements DOM elements.
     * @param rawPseudoArg Number arg of :nth-ancestor() or :upward() pseudo-class.
     * @param pseudoName Pseudo-class name.
     *
     * @returns Array of ancestor DOM elements.
     */
    nthAncestor: (domElements, rawPseudoArg, pseudoName) => {
      const deep = getValidNumberAncestorArg(rawPseudoArg, pseudoName);
      const ancestors = domElements.map(domElement => {
        let ancestor = null;
        try {
          ancestor = getNthAncestor(domElement, deep, pseudoName);
        } catch (e) {
          logger.error(getErrorMessage(e));
        }
        return ancestor;
      }).filter(isHtmlElement);
      return ancestors;
    },
    /**
     * Returns list of elements by xpath expression, evaluated on every dom node from domElements list.
     *
     * @param domElements DOM elements.
     * @param rawPseudoArg Arg of :xpath() pseudo-class.
     *
     * @returns Array of DOM elements matched by xpath expression.
     */
    xpath: (domElements, rawPseudoArg) => {
      const foundElements = domElements.map(domElement => {
        const result = [];
        let xpathResult;
        try {
          xpathResult = document.evaluate(rawPseudoArg, domElement, null, window.XPathResult.UNORDERED_NODE_ITERATOR_TYPE, null);
        } catch (e) {
          logger.error(getErrorMessage(e));
          throw new Error(`Invalid argument of :xpath() pseudo-class: '${rawPseudoArg}'`);
        }
        let node = xpathResult.iterateNext();
        while (node) {
          if (isHtmlElement(node)) {
            result.push(node);
          }
          node = xpathResult.iterateNext();
        }
        return result;
      });
      return flatten(foundElements);
    },
    /**
     * Returns list of closest ancestors relative to every dom node from domElements list.
     *
     * @param domElements DOM elements.
     * @param rawPseudoArg Standard selector arg of :upward() pseudo-class.
     *
     * @returns Array of closest ancestor DOM elements.
     * @throws An error if `rawPseudoArg` is not a valid standard selector.
     */
    upward: (domElements, rawPseudoArg) => {
      if (!validateStandardSelector(rawPseudoArg)) {
        throw new Error(`Invalid argument of :upward pseudo-class: '${rawPseudoArg}'`);
      }
      const closestAncestors = domElements.map(domElement => {
        // closest to parent element should be found
        // otherwise `.base:upward(.base)` will return itself too, not only ancestor
        const parent = domElement.parentElement;
        if (!parent) {
          return null;
        }
        return parent.closest(rawPseudoArg);
      }).filter(isHtmlElement);
      return closestAncestors;
    }
  };

  /**
   * Calculated selector text which is needed to :has(), :is() and :not() pseudo-classes.
   * Contains calculated part (depends on the processed element)
   * and value of RegularSelector which is next to selector by.
   *
   * Native Document.querySelectorAll() does not select exact descendant elements
   * but match all page elements satisfying the selector,
   * so extra specification is needed for proper descendants selection
   * e.g. 'div:has(> img)'.
   *
   * Its calculation depends on extended selector.
   */

  /**
   * Combined `:scope` pseudo-class and **child** combinator — `:scope>`.
   */
  const scopeDirectChildren = `${SCOPE_CSS_PSEUDO_CLASS}${CHILD_COMBINATOR}`;
  /**
   * Combined `:scope` pseudo-class and **descendant** combinator — `:scope `.
   */

  const scopeAnyChildren = `${SCOPE_CSS_PSEUDO_CLASS}${DESCENDANT_COMBINATOR}`;
  /**
   * Type for relative pseudo-class helpers args.
   */

  /**
   * Returns the first of RegularSelector child node for `selectorNode`.
   *
   * @param selectorNode Ast Selector node.
   * @param pseudoName Name of relative pseudo-class.
   *
   * @returns Ast RegularSelector node.
   */
  const getFirstInnerRegularChild = (selectorNode, pseudoName) => {
    return getFirstRegularChild(selectorNode.children, `RegularSelector is missing for :${pseudoName}() pseudo-class`);
  }; // TODO: fix for <forgiving-relative-selector-list>
  // https://github.com/AdguardTeam/ExtendedCss/issues/154

  /**
   * Checks whether the element has all relative elements specified by pseudo-class arg.
   * Used for :has() pseudo-class.
   *
   * @param argsData Relative pseudo-class helpers args data.
   *
   * @returns True if **all selectors** from argsData.relativeSelectorList is **matched** for argsData.element.
   */

  const hasRelativesBySelectorList = argsData => {
    const {
      element,
      relativeSelectorList,
      pseudoName
    } = argsData;
    return relativeSelectorList.children // Array.every() is used here as each Selector node from SelectorList should exist on page
    .every(selectorNode => {
      // selectorList.children always starts with regular selector as any selector generally
      const relativeRegularSelector = getFirstInnerRegularChild(selectorNode, pseudoName);
      let specifiedSelector = '';
      let rootElement = null;
      const regularSelector = getNodeValue(relativeRegularSelector);
      if (regularSelector.startsWith(NEXT_SIBLING_COMBINATOR) || regularSelector.startsWith(SUBSEQUENT_SIBLING_COMBINATOR)) {
        /**
         * For matching the element by "element:has(+ next-sibling)" and "element:has(~ sibling)"
         * we check whether the element's parentElement has specific direct child combination,
         * e.g. 'h1:has(+ .share)' -> `h1Node.parentElement.querySelectorAll(':scope > h1 + .share')`.
         *
         * @see {@link https://www.w3.org/TR/selectors-4/#relational}
         */
        rootElement = element.parentElement;
        const elementSelectorText = getElementSelectorDesc(element);
        specifiedSelector = `${scopeDirectChildren}${elementSelectorText}${regularSelector}`;
      } else if (regularSelector === ASTERISK) {
        /**
         * :scope specification is needed for proper descendants selection
         * as native element.querySelectorAll() does not select exact element descendants
         * e.g. 'a:has(> img)' -> `aNode.querySelectorAll(':scope > img')`.
         *
         * For 'any selector' as arg of relative simplicity should be set for all inner elements
         * e.g. 'div:has(*)' -> `divNode.querySelectorAll(':scope *')`
         * which means empty div with no child element.
         */
        rootElement = element;
        specifiedSelector = `${scopeAnyChildren}${ASTERISK}`;
      } else {
        /**
         * As it described above, inner elements should be found using `:scope` pseudo-class
         * e.g. 'a:has(> img)' -> `aNode.querySelectorAll(':scope > img')`
         * OR '.block(div > span)' -> `blockClassNode.querySelectorAll(':scope div > span')`.
         */
        specifiedSelector = `${scopeAnyChildren}${regularSelector}`;
        rootElement = element;
      }
      if (!rootElement) {
        throw new Error(`Selection by :${pseudoName}() pseudo-class is not possible`);
      }
      let relativeElements;
      try {
        // eslint-disable-next-line @typescript-eslint/no-use-before-define
        relativeElements = getElementsForSelectorNode(selectorNode, rootElement, specifiedSelector);
      } catch (e) {
        logger.error(getErrorMessage(e)); // fail for invalid selector

        throw new Error(`Invalid selector for :${pseudoName}() pseudo-class: '${regularSelector}'`);
      }
      return relativeElements.length > 0;
    });
  };
  /**
   * Checks whether the element is an any element specified by pseudo-class arg.
   * Used for :is() pseudo-class.
   *
   * @param argsData Relative pseudo-class helpers args data.
   *
   * @returns True if **any selector** from argsData.relativeSelectorList is **matched** for argsData.element.
   */

  const isAnyElementBySelectorList = argsData => {
    const {
      element,
      relativeSelectorList,
      pseudoName
    } = argsData;
    return relativeSelectorList.children // Array.some() is used here as any selector from selector list should exist on page
    .some(selectorNode => {
      // selectorList.children always starts with regular selector
      const relativeRegularSelector = getFirstInnerRegularChild(selectorNode, pseudoName);
      /**
       * For checking the element by 'div:is(.banner)'
       * we check whether the element's parentElement has any specific direct child.
       */

      const rootElement = getParent(element, `Selection by :${pseudoName}() pseudo-class is not possible`);
      /**
       * So we calculate the element "description" by it's tagname and attributes for targeting
       * and use it to specify the selection
       * e.g. `div:is(.banner)` --> `divNode.parentElement.querySelectorAll(':scope > .banner')`.
       */

      const specifiedSelector = `${scopeDirectChildren}${getNodeValue(relativeRegularSelector)}`;
      let anyElements;
      try {
        // eslint-disable-next-line @typescript-eslint/no-use-before-define
        anyElements = getElementsForSelectorNode(selectorNode, rootElement, specifiedSelector);
      } catch (e) {
        // do not fail on invalid selectors for :is()
        return false;
      } // TODO: figure out how to handle complex selectors with extended pseudo-classes
      // (check readme - extended-css-is-limitations)
      // because `element` and `anyElements` may be from different DOM levels

      return anyElements.includes(element);
    });
  };
  /**
   * Checks whether the element is not an element specified by pseudo-class arg.
   * Used for :not() pseudo-class.
   *
   * @param argsData Relative pseudo-class helpers args data.
   *
   * @returns True if **any selector** from argsData.relativeSelectorList is **not matched** for argsData.element.
   */

  const notElementBySelectorList = argsData => {
    const {
      element,
      relativeSelectorList,
      pseudoName
    } = argsData;
    return relativeSelectorList.children // Array.every() is used here as element should not be selected by any selector from selector list
    .every(selectorNode => {
      // selectorList.children always starts with regular selector
      const relativeRegularSelector = getFirstInnerRegularChild(selectorNode, pseudoName);
      /**
       * For checking the element by 'div:not([data="content"])
       * we check whether the element's parentElement has any specific direct child.
       */

      const rootElement = getParent(element, `Selection by :${pseudoName}() pseudo-class is not possible`);
      /**
       * So we calculate the element "description" by it's tagname and attributes for targeting
       * and use it to specify the selection
       * e.g. `div:not(.banner)` --> `divNode.parentElement.querySelectorAll(':scope > .banner')`.
       */

      const specifiedSelector = `${scopeDirectChildren}${getNodeValue(relativeRegularSelector)}`;
      let anyElements;
      try {
        // eslint-disable-next-line @typescript-eslint/no-use-before-define
        anyElements = getElementsForSelectorNode(selectorNode, rootElement, specifiedSelector);
      } catch (e) {
        // fail on invalid selectors for :not()
        logger.error(getErrorMessage(e)); // eslint-disable-next-line max-len

        throw new Error(`Invalid selector for :${pseudoName}() pseudo-class: '${getNodeValue(relativeRegularSelector)}'`);
      } // TODO: figure out how to handle up-looking pseudo-classes inside :not()
      // (check readme - extended-css-not-limitations)
      // because `element` and `anyElements` may be from different DOM levels

      return !anyElements.includes(element);
    });
  };
  /**
   * Selects dom elements by value of RegularSelector.
   *
   * @param regularSelectorNode RegularSelector node.
   * @param root Root DOM element.
   * @param specifiedSelector @see {@link SpecifiedSelector}.
   *
   * @returns Array of DOM elements.
   * @throws An error if RegularSelector node value is an invalid selector.
   */

  const getByRegularSelector = (regularSelectorNode, root, specifiedSelector) => {
    const selectorText = specifiedSelector ? specifiedSelector : getNodeValue(regularSelectorNode);
    let selectedElements = [];
    try {
      selectedElements = Array.from(root.querySelectorAll(selectorText));
    } catch (e) {
      throw new Error(`Error: unable to select by '${selectorText}' — ${getErrorMessage(e)}`);
    }
    return selectedElements;
  };
  /**
   * Returns list of dom elements filtered or selected by ExtendedSelector node.
   *
   * @param domElements Array of DOM elements.
   * @param extendedSelectorNode ExtendedSelector node.
   *
   * @returns Array of DOM elements.
   * @throws An error on unknown pseudo-class,
   * absent or invalid arg of extended pseudo-class, etc.
   */

  const getByExtendedSelector = (domElements, extendedSelectorNode) => {
    let foundElements = [];
    const extendedPseudoClassNode = getPseudoClassNode(extendedSelectorNode);
    const pseudoName = getNodeName(extendedPseudoClassNode);
    if (isAbsolutePseudoClass(pseudoName)) {
      // absolute extended pseudo-classes should have an argument
      const absolutePseudoArg = getNodeValue(extendedPseudoClassNode, `Missing arg for :${pseudoName}() pseudo-class`);
      if (pseudoName === NTH_ANCESTOR_PSEUDO_CLASS_MARKER) {
        // :nth-ancestor()
        foundElements = findByAbsolutePseudoPseudo.nthAncestor(domElements, absolutePseudoArg, pseudoName);
      } else if (pseudoName === XPATH_PSEUDO_CLASS_MARKER) {
        // :xpath()
        try {
          document.createExpression(absolutePseudoArg, null);
        } catch (e) {
          throw new Error(`Invalid argument of :${pseudoName}() pseudo-class: '${absolutePseudoArg}'`);
        }
        foundElements = findByAbsolutePseudoPseudo.xpath(domElements, absolutePseudoArg);
      } else if (pseudoName === UPWARD_PSEUDO_CLASS_MARKER) {
        // :upward()
        if (Number.isNaN(Number(absolutePseudoArg))) {
          // so arg is selector, not a number
          foundElements = findByAbsolutePseudoPseudo.upward(domElements, absolutePseudoArg);
        } else {
          foundElements = findByAbsolutePseudoPseudo.nthAncestor(domElements, absolutePseudoArg, pseudoName);
        }
      } else {
        // all other absolute extended pseudo-classes
        // e.g. contains, matches-attr, etc.
        foundElements = domElements.filter(element => {
          return isMatchedByAbsolutePseudo(element, pseudoName, absolutePseudoArg);
        });
      }
    } else if (isRelativePseudoClass(pseudoName)) {
      const relativeSelectorList = getRelativeSelectorListNode(extendedPseudoClassNode);
      let relativePredicate;
      switch (pseudoName) {
        case HAS_PSEUDO_CLASS_MARKER:
        case ABP_HAS_PSEUDO_CLASS_MARKER:
          relativePredicate = element => hasRelativesBySelectorList({
            element,
            relativeSelectorList,
            pseudoName
          });
          break;
        case IS_PSEUDO_CLASS_MARKER:
          relativePredicate = element => isAnyElementBySelectorList({
            element,
            relativeSelectorList,
            pseudoName
          });
          break;
        case NOT_PSEUDO_CLASS_MARKER:
          relativePredicate = element => notElementBySelectorList({
            element,
            relativeSelectorList,
            pseudoName
          });
          break;
        default:
          throw new Error(`Unknown relative pseudo-class: '${pseudoName}'`);
      }
      foundElements = domElements.filter(relativePredicate);
    } else {
      // extra check is parser missed something
      throw new Error(`Unknown extended pseudo-class: '${pseudoName}'`);
    }
    return foundElements;
  };
  /**
   * Returns list of dom elements which is selected by RegularSelector value.
   *
   * @param domElements Array of DOM elements.
   * @param regularSelectorNode RegularSelector node.
   *
   * @returns Array of DOM elements.
   * @throws An error if RegularSelector has not value.
   */

  const getByFollowingRegularSelector = (domElements, regularSelectorNode) => {
    // array of arrays because of Array.map() later
    let foundElements = [];
    const value = getNodeValue(regularSelectorNode);
    if (value.startsWith(CHILD_COMBINATOR)) {
      // e.g. div:has(> img) > .banner
      foundElements = domElements.map(root => {
        const specifiedSelector = `${SCOPE_CSS_PSEUDO_CLASS}${value}`;
        return getByRegularSelector(regularSelectorNode, root, specifiedSelector);
      });
    } else if (value.startsWith(NEXT_SIBLING_COMBINATOR) || value.startsWith(SUBSEQUENT_SIBLING_COMBINATOR)) {
      // e.g. div:has(> img) + .banner
      // or   div:has(> img) ~ .banner
      foundElements = domElements.map(element => {
        const rootElement = element.parentElement;
        if (!rootElement) {
          // do not throw error if there in no parent for element
          // e.g. '*:contains(text)' selects `html` which has no parentElement
          return [];
        }
        const elementSelectorText = getElementSelectorDesc(element);
        const specifiedSelector = `${scopeDirectChildren}${elementSelectorText}${value}`;
        const selected = getByRegularSelector(regularSelectorNode, rootElement, specifiedSelector);
        return selected;
      });
    } else {
      // space-separated regular selector after extended one
      // e.g. div:has(> img) .banner
      foundElements = domElements.map(root => {
        const specifiedSelector = `${scopeAnyChildren}${getNodeValue(regularSelectorNode)}`;
        return getByRegularSelector(regularSelectorNode, root, specifiedSelector);
      });
    } // foundElements should be flattened
    // as getByRegularSelector() returns elements array, and Array.map() collects them to array

    return flatten(foundElements);
  };
  /**
   * Returns elements nodes for Selector node.
   * As far as any selector always starts with regular part,
   * it selects by RegularSelector first and checks found elements later.
   *
   * Relative pseudo-classes has it's own subtree so getElementsForSelectorNode is called recursively.
   *
   * 'specifiedSelector' is needed for :has(), :is(), and :not() pseudo-classes
   * as native querySelectorAll() does not select exact element descendants even if it is called on 'div'
   * e.g. ':scope' specification is needed for proper descendants selection for 'div:has(> img)'.
   * So we check `divNode.querySelectorAll(':scope > img').length > 0`.
   *
   * @param selectorNode Selector node.
   * @param root Root DOM element.
   * @param specifiedSelector Needed element specification.
   *
   * @returns Array of DOM elements.
   * @throws An error if there is no selectorNodeChild.
   */

  const getElementsForSelectorNode = (selectorNode, root, specifiedSelector) => {
    let selectedElements = [];
    let i = 0;
    while (i < selectorNode.children.length) {
      const selectorNodeChild = getItemByIndex(selectorNode.children, i, 'selectorNodeChild should be specified');
      if (i === 0) {
        // any selector always starts with regular selector
        selectedElements = getByRegularSelector(selectorNodeChild, root, specifiedSelector);
      } else if (isExtendedSelectorNode(selectorNodeChild)) {
        // filter previously selected elements by next selector nodes
        selectedElements = getByExtendedSelector(selectedElements, selectorNodeChild);
      } else if (isRegularSelectorNode(selectorNodeChild)) {
        selectedElements = getByFollowingRegularSelector(selectedElements, selectorNodeChild);
      }
      i += 1;
    }
    return selectedElements;
  };

  /**
   * Selects elements by ast.
   *
   * @param ast Ast of parsed selector.
   * @param doc Document.
   *
   * @returns Array of DOM elements.
   */

  const selectElementsByAst = function (ast) {
    let doc = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : document;
    const selectedElements = []; // ast root is SelectorList node;
    // it has Selector nodes as children which should be processed separately

    ast.children.forEach(selectorNode => {
      selectedElements.push(...getElementsForSelectorNode(selectorNode, doc));
    }); // selectedElements should be flattened as it is array of arrays with elements

    const uniqueElements = [...new Set(flatten(selectedElements))];
    return uniqueElements;
  };
  /**
   * Class of ExtCssDocument is needed for caching.
   * For making cache related to each new instance of class, not global.
   */

  class ExtCssDocument {
    /**
     * Cache with selectors and their AST parsing results.
     */

    /**
     * Creates new ExtCssDocument and inits new `astCache`.
     */
    constructor() {
      this.astCache = new Map();
    }
    /**
     * Saves selector and it's ast to cache.
     *
     * @param selector Standard or extended selector.
     * @param ast Selector ast.
     */

    saveAstToCache(selector, ast) {
      this.astCache.set(selector, ast);
    }
    /**
     * Returns ast from cache for given selector.
     *
     * @param selector Standard or extended selector.
     *
     * @returns Previously parsed ast found in cache, or null if not found.
     */

    getAstFromCache(selector) {
      const cachedAst = this.astCache.get(selector) || null;
      return cachedAst;
    }
    /**
     * Returns selector ast:
     * - if cached ast exists — returns it;
     * - if no cached ast — saves newly parsed ast to cache and returns it.
     *
     * @param selector Standard or extended selector.
     *
     * @returns Ast for `selector`.
     */

    getSelectorAst(selector) {
      let ast = this.getAstFromCache(selector);
      if (!ast) {
        ast = parse(selector);
      }
      this.saveAstToCache(selector, ast);
      return ast;
    }
    /**
     * Selects elements by selector.
     *
     * @param selector Standard or extended selector.
     *
     * @returns Array of DOM elements.
     */

    querySelectorAll(selector) {
      const ast = this.getSelectorAst(selector);
      return selectElementsByAst(ast);
    }
  }
  const extCssDocument = new ExtCssDocument();

  /**
   * Converts array of `entries` to object.
   * Object.fromEntries() polyfill because it is not supported by old browsers, e.g. Chrome 55.
   * Only first two elements of `entries` array matter, other will be skipped silently.
   *
   * @see {@link https://caniuse.com/?search=Object.fromEntries}
   *
   * @param entries Array of pairs.
   *
   * @returns Object converted from `entries`.
   */
  const getObjectFromEntries = entries => {
    const object = {};
    entries.forEach(el => {
      const [key, value] = el;
      object[key] = value;
    });
    return object;
  };
  const DEBUG_PSEUDO_PROPERTY_KEY = 'debug';
  /**
   * Checks the presence of :remove() pseudo-class and validates it while parsing the selector part of css rule.
   *
   * @param rawSelector Selector which may contain :remove() pseudo-class.
   *
   * @returns Parsed selector data with selector and styles.
   * @throws An error on invalid :remove() position.
   */

  const parseRemoveSelector = rawSelector => {
    /**
     * No error will be thrown on invalid selector as it will be validated later
     * so it's better to explicitly specify 'any' selector for :remove() pseudo-class by '*',
     * e.g. '.banner > *:remove()' instead of '.banner > :remove()'.
     */
    // ':remove()'
    // eslint-disable-next-line max-len
    const VALID_REMOVE_MARKER = `${COLON}${REMOVE_PSEUDO_MARKER}${BRACKET.PARENTHESES.LEFT}${BRACKET.PARENTHESES.RIGHT}`; // ':remove(' - needed for validation rules like 'div:remove(2)'

    const INVALID_REMOVE_MARKER = `${COLON}${REMOVE_PSEUDO_MARKER}${BRACKET.PARENTHESES.LEFT}`;
    let selector;
    let shouldRemove = false;
    const firstIndex = rawSelector.indexOf(VALID_REMOVE_MARKER);
    if (firstIndex === 0) {
      // e.g. ':remove()'
      throw new Error(`${REMOVE_ERROR_PREFIX.NO_TARGET_SELECTOR}: '${rawSelector}'`);
    } else if (firstIndex > 0) {
      if (firstIndex !== rawSelector.lastIndexOf(VALID_REMOVE_MARKER)) {
        // rule with more than one :remove() pseudo-class is invalid
        // e.g. '.block:remove() > .banner:remove()'
        throw new Error(`${REMOVE_ERROR_PREFIX.MULTIPLE_USAGE}: '${rawSelector}'`);
      } else if (firstIndex + VALID_REMOVE_MARKER.length < rawSelector.length) {
        // remove pseudo-class should be last in the rule
        // e.g. '.block:remove():upward(2)'
        throw new Error(`${REMOVE_ERROR_PREFIX.INVALID_POSITION}: '${rawSelector}'`);
      } else {
        // valid :remove() pseudo-class position
        selector = rawSelector.substring(0, firstIndex);
        shouldRemove = true;
      }
    } else if (rawSelector.includes(INVALID_REMOVE_MARKER)) {
      // it is not valid if ':remove()' is absent in rule but just ':remove(' is present
      // e.g. 'div:remove(0)'
      throw new Error(`${REMOVE_ERROR_PREFIX.INVALID_REMOVE}: '${rawSelector}'`);
    } else {
      // there is no :remove() pseudo-class in rule
      selector = rawSelector;
    }
    const stylesOfSelector = shouldRemove ? [{
      property: REMOVE_PSEUDO_MARKER,
      value: PSEUDO_PROPERTY_POSITIVE_VALUE
    }] : [];
    return {
      selector,
      stylesOfSelector
    };
  };
  /**
   * Parses cropped selector part found before `{`.
   *
   * @param selectorBuffer Buffered selector to parse.
   * @param extCssDoc Needed for caching of selector ast.
   *
   * @returns Parsed validation data for cropped part of stylesheet which may be a selector.
   * @throws An error on unsupported CSS features, e.g. at-rules.
   */

  const parseSelectorRulePart = (selectorBuffer, extCssDoc) => {
    let selector = selectorBuffer.trim();
    if (selector.startsWith(AT_RULE_MARKER)) {
      throw new Error(`${NO_AT_RULE_ERROR_PREFIX}: '${selector}'.`);
    }
    let removeSelectorData;
    try {
      removeSelectorData = parseRemoveSelector(selector);
    } catch (e) {
      logger.error(getErrorMessage(e));
      throw new Error(`${REMOVE_ERROR_PREFIX.INVALID_REMOVE}: '${selector}'`);
    }
    let stylesOfSelector = [];
    let success = false;
    let ast;
    try {
      selector = removeSelectorData.selector;
      stylesOfSelector = removeSelectorData.stylesOfSelector; // validate found selector by parsing it to ast
      // so if it is invalid error will be thrown

      ast = extCssDoc.getSelectorAst(selector);
      success = true;
    } catch (e) {
      success = false;
    }
    return {
      success,
      selector,
      ast,
      stylesOfSelector
    };
  };
  /**
   * Creates a map for storing raw results of css rules parsing.
   * Used for merging styles for same selector.
   *
   * @returns Map where **key** is `selector`
   * and **value** is object with `ast` and `styles`.
   */

  const createRawResultsMap = () => {
    return new Map();
  };
  /**
   * Saves rules data for unique selectors.
   *
   * @param rawResults Previously collected results of parsing.
   * @param rawRuleData Parsed rule data.
   *
   * @throws An error if there is no rawRuleData.styles or rawRuleData.ast.
   */

  const saveToRawResults = (rawResults, rawRuleData) => {
    const {
      selector,
      ast,
      rawStyles
    } = rawRuleData;
    if (!rawStyles) {
      throw new Error(`No style declaration for selector: '${selector}'`);
    }
    if (!ast) {
      throw new Error(`No ast parsed for selector: '${selector}'`);
    }
    const storedRuleData = rawResults.get(selector);
    if (!storedRuleData) {
      rawResults.set(selector, {
        ast,
        styles: rawStyles
      });
    } else {
      storedRuleData.styles.push(...rawStyles);
    }
  };
  /**
   * Checks whether the 'remove' property positively set in styles
   * with only one positive value - 'true'.
   *
   * @param styles Array of styles.
   *
   * @returns True if there is 'remove' property with 'true' value in `styles`.
   */

  const isRemoveSetInStyles = styles => {
    return styles.some(s => {
      return s.property === REMOVE_PSEUDO_MARKER && s.value === PSEUDO_PROPERTY_POSITIVE_VALUE;
    });
  };
  /**
   * Returns 'debug' property value which is set in styles.
   *
   * @param styles Array of styles.
   *
   * @returns Value of 'debug' property if it is set in `styles`,
   * or `undefined` if the property is not found.
   */

  const getDebugStyleValue = styles => {
    const debugStyle = styles.find(s => {
      return s.property === DEBUG_PSEUDO_PROPERTY_KEY;
    });
    return debugStyle === null || debugStyle === void 0 ? void 0 : debugStyle.value;
  };
  /**
   * Prepares final RuleData.
   * Handles `debug` and `remove` in raw rule data styles.
   *
   * @param rawRuleData Raw data of selector css rule parsing.
   *
   * @returns Parsed ExtendedCss rule data.
   * @throws An error if rawRuleData.ast or rawRuleData.rawStyles not defined.
   */

  const prepareRuleData = rawRuleData => {
    const {
      selector,
      ast,
      rawStyles
    } = rawRuleData;
    if (!ast) {
      throw new Error(`AST should be parsed for selector: '${selector}'`);
    }
    if (!rawStyles) {
      throw new Error(`Styles should be parsed for selector: '${selector}'`);
    }
    const ruleData = {
      selector,
      ast
    };
    const debugValue = getDebugStyleValue(rawStyles);
    const shouldRemove = isRemoveSetInStyles(rawStyles);
    let styles = rawStyles;
    if (debugValue) {
      // get rid of 'debug' from styles
      styles = rawStyles.filter(s => s.property !== DEBUG_PSEUDO_PROPERTY_KEY); // and set it as separate property only if its value is valid
      // which is 'true' or 'global'

      if (debugValue === PSEUDO_PROPERTY_POSITIVE_VALUE || debugValue === DEBUG_PSEUDO_PROPERTY_GLOBAL_VALUE) {
        ruleData.debug = debugValue;
      }
    }
    if (shouldRemove) {
      // no other styles are needed to apply if 'remove' is set
      ruleData.style = {
        [REMOVE_PSEUDO_MARKER]: PSEUDO_PROPERTY_POSITIVE_VALUE
      };
      /**
       * 'content' property is needed for ExtCssConfiguration.beforeStyleApplied().
       *
       * @see {@link BeforeStyleAppliedCallback}
       */

      const contentStyle = styles.find(s => s.property === CONTENT_CSS_PROPERTY);
      if (contentStyle) {
        ruleData.style[CONTENT_CSS_PROPERTY] = contentStyle.value;
      }
    } else {
      // otherwise all styles should be applied.
      // every style property will be unique because of their converting into object
      if (styles.length > 0) {
        const stylesAsEntries = styles.map(style => {
          const {
            property,
            value
          } = style;
          return [property, value];
        });
        const preparedStyleData = getObjectFromEntries(stylesAsEntries);
        ruleData.style = preparedStyleData;
      }
    }
    return ruleData;
  };
  /**
   * Combines previously parsed css rules data objects
   * into rules which are ready to apply.
   *
   * @param rawResults Previously parsed css rules data objects.
   *
   * @returns Parsed ExtendedCss rule data.
   */

  const combineRulesData = rawResults => {
    const results = [];
    rawResults.forEach((value, key) => {
      const selector = key;
      const {
        ast,
        styles: rawStyles
      } = value;
      results.push(prepareRuleData({
        selector,
        ast,
        rawStyles
      }));
    });
    return results;
  };

  /**
   * Trims `rawStyle` and splits it into tokens.
   *
   * @param rawStyle Style declaration block content inside curly bracket — `{` and `}` —
   * can be a single style declaration or a list of declarations.
   *
   * @returns Array of tokens supported for style declaration block.
   */

  const tokenizeStyleBlock = rawStyle => {
    const styleDeclaration = rawStyle.trim();
    return tokenize(styleDeclaration, SUPPORTED_STYLE_DECLARATION_MARKS);
  };

  /**
   * Describes possible style declaration parts.
   *
   * IMPORTANT: it is used as 'const' instead of 'enum' to avoid side effects
   * during ExtendedCss import into other libraries.
   */

  const DECLARATION_PART = {
    PROPERTY: 'property',
    VALUE: 'value'
  };

  /**
   * Checks whether the quotes has been opened for style value.
   *
   * @param context Style block parser context.
   *
   * @returns True if style value has already opened quotes.
   */
  const isValueQuotesOpen = context => {
    return context.bufferValue !== '' && context.valueQuoteMark !== null;
  };
  /**
   * Saves parsed property and value to collection of parsed styles.
   * Prunes context buffers for property and value.
   *
   * @param context Style block parser context.
   */

  const collectStyle = context => {
    context.styles.push({
      property: context.bufferProperty.trim(),
      value: context.bufferValue.trim()
    }); // reset buffers

    context.bufferProperty = '';
    context.bufferValue = '';
  };
  /**
   * Handles token which is supposed to be a part of style **property**.
   *
   * @param context Style block parser context.
   * @param styleBlock Whole style block which is being parsed.
   * @param token Current token.
   *
   * @throws An error on invalid token.
   */

  const processPropertyToken = (context, styleBlock, token) => {
    const {
      value: tokenValue
    } = token;
    switch (token.type) {
      case TOKEN_TYPE.WORD:
        if (context.bufferProperty.length > 0) {
          // e.g. 'padding top: 0;' - current tokenValue is 'top' which is not valid
          throw new Error(`Invalid style property in style block: '${styleBlock}'`);
        }
        context.bufferProperty += tokenValue;
        break;
      case TOKEN_TYPE.MARK:
        // only colon and whitespaces are allowed while style property parsing
        if (tokenValue === COLON) {
          if (context.bufferProperty.trim().length === 0) {
            // e.g. such style block: '{ : none; }'
            throw new Error(`Missing style property before ':' in style block: '${styleBlock}'`);
          } // the property successfully collected

          context.bufferProperty = context.bufferProperty.trim(); // prepare for value collecting

          context.processing = DECLARATION_PART.VALUE; // the property buffer shall be reset after the value is successfully collected
        } else if (WHITE_SPACE_CHARACTERS.includes(tokenValue)) ;else {
          // if after the property there is anything other than ':' except whitespace, this is a parse error
          // https://www.w3.org/TR/css-syntax-3/#consume-declaration
          throw new Error(`Invalid style declaration in style block: '${styleBlock}'`);
        }
        break;
      default:
        throw new Error(`Unsupported style property character: '${tokenValue}' in style block: '${styleBlock}'`);
    }
  };
  /**
   * Handles token which is supposed to be a part of style **value**.
   *
   * @param context Style block parser context.
   * @param styleBlock Whole style block which is being parsed.
   * @param token Current token.
   *
   * @throws An error on invalid token.
   */

  const processValueToken = (context, styleBlock, token) => {
    const {
      value: tokenValue
    } = token;
    if (token.type === TOKEN_TYPE.WORD) {
      // simply collect to buffer
      context.bufferValue += tokenValue;
    } else {
      // otherwise check the mark
      switch (tokenValue) {
        case COLON:
          // the ':' character inside of the value should be inside of quotes
          // otherwise the value is not valid
          // e.g. 'content: display: none'
          // parser is here        ↑
          if (!isValueQuotesOpen(context)) {
            // eslint-disable-next-line max-len
            throw new Error(`Invalid style value for property '${context.bufferProperty}' in style block: '${styleBlock}'`);
          } // collect the colon inside quotes
          // e.g. 'content: "test:123"'
          // parser is here      ↑

          context.bufferValue += tokenValue;
          break;
        case SEMICOLON:
          if (isValueQuotesOpen(context)) {
            // ';' inside quotes is part of style value
            // e.g. 'content: "test;"'
            context.bufferValue += tokenValue;
          } else {
            // otherwise the value is successfully collected
            // save parsed style
            collectStyle(context); // prepare for value collecting

            context.processing = DECLARATION_PART.PROPERTY;
          }
          break;
        case SINGLE_QUOTE:
        case DOUBLE_QUOTE:
          // if quotes are not open
          if (context.valueQuoteMark === null) {
            // save the opening quote mark for later comparison
            context.valueQuoteMark = tokenValue;
          } else if (!context.bufferValue.endsWith(BACKSLASH) // otherwise a quote appeared in the value earlier,
          // and non-escaped quote should be checked whether it is a closing quote
          && context.valueQuoteMark === tokenValue) {
            context.valueQuoteMark = null;
          } // always save the quote to the buffer
          // but after the context.bufferValue is checked for BACKSLASH above
          // e.g. 'content: "test:123"'
          //      'content: "\""'

          context.bufferValue += tokenValue;
          break;
        case BACKSLASH:
          if (!isValueQuotesOpen(context)) {
            // eslint-disable-next-line max-len
            throw new Error(`Invalid style value for property '${context.bufferProperty}' in style block: '${styleBlock}'`);
          } // collect the backslash inside quotes
          // e.g. ' content: "\"" '
          // parser is here   ↑

          context.bufferValue += tokenValue;
          break;
        case SPACE:
        case TAB:
        case CARRIAGE_RETURN:
        case LINE_FEED:
        case FORM_FEED:
          // whitespace should be collected only if the value collecting started
          // which means inside of the value
          // e.g. 'width: 100% !important'
          // parser is here   ↑
          if (context.bufferValue.length > 0) {
            context.bufferValue += tokenValue;
          } // otherwise it can be omitted
          // e.g. 'width:  100% !important'
          // here        ↑

          break;
        default:
          throw new Error(`Unknown style declaration token: '${tokenValue}'`);
      }
    }
  };
  /**
   * Parses css rule style block.
   *
   * @param rawStyleBlock Style block to parse.
   *
   * @returns Array of style declarations.
   * @throws An error on invalid style block.
   */

  const parseStyleBlock = rawStyleBlock => {
    const styleBlock = rawStyleBlock.trim();
    const tokens = tokenizeStyleBlock(styleBlock);
    const context = {
      // style declaration parsing always starts with 'property'
      processing: DECLARATION_PART.PROPERTY,
      styles: [],
      bufferProperty: '',
      bufferValue: '',
      valueQuoteMark: null
    };
    let i = 0;
    while (i < tokens.length) {
      const token = tokens[i];
      if (!token) {
        break;
      }
      if (context.processing === DECLARATION_PART.PROPERTY) {
        processPropertyToken(context, styleBlock, token);
      } else if (context.processing === DECLARATION_PART.VALUE) {
        processValueToken(context, styleBlock, token);
      } else {
        throw new Error('Style declaration parsing failed');
      }
      i += 1;
    } // unbalanced value quotes
    // e.g. 'content: "test} '

    if (isValueQuotesOpen(context)) {
      throw new Error(`Unbalanced style declaration quotes in style block: '${styleBlock}'`);
    } // collected property and value have not been saved to styles;
    // it is possible for style block with no semicolon at the end
    // e.g. such style block: '{ display: none }'

    if (context.bufferProperty.length > 0) {
      if (context.bufferValue.length === 0) {
        // e.g. such style blocks:
        //   '{ display:  }'
        //   '{ remove }'
        // eslint-disable-next-line max-len
        throw new Error(`Missing style value for property '${context.bufferProperty}' in style block '${styleBlock}'`);
      }
      collectStyle(context);
    } // rule with empty style block
    // e.g. 'div { }'

    if (context.styles.length === 0) {
      throw new Error(STYLE_ERROR_PREFIX.NO_STYLE);
    }
    return context.styles;
  };

  /**
   * Returns array of positions of `{` in `cssRule`.
   *
   * @param cssRule CSS rule.
   *
   * @returns Array of left curly bracket indexes.
   */

  const getLeftCurlyBracketIndexes = cssRule => {
    const indexes = [];
    for (let i = 0; i < cssRule.length; i += 1) {
      if (cssRule[i] === BRACKET.CURLY.LEFT) {
        indexes.push(i);
      }
    }
    return indexes;
  }; // TODO: use `extCssDoc` for caching of style block parser results

  /**
   * Parses CSS rule into rules data object:
   * 1. Find the last `{` mark in the rule
   *    which supposed to be a divider between selector and style block.
   * 2. Validates found string part before the `{` via selector parser; and if:
   *  - parsing failed – get the previous `{` in the rule,
   *    and validates a new rule part again [2];
   *  - parsing successful — saves a found rule part as selector and parses the style block.
   *
   * @param rawCssRule Single CSS rule to parse.
   * @param extCssDoc ExtCssDocument which is used for selector ast caching.
   *
   * @returns Array of rules data which contains:
   *   - selector as string;
   *   - ast to query elements by;
   *   - map of styles to apply.
   * @throws An error on invalid css rule syntax:
   *   - unsupported CSS features – comments and at-rules
   *   - invalid selector or style block.
   */

  const parseRule = (rawCssRule, extCssDoc) => {
    var _rawRuleData$selector;
    const cssRule = rawCssRule.trim();
    if (cssRule.includes(`${SLASH}${ASTERISK}`) && cssRule.includes(`${ASTERISK}${SLASH}`)) {
      throw new Error(STYLE_ERROR_PREFIX.NO_COMMENT);
    }
    const leftCurlyBracketIndexes = getLeftCurlyBracketIndexes(cssRule); // rule with style block but no selector
    // e.g. '{ display: none; }'

    if (getFirst(leftCurlyBracketIndexes) === 0) {
      throw new Error(NO_SELECTOR_ERROR_PREFIX);
    }
    let selectorData; // if rule has `{` but there is no `}`

    if (leftCurlyBracketIndexes.length > 0 && !cssRule.includes(BRACKET.CURLY.RIGHT)) {
      throw new Error(`${STYLE_ERROR_PREFIX.NO_STYLE} OR ${STYLE_ERROR_PREFIX.UNCLOSED_STYLE}`);
    }
    if (
    // if rule has no `{`
    leftCurlyBracketIndexes.length === 0 // or `}`
    || !cssRule.includes(BRACKET.CURLY.RIGHT)) {
      try {
        // the whole css rule considered as "selector part"
        // which may contain :remove() pseudo-class
        selectorData = parseSelectorRulePart(cssRule, extCssDoc);
        if (selectorData.success) {
          var _selectorData$stylesO;

          // rule with no style block has valid :remove() pseudo-class
          // which is parsed into "styles"
          // e.g. 'div:remove()'
          // but also it can be just selector with no styles
          // e.g. 'div'
          // which should not be considered as valid css rule
          if (((_selectorData$stylesO = selectorData.stylesOfSelector) === null || _selectorData$stylesO === void 0 ? void 0 : _selectorData$stylesO.length) === 0) {
            throw new Error(STYLE_ERROR_PREFIX.NO_STYLE_OR_REMOVE);
          }
          return {
            selector: selectorData.selector.trim(),
            ast: selectorData.ast,
            rawStyles: selectorData.stylesOfSelector
          };
        } else {
          // not valid selector
          throw new Error('Invalid selector');
        }
      } catch (e) {
        throw new Error(getErrorMessage(e));
      }
    }
    let selectorBuffer;
    let styleBlockBuffer;
    const rawRuleData = {
      selector: ''
    }; // css rule should be parsed from its end

    for (let i = leftCurlyBracketIndexes.length - 1; i > -1; i -= 1) {
      const index = leftCurlyBracketIndexes[i];
      if (!index) {
        throw new Error(`Impossible to continue, no '{' to process for rule: '${cssRule}'`);
      } // selector is before `{`, style block is after it

      selectorBuffer = cssRule.slice(0, index); // skip curly brackets

      styleBlockBuffer = cssRule.slice(index + 1, cssRule.length - 1);
      selectorData = parseSelectorRulePart(selectorBuffer, extCssDoc);
      if (selectorData.success) {
        var _rawRuleData$rawStyle;

        // selector successfully parsed
        rawRuleData.selector = selectorData.selector.trim();
        rawRuleData.ast = selectorData.ast;
        rawRuleData.rawStyles = selectorData.stylesOfSelector; // style block should be parsed
        // TODO: add cache for style block parsing

        const parsedStyles = parseStyleBlock(styleBlockBuffer);
        (_rawRuleData$rawStyle = rawRuleData.rawStyles) === null || _rawRuleData$rawStyle === void 0 ? void 0 : _rawRuleData$rawStyle.push(...parsedStyles); // stop rule parsing

        break;
      } else {
        // if selector was not parsed successfully
        // continue with next index of `{`
        continue;
      }
    }
    if (((_rawRuleData$selector = rawRuleData.selector) === null || _rawRuleData$selector === void 0 ? void 0 : _rawRuleData$selector.length) === 0) {
      // skip the rule as selector
      throw new Error('Selector in not valid');
    }
    return rawRuleData;
  };
  /**
   * Parses array of CSS rules into array of rules data objects.
   * Invalid rules are skipped and not applied,
   * and the errors are logged.
   *
   * @param rawCssRules Array of rules to parse.
   * @param extCssDoc Needed for selector ast caching.
   *
   * @returns Array of parsed valid rules data.
   */

  const parseRules = (rawCssRules, extCssDoc) => {
    const rawResults = createRawResultsMap();
    const warnings = []; // trim all rules and find unique ones

    const uniqueRules = [...new Set(rawCssRules.map(r => r.trim()))];
    uniqueRules.forEach(rule => {
      try {
        saveToRawResults(rawResults, parseRule(rule, extCssDoc));
      } catch (e) {
        // skip the invalid rule
        const errorMessage = getErrorMessage(e);
        warnings.push(`'${rule}' - error: '${errorMessage}'`);
      }
    }); // log info about skipped invalid rules

    if (warnings.length > 0) {
      logger.info(`Invalid rules:\n  ${warnings.join('\n  ')}`);
    }
    return combineRulesData(rawResults);
  };
  const REGEXP_DECLARATION_END = /[;}]/g;
  const REGEXP_DECLARATION_DIVIDER = /[;:}]/g;
  const REGEXP_NON_WHITESPACE = /\S/g;
  /**
   * Interface for stylesheet parser context.
   */

  /**
   * Resets rule data buffer to init value after rule successfully collected.
   *
   * @param context Stylesheet parser context.
   */
  const restoreRuleAcc = context => {
    context.rawRuleData = {
      selector: ''
    };
  };
  /**
   * Parses cropped selector part found before `{` previously.
   *
   * @param context Stylesheet parser context.
   * @param extCssDoc Needed for caching of selector ast.
   *
   * @returns Parsed validation data for cropped part of stylesheet which may be a selector.
   * @throws An error on unsupported CSS features, e.g. at-rules.
   */

  const parseSelectorPart = (context, extCssDoc) => {
    let selector = context.selectorBuffer.trim();
    if (selector.startsWith(AT_RULE_MARKER)) {
      throw new Error(`${NO_AT_RULE_ERROR_PREFIX}: '${selector}'.`);
    }
    let removeSelectorData;
    try {
      removeSelectorData = parseRemoveSelector(selector);
    } catch (e) {
      logger.error(getErrorMessage(e));
      throw new Error(`${REMOVE_ERROR_PREFIX.INVALID_REMOVE}: '${selector}'`);
    }
    if (context.nextIndex === -1) {
      if (selector === removeSelectorData.selector) {
        // rule should have style or pseudo-class :remove()
        throw new Error(`${STYLE_ERROR_PREFIX.NO_STYLE_OR_REMOVE}: '${context.cssToParse}'`);
      } // stop parsing as there is no style declaration and selector parsed fine

      context.cssToParse = '';
    }
    let stylesOfSelector = [];
    let success = false;
    let ast;
    try {
      selector = removeSelectorData.selector;
      stylesOfSelector = removeSelectorData.stylesOfSelector; // validate found selector by parsing it to ast
      // so if it is invalid error will be thrown

      ast = extCssDoc.getSelectorAst(selector);
      success = true;
    } catch (e) {
      success = false;
    }
    if (context.nextIndex > 0) {
      // slice found valid selector part off
      // and parse rest of stylesheet later
      context.cssToParse = context.cssToParse.slice(context.nextIndex);
    }
    return {
      success,
      selector,
      ast,
      stylesOfSelector
    };
  };
  /**
   * Recursively parses style declaration string into `Style`s.
   *
   * @param context Stylesheet parser context.
   * @param styles Array of styles.
   *
   * @throws An error on invalid style declaration.
   * @returns A number index of the next `}` in `this.cssToParse`.
   */

  const parseUntilClosingBracket = (context, styles) => {
    // Expects ":", ";", and "}".
    REGEXP_DECLARATION_DIVIDER.lastIndex = context.nextIndex;
    let match = REGEXP_DECLARATION_DIVIDER.exec(context.cssToParse);
    if (match === null) {
      throw new Error(`${STYLE_ERROR_PREFIX.INVALID_STYLE}: '${context.cssToParse}'`);
    }
    let matchPos = match.index;
    let matched = match[0];
    if (matched === BRACKET.CURLY.RIGHT) {
      const declarationChunk = context.cssToParse.slice(context.nextIndex, matchPos);
      if (declarationChunk.trim().length === 0) {
        // empty style declaration
        // e.g. 'div { }'
        if (styles.length === 0) {
          throw new Error(`${STYLE_ERROR_PREFIX.NO_STYLE}: '${context.cssToParse}'`);
        } // else valid style parsed before it
        // e.g. '{ display: none; }' -- position is after ';'
      } else {
        // closing curly bracket '}' is matched before colon ':'
        // trimmed declarationChunk is not a space, between ';' and '}',
        // e.g. 'visible }' in style '{ display: none; visible }' after part before ';' is parsed
        throw new Error(`${STYLE_ERROR_PREFIX.INVALID_STYLE}: '${context.cssToParse}'`);
      }
      return matchPos;
    }
    if (matched === COLON) {
      const colonIndex = matchPos; // Expects ";" and "}".

      REGEXP_DECLARATION_END.lastIndex = colonIndex;
      match = REGEXP_DECLARATION_END.exec(context.cssToParse);
      if (match === null) {
        throw new Error(`${STYLE_ERROR_PREFIX.UNCLOSED_STYLE}: '${context.cssToParse}'`);
      }
      matchPos = match.index;
      matched = match[0]; // Populates the `styleMap` key-value map.

      const property = context.cssToParse.slice(context.nextIndex, colonIndex).trim();
      if (property.length === 0) {
        throw new Error(`${STYLE_ERROR_PREFIX.NO_PROPERTY}: '${context.cssToParse}'`);
      }
      const value = context.cssToParse.slice(colonIndex + 1, matchPos).trim();
      if (value.length === 0) {
        throw new Error(`${STYLE_ERROR_PREFIX.NO_VALUE}: '${context.cssToParse}'`);
      }
      styles.push({
        property,
        value
      }); // finish style parsing if '}' is found
      // e.g. '{ display: none }' -- no ';' at the end of declaration

      if (matched === BRACKET.CURLY.RIGHT) {
        return matchPos;
      }
    } // matchPos is the position of the next ';'
    // crop 'cssToParse' and re-run the loop

    context.cssToParse = context.cssToParse.slice(matchPos + 1);
    context.nextIndex = 0;
    return parseUntilClosingBracket(context, styles); // Should be a subject of tail-call optimization.
  };
  /**
   * Parses next style declaration part in stylesheet.
   *
   * @param context Stylesheet parser context.
   *
   * @returns Array of style data objects.
   */

  const parseNextStyle = context => {
    const styles = [];
    const styleEndPos = parseUntilClosingBracket(context, styles); // find next rule after the style declaration

    REGEXP_NON_WHITESPACE.lastIndex = styleEndPos + 1;
    const match = REGEXP_NON_WHITESPACE.exec(context.cssToParse);
    if (match === null) {
      context.cssToParse = '';
      return styles;
    }
    const matchPos = match.index; // cut out matched style declaration for previous selector

    context.cssToParse = context.cssToParse.slice(matchPos);
    return styles;
  };
  /**
   * Parses stylesheet of rules into rules data objects (non-recursively):
   * 1. Iterates through stylesheet string.
   * 2. Finds first `{` which can be style declaration start or part of selector.
   * 3. Validates found string part via selector parser; and if:
   *  - it throws error — saves string part to buffer as part of selector,
   *    slice next stylesheet part to `{` [2] and validates again [3];
   *  - no error — saves found string part as selector and starts to parse styles (recursively).
   *
   * @param rawStylesheet Raw stylesheet as string.
   * @param extCssDoc ExtCssDocument which uses cache while selectors parsing.
   * @throws An error on unsupported CSS features, e.g. comments or invalid stylesheet syntax.
   * @returns Array of rules data which contains:
   * - selector as string;
   * - ast to query elements by;
   * - map of styles to apply.
   */

  const parseStylesheet = (rawStylesheet, extCssDoc) => {
    const stylesheet = rawStylesheet.trim();
    if (stylesheet.includes(`${SLASH}${ASTERISK}`) && stylesheet.includes(`${ASTERISK}${SLASH}`)) {
      throw new Error(`${STYLE_ERROR_PREFIX.NO_COMMENT} in stylesheet: '${stylesheet}'`);
    }
    const context = {
      // any stylesheet should start with selector
      isSelector: true,
      // init value of parser position
      nextIndex: 0,
      // init value of cssToParse
      cssToParse: stylesheet,
      // buffer for collecting selector part
      selectorBuffer: '',
      // accumulator for rules
      rawRuleData: {
        selector: ''
      }
    };
    const rawResults = createRawResultsMap();
    let selectorData; // context.cssToParse is going to be cropped while its parsing

    while (context.cssToParse) {
      if (context.isSelector) {
        // find index of first opening curly bracket
        // which may mean start of style part and end of selector one
        context.nextIndex = context.cssToParse.indexOf(BRACKET.CURLY.LEFT); // rule should not start with style, selector is required
        // e.g. '{ display: none; }'

        if (context.selectorBuffer.length === 0 && context.nextIndex === 0) {
          throw new Error(`${STYLE_ERROR_PREFIX.NO_SELECTOR}: '${context.cssToParse}'`);
        }
        if (context.nextIndex === -1) {
          // no style declaration in rule
          // but rule still may contain :remove() pseudo-class
          context.selectorBuffer = context.cssToParse;
        } else {
          // collect string parts before opening curly bracket
          // until valid selector collected
          context.selectorBuffer += context.cssToParse.slice(0, context.nextIndex);
        }
        selectorData = parseSelectorPart(context, extCssDoc);
        if (selectorData.success) {
          // selector successfully parsed
          context.rawRuleData.selector = selectorData.selector.trim();
          context.rawRuleData.ast = selectorData.ast;
          context.rawRuleData.rawStyles = selectorData.stylesOfSelector;
          context.isSelector = false; // save rule data if there is no style declaration

          if (context.nextIndex === -1) {
            saveToRawResults(rawResults, context.rawRuleData); // clean up ruleContext

            restoreRuleAcc(context);
          } else {
            // skip the opening curly bracket at the start of style declaration part
            context.nextIndex = 1;
            context.selectorBuffer = '';
          }
        } else {
          // if selector was not successfully parsed parseSelectorPart(), continue stylesheet parsing:
          // save the found bracket to buffer and proceed to next loop iteration
          context.selectorBuffer += BRACKET.CURLY.LEFT; // delete `{` from cssToParse

          context.cssToParse = context.cssToParse.slice(1);
        }
      } else {
        var _context$rawRuleData$;

        // style declaration should be parsed
        const parsedStyles = parseNextStyle(context); // styles can be parsed from selector part if it has :remove() pseudo-class
        // e.g. '.banner:remove() { debug: true; }'

        (_context$rawRuleData$ = context.rawRuleData.rawStyles) === null || _context$rawRuleData$ === void 0 ? void 0 : _context$rawRuleData$.push(...parsedStyles); // save rule data to results

        saveToRawResults(rawResults, context.rawRuleData);
        context.nextIndex = 0; // clean up ruleContext

        restoreRuleAcc(context); // parse next rule selector after style successfully parsed

        context.isSelector = true;
      }
    }
    return combineRulesData(rawResults);
  };

  /**
   * Checks whether passed `arg` is number type.
   *
   * @param arg Value to check.
   *
   * @returns True if `arg` is number and not NaN.
   */
  const isNumber = arg => {
    return typeof arg === 'number' && !Number.isNaN(arg);
  };

  /**
   * The purpose of ThrottleWrapper is to throttle calls of the function
   * that applies ExtendedCss rules. The reasoning here is that the function calls
   * are triggered by MutationObserver and there may be many mutations in a short period of time.
   * We do not want to apply rules on every mutation so we use this helper to make sure
   * that there is only one call in the given amount of time.
   */

  class ThrottleWrapper {
    /**
     * Creates new ThrottleWrapper.
     * The {@link callback} should be executed not more often than {@link ThrottleWrapper.THROTTLE_DELAY_MS}.
     *
     * @param callback The callback.
     */
    constructor(callback) {
      this.callback = callback;
      this.executeCallback = this.executeCallback.bind(this);
    }
    /**
     * Calls the {@link callback} function and update bounded throttle wrapper properties.
     */

    executeCallback() {
      this.lastRunTime = performance.now();
      if (isNumber(this.timerId)) {
        clearTimeout(this.timerId);
        delete this.timerId;
      }
      this.callback();
    }
    /**
     * Schedules the {@link executeCallback} function execution via setTimeout.
     * It may triggered by MutationObserver job which may occur too ofter, so we limit the function execution:
     *
     * 1. If {@link timerId} is set, ignore the call, because the function is already scheduled to be executed;
     *
     * 2. If {@link lastRunTime} is set, we need to check the time elapsed time since the last call. If it is
     * less than {@link ThrottleWrapper.THROTTLE_DELAY_MS}, we schedule the function execution after the remaining time.
     * 
     * Otherwise, we execute the function asynchronously to ensure that it is executed 
     * in the correct order with respect to DOM events, by deferring its execution until after 
     * those tasks have completed.
     */

    run() {
      if (isNumber(this.timerId)) {
        // there is a pending execution scheduled
        return;
      }
      if (isNumber(this.lastRunTime)) {
        const elapsedTime = performance.now() - this.lastRunTime;
        if (elapsedTime < ThrottleWrapper.THROTTLE_DELAY_MS) {
          this.timerId = window.setTimeout(this.executeCallback, ThrottleWrapper.THROTTLE_DELAY_MS - elapsedTime);
          return;
        }
      }
      /**
       * We use `setTimeout` instead `requestAnimationFrame`
       * here because requestAnimationFrame can be delayed for a long time
       * when the browser saves battery or the engine is heavily loaded.
       */

      this.timerId = window.setTimeout(this.executeCallback);
    }
  }
  _defineProperty(ThrottleWrapper, "THROTTLE_DELAY_MS", 150);
  const LAST_EVENT_TIMEOUT_MS = 10;
  const IGNORED_EVENTS = ['mouseover', 'mouseleave', 'mouseenter', 'mouseout'];
  const SUPPORTED_EVENTS = [
  // keyboard events
  'keydown', 'keypress', 'keyup',
  // mouse events
  'auxclick', 'click', 'contextmenu', 'dblclick', 'mousedown', 'mouseenter', 'mouseleave', 'mousemove', 'mouseover', 'mouseout', 'mouseup', 'pointerlockchange', 'pointerlockerror', 'select', 'wheel']; // 'wheel' event makes scrolling in Safari twitchy
  // https://github.com/AdguardTeam/ExtendedCss/issues/120

  const SAFARI_PROBLEMATIC_EVENTS = ['wheel'];
  /**
   * We use EventTracker to track the event that is likely to cause the mutation.
   * The problem is that we cannot use `window.event` directly from the mutation observer call
   * as we're not in the event handler context anymore.
   */

  class EventTracker {
    /**
     * Creates new EventTracker.
     */
    constructor() {
      _defineProperty(this, "getLastEventType", () => this.lastEventType);
      _defineProperty(this, "getTimeSinceLastEvent", () => {
        if (!this.lastEventTime) {
          return null;
        }
        return Date.now() - this.lastEventTime;
      });
      this.trackedEvents = isSafariBrowser ? SUPPORTED_EVENTS.filter(event => !SAFARI_PROBLEMATIC_EVENTS.includes(event)) : SUPPORTED_EVENTS;
      this.trackedEvents.forEach(eventName => {
        document.documentElement.addEventListener(eventName, this.trackEvent, true);
      });
    }
    /**
     * Callback for event listener for events tracking.
     *
     * @param event Any event.
     */

    trackEvent(event) {
      this.lastEventType = event.type;
      this.lastEventTime = Date.now();
    }

    /**
     * Checks whether the last caught event should be ignored.
     *
     * @returns True if event should be ignored.
     */
    isIgnoredEventType() {
      const lastEventType = this.getLastEventType();
      const sinceLastEventTime = this.getTimeSinceLastEvent();
      return !!lastEventType && IGNORED_EVENTS.includes(lastEventType) && !!sinceLastEventTime && sinceLastEventTime < LAST_EVENT_TIMEOUT_MS;
    }
    /**
     * Stops event tracking by removing event listener.
     */

    stopTracking() {
      this.trackedEvents.forEach(eventName => {
        document.documentElement.removeEventListener(eventName, this.trackEvent, true);
      });
    }
  }

  /**
   * We are trying to limit the number of callback calls by not calling it on all kind of "hover" events.
   * The rationale behind this is that "hover" events often cause attributes modification,
   * but re-applying extCSS rules will be useless as these attribute changes are usually transient.
   *
   * @param mutations DOM elements mutation records.
   * @returns True if all mutations are about attributes changes, otherwise false.
   */

  function shouldIgnoreMutations(mutations) {
    // ignore if all mutations are about attributes changes
    return !mutations.some(m => m.type !== 'attributes');
  }
  /**
   * Adds new {@link context.domMutationObserver} instance and connect it to document.
   * 
   * @param context ExtendedCss context.
   */

  function observeDocument(context) {
    if (context.isDomObserved) {
      return;
    } // enable dynamically added elements handling

    context.isDomObserved = true;
    context.domMutationObserver = new natives.MutationObserver(mutations => {
      if (!mutations || mutations.length === 0) {
        return;
      }
      const eventTracker = new EventTracker();
      if (eventTracker.isIgnoredEventType() && shouldIgnoreMutations(mutations)) {
        return;
      } // save instance of EventTracker to context
      // for removing its event listeners on disconnectDocument() while mainDisconnect()

      context.eventTracker = eventTracker;
      context.scheduler.run();
    });
    context.domMutationObserver.observe(document, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['id', 'class']
    });
  }
  /**
   * Disconnect from {@link context.domMutationObserver}.
   * 
   * @param context ExtendedCss context.
   */

  function disconnectDocument(context) {
    if (!context.isDomObserved) {
      return;
    } // disable dynamically added elements handling

    context.isDomObserved = false;
    if (context.domMutationObserver) {
      context.domMutationObserver.disconnect();
    } // clean up event listeners

    if (context.eventTracker) {
      context.eventTracker.stopTracking();
    }
  }
  const CONTENT_ATTR_PREFIX_REGEXP = /^("|')adguard.+?/;
  /**
   * Removes affectedElement.node from DOM.
   *
   * @param context ExtendedCss context.
   * @param affectedElement Affected element.
   */

  const removeElement = (context, affectedElement) => {
    const {
      node
    } = affectedElement;
    affectedElement.removed = true;
    const elementSelector = getElementSelectorPath(node); // check if the element has been already removed earlier

    const elementRemovalsCounter = context.removalsStatistic[elementSelector] || 0; // if removals attempts happened more than specified we do not try to remove node again

    if (elementRemovalsCounter > MAX_STYLE_PROTECTION_COUNT) {
      logger.error(`ExtendedCss: infinite loop protection for selector: '${elementSelector}'`);
      return;
    }
    if (node.parentElement) {
      node.parentElement.removeChild(node);
      context.removalsStatistic[elementSelector] = elementRemovalsCounter + 1;
    }
  };
  /**
   * Sets style to the specified DOM node.
   *
   * @param node DOM element.
   * @param style Style to set.
   */

  const setStyleToElement = (node, style) => {
    if (!(node instanceof HTMLElement)) {
      return;
    }
    Object.keys(style).forEach(prop => {
      // Apply this style only to existing properties
      // We cannot use hasOwnProperty here (does not work in FF)
      if (typeof node.style.getPropertyValue(prop.toString()) !== 'undefined') {
        let value = style[prop];
        if (!value) {
          return;
        } // do not apply 'content' style given by tsurlfilter
        // which is needed only for BeforeStyleAppliedCallback

        if (prop === CONTENT_CSS_PROPERTY && value.match(CONTENT_ATTR_PREFIX_REGEXP)) {
          return;
        } // First we should remove !important attribute (or it won't be applied')

        value = removeSuffix(value.trim(), '!important').trim();
        node.style.setProperty(prop, value, 'important');
      }
    });
  };
  /**
   * Checks the required properties of `affectedElement`
   * **before** `beforeStyleApplied()` execution.
   *
   * @param affectedElement Affected element.
   *
   * @returns False if there is no `node` or `rules`
   * or `rules` is not an array.
   */

  const isIAffectedElement = affectedElement => {
    return 'node' in affectedElement && 'rules' in affectedElement && affectedElement.rules instanceof Array;
  };
  /**
   * Checks the required properties of `affectedElement`
   * **after** `beforeStyleApplied()` execution.
   * These properties are needed for proper internal usage.
   *
   * @param affectedElement Affected element.
   *
   * @returns False if there is no `node` or `rules`
   * or `rules` is not an array.
   */

  const isAffectedElement = affectedElement => {
    return 'node' in affectedElement && 'originalStyle' in affectedElement && 'rules' in affectedElement && affectedElement.rules instanceof Array;
  };
  /**
   * Applies style to the specified DOM node.
   *
   * @param context ExtendedCss context.
   * @param rawAffectedElement Object containing DOM node and rule to be applied.
   *
   * @throws An error if affectedElement has no style to apply.
   */

  const applyStyle = (context, rawAffectedElement) => {
    if (rawAffectedElement.protectionObserver) {
      // style is already applied and protected by the observer
      return;
    }
    let affectedElement;
    if (context.beforeStyleApplied) {
      if (!isIAffectedElement(rawAffectedElement)) {
        throw new Error("Returned IAffectedElement should have 'node' and 'rules' properties");
      }
      affectedElement = context.beforeStyleApplied(rawAffectedElement);
      if (!affectedElement) {
        throw new Error("Callback 'beforeStyleApplied' should return IAffectedElement");
      }
    } else {
      affectedElement = rawAffectedElement;
    }
    if (!isAffectedElement(affectedElement)) {
      throw new Error("Returned IAffectedElement should have 'node' and 'rules' properties");
    }
    const {
      node,
      rules
    } = affectedElement;
    for (let i = 0; i < rules.length; i += 1) {
      const rule = rules[i];
      const selector = rule === null || rule === void 0 ? void 0 : rule.selector;
      const style = rule === null || rule === void 0 ? void 0 : rule.style;
      const debug = rule === null || rule === void 0 ? void 0 : rule.debug; // rule may not have style to apply
      // e.g. 'div:has(> a) { debug: true }' -> means no style to apply, and enable debug mode

      if (style) {
        if (style[REMOVE_PSEUDO_MARKER] === PSEUDO_PROPERTY_POSITIVE_VALUE) {
          removeElement(context, affectedElement);
          return;
        }
        setStyleToElement(node, style);
      } else if (!debug) {
        // but rule should not have both style and debug properties
        throw new Error(`No style declaration in rule for selector: '${selector}'`);
      }
    }
  };
  /**
   * Reverts style for the affected object.
   *
   * @param affectedElement Affected element.
   */

  const revertStyle = affectedElement => {
    if (affectedElement.protectionObserver) {
      affectedElement.protectionObserver.disconnect();
    }
    affectedElement.node.style.cssText = affectedElement.originalStyle;
  };

  /**
   * ExtMutationObserver is a wrapper over regular MutationObserver with one additional function:
   * it keeps track of the number of times we called the "ProtectionCallback".
   *
   * We use an instance of this to monitor styles added by ExtendedCss
   * and to make sure these styles are recovered if the page script attempts to modify them.
   *
   * However, we want to avoid endless loops of modification if the page script repeatedly modifies the styles.
   * So we keep track of the number of calls and observe() makes a decision
   * whether to continue recovering the styles or not.
   */

  class ExtMutationObserver {
    /**
     * Extra property for keeping 'style fix counts'.
     */

    /**
     * Creates new ExtMutationObserver.
     *
     * @param protectionCallback Callback which execution should be counted.
     */
    constructor(protectionCallback) {
      this.styleProtectionCount = 0;
      this.observer = new natives.MutationObserver(mutations => {
        if (!mutations.length) {
          return;
        }
        this.styleProtectionCount += 1;
        protectionCallback(mutations, this);
      });
    }
    /**
     * Starts to observe target element,
     * prevents infinite loop of observing due to the limited number of times of callback runs.
     *
     * @param target Target to observe.
     * @param options Mutation observer options.
     */

    observe(target, options) {
      if (this.styleProtectionCount < MAX_STYLE_PROTECTION_COUNT) {
        this.observer.observe(target, options);
      } else {
        logger.error('ExtendedCss: infinite loop protection for style');
      }
    }
    /**
     * Stops ExtMutationObserver from observing any mutations.
     * Until the `observe()` is used again, `protectionCallback` will not be invoked.
     */

    disconnect() {
      this.observer.disconnect();
    }
  }
  const PROTECTION_OBSERVER_OPTIONS = {
    attributes: true,
    attributeOldValue: true,
    attributeFilter: ['style']
  };
  /**
   * Creates MutationObserver protection callback.
   *
   * @param styles Styles data object.
   *
   * @returns Callback for styles protection.
   */

  const createProtectionCallback = styles => {
    const protectionCallback = (mutations, extObserver) => {
      if (!mutations[0]) {
        return;
      }
      const {
        target
      } = mutations[0];
      extObserver.disconnect();
      styles.forEach(style => {
        setStyleToElement(target, style);
      });
      extObserver.observe(target, PROTECTION_OBSERVER_OPTIONS);
    };
    return protectionCallback;
  };
  /**
   * Sets up a MutationObserver which protects style attributes from changes.
   *
   * @param node DOM node.
   * @param rules Rule data objects.
   * @returns Mutation observer used to protect attribute or null if there's nothing to protect.
   */

  const protectStyleAttribute = (node, rules) => {
    if (!natives.MutationObserver) {
      return null;
    }
    const styles = [];
    rules.forEach(ruleData => {
      const {
        style
      } = ruleData; // some rules might have only debug property in style declaration
      // e.g. 'div:has(> a) { debug: true }' -> parsed to boolean `ruleData.debug`
      // so no style is fine, and here we should collect only valid styles to protect

      if (style) {
        styles.push(style);
      }
    });
    const protectionObserver = new ExtMutationObserver(createProtectionCallback(styles));
    protectionObserver.observe(node, PROTECTION_OBSERVER_OPTIONS);
    return protectionObserver;
  };
  const STATS_DECIMAL_DIGITS_COUNT = 4;

  /**
   * A helper class for applied rule stats.
   */
  class TimingStats {
    /**
     * Creates new TimingStats.
     */
    constructor() {
      this.appliesTimings = [];
      this.appliesCount = 0;
      this.timingsSum = 0;
      this.meanTiming = 0;
      this.squaredSum = 0;
      this.standardDeviation = 0;
    }
    /**
     * Observe target element and mark observer as active.
     *
     * @param elapsedTimeMs Time in ms.
     */

    push(elapsedTimeMs) {
      this.appliesTimings.push(elapsedTimeMs);
      this.appliesCount += 1;
      this.timingsSum += elapsedTimeMs;
      this.meanTiming = this.timingsSum / this.appliesCount;
      this.squaredSum += elapsedTimeMs * elapsedTimeMs;
      this.standardDeviation = Math.sqrt(this.squaredSum / this.appliesCount - Math.pow(this.meanTiming, 2));
    }
  }

  /**
   * Makes the timestamps more readable.
   *
   * @param timestamp Raw timestamp.
   *
   * @returns Fine-looking timestamps.
   */
  const beautifyTimingNumber = timestamp => {
    return Number(timestamp.toFixed(STATS_DECIMAL_DIGITS_COUNT));
  };
  /**
   * Improves timing stats readability.
   *
   * @param rawTimings Collected timings with raw timestamp.
   *
   * @returns Fine-looking timing stats.
   */

  const beautifyTimings = rawTimings => {
    return {
      appliesTimings: rawTimings.appliesTimings.map(t => beautifyTimingNumber(t)),
      appliesCount: beautifyTimingNumber(rawTimings.appliesCount),
      timingsSum: beautifyTimingNumber(rawTimings.timingsSum),
      meanTiming: beautifyTimingNumber(rawTimings.meanTiming),
      standardDeviation: beautifyTimingNumber(rawTimings.standardDeviation)
    };
  };
  /**
   * Prints timing information if debugging mode is enabled.
   *
   * @param context ExtendedCss context.
   */

  const printTimingInfo = context => {
    if (context.areTimingsPrinted) {
      return;
    }
    context.areTimingsPrinted = true;
    const timingsLogData = {};
    context.parsedRules.forEach(ruleData => {
      if (ruleData.timingStats) {
        const {
          selector,
          style,
          debug,
          matchedElements
        } = ruleData; // style declaration for some rules is parsed to debug property and no style to apply
        // e.g. 'div:has(> a) { debug: true }'

        if (!style && !debug) {
          throw new Error(`Rule should have style declaration for selector: '${selector}'`);
        }
        const selectorData = {
          selectorParsed: selector,
          timings: beautifyTimings(ruleData.timingStats)
        }; // `ruleData.style` may contain `remove` pseudo-property
        // and make logs look better

        if (style && style[REMOVE_PSEUDO_MARKER] === PSEUDO_PROPERTY_POSITIVE_VALUE) {
          selectorData.removed = true; // no matchedElements for such case as they are removed after ExtendedCss applied
        } else {
          selectorData.styleApplied = style || null;
          selectorData.matchedElements = matchedElements;
        }
        timingsLogData[selector] = selectorData;
      }
    });
    if (Object.keys(timingsLogData).length === 0) {
      return;
    } // add location.href to the message to distinguish frames

    logger.info('[ExtendedCss] Timings in milliseconds for %o:\n%o', window.location.href, timingsLogData);
  };

  /**
   * Finds affectedElement object for the specified DOM node.
   *
   * @param affElements Array of affected elements — context.affectedElements.
   * @param domNode DOM node.
   * @returns Found affectedElement or undefined.
   */

  const findAffectedElement = (affElements, domNode) => {
    return affElements.find(affEl => affEl.node === domNode);
  };
  /**
   * Applies specified rule and returns list of elements affected.
   *
   * @param context ExtendedCss context.
   * @param ruleData Rule to apply.
   * @returns List of elements affected by the rule.
   */

  const applyRule = (context, ruleData) => {
    // debugging mode can be enabled in two ways:
    // 1. for separate rules - by `{ debug: true; }`
    // 2. for all rules simultaneously by:
    //   - `{ debug: global; }` in any rule
    //   - positive `debug` property in ExtCssConfiguration
    const isDebuggingMode = !!ruleData.debug || context.debug;
    let startTime;
    if (isDebuggingMode) {
      startTime = performance.now();
    }
    const {
      ast
    } = ruleData;
    const nodes = []; // selector can be successfully parser into ast with no error
    // but its applying by native Document.querySelectorAll() still may throw an error
    // e.g. 'div[..banner]'

    try {
      nodes.push(...selectElementsByAst(ast));
    } catch (e) {
      // log the error only in debug mode
      if (context.debug) {
        logger.error(getErrorMessage(e));
      }
    }
    nodes.forEach(node => {
      let affectedElement = findAffectedElement(context.affectedElements, node);
      if (affectedElement) {
        affectedElement.rules.push(ruleData);
        applyStyle(context, affectedElement);
      } else {
        // Applying style first time
        const originalStyle = node.style.cssText;
        affectedElement = {
          node,
          // affected DOM node
          rules: [ruleData],
          // rule to be applied
          originalStyle,
          // original node style
          protectionObserver: null // style attribute observer
        };
        applyStyle(context, affectedElement);
        context.affectedElements.push(affectedElement);
      }
    });
    if (isDebuggingMode && startTime) {
      const elapsedTimeMs = performance.now() - startTime;
      if (!ruleData.timingStats) {
        ruleData.timingStats = new TimingStats();
      }
      ruleData.timingStats.push(elapsedTimeMs);
    }
    return nodes;
  };
  /**
   * Applies filtering rules.
   *
   * @param context ExtendedCss context.
   */

  const applyRules = context => {
    const newSelectedElements = []; // some rules could make call - selector.querySelectorAll() temporarily to change node id attribute
    // this caused MutationObserver to call recursively
    // https://github.com/AdguardTeam/ExtendedCss/issues/81

    disconnectDocument(context);
    context.parsedRules.forEach(ruleData => {
      const nodes = applyRule(context, ruleData);
      Array.prototype.push.apply(newSelectedElements, nodes); // save matched elements to ruleData as linked to applied rule
      // only for debugging purposes

      if (ruleData.debug) {
        ruleData.matchedElements = nodes;
      }
    }); // Now revert styles for elements which are no more affected

    let affLength = context.affectedElements.length; // do nothing if there is no elements to process

    while (affLength) {
      const affectedElement = context.affectedElements[affLength - 1];
      if (!affectedElement) {
        break;
      }
      if (!newSelectedElements.includes(affectedElement.node)) {
        // Time to revert style
        revertStyle(affectedElement);
        context.affectedElements.splice(affLength - 1, 1);
      } else if (!affectedElement.removed) {
        // Add style protection observer
        // Protect "style" attribute from changes
        if (!affectedElement.protectionObserver) {
          affectedElement.protectionObserver = protectStyleAttribute(affectedElement.node, affectedElement.rules);
        }
      }
      affLength -= 1;
    } // After styles are applied we can start observe again

    observeDocument(context);
    printTimingInfo(context);
  };

  /**
   * Result of selector validation.
   */

  /**
   * Main class of ExtendedCss lib.
   *
   * Parses css stylesheet with any selectors (passed to its argument as styleSheet),
   * and guarantee its applying as mutation observer is used to prevent the restyling of needed elements by other scripts.
   * This style protection is limited to 50 times to avoid infinite loop (MAX_STYLE_PROTECTION_COUNT).
   * Our own ThrottleWrapper is used for styles applying to avoid too often lib reactions on page mutations.
   *
   * Constructor creates the instance of class which should be run be `apply()` method to apply the rules,
   * and the applying can be stopped by `dispose()`.
   *
   * Can be used to select page elements by selector with `query()` method (similar to `Document.querySelectorAll()`),
   * which does not require instance creating.
   */
  class ExtendedCss {
    /**
     * Creates new ExtendedCss.
     *
     * @param configuration ExtendedCss configuration.
     */
    constructor(configuration) {
      if (!configuration) {
        throw new Error('ExtendedCss configuration should be provided.');
      }
      this.applyRulesCallbackListener = this.applyRulesCallbackListener.bind(this);
      this.context = {
        beforeStyleApplied: configuration.beforeStyleApplied,
        debug: false,
        affectedElements: [],
        isDomObserved: false,
        removalsStatistic: {},
        parsedRules: [],
        scheduler: new ThrottleWrapper(this.applyRulesCallbackListener)
      }; // TODO: throw an error instead of logging and handle it in related products.

      if (!isBrowserSupported()) {
        logger.error('Browser is not supported by ExtendedCss');
        return;
      } // at least 'styleSheet' or 'cssRules' should be provided

      if (!configuration.styleSheet && !configuration.cssRules) {
        throw new Error("ExtendedCss configuration should have 'styleSheet' or 'cssRules' defined.");
      } // 'styleSheet' and 'cssRules' are optional
      // and both can be provided at the same time
      // so both should be parsed and applied in such case

      if (configuration.styleSheet) {
        // stylesheet parsing can fail on some invalid selectors
        try {
          this.context.parsedRules.push(...parseStylesheet(configuration.styleSheet, extCssDocument));
        } catch (e) {
          // eslint-disable-next-line max-len
          throw new Error(`Pass the rules as configuration.cssRules since configuration.styleSheet cannot be parsed because of: '${getErrorMessage(e)}'`);
        }
      }
      if (configuration.cssRules) {
        this.context.parsedRules.push(...parseRules(configuration.cssRules, extCssDocument));
      } // true if set in configuration
      // or any rule in styleSheet has `debug: global`

      this.context.debug = configuration.debug || this.context.parsedRules.some(ruleData => {
        return ruleData.debug === DEBUG_PSEUDO_PROPERTY_GLOBAL_VALUE;
      });
      if (this.context.beforeStyleApplied && typeof this.context.beforeStyleApplied !== 'function') {
        // eslint-disable-next-line max-len
        throw new Error(`Invalid configuration. Type of 'beforeStyleApplied' should be a function, received: '${typeof this.context.beforeStyleApplied}'`);
      }
    }
    /**
     * Invokes {@link applyRules} function with current app context.
     * 
     * This method is bound to the class instance in the constructor because it is called
     * in {@link ThrottleWrapper} and on the DOMContentLoaded event.
     */

    applyRulesCallbackListener() {
      applyRules(this.context);
    }
    /**
     * Initializes ExtendedCss.
     *
     * Should be executed on page ASAP,
     * otherwise the :contains() pseudo-class may work incorrectly.
     */

    init() {
      /**
       * Native Node textContent getter must be intercepted as soon as possible,
       * and stored as it is needed for proper work of :contains() pseudo-class
       * because DOM Node prototype 'textContent' property may be mocked.
       *
       * @see {@link https://github.com/AdguardTeam/ExtendedCss/issues/127}
       */
      nativeTextContent.setGetter();
    }
    /**
     * Applies stylesheet rules on page.
     */

    apply() {
      applyRules(this.context);
      if (document.readyState !== 'complete') {
        document.addEventListener('DOMContentLoaded', this.applyRulesCallbackListener, false);
      }
    }
    /**
     * Disposes ExtendedCss and removes our styles from matched elements.
     */

    dispose() {
      disconnectDocument(this.context);
      this.context.affectedElements.forEach(el => {
        revertStyle(el);
      });
      document.removeEventListener('DOMContentLoaded', this.applyRulesCallbackListener, false);
    }
    /**
     * Exposed for testing purposes only.
     *
     * @returns Array of AffectedElement data objects.
     */

    getAffectedElements() {
      return this.context.affectedElements;
    }
    /**
     * Returns a list of the document's elements that match the specified selector.
     * Uses ExtCssDocument.querySelectorAll().
     *
     * @param selector Selector text.
     * @param [noTiming=true] If true — do not print the timings to the console.
     *
     * @throws An error if selector is not valid.
     * @returns A list of elements that match the selector.
     */

    static query(selector) {
      let noTiming = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : true;
      if (typeof selector !== 'string') {
        throw new Error('Selector should be defined as a string.');
      }
      const start = performance.now();
      try {
        return extCssDocument.querySelectorAll(selector);
      } finally {
        const end = performance.now();
        if (!noTiming) {
          logger.info(`[ExtendedCss] Elapsed: ${Math.round((end - start) * 1000)} μs.`);
        }
      }
    }
    /**
     * Validates selector.
     *
     * @param inputSelector Selector text to validate.
     *
     * @returns Result of selector validation.
     */

    static validate(inputSelector) {
      try {
        // ExtendedCss in general supports :remove() in selector
        // but ExtendedCss.query() does not support it as it should be parsed by stylesheet parser.
        // so for validation we have to handle selectors with `:remove()` in it
        const {
          selector
        } = parseRemoveSelector(inputSelector);
        ExtendedCss.query(selector);
        return {
          ok: true,
          error: null
        };
      } catch (e) {
        // not valid input `selector` should be logged eventually
        const error = `Error: Invalid selector: '${inputSelector}' -- ${getErrorMessage(e)}`;
        return {
          ok: false,
          error
        };
      }
    }
  }
  function AmazonApstag(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function AmazonApstag(source) {
      var apstagWrapper = {
        fetchBids(a, b) {
          if (typeof b === "function") {
            b([]);
          }
        },
        init: noopFunc,
        setDisplayBids: noopFunc,
        targetingKeys: noopFunc
      };
      window.apstag = apstagWrapper;
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      AmazonApstag.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function DidomiLoader(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function DidomiLoader(source) {
      function UserConsentStatusForVendorSubscribe() {}
      UserConsentStatusForVendorSubscribe.prototype.filter = function () {
        return new UserConsentStatusForVendorSubscribe();
      };
      UserConsentStatusForVendorSubscribe.prototype.subscribe = noopFunc;
      function UserConsentStatusForVendor() {}
      UserConsentStatusForVendor.prototype.first = function () {
        return new UserConsentStatusForVendorSubscribe();
      };
      UserConsentStatusForVendor.prototype.filter = function () {
        return new UserConsentStatusForVendorSubscribe();
      };
      UserConsentStatusForVendor.prototype.subscribe = noopFunc;
      var DidomiWrapper = {
        isConsentRequired: falseFunc,
        getUserConsentStatusForPurpose: trueFunc,
        getUserConsentStatus: trueFunc,
        getUserStatus: noopFunc,
        getRequiredPurposes: noopArray,
        getUserConsentStatusForVendor: trueFunc,
        Purposes: {
          Cookies: "cookies"
        },
        notice: {
          configure: noopFunc,
          hide: noopFunc,
          isVisible: falseFunc,
          show: noopFunc,
          showDataProcessing: trueFunc
        },
        isUserConsentStatusPartial: falseFunc,
        on() {
          return {
            actions: {},
            emitter: {},
            services: {},
            store: {}
          };
        },
        shouldConsentBeCollected: falseFunc,
        getUserConsentStatusForAll: noopFunc,
        getObservableOnUserConsentStatusForVendor() {
          return new UserConsentStatusForVendor();
        }
      };
      window.Didomi = DidomiWrapper;
      var didomiStateWrapper = {
        didomiExperimentId: "",
        didomiExperimentUserGroup: "",
        didomiGDPRApplies: 1,
        didomiIABConsent: "",
        didomiPurposesConsent: "",
        didomiPurposesConsentDenied: "",
        didomiPurposesConsentUnknown: "",
        didomiVendorsConsent: "",
        didomiVendorsConsentDenied: "",
        didomiVendorsConsentUnknown: "",
        didomiVendorsRawConsent: "",
        didomiVendorsRawConsentDenied: "",
        didomiVendorsRawConsentUnknown: ""
      };
      window.didomiState = didomiStateWrapper;
      var tcData = {
        eventStatus: "tcloaded",
        gdprApplies: false,
        listenerId: noopFunc,
        vendor: {
          consents: []
        },
        purpose: {
          consents: []
        }
      };
      var __tcfapiWrapper = function __tcfapiWrapper(command, version, callback) {
        if (typeof callback !== "function" || command === "removeEventListener") {
          return;
        }
        callback(tcData, true);
      };
      window.__tcfapi = __tcfapiWrapper;
      var didomiEventListenersWrapper = {
        stub: true,
        push: noopFunc
      };
      window.didomiEventListeners = didomiEventListenersWrapper;
      var didomiOnReadyWrapper = {
        stub: true,
        push(arg) {
          if (typeof arg !== "function") {
            return;
          }
          if (document.readyState !== "complete") {
            window.addEventListener("load", function () {
              setTimeout(arg(window.Didomi));
            });
          } else {
            setTimeout(arg(window.Didomi));
          }
        }
      };
      window.didomiOnReady = window.didomiOnReady || didomiOnReadyWrapper;
      if (Array.isArray(window.didomiOnReady)) {
        window.didomiOnReady.forEach(function (arg) {
          if (typeof arg === "function") {
            try {
              setTimeout(arg(window.Didomi));
            } catch (e) {}
          }
        });
      }
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    function noopArray() {
      return [];
    }
    function trueFunc() {
      return true;
    }
    function falseFunc() {
      return false;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      DidomiLoader.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function Fingerprintjs2(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function Fingerprintjs2(source) {
      var browserId = "";
      for (var i = 0; i < 8; i += 1) {
        browserId += (Math.random() * 65536 + 4096).toString(16).slice(-4);
      }
      var Fingerprint2 = function Fingerprint2() {};
      Fingerprint2.get = function (options, callback) {
        if (!callback) {
          callback = options;
        }
        setTimeout(function () {
          if (callback) {
            callback(browserId, []);
          }
        }, 1);
      };
      Fingerprint2.prototype = {
        get: Fingerprint2.get
      };
      window.Fingerprint2 = Fingerprint2;
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      Fingerprintjs2.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function Fingerprintjs3(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function Fingerprintjs3(source) {
      var visitorId = function () {
        var id = "";
        for (var i = 0; i < 8; i += 1) {
          id += (Math.random() * 65536 + 4096).toString(16).slice(-4);
        }
        return id;
      }();
      var FingerprintJS = function FingerprintJS() {};
      FingerprintJS.prototype = {
        load() {
          return Promise.resolve(new FingerprintJS());
        },
        get() {
          return Promise.resolve({
            visitorId: visitorId
          });
        },
        hashComponents: noopStr
      };
      window.FingerprintJS = new FingerprintJS();
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopStr() {
      return "";
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      Fingerprintjs3.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function Gemius(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function Gemius(source) {
      var GemiusPlayer = function GemiusPlayer() {};
      GemiusPlayer.prototype = {
        setVideoObject: noopFunc,
        newProgram: noopFunc,
        programEvent: noopFunc,
        newAd: noopFunc,
        adEvent: noopFunc
      };
      window.GemiusPlayer = GemiusPlayer;
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      Gemius.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function GoogleAnalytics(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function GoogleAnalytics(source) {
      var _window$googleAnalyti;
      var Tracker = function Tracker() {};
      var proto = Tracker.prototype;
      proto.get = noopFunc;
      proto.set = noopFunc;
      proto.send = noopFunc;
      var googleAnalyticsName = window.GoogleAnalyticsObject || "ga";
      var queue = (_window$googleAnalyti = window[googleAnalyticsName]) === null || _window$googleAnalyti === void 0 ? void 0 : _window$googleAnalyti.q;
      function ga(a) {
        var len = arguments.length;
        if (len === 0) {
          return;
        }
        var lastArg = arguments[len - 1];
        var replacer;
        if (lastArg instanceof Object && lastArg !== null && typeof lastArg.hitCallback === "function") {
          replacer = lastArg.hitCallback;
        } else if (typeof lastArg === "function") {
          replacer = function replacer() {
            lastArg(ga.create());
          };
        }
        try {
          setTimeout(replacer, 1);
        } catch (ex) {}
      }
      ga.create = function () {
        return new Tracker();
      };
      ga.getByName = function () {
        return new Tracker();
      };
      ga.getAll = function () {
        return [new Tracker()];
      };
      ga.remove = noopFunc;
      ga.loaded = true;
      window[googleAnalyticsName] = ga;
      if (Array.isArray(queue)) {
        var push = function push(arg) {
          ga(...arg);
        };
        queue.push = push;
        queue.forEach(push);
      }
      var {
        dataLayer: dataLayer,
        google_optimize: google_optimize
      } = window;
      if (dataLayer instanceof Object === false) {
        return;
      }
      if (dataLayer.hide instanceof Object && typeof dataLayer.hide.end === "function") {
        dataLayer.hide.end();
      }
      var handleCallback = function handleCallback(dataObj, funcName) {
        if (dataObj && typeof dataObj[funcName] === "function") {
          setTimeout(dataObj[funcName]);
        }
      };
      if (typeof dataLayer.push === "function") {
        dataLayer.push = function (data) {
          if (data instanceof Object) {
            handleCallback(data, "eventCallback");
            for (var key in data) {
              handleCallback(data[key], "event_callback");
            }
            if (!data.hasOwnProperty("eventCallback") && !data.hasOwnProperty("eventCallback")) {
              [].push.call(window.dataLayer, data);
            }
          }
          if (Array.isArray(data)) {
            data.forEach(function (arg) {
              handleCallback(arg, "callback");
            });
          }
          return noopFunc;
        };
      }
      if (google_optimize instanceof Object && typeof google_optimize.get === "function") {
        var googleOptimizeWrapper = {
          get: noopFunc
        };
        window.google_optimize = googleOptimizeWrapper;
      }
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      GoogleAnalytics.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function GoogleAnalyticsGa(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function GoogleAnalyticsGa(source) {
      function Gaq() {}
      Gaq.prototype.Na = noopFunc;
      Gaq.prototype.O = noopFunc;
      Gaq.prototype.Sa = noopFunc;
      Gaq.prototype.Ta = noopFunc;
      Gaq.prototype.Va = noopFunc;
      Gaq.prototype._createAsyncTracker = noopFunc;
      Gaq.prototype._getAsyncTracker = noopFunc;
      Gaq.prototype._getPlugin = noopFunc;
      Gaq.prototype.push = function (data) {
        if (typeof data === "function") {
          data();
          return;
        }
        if (Array.isArray(data) === false) {
          return;
        }
        if (typeof data[0] === "string" && /(^|\.)_link$/.test(data[0]) && typeof data[1] === "string") {
          window.location.assign(data[1]);
        }
        if (data[0] === "_set" && data[1] === "hitCallback" && typeof data[2] === "function") {
          data[2]();
        }
      };
      var gaq = new Gaq();
      var asyncTrackers = window._gaq || [];
      if (Array.isArray(asyncTrackers)) {
        while (asyncTrackers[0]) {
          gaq.push(asyncTrackers.shift());
        }
      }
      window._gaq = gaq.qf = gaq;
      function Gat() {}
      var api = ["_addIgnoredOrganic", "_addIgnoredRef", "_addItem", "_addOrganic", "_addTrans", "_clearIgnoredOrganic", "_clearIgnoredRef", "_clearOrganic", "_cookiePathCopy", "_deleteCustomVar", "_getName", "_setAccount", "_getAccount", "_getClientInfo", "_getDetectFlash", "_getDetectTitle", "_getLinkerUrl", "_getLocalGifPath", "_getServiceMode", "_getVersion", "_getVisitorCustomVar", "_initData", "_link", "_linkByPost", "_setAllowAnchor", "_setAllowHash", "_setAllowLinker", "_setCampContentKey", "_setCampMediumKey", "_setCampNameKey", "_setCampNOKey", "_setCampSourceKey", "_setCampTermKey", "_setCampaignCookieTimeout", "_setCampaignTrack", "_setClientInfo", "_setCookiePath", "_setCookiePersistence", "_setCookieTimeout", "_setCustomVar", "_setDetectFlash", "_setDetectTitle", "_setDomainName", "_setLocalGifPath", "_setLocalRemoteServerMode", "_setLocalServerMode", "_setReferrerOverride", "_setRemoteServerMode", "_setSampleRate", "_setSessionTimeout", "_setSiteSpeedSampleRate", "_setSessionCookieTimeout", "_setVar", "_setVisitorCookieTimeout", "_trackEvent", "_trackPageLoadTime", "_trackPageview", "_trackSocial", "_trackTiming", "_trackTrans", "_visitCode"];
      var tracker = api.reduce(function (res, funcName) {
        res[funcName] = noopFunc;
        return res;
      }, {});
      tracker._getLinkerUrl = function (a) {
        return a;
      };
      tracker._link = function (url) {
        if (typeof url !== "string") {
          return;
        }
        try {
          window.location.assign(url);
        } catch (e) {
          logMessage(source, e);
        }
      };
      Gat.prototype._anonymizeIP = noopFunc;
      Gat.prototype._createTracker = noopFunc;
      Gat.prototype._forceSSL = noopFunc;
      Gat.prototype._getPlugin = noopFunc;
      Gat.prototype._getTracker = function () {
        return tracker;
      };
      Gat.prototype._getTrackerByName = function () {
        return tracker;
      };
      Gat.prototype._getTrackers = noopFunc;
      Gat.prototype.aa = noopFunc;
      Gat.prototype.ab = noopFunc;
      Gat.prototype.hb = noopFunc;
      Gat.prototype.la = noopFunc;
      Gat.prototype.oa = noopFunc;
      Gat.prototype.pa = noopFunc;
      Gat.prototype.u = noopFunc;
      var gat = new Gat();
      window._gat = gat;
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      GoogleAnalyticsGa.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function GoogleIma3(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function GoogleIma3(source) {
      var _window$google$ima;
      var VERSION = "3.453.0";
      var ima = {};
      var AdDisplayContainer = function AdDisplayContainer(containerElement) {
        var divElement = document.createElement("div");
        divElement.style.setProperty("display", "none", "important");
        divElement.style.setProperty("visibility", "collapse", "important");
        if (containerElement) {
          containerElement.appendChild(divElement);
        }
      };
      AdDisplayContainer.prototype.destroy = noopFunc;
      AdDisplayContainer.prototype.initialize = noopFunc;
      var ImaSdkSettings = function ImaSdkSettings() {};
      ImaSdkSettings.CompanionBackfillMode = {
        ALWAYS: "always",
        ON_MASTER_AD: "on_master_ad"
      };
      ImaSdkSettings.VpaidMode = {
        DISABLED: 0,
        ENABLED: 1,
        INSECURE: 2
      };
      ImaSdkSettings.prototype = {
        c: true,
        f: {},
        i: false,
        l: "",
        p: "",
        r: 0,
        t: "",
        v: "",
        getCompanionBackfill: noopFunc,
        getDisableCustomPlaybackForIOS10Plus() {
          return this.i;
        },
        getDisabledFlashAds: function getDisabledFlashAds() {
          return true;
        },
        getFeatureFlags() {
          return this.f;
        },
        getLocale() {
          return this.l;
        },
        getNumRedirects() {
          return this.r;
        },
        getPlayerType() {
          return this.t;
        },
        getPlayerVersion() {
          return this.v;
        },
        getPpid() {
          return this.p;
        },
        getVpaidMode() {
          return this.C;
        },
        isCookiesEnabled() {
          return this.c;
        },
        isVpaidAdapter() {
          return this.M;
        },
        setCompanionBackfill: noopFunc,
        setAutoPlayAdBreaks(a) {
          this.K = a;
        },
        setCookiesEnabled(c) {
          this.c = !!c;
        },
        setDisableCustomPlaybackForIOS10Plus(i) {
          this.i = !!i;
        },
        setDisableFlashAds: noopFunc,
        setFeatureFlags(f) {
          this.f = !!f;
        },
        setIsVpaidAdapter(a) {
          this.M = a;
        },
        setLocale(l) {
          this.l = !!l;
        },
        setNumRedirects(r) {
          this.r = !!r;
        },
        setPageCorrelator(a) {
          this.R = a;
        },
        setPlayerType(t) {
          this.t = !!t;
        },
        setPlayerVersion(v) {
          this.v = !!v;
        },
        setPpid(p) {
          this.p = !!p;
        },
        setVpaidMode(a) {
          this.C = a;
        },
        setSessionId: noopFunc,
        setStreamCorrelator: noopFunc,
        setVpaidAllowed: noopFunc,
        CompanionBackfillMode: {
          ALWAYS: "always",
          ON_MASTER_AD: "on_master_ad"
        },
        VpaidMode: {
          DISABLED: 0,
          ENABLED: 1,
          INSECURE: 2
        }
      };
      var EventHandler = function EventHandler() {
        this.listeners = new Map();
        this._dispatch = function (e) {
          var listeners = this.listeners.get(e.type);
          listeners = listeners ? listeners.values() : [];
          for (var _i = 0, _Array$from = Array.from(listeners); _i < _Array$from.length; _i++) {
            var listener = _Array$from[_i];
            try {
              listener(e);
            } catch (r) {
              logMessage(source, r);
            }
          }
        };
        this.addEventListener = function (types, callback, options, context) {
          if (!Array.isArray(types)) {
            types = [types];
          }
          for (var i = 0; i < types.length; i += 1) {
            var type = types[i];
            if (!this.listeners.has(type)) {
              this.listeners.set(type, new Map());
            }
            this.listeners.get(type).set(callback, callback.bind(context || this));
          }
        };
        this.removeEventListener = function (types, callback) {
          if (!Array.isArray(types)) {
            types = [types];
          }
          for (var i = 0; i < types.length; i += 1) {
            var _this$listeners$get;
            var type = types[i];
            (_this$listeners$get = this.listeners.get(type)) === null || _this$listeners$get === void 0 || _this$listeners$get.delete(callback);
          }
        };
      };
      var AdsManager = new EventHandler();
      AdsManager.volume = 1;
      AdsManager.collapse = noopFunc;
      AdsManager.configureAdsManager = noopFunc;
      AdsManager.destroy = noopFunc;
      AdsManager.discardAdBreak = noopFunc;
      AdsManager.expand = noopFunc;
      AdsManager.focus = noopFunc;
      AdsManager.getAdSkippableState = function () {
        return false;
      };
      AdsManager.getCuePoints = function () {
        return [0];
      };
      AdsManager.getCurrentAd = function () {
        return currentAd;
      };
      AdsManager.getCurrentAdCuePoints = function () {
        return [];
      };
      AdsManager.getRemainingTime = function () {
        return 0;
      };
      AdsManager.getVolume = function () {
        return this.volume;
      };
      AdsManager.init = noopFunc;
      AdsManager.isCustomClickTrackingUsed = function () {
        return false;
      };
      AdsManager.isCustomPlaybackUsed = function () {
        return false;
      };
      AdsManager.pause = noopFunc;
      AdsManager.requestNextAdBreak = noopFunc;
      AdsManager.resize = noopFunc;
      AdsManager.resume = noopFunc;
      AdsManager.setVolume = function (v) {
        this.volume = v;
      };
      AdsManager.skip = noopFunc;
      AdsManager.start = function () {
        for (var _i2 = 0, _arr = [AdEvent.Type.ALL_ADS_COMPLETED, AdEvent.Type.CONTENT_RESUME_REQUESTED]; _i2 < _arr.length; _i2++) {
          var type = _arr[_i2];
          try {
            this._dispatch(new ima.AdEvent(type));
          } catch (e) {
            logMessage(source, e);
          }
        }
      };
      AdsManager.stop = noopFunc;
      AdsManager.updateAdsRenderingSettings = noopFunc;
      var manager = Object.create(AdsManager);
      var AdsManagerLoadedEvent = function AdsManagerLoadedEvent(type, adsRequest, userRequestContext) {
        this.type = type;
        this.adsRequest = adsRequest;
        this.userRequestContext = userRequestContext;
      };
      AdsManagerLoadedEvent.prototype = {
        getAdsManager: function getAdsManager() {
          return manager;
        },
        getUserRequestContext() {
          if (this.userRequestContext) {
            return this.userRequestContext;
          }
          return {};
        }
      };
      AdsManagerLoadedEvent.Type = {
        ADS_MANAGER_LOADED: "adsManagerLoaded"
      };
      var AdsLoader = EventHandler;
      AdsLoader.prototype.settings = new ImaSdkSettings();
      AdsLoader.prototype.contentComplete = noopFunc;
      AdsLoader.prototype.destroy = noopFunc;
      AdsLoader.prototype.getSettings = function () {
        return this.settings;
      };
      AdsLoader.prototype.getVersion = function () {
        return VERSION;
      };
      AdsLoader.prototype.requestAds = function (adsRequest, userRequestContext) {
        var _this = this;
        requestAnimationFrame(function () {
          var {
            ADS_MANAGER_LOADED: ADS_MANAGER_LOADED
          } = AdsManagerLoadedEvent.Type;
          var event = new ima.AdsManagerLoadedEvent(ADS_MANAGER_LOADED, adsRequest, userRequestContext);
          _this._dispatch(event);
        });
        var e = new ima.AdError("adPlayError", 1205, 1205, "The browser prevented playback initiated without user interaction.", adsRequest, userRequestContext);
        requestAnimationFrame(function () {
          _this._dispatch(new ima.AdErrorEvent(e));
        });
      };
      var AdsRenderingSettings = noopFunc;
      var AdsRequest = function AdsRequest() {};
      AdsRequest.prototype = {
        setAdWillAutoPlay: noopFunc,
        setAdWillPlayMuted: noopFunc,
        setContinuousPlayback: noopFunc
      };
      var AdPodInfo = function AdPodInfo() {};
      AdPodInfo.prototype = {
        getAdPosition: function getAdPosition() {
          return 1;
        },
        getIsBumper: function getIsBumper() {
          return false;
        },
        getMaxDuration: function getMaxDuration() {
          return -1;
        },
        getPodIndex: function getPodIndex() {
          return 1;
        },
        getTimeOffset: function getTimeOffset() {
          return 0;
        },
        getTotalAds: function getTotalAds() {
          return 1;
        }
      };
      var UniversalAdIdInfo = function UniversalAdIdInfo() {};
      UniversalAdIdInfo.prototype.getAdIdRegistry = function () {
        return "";
      };
      UniversalAdIdInfo.prototype.getAdIsValue = function () {
        return "";
      };
      var Ad = function Ad() {};
      Ad.prototype = {
        pi: new AdPodInfo(),
        getAdId: function getAdId() {
          return "";
        },
        getAdPodInfo() {
          return this.pi;
        },
        getAdSystem: function getAdSystem() {
          return "";
        },
        getAdvertiserName: function getAdvertiserName() {
          return "";
        },
        getApiFramework: function getApiFramework() {
          return null;
        },
        getCompanionAds: function getCompanionAds() {
          return [];
        },
        getContentType: function getContentType() {
          return "";
        },
        getCreativeAdId: function getCreativeAdId() {
          return "";
        },
        getDealId: function getDealId() {
          return "";
        },
        getDescription: function getDescription() {
          return "";
        },
        getDuration: function getDuration() {
          return 8.5;
        },
        getHeight: function getHeight() {
          return 0;
        },
        getMediaUrl: function getMediaUrl() {
          return null;
        },
        getMinSuggestedDuration: function getMinSuggestedDuration() {
          return -2;
        },
        getSkipTimeOffset: function getSkipTimeOffset() {
          return -1;
        },
        getSurveyUrl: function getSurveyUrl() {
          return null;
        },
        getTitle: function getTitle() {
          return "";
        },
        getTraffickingParametersString: function getTraffickingParametersString() {
          return "";
        },
        getUiElements: function getUiElements() {
          return [""];
        },
        getUniversalAdIdRegistry: function getUniversalAdIdRegistry() {
          return "unknown";
        },
        getUniversalAdIds: function getUniversalAdIds() {
          return [new UniversalAdIdInfo()];
        },
        getUniversalAdIdValue: function getUniversalAdIdValue() {
          return "unknown";
        },
        getVastMediaBitrate: function getVastMediaBitrate() {
          return 0;
        },
        getVastMediaHeight: function getVastMediaHeight() {
          return 0;
        },
        getVastMediaWidth: function getVastMediaWidth() {
          return 0;
        },
        getWidth: function getWidth() {
          return 0;
        },
        getWrapperAdIds: function getWrapperAdIds() {
          return [""];
        },
        getWrapperAdSystems: function getWrapperAdSystems() {
          return [""];
        },
        getWrapperCreativeIds: function getWrapperCreativeIds() {
          return [""];
        },
        isLinear: function isLinear() {
          return true;
        },
        isSkippable() {
          return true;
        }
      };
      var CompanionAd = function CompanionAd() {};
      CompanionAd.prototype = {
        getAdSlotId: function getAdSlotId() {
          return "";
        },
        getContent: function getContent() {
          return "";
        },
        getContentType: function getContentType() {
          return "";
        },
        getHeight: function getHeight() {
          return 1;
        },
        getWidth: function getWidth() {
          return 1;
        }
      };
      var AdError = function AdError(type, code, vast, message, adsRequest, userRequestContext) {
        this.errorCode = code;
        this.message = message;
        this.type = type;
        this.adsRequest = adsRequest;
        this.userRequestContext = userRequestContext;
        this.getErrorCode = function () {
          return this.errorCode;
        };
        this.getInnerError = function () {
          return null;
        };
        this.getMessage = function () {
          return this.message;
        };
        this.getType = function () {
          return this.type;
        };
        this.getVastErrorCode = function () {
          return this.vastErrorCode;
        };
        this.toString = function () {
          return `AdError ${this.errorCode}: ${this.message}`;
        };
      };
      AdError.ErrorCode = {};
      AdError.Type = {};
      var isEngadget = function isEngadget() {
        try {
          for (var _i3 = 0, _Object$values = Object.values(window.vidible._getContexts()); _i3 < _Object$values.length; _i3++) {
            var _ctx$getPlayer;
            var ctx = _Object$values[_i3];
            if ((_ctx$getPlayer = ctx.getPlayer()) !== null && _ctx$getPlayer !== void 0 && (_ctx$getPlayer = _ctx$getPlayer.div) !== null && _ctx$getPlayer !== void 0 && _ctx$getPlayer.innerHTML.includes("www.engadget.com")) {
              return true;
            }
          }
        } catch (e) {}
        return false;
      };
      var currentAd = isEngadget() ? undefined : new Ad();
      var AdEvent = function AdEvent(type) {
        this.type = type;
      };
      AdEvent.prototype = {
        getAd: function getAd() {
          return currentAd;
        },
        getAdData: function getAdData() {}
      };
      AdEvent.Type = {
        AD_BREAK_READY: "adBreakReady",
        AD_BUFFERING: "adBuffering",
        AD_CAN_PLAY: "adCanPlay",
        AD_METADATA: "adMetadata",
        AD_PROGRESS: "adProgress",
        ALL_ADS_COMPLETED: "allAdsCompleted",
        CLICK: "click",
        COMPLETE: "complete",
        CONTENT_PAUSE_REQUESTED: "contentPauseRequested",
        CONTENT_RESUME_REQUESTED: "contentResumeRequested",
        DURATION_CHANGE: "durationChange",
        EXPANDED_CHANGED: "expandedChanged",
        FIRST_QUARTILE: "firstQuartile",
        IMPRESSION: "impression",
        INTERACTION: "interaction",
        LINEAR_CHANGE: "linearChange",
        LINEAR_CHANGED: "linearChanged",
        LOADED: "loaded",
        LOG: "log",
        MIDPOINT: "midpoint",
        PAUSED: "pause",
        RESUMED: "resume",
        SKIPPABLE_STATE_CHANGED: "skippableStateChanged",
        SKIPPED: "skip",
        STARTED: "start",
        THIRD_QUARTILE: "thirdQuartile",
        USER_CLOSE: "userClose",
        VIDEO_CLICKED: "videoClicked",
        VIDEO_ICON_CLICKED: "videoIconClicked",
        VIEWABLE_IMPRESSION: "viewable_impression",
        VOLUME_CHANGED: "volumeChange",
        VOLUME_MUTED: "mute"
      };
      var AdErrorEvent = function AdErrorEvent(error) {
        this.error = error;
        this.type = "adError";
        this.getError = function () {
          return this.error;
        };
        this.getUserRequestContext = function () {
          var _this$error;
          if ((_this$error = this.error) !== null && _this$error !== void 0 && _this$error.userRequestContext) {
            return this.error.userRequestContext;
          }
          return {};
        };
      };
      AdErrorEvent.Type = {
        AD_ERROR: "adError"
      };
      var CustomContentLoadedEvent = function CustomContentLoadedEvent() {};
      CustomContentLoadedEvent.Type = {
        CUSTOM_CONTENT_LOADED: "deprecated-event"
      };
      var CompanionAdSelectionSettings = function CompanionAdSelectionSettings() {};
      CompanionAdSelectionSettings.CreativeType = {
        ALL: "All",
        FLASH: "Flash",
        IMAGE: "Image"
      };
      CompanionAdSelectionSettings.ResourceType = {
        ALL: "All",
        HTML: "Html",
        IFRAME: "IFrame",
        STATIC: "Static"
      };
      CompanionAdSelectionSettings.SizeCriteria = {
        IGNORE: "IgnoreSize",
        SELECT_EXACT_MATCH: "SelectExactMatch",
        SELECT_NEAR_MATCH: "SelectNearMatch"
      };
      var AdCuePoints = function AdCuePoints() {};
      AdCuePoints.prototype = {
        getCuePoints: function getCuePoints() {
          return [];
        },
        getAdIdRegistry: function getAdIdRegistry() {
          return "";
        },
        getAdIdValue: function getAdIdValue() {
          return "";
        }
      };
      var AdProgressData = noopFunc;
      Object.assign(ima, {
        AdCuePoints: AdCuePoints,
        AdDisplayContainer: AdDisplayContainer,
        AdError: AdError,
        AdErrorEvent: AdErrorEvent,
        AdEvent: AdEvent,
        AdPodInfo: AdPodInfo,
        AdProgressData: AdProgressData,
        AdsLoader: AdsLoader,
        AdsManager: manager,
        AdsManagerLoadedEvent: AdsManagerLoadedEvent,
        AdsRenderingSettings: AdsRenderingSettings,
        AdsRequest: AdsRequest,
        CompanionAd: CompanionAd,
        CompanionAdSelectionSettings: CompanionAdSelectionSettings,
        CustomContentLoadedEvent: CustomContentLoadedEvent,
        gptProxyInstance: {},
        ImaSdkSettings: ImaSdkSettings,
        OmidAccessMode: {
          DOMAIN: "domain",
          FULL: "full",
          LIMITED: "limited"
        },
        OmidVerificationVendor: {
          1: "OTHER",
          2: "MOAT",
          3: "DOUBLEVERIFY",
          4: "INTEGRAL_AD_SCIENCE",
          5: "PIXELATE",
          6: "NIELSEN",
          7: "COMSCORE",
          8: "MEETRICS",
          9: "GOOGLE",
          OTHER: 1,
          MOAT: 2,
          DOUBLEVERIFY: 3,
          INTEGRAL_AD_SCIENCE: 4,
          PIXELATE: 5,
          NIELSEN: 6,
          COMSCORE: 7,
          MEETRICS: 8,
          GOOGLE: 9
        },
        settings: new ImaSdkSettings(),
        UiElements: {
          AD_ATTRIBUTION: "adAttribution",
          COUNTDOWN: "countdown"
        },
        UniversalAdIdInfo: UniversalAdIdInfo,
        VERSION: VERSION,
        ViewMode: {
          FULLSCREEN: "fullscreen",
          NORMAL: "normal"
        }
      });
      if (!window.google) {
        window.google = {};
      }
      if ((_window$google$ima = window.google.ima) !== null && _window$google$ima !== void 0 && _window$google$ima.dai) {
        ima.dai = window.google.ima.dai;
      }
      window.google.ima = ima;
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      GoogleIma3.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function GoogleSyndicationAdsByGoogle(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function GoogleSyndicationAdsByGoogle(source) {
      window.adsbygoogle = {
        loaded: true,
        push(arg) {
          if (typeof this.length === "undefined") {
            this.length = 0;
            this.length += 1;
          }
          if (arg !== null && arg instanceof Object && arg.constructor.name === "Object") {
            for (var _i = 0, _Object$keys = Object.keys(arg); _i < _Object$keys.length; _i++) {
              var key = _Object$keys[_i];
              if (typeof arg[key] === "function") {
                try {
                  arg[key].call(this, {});
                } catch (_unused) {}
              }
            }
          }
        }
      };
      var adElems = document.querySelectorAll(".adsbygoogle");
      var css = "height:1px!important;max-height:1px!important;max-width:1px!important;width:1px!important;";
      var statusAttrName = "data-adsbygoogle-status";
      var ASWIFT_IFRAME_MARKER = "aswift_";
      var GOOGLE_ADS_IFRAME_MARKER = "google_ads_iframe_";
      var executed = false;
      for (var i = 0; i < adElems.length; i += 1) {
        var adElemChildNodes = adElems[i].childNodes;
        var childNodesQuantity = adElemChildNodes.length;
        var areIframesDefined = false;
        if (childNodesQuantity > 0) {
          areIframesDefined = childNodesQuantity === 2 && adElemChildNodes[0].nodeName.toLowerCase() === "iframe" && adElemChildNodes[0].id.includes(ASWIFT_IFRAME_MARKER) && adElemChildNodes[1].nodeName.toLowerCase() === "iframe" && adElemChildNodes[1].id.includes(GOOGLE_ADS_IFRAME_MARKER);
        }
        if (!areIframesDefined) {
          adElems[i].setAttribute(statusAttrName, "done");
          var aswiftIframe = document.createElement("iframe");
          aswiftIframe.id = `${ASWIFT_IFRAME_MARKER}${i}`;
          aswiftIframe.style = css;
          adElems[i].appendChild(aswiftIframe);
          var innerAswiftIframe = document.createElement("iframe");
          aswiftIframe.contentWindow.document.body.appendChild(innerAswiftIframe);
          var googleadsIframe = document.createElement("iframe");
          googleadsIframe.id = `${GOOGLE_ADS_IFRAME_MARKER}${i}`;
          googleadsIframe.style = css;
          adElems[i].appendChild(googleadsIframe);
          var innerGoogleadsIframe = document.createElement("iframe");
          googleadsIframe.contentWindow.document.body.appendChild(innerGoogleadsIframe);
          executed = true;
        }
      }
      if (executed) {
        hit(source);
      }
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      GoogleSyndicationAdsByGoogle.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function GoogleTagServicesGpt(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function GoogleTagServicesGpt(source) {
      var slots = new Map();
      var slotsById = new Map();
      var slotsPerPath = new Map();
      var slotCreatives = new Map();
      var eventCallbacks = new Map();
      var gTargeting = new Map();
      var addEventListener = function addEventListener(name, listener) {
        if (!eventCallbacks.has(name)) {
          eventCallbacks.set(name, new Set());
        }
        eventCallbacks.get(name).add(listener);
        return this;
      };
      var removeEventListener = function removeEventListener(name, listener) {
        if (eventCallbacks.has(name)) {
          return eventCallbacks.get(name).delete(listener);
        }
        return false;
      };
      var fireSlotEvent = function fireSlotEvent(name, slot) {
        return new Promise(function (resolve) {
          requestAnimationFrame(function () {
            var size = [0, 0];
            var callbacksSet = eventCallbacks.get(name) || [];
            var callbackArray = Array.from(callbacksSet);
            for (var i = 0; i < callbackArray.length; i += 1) {
              callbackArray[i]({
                isEmpty: true,
                size: size,
                slot: slot
              });
            }
            resolve();
          });
        });
      };
      var emptySlotElement = function emptySlotElement(slot) {
        var node = document.getElementById(slot.getSlotElementId());
        while (node !== null && node !== void 0 && node.lastChild) {
          node.lastChild.remove();
        }
      };
      var recreateIframeForSlot = function recreateIframeForSlot(slot) {
        var _document$getElementB;
        var eid = `google_ads_iframe_${slot.getId()}`;
        (_document$getElementB = document.getElementById(eid)) === null || _document$getElementB === void 0 || _document$getElementB.remove();
        var node = document.getElementById(slot.getSlotElementId());
        if (node) {
          var f = document.createElement("iframe");
          f.id = eid;
          f.srcdoc = "<body></body>";
          f.style = "position:absolute; width:0; height:0; left:0; right:0; z-index:-1; border:0";
          f.setAttribute("width", 0);
          f.setAttribute("height", 0);
          f.setAttribute("data-load-complete", true);
          f.setAttribute("data-google-container-id", true);
          f.setAttribute("sandbox", "");
          node.appendChild(f);
        }
      };
      var displaySlot = function displaySlot(slot) {
        if (!slot) {
          return;
        }
        var id = slot.getSlotElementId();
        if (!document.getElementById(id)) {
          return;
        }
        var parent = document.getElementById(id);
        if (parent) {
          parent.appendChild(document.createElement("div"));
        }
        emptySlotElement(slot);
        recreateIframeForSlot(slot);
        fireSlotEvent("slotRenderEnded", slot);
        fireSlotEvent("slotRequested", slot);
        fireSlotEvent("slotResponseReceived", slot);
        fireSlotEvent("slotOnload", slot);
        fireSlotEvent("impressionViewable", slot);
      };
      var companionAdsService = {
        addEventListener: addEventListener,
        removeEventListener: removeEventListener,
        enableSyncLoading: noopFunc,
        setRefreshUnfilledSlots: noopFunc,
        getSlots: noopArray
      };
      var contentService = {
        addEventListener: addEventListener,
        removeEventListener: removeEventListener,
        setContent: noopFunc
      };
      function PassbackSlot() {}
      PassbackSlot.prototype.display = noopFunc;
      PassbackSlot.prototype.get = noopNull;
      PassbackSlot.prototype.set = noopThis;
      PassbackSlot.prototype.setClickUrl = noopThis;
      PassbackSlot.prototype.setTagForChildDirectedTreatment = noopThis;
      PassbackSlot.prototype.setTargeting = noopThis;
      PassbackSlot.prototype.updateTargetingFromMap = noopThis;
      function SizeMappingBuilder() {}
      SizeMappingBuilder.prototype.addSize = noopThis;
      SizeMappingBuilder.prototype.build = noopNull;
      var getTargetingValue = function getTargetingValue(v) {
        if (typeof v === "string") {
          return [v];
        }
        try {
          return Array.prototype.flat.call(v);
        } catch (_unused) {}
        return [];
      };
      var updateTargeting = function updateTargeting(targeting, map) {
        if (typeof map === "object") {
          for (var key in map) {
            if (Object.prototype.hasOwnProperty.call(map, key)) {
              targeting.set(key, getTargetingValue(map[key]));
            }
          }
        }
      };
      var defineSlot = function defineSlot(adUnitPath, creatives, optDiv) {
        if (slotsById.has(optDiv)) {
          var _document$getElementB2;
          (_document$getElementB2 = document.getElementById(optDiv)) === null || _document$getElementB2 === void 0 || _document$getElementB2.remove();
          return slotsById.get(optDiv);
        }
        var attributes = new Map();
        var targeting = new Map();
        var exclusions = new Set();
        var response = {
          advertiserId: undefined,
          campaignId: undefined,
          creativeId: undefined,
          creativeTemplateId: undefined,
          lineItemId: undefined
        };
        var sizes = [{
          getHeight: function getHeight() {
            return 2;
          },
          getWidth: function getWidth() {
            return 2;
          }
        }];
        var num = (slotsPerPath.get(adUnitPath) || 0) + 1;
        slotsPerPath.set(adUnitPath, num);
        var id = `${adUnitPath}_${num}`;
        var clickUrl = "";
        var collapseEmptyDiv = null;
        var services = new Set();
        var slot = {
          addService(e) {
            services.add(e);
            return slot;
          },
          clearCategoryExclusions: noopThis,
          clearTargeting(k) {
            if (k === undefined) {
              targeting.clear();
            } else {
              targeting.delete(k);
            }
          },
          defineSizeMapping(mapping) {
            slotCreatives.set(optDiv, mapping);
            return this;
          },
          get: function get(k) {
            return attributes.get(k);
          },
          getAdUnitPath: function getAdUnitPath() {
            return adUnitPath;
          },
          getAttributeKeys: function getAttributeKeys() {
            return Array.from(attributes.keys());
          },
          getCategoryExclusions: function getCategoryExclusions() {
            return Array.from(exclusions);
          },
          getClickUrl: function getClickUrl() {
            return clickUrl;
          },
          getCollapseEmptyDiv: function getCollapseEmptyDiv() {
            return collapseEmptyDiv;
          },
          getContentUrl: function getContentUrl() {
            return "";
          },
          getDivStartsCollapsed: function getDivStartsCollapsed() {
            return null;
          },
          getDomId: function getDomId() {
            return optDiv;
          },
          getEscapedQemQueryId: function getEscapedQemQueryId() {
            return "";
          },
          getFirstLook: function getFirstLook() {
            return 0;
          },
          getId: function getId() {
            return id;
          },
          getHtml: function getHtml() {
            return "";
          },
          getName: function getName() {
            return id;
          },
          getOutOfPage: function getOutOfPage() {
            return false;
          },
          getResponseInformation: function getResponseInformation() {
            return response;
          },
          getServices: function getServices() {
            return Array.from(services);
          },
          getSizes: function getSizes() {
            return sizes;
          },
          getSlotElementId: function getSlotElementId() {
            return optDiv;
          },
          getSlotId: function getSlotId() {
            return slot;
          },
          getTargeting: function getTargeting(k) {
            return targeting.get(k) || gTargeting.get(k) || [];
          },
          getTargetingKeys: function getTargetingKeys() {
            return Array.from(new Set(Array.of(...gTargeting.keys(), ...targeting.keys())));
          },
          getTargetingMap: function getTargetingMap() {
            return Object.assign(Object.fromEntries(gTargeting.entries()), Object.fromEntries(targeting.entries()));
          },
          set(k, v) {
            attributes.set(k, v);
            return slot;
          },
          setCategoryExclusion(e) {
            exclusions.add(e);
            return slot;
          },
          setClickUrl(u) {
            clickUrl = u;
            return slot;
          },
          setCollapseEmptyDiv(v) {
            collapseEmptyDiv = !!v;
            return slot;
          },
          setSafeFrameConfig: noopThis,
          setTagForChildDirectedTreatment: noopThis,
          setTargeting(k, v) {
            targeting.set(k, getTargetingValue(v));
            return slot;
          },
          toString: function toString() {
            return id;
          },
          updateTargetingFromMap(map) {
            updateTargeting(targeting, map);
            return slot;
          }
        };
        slots.set(adUnitPath, slot);
        slotsById.set(optDiv, slot);
        slotCreatives.set(optDiv, creatives);
        return slot;
      };
      var pubAdsService = {
        addEventListener: addEventListener,
        removeEventListener: removeEventListener,
        clear: noopFunc,
        clearCategoryExclusions: noopThis,
        clearTagForChildDirectedTreatment: noopThis,
        clearTargeting(k) {
          if (k === undefined) {
            gTargeting.clear();
          } else {
            gTargeting.delete(k);
          }
        },
        collapseEmptyDivs: noopFunc,
        defineOutOfPagePassback() {
          return new PassbackSlot();
        },
        definePassback() {
          return new PassbackSlot();
        },
        disableInitialLoad: noopFunc,
        display: noopFunc,
        enableAsyncRendering: noopFunc,
        enableLazyLoad: noopFunc,
        enableSingleRequest: noopFunc,
        enableSyncRendering: noopFunc,
        enableVideoAds: noopFunc,
        get: noopNull,
        getAttributeKeys: noopArray,
        getTargeting: noopArray,
        getTargetingKeys: noopArray,
        getSlots: noopArray,
        isInitialLoadDisabled: trueFunc,
        refresh: noopFunc,
        set: noopThis,
        setCategoryExclusion: noopThis,
        setCentering: noopFunc,
        setCookieOptions: noopThis,
        setForceSafeFrame: noopThis,
        setLocation: noopThis,
        setPrivacySettings: noopThis,
        setPublisherProvidedId: noopThis,
        setRequestNonPersonalizedAds: noopThis,
        setSafeFrameConfig: noopThis,
        setTagForChildDirectedTreatment: noopThis,
        setTargeting: noopThis,
        setVideoContent: noopThis,
        updateCorrelator: noopFunc
      };
      var {
        googletag = {}
      } = window;
      var {
        cmd = []
      } = googletag;
      googletag.apiReady = true;
      googletag.cmd = [];
      googletag.cmd.push = function (a) {
        try {
          a();
        } catch (ex) {}
        return 1;
      };
      googletag.companionAds = function () {
        return companionAdsService;
      };
      googletag.content = function () {
        return contentService;
      };
      googletag.defineOutOfPageSlot = defineSlot;
      googletag.defineSlot = defineSlot;
      googletag.destroySlots = function () {
        slots.clear();
        slotsById.clear();
      };
      googletag.disablePublisherConsole = noopFunc;
      googletag.display = function (arg) {
        var id;
        if (arg !== null && arg !== void 0 && arg.getSlotElementId) {
          id = arg.getSlotElementId();
        } else if (arg !== null && arg !== void 0 && arg.nodeType) {
          id = arg.id;
        } else {
          id = String(arg);
        }
        displaySlot(slotsById.get(id));
      };
      googletag.enableServices = noopFunc;
      googletag.getVersion = noopStr;
      googletag.pubads = function () {
        return pubAdsService;
      };
      googletag.pubadsReady = true;
      googletag.setAdIframeTitle = noopFunc;
      googletag.sizeMapping = function () {
        return new SizeMappingBuilder();
      };
      window.googletag = googletag;
      while (cmd.length !== 0) {
        googletag.cmd.push(cmd.shift());
      }
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    function noopThis() {
      return this;
    }
    function noopNull() {
      return null;
    }
    function noopArray() {
      return [];
    }
    function noopStr() {
      return "";
    }
    function trueFunc() {
      return true;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      GoogleTagServicesGpt.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function Matomo(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function Matomo(source) {
      var Tracker = function Tracker() {};
      Tracker.prototype.setDoNotTrack = noopFunc;
      Tracker.prototype.setDomains = noopFunc;
      Tracker.prototype.setCustomDimension = noopFunc;
      Tracker.prototype.trackPageView = noopFunc;
      var AsyncTracker = function AsyncTracker() {};
      AsyncTracker.prototype.addListener = noopFunc;
      var matomoWrapper = {
        getTracker: Tracker,
        getAsyncTracker: AsyncTracker
      };
      window.Piwik = matomoWrapper;
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      Matomo.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function NaverWcslog(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function NaverWcslog(source) {
      window.wcs_add = {};
      window.wcs_do = noopFunc;
      window.wcs = {
        inflow: noopFunc
      };
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      NaverWcslog.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function Pardot(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function Pardot(source) {
      window.piVersion = "1.0.2";
      window.piScriptNum = 0;
      window.piScriptObj = [];
      window.checkNamespace = noopFunc;
      window.getPardotUrl = noopStr;
      window.piGetParameter = noopNull;
      window.piSetCookie = noopFunc;
      window.piGetCookie = noopStr;
      function piTracker() {
        window.pi = {
          tracker: {
            visitor_id: "",
            visitor_id_sign: "",
            pi_opt_in: "",
            campaign_id: ""
          }
        };
        window.piScriptNum += 1;
      }
      window.piResponse = noopFunc;
      window.piTracker = piTracker;
      piTracker();
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    function noopStr() {
      return "";
    }
    function noopNull() {
      return null;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      Pardot.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function Prebid(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function Prebid(source) {
      var pushFunction = function pushFunction(arg) {
        if (typeof arg === "function") {
          try {
            arg.call();
          } catch (ex) {}
        }
      };
      var pbjsWrapper = {
        addAdUnits() {},
        adServers: {
          dfp: {
            buildVideoUrl: noopStr
          }
        },
        adUnits: [],
        aliasBidder() {},
        cmd: [],
        enableAnalytics() {},
        getHighestCpmBids: noopArray,
        libLoaded: true,
        que: [],
        requestBids(arg) {
          if (arg instanceof Object && arg.bidsBackHandler) {
            try {
              arg.bidsBackHandler.call();
            } catch (ex) {}
          }
        },
        removeAdUnit() {},
        setBidderConfig() {},
        setConfig() {},
        setTargetingForGPTAsync() {}
      };
      pbjsWrapper.cmd.push = pushFunction;
      pbjsWrapper.que.push = pushFunction;
      window.pbjs = pbjsWrapper;
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopStr() {
      return "";
    }
    function noopArray() {
      return [];
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      Prebid.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function ScoreCardResearchBeacon(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function ScoreCardResearchBeacon(source) {
      window.COMSCORE = {
        purge() {
          window._comscore = [];
        },
        beacon() {}
      };
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      ScoreCardResearchBeacon.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function abortCurrentInlineScript(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function abortCurrentInlineScript(source, property, search) {
      var searchRegexp = toRegExp(search);
      var rid = randomId();
      var SRC_DATA_MARKER = "data:text/javascript;base64,";
      var getCurrentScript = function getCurrentScript() {
        if ("currentScript" in document) {
          return document.currentScript;
        }
        var scripts = document.getElementsByTagName("script");
        return scripts[scripts.length - 1];
      };
      var ourScript = getCurrentScript();
      var abort = function abort() {
        var _scriptEl$src;
        var scriptEl = getCurrentScript();
        if (!scriptEl) {
          return;
        }
        var content = scriptEl.textContent;
        try {
          var textContentGetter = Object.getOwnPropertyDescriptor(Node.prototype, "textContent").get;
          content = textContentGetter.call(scriptEl);
        } catch (e) {}
        if (content.length === 0 && typeof scriptEl.src !== "undefined" && (_scriptEl$src = scriptEl.src) !== null && _scriptEl$src !== void 0 && _scriptEl$src.startsWith(SRC_DATA_MARKER)) {
          var encodedContent = scriptEl.src.slice(SRC_DATA_MARKER.length);
          content = window.atob(encodedContent);
        }
        if (scriptEl instanceof HTMLScriptElement && content.length > 0 && scriptEl !== ourScript && searchRegexp.test(content)) {
          hit(source);
          throw new ReferenceError(rid);
        }
      };
      var _setChainPropAccess = function setChainPropAccess(owner, property) {
        var chainInfo = getPropertyInChain(owner, property);
        var {
          base: base
        } = chainInfo;
        var {
          prop: prop,
          chain: chain
        } = chainInfo;
        if (base instanceof Object === false && base === null) {
          var props = property.split(".");
          var propIndex = props.indexOf(prop);
          var baseName = props[propIndex - 1];
          var message = `The scriptlet had been executed before the ${baseName} was loaded.`;
          logMessage(source, message);
          return;
        }
        if (chain) {
          var setter = function setter(a) {
            base = a;
            if (a instanceof Object) {
              _setChainPropAccess(a, chain);
            }
          };
          Object.defineProperty(owner, prop, {
            get: function get() {
              return base;
            },
            set: setter
          });
          return;
        }
        var currentValue = base[prop];
        var origDescriptor = Object.getOwnPropertyDescriptor(base, prop);
        if (origDescriptor instanceof Object === false || origDescriptor.get instanceof Function === false) {
          currentValue = base[prop];
          origDescriptor = undefined;
        }
        var descriptorWrapper = Object.assign(getDescriptorAddon(), {
          currentValue: currentValue,
          get() {
            if (!this.isAbortingSuspended) {
              this.isolateCallback(abort);
            }
            if (origDescriptor instanceof Object) {
              return origDescriptor.get.call(base);
            }
            return this.currentValue;
          },
          set(newValue) {
            if (!this.isAbortingSuspended) {
              this.isolateCallback(abort);
            }
            if (origDescriptor instanceof Object) {
              origDescriptor.set.call(base, newValue);
            } else {
              this.currentValue = newValue;
            }
          }
        });
        setPropertyAccess(base, prop, {
          get() {
            return descriptorWrapper.get.call(descriptorWrapper);
          },
          set(newValue) {
            descriptorWrapper.set.call(descriptorWrapper, newValue);
          }
        });
      };
      _setChainPropAccess(window, property);
      window.onerror = createOnErrorHandler(rid).bind();
    }
    function randomId() {
      return Math.random().toString(36).slice(2, 9);
    }
    function setPropertyAccess(object, property, descriptor) {
      var currentDescriptor = Object.getOwnPropertyDescriptor(object, property);
      if (currentDescriptor && !currentDescriptor.configurable) {
        return false;
      }
      Object.defineProperty(object, property, descriptor);
      return true;
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function createOnErrorHandler(rid) {
      var nativeOnError = window.onerror;
      return function onError(error) {
        if (typeof error === "string" && error.includes(rid)) {
          return true;
        }
        if (nativeOnError instanceof Function) {
          for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
            args[_key - 1] = arguments[_key];
          }
          return nativeOnError.apply(window, [error, ...args]);
        }
        return false;
      };
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    function getDescriptorAddon() {
      return {
        isAbortingSuspended: false,
        isolateCallback(cb) {
          this.isAbortingSuspended = true;
          try {
            for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
              args[_key - 1] = arguments[_key];
            }
            var result = cb(...args);
            this.isAbortingSuspended = false;
            return result;
          } catch (_unused) {
            var rid = randomId();
            this.isAbortingSuspended = false;
            throw new ReferenceError(rid);
          }
        }
      };
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      abortCurrentInlineScript.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function abortOnPropertyRead(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function abortOnPropertyRead(source, property) {
      if (!property) {
        return;
      }
      var rid = randomId();
      var abort = function abort() {
        hit(source);
        throw new ReferenceError(rid);
      };
      var _setChainPropAccess = function setChainPropAccess(owner, property) {
        var chainInfo = getPropertyInChain(owner, property);
        var {
          base: base
        } = chainInfo;
        var {
          prop: prop,
          chain: chain
        } = chainInfo;
        if (chain) {
          var setter = function setter(a) {
            base = a;
            if (a instanceof Object) {
              _setChainPropAccess(a, chain);
            }
          };
          Object.defineProperty(owner, prop, {
            get: function get() {
              return base;
            },
            set: setter
          });
          return;
        }
        setPropertyAccess(base, prop, {
          get: abort,
          set: function set() {}
        });
      };
      _setChainPropAccess(window, property);
      window.onerror = createOnErrorHandler(rid).bind();
    }
    function randomId() {
      return Math.random().toString(36).slice(2, 9);
    }
    function setPropertyAccess(object, property, descriptor) {
      var currentDescriptor = Object.getOwnPropertyDescriptor(object, property);
      if (currentDescriptor && !currentDescriptor.configurable) {
        return false;
      }
      Object.defineProperty(object, property, descriptor);
      return true;
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function createOnErrorHandler(rid) {
      var nativeOnError = window.onerror;
      return function onError(error) {
        if (typeof error === "string" && error.includes(rid)) {
          return true;
        }
        if (nativeOnError instanceof Function) {
          for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
            args[_key - 1] = arguments[_key];
          }
          return nativeOnError.apply(window, [error, ...args]);
        }
        return false;
      };
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      abortOnPropertyRead.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function abortOnPropertyWrite(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function abortOnPropertyWrite(source, property) {
      if (!property) {
        return;
      }
      var rid = randomId();
      var abort = function abort() {
        hit(source);
        throw new ReferenceError(rid);
      };
      var _setChainPropAccess = function setChainPropAccess(owner, property) {
        var chainInfo = getPropertyInChain(owner, property);
        var {
          base: base
        } = chainInfo;
        var {
          prop: prop,
          chain: chain
        } = chainInfo;
        if (chain) {
          var setter = function setter(a) {
            base = a;
            if (a instanceof Object) {
              _setChainPropAccess(a, chain);
            }
          };
          Object.defineProperty(owner, prop, {
            get: function get() {
              return base;
            },
            set: setter
          });
          return;
        }
        setPropertyAccess(base, prop, {
          set: abort
        });
      };
      _setChainPropAccess(window, property);
      window.onerror = createOnErrorHandler(rid).bind();
    }
    function randomId() {
      return Math.random().toString(36).slice(2, 9);
    }
    function setPropertyAccess(object, property, descriptor) {
      var currentDescriptor = Object.getOwnPropertyDescriptor(object, property);
      if (currentDescriptor && !currentDescriptor.configurable) {
        return false;
      }
      Object.defineProperty(object, property, descriptor);
      return true;
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function createOnErrorHandler(rid) {
      var nativeOnError = window.onerror;
      return function onError(error) {
        if (typeof error === "string" && error.includes(rid)) {
          return true;
        }
        if (nativeOnError instanceof Function) {
          for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
            args[_key - 1] = arguments[_key];
          }
          return nativeOnError.apply(window, [error, ...args]);
        }
        return false;
      };
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      abortOnPropertyWrite.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function abortOnStackTrace(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function abortOnStackTrace(source, property, stack) {
      if (!property || !stack) {
        return;
      }
      var rid = randomId();
      var abort = function abort() {
        hit(source);
        throw new ReferenceError(rid);
      };
      var _setChainPropAccess = function setChainPropAccess(owner, property) {
        var chainInfo = getPropertyInChain(owner, property);
        var {
          base: base
        } = chainInfo;
        var {
          prop: prop,
          chain: chain
        } = chainInfo;
        if (chain) {
          var setter = function setter(a) {
            base = a;
            if (a instanceof Object) {
              _setChainPropAccess(a, chain);
            }
          };
          Object.defineProperty(owner, prop, {
            get: function get() {
              return base;
            },
            set: setter
          });
          return;
        }
        if (!stack.match(/^(inlineScript|injectedScript)$/) && !isValidStrPattern(stack)) {
          logMessage(source, `Invalid parameter: ${stack}`);
          return;
        }
        var descriptorWrapper = Object.assign(getDescriptorAddon(), {
          value: base[prop],
          get() {
            if (!this.isAbortingSuspended && this.isolateCallback(matchStackTrace, stack, new Error().stack)) {
              abort();
            }
            return this.value;
          },
          set(newValue) {
            if (!this.isAbortingSuspended && this.isolateCallback(matchStackTrace, stack, new Error().stack)) {
              abort();
            }
            this.value = newValue;
          }
        });
        setPropertyAccess(base, prop, {
          get() {
            return descriptorWrapper.get.call(descriptorWrapper);
          },
          set(newValue) {
            descriptorWrapper.set.call(descriptorWrapper, newValue);
          }
        });
      };
      _setChainPropAccess(window, property);
      window.onerror = createOnErrorHandler(rid).bind();
    }
    function randomId() {
      return Math.random().toString(36).slice(2, 9);
    }
    function setPropertyAccess(object, property, descriptor) {
      var currentDescriptor = Object.getOwnPropertyDescriptor(object, property);
      if (currentDescriptor && !currentDescriptor.configurable) {
        return false;
      }
      Object.defineProperty(object, property, descriptor);
      return true;
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function createOnErrorHandler(rid) {
      var nativeOnError = window.onerror;
      return function onError(error) {
        if (typeof error === "string" && error.includes(rid)) {
          return true;
        }
        if (nativeOnError instanceof Function) {
          for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
            args[_key - 1] = arguments[_key];
          }
          return nativeOnError.apply(window, [error, ...args]);
        }
        return false;
      };
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    function matchStackTrace(stackMatch, stackTrace) {
      if (!stackMatch || stackMatch === "") {
        return true;
      }
      var regExpValues = backupRegExpValues();
      if (shouldAbortInlineOrInjectedScript(stackMatch, stackTrace)) {
        if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
          restoreRegExpValues(regExpValues);
        }
        return true;
      }
      var stackRegexp = toRegExp(stackMatch);
      var refinedStackTrace = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      }).join("\n");
      if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
        restoreRegExpValues(regExpValues);
      }
      return getNativeRegexpTest().call(stackRegexp, refinedStackTrace);
    }
    function getDescriptorAddon() {
      return {
        isAbortingSuspended: false,
        isolateCallback(cb) {
          this.isAbortingSuspended = true;
          try {
            for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
              args[_key - 1] = arguments[_key];
            }
            var result = cb(...args);
            this.isAbortingSuspended = false;
            return result;
          } catch (_unused) {
            var rid = randomId();
            this.isAbortingSuspended = false;
            throw new ReferenceError(rid);
          }
        }
      };
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    function getNativeRegexpTest() {
      var descriptor = Object.getOwnPropertyDescriptor(RegExp.prototype, "test");
      var nativeRegexTest = descriptor === null || descriptor === void 0 ? void 0 : descriptor.value;
      if (descriptor && typeof descriptor.value === "function") {
        return nativeRegexTest;
      }
      throw new Error("RegExp.prototype.test is not a function");
    }
    function shouldAbortInlineOrInjectedScript(stackMatch, stackTrace) {
      var INLINE_SCRIPT_STRING = "inlineScript";
      var INJECTED_SCRIPT_STRING = "injectedScript";
      var INJECTED_SCRIPT_MARKER = "<anonymous>";
      var isInlineScript = function isInlineScript(match) {
        return match.includes(INLINE_SCRIPT_STRING);
      };
      var isInjectedScript = function isInjectedScript(match) {
        return match.includes(INJECTED_SCRIPT_STRING);
      };
      if (!(isInlineScript(stackMatch) || isInjectedScript(stackMatch))) {
        return false;
      }
      var documentURL = window.location.href;
      var pos = documentURL.indexOf("#");
      if (pos !== -1) {
        documentURL = documentURL.slice(0, pos);
      }
      var stackSteps = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      });
      var stackLines = stackSteps.map(function (line) {
        var stack;
        var getStackTraceValues = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(line);
        if (getStackTraceValues) {
          var _stackURL, _stackURL2;
          var stackURL = getStackTraceValues[2];
          var stackLine = getStackTraceValues[3];
          var stackCol = getStackTraceValues[4];
          if ((_stackURL = stackURL) !== null && _stackURL !== void 0 && _stackURL.startsWith("(")) {
            stackURL = stackURL.slice(1);
          }
          if ((_stackURL2 = stackURL) !== null && _stackURL2 !== void 0 && _stackURL2.startsWith(INJECTED_SCRIPT_MARKER)) {
            var _stackFunction;
            stackURL = INJECTED_SCRIPT_STRING;
            var stackFunction = getStackTraceValues[1] !== undefined ? getStackTraceValues[1].slice(0, -1) : line.slice(0, getStackTraceValues.index).trim();
            if ((_stackFunction = stackFunction) !== null && _stackFunction !== void 0 && _stackFunction.startsWith("at")) {
              stackFunction = stackFunction.slice(2).trim();
            }
            stack = `${stackFunction} ${stackURL}${stackLine}${stackCol}`.trim();
          } else if (stackURL === documentURL) {
            stack = `${INLINE_SCRIPT_STRING}${stackLine}${stackCol}`.trim();
          } else {
            stack = `${stackURL}${stackLine}${stackCol}`.trim();
          }
        } else {
          stack = line;
        }
        return stack;
      });
      if (stackLines) {
        for (var index = 0; index < stackLines.length; index += 1) {
          if (isInlineScript(stackMatch) && stackLines[index].startsWith(INLINE_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
          if (isInjectedScript(stackMatch) && stackLines[index].startsWith(INJECTED_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
        }
      }
      return false;
    }
    function backupRegExpValues() {
      try {
        var arrayOfRegexpValues = [];
        for (var index = 1; index < 10; index += 1) {
          var value = `$${index}`;
          if (!RegExp[value]) {
            break;
          }
          arrayOfRegexpValues.push(RegExp[value]);
        }
        return arrayOfRegexpValues;
      } catch (error) {
        return [];
      }
    }
    function restoreRegExpValues(array) {
      if (!array.length) {
        return;
      }
      try {
        var stringPattern = "";
        if (array.length === 1) {
          stringPattern = `(${array[0]})`;
        } else {
          stringPattern = array.reduce(function (accumulator, currentValue, currentIndex) {
            if (currentIndex === 1) {
              return `(${accumulator}),(${currentValue})`;
            }
            return `${accumulator},(${currentValue})`;
          });
        }
        var regExpGroup = new RegExp(stringPattern);
        array.toString().replace(regExpGroup, "");
      } catch (error) {
        var message = `Failed to restore RegExp values: ${error}`;
        console.log(message);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      abortOnStackTrace.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function adjustSetInterval(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function adjustSetInterval(source, matchCallback, matchDelay, boost) {
      var nativeSetInterval = window.setInterval;
      var matchRegexp = toRegExp(matchCallback);
      var intervalWrapper = function intervalWrapper(callback, delay) {
        if (!isValidCallback(callback)) {
          var message = `Scriptlet can't be applied because of invalid callback: '${String(callback)}'`;
          logMessage(source, message);
        } else if (matchRegexp.test(callback.toString()) && isDelayMatched(matchDelay, delay)) {
          delay *= getBoostMultiplier(boost);
          hit(source);
        }
        for (var _len = arguments.length, args = new Array(_len > 2 ? _len - 2 : 0), _key = 2; _key < _len; _key++) {
          args[_key - 2] = arguments[_key];
        }
        return nativeSetInterval.apply(window, [callback, delay, ...args]);
      };
      window.setInterval = intervalWrapper;
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function isValidCallback(callback) {
      return callback instanceof Function || typeof callback === "string";
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function getBoostMultiplier(boost) {
      var DEFAULT_MULTIPLIER = .05;
      var MIN_MULTIPLIER = .001;
      var MAX_MULTIPLIER = 50;
      var parsedBoost = parseFloat(boost);
      var boostMultiplier = nativeIsNaN(parsedBoost) || !nativeIsFinite(parsedBoost) ? DEFAULT_MULTIPLIER : parsedBoost;
      if (boostMultiplier < MIN_MULTIPLIER) {
        boostMultiplier = MIN_MULTIPLIER;
      }
      if (boostMultiplier > MAX_MULTIPLIER) {
        boostMultiplier = MAX_MULTIPLIER;
      }
      return boostMultiplier;
    }
    function isDelayMatched(inputDelay, realDelay) {
      return shouldMatchAnyDelay(inputDelay) || realDelay === getMatchDelay(inputDelay);
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function nativeIsFinite(num) {
      var native = Number.isFinite || window.isFinite;
      return native(num);
    }
    function getMatchDelay(delay) {
      var DEFAULT_DELAY = 1e3;
      var parsedDelay = parseInt(delay, 10);
      var delayMatch = nativeIsNaN(parsedDelay) ? DEFAULT_DELAY : parsedDelay;
      return delayMatch;
    }
    function shouldMatchAnyDelay(delay) {
      return delay === "*";
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      adjustSetInterval.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function adjustSetTimeout(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function adjustSetTimeout(source, matchCallback, matchDelay, boost) {
      var nativeSetTimeout = window.setTimeout;
      var matchRegexp = toRegExp(matchCallback);
      var timeoutWrapper = function timeoutWrapper(callback, delay) {
        if (!isValidCallback(callback)) {
          var message = `Scriptlet can't be applied because of invalid callback: '${String(callback)}'`;
          logMessage(source, message);
        } else if (matchRegexp.test(callback.toString()) && isDelayMatched(matchDelay, delay)) {
          delay *= getBoostMultiplier(boost);
          hit(source);
        }
        for (var _len = arguments.length, args = new Array(_len > 2 ? _len - 2 : 0), _key = 2; _key < _len; _key++) {
          args[_key - 2] = arguments[_key];
        }
        return nativeSetTimeout.apply(window, [callback, delay, ...args]);
      };
      window.setTimeout = timeoutWrapper;
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function isValidCallback(callback) {
      return callback instanceof Function || typeof callback === "string";
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function getBoostMultiplier(boost) {
      var DEFAULT_MULTIPLIER = .05;
      var MIN_MULTIPLIER = .001;
      var MAX_MULTIPLIER = 50;
      var parsedBoost = parseFloat(boost);
      var boostMultiplier = nativeIsNaN(parsedBoost) || !nativeIsFinite(parsedBoost) ? DEFAULT_MULTIPLIER : parsedBoost;
      if (boostMultiplier < MIN_MULTIPLIER) {
        boostMultiplier = MIN_MULTIPLIER;
      }
      if (boostMultiplier > MAX_MULTIPLIER) {
        boostMultiplier = MAX_MULTIPLIER;
      }
      return boostMultiplier;
    }
    function isDelayMatched(inputDelay, realDelay) {
      return shouldMatchAnyDelay(inputDelay) || realDelay === getMatchDelay(inputDelay);
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function nativeIsFinite(num) {
      var native = Number.isFinite || window.isFinite;
      return native(num);
    }
    function getMatchDelay(delay) {
      var DEFAULT_DELAY = 1e3;
      var parsedDelay = parseInt(delay, 10);
      var delayMatch = nativeIsNaN(parsedDelay) ? DEFAULT_DELAY : parsedDelay;
      return delayMatch;
    }
    function shouldMatchAnyDelay(delay) {
      return delay === "*";
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      adjustSetTimeout.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function callNoThrow(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function callNoThrow(source, functionName) {
      if (!functionName) {
        return;
      }
      var {
        base: base,
        prop: prop
      } = getPropertyInChain(window, functionName);
      if (!base || !prop || typeof base[prop] !== "function") {
        var message = `${functionName} is not a function`;
        logMessage(source, message);
        return;
      }
      var objectWrapper = function objectWrapper() {
        var result;
        try {
          result = Reflect.apply(...arguments);
        } catch (e) {
          var _message = `Error calling ${functionName}: ${e.message}`;
          logMessage(source, _message);
        }
        hit(source);
        return result;
      };
      var objectHandler = {
        apply: objectWrapper
      };
      base[prop] = new Proxy(base[prop], objectHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      callNoThrow.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function debugCurrentInlineScript(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function debugCurrentInlineScript(source, property, search) {
      var searchRegexp = toRegExp(search);
      var rid = randomId();
      var getCurrentScript = function getCurrentScript() {
        if ("currentScript" in document) {
          return document.currentScript;
        }
        var scripts = document.getElementsByTagName("script");
        return scripts[scripts.length - 1];
      };
      var ourScript = getCurrentScript();
      var abort = function abort() {
        var scriptEl = getCurrentScript();
        if (!scriptEl) {
          return;
        }
        var content = scriptEl.textContent;
        try {
          var textContentGetter = Object.getOwnPropertyDescriptor(Node.prototype, "textContent").get;
          content = textContentGetter.call(scriptEl);
        } catch (e) {}
        if (scriptEl instanceof HTMLScriptElement && content.length > 0 && scriptEl !== ourScript && searchRegexp.test(content)) {
          hit(source);
          debugger;
        }
      };
      var _setChainPropAccess = function setChainPropAccess(owner, property) {
        var chainInfo = getPropertyInChain(owner, property);
        var {
          base: base
        } = chainInfo;
        var {
          prop: prop,
          chain: chain
        } = chainInfo;
        if (base instanceof Object === false && base === null) {
          var props = property.split(".");
          var propIndex = props.indexOf(prop);
          var baseName = props[propIndex - 1];
          var message = `The scriptlet had been executed before the ${baseName} was loaded.`;
          logMessage(message, source.verbose);
          return;
        }
        if (chain) {
          var setter = function setter(a) {
            base = a;
            if (a instanceof Object) {
              _setChainPropAccess(a, chain);
            }
          };
          Object.defineProperty(owner, prop, {
            get: function get() {
              return base;
            },
            set: setter
          });
          return;
        }
        var currentValue = base[prop];
        setPropertyAccess(base, prop, {
          set: function set(value) {
            abort();
            currentValue = value;
          },
          get: function get() {
            abort();
            return currentValue;
          }
        });
      };
      _setChainPropAccess(window, property);
      window.onerror = createOnErrorHandler(rid).bind();
    }
    function randomId() {
      return Math.random().toString(36).slice(2, 9);
    }
    function setPropertyAccess(object, property, descriptor) {
      var currentDescriptor = Object.getOwnPropertyDescriptor(object, property);
      if (currentDescriptor && !currentDescriptor.configurable) {
        return false;
      }
      Object.defineProperty(object, property, descriptor);
      return true;
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function createOnErrorHandler(rid) {
      var nativeOnError = window.onerror;
      return function onError(error) {
        if (typeof error === "string" && error.includes(rid)) {
          return true;
        }
        if (nativeOnError instanceof Function) {
          for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
            args[_key - 1] = arguments[_key];
          }
          return nativeOnError.apply(window, [error, ...args]);
        }
        return false;
      };
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      debugCurrentInlineScript.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function debugOnPropertyRead(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function debugOnPropertyRead(source, property) {
      if (!property) {
        return;
      }
      var rid = randomId();
      var abort = function abort() {
        hit(source);
        debugger;
      };
      var _setChainPropAccess = function setChainPropAccess(owner, property) {
        var chainInfo = getPropertyInChain(owner, property);
        var {
          base: base
        } = chainInfo;
        var {
          prop: prop,
          chain: chain
        } = chainInfo;
        if (chain) {
          var setter = function setter(a) {
            base = a;
            if (a instanceof Object) {
              _setChainPropAccess(a, chain);
            }
          };
          Object.defineProperty(owner, prop, {
            get: function get() {
              return base;
            },
            set: setter
          });
          return;
        }
        setPropertyAccess(base, prop, {
          get: abort,
          set: noopFunc
        });
      };
      _setChainPropAccess(window, property);
      window.onerror = createOnErrorHandler(rid).bind();
    }
    function randomId() {
      return Math.random().toString(36).slice(2, 9);
    }
    function setPropertyAccess(object, property, descriptor) {
      var currentDescriptor = Object.getOwnPropertyDescriptor(object, property);
      if (currentDescriptor && !currentDescriptor.configurable) {
        return false;
      }
      Object.defineProperty(object, property, descriptor);
      return true;
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function createOnErrorHandler(rid) {
      var nativeOnError = window.onerror;
      return function onError(error) {
        if (typeof error === "string" && error.includes(rid)) {
          return true;
        }
        if (nativeOnError instanceof Function) {
          for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
            args[_key - 1] = arguments[_key];
          }
          return nativeOnError.apply(window, [error, ...args]);
        }
        return false;
      };
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      debugOnPropertyRead.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function debugOnPropertyWrite(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function debugOnPropertyWrite(source, property) {
      if (!property) {
        return;
      }
      var rid = randomId();
      var abort = function abort() {
        hit(source);
        debugger;
      };
      var _setChainPropAccess = function setChainPropAccess(owner, property) {
        var chainInfo = getPropertyInChain(owner, property);
        var {
          base: base
        } = chainInfo;
        var {
          prop: prop,
          chain: chain
        } = chainInfo;
        if (chain) {
          var setter = function setter(a) {
            base = a;
            if (a instanceof Object) {
              _setChainPropAccess(a, chain);
            }
          };
          Object.defineProperty(owner, prop, {
            get: function get() {
              return base;
            },
            set: setter
          });
          return;
        }
        setPropertyAccess(base, prop, {
          set: abort
        });
      };
      _setChainPropAccess(window, property);
      window.onerror = createOnErrorHandler(rid).bind();
    }
    function randomId() {
      return Math.random().toString(36).slice(2, 9);
    }
    function setPropertyAccess(object, property, descriptor) {
      var currentDescriptor = Object.getOwnPropertyDescriptor(object, property);
      if (currentDescriptor && !currentDescriptor.configurable) {
        return false;
      }
      Object.defineProperty(object, property, descriptor);
      return true;
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function createOnErrorHandler(rid) {
      var nativeOnError = window.onerror;
      return function onError(error) {
        if (typeof error === "string" && error.includes(rid)) {
          return true;
        }
        if (nativeOnError instanceof Function) {
          for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
            args[_key - 1] = arguments[_key];
          }
          return nativeOnError.apply(window, [error, ...args]);
        }
        return false;
      };
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      debugOnPropertyWrite.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function dirString(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function dirString(source, times) {
      var {
        dir: dir
      } = console;
      function dirWrapper(object) {
        if (typeof dir === "function") {
          dir.call(this, object);
        }
        hit(source);
      }
      console.dir = dirWrapper;
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      dirString.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function disableNewtabLinks(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function disableNewtabLinks(source) {
      document.addEventListener("click", function (ev) {
        var {
          target: target
        } = ev;
        while (target !== null) {
          if (target.localName === "a" && target.hasAttribute("target")) {
            ev.stopPropagation();
            ev.preventDefault();
            hit(source);
            break;
          }
          target = target.parentNode;
        }
      });
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      disableNewtabLinks.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function evalDataPrune(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function evalDataPrune(source, propsToRemove, requiredInitialProps, stack) {
      var prunePaths = getPrunePath(propsToRemove);
      var requiredPaths = getPrunePath(requiredInitialProps);
      var nativeObjects = {
        nativeStringify: window.JSON.stringify
      };
      var evalWrapper = function evalWrapper(target, thisArg, args) {
        var data = Reflect.apply(target, thisArg, args);
        if (typeof data === "object") {
          data = jsonPruner(source, data, prunePaths, requiredPaths, stack, nativeObjects);
        }
        return data;
      };
      var evalHandler = {
        apply: evalWrapper
      };
      window.eval = new Proxy(window.eval, evalHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function matchStackTrace(stackMatch, stackTrace) {
      if (!stackMatch || stackMatch === "") {
        return true;
      }
      var regExpValues = backupRegExpValues();
      if (shouldAbortInlineOrInjectedScript(stackMatch, stackTrace)) {
        if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
          restoreRegExpValues(regExpValues);
        }
        return true;
      }
      var stackRegexp = toRegExp(stackMatch);
      var refinedStackTrace = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      }).join("\n");
      if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
        restoreRegExpValues(regExpValues);
      }
      return getNativeRegexpTest().call(stackRegexp, refinedStackTrace);
    }
    function getWildcardPropertyInChain(base, chain) {
      var lookThrough = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var output = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : [];
      var pos = chain.indexOf(".");
      if (pos === -1) {
        if (chain === "*" || chain === "[]") {
          for (var key in base) {
            if (Object.prototype.hasOwnProperty.call(base, key)) {
              output.push({
                base: base,
                prop: key
              });
            }
          }
        } else {
          output.push({
            base: base,
            prop: chain
          });
        }
        return output;
      }
      var prop = chain.slice(0, pos);
      var shouldLookThrough = prop === "[]" && Array.isArray(base) || prop === "*" && base instanceof Object;
      if (shouldLookThrough) {
        var nextProp = chain.slice(pos + 1);
        var baseKeys = Object.keys(base);
        baseKeys.forEach(function (key) {
          var item = base[key];
          getWildcardPropertyInChain(item, nextProp, lookThrough, output);
        });
      }
      if (Array.isArray(base)) {
        base.forEach(function (key) {
          var nextBase = key;
          if (nextBase !== undefined) {
            getWildcardPropertyInChain(nextBase, chain, lookThrough, output);
          }
        });
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if (nextBase !== undefined) {
        getWildcardPropertyInChain(nextBase, chain, lookThrough, output);
      }
      return output;
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function isPruningNeeded(source, root, prunePaths, requiredPaths, stack, nativeObjects) {
      if (!root) {
        return false;
      }
      var {
        nativeStringify: nativeStringify
      } = nativeObjects;
      var shouldProcess;
      if (prunePaths.length === 0 && requiredPaths.length > 0) {
        var rootString = nativeStringify(root);
        var matchRegex = toRegExp(requiredPaths.join(""));
        var shouldLog = matchRegex.test(rootString);
        if (shouldLog) {
          logMessage(source, `${window.location.hostname}\n${nativeStringify(root, null, 2)}\nStack trace:\n${new Error().stack}`, true);
          if (root && typeof root === "object") {
            logMessage(source, root, true, false);
          }
          shouldProcess = false;
          return shouldProcess;
        }
      }
      if (stack && !matchStackTrace(stack, new Error().stack || "")) {
        shouldProcess = false;
        return shouldProcess;
      }
      var wildcardSymbols = [".*.", "*.", ".*", ".[].", "[].", ".[]"];
      var _loop = function _loop() {
          var requiredPath = requiredPaths[i];
          var lastNestedPropName = requiredPath.split(".").pop();
          var hasWildcard = wildcardSymbols.some(function (symbol) {
            return requiredPath.includes(symbol);
          });
          var details = getWildcardPropertyInChain(root, requiredPath, hasWildcard);
          if (!details.length) {
            shouldProcess = false;
            return {
              v: shouldProcess
            };
          }
          shouldProcess = !hasWildcard;
          for (var j = 0; j < details.length; j += 1) {
            var hasRequiredProp = typeof lastNestedPropName === "string" && details[j].base[lastNestedPropName] !== undefined;
            if (hasWildcard) {
              shouldProcess = hasRequiredProp || shouldProcess;
            } else {
              shouldProcess = hasRequiredProp && shouldProcess;
            }
          }
        },
        _ret;
      for (var i = 0; i < requiredPaths.length; i += 1) {
        _ret = _loop();
        if (_ret) return _ret.v;
      }
      return shouldProcess;
    }
    function jsonPruner(source, root, prunePaths, requiredPaths, stack, nativeObjects) {
      var {
        nativeStringify: nativeStringify
      } = nativeObjects;
      if (prunePaths.length === 0 && requiredPaths.length === 0) {
        logMessage(source, `${window.location.hostname}\n${nativeStringify(root, null, 2)}\nStack trace:\n${new Error().stack}`, true);
        if (root && typeof root === "object") {
          logMessage(source, root, true, false);
        }
        return root;
      }
      try {
        if (isPruningNeeded(source, root, prunePaths, requiredPaths, stack, nativeObjects) === false) {
          return root;
        }
        prunePaths.forEach(function (path) {
          var ownerObjArr = getWildcardPropertyInChain(root, path, true);
          ownerObjArr.forEach(function (ownerObj) {
            if (ownerObj !== undefined && ownerObj.base) {
              delete ownerObj.base[ownerObj.prop];
              hit(source);
            }
          });
        });
      } catch (e) {
        logMessage(source, e);
      }
      return root;
    }
    function getPrunePath(props) {
      var validPropsString = typeof props === "string" && props !== undefined && props !== "";
      return validPropsString ? props.split(/ +/) : [];
    }
    function getNativeRegexpTest() {
      var descriptor = Object.getOwnPropertyDescriptor(RegExp.prototype, "test");
      var nativeRegexTest = descriptor === null || descriptor === void 0 ? void 0 : descriptor.value;
      if (descriptor && typeof descriptor.value === "function") {
        return nativeRegexTest;
      }
      throw new Error("RegExp.prototype.test is not a function");
    }
    function shouldAbortInlineOrInjectedScript(stackMatch, stackTrace) {
      var INLINE_SCRIPT_STRING = "inlineScript";
      var INJECTED_SCRIPT_STRING = "injectedScript";
      var INJECTED_SCRIPT_MARKER = "<anonymous>";
      var isInlineScript = function isInlineScript(match) {
        return match.includes(INLINE_SCRIPT_STRING);
      };
      var isInjectedScript = function isInjectedScript(match) {
        return match.includes(INJECTED_SCRIPT_STRING);
      };
      if (!(isInlineScript(stackMatch) || isInjectedScript(stackMatch))) {
        return false;
      }
      var documentURL = window.location.href;
      var pos = documentURL.indexOf("#");
      if (pos !== -1) {
        documentURL = documentURL.slice(0, pos);
      }
      var stackSteps = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      });
      var stackLines = stackSteps.map(function (line) {
        var stack;
        var getStackTraceValues = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(line);
        if (getStackTraceValues) {
          var _stackURL, _stackURL2;
          var stackURL = getStackTraceValues[2];
          var stackLine = getStackTraceValues[3];
          var stackCol = getStackTraceValues[4];
          if ((_stackURL = stackURL) !== null && _stackURL !== void 0 && _stackURL.startsWith("(")) {
            stackURL = stackURL.slice(1);
          }
          if ((_stackURL2 = stackURL) !== null && _stackURL2 !== void 0 && _stackURL2.startsWith(INJECTED_SCRIPT_MARKER)) {
            var _stackFunction;
            stackURL = INJECTED_SCRIPT_STRING;
            var stackFunction = getStackTraceValues[1] !== undefined ? getStackTraceValues[1].slice(0, -1) : line.slice(0, getStackTraceValues.index).trim();
            if ((_stackFunction = stackFunction) !== null && _stackFunction !== void 0 && _stackFunction.startsWith("at")) {
              stackFunction = stackFunction.slice(2).trim();
            }
            stack = `${stackFunction} ${stackURL}${stackLine}${stackCol}`.trim();
          } else if (stackURL === documentURL) {
            stack = `${INLINE_SCRIPT_STRING}${stackLine}${stackCol}`.trim();
          } else {
            stack = `${stackURL}${stackLine}${stackCol}`.trim();
          }
        } else {
          stack = line;
        }
        return stack;
      });
      if (stackLines) {
        for (var index = 0; index < stackLines.length; index += 1) {
          if (isInlineScript(stackMatch) && stackLines[index].startsWith(INLINE_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
          if (isInjectedScript(stackMatch) && stackLines[index].startsWith(INJECTED_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
        }
      }
      return false;
    }
    function backupRegExpValues() {
      try {
        var arrayOfRegexpValues = [];
        for (var index = 1; index < 10; index += 1) {
          var value = `$${index}`;
          if (!RegExp[value]) {
            break;
          }
          arrayOfRegexpValues.push(RegExp[value]);
        }
        return arrayOfRegexpValues;
      } catch (error) {
        return [];
      }
    }
    function restoreRegExpValues(array) {
      if (!array.length) {
        return;
      }
      try {
        var stringPattern = "";
        if (array.length === 1) {
          stringPattern = `(${array[0]})`;
        } else {
          stringPattern = array.reduce(function (accumulator, currentValue, currentIndex) {
            if (currentIndex === 1) {
              return `(${accumulator}),(${currentValue})`;
            }
            return `${accumulator},(${currentValue})`;
          });
        }
        var regExpGroup = new RegExp(stringPattern);
        array.toString().replace(regExpGroup, "");
      } catch (error) {
        var message = `Failed to restore RegExp values: ${error}`;
        console.log(message);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      evalDataPrune.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function forceWindowClose(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function forceWindowClose(source) {
      var path = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : "";
      if (typeof window.close !== "function") {
        var message = "window.close() is not a function so 'close-window' scriptlet is unavailable";
        logMessage(source, message);
        return;
      }
      var closeImmediately = function closeImmediately() {
        try {
          hit(source);
          window.close();
        } catch (e) {
          logMessage(source, e);
        }
      };
      var closeByExtension = function closeByExtension() {
        var extCall = function extCall() {
          dispatchEvent(new Event("adguard:scriptlet-close-window"));
        };
        window.addEventListener("adguard:subscribed-to-close-window", extCall, {
          once: true
        });
        setTimeout(function () {
          window.removeEventListener("adguard:subscribed-to-close-window", extCall, {
            once: true
          });
        }, 5e3);
      };
      var shouldClose = function shouldClose() {
        if (path === "") {
          return true;
        }
        var pathRegexp = toRegExp(path);
        var currentPath = `${window.location.pathname}${window.location.search}`;
        return pathRegexp.test(currentPath);
      };
      if (shouldClose()) {
        closeImmediately();
        if (navigator.userAgent.includes("Chrome")) {
          closeByExtension();
        }
      }
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      forceWindowClose.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function hideInShadowDom(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function hideInShadowDom(source, selector, baseSelector) {
      if (!Element.prototype.attachShadow) {
        return;
      }
      var hideElement = function hideElement(targetElement) {
        var DISPLAY_NONE_CSS = "display:none!important;";
        targetElement.style.cssText = DISPLAY_NONE_CSS;
      };
      var hideHandler = function hideHandler() {
        var hostElements = !baseSelector ? findHostElements(document.documentElement) : document.querySelectorAll(baseSelector);
        var _loop = function _loop() {
          var isHidden = false;
          var {
            targets: targets,
            innerHosts: innerHosts
          } = pierceShadowDom(selector, hostElements);
          targets.forEach(function (targetEl) {
            hideElement(targetEl);
            isHidden = true;
          });
          if (isHidden) {
            hit(source);
          }
          hostElements = innerHosts;
        };
        while (hostElements.length !== 0) {
          _loop();
        }
      };
      hideHandler();
      observeDOMChanges(hideHandler, true);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function observeDOMChanges(callback) {
      var observeAttrs = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : false;
      var attrsToObserve = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : [];
      var THROTTLE_DELAY_MS = 20;
      var observer = new MutationObserver(throttle(callbackWrapper, THROTTLE_DELAY_MS));
      var connect = function connect() {
        if (attrsToObserve.length > 0) {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs,
            attributeFilter: attrsToObserve
          });
        } else {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs
          });
        }
      };
      var disconnect = function disconnect() {
        observer.disconnect();
      };
      function callbackWrapper() {
        disconnect();
        callback();
        connect();
      }
      connect();
    }
    function findHostElements(rootElement) {
      var hosts = [];
      if (rootElement) {
        var domElems = rootElement.querySelectorAll("*");
        domElems.forEach(function (el) {
          if (el.shadowRoot) {
            hosts.push(el);
          }
        });
      }
      return hosts;
    }
    function pierceShadowDom(selector, hostElements) {
      var targets = [];
      var innerHostsAcc = [];
      hostElements.forEach(function (host) {
        var simpleElems = host.querySelectorAll(selector);
        targets = targets.concat([].slice.call(simpleElems));
        var shadowRootElem = host.shadowRoot;
        var shadowChildren = shadowRootElem.querySelectorAll(selector);
        targets = targets.concat([].slice.call(shadowChildren));
        innerHostsAcc.push(findHostElements(shadowRootElem));
      });
      var innerHosts = flatten(innerHostsAcc);
      return {
        targets: targets,
        innerHosts: innerHosts
      };
    }
    function flatten(input) {
      var stack = [];
      input.forEach(function (el) {
        return stack.push(el);
      });
      var res = [];
      while (stack.length) {
        var next = stack.pop();
        if (Array.isArray(next)) {
          next.forEach(function (el) {
            return stack.push(el);
          });
        } else {
          res.push(next);
        }
      }
      return res.reverse();
    }
    function throttle(cb, delay) {
      var wait = false;
      var savedArgs;
      var _wrapper = function wrapper() {
        for (var _len = arguments.length, args = new Array(_len), _key = 0; _key < _len; _key++) {
          args[_key] = arguments[_key];
        }
        if (wait) {
          savedArgs = args;
          return;
        }
        cb(...args);
        wait = true;
        setTimeout(function () {
          wait = false;
          if (savedArgs) {
            _wrapper(...savedArgs);
            savedArgs = null;
          }
        }, delay);
      };
      return _wrapper;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      hideInShadowDom.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function hrefSanitizer(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function hrefSanitizer(source, selector) {
      var attribute = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : "text";
      var transform = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      if (!selector) {
        logMessage(source, "Selector is required.");
        return;
      }
      var BASE64_DECODE_TRANSFORM_MARKER = "base64decode";
      var REMOVE_HASH_TRANSFORM_MARKER = "removeHash";
      var REMOVE_PARAM_TRANSFORM_MARKER = "removeParam";
      var MARKER_SEPARATOR = ":";
      var COMMA = ",";
      var regexpNotValidAtStart = /^[^!-~\xAA\xB5\xBA\xC0-\xD6\xD8-\xF6\xF8-\u02C1\u02C6-\u02D1\u02E0-\u02E4\u02EC\u02EE\u0370-\u0374\u0376\u0377\u037A-\u037D\u037F\u0386\u0388-\u038A\u038C\u038E-\u03A1\u03A3-\u03F5\u03F7-\u0481\u048A-\u052F\u0531-\u0556\u0559\u0560-\u0588\u05D0-\u05EA\u05EF-\u05F2\u0620-\u064A\u066E\u066F\u0671-\u06D3\u06D5\u06E5\u06E6\u06EE\u06EF\u06FA-\u06FC\u06FF\u0710\u0712-\u072F\u074D-\u07A5\u07B1\u07CA-\u07EA\u07F4\u07F5\u07FA\u0800-\u0815\u081A\u0824\u0828\u0840-\u0858\u0860-\u086A\u0870-\u0887\u0889-\u088E\u08A0-\u08C9\u0904-\u0939\u093D\u0950\u0958-\u0961\u0971-\u0980\u0985-\u098C\u098F\u0990\u0993-\u09A8\u09AA-\u09B0\u09B2\u09B6-\u09B9\u09BD\u09CE\u09DC\u09DD\u09DF-\u09E1\u09F0\u09F1\u09FC\u0A05-\u0A0A\u0A0F\u0A10\u0A13-\u0A28\u0A2A-\u0A30\u0A32\u0A33\u0A35\u0A36\u0A38\u0A39\u0A59-\u0A5C\u0A5E\u0A72-\u0A74\u0A85-\u0A8D\u0A8F-\u0A91\u0A93-\u0AA8\u0AAA-\u0AB0\u0AB2\u0AB3\u0AB5-\u0AB9\u0ABD\u0AD0\u0AE0\u0AE1\u0AF9\u0B05-\u0B0C\u0B0F\u0B10\u0B13-\u0B28\u0B2A-\u0B30\u0B32\u0B33\u0B35-\u0B39\u0B3D\u0B5C\u0B5D\u0B5F-\u0B61\u0B71\u0B83\u0B85-\u0B8A\u0B8E-\u0B90\u0B92-\u0B95\u0B99\u0B9A\u0B9C\u0B9E\u0B9F\u0BA3\u0BA4\u0BA8-\u0BAA\u0BAE-\u0BB9\u0BD0\u0C05-\u0C0C\u0C0E-\u0C10\u0C12-\u0C28\u0C2A-\u0C39\u0C3D\u0C58-\u0C5A\u0C5D\u0C60\u0C61\u0C80\u0C85-\u0C8C\u0C8E-\u0C90\u0C92-\u0CA8\u0CAA-\u0CB3\u0CB5-\u0CB9\u0CBD\u0CDD\u0CDE\u0CE0\u0CE1\u0CF1\u0CF2\u0D04-\u0D0C\u0D0E-\u0D10\u0D12-\u0D3A\u0D3D\u0D4E\u0D54-\u0D56\u0D5F-\u0D61\u0D7A-\u0D7F\u0D85-\u0D96\u0D9A-\u0DB1\u0DB3-\u0DBB\u0DBD\u0DC0-\u0DC6\u0E01-\u0E30\u0E32\u0E33\u0E40-\u0E46\u0E81\u0E82\u0E84\u0E86-\u0E8A\u0E8C-\u0EA3\u0EA5\u0EA7-\u0EB0\u0EB2\u0EB3\u0EBD\u0EC0-\u0EC4\u0EC6\u0EDC-\u0EDF\u0F00\u0F40-\u0F47\u0F49-\u0F6C\u0F88-\u0F8C\u1000-\u102A\u103F\u1050-\u1055\u105A-\u105D\u1061\u1065\u1066\u106E-\u1070\u1075-\u1081\u108E\u10A0-\u10C5\u10C7\u10CD\u10D0-\u10FA\u10FC-\u1248\u124A-\u124D\u1250-\u1256\u1258\u125A-\u125D\u1260-\u1288\u128A-\u128D\u1290-\u12B0\u12B2-\u12B5\u12B8-\u12BE\u12C0\u12C2-\u12C5\u12C8-\u12D6\u12D8-\u1310\u1312-\u1315\u1318-\u135A\u1380-\u138F\u13A0-\u13F5\u13F8-\u13FD\u1401-\u166C\u166F-\u167F\u1681-\u169A\u16A0-\u16EA\u16F1-\u16F8\u1700-\u1711\u171F-\u1731\u1740-\u1751\u1760-\u176C\u176E-\u1770\u1780-\u17B3\u17D7\u17DC\u1820-\u1878\u1880-\u1884\u1887-\u18A8\u18AA\u18B0-\u18F5\u1900-\u191E\u1950-\u196D\u1970-\u1974\u1980-\u19AB\u19B0-\u19C9\u1A00-\u1A16\u1A20-\u1A54\u1AA7\u1B05-\u1B33\u1B45-\u1B4C\u1B83-\u1BA0\u1BAE\u1BAF\u1BBA-\u1BE5\u1C00-\u1C23\u1C4D-\u1C4F\u1C5A-\u1C7D\u1C80-\u1C8A\u1C90-\u1CBA\u1CBD-\u1CBF\u1CE9-\u1CEC\u1CEE-\u1CF3\u1CF5\u1CF6\u1CFA\u1D00-\u1DBF\u1E00-\u1F15\u1F18-\u1F1D\u1F20-\u1F45\u1F48-\u1F4D\u1F50-\u1F57\u1F59\u1F5B\u1F5D\u1F5F-\u1F7D\u1F80-\u1FB4\u1FB6-\u1FBC\u1FBE\u1FC2-\u1FC4\u1FC6-\u1FCC\u1FD0-\u1FD3\u1FD6-\u1FDB\u1FE0-\u1FEC\u1FF2-\u1FF4\u1FF6-\u1FFC\u2071\u207F\u2090-\u209C\u2102\u2107\u210A-\u2113\u2115\u2119-\u211D\u2124\u2126\u2128\u212A-\u212D\u212F-\u2139\u213C-\u213F\u2145-\u2149\u214E\u2183\u2184\u2C00-\u2CE4\u2CEB-\u2CEE\u2CF2\u2CF3\u2D00-\u2D25\u2D27\u2D2D\u2D30-\u2D67\u2D6F\u2D80-\u2D96\u2DA0-\u2DA6\u2DA8-\u2DAE\u2DB0-\u2DB6\u2DB8-\u2DBE\u2DC0-\u2DC6\u2DC8-\u2DCE\u2DD0-\u2DD6\u2DD8-\u2DDE\u2E2F\u3005\u3006\u3031-\u3035\u303B\u303C\u3041-\u3096\u309D-\u309F\u30A1-\u30FA\u30FC-\u30FF\u3105-\u312F\u3131-\u318E\u31A0-\u31BF\u31F0-\u31FF\u3400-\u4DBF\u4E00-\uA48C\uA4D0-\uA4FD\uA500-\uA60C\uA610-\uA61F\uA62A\uA62B\uA640-\uA66E\uA67F-\uA69D\uA6A0-\uA6E5\uA717-\uA71F\uA722-\uA788\uA78B-\uA7CD\uA7D0\uA7D1\uA7D3\uA7D5-\uA7DC\uA7F2-\uA801\uA803-\uA805\uA807-\uA80A\uA80C-\uA822\uA840-\uA873\uA882-\uA8B3\uA8F2-\uA8F7\uA8FB\uA8FD\uA8FE\uA90A-\uA925\uA930-\uA946\uA960-\uA97C\uA984-\uA9B2\uA9CF\uA9E0-\uA9E4\uA9E6-\uA9EF\uA9FA-\uA9FE\uAA00-\uAA28\uAA40-\uAA42\uAA44-\uAA4B\uAA60-\uAA76\uAA7A\uAA7E-\uAAAF\uAAB1\uAAB5\uAAB6\uAAB9-\uAABD\uAAC0\uAAC2\uAADB-\uAADD\uAAE0-\uAAEA\uAAF2-\uAAF4\uAB01-\uAB06\uAB09-\uAB0E\uAB11-\uAB16\uAB20-\uAB26\uAB28-\uAB2E\uAB30-\uAB5A\uAB5C-\uAB69\uAB70-\uABE2\uAC00-\uD7A3\uD7B0-\uD7C6\uD7CB-\uD7FB\uF900-\uFA6D\uFA70-\uFAD9\uFB00-\uFB06\uFB13-\uFB17\uFB1D\uFB1F-\uFB28\uFB2A-\uFB36\uFB38-\uFB3C\uFB3E\uFB40\uFB41\uFB43\uFB44\uFB46-\uFBB1\uFBD3-\uFD3D\uFD50-\uFD8F\uFD92-\uFDC7\uFDF0-\uFDFB\uFE70-\uFE74\uFE76-\uFEFC\uFF21-\uFF3A\uFF41-\uFF5A\uFF66-\uFFBE\uFFC2-\uFFC7\uFFCA-\uFFCF\uFFD2-\uFFD7\uFFDA-\uFFDC\u{10000}-\u{1000B}\u{1000D}-\u{10026}\u{10028}-\u{1003A}\u{1003C}\u{1003D}\u{1003F}-\u{1004D}\u{10050}-\u{1005D}\u{10080}-\u{100FA}\u{10280}-\u{1029C}\u{102A0}-\u{102D0}\u{10300}-\u{1031F}\u{1032D}-\u{10340}\u{10342}-\u{10349}\u{10350}-\u{10375}\u{10380}-\u{1039D}\u{103A0}-\u{103C3}\u{103C8}-\u{103CF}\u{10400}-\u{1049D}\u{104B0}-\u{104D3}\u{104D8}-\u{104FB}\u{10500}-\u{10527}\u{10530}-\u{10563}\u{10570}-\u{1057A}\u{1057C}-\u{1058A}\u{1058C}-\u{10592}\u{10594}\u{10595}\u{10597}-\u{105A1}\u{105A3}-\u{105B1}\u{105B3}-\u{105B9}\u{105BB}\u{105BC}\u{105C0}-\u{105F3}\u{10600}-\u{10736}\u{10740}-\u{10755}\u{10760}-\u{10767}\u{10780}-\u{10785}\u{10787}-\u{107B0}\u{107B2}-\u{107BA}\u{10800}-\u{10805}\u{10808}\u{1080A}-\u{10835}\u{10837}\u{10838}\u{1083C}\u{1083F}-\u{10855}\u{10860}-\u{10876}\u{10880}-\u{1089E}\u{108E0}-\u{108F2}\u{108F4}\u{108F5}\u{10900}-\u{10915}\u{10920}-\u{10939}\u{10980}-\u{109B7}\u{109BE}\u{109BF}\u{10A00}\u{10A10}-\u{10A13}\u{10A15}-\u{10A17}\u{10A19}-\u{10A35}\u{10A60}-\u{10A7C}\u{10A80}-\u{10A9C}\u{10AC0}-\u{10AC7}\u{10AC9}-\u{10AE4}\u{10B00}-\u{10B35}\u{10B40}-\u{10B55}\u{10B60}-\u{10B72}\u{10B80}-\u{10B91}\u{10C00}-\u{10C48}\u{10C80}-\u{10CB2}\u{10CC0}-\u{10CF2}\u{10D00}-\u{10D23}\u{10D4A}-\u{10D65}\u{10D6F}-\u{10D85}\u{10E80}-\u{10EA9}\u{10EB0}\u{10EB1}\u{10EC2}-\u{10EC4}\u{10F00}-\u{10F1C}\u{10F27}\u{10F30}-\u{10F45}\u{10F70}-\u{10F81}\u{10FB0}-\u{10FC4}\u{10FE0}-\u{10FF6}\u{11003}-\u{11037}\u{11071}\u{11072}\u{11075}\u{11083}-\u{110AF}\u{110D0}-\u{110E8}\u{11103}-\u{11126}\u{11144}\u{11147}\u{11150}-\u{11172}\u{11176}\u{11183}-\u{111B2}\u{111C1}-\u{111C4}\u{111DA}\u{111DC}\u{11200}-\u{11211}\u{11213}-\u{1122B}\u{1123F}\u{11240}\u{11280}-\u{11286}\u{11288}\u{1128A}-\u{1128D}\u{1128F}-\u{1129D}\u{1129F}-\u{112A8}\u{112B0}-\u{112DE}\u{11305}-\u{1130C}\u{1130F}\u{11310}\u{11313}-\u{11328}\u{1132A}-\u{11330}\u{11332}\u{11333}\u{11335}-\u{11339}\u{1133D}\u{11350}\u{1135D}-\u{11361}\u{11380}-\u{11389}\u{1138B}\u{1138E}\u{11390}-\u{113B5}\u{113B7}\u{113D1}\u{113D3}\u{11400}-\u{11434}\u{11447}-\u{1144A}\u{1145F}-\u{11461}\u{11480}-\u{114AF}\u{114C4}\u{114C5}\u{114C7}\u{11580}-\u{115AE}\u{115D8}-\u{115DB}\u{11600}-\u{1162F}\u{11644}\u{11680}-\u{116AA}\u{116B8}\u{11700}-\u{1171A}\u{11740}-\u{11746}\u{11800}-\u{1182B}\u{118A0}-\u{118DF}\u{118FF}-\u{11906}\u{11909}\u{1190C}-\u{11913}\u{11915}\u{11916}\u{11918}-\u{1192F}\u{1193F}\u{11941}\u{119A0}-\u{119A7}\u{119AA}-\u{119D0}\u{119E1}\u{119E3}\u{11A00}\u{11A0B}-\u{11A32}\u{11A3A}\u{11A50}\u{11A5C}-\u{11A89}\u{11A9D}\u{11AB0}-\u{11AF8}\u{11BC0}-\u{11BE0}\u{11C00}-\u{11C08}\u{11C0A}-\u{11C2E}\u{11C40}\u{11C72}-\u{11C8F}\u{11D00}-\u{11D06}\u{11D08}\u{11D09}\u{11D0B}-\u{11D30}\u{11D46}\u{11D60}-\u{11D65}\u{11D67}\u{11D68}\u{11D6A}-\u{11D89}\u{11D98}\u{11EE0}-\u{11EF2}\u{11F02}\u{11F04}-\u{11F10}\u{11F12}-\u{11F33}\u{11FB0}\u{12000}-\u{12399}\u{12480}-\u{12543}\u{12F90}-\u{12FF0}\u{13000}-\u{1342F}\u{13441}-\u{13446}\u{13460}-\u{143FA}\u{14400}-\u{14646}\u{16100}-\u{1611D}\u{16800}-\u{16A38}\u{16A40}-\u{16A5E}\u{16A70}-\u{16ABE}\u{16AD0}-\u{16AED}\u{16B00}-\u{16B2F}\u{16B40}-\u{16B43}\u{16B63}-\u{16B77}\u{16B7D}-\u{16B8F}\u{16D40}-\u{16D6C}\u{16E40}-\u{16E7F}\u{16F00}-\u{16F4A}\u{16F50}\u{16F93}-\u{16F9F}\u{16FE0}\u{16FE1}\u{16FE3}\u{17000}-\u{187F7}\u{18800}-\u{18CD5}\u{18CFF}-\u{18D08}\u{1AFF0}-\u{1AFF3}\u{1AFF5}-\u{1AFFB}\u{1AFFD}\u{1AFFE}\u{1B000}-\u{1B122}\u{1B132}\u{1B150}-\u{1B152}\u{1B155}\u{1B164}-\u{1B167}\u{1B170}-\u{1B2FB}\u{1BC00}-\u{1BC6A}\u{1BC70}-\u{1BC7C}\u{1BC80}-\u{1BC88}\u{1BC90}-\u{1BC99}\u{1D400}-\u{1D454}\u{1D456}-\u{1D49C}\u{1D49E}\u{1D49F}\u{1D4A2}\u{1D4A5}\u{1D4A6}\u{1D4A9}-\u{1D4AC}\u{1D4AE}-\u{1D4B9}\u{1D4BB}\u{1D4BD}-\u{1D4C3}\u{1D4C5}-\u{1D505}\u{1D507}-\u{1D50A}\u{1D50D}-\u{1D514}\u{1D516}-\u{1D51C}\u{1D51E}-\u{1D539}\u{1D53B}-\u{1D53E}\u{1D540}-\u{1D544}\u{1D546}\u{1D54A}-\u{1D550}\u{1D552}-\u{1D6A5}\u{1D6A8}-\u{1D6C0}\u{1D6C2}-\u{1D6DA}\u{1D6DC}-\u{1D6FA}\u{1D6FC}-\u{1D714}\u{1D716}-\u{1D734}\u{1D736}-\u{1D74E}\u{1D750}-\u{1D76E}\u{1D770}-\u{1D788}\u{1D78A}-\u{1D7A8}\u{1D7AA}-\u{1D7C2}\u{1D7C4}-\u{1D7CB}\u{1DF00}-\u{1DF1E}\u{1DF25}-\u{1DF2A}\u{1E030}-\u{1E06D}\u{1E100}-\u{1E12C}\u{1E137}-\u{1E13D}\u{1E14E}\u{1E290}-\u{1E2AD}\u{1E2C0}-\u{1E2EB}\u{1E4D0}-\u{1E4EB}\u{1E5D0}-\u{1E5ED}\u{1E5F0}\u{1E7E0}-\u{1E7E6}\u{1E7E8}-\u{1E7EB}\u{1E7ED}\u{1E7EE}\u{1E7F0}-\u{1E7FE}\u{1E800}-\u{1E8C4}\u{1E900}-\u{1E943}\u{1E94B}\u{1EE00}-\u{1EE03}\u{1EE05}-\u{1EE1F}\u{1EE21}\u{1EE22}\u{1EE24}\u{1EE27}\u{1EE29}-\u{1EE32}\u{1EE34}-\u{1EE37}\u{1EE39}\u{1EE3B}\u{1EE42}\u{1EE47}\u{1EE49}\u{1EE4B}\u{1EE4D}-\u{1EE4F}\u{1EE51}\u{1EE52}\u{1EE54}\u{1EE57}\u{1EE59}\u{1EE5B}\u{1EE5D}\u{1EE5F}\u{1EE61}\u{1EE62}\u{1EE64}\u{1EE67}-\u{1EE6A}\u{1EE6C}-\u{1EE72}\u{1EE74}-\u{1EE77}\u{1EE79}-\u{1EE7C}\u{1EE7E}\u{1EE80}-\u{1EE89}\u{1EE8B}-\u{1EE9B}\u{1EEA1}-\u{1EEA3}\u{1EEA5}-\u{1EEA9}\u{1EEAB}-\u{1EEBB}\u{20000}-\u{2A6DF}\u{2A700}-\u{2B739}\u{2B740}-\u{2B81D}\u{2B820}-\u{2CEA1}\u{2CEB0}-\u{2EBE0}\u{2EBF0}-\u{2EE5D}\u{2F800}-\u{2FA1D}\u{30000}-\u{3134A}\u{31350}-\u{323AF}]+/u;
      var regexpNotValidAtEnd = /[^!-~\xAA\xB5\xBA\xC0-\xD6\xD8-\xF6\xF8-\u02C1\u02C6-\u02D1\u02E0-\u02E4\u02EC\u02EE\u0370-\u0374\u0376\u0377\u037A-\u037D\u037F\u0386\u0388-\u038A\u038C\u038E-\u03A1\u03A3-\u03F5\u03F7-\u0481\u048A-\u052F\u0531-\u0556\u0559\u0560-\u0588\u05D0-\u05EA\u05EF-\u05F2\u0620-\u064A\u066E\u066F\u0671-\u06D3\u06D5\u06E5\u06E6\u06EE\u06EF\u06FA-\u06FC\u06FF\u0710\u0712-\u072F\u074D-\u07A5\u07B1\u07CA-\u07EA\u07F4\u07F5\u07FA\u0800-\u0815\u081A\u0824\u0828\u0840-\u0858\u0860-\u086A\u0870-\u0887\u0889-\u088E\u08A0-\u08C9\u0904-\u0939\u093D\u0950\u0958-\u0961\u0971-\u0980\u0985-\u098C\u098F\u0990\u0993-\u09A8\u09AA-\u09B0\u09B2\u09B6-\u09B9\u09BD\u09CE\u09DC\u09DD\u09DF-\u09E1\u09F0\u09F1\u09FC\u0A05-\u0A0A\u0A0F\u0A10\u0A13-\u0A28\u0A2A-\u0A30\u0A32\u0A33\u0A35\u0A36\u0A38\u0A39\u0A59-\u0A5C\u0A5E\u0A72-\u0A74\u0A85-\u0A8D\u0A8F-\u0A91\u0A93-\u0AA8\u0AAA-\u0AB0\u0AB2\u0AB3\u0AB5-\u0AB9\u0ABD\u0AD0\u0AE0\u0AE1\u0AF9\u0B05-\u0B0C\u0B0F\u0B10\u0B13-\u0B28\u0B2A-\u0B30\u0B32\u0B33\u0B35-\u0B39\u0B3D\u0B5C\u0B5D\u0B5F-\u0B61\u0B71\u0B83\u0B85-\u0B8A\u0B8E-\u0B90\u0B92-\u0B95\u0B99\u0B9A\u0B9C\u0B9E\u0B9F\u0BA3\u0BA4\u0BA8-\u0BAA\u0BAE-\u0BB9\u0BD0\u0C05-\u0C0C\u0C0E-\u0C10\u0C12-\u0C28\u0C2A-\u0C39\u0C3D\u0C58-\u0C5A\u0C5D\u0C60\u0C61\u0C80\u0C85-\u0C8C\u0C8E-\u0C90\u0C92-\u0CA8\u0CAA-\u0CB3\u0CB5-\u0CB9\u0CBD\u0CDD\u0CDE\u0CE0\u0CE1\u0CF1\u0CF2\u0D04-\u0D0C\u0D0E-\u0D10\u0D12-\u0D3A\u0D3D\u0D4E\u0D54-\u0D56\u0D5F-\u0D61\u0D7A-\u0D7F\u0D85-\u0D96\u0D9A-\u0DB1\u0DB3-\u0DBB\u0DBD\u0DC0-\u0DC6\u0E01-\u0E30\u0E32\u0E33\u0E40-\u0E46\u0E81\u0E82\u0E84\u0E86-\u0E8A\u0E8C-\u0EA3\u0EA5\u0EA7-\u0EB0\u0EB2\u0EB3\u0EBD\u0EC0-\u0EC4\u0EC6\u0EDC-\u0EDF\u0F00\u0F40-\u0F47\u0F49-\u0F6C\u0F88-\u0F8C\u1000-\u102A\u103F\u1050-\u1055\u105A-\u105D\u1061\u1065\u1066\u106E-\u1070\u1075-\u1081\u108E\u10A0-\u10C5\u10C7\u10CD\u10D0-\u10FA\u10FC-\u1248\u124A-\u124D\u1250-\u1256\u1258\u125A-\u125D\u1260-\u1288\u128A-\u128D\u1290-\u12B0\u12B2-\u12B5\u12B8-\u12BE\u12C0\u12C2-\u12C5\u12C8-\u12D6\u12D8-\u1310\u1312-\u1315\u1318-\u135A\u1380-\u138F\u13A0-\u13F5\u13F8-\u13FD\u1401-\u166C\u166F-\u167F\u1681-\u169A\u16A0-\u16EA\u16F1-\u16F8\u1700-\u1711\u171F-\u1731\u1740-\u1751\u1760-\u176C\u176E-\u1770\u1780-\u17B3\u17D7\u17DC\u1820-\u1878\u1880-\u1884\u1887-\u18A8\u18AA\u18B0-\u18F5\u1900-\u191E\u1950-\u196D\u1970-\u1974\u1980-\u19AB\u19B0-\u19C9\u1A00-\u1A16\u1A20-\u1A54\u1AA7\u1B05-\u1B33\u1B45-\u1B4C\u1B83-\u1BA0\u1BAE\u1BAF\u1BBA-\u1BE5\u1C00-\u1C23\u1C4D-\u1C4F\u1C5A-\u1C7D\u1C80-\u1C8A\u1C90-\u1CBA\u1CBD-\u1CBF\u1CE9-\u1CEC\u1CEE-\u1CF3\u1CF5\u1CF6\u1CFA\u1D00-\u1DBF\u1E00-\u1F15\u1F18-\u1F1D\u1F20-\u1F45\u1F48-\u1F4D\u1F50-\u1F57\u1F59\u1F5B\u1F5D\u1F5F-\u1F7D\u1F80-\u1FB4\u1FB6-\u1FBC\u1FBE\u1FC2-\u1FC4\u1FC6-\u1FCC\u1FD0-\u1FD3\u1FD6-\u1FDB\u1FE0-\u1FEC\u1FF2-\u1FF4\u1FF6-\u1FFC\u2071\u207F\u2090-\u209C\u2102\u2107\u210A-\u2113\u2115\u2119-\u211D\u2124\u2126\u2128\u212A-\u212D\u212F-\u2139\u213C-\u213F\u2145-\u2149\u214E\u2183\u2184\u2C00-\u2CE4\u2CEB-\u2CEE\u2CF2\u2CF3\u2D00-\u2D25\u2D27\u2D2D\u2D30-\u2D67\u2D6F\u2D80-\u2D96\u2DA0-\u2DA6\u2DA8-\u2DAE\u2DB0-\u2DB6\u2DB8-\u2DBE\u2DC0-\u2DC6\u2DC8-\u2DCE\u2DD0-\u2DD6\u2DD8-\u2DDE\u2E2F\u3005\u3006\u3031-\u3035\u303B\u303C\u3041-\u3096\u309D-\u309F\u30A1-\u30FA\u30FC-\u30FF\u3105-\u312F\u3131-\u318E\u31A0-\u31BF\u31F0-\u31FF\u3400-\u4DBF\u4E00-\uA48C\uA4D0-\uA4FD\uA500-\uA60C\uA610-\uA61F\uA62A\uA62B\uA640-\uA66E\uA67F-\uA69D\uA6A0-\uA6E5\uA717-\uA71F\uA722-\uA788\uA78B-\uA7CD\uA7D0\uA7D1\uA7D3\uA7D5-\uA7DC\uA7F2-\uA801\uA803-\uA805\uA807-\uA80A\uA80C-\uA822\uA840-\uA873\uA882-\uA8B3\uA8F2-\uA8F7\uA8FB\uA8FD\uA8FE\uA90A-\uA925\uA930-\uA946\uA960-\uA97C\uA984-\uA9B2\uA9CF\uA9E0-\uA9E4\uA9E6-\uA9EF\uA9FA-\uA9FE\uAA00-\uAA28\uAA40-\uAA42\uAA44-\uAA4B\uAA60-\uAA76\uAA7A\uAA7E-\uAAAF\uAAB1\uAAB5\uAAB6\uAAB9-\uAABD\uAAC0\uAAC2\uAADB-\uAADD\uAAE0-\uAAEA\uAAF2-\uAAF4\uAB01-\uAB06\uAB09-\uAB0E\uAB11-\uAB16\uAB20-\uAB26\uAB28-\uAB2E\uAB30-\uAB5A\uAB5C-\uAB69\uAB70-\uABE2\uAC00-\uD7A3\uD7B0-\uD7C6\uD7CB-\uD7FB\uF900-\uFA6D\uFA70-\uFAD9\uFB00-\uFB06\uFB13-\uFB17\uFB1D\uFB1F-\uFB28\uFB2A-\uFB36\uFB38-\uFB3C\uFB3E\uFB40\uFB41\uFB43\uFB44\uFB46-\uFBB1\uFBD3-\uFD3D\uFD50-\uFD8F\uFD92-\uFDC7\uFDF0-\uFDFB\uFE70-\uFE74\uFE76-\uFEFC\uFF21-\uFF3A\uFF41-\uFF5A\uFF66-\uFFBE\uFFC2-\uFFC7\uFFCA-\uFFCF\uFFD2-\uFFD7\uFFDA-\uFFDC\u{10000}-\u{1000B}\u{1000D}-\u{10026}\u{10028}-\u{1003A}\u{1003C}\u{1003D}\u{1003F}-\u{1004D}\u{10050}-\u{1005D}\u{10080}-\u{100FA}\u{10280}-\u{1029C}\u{102A0}-\u{102D0}\u{10300}-\u{1031F}\u{1032D}-\u{10340}\u{10342}-\u{10349}\u{10350}-\u{10375}\u{10380}-\u{1039D}\u{103A0}-\u{103C3}\u{103C8}-\u{103CF}\u{10400}-\u{1049D}\u{104B0}-\u{104D3}\u{104D8}-\u{104FB}\u{10500}-\u{10527}\u{10530}-\u{10563}\u{10570}-\u{1057A}\u{1057C}-\u{1058A}\u{1058C}-\u{10592}\u{10594}\u{10595}\u{10597}-\u{105A1}\u{105A3}-\u{105B1}\u{105B3}-\u{105B9}\u{105BB}\u{105BC}\u{105C0}-\u{105F3}\u{10600}-\u{10736}\u{10740}-\u{10755}\u{10760}-\u{10767}\u{10780}-\u{10785}\u{10787}-\u{107B0}\u{107B2}-\u{107BA}\u{10800}-\u{10805}\u{10808}\u{1080A}-\u{10835}\u{10837}\u{10838}\u{1083C}\u{1083F}-\u{10855}\u{10860}-\u{10876}\u{10880}-\u{1089E}\u{108E0}-\u{108F2}\u{108F4}\u{108F5}\u{10900}-\u{10915}\u{10920}-\u{10939}\u{10980}-\u{109B7}\u{109BE}\u{109BF}\u{10A00}\u{10A10}-\u{10A13}\u{10A15}-\u{10A17}\u{10A19}-\u{10A35}\u{10A60}-\u{10A7C}\u{10A80}-\u{10A9C}\u{10AC0}-\u{10AC7}\u{10AC9}-\u{10AE4}\u{10B00}-\u{10B35}\u{10B40}-\u{10B55}\u{10B60}-\u{10B72}\u{10B80}-\u{10B91}\u{10C00}-\u{10C48}\u{10C80}-\u{10CB2}\u{10CC0}-\u{10CF2}\u{10D00}-\u{10D23}\u{10D4A}-\u{10D65}\u{10D6F}-\u{10D85}\u{10E80}-\u{10EA9}\u{10EB0}\u{10EB1}\u{10EC2}-\u{10EC4}\u{10F00}-\u{10F1C}\u{10F27}\u{10F30}-\u{10F45}\u{10F70}-\u{10F81}\u{10FB0}-\u{10FC4}\u{10FE0}-\u{10FF6}\u{11003}-\u{11037}\u{11071}\u{11072}\u{11075}\u{11083}-\u{110AF}\u{110D0}-\u{110E8}\u{11103}-\u{11126}\u{11144}\u{11147}\u{11150}-\u{11172}\u{11176}\u{11183}-\u{111B2}\u{111C1}-\u{111C4}\u{111DA}\u{111DC}\u{11200}-\u{11211}\u{11213}-\u{1122B}\u{1123F}\u{11240}\u{11280}-\u{11286}\u{11288}\u{1128A}-\u{1128D}\u{1128F}-\u{1129D}\u{1129F}-\u{112A8}\u{112B0}-\u{112DE}\u{11305}-\u{1130C}\u{1130F}\u{11310}\u{11313}-\u{11328}\u{1132A}-\u{11330}\u{11332}\u{11333}\u{11335}-\u{11339}\u{1133D}\u{11350}\u{1135D}-\u{11361}\u{11380}-\u{11389}\u{1138B}\u{1138E}\u{11390}-\u{113B5}\u{113B7}\u{113D1}\u{113D3}\u{11400}-\u{11434}\u{11447}-\u{1144A}\u{1145F}-\u{11461}\u{11480}-\u{114AF}\u{114C4}\u{114C5}\u{114C7}\u{11580}-\u{115AE}\u{115D8}-\u{115DB}\u{11600}-\u{1162F}\u{11644}\u{11680}-\u{116AA}\u{116B8}\u{11700}-\u{1171A}\u{11740}-\u{11746}\u{11800}-\u{1182B}\u{118A0}-\u{118DF}\u{118FF}-\u{11906}\u{11909}\u{1190C}-\u{11913}\u{11915}\u{11916}\u{11918}-\u{1192F}\u{1193F}\u{11941}\u{119A0}-\u{119A7}\u{119AA}-\u{119D0}\u{119E1}\u{119E3}\u{11A00}\u{11A0B}-\u{11A32}\u{11A3A}\u{11A50}\u{11A5C}-\u{11A89}\u{11A9D}\u{11AB0}-\u{11AF8}\u{11BC0}-\u{11BE0}\u{11C00}-\u{11C08}\u{11C0A}-\u{11C2E}\u{11C40}\u{11C72}-\u{11C8F}\u{11D00}-\u{11D06}\u{11D08}\u{11D09}\u{11D0B}-\u{11D30}\u{11D46}\u{11D60}-\u{11D65}\u{11D67}\u{11D68}\u{11D6A}-\u{11D89}\u{11D98}\u{11EE0}-\u{11EF2}\u{11F02}\u{11F04}-\u{11F10}\u{11F12}-\u{11F33}\u{11FB0}\u{12000}-\u{12399}\u{12480}-\u{12543}\u{12F90}-\u{12FF0}\u{13000}-\u{1342F}\u{13441}-\u{13446}\u{13460}-\u{143FA}\u{14400}-\u{14646}\u{16100}-\u{1611D}\u{16800}-\u{16A38}\u{16A40}-\u{16A5E}\u{16A70}-\u{16ABE}\u{16AD0}-\u{16AED}\u{16B00}-\u{16B2F}\u{16B40}-\u{16B43}\u{16B63}-\u{16B77}\u{16B7D}-\u{16B8F}\u{16D40}-\u{16D6C}\u{16E40}-\u{16E7F}\u{16F00}-\u{16F4A}\u{16F50}\u{16F93}-\u{16F9F}\u{16FE0}\u{16FE1}\u{16FE3}\u{17000}-\u{187F7}\u{18800}-\u{18CD5}\u{18CFF}-\u{18D08}\u{1AFF0}-\u{1AFF3}\u{1AFF5}-\u{1AFFB}\u{1AFFD}\u{1AFFE}\u{1B000}-\u{1B122}\u{1B132}\u{1B150}-\u{1B152}\u{1B155}\u{1B164}-\u{1B167}\u{1B170}-\u{1B2FB}\u{1BC00}-\u{1BC6A}\u{1BC70}-\u{1BC7C}\u{1BC80}-\u{1BC88}\u{1BC90}-\u{1BC99}\u{1D400}-\u{1D454}\u{1D456}-\u{1D49C}\u{1D49E}\u{1D49F}\u{1D4A2}\u{1D4A5}\u{1D4A6}\u{1D4A9}-\u{1D4AC}\u{1D4AE}-\u{1D4B9}\u{1D4BB}\u{1D4BD}-\u{1D4C3}\u{1D4C5}-\u{1D505}\u{1D507}-\u{1D50A}\u{1D50D}-\u{1D514}\u{1D516}-\u{1D51C}\u{1D51E}-\u{1D539}\u{1D53B}-\u{1D53E}\u{1D540}-\u{1D544}\u{1D546}\u{1D54A}-\u{1D550}\u{1D552}-\u{1D6A5}\u{1D6A8}-\u{1D6C0}\u{1D6C2}-\u{1D6DA}\u{1D6DC}-\u{1D6FA}\u{1D6FC}-\u{1D714}\u{1D716}-\u{1D734}\u{1D736}-\u{1D74E}\u{1D750}-\u{1D76E}\u{1D770}-\u{1D788}\u{1D78A}-\u{1D7A8}\u{1D7AA}-\u{1D7C2}\u{1D7C4}-\u{1D7CB}\u{1DF00}-\u{1DF1E}\u{1DF25}-\u{1DF2A}\u{1E030}-\u{1E06D}\u{1E100}-\u{1E12C}\u{1E137}-\u{1E13D}\u{1E14E}\u{1E290}-\u{1E2AD}\u{1E2C0}-\u{1E2EB}\u{1E4D0}-\u{1E4EB}\u{1E5D0}-\u{1E5ED}\u{1E5F0}\u{1E7E0}-\u{1E7E6}\u{1E7E8}-\u{1E7EB}\u{1E7ED}\u{1E7EE}\u{1E7F0}-\u{1E7FE}\u{1E800}-\u{1E8C4}\u{1E900}-\u{1E943}\u{1E94B}\u{1EE00}-\u{1EE03}\u{1EE05}-\u{1EE1F}\u{1EE21}\u{1EE22}\u{1EE24}\u{1EE27}\u{1EE29}-\u{1EE32}\u{1EE34}-\u{1EE37}\u{1EE39}\u{1EE3B}\u{1EE42}\u{1EE47}\u{1EE49}\u{1EE4B}\u{1EE4D}-\u{1EE4F}\u{1EE51}\u{1EE52}\u{1EE54}\u{1EE57}\u{1EE59}\u{1EE5B}\u{1EE5D}\u{1EE5F}\u{1EE61}\u{1EE62}\u{1EE64}\u{1EE67}-\u{1EE6A}\u{1EE6C}-\u{1EE72}\u{1EE74}-\u{1EE77}\u{1EE79}-\u{1EE7C}\u{1EE7E}\u{1EE80}-\u{1EE89}\u{1EE8B}-\u{1EE9B}\u{1EEA1}-\u{1EEA3}\u{1EEA5}-\u{1EEA9}\u{1EEAB}-\u{1EEBB}\u{20000}-\u{2A6DF}\u{2A700}-\u{2B739}\u{2B740}-\u{2B81D}\u{2B820}-\u{2CEA1}\u{2CEB0}-\u{2EBE0}\u{2EBF0}-\u{2EE5D}\u{2F800}-\u{2FA1D}\u{30000}-\u{3134A}\u{31350}-\u{323AF}]+$/u;
      var extractNewHref = function extractNewHref(anchor, attr) {
        if (attr === "text") {
          if (!anchor.textContent) {
            return "";
          }
          return anchor.textContent.replace(regexpNotValidAtStart, "").replace(regexpNotValidAtEnd, "");
        }
        if (attr.startsWith("?")) {
          try {
            var url = new URL(anchor.href, document.location.href);
            return url.searchParams.get(attr.slice(1)) || "";
          } catch (ex) {
            logMessage(source, `Cannot retrieve the parameter '${attr.slice(1)}' from the URL '${anchor.href}`);
            return "";
          }
        }
        if (attr.startsWith("[") && attr.endsWith("]")) {
          return anchor.getAttribute(attr.slice(1, -1)) || "";
        }
        return "";
      };
      var isValidURL = function isValidURL(url) {
        try {
          new URL(url);
          return true;
        } catch (_unused) {
          return false;
        }
      };
      var getValidURL = function getValidURL(text) {
        if (!text) {
          return null;
        }
        try {
          var {
            href: href,
            protocol: protocol
          } = new URL(text, document.location.href);
          if (protocol !== "http:" && protocol !== "https:") {
            logMessage(source, `Protocol not allowed: "${protocol}", from URL: "${href}"`);
            return null;
          }
          return href;
        } catch (_unused2) {
          return null;
        }
      };
      var isSanitizableAnchor = function isSanitizableAnchor(element) {
        return element.nodeName.toLowerCase() === "a" && element.hasAttribute("href");
      };
      var _extractURLFromObject = function extractURLFromObject(obj) {
        for (var key in obj) {
          if (!Object.prototype.hasOwnProperty.call(obj, key)) {
            continue;
          }
          var value = obj[key];
          if (typeof value === "string" && isValidURL(value)) {
            return value;
          }
          if (typeof value === "object" && value !== null) {
            var result = _extractURLFromObject(value);
            if (result) {
              return result;
            }
          }
        }
        return null;
      };
      var isStringifiedObject = function isStringifiedObject(content) {
        return content.startsWith("{") && content.endsWith("}");
      };
      var decodeBase64SeveralTimes = function decodeBase64SeveralTimes(text, times) {
        var result = text;
        for (var i = 0; i < times; i += 1) {
          try {
            result = atob(result);
          } catch (e) {
            if (result === text) {
              return "";
            }
          }
        }
        if (isValidURL(result)) {
          return result;
        }
        if (isStringifiedObject(result)) {
          try {
            var parsedResult = JSON.parse(result);
            return _extractURLFromObject(parsedResult);
          } catch (ex) {
            return "";
          }
        }
        logMessage(source, `Failed to decode base64 string: ${text}`);
        return "";
      };
      var SEARCH_QUERY_MARKER = "?";
      var SEARCH_PARAMS_MARKER = "&";
      var HASHBANG_MARKER = "#!";
      var ANCHOR_MARKER = "#";
      var DECODE_ATTEMPTS_NUMBER = 10;
      var decodeSearchString = function decodeSearchString(search) {
        var searchString = search.replace(SEARCH_QUERY_MARKER, "");
        var decodedParam;
        var validEncodedParam;
        if (searchString.includes(SEARCH_PARAMS_MARKER)) {
          var searchParamsArray = searchString.split(SEARCH_PARAMS_MARKER);
          searchParamsArray.forEach(function (param) {
            decodedParam = decodeBase64SeveralTimes(param, DECODE_ATTEMPTS_NUMBER);
            if (decodedParam && decodedParam.length > 0) {
              validEncodedParam = decodedParam;
            }
          });
          return validEncodedParam;
        }
        return decodeBase64SeveralTimes(searchString, DECODE_ATTEMPTS_NUMBER);
      };
      var decodeHashString = function decodeHashString(hash) {
        var validEncodedHash = "";
        if (hash.includes(HASHBANG_MARKER)) {
          validEncodedHash = hash.replace(HASHBANG_MARKER, "");
        } else if (hash.includes(ANCHOR_MARKER)) {
          validEncodedHash = hash.replace(ANCHOR_MARKER, "");
        }
        return validEncodedHash ? decodeBase64SeveralTimes(validEncodedHash, DECODE_ATTEMPTS_NUMBER) : "";
      };
      var removeHash = function removeHash(url) {
        var urlObj = new URL(url, window.location.origin);
        if (!urlObj.hash) {
          return "";
        }
        urlObj.hash = "";
        return urlObj.toString();
      };
      var removeParam = function removeParam(url, transformValue) {
        var urlObj = new URL(url, window.location.origin);
        var paramNamesToRemoveStr = transformValue.split(MARKER_SEPARATOR)[1];
        if (!paramNamesToRemoveStr) {
          urlObj.search = "";
          return urlObj.toString();
        }
        var initSearchParamsLength = urlObj.searchParams.toString().length;
        var removeParams = paramNamesToRemoveStr.split(COMMA);
        removeParams.forEach(function (param) {
          if (urlObj.searchParams.has(param)) {
            urlObj.searchParams.delete(param);
          }
        });
        if (initSearchParamsLength === urlObj.searchParams.toString().length) {
          return "";
        }
        return urlObj.toString();
      };
      var decodeBase64URL = function decodeBase64URL(url) {
        var {
          search: search,
          hash: hash
        } = new URL(url, document.location.href);
        if (search.length > 0) {
          return decodeSearchString(search);
        }
        if (hash.length > 0) {
          return decodeHashString(hash);
        }
        logMessage(source, `Failed to execute base64 from URL: ${url}`);
        return null;
      };
      var base64Decode = function base64Decode(href) {
        if (isValidURL(href)) {
          return decodeBase64URL(href) || "";
        }
        return decodeBase64SeveralTimes(href, DECODE_ATTEMPTS_NUMBER) || "";
      };
      var sanitize = function sanitize(elementSelector) {
        var elements;
        try {
          elements = document.querySelectorAll(elementSelector);
        } catch (e) {
          logMessage(source, `Invalid selector "${elementSelector}"`);
          return;
        }
        elements.forEach(function (elem) {
          try {
            if (!isSanitizableAnchor(elem)) {
              logMessage(source, `${elem} is not a valid element to sanitize`);
              return;
            }
            var newHref = extractNewHref(elem, attribute);
            if (transform) {
              switch (true) {
                case transform === BASE64_DECODE_TRANSFORM_MARKER:
                  newHref = base64Decode(newHref);
                  break;
                case transform === REMOVE_HASH_TRANSFORM_MARKER:
                  newHref = removeHash(newHref);
                  break;
                case transform.startsWith(REMOVE_PARAM_TRANSFORM_MARKER):
                  {
                    newHref = removeParam(newHref, transform);
                    break;
                  }
                default:
                  logMessage(source, `Invalid transform option: "${transform}"`);
                  return;
              }
            }
            var newValidHref = getValidURL(newHref);
            if (!newValidHref) {
              logMessage(source, `Invalid URL: ${newHref}`);
              return;
            }
            var oldHref = elem.href;
            elem.setAttribute("href", newValidHref);
            if (newValidHref !== oldHref) {
              logMessage(source, `Sanitized "${oldHref}" to "${newValidHref}".`);
            }
          } catch (ex) {
            logMessage(source, `Failed to sanitize ${elem}.`);
          }
        });
        hit(source);
      };
      var run = function run() {
        sanitize(selector);
        observeDOMChanges(function () {
          return sanitize(selector);
        }, true);
      };
      if (document.readyState === "loading") {
        window.addEventListener("DOMContentLoaded", run, {
          once: true
        });
      } else {
        run();
      }
    }
    function observeDOMChanges(callback) {
      var observeAttrs = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : false;
      var attrsToObserve = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : [];
      var THROTTLE_DELAY_MS = 20;
      var observer = new MutationObserver(throttle(callbackWrapper, THROTTLE_DELAY_MS));
      var connect = function connect() {
        if (attrsToObserve.length > 0) {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs,
            attributeFilter: attrsToObserve
          });
        } else {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs
          });
        }
      };
      var disconnect = function disconnect() {
        observer.disconnect();
      };
      function callbackWrapper() {
        disconnect();
        callback();
        connect();
      }
      connect();
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function throttle(cb, delay) {
      var wait = false;
      var savedArgs;
      var _wrapper = function wrapper() {
        for (var _len = arguments.length, args = new Array(_len), _key = 0; _key < _len; _key++) {
          args[_key] = arguments[_key];
        }
        if (wait) {
          savedArgs = args;
          return;
        }
        cb(...args);
        wait = true;
        setTimeout(function () {
          wait = false;
          if (savedArgs) {
            _wrapper(...savedArgs);
            savedArgs = null;
          }
        }, delay);
      };
      return _wrapper;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      hrefSanitizer.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function injectCssInShadowDom(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function injectCssInShadowDom(source, cssRule) {
      var hostSelector = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : "";
      if (!Element.prototype.attachShadow || typeof Proxy === "undefined" || typeof Reflect === "undefined") {
        return;
      }
      if (cssRule.match(/(url|image-set)\(.*\)/i)) {
        logMessage(source, '"url()" function is not allowed for css rules');
        return;
      }
      var callback = function callback(shadowRoot) {
        try {
          var stylesheet = new CSSStyleSheet();
          try {
            stylesheet.insertRule(cssRule);
          } catch (e) {
            logMessage(source, `Unable to apply the rule '${cssRule}' due to: \n'${e.message}'`);
            return;
          }
          shadowRoot.adoptedStyleSheets = [...shadowRoot.adoptedStyleSheets, stylesheet];
        } catch (_unused) {
          var styleTag = document.createElement("style");
          styleTag.innerText = cssRule;
          shadowRoot.appendChild(styleTag);
        }
        hit(source);
      };
      hijackAttachShadow(window, hostSelector, callback);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function hijackAttachShadow(context, hostSelector, callback) {
      var handlerWrapper = function handlerWrapper(target, thisArg, args) {
        var shadowRoot = Reflect.apply(target, thisArg, args);
        if (thisArg && thisArg.matches(hostSelector || "*")) {
          callback(shadowRoot);
        }
        return shadowRoot;
      };
      var attachShadowHandler = {
        apply: handlerWrapper
      };
      context.Element.prototype.attachShadow = new Proxy(context.Element.prototype.attachShadow, attachShadowHandler);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      injectCssInShadowDom.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function jsonPrune(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function jsonPrune(source, propsToRemove, requiredInitialProps) {
      var stack = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var prunePaths = getPrunePath(propsToRemove);
      var requiredPaths = getPrunePath(requiredInitialProps);
      var nativeObjects = {
        nativeStringify: window.JSON.stringify
      };
      var nativeJSONParse = JSON.parse;
      var jsonParseWrapper = function jsonParseWrapper() {
        for (var _len = arguments.length, args = new Array(_len), _key = 0; _key < _len; _key++) {
          args[_key] = arguments[_key];
        }
        var root = nativeJSONParse.apply(JSON, args);
        return jsonPruner(source, root, prunePaths, requiredPaths, stack, nativeObjects);
      };
      jsonParseWrapper.toString = nativeJSONParse.toString.bind(nativeJSONParse);
      JSON.parse = jsonParseWrapper;
      var nativeResponseJson = Response.prototype.json;
      var responseJsonWrapper = function responseJsonWrapper() {
        var promise = nativeResponseJson.apply(this);
        return promise.then(function (obj) {
          return jsonPruner(source, obj, prunePaths, requiredPaths, stack, nativeObjects);
        });
      };
      if (typeof Response === "undefined") {
        return;
      }
      Response.prototype.json = responseJsonWrapper;
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function matchStackTrace(stackMatch, stackTrace) {
      if (!stackMatch || stackMatch === "") {
        return true;
      }
      var regExpValues = backupRegExpValues();
      if (shouldAbortInlineOrInjectedScript(stackMatch, stackTrace)) {
        if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
          restoreRegExpValues(regExpValues);
        }
        return true;
      }
      var stackRegexp = toRegExp(stackMatch);
      var refinedStackTrace = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      }).join("\n");
      if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
        restoreRegExpValues(regExpValues);
      }
      return getNativeRegexpTest().call(stackRegexp, refinedStackTrace);
    }
    function getWildcardPropertyInChain(base, chain) {
      var lookThrough = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var output = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : [];
      var pos = chain.indexOf(".");
      if (pos === -1) {
        if (chain === "*" || chain === "[]") {
          for (var key in base) {
            if (Object.prototype.hasOwnProperty.call(base, key)) {
              output.push({
                base: base,
                prop: key
              });
            }
          }
        } else {
          output.push({
            base: base,
            prop: chain
          });
        }
        return output;
      }
      var prop = chain.slice(0, pos);
      var shouldLookThrough = prop === "[]" && Array.isArray(base) || prop === "*" && base instanceof Object;
      if (shouldLookThrough) {
        var nextProp = chain.slice(pos + 1);
        var baseKeys = Object.keys(base);
        baseKeys.forEach(function (key) {
          var item = base[key];
          getWildcardPropertyInChain(item, nextProp, lookThrough, output);
        });
      }
      if (Array.isArray(base)) {
        base.forEach(function (key) {
          var nextBase = key;
          if (nextBase !== undefined) {
            getWildcardPropertyInChain(nextBase, chain, lookThrough, output);
          }
        });
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if (nextBase !== undefined) {
        getWildcardPropertyInChain(nextBase, chain, lookThrough, output);
      }
      return output;
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function isPruningNeeded(source, root, prunePaths, requiredPaths, stack, nativeObjects) {
      if (!root) {
        return false;
      }
      var {
        nativeStringify: nativeStringify
      } = nativeObjects;
      var shouldProcess;
      if (prunePaths.length === 0 && requiredPaths.length > 0) {
        var rootString = nativeStringify(root);
        var matchRegex = toRegExp(requiredPaths.join(""));
        var shouldLog = matchRegex.test(rootString);
        if (shouldLog) {
          logMessage(source, `${window.location.hostname}\n${nativeStringify(root, null, 2)}\nStack trace:\n${new Error().stack}`, true);
          if (root && typeof root === "object") {
            logMessage(source, root, true, false);
          }
          shouldProcess = false;
          return shouldProcess;
        }
      }
      if (stack && !matchStackTrace(stack, new Error().stack || "")) {
        shouldProcess = false;
        return shouldProcess;
      }
      var wildcardSymbols = [".*.", "*.", ".*", ".[].", "[].", ".[]"];
      var _loop = function _loop() {
          var requiredPath = requiredPaths[i];
          var lastNestedPropName = requiredPath.split(".").pop();
          var hasWildcard = wildcardSymbols.some(function (symbol) {
            return requiredPath.includes(symbol);
          });
          var details = getWildcardPropertyInChain(root, requiredPath, hasWildcard);
          if (!details.length) {
            shouldProcess = false;
            return {
              v: shouldProcess
            };
          }
          shouldProcess = !hasWildcard;
          for (var j = 0; j < details.length; j += 1) {
            var hasRequiredProp = typeof lastNestedPropName === "string" && details[j].base[lastNestedPropName] !== undefined;
            if (hasWildcard) {
              shouldProcess = hasRequiredProp || shouldProcess;
            } else {
              shouldProcess = hasRequiredProp && shouldProcess;
            }
          }
        },
        _ret;
      for (var i = 0; i < requiredPaths.length; i += 1) {
        _ret = _loop();
        if (_ret) return _ret.v;
      }
      return shouldProcess;
    }
    function jsonPruner(source, root, prunePaths, requiredPaths, stack, nativeObjects) {
      var {
        nativeStringify: nativeStringify
      } = nativeObjects;
      if (prunePaths.length === 0 && requiredPaths.length === 0) {
        logMessage(source, `${window.location.hostname}\n${nativeStringify(root, null, 2)}\nStack trace:\n${new Error().stack}`, true);
        if (root && typeof root === "object") {
          logMessage(source, root, true, false);
        }
        return root;
      }
      try {
        if (isPruningNeeded(source, root, prunePaths, requiredPaths, stack, nativeObjects) === false) {
          return root;
        }
        prunePaths.forEach(function (path) {
          var ownerObjArr = getWildcardPropertyInChain(root, path, true);
          ownerObjArr.forEach(function (ownerObj) {
            if (ownerObj !== undefined && ownerObj.base) {
              delete ownerObj.base[ownerObj.prop];
              hit(source);
            }
          });
        });
      } catch (e) {
        logMessage(source, e);
      }
      return root;
    }
    function getPrunePath(props) {
      var validPropsString = typeof props === "string" && props !== undefined && props !== "";
      return validPropsString ? props.split(/ +/) : [];
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function getNativeRegexpTest() {
      var descriptor = Object.getOwnPropertyDescriptor(RegExp.prototype, "test");
      var nativeRegexTest = descriptor === null || descriptor === void 0 ? void 0 : descriptor.value;
      if (descriptor && typeof descriptor.value === "function") {
        return nativeRegexTest;
      }
      throw new Error("RegExp.prototype.test is not a function");
    }
    function shouldAbortInlineOrInjectedScript(stackMatch, stackTrace) {
      var INLINE_SCRIPT_STRING = "inlineScript";
      var INJECTED_SCRIPT_STRING = "injectedScript";
      var INJECTED_SCRIPT_MARKER = "<anonymous>";
      var isInlineScript = function isInlineScript(match) {
        return match.includes(INLINE_SCRIPT_STRING);
      };
      var isInjectedScript = function isInjectedScript(match) {
        return match.includes(INJECTED_SCRIPT_STRING);
      };
      if (!(isInlineScript(stackMatch) || isInjectedScript(stackMatch))) {
        return false;
      }
      var documentURL = window.location.href;
      var pos = documentURL.indexOf("#");
      if (pos !== -1) {
        documentURL = documentURL.slice(0, pos);
      }
      var stackSteps = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      });
      var stackLines = stackSteps.map(function (line) {
        var stack;
        var getStackTraceValues = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(line);
        if (getStackTraceValues) {
          var _stackURL, _stackURL2;
          var stackURL = getStackTraceValues[2];
          var stackLine = getStackTraceValues[3];
          var stackCol = getStackTraceValues[4];
          if ((_stackURL = stackURL) !== null && _stackURL !== void 0 && _stackURL.startsWith("(")) {
            stackURL = stackURL.slice(1);
          }
          if ((_stackURL2 = stackURL) !== null && _stackURL2 !== void 0 && _stackURL2.startsWith(INJECTED_SCRIPT_MARKER)) {
            var _stackFunction;
            stackURL = INJECTED_SCRIPT_STRING;
            var stackFunction = getStackTraceValues[1] !== undefined ? getStackTraceValues[1].slice(0, -1) : line.slice(0, getStackTraceValues.index).trim();
            if ((_stackFunction = stackFunction) !== null && _stackFunction !== void 0 && _stackFunction.startsWith("at")) {
              stackFunction = stackFunction.slice(2).trim();
            }
            stack = `${stackFunction} ${stackURL}${stackLine}${stackCol}`.trim();
          } else if (stackURL === documentURL) {
            stack = `${INLINE_SCRIPT_STRING}${stackLine}${stackCol}`.trim();
          } else {
            stack = `${stackURL}${stackLine}${stackCol}`.trim();
          }
        } else {
          stack = line;
        }
        return stack;
      });
      if (stackLines) {
        for (var index = 0; index < stackLines.length; index += 1) {
          if (isInlineScript(stackMatch) && stackLines[index].startsWith(INLINE_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
          if (isInjectedScript(stackMatch) && stackLines[index].startsWith(INJECTED_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
        }
      }
      return false;
    }
    function backupRegExpValues() {
      try {
        var arrayOfRegexpValues = [];
        for (var index = 1; index < 10; index += 1) {
          var value = `$${index}`;
          if (!RegExp[value]) {
            break;
          }
          arrayOfRegexpValues.push(RegExp[value]);
        }
        return arrayOfRegexpValues;
      } catch (error) {
        return [];
      }
    }
    function restoreRegExpValues(array) {
      if (!array.length) {
        return;
      }
      try {
        var stringPattern = "";
        if (array.length === 1) {
          stringPattern = `(${array[0]})`;
        } else {
          stringPattern = array.reduce(function (accumulator, currentValue, currentIndex) {
            if (currentIndex === 1) {
              return `(${accumulator}),(${currentValue})`;
            }
            return `${accumulator},(${currentValue})`;
          });
        }
        var regExpGroup = new RegExp(stringPattern);
        array.toString().replace(regExpGroup, "");
      } catch (error) {
        var message = `Failed to restore RegExp values: ${error}`;
        console.log(message);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      jsonPrune.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function jsonPruneFetchResponse(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function jsonPruneFetchResponse(source, propsToRemove, obligatoryProps) {
      var propsToMatch = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var stack = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : "";
      if (typeof fetch === "undefined" || typeof Proxy === "undefined" || typeof Response === "undefined") {
        return;
      }
      var prunePaths = getPrunePath(propsToRemove);
      var requiredPaths = getPrunePath(obligatoryProps);
      var nativeStringify = window.JSON.stringify;
      var nativeRequestClone = window.Request.prototype.clone;
      var nativeResponseClone = window.Response.prototype.clone;
      var nativeFetch = window.fetch;
      var fetchHandlerWrapper = async function fetchHandlerWrapper(target, thisArg, args) {
        var fetchData = getFetchData(args, nativeRequestClone);
        if (!matchRequestProps(source, propsToMatch, fetchData)) {
          return Reflect.apply(target, thisArg, args);
        }
        var originalResponse;
        var clonedResponse;
        try {
          originalResponse = await nativeFetch.apply(null, args);
          clonedResponse = nativeResponseClone.call(originalResponse);
        } catch (_unused) {
          logMessage(source, `Could not make an original fetch request: ${fetchData.url}`);
          return Reflect.apply(target, thisArg, args);
        }
        var json;
        try {
          json = await originalResponse.json();
        } catch (e) {
          var message = `Response body can't be converted to json: ${objectToString(fetchData)}`;
          logMessage(source, message);
          return clonedResponse;
        }
        var modifiedJson = jsonPruner(source, json, prunePaths, requiredPaths, stack, {
          nativeStringify: nativeStringify,
          nativeRequestClone: nativeRequestClone,
          nativeResponseClone: nativeResponseClone,
          nativeFetch: nativeFetch
        });
        var forgedResponse = forgeResponse(originalResponse, nativeStringify(modifiedJson));
        hit(source);
        return forgedResponse;
      };
      var fetchHandler = {
        apply: fetchHandlerWrapper
      };
      window.fetch = new Proxy(window.fetch, fetchHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function getFetchData(args, nativeRequestClone) {
      var fetchPropsObj = {};
      var resource = args[0];
      var fetchUrl;
      var fetchInit;
      if (resource instanceof Request) {
        var realData = nativeRequestClone.call(resource);
        var requestData = getRequestData(realData);
        fetchUrl = requestData.url;
        fetchInit = requestData;
      } else {
        fetchUrl = resource;
        fetchInit = args[1];
      }
      fetchPropsObj.url = fetchUrl;
      if (fetchInit instanceof Object) {
        var props = Object.keys(fetchInit);
        props.forEach(function (prop) {
          fetchPropsObj[prop] = fetchInit[prop];
        });
      }
      return fetchPropsObj;
    }
    function objectToString(obj) {
      if (!obj || typeof obj !== "object") {
        return String(obj);
      }
      if (isEmptyObject(obj)) {
        return "{}";
      }
      return Object.entries(obj).map(function (pair) {
        var key = pair[0];
        var value = pair[1];
        var recordValueStr = value;
        if (value instanceof Object) {
          recordValueStr = `{ ${objectToString(value)} }`;
        }
        return `${key}:"${recordValueStr}"`;
      }).join(" ");
    }
    function matchRequestProps(source, propsToMatch, requestData) {
      if (propsToMatch === "" || propsToMatch === "*") {
        return true;
      }
      var isMatched;
      var parsedData = parseMatchProps(propsToMatch);
      if (!isValidParsedData(parsedData)) {
        logMessage(source, `Invalid parameter: ${propsToMatch}`);
        isMatched = false;
      } else {
        var matchData = getMatchPropsData(parsedData);
        var matchKeys = Object.keys(matchData);
        isMatched = matchKeys.every(function (matchKey) {
          var matchValue = matchData[matchKey];
          var dataValue = requestData[matchKey];
          return Object.prototype.hasOwnProperty.call(requestData, matchKey) && typeof dataValue === "string" && (matchValue === null || matchValue === void 0 ? void 0 : matchValue.test(dataValue));
        });
      }
      return isMatched;
    }
    function jsonPruner(source, root, prunePaths, requiredPaths, stack, nativeObjects) {
      var {
        nativeStringify: nativeStringify
      } = nativeObjects;
      if (prunePaths.length === 0 && requiredPaths.length === 0) {
        logMessage(source, `${window.location.hostname}\n${nativeStringify(root, null, 2)}\nStack trace:\n${new Error().stack}`, true);
        if (root && typeof root === "object") {
          logMessage(source, root, true, false);
        }
        return root;
      }
      try {
        if (isPruningNeeded(source, root, prunePaths, requiredPaths, stack, nativeObjects) === false) {
          return root;
        }
        prunePaths.forEach(function (path) {
          var ownerObjArr = getWildcardPropertyInChain(root, path, true);
          ownerObjArr.forEach(function (ownerObj) {
            if (ownerObj !== undefined && ownerObj.base) {
              delete ownerObj.base[ownerObj.prop];
              hit(source);
            }
          });
        });
      } catch (e) {
        logMessage(source, e);
      }
      return root;
    }
    function getPrunePath(props) {
      var validPropsString = typeof props === "string" && props !== undefined && props !== "";
      return validPropsString ? props.split(/ +/) : [];
    }
    function forgeResponse(response, textContent) {
      var {
        bodyUsed: bodyUsed,
        headers: headers,
        ok: ok,
        redirected: redirected,
        status: status,
        statusText: statusText,
        type: type,
        url: url
      } = response;
      var forgedResponse = new Response(textContent, {
        status: status,
        statusText: statusText,
        headers: headers
      });
      Object.defineProperties(forgedResponse, {
        url: {
          value: url
        },
        type: {
          value: type
        },
        ok: {
          value: ok
        },
        bodyUsed: {
          value: bodyUsed
        },
        redirected: {
          value: redirected
        }
      });
      return forgedResponse;
    }
    function isPruningNeeded(source, root, prunePaths, requiredPaths, stack, nativeObjects) {
      if (!root) {
        return false;
      }
      var {
        nativeStringify: nativeStringify
      } = nativeObjects;
      var shouldProcess;
      if (prunePaths.length === 0 && requiredPaths.length > 0) {
        var rootString = nativeStringify(root);
        var matchRegex = toRegExp(requiredPaths.join(""));
        var shouldLog = matchRegex.test(rootString);
        if (shouldLog) {
          logMessage(source, `${window.location.hostname}\n${nativeStringify(root, null, 2)}\nStack trace:\n${new Error().stack}`, true);
          if (root && typeof root === "object") {
            logMessage(source, root, true, false);
          }
          shouldProcess = false;
          return shouldProcess;
        }
      }
      if (stack && !matchStackTrace(stack, new Error().stack || "")) {
        shouldProcess = false;
        return shouldProcess;
      }
      var wildcardSymbols = [".*.", "*.", ".*", ".[].", "[].", ".[]"];
      var _loop = function _loop() {
          var requiredPath = requiredPaths[i];
          var lastNestedPropName = requiredPath.split(".").pop();
          var hasWildcard = wildcardSymbols.some(function (symbol) {
            return requiredPath.includes(symbol);
          });
          var details = getWildcardPropertyInChain(root, requiredPath, hasWildcard);
          if (!details.length) {
            shouldProcess = false;
            return {
              v: shouldProcess
            };
          }
          shouldProcess = !hasWildcard;
          for (var j = 0; j < details.length; j += 1) {
            var hasRequiredProp = typeof lastNestedPropName === "string" && details[j].base[lastNestedPropName] !== undefined;
            if (hasWildcard) {
              shouldProcess = hasRequiredProp || shouldProcess;
            } else {
              shouldProcess = hasRequiredProp && shouldProcess;
            }
          }
        },
        _ret;
      for (var i = 0; i < requiredPaths.length; i += 1) {
        _ret = _loop();
        if (_ret) return _ret.v;
      }
      return shouldProcess;
    }
    function matchStackTrace(stackMatch, stackTrace) {
      if (!stackMatch || stackMatch === "") {
        return true;
      }
      var regExpValues = backupRegExpValues();
      if (shouldAbortInlineOrInjectedScript(stackMatch, stackTrace)) {
        if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
          restoreRegExpValues(regExpValues);
        }
        return true;
      }
      var stackRegexp = toRegExp(stackMatch);
      var refinedStackTrace = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      }).join("\n");
      if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
        restoreRegExpValues(regExpValues);
      }
      return getNativeRegexpTest().call(stackRegexp, refinedStackTrace);
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    function getRequestData(request) {
      var requestInitOptions = getRequestProps();
      var entries = requestInitOptions.map(function (key) {
        var value = request[key];
        return [key, value];
      });
      return Object.fromEntries(entries);
    }
    function getRequestProps() {
      return ["url", "method", "headers", "body", "credentials", "cache", "redirect", "referrer", "referrerPolicy", "integrity", "keepalive", "signal", "mode"];
    }
    function parseMatchProps(propsToMatchStr) {
      var PROPS_DIVIDER = " ";
      var PAIRS_MARKER = ":";
      var isRequestProp = function isRequestProp(prop) {
        return getRequestProps().includes(prop);
      };
      var propsObj = {};
      var props = propsToMatchStr.split(PROPS_DIVIDER);
      props.forEach(function (prop) {
        var dividerInd = prop.indexOf(PAIRS_MARKER);
        var key = prop.slice(0, dividerInd);
        if (isRequestProp(key)) {
          var value = prop.slice(dividerInd + 1);
          propsObj[key] = value;
        } else {
          propsObj.url = prop;
        }
      });
      return propsObj;
    }
    function isValidParsedData(data) {
      return Object.values(data).every(function (value) {
        return isValidStrPattern(value);
      });
    }
    function getMatchPropsData(data) {
      var matchData = {};
      var dataKeys = Object.keys(data);
      dataKeys.forEach(function (key) {
        matchData[key] = toRegExp(data[key]);
      });
      return matchData;
    }
    function getWildcardPropertyInChain(base, chain) {
      var lookThrough = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var output = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : [];
      var pos = chain.indexOf(".");
      if (pos === -1) {
        if (chain === "*" || chain === "[]") {
          for (var key in base) {
            if (Object.prototype.hasOwnProperty.call(base, key)) {
              output.push({
                base: base,
                prop: key
              });
            }
          }
        } else {
          output.push({
            base: base,
            prop: chain
          });
        }
        return output;
      }
      var prop = chain.slice(0, pos);
      var shouldLookThrough = prop === "[]" && Array.isArray(base) || prop === "*" && base instanceof Object;
      if (shouldLookThrough) {
        var nextProp = chain.slice(pos + 1);
        var baseKeys = Object.keys(base);
        baseKeys.forEach(function (key) {
          var item = base[key];
          getWildcardPropertyInChain(item, nextProp, lookThrough, output);
        });
      }
      if (Array.isArray(base)) {
        base.forEach(function (key) {
          var nextBase = key;
          if (nextBase !== undefined) {
            getWildcardPropertyInChain(nextBase, chain, lookThrough, output);
          }
        });
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if (nextBase !== undefined) {
        getWildcardPropertyInChain(nextBase, chain, lookThrough, output);
      }
      return output;
    }
    function shouldAbortInlineOrInjectedScript(stackMatch, stackTrace) {
      var INLINE_SCRIPT_STRING = "inlineScript";
      var INJECTED_SCRIPT_STRING = "injectedScript";
      var INJECTED_SCRIPT_MARKER = "<anonymous>";
      var isInlineScript = function isInlineScript(match) {
        return match.includes(INLINE_SCRIPT_STRING);
      };
      var isInjectedScript = function isInjectedScript(match) {
        return match.includes(INJECTED_SCRIPT_STRING);
      };
      if (!(isInlineScript(stackMatch) || isInjectedScript(stackMatch))) {
        return false;
      }
      var documentURL = window.location.href;
      var pos = documentURL.indexOf("#");
      if (pos !== -1) {
        documentURL = documentURL.slice(0, pos);
      }
      var stackSteps = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      });
      var stackLines = stackSteps.map(function (line) {
        var stack;
        var getStackTraceValues = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(line);
        if (getStackTraceValues) {
          var _stackURL, _stackURL2;
          var stackURL = getStackTraceValues[2];
          var stackLine = getStackTraceValues[3];
          var stackCol = getStackTraceValues[4];
          if ((_stackURL = stackURL) !== null && _stackURL !== void 0 && _stackURL.startsWith("(")) {
            stackURL = stackURL.slice(1);
          }
          if ((_stackURL2 = stackURL) !== null && _stackURL2 !== void 0 && _stackURL2.startsWith(INJECTED_SCRIPT_MARKER)) {
            var _stackFunction;
            stackURL = INJECTED_SCRIPT_STRING;
            var stackFunction = getStackTraceValues[1] !== undefined ? getStackTraceValues[1].slice(0, -1) : line.slice(0, getStackTraceValues.index).trim();
            if ((_stackFunction = stackFunction) !== null && _stackFunction !== void 0 && _stackFunction.startsWith("at")) {
              stackFunction = stackFunction.slice(2).trim();
            }
            stack = `${stackFunction} ${stackURL}${stackLine}${stackCol}`.trim();
          } else if (stackURL === documentURL) {
            stack = `${INLINE_SCRIPT_STRING}${stackLine}${stackCol}`.trim();
          } else {
            stack = `${stackURL}${stackLine}${stackCol}`.trim();
          }
        } else {
          stack = line;
        }
        return stack;
      });
      if (stackLines) {
        for (var index = 0; index < stackLines.length; index += 1) {
          if (isInlineScript(stackMatch) && stackLines[index].startsWith(INLINE_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
          if (isInjectedScript(stackMatch) && stackLines[index].startsWith(INJECTED_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
        }
      }
      return false;
    }
    function getNativeRegexpTest() {
      var descriptor = Object.getOwnPropertyDescriptor(RegExp.prototype, "test");
      var nativeRegexTest = descriptor === null || descriptor === void 0 ? void 0 : descriptor.value;
      if (descriptor && typeof descriptor.value === "function") {
        return nativeRegexTest;
      }
      throw new Error("RegExp.prototype.test is not a function");
    }
    function backupRegExpValues() {
      try {
        var arrayOfRegexpValues = [];
        for (var index = 1; index < 10; index += 1) {
          var value = `$${index}`;
          if (!RegExp[value]) {
            break;
          }
          arrayOfRegexpValues.push(RegExp[value]);
        }
        return arrayOfRegexpValues;
      } catch (error) {
        return [];
      }
    }
    function restoreRegExpValues(array) {
      if (!array.length) {
        return;
      }
      try {
        var stringPattern = "";
        if (array.length === 1) {
          stringPattern = `(${array[0]})`;
        } else {
          stringPattern = array.reduce(function (accumulator, currentValue, currentIndex) {
            if (currentIndex === 1) {
              return `(${accumulator}),(${currentValue})`;
            }
            return `${accumulator},(${currentValue})`;
          });
        }
        var regExpGroup = new RegExp(stringPattern);
        array.toString().replace(regExpGroup, "");
      } catch (error) {
        var message = `Failed to restore RegExp values: ${error}`;
        console.log(message);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      jsonPruneFetchResponse.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function jsonPruneXhrResponse(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function jsonPruneXhrResponse(source, propsToRemove, obligatoryProps) {
      var propsToMatch = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var stack = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : "";
      if (typeof Proxy === "undefined") {
        return;
      }
      var shouldLog = !propsToRemove && !obligatoryProps;
      var prunePaths = getPrunePath(propsToRemove);
      var requiredPaths = getPrunePath(obligatoryProps);
      var nativeParse = window.JSON.parse;
      var nativeStringify = window.JSON.stringify;
      var nativeOpen = window.XMLHttpRequest.prototype.open;
      var nativeSend = window.XMLHttpRequest.prototype.send;
      var setRequestHeaderWrapper = function setRequestHeaderWrapper(setRequestHeader, thisArgument, argsList) {
        thisArgument.collectedHeaders.push(argsList);
        return Reflect.apply(setRequestHeader, thisArgument, argsList);
      };
      var setRequestHeaderHandler = {
        apply: setRequestHeaderWrapper
      };
      var xhrData;
      var openWrapper = function openWrapper(target, thisArg, args) {
        xhrData = getXhrData.apply(null, args);
        if (matchRequestProps(source, propsToMatch, xhrData) || shouldLog) {
          thisArg.xhrShouldBePruned = true;
          thisArg.headersReceived = !!thisArg.headersReceived;
        }
        if (thisArg.xhrShouldBePruned && !thisArg.headersReceived) {
          thisArg.headersReceived = true;
          thisArg.collectedHeaders = [];
          thisArg.setRequestHeader = new Proxy(thisArg.setRequestHeader, setRequestHeaderHandler);
        }
        return Reflect.apply(target, thisArg, args);
      };
      var sendWrapper = function sendWrapper(target, thisArg, args) {
        var stackTrace = new Error().stack || "";
        if (!thisArg.xhrShouldBePruned || stack && !matchStackTrace(stack, stackTrace)) {
          return Reflect.apply(target, thisArg, args);
        }
        var forgedRequest = new XMLHttpRequest();
        forgedRequest.addEventListener("readystatechange", function () {
          if (forgedRequest.readyState !== 4) {
            return;
          }
          var {
            readyState: readyState,
            response: response,
            responseText: responseText,
            responseURL: responseURL,
            responseXML: responseXML,
            status: status,
            statusText: statusText
          } = forgedRequest;
          var content = responseText || response;
          if (typeof content !== "string" && typeof content !== "object") {
            return;
          }
          var modifiedContent;
          if (typeof content === "string") {
            try {
              var jsonContent = nativeParse(content);
              if (shouldLog) {
                logMessage(source, `${window.location.hostname}\n${nativeStringify(jsonContent, null, 2)}\nStack trace:\n${stackTrace}`, true);
                logMessage(source, jsonContent, true, false);
                modifiedContent = content;
              } else {
                modifiedContent = jsonPruner(source, jsonContent, prunePaths, requiredPaths, stack = "", {
                  nativeStringify: nativeStringify
                });
                try {
                  var {
                    responseType: responseType
                  } = thisArg;
                  switch (responseType) {
                    case "":
                    case "text":
                      modifiedContent = nativeStringify(modifiedContent);
                      break;
                    case "arraybuffer":
                      modifiedContent = new TextEncoder().encode(nativeStringify(modifiedContent)).buffer;
                      break;
                    case "blob":
                      modifiedContent = new Blob([nativeStringify(modifiedContent)]);
                      break;
                    default:
                      break;
                  }
                } catch (error) {
                  var message = `Response body cannot be converted to reponse type: '${content}'`;
                  logMessage(source, message);
                  modifiedContent = content;
                }
              }
            } catch (error) {
              var _message = `Response body cannot be converted to json: '${content}'`;
              logMessage(source, _message);
              modifiedContent = content;
            }
          }
          Object.defineProperties(thisArg, {
            readyState: {
              value: readyState,
              writable: false
            },
            responseURL: {
              value: responseURL,
              writable: false
            },
            responseXML: {
              value: responseXML,
              writable: false
            },
            status: {
              value: status,
              writable: false
            },
            statusText: {
              value: statusText,
              writable: false
            },
            response: {
              value: modifiedContent,
              writable: false
            },
            responseText: {
              value: modifiedContent,
              writable: false
            }
          });
          setTimeout(function () {
            var stateEvent = new Event("readystatechange");
            thisArg.dispatchEvent(stateEvent);
            var loadEvent = new Event("load");
            thisArg.dispatchEvent(loadEvent);
            var loadEndEvent = new Event("loadend");
            thisArg.dispatchEvent(loadEndEvent);
          }, 1);
          hit(source);
        });
        nativeOpen.apply(forgedRequest, [xhrData.method, xhrData.url, Boolean(xhrData.async)]);
        thisArg.collectedHeaders.forEach(function (header) {
          forgedRequest.setRequestHeader(header[0], header[1]);
        });
        thisArg.collectedHeaders = [];
        try {
          nativeSend.call(forgedRequest, args);
        } catch (_unused) {
          return Reflect.apply(target, thisArg, args);
        }
        return undefined;
      };
      var openHandler = {
        apply: openWrapper
      };
      var sendHandler = {
        apply: sendWrapper
      };
      XMLHttpRequest.prototype.open = new Proxy(XMLHttpRequest.prototype.open, openHandler);
      XMLHttpRequest.prototype.send = new Proxy(XMLHttpRequest.prototype.send, sendHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function jsonPruner(source, root, prunePaths, requiredPaths, stack, nativeObjects) {
      var {
        nativeStringify: nativeStringify
      } = nativeObjects;
      if (prunePaths.length === 0 && requiredPaths.length === 0) {
        logMessage(source, `${window.location.hostname}\n${nativeStringify(root, null, 2)}\nStack trace:\n${new Error().stack}`, true);
        if (root && typeof root === "object") {
          logMessage(source, root, true, false);
        }
        return root;
      }
      try {
        if (isPruningNeeded(source, root, prunePaths, requiredPaths, stack, nativeObjects) === false) {
          return root;
        }
        prunePaths.forEach(function (path) {
          var ownerObjArr = getWildcardPropertyInChain(root, path, true);
          ownerObjArr.forEach(function (ownerObj) {
            if (ownerObj !== undefined && ownerObj.base) {
              delete ownerObj.base[ownerObj.prop];
              hit(source);
            }
          });
        });
      } catch (e) {
        logMessage(source, e);
      }
      return root;
    }
    function getPrunePath(props) {
      var validPropsString = typeof props === "string" && props !== undefined && props !== "";
      return validPropsString ? props.split(/ +/) : [];
    }
    function matchRequestProps(source, propsToMatch, requestData) {
      if (propsToMatch === "" || propsToMatch === "*") {
        return true;
      }
      var isMatched;
      var parsedData = parseMatchProps(propsToMatch);
      if (!isValidParsedData(parsedData)) {
        logMessage(source, `Invalid parameter: ${propsToMatch}`);
        isMatched = false;
      } else {
        var matchData = getMatchPropsData(parsedData);
        var matchKeys = Object.keys(matchData);
        isMatched = matchKeys.every(function (matchKey) {
          var matchValue = matchData[matchKey];
          var dataValue = requestData[matchKey];
          return Object.prototype.hasOwnProperty.call(requestData, matchKey) && typeof dataValue === "string" && (matchValue === null || matchValue === void 0 ? void 0 : matchValue.test(dataValue));
        });
      }
      return isMatched;
    }
    function getXhrData(method, url, async, user, password) {
      return {
        method: method,
        url: url,
        async: async,
        user: user,
        password: password
      };
    }
    function isPruningNeeded(source, root, prunePaths, requiredPaths, stack, nativeObjects) {
      if (!root) {
        return false;
      }
      var {
        nativeStringify: nativeStringify
      } = nativeObjects;
      var shouldProcess;
      if (prunePaths.length === 0 && requiredPaths.length > 0) {
        var rootString = nativeStringify(root);
        var matchRegex = toRegExp(requiredPaths.join(""));
        var shouldLog = matchRegex.test(rootString);
        if (shouldLog) {
          logMessage(source, `${window.location.hostname}\n${nativeStringify(root, null, 2)}\nStack trace:\n${new Error().stack}`, true);
          if (root && typeof root === "object") {
            logMessage(source, root, true, false);
          }
          shouldProcess = false;
          return shouldProcess;
        }
      }
      if (stack && !matchStackTrace(stack, new Error().stack || "")) {
        shouldProcess = false;
        return shouldProcess;
      }
      var wildcardSymbols = [".*.", "*.", ".*", ".[].", "[].", ".[]"];
      var _loop = function _loop() {
          var requiredPath = requiredPaths[i];
          var lastNestedPropName = requiredPath.split(".").pop();
          var hasWildcard = wildcardSymbols.some(function (symbol) {
            return requiredPath.includes(symbol);
          });
          var details = getWildcardPropertyInChain(root, requiredPath, hasWildcard);
          if (!details.length) {
            shouldProcess = false;
            return {
              v: shouldProcess
            };
          }
          shouldProcess = !hasWildcard;
          for (var j = 0; j < details.length; j += 1) {
            var hasRequiredProp = typeof lastNestedPropName === "string" && details[j].base[lastNestedPropName] !== undefined;
            if (hasWildcard) {
              shouldProcess = hasRequiredProp || shouldProcess;
            } else {
              shouldProcess = hasRequiredProp && shouldProcess;
            }
          }
        },
        _ret;
      for (var i = 0; i < requiredPaths.length; i += 1) {
        _ret = _loop();
        if (_ret) return _ret.v;
      }
      return shouldProcess;
    }
    function matchStackTrace(stackMatch, stackTrace) {
      if (!stackMatch || stackMatch === "") {
        return true;
      }
      var regExpValues = backupRegExpValues();
      if (shouldAbortInlineOrInjectedScript(stackMatch, stackTrace)) {
        if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
          restoreRegExpValues(regExpValues);
        }
        return true;
      }
      var stackRegexp = toRegExp(stackMatch);
      var refinedStackTrace = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      }).join("\n");
      if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
        restoreRegExpValues(regExpValues);
      }
      return getNativeRegexpTest().call(stackRegexp, refinedStackTrace);
    }
    function getMatchPropsData(data) {
      var matchData = {};
      var dataKeys = Object.keys(data);
      dataKeys.forEach(function (key) {
        matchData[key] = toRegExp(data[key]);
      });
      return matchData;
    }
    function getRequestProps() {
      return ["url", "method", "headers", "body", "credentials", "cache", "redirect", "referrer", "referrerPolicy", "integrity", "keepalive", "signal", "mode"];
    }
    function isValidParsedData(data) {
      return Object.values(data).every(function (value) {
        return isValidStrPattern(value);
      });
    }
    function parseMatchProps(propsToMatchStr) {
      var PROPS_DIVIDER = " ";
      var PAIRS_MARKER = ":";
      var isRequestProp = function isRequestProp(prop) {
        return getRequestProps().includes(prop);
      };
      var propsObj = {};
      var props = propsToMatchStr.split(PROPS_DIVIDER);
      props.forEach(function (prop) {
        var dividerInd = prop.indexOf(PAIRS_MARKER);
        var key = prop.slice(0, dividerInd);
        if (isRequestProp(key)) {
          var value = prop.slice(dividerInd + 1);
          propsObj[key] = value;
        } else {
          propsObj.url = prop;
        }
      });
      return propsObj;
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    function getWildcardPropertyInChain(base, chain) {
      var lookThrough = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var output = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : [];
      var pos = chain.indexOf(".");
      if (pos === -1) {
        if (chain === "*" || chain === "[]") {
          for (var key in base) {
            if (Object.prototype.hasOwnProperty.call(base, key)) {
              output.push({
                base: base,
                prop: key
              });
            }
          }
        } else {
          output.push({
            base: base,
            prop: chain
          });
        }
        return output;
      }
      var prop = chain.slice(0, pos);
      var shouldLookThrough = prop === "[]" && Array.isArray(base) || prop === "*" && base instanceof Object;
      if (shouldLookThrough) {
        var nextProp = chain.slice(pos + 1);
        var baseKeys = Object.keys(base);
        baseKeys.forEach(function (key) {
          var item = base[key];
          getWildcardPropertyInChain(item, nextProp, lookThrough, output);
        });
      }
      if (Array.isArray(base)) {
        base.forEach(function (key) {
          var nextBase = key;
          if (nextBase !== undefined) {
            getWildcardPropertyInChain(nextBase, chain, lookThrough, output);
          }
        });
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if (nextBase !== undefined) {
        getWildcardPropertyInChain(nextBase, chain, lookThrough, output);
      }
      return output;
    }
    function shouldAbortInlineOrInjectedScript(stackMatch, stackTrace) {
      var INLINE_SCRIPT_STRING = "inlineScript";
      var INJECTED_SCRIPT_STRING = "injectedScript";
      var INJECTED_SCRIPT_MARKER = "<anonymous>";
      var isInlineScript = function isInlineScript(match) {
        return match.includes(INLINE_SCRIPT_STRING);
      };
      var isInjectedScript = function isInjectedScript(match) {
        return match.includes(INJECTED_SCRIPT_STRING);
      };
      if (!(isInlineScript(stackMatch) || isInjectedScript(stackMatch))) {
        return false;
      }
      var documentURL = window.location.href;
      var pos = documentURL.indexOf("#");
      if (pos !== -1) {
        documentURL = documentURL.slice(0, pos);
      }
      var stackSteps = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      });
      var stackLines = stackSteps.map(function (line) {
        var stack;
        var getStackTraceValues = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(line);
        if (getStackTraceValues) {
          var _stackURL, _stackURL2;
          var stackURL = getStackTraceValues[2];
          var stackLine = getStackTraceValues[3];
          var stackCol = getStackTraceValues[4];
          if ((_stackURL = stackURL) !== null && _stackURL !== void 0 && _stackURL.startsWith("(")) {
            stackURL = stackURL.slice(1);
          }
          if ((_stackURL2 = stackURL) !== null && _stackURL2 !== void 0 && _stackURL2.startsWith(INJECTED_SCRIPT_MARKER)) {
            var _stackFunction;
            stackURL = INJECTED_SCRIPT_STRING;
            var stackFunction = getStackTraceValues[1] !== undefined ? getStackTraceValues[1].slice(0, -1) : line.slice(0, getStackTraceValues.index).trim();
            if ((_stackFunction = stackFunction) !== null && _stackFunction !== void 0 && _stackFunction.startsWith("at")) {
              stackFunction = stackFunction.slice(2).trim();
            }
            stack = `${stackFunction} ${stackURL}${stackLine}${stackCol}`.trim();
          } else if (stackURL === documentURL) {
            stack = `${INLINE_SCRIPT_STRING}${stackLine}${stackCol}`.trim();
          } else {
            stack = `${stackURL}${stackLine}${stackCol}`.trim();
          }
        } else {
          stack = line;
        }
        return stack;
      });
      if (stackLines) {
        for (var index = 0; index < stackLines.length; index += 1) {
          if (isInlineScript(stackMatch) && stackLines[index].startsWith(INLINE_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
          if (isInjectedScript(stackMatch) && stackLines[index].startsWith(INJECTED_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
        }
      }
      return false;
    }
    function getNativeRegexpTest() {
      var descriptor = Object.getOwnPropertyDescriptor(RegExp.prototype, "test");
      var nativeRegexTest = descriptor === null || descriptor === void 0 ? void 0 : descriptor.value;
      if (descriptor && typeof descriptor.value === "function") {
        return nativeRegexTest;
      }
      throw new Error("RegExp.prototype.test is not a function");
    }
    function backupRegExpValues() {
      try {
        var arrayOfRegexpValues = [];
        for (var index = 1; index < 10; index += 1) {
          var value = `$${index}`;
          if (!RegExp[value]) {
            break;
          }
          arrayOfRegexpValues.push(RegExp[value]);
        }
        return arrayOfRegexpValues;
      } catch (error) {
        return [];
      }
    }
    function restoreRegExpValues(array) {
      if (!array.length) {
        return;
      }
      try {
        var stringPattern = "";
        if (array.length === 1) {
          stringPattern = `(${array[0]})`;
        } else {
          stringPattern = array.reduce(function (accumulator, currentValue, currentIndex) {
            if (currentIndex === 1) {
              return `(${accumulator}),(${currentValue})`;
            }
            return `${accumulator},(${currentValue})`;
          });
        }
        var regExpGroup = new RegExp(stringPattern);
        array.toString().replace(regExpGroup, "");
      } catch (error) {
        var message = `Failed to restore RegExp values: ${error}`;
        console.log(message);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      jsonPruneXhrResponse.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function log$1(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function log() {
      for (var _len = arguments.length, args = new Array(_len), _key = 0; _key < _len; _key++) {
        args[_key] = arguments[_key];
      }
      console.log(args);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      log.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function logAddEventListener(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function logAddEventListener(source) {
      var nativeAddEventListener = window.EventTarget.prototype.addEventListener;
      function addEventListenerWrapper(type, listener) {
        var _this$constructor;
        if (validateType(type) && validateListener(listener)) {
          var message = `addEventListener("${type}", ${listenerToString(listener)})`;
          logMessage(source, message, true);
          hit(source);
        } else {
          var _message = `Invalid event type or listener passed to addEventListener:\n        type: ${convertTypeToString(type)}\n        listener: ${convertTypeToString(listener)}`;
          logMessage(source, _message, true);
        }
        var context = this;
        if (this && ((_this$constructor = this.constructor) === null || _this$constructor === void 0 ? void 0 : _this$constructor.name) === "Window" && this !== window) {
          context = window;
        }
        for (var _len = arguments.length, args = new Array(_len > 2 ? _len - 2 : 0), _key = 2; _key < _len; _key++) {
          args[_key - 2] = arguments[_key];
        }
        return nativeAddEventListener.apply(context, [type, listener, ...args]);
      }
      var descriptor = {
        configurable: true,
        set: function set() {},
        get: function get() {
          return addEventListenerWrapper;
        }
      };
      Object.defineProperty(window.EventTarget.prototype, "addEventListener", descriptor);
      Object.defineProperty(window, "addEventListener", descriptor);
      Object.defineProperty(document, "addEventListener", descriptor);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function validateType(type) {
      return typeof type !== "undefined";
    }
    function validateListener(listener) {
      return typeof listener !== "undefined" && (typeof listener === "function" || typeof listener === "object" && listener !== null && "handleEvent" in listener && typeof listener.handleEvent === "function");
    }
    function listenerToString(listener) {
      return typeof listener === "function" ? listener.toString() : listener.handleEvent.toString();
    }
    function convertTypeToString(value) {
      var output;
      if (typeof value === "undefined") {
        output = "undefined";
      } else if (typeof value === "object") {
        if (value === null) {
          output = "null";
        } else {
          output = objectToString(value);
        }
      } else {
        output = String(value);
      }
      return output;
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function objectToString(obj) {
      if (!obj || typeof obj !== "object") {
        return String(obj);
      }
      if (isEmptyObject(obj)) {
        return "{}";
      }
      return Object.entries(obj).map(function (pair) {
        var key = pair[0];
        var value = pair[1];
        var recordValueStr = value;
        if (value instanceof Object) {
          recordValueStr = `{ ${objectToString(value)} }`;
        }
        return `${key}:"${recordValueStr}"`;
      }).join(" ");
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      logAddEventListener.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function logEval(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function logEval(source) {
      var nativeEval = window.eval;
      function evalWrapper(str) {
        hit(source);
        logMessage(source, `eval("${str}")`, true);
        return nativeEval(str);
      }
      window.eval = evalWrapper;
      var nativeFunction = window.Function;
      function FunctionWrapper() {
        hit(source);
        for (var _len = arguments.length, args = new Array(_len), _key = 0; _key < _len; _key++) {
          args[_key] = arguments[_key];
        }
        logMessage(source, `new Function(${args.join(", ")})`, true);
        return nativeFunction.apply(this, [...args]);
      }
      FunctionWrapper.prototype = Object.create(nativeFunction.prototype);
      FunctionWrapper.prototype.constructor = FunctionWrapper;
      window.Function = FunctionWrapper;
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      logEval.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function logOnStackTrace(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function logOnStackTrace(source, property) {
      if (!property) {
        return;
      }
      var refineStackTrace = function refineStackTrace(stackString) {
        var regExpValues = backupRegExpValues();
        var stackSteps = stackString.split("\n").slice(2).map(function (line) {
          return line.replace(/ {4}at /, "");
        });
        var logInfoArray = stackSteps.map(function (line) {
          var funcName;
          var funcFullPath;
          var reg = /\(([^\)]+)\)/;
          var regFirefox = /(.*?@)(\S+)(:\d+):\d+\)?$/;
          if (line.match(reg)) {
            funcName = line.split(" ").slice(0, -1).join(" ");
            funcFullPath = line.match(reg)[1];
          } else if (line.match(regFirefox)) {
            funcName = line.split("@").slice(0, -1).join(" ");
            funcFullPath = line.match(regFirefox)[2];
          } else {
            funcName = "function name is not available";
            funcFullPath = line;
          }
          return [funcName, funcFullPath];
        });
        var logInfoObject = {};
        logInfoArray.forEach(function (pair) {
          logInfoObject[pair[0]] = pair[1];
        });
        if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
          restoreRegExpValues(regExpValues);
        }
        return logInfoObject;
      };
      var _setChainPropAccess = function setChainPropAccess(owner, property) {
        var chainInfo = getPropertyInChain(owner, property);
        var {
          base: base
        } = chainInfo;
        var {
          prop: prop,
          chain: chain
        } = chainInfo;
        if (chain) {
          var setter = function setter(a) {
            base = a;
            if (a instanceof Object) {
              _setChainPropAccess(a, chain);
            }
          };
          Object.defineProperty(owner, prop, {
            get: function get() {
              return base;
            },
            set: setter
          });
          return;
        }
        var value = base[prop];
        setPropertyAccess(base, prop, {
          get() {
            hit(source);
            logMessage(source, `Get ${prop}`, true);
            console.table(refineStackTrace(new Error().stack));
            return value;
          },
          set(newValue) {
            hit(source);
            logMessage(source, `Set ${prop}`, true);
            console.table(refineStackTrace(new Error().stack));
            value = newValue;
          }
        });
      };
      _setChainPropAccess(window, property);
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function setPropertyAccess(object, property, descriptor) {
      var currentDescriptor = Object.getOwnPropertyDescriptor(object, property);
      if (currentDescriptor && !currentDescriptor.configurable) {
        return false;
      }
      Object.defineProperty(object, property, descriptor);
      return true;
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    function backupRegExpValues() {
      try {
        var arrayOfRegexpValues = [];
        for (var index = 1; index < 10; index += 1) {
          var value = `$${index}`;
          if (!RegExp[value]) {
            break;
          }
          arrayOfRegexpValues.push(RegExp[value]);
        }
        return arrayOfRegexpValues;
      } catch (error) {
        return [];
      }
    }
    function restoreRegExpValues(array) {
      if (!array.length) {
        return;
      }
      try {
        var stringPattern = "";
        if (array.length === 1) {
          stringPattern = `(${array[0]})`;
        } else {
          stringPattern = array.reduce(function (accumulator, currentValue, currentIndex) {
            if (currentIndex === 1) {
              return `(${accumulator}),(${currentValue})`;
            }
            return `${accumulator},(${currentValue})`;
          });
        }
        var regExpGroup = new RegExp(stringPattern);
        array.toString().replace(regExpGroup, "");
      } catch (error) {
        var message = `Failed to restore RegExp values: ${error}`;
        console.log(message);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      logOnStackTrace.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function m3uPrune(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function m3uPrune(source, propsToRemove) {
      var urlToMatch = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : "";
      var verbose = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : false;
      if (typeof Reflect === "undefined" || typeof fetch === "undefined" || typeof Proxy === "undefined" || typeof Response === "undefined") {
        return;
      }
      var shouldPruneResponse = false;
      var shouldLogContent = verbose === "true";
      var urlMatchRegexp = toRegExp(urlToMatch);
      var SEGMENT_MARKER = "#";
      var AD_MARKER = {
        ASSET: "#EXT-X-ASSET:",
        CUE: "#EXT-X-CUE:",
        CUE_IN: "#EXT-X-CUE-IN",
        DISCONTINUITY: "#EXT-X-DISCONTINUITY",
        EXTINF: "#EXTINF",
        EXTM3U: "#EXTM3U",
        SCTE35: "#EXT-X-SCTE35:"
      };
      var COMCAST_AD_MARKER = {
        AD: "-AD-",
        VAST: "-VAST-",
        VMAP_AD: "-VMAP-AD-",
        VMAP_AD_BREAK: "#EXT-X-VMAP-AD-BREAK:"
      };
      var TAGS_ALLOWLIST = ["#EXT-X-TARGETDURATION", "#EXT-X-MEDIA-SEQUENCE", "#EXT-X-DISCONTINUITY-SEQUENCE", "#EXT-X-ENDLIST", "#EXT-X-PLAYLIST-TYPE", "#EXT-X-I-FRAMES-ONLY", "#EXT-X-MEDIA", "#EXT-X-STREAM-INF", "#EXT-X-I-FRAME-STREAM-INF", "#EXT-X-SESSION-DATA", "#EXT-X-SESSION-KEY", "#EXT-X-INDEPENDENT-SEGMENTS", "#EXT-X-START"];
      var isAllowedTag = function isAllowedTag(str) {
        return TAGS_ALLOWLIST.some(function (el) {
          return str.startsWith(el);
        });
      };
      var _pruneExtinfFromVmapBlock = function pruneExtinfFromVmapBlock(lines, i) {
        var array = lines.slice();
        var index = i;
        if (array[index].includes(AD_MARKER.EXTINF)) {
          array[index] = undefined;
          index += 1;
          if (array[index].includes(AD_MARKER.DISCONTINUITY)) {
            array[index] = undefined;
            index += 1;
            var prunedExtinf = _pruneExtinfFromVmapBlock(array, index);
            array = prunedExtinf.array;
            index = prunedExtinf.index;
          }
        }
        return {
          array: array,
          index: index
        };
      };
      var pruneVmapBlock = function pruneVmapBlock(lines) {
        var array = lines.slice();
        for (var i = 0; i < array.length - 1; i += 1) {
          if (array[i].includes(COMCAST_AD_MARKER.VMAP_AD) || array[i].includes(COMCAST_AD_MARKER.VAST) || array[i].includes(COMCAST_AD_MARKER.AD)) {
            array[i] = undefined;
            if (array[i + 1].includes(AD_MARKER.EXTINF)) {
              i += 1;
              var prunedExtinf = _pruneExtinfFromVmapBlock(array, i);
              array = prunedExtinf.array;
              i = prunedExtinf.index - 1;
            }
          }
        }
        return array;
      };
      var pruneSpliceoutBlock = function pruneSpliceoutBlock(line, index, array) {
        if (!line.startsWith(AD_MARKER.CUE)) {
          return line;
        }
        line = undefined;
        index += 1;
        if (array[index].startsWith(AD_MARKER.ASSET)) {
          array[index] = undefined;
          index += 1;
        }
        if (array[index].startsWith(AD_MARKER.SCTE35)) {
          array[index] = undefined;
          index += 1;
        }
        if (array[index].startsWith(AD_MARKER.CUE_IN)) {
          array[index] = undefined;
          index += 1;
        }
        if (array[index].startsWith(AD_MARKER.SCTE35)) {
          array[index] = undefined;
        }
        return line;
      };
      var removeM3ULineRegexp = toRegExp(propsToRemove);
      var pruneInfBlock = function pruneInfBlock(line, index, array) {
        if (!line.startsWith(AD_MARKER.EXTINF)) {
          return line;
        }
        if (!removeM3ULineRegexp.test(array[index + 1])) {
          return line;
        }
        if (!isAllowedTag(array[index])) {
          array[index] = undefined;
        }
        index += 1;
        if (!isAllowedTag(array[index])) {
          array[index] = undefined;
        }
        index += 1;
        if (array[index].startsWith(AD_MARKER.DISCONTINUITY)) {
          array[index] = undefined;
        }
        return line;
      };
      var pruneSegments = function pruneSegments(lines) {
        for (var i = 0; i < lines.length - 1; i += 1) {
          var _lines$i;
          if ((_lines$i = lines[i]) !== null && _lines$i !== void 0 && _lines$i.startsWith(SEGMENT_MARKER) && removeM3ULineRegexp.test(lines[i])) {
            var segmentName = lines[i].substring(0, lines[i].indexOf(":"));
            if (!segmentName) {
              return lines;
            }
            lines[i] = undefined;
            i += 1;
            for (var j = i; j < lines.length; j += 1) {
              if (!lines[j].includes(segmentName) && !isAllowedTag(lines[j])) {
                lines[j] = undefined;
              } else {
                i = j - 1;
                break;
              }
            }
          }
        }
        return lines;
      };
      var isM3U = function isM3U(text) {
        if (typeof text === "string") {
          var trimmedText = text.trim();
          return trimmedText.startsWith(AD_MARKER.EXTM3U) || trimmedText.startsWith(COMCAST_AD_MARKER.VMAP_AD_BREAK);
        }
        return false;
      };
      var isPruningNeeded = function isPruningNeeded(text, regexp) {
        return isM3U(text) && regexp.test(text);
      };
      var pruneM3U = function pruneM3U(text) {
        if (shouldLogContent) {
          logMessage(source, `Original M3U content:\n${text}`);
        }
        var lines = text.split(/\r?\n/);
        if (text.includes(COMCAST_AD_MARKER.VMAP_AD_BREAK)) {
          lines = pruneVmapBlock(lines);
          lines = lines.filter(function (l) {
            return !!l;
          }).join("\n");
          if (shouldLogContent) {
            logMessage(source, `Modified M3U content:\n${lines}`);
          }
          return lines;
        }
        lines = pruneSegments(lines);
        lines = lines.map(function (line, index, array) {
          if (typeof line === "undefined") {
            return line;
          }
          line = pruneSpliceoutBlock(line, index, array);
          if (typeof line !== "undefined") {
            line = pruneInfBlock(line, index, array);
          }
          return line;
        }).filter(function (l) {
          return !!l;
        }).join("\n");
        if (shouldLogContent) {
          logMessage(source, `Modified M3U content:\n${lines}`);
        }
        return lines;
      };
      var nativeOpen = window.XMLHttpRequest.prototype.open;
      var nativeSend = window.XMLHttpRequest.prototype.send;
      var xhrData;
      var openWrapper = function openWrapper(target, thisArg, args) {
        xhrData = getXhrData.apply(null, args);
        if (matchRequestProps(source, urlToMatch, xhrData)) {
          thisArg.shouldBePruned = true;
        }
        if (thisArg.shouldBePruned) {
          thisArg.collectedHeaders = [];
          var setRequestHeaderWrapper = function setRequestHeaderWrapper(target, thisArg, args) {
            thisArg.collectedHeaders.push(args);
            return Reflect.apply(target, thisArg, args);
          };
          var setRequestHeaderHandler = {
            apply: setRequestHeaderWrapper
          };
          thisArg.setRequestHeader = new Proxy(thisArg.setRequestHeader, setRequestHeaderHandler);
        }
        return Reflect.apply(target, thisArg, args);
      };
      var sendWrapper = function sendWrapper(target, thisArg, args) {
        var allowedResponseTypeValues = ["", "text"];
        if (!thisArg.shouldBePruned || !allowedResponseTypeValues.includes(thisArg.responseType)) {
          return Reflect.apply(target, thisArg, args);
        }
        var forgedRequest = new XMLHttpRequest();
        forgedRequest.addEventListener("readystatechange", function () {
          if (forgedRequest.readyState !== 4) {
            return;
          }
          var {
            readyState: readyState,
            response: response,
            responseText: responseText,
            responseURL: responseURL,
            responseXML: responseXML,
            status: status,
            statusText: statusText
          } = forgedRequest;
          var content = responseText || response;
          if (typeof content !== "string") {
            return;
          }
          if (!propsToRemove) {
            if (isM3U(response)) {
              var message = `XMLHttpRequest.open() URL: ${responseURL}\nresponse: ${response}`;
              logMessage(source, message);
            }
          } else {
            shouldPruneResponse = isPruningNeeded(response, removeM3ULineRegexp);
          }
          var responseContent = shouldPruneResponse ? pruneM3U(response) : response;
          Object.defineProperties(thisArg, {
            readyState: {
              value: readyState,
              writable: false
            },
            responseURL: {
              value: responseURL,
              writable: false
            },
            responseXML: {
              value: responseXML,
              writable: false
            },
            status: {
              value: status,
              writable: false
            },
            statusText: {
              value: statusText,
              writable: false
            },
            response: {
              value: responseContent,
              writable: false
            },
            responseText: {
              value: responseContent,
              writable: false
            }
          });
          setTimeout(function () {
            var stateEvent = new Event("readystatechange");
            thisArg.dispatchEvent(stateEvent);
            var loadEvent = new Event("load");
            thisArg.dispatchEvent(loadEvent);
            var loadEndEvent = new Event("loadend");
            thisArg.dispatchEvent(loadEndEvent);
          }, 1);
          hit(source);
        });
        nativeOpen.apply(forgedRequest, [xhrData.method, xhrData.url]);
        thisArg.collectedHeaders.forEach(function (header) {
          var name = header[0];
          var value = header[1];
          forgedRequest.setRequestHeader(name, value);
        });
        thisArg.collectedHeaders = [];
        try {
          nativeSend.call(forgedRequest, args);
        } catch (_unused) {
          return Reflect.apply(target, thisArg, args);
        }
        return undefined;
      };
      var openHandler = {
        apply: openWrapper
      };
      var sendHandler = {
        apply: sendWrapper
      };
      XMLHttpRequest.prototype.open = new Proxy(XMLHttpRequest.prototype.open, openHandler);
      XMLHttpRequest.prototype.send = new Proxy(XMLHttpRequest.prototype.send, sendHandler);
      var nativeFetch = window.fetch;
      var fetchWrapper = async function fetchWrapper(target, thisArg, args) {
        var fetchURL = args[0] instanceof Request ? args[0].url : args[0];
        if (typeof fetchURL !== "string" || fetchURL.length === 0) {
          return Reflect.apply(target, thisArg, args);
        }
        if (urlMatchRegexp.test(fetchURL)) {
          var response = await nativeFetch(...args);
          var clonedResponse = response.clone();
          var responseText = await response.text();
          if (!propsToRemove && isM3U(responseText)) {
            var message = `fetch URL: ${fetchURL}\nresponse text: ${responseText}`;
            logMessage(source, message);
            return clonedResponse;
          }
          if (isPruningNeeded(responseText, removeM3ULineRegexp)) {
            var prunedText = pruneM3U(responseText);
            hit(source);
            return new Response(prunedText, {
              status: response.status,
              statusText: response.statusText,
              headers: response.headers
            });
          }
          return clonedResponse;
        }
        return Reflect.apply(target, thisArg, args);
      };
      var fetchHandler = {
        apply: fetchWrapper
      };
      window.fetch = new Proxy(window.fetch, fetchHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function getXhrData(method, url, async, user, password) {
      return {
        method: method,
        url: url,
        async: async,
        user: user,
        password: password
      };
    }
    function matchRequestProps(source, propsToMatch, requestData) {
      if (propsToMatch === "" || propsToMatch === "*") {
        return true;
      }
      var isMatched;
      var parsedData = parseMatchProps(propsToMatch);
      if (!isValidParsedData(parsedData)) {
        logMessage(source, `Invalid parameter: ${propsToMatch}`);
        isMatched = false;
      } else {
        var matchData = getMatchPropsData(parsedData);
        var matchKeys = Object.keys(matchData);
        isMatched = matchKeys.every(function (matchKey) {
          var matchValue = matchData[matchKey];
          var dataValue = requestData[matchKey];
          return Object.prototype.hasOwnProperty.call(requestData, matchKey) && typeof dataValue === "string" && (matchValue === null || matchValue === void 0 ? void 0 : matchValue.test(dataValue));
        });
      }
      return isMatched;
    }
    function getMatchPropsData(data) {
      var matchData = {};
      var dataKeys = Object.keys(data);
      dataKeys.forEach(function (key) {
        matchData[key] = toRegExp(data[key]);
      });
      return matchData;
    }
    function getRequestProps() {
      return ["url", "method", "headers", "body", "credentials", "cache", "redirect", "referrer", "referrerPolicy", "integrity", "keepalive", "signal", "mode"];
    }
    function isValidParsedData(data) {
      return Object.values(data).every(function (value) {
        return isValidStrPattern(value);
      });
    }
    function parseMatchProps(propsToMatchStr) {
      var PROPS_DIVIDER = " ";
      var PAIRS_MARKER = ":";
      var isRequestProp = function isRequestProp(prop) {
        return getRequestProps().includes(prop);
      };
      var propsObj = {};
      var props = propsToMatchStr.split(PROPS_DIVIDER);
      props.forEach(function (prop) {
        var dividerInd = prop.indexOf(PAIRS_MARKER);
        var key = prop.slice(0, dividerInd);
        if (isRequestProp(key)) {
          var value = prop.slice(dividerInd + 1);
          propsObj[key] = value;
        } else {
          propsObj.url = prop;
        }
      });
      return propsObj;
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      m3uPrune.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function metrikaYandexTag(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function metrikaYandexTag(source) {
      var asyncCallbackFromOptions = function asyncCallbackFromOptions(id, param) {
        var options = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : {};
        var {
          callback: callback
        } = options;
        var {
          ctx: ctx
        } = options;
        if (typeof callback === "function") {
          callback = ctx !== undefined ? callback.bind(ctx) : callback;
          setTimeout(function () {
            return callback();
          });
        }
      };
      var addFileExtension = noopFunc;
      var extLink = asyncCallbackFromOptions;
      var file = asyncCallbackFromOptions;
      var getClientID = function getClientID(id, cb) {
        if (!cb) {
          return;
        }
        setTimeout(cb(null));
      };
      var hitFunc = asyncCallbackFromOptions;
      var notBounce = asyncCallbackFromOptions;
      var params = noopFunc;
      var reachGoal = function reachGoal(id, target, params, callback, ctx) {
        asyncCallbackFromOptions(null, null, {
          callback: callback,
          ctx: ctx
        });
      };
      var setUserID = noopFunc;
      var userParams = noopFunc;
      var destruct = noopFunc;
      var api = {
        addFileExtension: addFileExtension,
        extLink: extLink,
        file: file,
        getClientID: getClientID,
        hit: hitFunc,
        notBounce: notBounce,
        params: params,
        reachGoal: reachGoal,
        setUserID: setUserID,
        userParams: userParams,
        destruct: destruct
      };
      function init(id) {
        window[`yaCounter${id}`] = api;
        document.dispatchEvent(new Event(`yacounter${id}inited`));
      }
      function ym(id, funcName) {
        if (funcName === "init") {
          return init(id);
        }
        for (var _len = arguments.length, args = new Array(_len > 2 ? _len - 2 : 0), _key = 2; _key < _len; _key++) {
          args[_key - 2] = arguments[_key];
        }
        return api[funcName] && api[funcName](id, ...args);
      }
      if (typeof window.ym === "undefined") {
        window.ym = ym;
        ym.a = [];
      } else if (window.ym && window.ym.a) {
        ym.a = window.ym.a;
        window.ym = ym;
        window.ym.a.forEach(function (params) {
          var id = params[0];
          init(id);
        });
      }
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      metrikaYandexTag.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function metrikaYandexWatch(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function metrikaYandexWatch(source) {
      var cbName = "yandex_metrika_callbacks";
      var asyncCallbackFromOptions = function asyncCallbackFromOptions() {
        var options = arguments.length > 0 && arguments[0] !== undefined ? arguments[0] : {};
        var {
          callback: callback
        } = options;
        var {
          ctx: ctx
        } = options;
        if (typeof callback === "function") {
          callback = ctx !== undefined ? callback.bind(ctx) : callback;
          setTimeout(function () {
            return callback();
          });
        }
      };
      function Metrika() {}
      Metrika.counters = noopArray;
      Metrika.prototype.addFileExtension = noopFunc;
      Metrika.prototype.getClientID = noopFunc;
      Metrika.prototype.setUserID = noopFunc;
      Metrika.prototype.userParams = noopFunc;
      Metrika.prototype.params = noopFunc;
      Metrika.prototype.counters = noopArray;
      Metrika.prototype.extLink = function (url, options) {
        asyncCallbackFromOptions(options);
      };
      Metrika.prototype.file = function (url, options) {
        asyncCallbackFromOptions(options);
      };
      Metrika.prototype.hit = function (url, options) {
        asyncCallbackFromOptions(options);
      };
      Metrika.prototype.reachGoal = function (target, params, cb, ctx) {
        asyncCallbackFromOptions({
          callback: cb,
          ctx: ctx
        });
      };
      Metrika.prototype.notBounce = asyncCallbackFromOptions;
      if (window.Ya) {
        window.Ya.Metrika = Metrika;
      } else {
        window.Ya = {
          Metrika: Metrika
        };
      }
      if (window[cbName] && Array.isArray(window[cbName])) {
        window[cbName].forEach(function (func) {
          if (typeof func === "function") {
            func();
          }
        });
      }
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    function noopArray() {
      return [];
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      metrikaYandexWatch.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function noProtectedAudience(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function noProtectedAudience(source) {
      if (Document instanceof Object === false) {
        return;
      }
      var protectedAudienceMethods = {
        joinAdInterestGroup: noopResolveVoid,
        runAdAuction: noopResolveNull,
        leaveAdInterestGroup: noopResolveVoid,
        clearOriginJoinedAdInterestGroups: noopResolveVoid,
        createAuctionNonce: noopStr,
        updateAdInterestGroups: noopFunc
      };
      for (var _i = 0, _Object$keys = Object.keys(protectedAudienceMethods); _i < _Object$keys.length; _i++) {
        var key = _Object$keys[_i];
        var methodName = key;
        var prototype = Navigator.prototype;
        if (!Object.prototype.hasOwnProperty.call(prototype, methodName) || prototype[methodName] instanceof Function === false) {
          continue;
        }
        prototype[methodName] = protectedAudienceMethods[methodName];
      }
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopStr() {
      return "";
    }
    function noopFunc() {}
    function noopResolveVoid() {
      return Promise.resolve(undefined);
    }
    function noopResolveNull() {
      return Promise.resolve(null);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      noProtectedAudience.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function noTopics(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function noTopics(source) {
      var TOPICS_PROPERTY_NAME = "browsingTopics";
      if (Document instanceof Object === false) {
        return;
      }
      if (!Object.prototype.hasOwnProperty.call(Document.prototype, TOPICS_PROPERTY_NAME) || Document.prototype[TOPICS_PROPERTY_NAME] instanceof Function === false) {
        return;
      }
      Document.prototype[TOPICS_PROPERTY_NAME] = function () {
        return noopPromiseResolve("[]");
      };
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopPromiseResolve() {
      var responseBody = arguments.length > 0 && arguments[0] !== undefined ? arguments[0] : "{}";
      var responseUrl = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : "";
      var responseType = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : "basic";
      if (typeof Response === "undefined") {
        return;
      }
      var response = new Response(responseBody, {
        status: 200,
        statusText: "OK"
      });
      if (responseType === "opaque") {
        Object.defineProperties(response, {
          body: {
            value: null
          },
          status: {
            value: 0
          },
          ok: {
            value: false
          },
          statusText: {
            value: ""
          },
          url: {
            value: ""
          },
          type: {
            value: responseType
          }
        });
      } else {
        Object.defineProperties(response, {
          url: {
            value: responseUrl
          },
          type: {
            value: responseType
          }
        });
      }
      return Promise.resolve(response);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      noTopics.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function noeval(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function noeval(source) {
      window.eval = function evalWrapper(s) {
        hit(source);
        logMessage(source, `AdGuard has prevented eval:\n${s}`, true);
      }.bind();
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      noeval.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function nowebrtc(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function nowebrtc(source) {
      var propertyName = "";
      if (window.RTCPeerConnection) {
        propertyName = "RTCPeerConnection";
      } else if (window.webkitRTCPeerConnection) {
        propertyName = "webkitRTCPeerConnection";
      }
      if (propertyName === "") {
        return;
      }
      var rtcReplacement = function rtcReplacement(config) {
        var message = `Document tried to create an RTCPeerConnection: ${convertRtcConfigToString(config)}`;
        logMessage(source, message);
        hit(source);
      };
      rtcReplacement.prototype = {
        close: noopFunc,
        createDataChannel: noopFunc,
        createOffer: noopFunc,
        setRemoteDescription: noopFunc
      };
      var rtc = window[propertyName];
      window[propertyName] = rtcReplacement;
      if (rtc.prototype) {
        rtc.prototype.createDataChannel = function (a, b) {
          return {
            close: noopFunc,
            send: noopFunc
          };
        }.bind(null);
      }
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function convertRtcConfigToString(config) {
      var UNDEF_STR = "undefined";
      var str = UNDEF_STR;
      if (config === null) {
        str = "null";
      } else if (config instanceof Object) {
        var SERVERS_PROP_NAME = "iceServers";
        var URLS_PROP_NAME = "urls";
        if (Object.prototype.hasOwnProperty.call(config, SERVERS_PROP_NAME) && config[SERVERS_PROP_NAME] && Object.prototype.hasOwnProperty.call(config[SERVERS_PROP_NAME][0], URLS_PROP_NAME) && !!config[SERVERS_PROP_NAME][0][URLS_PROP_NAME]) {
          str = config[SERVERS_PROP_NAME][0][URLS_PROP_NAME].toString();
        }
      }
      return str;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      nowebrtc.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventAddEventListener(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventAddEventListener(source, typeSearch, listenerSearch) {
      var typeSearchRegexp = toRegExp(typeSearch);
      var listenerSearchRegexp = toRegExp(listenerSearch);
      var nativeAddEventListener = window.EventTarget.prototype.addEventListener;
      function addEventListenerWrapper(type, listener) {
        var _this$constructor;
        var shouldPrevent = false;
        if (validateType(type) && validateListener(listener)) {
          shouldPrevent = typeSearchRegexp.test(type.toString()) && listenerSearchRegexp.test(listenerToString(listener));
        }
        if (shouldPrevent) {
          hit(source);
          return undefined;
        }
        var context = this;
        if (this && ((_this$constructor = this.constructor) === null || _this$constructor === void 0 ? void 0 : _this$constructor.name) === "Window" && this !== window) {
          context = window;
        }
        for (var _len = arguments.length, args = new Array(_len > 2 ? _len - 2 : 0), _key = 2; _key < _len; _key++) {
          args[_key - 2] = arguments[_key];
        }
        return nativeAddEventListener.apply(context, [type, listener, ...args]);
      }
      var descriptor = {
        configurable: true,
        set: function set() {},
        get: function get() {
          return addEventListenerWrapper;
        }
      };
      Object.defineProperty(window.EventTarget.prototype, "addEventListener", descriptor);
      Object.defineProperty(window, "addEventListener", descriptor);
      Object.defineProperty(document, "addEventListener", descriptor);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function validateType(type) {
      return typeof type !== "undefined";
    }
    function validateListener(listener) {
      return typeof listener !== "undefined" && (typeof listener === "function" || typeof listener === "object" && listener !== null && "handleEvent" in listener && typeof listener.handleEvent === "function");
    }
    function listenerToString(listener) {
      return typeof listener === "function" ? listener.toString() : listener.handleEvent.toString();
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventAddEventListener.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventAdfly(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventAdfly(source) {
      var isDigit = function isDigit(data) {
        return /^\d$/.test(data);
      };
      var handler = function handler(encodedURL) {
        var evenChars = "";
        var oddChars = "";
        for (var i = 0; i < encodedURL.length; i += 1) {
          if (i % 2 === 0) {
            evenChars += encodedURL.charAt(i);
          } else {
            oddChars = encodedURL.charAt(i) + oddChars;
          }
        }
        var data = (evenChars + oddChars).split("");
        for (var _i = 0; _i < data.length; _i += 1) {
          if (isDigit(data[_i])) {
            for (var ii = _i + 1; ii < data.length; ii += 1) {
              if (isDigit(data[ii])) {
                var temp = parseInt(data[_i], 10) ^ parseInt(data[ii], 10);
                if (temp < 10) {
                  data[_i] = temp.toString();
                }
                _i = ii;
                break;
              }
            }
          }
        }
        data = data.join("");
        var decodedURL = window.atob(data).slice(16, -16);
        if (window.stop) {
          window.stop();
        }
        window.onbeforeunload = null;
        window.location.href = decodedURL;
      };
      var val;
      var applyHandler = true;
      var result = setPropertyAccess(window, "ysmm", {
        configurable: false,
        set: function set(value) {
          if (applyHandler) {
            applyHandler = false;
            try {
              if (typeof value === "string") {
                handler(value);
              }
            } catch (err) {}
          }
          val = value;
        },
        get: function get() {
          return val;
        }
      });
      if (result) {
        hit(source);
      } else {
        logMessage(source, "Failed to set up prevent-adfly scriptlet");
      }
    }
    function setPropertyAccess(object, property, descriptor) {
      var currentDescriptor = Object.getOwnPropertyDescriptor(object, property);
      if (currentDescriptor && !currentDescriptor.configurable) {
        return false;
      }
      Object.defineProperty(object, property, descriptor);
      return true;
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventAdfly.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventBab(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventBab(source) {
      var nativeSetTimeout = window.setTimeout;
      var babRegex = /\.bab_elementid.$/;
      var timeoutWrapper = function timeoutWrapper(callback) {
        if (typeof callback !== "string" || !babRegex.test(callback)) {
          for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
            args[_key - 1] = arguments[_key];
          }
          return nativeSetTimeout.apply(window, [callback, ...args]);
        }
        hit(source);
      };
      window.setTimeout = timeoutWrapper;
      var signatures = [["blockadblock"], ["babasbm"], [/getItem\('babn'\)/], ["getElementById", "String.fromCharCode", "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789", "charAt", "DOMContentLoaded", "AdBlock", "addEventListener", "doScroll", "fromCharCode", "<<2|r>>4", "sessionStorage", "clientWidth", "localStorage", "Math", "random"]];
      var check = function check(str) {
        if (typeof str !== "string") {
          return false;
        }
        for (var i = 0; i < signatures.length; i += 1) {
          var tokens = signatures[i];
          var match = 0;
          for (var j = 0; j < tokens.length; j += 1) {
            var token = tokens[j];
            var found = token instanceof RegExp ? token.test(str) : str.includes(token);
            if (found) {
              match += 1;
            }
          }
          if (match / tokens.length >= .8) {
            return true;
          }
        }
        return false;
      };
      var nativeEval = window.eval;
      var evalWrapper = function evalWrapper(str) {
        if (!check(str)) {
          return nativeEval(str);
        }
        hit(source);
        var bodyEl = document.body;
        if (bodyEl) {
          bodyEl.style.removeProperty("visibility");
        }
        var el = document.getElementById("babasbmsgx");
        if (el) {
          el.parentNode.removeChild(el);
        }
      };
      window.eval = evalWrapper.bind(window);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventBab.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventCanvas(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventCanvas(source, contextType) {
      var handlerWrapper = function handlerWrapper(target, thisArg, argumentsList) {
        var type = argumentsList[0];
        var shouldPrevent = false;
        if (!contextType) {
          shouldPrevent = true;
        } else if (isValidMatchStr(contextType)) {
          var {
            isInvertedMatch: isInvertedMatch,
            matchRegexp: matchRegexp
          } = parseMatchArg(contextType);
          shouldPrevent = matchRegexp.test(type) !== isInvertedMatch;
        } else {
          logMessage(source, `Invalid contextType parameter: ${contextType}`);
          shouldPrevent = false;
        }
        if (shouldPrevent) {
          hit(source);
          return null;
        }
        return Reflect.apply(target, thisArg, argumentsList);
      };
      var canvasHandler = {
        apply: handlerWrapper
      };
      window.HTMLCanvasElement.prototype.getContext = new Proxy(window.HTMLCanvasElement.prototype.getContext, canvasHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function parseMatchArg(match) {
      var INVERT_MARKER = "!";
      var isInvertedMatch = match ? match === null || match === void 0 ? void 0 : match.startsWith(INVERT_MARKER) : false;
      var matchValue = isInvertedMatch ? match.slice(1) : match;
      var matchRegexp = toRegExp(matchValue);
      return {
        isInvertedMatch: isInvertedMatch,
        matchRegexp: matchRegexp,
        matchValue: matchValue
      };
    }
    function isValidMatchStr(match) {
      var INVERT_MARKER = "!";
      var str = match;
      if (match !== null && match !== void 0 && match.startsWith(INVERT_MARKER)) {
        str = match.slice(1);
      }
      return isValidStrPattern(str);
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventCanvas.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventElementSrcLoading(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventElementSrcLoading(source, tagName, match) {
      if (typeof Proxy === "undefined" || typeof Reflect === "undefined") {
        return;
      }
      var srcMockData = {
        script: "data:text/javascript;base64,KCk9Pnt9",
        img: "data:image/gif;base64,R0lGODlhAQABAAAAACH5BAEKAAEALAAAAAABAAEAAAICTAEAOw==",
        iframe: "data:text/html;base64, PGRpdj48L2Rpdj4=",
        link: "data:text/plain;base64,"
      };
      var instance;
      if (tagName === "script") {
        instance = HTMLScriptElement;
      } else if (tagName === "img") {
        instance = HTMLImageElement;
      } else if (tagName === "iframe") {
        instance = HTMLIFrameElement;
      } else if (tagName === "link") {
        instance = HTMLLinkElement;
      } else {
        return;
      }
      var hasTrustedTypes = window.trustedTypes && typeof window.trustedTypes.createPolicy === "function";
      var policy;
      if (hasTrustedTypes) {
        policy = window.trustedTypes.createPolicy("AGPolicy", {
          createScriptURL: function createScriptURL(arg) {
            return arg;
          }
        });
      }
      var SOURCE_PROPERTY_NAME = tagName === "link" ? "href" : "src";
      var ONERROR_PROPERTY_NAME = "onerror";
      var searchRegexp = toRegExp(match);
      var setMatchedAttribute = function setMatchedAttribute(elem) {
        return elem.setAttribute(source.name, "matched");
      };
      var setAttributeWrapper = function setAttributeWrapper(target, thisArg, args) {
        if (!args[0] || !args[1]) {
          return Reflect.apply(target, thisArg, args);
        }
        var nodeName = thisArg.nodeName.toLowerCase();
        var attrName = args[0].toLowerCase();
        var attrValue = args[1];
        var isMatched = attrName === SOURCE_PROPERTY_NAME && tagName.toLowerCase() === nodeName && srcMockData[nodeName] && searchRegexp.test(attrValue);
        if (!isMatched) {
          return Reflect.apply(target, thisArg, args);
        }
        hit(source);
        setMatchedAttribute(thisArg);
        return Reflect.apply(target, thisArg, [attrName, srcMockData[nodeName]]);
      };
      var setAttributeHandler = {
        apply: setAttributeWrapper
      };
      instance.prototype.setAttribute = new Proxy(Element.prototype.setAttribute, setAttributeHandler);
      var origSrcDescriptor = safeGetDescriptor(instance.prototype, SOURCE_PROPERTY_NAME);
      if (!origSrcDescriptor) {
        return;
      }
      Object.defineProperty(instance.prototype, SOURCE_PROPERTY_NAME, {
        enumerable: true,
        configurable: true,
        get() {
          return origSrcDescriptor.get.call(this);
        },
        set(urlValue) {
          var nodeName = this.nodeName.toLowerCase();
          var isMatched = tagName.toLowerCase() === nodeName && srcMockData[nodeName] && searchRegexp.test(urlValue);
          if (!isMatched) {
            origSrcDescriptor.set.call(this, urlValue);
            return true;
          }
          if (policy && urlValue instanceof TrustedScriptURL) {
            var trustedSrc = policy.createScriptURL(urlValue);
            origSrcDescriptor.set.call(this, trustedSrc);
            hit(source);
            return;
          }
          setMatchedAttribute(this);
          origSrcDescriptor.set.call(this, srcMockData[nodeName]);
          hit(source);
        }
      });
      var origOnerrorDescriptor = safeGetDescriptor(HTMLElement.prototype, ONERROR_PROPERTY_NAME);
      if (!origOnerrorDescriptor) {
        return;
      }
      Object.defineProperty(HTMLElement.prototype, ONERROR_PROPERTY_NAME, {
        enumerable: true,
        configurable: true,
        get() {
          return origOnerrorDescriptor.get.call(this);
        },
        set(cb) {
          var isMatched = this.getAttribute(source.name) === "matched";
          if (!isMatched) {
            origOnerrorDescriptor.set.call(this, cb);
            return true;
          }
          origOnerrorDescriptor.set.call(this, noopFunc);
          return true;
        }
      });
      var addEventListenerWrapper = function addEventListenerWrapper(target, thisArg, args) {
        if (!args[0] || !args[1] || !thisArg) {
          return Reflect.apply(target, thisArg, args);
        }
        var eventName = args[0];
        var isMatched = typeof thisArg.getAttribute === "function" && thisArg.getAttribute(source.name) === "matched" && eventName === "error";
        if (isMatched) {
          return Reflect.apply(target, thisArg, [eventName, noopFunc]);
        }
        return Reflect.apply(target, thisArg, args);
      };
      var addEventListenerHandler = {
        apply: addEventListenerWrapper
      };
      EventTarget.prototype.addEventListener = new Proxy(EventTarget.prototype.addEventListener, addEventListenerHandler);
      var preventInlineOnerror = function preventInlineOnerror(tagName, src) {
        window.addEventListener("error", function (event) {
          if (!event.target || !event.target.nodeName || event.target.nodeName.toLowerCase() !== tagName || !event.target.src || !src.test(event.target.src)) {
            return;
          }
          hit(source);
          if (typeof event.target.onload === "function") {
            event.target.onerror = event.target.onload;
            return;
          }
          event.target.onerror = noopFunc;
        }, true);
      };
      preventInlineOnerror(tagName, searchRegexp);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function safeGetDescriptor(obj, prop) {
      var descriptor = Object.getOwnPropertyDescriptor(obj, prop);
      if (descriptor && descriptor.configurable) {
        return descriptor;
      }
      return null;
    }
    function noopFunc() {}
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventElementSrcLoading.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventEvalIf(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventEvalIf(source, search) {
      var searchRegexp = toRegExp(search);
      var nativeEval = window.eval;
      window.eval = function (payload) {
        if (!searchRegexp.test(payload.toString())) {
          return nativeEval.call(window, payload);
        }
        hit(source);
        return undefined;
      }.bind(window);
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventEvalIf.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventFab(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventFab(source) {
      hit(source);
      var Fab = function Fab() {};
      Fab.prototype.check = noopFunc;
      Fab.prototype.clearEvent = noopFunc;
      Fab.prototype.emitEvent = noopFunc;
      Fab.prototype.on = function (a, b) {
        if (!a) {
          b();
        }
        return this;
      };
      Fab.prototype.onDetected = noopThis;
      Fab.prototype.onNotDetected = function (a) {
        a();
        return this;
      };
      Fab.prototype.setOption = noopFunc;
      Fab.prototype.options = {
        set: noopFunc,
        get: noopFunc
      };
      var fab = new Fab();
      var getSetFab = {
        get() {
          return Fab;
        },
        set() {}
      };
      var getsetfab = {
        get() {
          return fab;
        },
        set() {}
      };
      if (Object.prototype.hasOwnProperty.call(window, "FuckAdBlock")) {
        window.FuckAdBlock = Fab;
      } else {
        Object.defineProperty(window, "FuckAdBlock", getSetFab);
      }
      if (Object.prototype.hasOwnProperty.call(window, "BlockAdBlock")) {
        window.BlockAdBlock = Fab;
      } else {
        Object.defineProperty(window, "BlockAdBlock", getSetFab);
      }
      if (Object.prototype.hasOwnProperty.call(window, "SniffAdBlock")) {
        window.SniffAdBlock = Fab;
      } else {
        Object.defineProperty(window, "SniffAdBlock", getSetFab);
      }
      if (Object.prototype.hasOwnProperty.call(window, "fuckAdBlock")) {
        window.fuckAdBlock = fab;
      } else {
        Object.defineProperty(window, "fuckAdBlock", getsetfab);
      }
      if (Object.prototype.hasOwnProperty.call(window, "blockAdBlock")) {
        window.blockAdBlock = fab;
      } else {
        Object.defineProperty(window, "blockAdBlock", getsetfab);
      }
      if (Object.prototype.hasOwnProperty.call(window, "sniffAdBlock")) {
        window.sniffAdBlock = fab;
      } else {
        Object.defineProperty(window, "sniffAdBlock", getsetfab);
      }
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    function noopThis() {
      return this;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventFab.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventFetch(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventFetch(source, propsToMatch) {
      var responseBody = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : "emptyObj";
      var responseType = arguments.length > 3 ? arguments[3] : undefined;
      if (typeof fetch === "undefined" || typeof Proxy === "undefined" || typeof Response === "undefined") {
        return;
      }
      var nativeRequestClone = Request.prototype.clone;
      var strResponseBody;
      if (responseBody === "" || responseBody === "emptyObj") {
        strResponseBody = "{}";
      } else if (responseBody === "emptyArr") {
        strResponseBody = "[]";
      } else if (responseBody === "emptyStr") {
        strResponseBody = "";
      } else {
        logMessage(source, `Invalid responseBody parameter: '${responseBody}'`);
        return;
      }
      var isResponseTypeSpecified = typeof responseType !== "undefined";
      var isResponseTypeSupported = function isResponseTypeSupported(responseType) {
        var SUPPORTED_TYPES = ["basic", "cors", "opaque"];
        return SUPPORTED_TYPES.includes(responseType);
      };
      if (isResponseTypeSpecified && !isResponseTypeSupported(responseType)) {
        logMessage(source, `Invalid responseType parameter: '${responseType}'`);
        return;
      }
      var getResponseType = function getResponseType(request) {
        try {
          var {
            mode: mode
          } = request;
          if (mode === undefined || mode === "cors" || mode === "no-cors") {
            var fetchURL = new URL(request.url);
            if (fetchURL.origin === document.location.origin) {
              return "basic";
            }
            return mode === "no-cors" ? "opaque" : "cors";
          }
        } catch (error) {
          logMessage(source, `Could not determine response type: ${error}`);
        }
        return undefined;
      };
      var handlerWrapper = async function handlerWrapper(target, thisArg, args) {
        var shouldPrevent = false;
        var fetchData = getFetchData(args, nativeRequestClone);
        if (typeof propsToMatch === "undefined") {
          logMessage(source, `fetch( ${objectToString(fetchData)} )`, true);
          hit(source);
          return Reflect.apply(target, thisArg, args);
        }
        shouldPrevent = matchRequestProps(source, propsToMatch, fetchData);
        if (shouldPrevent) {
          hit(source);
          var finalResponseType;
          try {
            finalResponseType = responseType || getResponseType(fetchData);
            var origResponse = await Reflect.apply(target, thisArg, args);
            if (!origResponse.ok) {
              return noopPromiseResolve(strResponseBody, fetchData.url, finalResponseType);
            }
            return modifyResponse(origResponse, {
              body: strResponseBody,
              type: finalResponseType
            });
          } catch (ex) {
            return noopPromiseResolve(strResponseBody, fetchData.url, finalResponseType);
          }
        }
        return Reflect.apply(target, thisArg, args);
      };
      var fetchHandler = {
        apply: handlerWrapper
      };
      fetch = new Proxy(fetch, fetchHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function getFetchData(args, nativeRequestClone) {
      var fetchPropsObj = {};
      var resource = args[0];
      var fetchUrl;
      var fetchInit;
      if (resource instanceof Request) {
        var realData = nativeRequestClone.call(resource);
        var requestData = getRequestData(realData);
        fetchUrl = requestData.url;
        fetchInit = requestData;
      } else {
        fetchUrl = resource;
        fetchInit = args[1];
      }
      fetchPropsObj.url = fetchUrl;
      if (fetchInit instanceof Object) {
        var props = Object.keys(fetchInit);
        props.forEach(function (prop) {
          fetchPropsObj[prop] = fetchInit[prop];
        });
      }
      return fetchPropsObj;
    }
    function objectToString(obj) {
      if (!obj || typeof obj !== "object") {
        return String(obj);
      }
      if (isEmptyObject(obj)) {
        return "{}";
      }
      return Object.entries(obj).map(function (pair) {
        var key = pair[0];
        var value = pair[1];
        var recordValueStr = value;
        if (value instanceof Object) {
          recordValueStr = `{ ${objectToString(value)} }`;
        }
        return `${key}:"${recordValueStr}"`;
      }).join(" ");
    }
    function matchRequestProps(source, propsToMatch, requestData) {
      if (propsToMatch === "" || propsToMatch === "*") {
        return true;
      }
      var isMatched;
      var parsedData = parseMatchProps(propsToMatch);
      if (!isValidParsedData(parsedData)) {
        logMessage(source, `Invalid parameter: ${propsToMatch}`);
        isMatched = false;
      } else {
        var matchData = getMatchPropsData(parsedData);
        var matchKeys = Object.keys(matchData);
        isMatched = matchKeys.every(function (matchKey) {
          var matchValue = matchData[matchKey];
          var dataValue = requestData[matchKey];
          return Object.prototype.hasOwnProperty.call(requestData, matchKey) && typeof dataValue === "string" && (matchValue === null || matchValue === void 0 ? void 0 : matchValue.test(dataValue));
        });
      }
      return isMatched;
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function noopPromiseResolve() {
      var responseBody = arguments.length > 0 && arguments[0] !== undefined ? arguments[0] : "{}";
      var responseUrl = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : "";
      var responseType = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : "basic";
      if (typeof Response === "undefined") {
        return;
      }
      var response = new Response(responseBody, {
        status: 200,
        statusText: "OK"
      });
      if (responseType === "opaque") {
        Object.defineProperties(response, {
          body: {
            value: null
          },
          status: {
            value: 0
          },
          ok: {
            value: false
          },
          statusText: {
            value: ""
          },
          url: {
            value: ""
          },
          type: {
            value: responseType
          }
        });
      } else {
        Object.defineProperties(response, {
          url: {
            value: responseUrl
          },
          type: {
            value: responseType
          }
        });
      }
      return Promise.resolve(response);
    }
    function modifyResponse(origResponse) {
      var _origResponse$headers;
      var replacement = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : {
        body: "{}"
      };
      var headers = {};
      origResponse === null || origResponse === void 0 || (_origResponse$headers = origResponse.headers) === null || _origResponse$headers === void 0 || _origResponse$headers.forEach(function (value, key) {
        headers[key] = value;
      });
      var modifiedResponse = new Response(replacement.body, {
        status: origResponse.status,
        statusText: origResponse.statusText,
        headers: headers
      });
      Object.defineProperties(modifiedResponse, {
        url: {
          value: origResponse.url
        },
        type: {
          value: replacement.type || origResponse.type
        }
      });
      return modifiedResponse;
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    function getRequestData(request) {
      var requestInitOptions = getRequestProps();
      var entries = requestInitOptions.map(function (key) {
        var value = request[key];
        return [key, value];
      });
      return Object.fromEntries(entries);
    }
    function getRequestProps() {
      return ["url", "method", "headers", "body", "credentials", "cache", "redirect", "referrer", "referrerPolicy", "integrity", "keepalive", "signal", "mode"];
    }
    function parseMatchProps(propsToMatchStr) {
      var PROPS_DIVIDER = " ";
      var PAIRS_MARKER = ":";
      var isRequestProp = function isRequestProp(prop) {
        return getRequestProps().includes(prop);
      };
      var propsObj = {};
      var props = propsToMatchStr.split(PROPS_DIVIDER);
      props.forEach(function (prop) {
        var dividerInd = prop.indexOf(PAIRS_MARKER);
        var key = prop.slice(0, dividerInd);
        if (isRequestProp(key)) {
          var value = prop.slice(dividerInd + 1);
          propsObj[key] = value;
        } else {
          propsObj.url = prop;
        }
      });
      return propsObj;
    }
    function isValidParsedData(data) {
      return Object.values(data).every(function (value) {
        return isValidStrPattern(value);
      });
    }
    function getMatchPropsData(data) {
      var matchData = {};
      var dataKeys = Object.keys(data);
      dataKeys.forEach(function (key) {
        matchData[key] = toRegExp(data[key]);
      });
      return matchData;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventFetch.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventPopadsNet(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventPopadsNet(source) {
      var rid = randomId();
      var throwError = function throwError() {
        throw new ReferenceError(rid);
      };
      delete window.PopAds;
      delete window.popns;
      Object.defineProperties(window, {
        PopAds: {
          set: throwError
        },
        popns: {
          set: throwError
        }
      });
      window.onerror = createOnErrorHandler(rid).bind();
      hit(source);
    }
    function createOnErrorHandler(rid) {
      var nativeOnError = window.onerror;
      return function onError(error) {
        if (typeof error === "string" && error.includes(rid)) {
          return true;
        }
        if (nativeOnError instanceof Function) {
          for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
            args[_key - 1] = arguments[_key];
          }
          return nativeOnError.apply(window, [error, ...args]);
        }
        return false;
      };
    }
    function randomId() {
      return Math.random().toString(36).slice(2, 9);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventPopadsNet.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventRefresh(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventRefresh(source, delaySec) {
      var getMetaElements = function getMetaElements() {
        var metaNodes = [];
        try {
          metaNodes = document.querySelectorAll('meta[http-equiv="refresh" i][content]');
        } catch (e) {
          try {
            metaNodes = document.querySelectorAll('meta[http-equiv="refresh"][content]');
          } catch (e) {
            logMessage(source, e);
          }
        }
        return Array.from(metaNodes);
      };
      var getMetaContentDelay = function getMetaContentDelay(metaElements) {
        var delays = metaElements.map(function (meta) {
          var contentString = meta.getAttribute("content");
          if (contentString.length === 0) {
            return null;
          }
          var contentDelay;
          var limiterIndex = contentString.indexOf(";");
          if (limiterIndex !== -1) {
            var delaySubstring = contentString.substring(0, limiterIndex);
            contentDelay = getNumberFromString(delaySubstring);
          } else {
            contentDelay = getNumberFromString(contentString);
          }
          return contentDelay;
        }).filter(function (delay) {
          return delay !== null;
        });
        if (!delays.length) {
          return null;
        }
        var minDelay = delays.reduce(function (a, b) {
          return Math.min(a, b);
        });
        return minDelay;
      };
      var stop = function stop() {
        var metaElements = getMetaElements();
        if (metaElements.length === 0) {
          return;
        }
        var secondsToRun = getNumberFromString(delaySec);
        if (secondsToRun === null) {
          secondsToRun = getMetaContentDelay(metaElements);
        }
        if (secondsToRun === null) {
          return;
        }
        var delayMs = secondsToRun * 1e3;
        setTimeout(function () {
          window.stop();
          hit(source);
        }, delayMs);
      };
      if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", stop, {
          once: true
        });
      } else {
        stop();
      }
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function getNumberFromString(rawString) {
      var parsedDelay = parseInt(rawString, 10);
      var validDelay = nativeIsNaN(parsedDelay) ? null : parsedDelay;
      return validDelay;
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventRefresh.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventRequestAnimationFrame(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventRequestAnimationFrame(source, match) {
      var nativeRequestAnimationFrame = window.requestAnimationFrame;
      var shouldLog = typeof match === "undefined";
      var {
        isInvertedMatch: isInvertedMatch,
        matchRegexp: matchRegexp
      } = parseMatchArg(match);
      var rafWrapper = function rafWrapper(callback) {
        var shouldPrevent = false;
        if (shouldLog) {
          hit(source);
          logMessage(source, `requestAnimationFrame(${String(callback)})`, true);
        } else if (isValidCallback(callback) && isValidStrPattern(match)) {
          shouldPrevent = matchRegexp.test(callback.toString()) !== isInvertedMatch;
        }
        if (shouldPrevent) {
          hit(source);
          return nativeRequestAnimationFrame(noopFunc);
        }
        for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
          args[_key - 1] = arguments[_key];
        }
        return nativeRequestAnimationFrame.apply(window, [callback, ...args]);
      };
      window.requestAnimationFrame = rafWrapper;
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    function parseMatchArg(match) {
      var INVERT_MARKER = "!";
      var isInvertedMatch = match ? match === null || match === void 0 ? void 0 : match.startsWith(INVERT_MARKER) : false;
      var matchValue = isInvertedMatch ? match.slice(1) : match;
      var matchRegexp = toRegExp(matchValue);
      return {
        isInvertedMatch: isInvertedMatch,
        matchRegexp: matchRegexp,
        matchValue: matchValue
      };
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function isValidCallback(callback) {
      return callback instanceof Function || typeof callback === "string";
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventRequestAnimationFrame.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventSetInterval(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventSetInterval(source, matchCallback, matchDelay) {
      var shouldLog = typeof matchCallback === "undefined" && typeof matchDelay === "undefined";
      var handlerWrapper = function handlerWrapper(target, thisArg, args) {
        var callback = args[0];
        var delay = args[1];
        var shouldPrevent = false;
        if (shouldLog) {
          hit(source);
          logMessage(source, `setInterval(${String(callback)}, ${delay})`, true);
        } else {
          shouldPrevent = isPreventionNeeded({
            callback: callback,
            delay: delay,
            matchCallback: matchCallback,
            matchDelay: matchDelay
          });
        }
        if (shouldPrevent) {
          hit(source);
          args[0] = noopFunc;
        }
        return target.apply(thisArg, args);
      };
      var setIntervalHandler = {
        apply: handlerWrapper
      };
      window.setInterval = new Proxy(window.setInterval, setIntervalHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    function isPreventionNeeded(_ref) {
      var {
        callback: callback,
        delay: delay,
        matchCallback: matchCallback,
        matchDelay: matchDelay
      } = _ref;
      if (!isValidCallback(callback)) {
        return false;
      }
      if (!isValidMatchStr(matchCallback) || matchDelay && !isValidMatchNumber(matchDelay)) {
        return false;
      }
      var {
        isInvertedMatch: isInvertedMatch,
        matchRegexp: matchRegexp
      } = parseMatchArg(matchCallback);
      var {
        isInvertedDelayMatch: isInvertedDelayMatch,
        delayMatch: delayMatch
      } = parseDelayArg(matchDelay);
      var parsedDelay = parseRawDelay(delay);
      var shouldPrevent = false;
      var callbackStr = String(callback);
      if (delayMatch === null) {
        shouldPrevent = matchRegexp.test(callbackStr) !== isInvertedMatch;
      } else if (!matchCallback) {
        shouldPrevent = parsedDelay === delayMatch !== isInvertedDelayMatch;
      } else {
        shouldPrevent = matchRegexp.test(callbackStr) !== isInvertedMatch && parsedDelay === delayMatch !== isInvertedDelayMatch;
      }
      return shouldPrevent;
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function parseMatchArg(match) {
      var INVERT_MARKER = "!";
      var isInvertedMatch = match ? match === null || match === void 0 ? void 0 : match.startsWith(INVERT_MARKER) : false;
      var matchValue = isInvertedMatch ? match.slice(1) : match;
      var matchRegexp = toRegExp(matchValue);
      return {
        isInvertedMatch: isInvertedMatch,
        matchRegexp: matchRegexp,
        matchValue: matchValue
      };
    }
    function parseDelayArg(delay) {
      var INVERT_MARKER = "!";
      var isInvertedDelayMatch = delay === null || delay === void 0 ? void 0 : delay.startsWith(INVERT_MARKER);
      var delayValue = isInvertedDelayMatch ? delay.slice(1) : delay;
      var parsedDelay = parseInt(delayValue, 10);
      var delayMatch = nativeIsNaN(parsedDelay) ? null : parsedDelay;
      return {
        isInvertedDelayMatch: isInvertedDelayMatch,
        delayMatch: delayMatch
      };
    }
    function isValidCallback(callback) {
      return callback instanceof Function || typeof callback === "string";
    }
    function isValidMatchStr(match) {
      var INVERT_MARKER = "!";
      var str = match;
      if (match !== null && match !== void 0 && match.startsWith(INVERT_MARKER)) {
        str = match.slice(1);
      }
      return isValidStrPattern(str);
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    function nativeIsFinite(num) {
      var native = Number.isFinite || window.isFinite;
      return native(num);
    }
    function isValidMatchNumber(match) {
      var INVERT_MARKER = "!";
      var str = match;
      if (match !== null && match !== void 0 && match.startsWith(INVERT_MARKER)) {
        str = match.slice(1);
      }
      var num = parseFloat(str);
      return !nativeIsNaN(num) && nativeIsFinite(num);
    }
    function parseRawDelay(delay) {
      var parsedDelay = Math.floor(parseInt(delay, 10));
      return typeof parsedDelay === "number" && !nativeIsNaN(parsedDelay) ? parsedDelay : delay;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventSetInterval.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventSetTimeout(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventSetTimeout(source, matchCallback, matchDelay) {
      var shouldLog = typeof matchCallback === "undefined" && typeof matchDelay === "undefined";
      var handlerWrapper = function handlerWrapper(target, thisArg, args) {
        var callback = args[0];
        var delay = args[1];
        var shouldPrevent = false;
        if (shouldLog) {
          hit(source);
          logMessage(source, `setTimeout(${String(callback)}, ${delay})`, true);
        } else {
          shouldPrevent = isPreventionNeeded({
            callback: callback,
            delay: delay,
            matchCallback: matchCallback,
            matchDelay: matchDelay
          });
        }
        if (shouldPrevent) {
          hit(source);
          args[0] = noopFunc;
        }
        return target.apply(thisArg, args);
      };
      var setTimeoutHandler = {
        apply: handlerWrapper
      };
      window.setTimeout = new Proxy(window.setTimeout, setTimeoutHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function noopFunc() {}
    function isPreventionNeeded(_ref) {
      var {
        callback: callback,
        delay: delay,
        matchCallback: matchCallback,
        matchDelay: matchDelay
      } = _ref;
      if (!isValidCallback(callback)) {
        return false;
      }
      if (!isValidMatchStr(matchCallback) || matchDelay && !isValidMatchNumber(matchDelay)) {
        return false;
      }
      var {
        isInvertedMatch: isInvertedMatch,
        matchRegexp: matchRegexp
      } = parseMatchArg(matchCallback);
      var {
        isInvertedDelayMatch: isInvertedDelayMatch,
        delayMatch: delayMatch
      } = parseDelayArg(matchDelay);
      var parsedDelay = parseRawDelay(delay);
      var shouldPrevent = false;
      var callbackStr = String(callback);
      if (delayMatch === null) {
        shouldPrevent = matchRegexp.test(callbackStr) !== isInvertedMatch;
      } else if (!matchCallback) {
        shouldPrevent = parsedDelay === delayMatch !== isInvertedDelayMatch;
      } else {
        shouldPrevent = matchRegexp.test(callbackStr) !== isInvertedMatch && parsedDelay === delayMatch !== isInvertedDelayMatch;
      }
      return shouldPrevent;
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function parseMatchArg(match) {
      var INVERT_MARKER = "!";
      var isInvertedMatch = match ? match === null || match === void 0 ? void 0 : match.startsWith(INVERT_MARKER) : false;
      var matchValue = isInvertedMatch ? match.slice(1) : match;
      var matchRegexp = toRegExp(matchValue);
      return {
        isInvertedMatch: isInvertedMatch,
        matchRegexp: matchRegexp,
        matchValue: matchValue
      };
    }
    function parseDelayArg(delay) {
      var INVERT_MARKER = "!";
      var isInvertedDelayMatch = delay === null || delay === void 0 ? void 0 : delay.startsWith(INVERT_MARKER);
      var delayValue = isInvertedDelayMatch ? delay.slice(1) : delay;
      var parsedDelay = parseInt(delayValue, 10);
      var delayMatch = nativeIsNaN(parsedDelay) ? null : parsedDelay;
      return {
        isInvertedDelayMatch: isInvertedDelayMatch,
        delayMatch: delayMatch
      };
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function isValidCallback(callback) {
      return callback instanceof Function || typeof callback === "string";
    }
    function isValidMatchStr(match) {
      var INVERT_MARKER = "!";
      var str = match;
      if (match !== null && match !== void 0 && match.startsWith(INVERT_MARKER)) {
        str = match.slice(1);
      }
      return isValidStrPattern(str);
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function nativeIsFinite(num) {
      var native = Number.isFinite || window.isFinite;
      return native(num);
    }
    function isValidMatchNumber(match) {
      var INVERT_MARKER = "!";
      var str = match;
      if (match !== null && match !== void 0 && match.startsWith(INVERT_MARKER)) {
        str = match.slice(1);
      }
      var num = parseFloat(str);
      return !nativeIsNaN(num) && nativeIsFinite(num);
    }
    function parseRawDelay(delay) {
      var parsedDelay = Math.floor(parseInt(delay, 10));
      return typeof parsedDelay === "number" && !nativeIsNaN(parsedDelay) ? parsedDelay : delay;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventSetTimeout.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventWindowOpen(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventWindowOpen(source) {
      var match = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : "*";
      var delay = arguments.length > 2 ? arguments[2] : undefined;
      var replacement = arguments.length > 3 ? arguments[3] : undefined;
      var nativeOpen = window.open;
      var isNewSyntax = match !== "0" && match !== "1";
      var oldOpenWrapper = function oldOpenWrapper(str) {
        match = Number(match) > 0;
        for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
          args[_key - 1] = arguments[_key];
        }
        if (!isValidStrPattern(delay)) {
          logMessage(source, `Invalid parameter: ${delay}`);
          return nativeOpen.apply(window, [str, ...args]);
        }
        var searchRegexp = toRegExp(delay);
        if (match !== searchRegexp.test(str)) {
          return nativeOpen.apply(window, [str, ...args]);
        }
        hit(source);
        return handleOldReplacement(replacement);
      };
      var newOpenWrapper = function newOpenWrapper(url) {
        var shouldLog = replacement && replacement.includes("log");
        for (var _len2 = arguments.length, args = new Array(_len2 > 1 ? _len2 - 1 : 0), _key2 = 1; _key2 < _len2; _key2++) {
          args[_key2 - 1] = arguments[_key2];
        }
        if (shouldLog) {
          var argsStr = args && args.length > 0 ? `, ${args.join(", ")}` : "";
          var message = `${url}${argsStr}`;
          logMessage(source, message, true);
          hit(source);
        }
        var shouldPrevent = false;
        if (match === "*") {
          shouldPrevent = true;
        } else if (isValidMatchStr(match)) {
          var {
            isInvertedMatch: isInvertedMatch,
            matchRegexp: matchRegexp
          } = parseMatchArg(match);
          shouldPrevent = matchRegexp.test(url) !== isInvertedMatch;
        } else {
          logMessage(source, `Invalid parameter: ${match}`);
          shouldPrevent = false;
        }
        if (shouldPrevent) {
          var parsedDelay = parseInt(delay, 10);
          var result;
          if (nativeIsNaN(parsedDelay)) {
            result = noopNull();
          } else {
            var decoyArgs = {
              replacement: replacement,
              url: url,
              delay: parsedDelay
            };
            var decoy = createDecoy(decoyArgs);
            var popup = decoy.contentWindow;
            if (typeof popup === "object" && popup !== null) {
              Object.defineProperty(popup, "closed", {
                value: false
              });
              Object.defineProperty(popup, "opener", {
                value: window
              });
              Object.defineProperty(popup, "frameElement", {
                value: null
              });
            } else {
              var nativeGetter = decoy.contentWindow && decoy.contentWindow.get;
              Object.defineProperty(decoy, "contentWindow", {
                get: getPreventGetter(nativeGetter)
              });
              popup = decoy.contentWindow;
            }
            result = popup;
          }
          hit(source);
          return result;
        }
        return nativeOpen.apply(window, [url, ...args]);
      };
      window.open = isNewSyntax ? newOpenWrapper : oldOpenWrapper;
      window.open.toString = nativeOpen.toString.bind(nativeOpen);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    function isValidMatchStr(match) {
      var INVERT_MARKER = "!";
      var str = match;
      if (match !== null && match !== void 0 && match.startsWith(INVERT_MARKER)) {
        str = match.slice(1);
      }
      return isValidStrPattern(str);
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function parseMatchArg(match) {
      var INVERT_MARKER = "!";
      var isInvertedMatch = match ? match === null || match === void 0 ? void 0 : match.startsWith(INVERT_MARKER) : false;
      var matchValue = isInvertedMatch ? match.slice(1) : match;
      var matchRegexp = toRegExp(matchValue);
      return {
        isInvertedMatch: isInvertedMatch,
        matchRegexp: matchRegexp,
        matchValue: matchValue
      };
    }
    function handleOldReplacement(replacement) {
      var result;
      if (!replacement) {
        result = noopFunc;
      } else if (replacement === "trueFunc") {
        result = trueFunc;
      } else if (replacement.includes("=")) {
        var isProp = replacement.startsWith("{") && replacement.endsWith("}");
        if (isProp) {
          var propertyPart = replacement.slice(1, -1);
          var propertyName = substringBefore(propertyPart, "=");
          var propertyValue = substringAfter(propertyPart, "=");
          if (propertyValue === "noopFunc") {
            result = {};
            result[propertyName] = noopFunc;
          }
        }
      }
      return result;
    }
    function createDecoy(args) {
      var UrlPropNameOf = function (UrlPropNameOf) {
        UrlPropNameOf["Object"] = "data";
        UrlPropNameOf["Iframe"] = "src";
        return UrlPropNameOf;
      }({});
      var {
        replacement: replacement,
        url: url,
        delay: delay
      } = args;
      var tag;
      if (replacement === "obj") {
        tag = "object";
      } else {
        tag = "iframe";
      }
      var decoy = document.createElement(tag);
      if (decoy instanceof HTMLObjectElement) {
        decoy[UrlPropNameOf.Object] = url;
      } else if (decoy instanceof HTMLIFrameElement) {
        decoy[UrlPropNameOf.Iframe] = url;
      }
      decoy.style.setProperty("height", "1px", "important");
      decoy.style.setProperty("position", "fixed", "important");
      decoy.style.setProperty("top", "-1px", "important");
      decoy.style.setProperty("width", "1px", "important");
      document.body.appendChild(decoy);
      setTimeout(function () {
        return decoy.remove();
      }, delay * 1e3);
      return decoy;
    }
    function getPreventGetter(nativeGetter) {
      var preventGetter = function preventGetter(target, prop) {
        if (prop && prop === "closed") {
          return false;
        }
        if (typeof nativeGetter === "function") {
          return noopFunc;
        }
        return prop && target[prop];
      };
      return preventGetter;
    }
    function noopNull() {
      return null;
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function noopFunc() {}
    function trueFunc() {
      return true;
    }
    function substringBefore(str, separator) {
      if (!str || !separator) {
        return str;
      }
      var index = str.indexOf(separator);
      return index < 0 ? str : str.substring(0, index);
    }
    function substringAfter(str, separator) {
      if (!str) {
        return str;
      }
      var index = str.indexOf(separator);
      return index < 0 ? "" : str.substring(index + separator.length);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventWindowOpen.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function preventXHR(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function preventXHR(source, propsToMatch, customResponseText) {
      if (typeof Proxy === "undefined") {
        return;
      }
      var nativeOpen = window.XMLHttpRequest.prototype.open;
      var nativeGetResponseHeader = window.XMLHttpRequest.prototype.getResponseHeader;
      var nativeGetAllResponseHeaders = window.XMLHttpRequest.prototype.getAllResponseHeaders;
      var xhrData;
      var modifiedResponse = "";
      var modifiedResponseText = "";
      var openWrapper = function openWrapper(target, thisArg, args) {
        xhrData = getXhrData.apply(null, args);
        if (typeof propsToMatch === "undefined") {
          logMessage(source, `xhr( ${objectToString(xhrData)} )`, true);
          hit(source);
        } else if (matchRequestProps(source, propsToMatch, xhrData)) {
          thisArg.shouldBePrevented = true;
          thisArg.xhrData = xhrData;
        }
        if (thisArg.shouldBePrevented) {
          thisArg.collectedHeaders = [];
          var setRequestHeaderWrapper = function setRequestHeaderWrapper(target, thisArg, args) {
            thisArg.collectedHeaders.push(args);
            return Reflect.apply(target, thisArg, args);
          };
          var setRequestHeaderHandler = {
            apply: setRequestHeaderWrapper
          };
          thisArg.setRequestHeader = new Proxy(thisArg.setRequestHeader, setRequestHeaderHandler);
        }
        return Reflect.apply(target, thisArg, args);
      };
      var sendWrapper = function sendWrapper(target, thisArg, args) {
        if (!thisArg.shouldBePrevented) {
          return Reflect.apply(target, thisArg, args);
        }
        if (thisArg.responseType === "blob") {
          modifiedResponse = new Blob();
        }
        if (thisArg.responseType === "arraybuffer") {
          modifiedResponse = new ArrayBuffer();
        }
        if (customResponseText) {
          var randomText = generateRandomResponse(customResponseText);
          if (randomText) {
            modifiedResponse = randomText;
            modifiedResponseText = randomText;
          } else {
            logMessage(source, `Invalid randomize parameter: '${customResponseText}'`);
          }
        }
        var forgedRequest = new XMLHttpRequest();
        var transitionReadyState = function transitionReadyState(state) {
          if (state === 4) {
            var {
              responseURL: responseURL,
              responseXML: responseXML
            } = forgedRequest;
            Object.defineProperties(thisArg, {
              readyState: {
                value: 4,
                writable: false
              },
              statusText: {
                value: "OK",
                writable: false
              },
              responseURL: {
                value: responseURL || thisArg.xhrData.url,
                writable: false
              },
              responseXML: {
                value: responseXML,
                writable: false
              },
              status: {
                value: 200,
                writable: false
              },
              response: {
                value: modifiedResponse,
                writable: false
              },
              responseText: {
                value: modifiedResponseText,
                writable: false
              }
            });
            hit(source);
          } else {
            Object.defineProperty(thisArg, "readyState", {
              value: state,
              writable: true,
              configurable: true
            });
          }
          var stateEvent = new Event("readystatechange");
          thisArg.dispatchEvent(stateEvent);
        };
        forgedRequest.addEventListener("readystatechange", function () {
          transitionReadyState(1);
          var loadStartEvent = new ProgressEvent("loadstart");
          thisArg.dispatchEvent(loadStartEvent);
          transitionReadyState(2);
          transitionReadyState(3);
          var progressEvent = new ProgressEvent("progress");
          thisArg.dispatchEvent(progressEvent);
          transitionReadyState(4);
        });
        setTimeout(function () {
          var loadEvent = new ProgressEvent("load");
          thisArg.dispatchEvent(loadEvent);
          var loadEndEvent = new ProgressEvent("loadend");
          thisArg.dispatchEvent(loadEndEvent);
        }, 1);
        nativeOpen.apply(forgedRequest, [thisArg.xhrData.method, thisArg.xhrData.url]);
        thisArg.collectedHeaders.forEach(function (header) {
          var name = header[0];
          var value = header[1];
          forgedRequest.setRequestHeader(name, value);
        });
        return undefined;
      };
      var getHeaderWrapper = function getHeaderWrapper(target, thisArg, args) {
        if (!thisArg.shouldBePrevented) {
          return nativeGetResponseHeader.apply(thisArg, args);
        }
        if (!thisArg.collectedHeaders.length) {
          return null;
        }
        var searchHeaderName = args[0].toLowerCase();
        var matchedHeader = thisArg.collectedHeaders.find(function (header) {
          var headerName = header[0].toLowerCase();
          return headerName === searchHeaderName;
        });
        return matchedHeader ? matchedHeader[1] : null;
      };
      var getAllHeadersWrapper = function getAllHeadersWrapper(target, thisArg) {
        if (!thisArg.shouldBePrevented) {
          return nativeGetAllResponseHeaders.call(thisArg);
        }
        if (!thisArg.collectedHeaders.length) {
          return "";
        }
        var allHeadersStr = thisArg.collectedHeaders.map(function (header) {
          var headerName = header[0];
          var headerValue = header[1];
          return `${headerName.toLowerCase()}: ${headerValue}`;
        }).join("\r\n");
        return allHeadersStr;
      };
      var openHandler = {
        apply: openWrapper
      };
      var sendHandler = {
        apply: sendWrapper
      };
      var getHeaderHandler = {
        apply: getHeaderWrapper
      };
      var getAllHeadersHandler = {
        apply: getAllHeadersWrapper
      };
      XMLHttpRequest.prototype.open = new Proxy(XMLHttpRequest.prototype.open, openHandler);
      XMLHttpRequest.prototype.send = new Proxy(XMLHttpRequest.prototype.send, sendHandler);
      XMLHttpRequest.prototype.getResponseHeader = new Proxy(XMLHttpRequest.prototype.getResponseHeader, getHeaderHandler);
      XMLHttpRequest.prototype.getAllResponseHeaders = new Proxy(XMLHttpRequest.prototype.getAllResponseHeaders, getAllHeadersHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function objectToString(obj) {
      if (!obj || typeof obj !== "object") {
        return String(obj);
      }
      if (isEmptyObject(obj)) {
        return "{}";
      }
      return Object.entries(obj).map(function (pair) {
        var key = pair[0];
        var value = pair[1];
        var recordValueStr = value;
        if (value instanceof Object) {
          recordValueStr = `{ ${objectToString(value)} }`;
        }
        return `${key}:"${recordValueStr}"`;
      }).join(" ");
    }
    function generateRandomResponse(customResponseText) {
      var customResponse = customResponseText;
      if (customResponse === "true") {
        customResponse = Math.random().toString(36).slice(-10);
        return customResponse;
      }
      customResponse = customResponse.replace("length:", "");
      var rangeRegex = /^\d+-\d+$/;
      if (!rangeRegex.test(customResponse)) {
        return null;
      }
      var rangeMin = getNumberFromString(customResponse.split("-")[0]);
      var rangeMax = getNumberFromString(customResponse.split("-")[1]);
      if (!nativeIsFinite(rangeMin) || !nativeIsFinite(rangeMax)) {
        return null;
      }
      if (rangeMin > rangeMax) {
        var temp = rangeMin;
        rangeMin = rangeMax;
        rangeMax = temp;
      }
      var LENGTH_RANGE_LIMIT = 500 * 1e3;
      if (rangeMax > LENGTH_RANGE_LIMIT) {
        return null;
      }
      var length = getRandomIntInclusive(rangeMin, rangeMax);
      customResponse = getRandomStrByLength(length);
      return customResponse;
    }
    function matchRequestProps(source, propsToMatch, requestData) {
      if (propsToMatch === "" || propsToMatch === "*") {
        return true;
      }
      var isMatched;
      var parsedData = parseMatchProps(propsToMatch);
      if (!isValidParsedData(parsedData)) {
        logMessage(source, `Invalid parameter: ${propsToMatch}`);
        isMatched = false;
      } else {
        var matchData = getMatchPropsData(parsedData);
        var matchKeys = Object.keys(matchData);
        isMatched = matchKeys.every(function (matchKey) {
          var matchValue = matchData[matchKey];
          var dataValue = requestData[matchKey];
          return Object.prototype.hasOwnProperty.call(requestData, matchKey) && typeof dataValue === "string" && (matchValue === null || matchValue === void 0 ? void 0 : matchValue.test(dataValue));
        });
      }
      return isMatched;
    }
    function getXhrData(method, url, async, user, password) {
      return {
        method: method,
        url: url,
        async: async,
        user: user,
        password: password
      };
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    function getNumberFromString(rawString) {
      var parsedDelay = parseInt(rawString, 10);
      var validDelay = nativeIsNaN(parsedDelay) ? null : parsedDelay;
      return validDelay;
    }
    function nativeIsFinite(num) {
      var native = Number.isFinite || window.isFinite;
      return native(num);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function parseMatchProps(propsToMatchStr) {
      var PROPS_DIVIDER = " ";
      var PAIRS_MARKER = ":";
      var isRequestProp = function isRequestProp(prop) {
        return getRequestProps().includes(prop);
      };
      var propsObj = {};
      var props = propsToMatchStr.split(PROPS_DIVIDER);
      props.forEach(function (prop) {
        var dividerInd = prop.indexOf(PAIRS_MARKER);
        var key = prop.slice(0, dividerInd);
        if (isRequestProp(key)) {
          var value = prop.slice(dividerInd + 1);
          propsObj[key] = value;
        } else {
          propsObj.url = prop;
        }
      });
      return propsObj;
    }
    function isValidParsedData(data) {
      return Object.values(data).every(function (value) {
        return isValidStrPattern(value);
      });
    }
    function getMatchPropsData(data) {
      var matchData = {};
      var dataKeys = Object.keys(data);
      dataKeys.forEach(function (key) {
        matchData[key] = toRegExp(data[key]);
      });
      return matchData;
    }
    function getRequestProps() {
      return ["url", "method", "headers", "body", "credentials", "cache", "redirect", "referrer", "referrerPolicy", "integrity", "keepalive", "signal", "mode"];
    }
    function getRandomIntInclusive(min, max) {
      min = Math.ceil(min);
      max = Math.floor(max);
      return Math.floor(Math.random() * (max - min + 1) + min);
    }
    function getRandomStrByLength(length) {
      var result = "";
      var characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()_+=~";
      var charactersLength = characters.length;
      for (var i = 0; i < length; i += 1) {
        result += characters.charAt(Math.floor(Math.random() * charactersLength));
      }
      return result;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      preventXHR.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function removeAttr(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function removeAttr(source, attrs, selector) {
      var applying = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "asap stay";
      if (!attrs) {
        return;
      }
      attrs = attrs.split(/\s*\|\s*/);
      if (!selector) {
        selector = `[${attrs.join("],[")}]`;
      }
      var rmattr = function rmattr() {
        var nodes = [];
        try {
          nodes = [].slice.call(document.querySelectorAll(selector));
        } catch (e) {
          logMessage(source, `Invalid selector arg: '${selector}'`);
        }
        var removed = false;
        nodes.forEach(function (node) {
          attrs.forEach(function (attr) {
            node.removeAttribute(attr);
            removed = true;
          });
        });
        if (removed) {
          hit(source);
        }
      };
      var flags = parseFlags(applying);
      var run = function run() {
        rmattr();
        if (!flags.hasFlag(flags.STAY)) {
          return;
        }
        observeDOMChanges(rmattr, true);
      };
      if (flags.hasFlag(flags.ASAP)) {
        if (document.readyState === "loading") {
          window.addEventListener("DOMContentLoaded", rmattr, {
            once: true
          });
        } else {
          rmattr();
        }
      }
      if (document.readyState !== "complete" && flags.hasFlag(flags.COMPLETE)) {
        window.addEventListener("load", run, {
          once: true
        });
      } else if (flags.hasFlag(flags.STAY)) {
        if (!applying.includes(" ")) {
          rmattr();
        }
        observeDOMChanges(rmattr, true);
      }
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function observeDOMChanges(callback) {
      var observeAttrs = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : false;
      var attrsToObserve = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : [];
      var THROTTLE_DELAY_MS = 20;
      var observer = new MutationObserver(throttle(callbackWrapper, THROTTLE_DELAY_MS));
      var connect = function connect() {
        if (attrsToObserve.length > 0) {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs,
            attributeFilter: attrsToObserve
          });
        } else {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs
          });
        }
      };
      var disconnect = function disconnect() {
        observer.disconnect();
      };
      function callbackWrapper() {
        disconnect();
        callback();
        connect();
      }
      connect();
    }
    function parseFlags(flags) {
      var FLAGS_DIVIDER = " ";
      var ASAP_FLAG = "asap";
      var COMPLETE_FLAG = "complete";
      var STAY_FLAG = "stay";
      var VALID_FLAGS = new Set([ASAP_FLAG, COMPLETE_FLAG, STAY_FLAG]);
      var passedFlags = new Set(flags.trim().split(FLAGS_DIVIDER).filter(function (flag) {
        return VALID_FLAGS.has(flag);
      }));
      return {
        ASAP: ASAP_FLAG,
        COMPLETE: COMPLETE_FLAG,
        STAY: STAY_FLAG,
        hasFlag: function hasFlag(flag) {
          return passedFlags.has(flag);
        }
      };
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function throttle(cb, delay) {
      var wait = false;
      var savedArgs;
      var _wrapper = function wrapper() {
        for (var _len = arguments.length, args = new Array(_len), _key = 0; _key < _len; _key++) {
          args[_key] = arguments[_key];
        }
        if (wait) {
          savedArgs = args;
          return;
        }
        cb(...args);
        wait = true;
        setTimeout(function () {
          wait = false;
          if (savedArgs) {
            _wrapper(...savedArgs);
            savedArgs = null;
          }
        }, delay);
      };
      return _wrapper;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      removeAttr.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function removeClass(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function removeClass(source, classNames, selector) {
      var applying = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "asap stay";
      if (!classNames) {
        return;
      }
      classNames = classNames.split(/\s*\|\s*/);
      var selectors = [];
      if (!selector) {
        selectors = classNames.map(function (className) {
          return `.${className}`;
        });
      }
      var removeClassHandler = function removeClassHandler() {
        var nodes = new Set();
        if (selector) {
          var foundNodes = [];
          try {
            foundNodes = [].slice.call(document.querySelectorAll(selector));
          } catch (e) {
            logMessage(source, `Invalid selector arg: '${selector}'`);
          }
          foundNodes.forEach(function (n) {
            return nodes.add(n);
          });
        } else if (selectors.length > 0) {
          selectors.forEach(function (s) {
            var elements = document.querySelectorAll(s);
            for (var i = 0; i < elements.length; i += 1) {
              var element = elements[i];
              nodes.add(element);
            }
          });
        }
        var removed = false;
        nodes.forEach(function (node) {
          classNames.forEach(function (className) {
            if (node.classList.contains(className)) {
              node.classList.remove(className);
              removed = true;
            }
          });
        });
        if (removed) {
          hit(source);
        }
      };
      var CLASS_ATTR_NAME = ["class"];
      var flags = parseFlags(applying);
      var run = function run() {
        removeClassHandler();
        if (!flags.hasFlag(flags.STAY)) {
          return;
        }
        observeDOMChanges(removeClassHandler, true, CLASS_ATTR_NAME);
      };
      if (flags.hasFlag(flags.ASAP)) {
        if (document.readyState === "loading") {
          window.addEventListener("DOMContentLoaded", removeClassHandler, {
            once: true
          });
        } else {
          removeClassHandler();
        }
      }
      if (document.readyState !== "complete" && flags.hasFlag(flags.COMPLETE)) {
        window.addEventListener("load", run, {
          once: true
        });
      } else if (flags.hasFlag(flags.STAY)) {
        if (!applying.includes(" ")) {
          removeClassHandler();
        }
        observeDOMChanges(removeClassHandler, true, CLASS_ATTR_NAME);
      }
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function observeDOMChanges(callback) {
      var observeAttrs = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : false;
      var attrsToObserve = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : [];
      var THROTTLE_DELAY_MS = 20;
      var observer = new MutationObserver(throttle(callbackWrapper, THROTTLE_DELAY_MS));
      var connect = function connect() {
        if (attrsToObserve.length > 0) {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs,
            attributeFilter: attrsToObserve
          });
        } else {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs
          });
        }
      };
      var disconnect = function disconnect() {
        observer.disconnect();
      };
      function callbackWrapper() {
        disconnect();
        callback();
        connect();
      }
      connect();
    }
    function parseFlags(flags) {
      var FLAGS_DIVIDER = " ";
      var ASAP_FLAG = "asap";
      var COMPLETE_FLAG = "complete";
      var STAY_FLAG = "stay";
      var VALID_FLAGS = new Set([ASAP_FLAG, COMPLETE_FLAG, STAY_FLAG]);
      var passedFlags = new Set(flags.trim().split(FLAGS_DIVIDER).filter(function (flag) {
        return VALID_FLAGS.has(flag);
      }));
      return {
        ASAP: ASAP_FLAG,
        COMPLETE: COMPLETE_FLAG,
        STAY: STAY_FLAG,
        hasFlag: function hasFlag(flag) {
          return passedFlags.has(flag);
        }
      };
    }
    function throttle(cb, delay) {
      var wait = false;
      var savedArgs;
      var _wrapper = function wrapper() {
        for (var _len = arguments.length, args = new Array(_len), _key = 0; _key < _len; _key++) {
          args[_key] = arguments[_key];
        }
        if (wait) {
          savedArgs = args;
          return;
        }
        cb(...args);
        wait = true;
        setTimeout(function () {
          wait = false;
          if (savedArgs) {
            _wrapper(...savedArgs);
            savedArgs = null;
          }
        }, delay);
      };
      return _wrapper;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      removeClass.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function removeCookie(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function removeCookie(source, match) {
      var matchRegexp = toRegExp(match);
      var removeCookieFromHost = function removeCookieFromHost(cookieName, hostName) {
        var cookieSpec = `${cookieName}=`;
        var domain1 = `; domain=${hostName}`;
        var domain2 = `; domain=.${hostName}`;
        var path = "; path=/";
        var expiration = "; expires=Thu, 01 Jan 1970 00:00:00 GMT";
        document.cookie = cookieSpec + expiration;
        document.cookie = cookieSpec + domain1 + expiration;
        document.cookie = cookieSpec + domain2 + expiration;
        document.cookie = cookieSpec + path + expiration;
        document.cookie = cookieSpec + domain1 + path + expiration;
        document.cookie = cookieSpec + domain2 + path + expiration;
        hit(source);
      };
      var rmCookie = function rmCookie() {
        document.cookie.split(";").forEach(function (cookieStr) {
          var pos = cookieStr.indexOf("=");
          if (pos === -1) {
            return;
          }
          var cookieName = cookieStr.slice(0, pos).trim();
          if (!matchRegexp.test(cookieName)) {
            return;
          }
          var hostParts = document.location.hostname.split(".");
          for (var i = 0; i <= hostParts.length - 1; i += 1) {
            var hostName = hostParts.slice(i).join(".");
            if (hostName) {
              removeCookieFromHost(cookieName, hostName);
            }
          }
        });
      };
      rmCookie();
      window.addEventListener("beforeunload", rmCookie);
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      removeCookie.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function removeInShadowDom(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function removeInShadowDom(source, selector, baseSelector) {
      if (!Element.prototype.attachShadow) {
        return;
      }
      var removeElement = function removeElement(targetElement) {
        targetElement.remove();
      };
      var removeHandler = function removeHandler() {
        var hostElements = !baseSelector ? findHostElements(document.documentElement) : document.querySelectorAll(baseSelector);
        var _loop = function _loop() {
          var isRemoved = false;
          var {
            targets: targets,
            innerHosts: innerHosts
          } = pierceShadowDom(selector, hostElements);
          targets.forEach(function (targetEl) {
            removeElement(targetEl);
            isRemoved = true;
          });
          if (isRemoved) {
            hit(source);
          }
          hostElements = innerHosts;
        };
        while (hostElements.length !== 0) {
          _loop();
        }
      };
      removeHandler();
      observeDOMChanges(removeHandler, true);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function observeDOMChanges(callback) {
      var observeAttrs = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : false;
      var attrsToObserve = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : [];
      var THROTTLE_DELAY_MS = 20;
      var observer = new MutationObserver(throttle(callbackWrapper, THROTTLE_DELAY_MS));
      var connect = function connect() {
        if (attrsToObserve.length > 0) {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs,
            attributeFilter: attrsToObserve
          });
        } else {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs
          });
        }
      };
      var disconnect = function disconnect() {
        observer.disconnect();
      };
      function callbackWrapper() {
        disconnect();
        callback();
        connect();
      }
      connect();
    }
    function findHostElements(rootElement) {
      var hosts = [];
      if (rootElement) {
        var domElems = rootElement.querySelectorAll("*");
        domElems.forEach(function (el) {
          if (el.shadowRoot) {
            hosts.push(el);
          }
        });
      }
      return hosts;
    }
    function pierceShadowDom(selector, hostElements) {
      var targets = [];
      var innerHostsAcc = [];
      hostElements.forEach(function (host) {
        var simpleElems = host.querySelectorAll(selector);
        targets = targets.concat([].slice.call(simpleElems));
        var shadowRootElem = host.shadowRoot;
        var shadowChildren = shadowRootElem.querySelectorAll(selector);
        targets = targets.concat([].slice.call(shadowChildren));
        innerHostsAcc.push(findHostElements(shadowRootElem));
      });
      var innerHosts = flatten(innerHostsAcc);
      return {
        targets: targets,
        innerHosts: innerHosts
      };
    }
    function flatten(input) {
      var stack = [];
      input.forEach(function (el) {
        return stack.push(el);
      });
      var res = [];
      while (stack.length) {
        var next = stack.pop();
        if (Array.isArray(next)) {
          next.forEach(function (el) {
            return stack.push(el);
          });
        } else {
          res.push(next);
        }
      }
      return res.reverse();
    }
    function throttle(cb, delay) {
      var wait = false;
      var savedArgs;
      var _wrapper = function wrapper() {
        for (var _len = arguments.length, args = new Array(_len), _key = 0; _key < _len; _key++) {
          args[_key] = arguments[_key];
        }
        if (wait) {
          savedArgs = args;
          return;
        }
        cb(...args);
        wait = true;
        setTimeout(function () {
          wait = false;
          if (savedArgs) {
            _wrapper(...savedArgs);
            savedArgs = null;
          }
        }, delay);
      };
      return _wrapper;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      removeInShadowDom.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function removeNodeText(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function removeNodeText(source, nodeName, textMatch, parentSelector) {
      var {
        selector: selector,
        nodeNameMatch: nodeNameMatch,
        textContentMatch: textContentMatch
      } = parseNodeTextParams(nodeName, textMatch);
      var handleNodes = function handleNodes(nodes) {
        return nodes.forEach(function (node) {
          var shouldReplace = isTargetNode(node, nodeNameMatch, textContentMatch);
          if (shouldReplace) {
            var ALL_TEXT_PATTERN = /^[^]*$/;
            var REPLACEMENT = "";
            replaceNodeText(source, node, ALL_TEXT_PATTERN, REPLACEMENT);
          }
        });
      };
      if (document.documentElement) {
        handleExistingNodes(selector, handleNodes, parentSelector);
      }
      observeDocumentWithTimeout(function (mutations) {
        return handleMutations(mutations, handleNodes, selector, parentSelector);
      });
    }
    function observeDocumentWithTimeout(callback) {
      var options = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : {
        subtree: true,
        childList: true
      };
      var timeout = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : 1e4;
      var documentObserver = new MutationObserver(function (mutations, observer) {
        observer.disconnect();
        callback(mutations, observer);
        observer.observe(document.documentElement, options);
      });
      documentObserver.observe(document.documentElement, options);
      if (typeof timeout === "number") {
        setTimeout(function () {
          return documentObserver.disconnect();
        }, timeout);
      }
    }
    function handleExistingNodes(selector, handler, parentSelector) {
      var processNodes = function processNodes(parent) {
        if (selector === "#text") {
          var textNodes = nodeListToArray(parent.childNodes).filter(function (node) {
            return node.nodeType === Node.TEXT_NODE;
          });
          handler(textNodes);
        } else {
          var _nodes = nodeListToArray(parent.querySelectorAll(selector));
          handler(_nodes);
        }
      };
      var parents = parentSelector ? document.querySelectorAll(parentSelector) : [document];
      parents.forEach(function (parent) {
        return processNodes(parent);
      });
    }
    function handleMutations(mutations, handler, selector, parentSelector) {
      var addedNodes = getAddedNodes(mutations);
      if (selector && parentSelector) {
        addedNodes.forEach(function () {
          handleExistingNodes(selector, handler, parentSelector);
        });
      } else {
        handler(addedNodes);
      }
    }
    function replaceNodeText(source, node, pattern, replacement) {
      var {
        textContent: textContent
      } = node;
      if (textContent) {
        if (node.nodeName === "SCRIPT" && window.trustedTypes && window.trustedTypes.createPolicy) {
          var policy = window.trustedTypes.createPolicy("AGPolicy", {
            createScript: function createScript(string) {
              return string;
            }
          });
          var modifiedText = textContent.replace(pattern, replacement);
          var trustedReplacement = policy.createScript(modifiedText);
          node.textContent = trustedReplacement;
        } else {
          node.textContent = textContent.replace(pattern, replacement);
        }
        hit(source);
      }
    }
    function isTargetNode(node, nodeNameMatch, textContentMatch) {
      var {
        nodeName: nodeName,
        textContent: textContent
      } = node;
      var nodeNameLowerCase = nodeName.toLowerCase();
      return textContent !== null && textContent !== "" && (nodeNameMatch instanceof RegExp ? nodeNameMatch.test(nodeNameLowerCase) : nodeNameMatch === nodeNameLowerCase) && (textContentMatch instanceof RegExp ? textContentMatch.test(textContent) : textContent.includes(textContentMatch));
    }
    function parseNodeTextParams(nodeName, textMatch) {
      var pattern = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : null;
      var REGEXP_START_MARKER = "/";
      var isStringNameMatch = !(nodeName.startsWith(REGEXP_START_MARKER) && nodeName.endsWith(REGEXP_START_MARKER));
      var selector = isStringNameMatch ? nodeName : "*";
      var nodeNameMatch = isStringNameMatch ? nodeName : toRegExp(nodeName);
      var textContentMatch = !textMatch.startsWith(REGEXP_START_MARKER) ? textMatch : toRegExp(textMatch);
      var patternMatch;
      if (pattern) {
        patternMatch = !pattern.startsWith(REGEXP_START_MARKER) ? pattern : toRegExp(pattern);
      }
      return {
        selector: selector,
        nodeNameMatch: nodeNameMatch,
        textContentMatch: textContentMatch,
        patternMatch: patternMatch
      };
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function nodeListToArray(nodeList) {
      var nodes = [];
      for (var i = 0; i < nodeList.length; i += 1) {
        nodes.push(nodeList[i]);
      }
      return nodes;
    }
    function getAddedNodes(mutations) {
      var nodes = [];
      for (var i = 0; i < mutations.length; i += 1) {
        var {
          addedNodes: addedNodes
        } = mutations[i];
        for (var j = 0; j < addedNodes.length; j += 1) {
          nodes.push(addedNodes[j]);
        }
      }
      return nodes;
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      removeNodeText.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function setAttr(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function setAttr(source, selector, attr) {
      var value = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      if (!selector || !attr) {
        return;
      }
      var allowedValues = ["true", "false"];
      var shouldCopyValue = value.startsWith("[") && value.endsWith("]");
      var isValidValue = value.length === 0 || !nativeIsNaN(parseInt(value, 10)) && parseInt(value, 10) >= 0 && parseInt(value, 10) <= 32767 || allowedValues.includes(value.toLowerCase());
      if (!shouldCopyValue && !isValidValue) {
        logMessage(source, `Invalid attribute value provided: '${convertTypeToString(value)}'`);
        return;
      }
      var attributeHandler;
      if (shouldCopyValue) {
        attributeHandler = function attributeHandler(elem, attr, value) {
          var valueToCopy = elem.getAttribute(value.slice(1, -1));
          if (valueToCopy === null) {
            logMessage(source, `No element attribute found to copy value from: ${value}`);
          }
          elem.setAttribute(attr, valueToCopy);
        };
      }
      setAttributeBySelector(source, selector, attr, value, attributeHandler);
      observeDOMChanges(function () {
        return setAttributeBySelector(source, selector, attr, value, attributeHandler);
      }, true);
    }
    function setAttributeBySelector(source, selector, attribute, value) {
      var attributeSetter = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : defaultAttributeSetter;
      var elements;
      try {
        elements = document.querySelectorAll(selector);
      } catch (_unused) {
        logMessage(source, `Failed to find elements matching selector "${selector}"`);
        return;
      }
      if (!elements || elements.length === 0) {
        return;
      }
      try {
        elements.forEach(function (elem) {
          return attributeSetter(elem, attribute, value);
        });
        hit(source);
      } catch (_unused2) {
        logMessage(source, `Failed to set [${attribute}="${value}"] to each of selected elements.`);
      }
    }
    function observeDOMChanges(callback) {
      var observeAttrs = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : false;
      var attrsToObserve = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : [];
      var THROTTLE_DELAY_MS = 20;
      var observer = new MutationObserver(throttle(callbackWrapper, THROTTLE_DELAY_MS));
      var connect = function connect() {
        if (attrsToObserve.length > 0) {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs,
            attributeFilter: attrsToObserve
          });
        } else {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs
          });
        }
      };
      var disconnect = function disconnect() {
        observer.disconnect();
      };
      function callbackWrapper() {
        disconnect();
        callback();
        connect();
      }
      connect();
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function convertTypeToString(value) {
      var output;
      if (typeof value === "undefined") {
        output = "undefined";
      } else if (typeof value === "object") {
        if (value === null) {
          output = "null";
        } else {
          output = objectToString(value);
        }
      } else {
        output = String(value);
      }
      return output;
    }
    function defaultAttributeSetter(elem, attribute, value) {
      return elem.setAttribute(attribute, value);
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function throttle(cb, delay) {
      var wait = false;
      var savedArgs;
      var _wrapper = function wrapper() {
        for (var _len = arguments.length, args = new Array(_len), _key = 0; _key < _len; _key++) {
          args[_key] = arguments[_key];
        }
        if (wait) {
          savedArgs = args;
          return;
        }
        cb(...args);
        wait = true;
        setTimeout(function () {
          wait = false;
          if (savedArgs) {
            _wrapper(...savedArgs);
            savedArgs = null;
          }
        }, delay);
      };
      return _wrapper;
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      setAttr.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function setConstant(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function setConstant(source, property, value) {
      var stack = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var valueWrapper = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : "";
      var setProxyTrap = arguments.length > 5 && arguments[5] !== undefined ? arguments[5] : false;
      var uboAliases = ["set-constant.js", "ubo-set-constant.js", "set.js", "ubo-set.js", "ubo-set-constant", "ubo-set"];
      if (uboAliases.includes(source.name)) {
        if (stack.length !== 1 && !getNumberFromString(stack)) {
          valueWrapper = stack;
        }
        stack = undefined;
      }
      if (!property || !matchStackTrace(stack, new Error().stack)) {
        return;
      }
      var isProxyTrapSet = false;
      var emptyArr = noopArray();
      var emptyObj = noopObject();
      var constantValue;
      if (value === "undefined") {
        constantValue = undefined;
      } else if (value === "false") {
        constantValue = false;
      } else if (value === "true") {
        constantValue = true;
      } else if (value === "null") {
        constantValue = null;
      } else if (value === "emptyArr") {
        constantValue = emptyArr;
      } else if (value === "emptyObj") {
        constantValue = emptyObj;
      } else if (value === "noopFunc") {
        constantValue = noopFunc;
      } else if (value === "noopCallbackFunc") {
        constantValue = noopCallbackFunc;
      } else if (value === "trueFunc") {
        constantValue = trueFunc;
      } else if (value === "falseFunc") {
        constantValue = falseFunc;
      } else if (value === "throwFunc") {
        constantValue = throwFunc;
      } else if (value === "noopPromiseResolve") {
        constantValue = noopPromiseResolve;
      } else if (value === "noopPromiseReject") {
        constantValue = noopPromiseReject;
      } else if (/^\d+$/.test(value)) {
        constantValue = parseFloat(value);
        if (nativeIsNaN(constantValue)) {
          return;
        }
        if (Math.abs(constantValue) > 32767) {
          return;
        }
      } else if (value === "-1") {
        constantValue = -1;
      } else if (value === "") {
        constantValue = "";
      } else if (value === "yes") {
        constantValue = "yes";
      } else if (value === "no") {
        constantValue = "no";
      } else {
        return;
      }
      var valueWrapperNames = ["asFunction", "asCallback", "asResolved", "asRejected"];
      if (valueWrapperNames.includes(valueWrapper)) {
        var valueWrappersMap = {
          asFunction(v) {
            return function () {
              return v;
            };
          },
          asCallback(v) {
            return function () {
              return function () {
                return v;
              };
            };
          },
          asResolved(v) {
            return Promise.resolve(v);
          },
          asRejected(v) {
            return Promise.reject(v);
          }
        };
        constantValue = valueWrappersMap[valueWrapper](constantValue);
      }
      var canceled = false;
      var mustCancel = function mustCancel(value) {
        if (canceled) {
          return canceled;
        }
        canceled = value !== undefined && constantValue !== undefined && typeof value !== typeof constantValue && value !== null;
        return canceled;
      };
      var trapProp = function trapProp(base, prop, configurable, handler) {
        if (!handler.init(base[prop])) {
          return false;
        }
        var origDescriptor = Object.getOwnPropertyDescriptor(base, prop);
        var prevSetter;
        if (origDescriptor instanceof Object) {
          if (!origDescriptor.configurable) {
            var message = `Property '${prop}' is not configurable`;
            logMessage(source, message);
            return false;
          }
          if (base[prop]) {
            base[prop] = constantValue;
          }
          if (origDescriptor.set instanceof Function) {
            prevSetter = origDescriptor.set;
          }
        }
        Object.defineProperty(base, prop, {
          configurable: configurable,
          get() {
            return handler.get();
          },
          set(a) {
            if (prevSetter !== undefined) {
              prevSetter(a);
            }
            if (a instanceof Object) {
              var propertiesToCheck = property.split(".").slice(1);
              if (setProxyTrap && !isProxyTrapSet) {
                isProxyTrapSet = true;
                a = new Proxy(a, {
                  get: function get(target, propertyKey, val) {
                    propertiesToCheck.reduce(function (object, currentProp, index, array) {
                      var currentObj = object === null || object === void 0 ? void 0 : object[currentProp];
                      if (index === array.length - 1 && currentObj !== constantValue) {
                        object[currentProp] = constantValue;
                      }
                      return currentObj || object;
                    }, target);
                    return Reflect.get(target, propertyKey, val);
                  }
                });
              }
            }
            handler.set(a);
          }
        });
        return true;
      };
      var _setChainPropAccess = function setChainPropAccess(owner, property) {
        var chainInfo = getPropertyInChain(owner, property);
        var {
          base: base
        } = chainInfo;
        var {
          prop: prop,
          chain: chain
        } = chainInfo;
        var inChainPropHandler = {
          factValue: undefined,
          init(a) {
            this.factValue = a;
            return true;
          },
          get() {
            return this.factValue;
          },
          set(a) {
            if (this.factValue === a) {
              return;
            }
            this.factValue = a;
            if (a instanceof Object) {
              _setChainPropAccess(a, chain);
            }
          }
        };
        var endPropHandler = {
          init(a) {
            if (mustCancel(a)) {
              return false;
            }
            return true;
          },
          get() {
            return constantValue;
          },
          set(a) {
            if (!mustCancel(a)) {
              return;
            }
            constantValue = a;
          }
        };
        if (!chain) {
          var isTrapped = trapProp(base, prop, false, endPropHandler);
          if (isTrapped) {
            hit(source);
          }
          return;
        }
        if (base !== undefined && base[prop] === null) {
          trapProp(base, prop, true, inChainPropHandler);
          return;
        }
        if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
          trapProp(base, prop, true, inChainPropHandler);
        }
        var propValue = owner[prop];
        if (propValue instanceof Object || typeof propValue === "object" && propValue !== null) {
          _setChainPropAccess(propValue, chain);
        }
        trapProp(base, prop, true, inChainPropHandler);
      };
      _setChainPropAccess(window, property);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function getNumberFromString(rawString) {
      var parsedDelay = parseInt(rawString, 10);
      var validDelay = nativeIsNaN(parsedDelay) ? null : parsedDelay;
      return validDelay;
    }
    function noopArray() {
      return [];
    }
    function noopObject() {
      return {};
    }
    function noopFunc() {}
    function noopCallbackFunc() {
      return noopFunc;
    }
    function trueFunc() {
      return true;
    }
    function falseFunc() {
      return false;
    }
    function throwFunc() {
      throw new Error();
    }
    function noopPromiseReject() {
      return Promise.reject();
    }
    function noopPromiseResolve() {
      var responseBody = arguments.length > 0 && arguments[0] !== undefined ? arguments[0] : "{}";
      var responseUrl = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : "";
      var responseType = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : "basic";
      if (typeof Response === "undefined") {
        return;
      }
      var response = new Response(responseBody, {
        status: 200,
        statusText: "OK"
      });
      if (responseType === "opaque") {
        Object.defineProperties(response, {
          body: {
            value: null
          },
          status: {
            value: 0
          },
          ok: {
            value: false
          },
          statusText: {
            value: ""
          },
          url: {
            value: ""
          },
          type: {
            value: responseType
          }
        });
      } else {
        Object.defineProperties(response, {
          url: {
            value: responseUrl
          },
          type: {
            value: responseType
          }
        });
      }
      return Promise.resolve(response);
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function matchStackTrace(stackMatch, stackTrace) {
      if (!stackMatch || stackMatch === "") {
        return true;
      }
      var regExpValues = backupRegExpValues();
      if (shouldAbortInlineOrInjectedScript(stackMatch, stackTrace)) {
        if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
          restoreRegExpValues(regExpValues);
        }
        return true;
      }
      var stackRegexp = toRegExp(stackMatch);
      var refinedStackTrace = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      }).join("\n");
      if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
        restoreRegExpValues(regExpValues);
      }
      return getNativeRegexpTest().call(stackRegexp, refinedStackTrace);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    function shouldAbortInlineOrInjectedScript(stackMatch, stackTrace) {
      var INLINE_SCRIPT_STRING = "inlineScript";
      var INJECTED_SCRIPT_STRING = "injectedScript";
      var INJECTED_SCRIPT_MARKER = "<anonymous>";
      var isInlineScript = function isInlineScript(match) {
        return match.includes(INLINE_SCRIPT_STRING);
      };
      var isInjectedScript = function isInjectedScript(match) {
        return match.includes(INJECTED_SCRIPT_STRING);
      };
      if (!(isInlineScript(stackMatch) || isInjectedScript(stackMatch))) {
        return false;
      }
      var documentURL = window.location.href;
      var pos = documentURL.indexOf("#");
      if (pos !== -1) {
        documentURL = documentURL.slice(0, pos);
      }
      var stackSteps = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      });
      var stackLines = stackSteps.map(function (line) {
        var stack;
        var getStackTraceValues = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(line);
        if (getStackTraceValues) {
          var _stackURL, _stackURL2;
          var stackURL = getStackTraceValues[2];
          var stackLine = getStackTraceValues[3];
          var stackCol = getStackTraceValues[4];
          if ((_stackURL = stackURL) !== null && _stackURL !== void 0 && _stackURL.startsWith("(")) {
            stackURL = stackURL.slice(1);
          }
          if ((_stackURL2 = stackURL) !== null && _stackURL2 !== void 0 && _stackURL2.startsWith(INJECTED_SCRIPT_MARKER)) {
            var _stackFunction;
            stackURL = INJECTED_SCRIPT_STRING;
            var stackFunction = getStackTraceValues[1] !== undefined ? getStackTraceValues[1].slice(0, -1) : line.slice(0, getStackTraceValues.index).trim();
            if ((_stackFunction = stackFunction) !== null && _stackFunction !== void 0 && _stackFunction.startsWith("at")) {
              stackFunction = stackFunction.slice(2).trim();
            }
            stack = `${stackFunction} ${stackURL}${stackLine}${stackCol}`.trim();
          } else if (stackURL === documentURL) {
            stack = `${INLINE_SCRIPT_STRING}${stackLine}${stackCol}`.trim();
          } else {
            stack = `${stackURL}${stackLine}${stackCol}`.trim();
          }
        } else {
          stack = line;
        }
        return stack;
      });
      if (stackLines) {
        for (var index = 0; index < stackLines.length; index += 1) {
          if (isInlineScript(stackMatch) && stackLines[index].startsWith(INLINE_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
          if (isInjectedScript(stackMatch) && stackLines[index].startsWith(INJECTED_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
        }
      }
      return false;
    }
    function getNativeRegexpTest() {
      var descriptor = Object.getOwnPropertyDescriptor(RegExp.prototype, "test");
      var nativeRegexTest = descriptor === null || descriptor === void 0 ? void 0 : descriptor.value;
      if (descriptor && typeof descriptor.value === "function") {
        return nativeRegexTest;
      }
      throw new Error("RegExp.prototype.test is not a function");
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function backupRegExpValues() {
      try {
        var arrayOfRegexpValues = [];
        for (var index = 1; index < 10; index += 1) {
          var value = `$${index}`;
          if (!RegExp[value]) {
            break;
          }
          arrayOfRegexpValues.push(RegExp[value]);
        }
        return arrayOfRegexpValues;
      } catch (error) {
        return [];
      }
    }
    function restoreRegExpValues(array) {
      if (!array.length) {
        return;
      }
      try {
        var stringPattern = "";
        if (array.length === 1) {
          stringPattern = `(${array[0]})`;
        } else {
          stringPattern = array.reduce(function (accumulator, currentValue, currentIndex) {
            if (currentIndex === 1) {
              return `(${accumulator}),(${currentValue})`;
            }
            return `${accumulator},(${currentValue})`;
          });
        }
        var regExpGroup = new RegExp(stringPattern);
        array.toString().replace(regExpGroup, "");
      } catch (error) {
        var message = `Failed to restore RegExp values: ${error}`;
        console.log(message);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      setConstant.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function setCookie(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function setCookie(source, name, value) {
      var path = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "/";
      var domain = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : "";
      var validValue = getLimitedCookieValue(value);
      if (validValue === null) {
        logMessage(source, `Invalid cookie value: '${validValue}'`);
        return;
      }
      if (!isValidCookiePath(path)) {
        logMessage(source, `Invalid cookie path: '${path}'`);
        return;
      }
      if (!document.location.origin.includes(domain)) {
        logMessage(source, `Cookie domain not matched by origin: '${domain}'`);
        return;
      }
      var cookieToSet = serializeCookie(name, validValue, path, domain);
      if (!cookieToSet) {
        logMessage(source, "Invalid cookie name or value");
        return;
      }
      hit(source);
      document.cookie = cookieToSet;
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function getLimitedCookieValue(value) {
      if (!value) {
        return null;
      }
      var allowedCookieValues = new Set(["true", "t", "false", "f", "yes", "y", "no", "n", "ok", "on", "off", "accept", "accepted", "notaccepted", "reject", "rejected", "allow", "allowed", "disallow", "deny", "enable", "enabled", "disable", "disabled", "necessary", "required", "hide", "hidden", "essential", "nonessential", "checked", "unchecked", "forbidden", "forever"]);
      var validValue;
      if (allowedCookieValues.has(value.toLowerCase())) {
        validValue = value;
      } else if (/^\d+$/.test(value)) {
        validValue = parseFloat(value);
        if (nativeIsNaN(validValue)) {
          return null;
        }
        if (Math.abs(validValue) < 0 || Math.abs(validValue) > 32767) {
          return null;
        }
      } else {
        return null;
      }
      return validValue;
    }
    function serializeCookie(name, rawValue, rawPath) {
      var domainValue = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var shouldEncodeValue = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : true;
      var HOST_PREFIX = "__Host-";
      var SECURE_PREFIX = "__Secure-";
      var COOKIE_BREAKER = ";";
      if (!shouldEncodeValue && `${rawValue}`.includes(COOKIE_BREAKER) || name.includes(COOKIE_BREAKER)) {
        return null;
      }
      var value = shouldEncodeValue ? encodeURIComponent(rawValue) : rawValue;
      var resultCookie = `${name}=${value}`;
      if (name.startsWith(HOST_PREFIX)) {
        resultCookie += "; path=/; secure";
        if (domainValue) {
          console.debug(`Domain value: "${domainValue}" has been ignored, because is not allowed for __Host- prefixed cookies`);
        }
        return resultCookie;
      }
      var path = getCookiePath(rawPath);
      if (path) {
        resultCookie += `; ${path}`;
      }
      if (name.startsWith(SECURE_PREFIX)) {
        resultCookie += "; secure";
      }
      if (domainValue) {
        resultCookie += `; domain=${domainValue}`;
      }
      return resultCookie;
    }
    function isValidCookiePath(rawPath) {
      return rawPath === "/" || rawPath === "none";
    }
    function getCookiePath(rawPath) {
      if (rawPath === "/") {
        return "path=/";
      }
      return "";
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      setCookie.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function setCookieReload(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function setCookieReload(source, name, value) {
      var path = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "/";
      var domain = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : "";
      if (isCookieSetWithValue(document.cookie, name, value)) {
        return;
      }
      var validValue = getLimitedCookieValue(value);
      if (validValue === null) {
        logMessage(source, `Invalid cookie value: '${value}'`);
        return;
      }
      if (!isValidCookiePath(path)) {
        logMessage(source, `Invalid cookie path: '${path}'`);
        return;
      }
      if (!document.location.origin.includes(domain)) {
        logMessage(source, `Cookie domain not matched by origin: '${domain}'`);
        return;
      }
      var cookieToSet = serializeCookie(name, validValue, path, domain);
      if (!cookieToSet) {
        logMessage(source, "Invalid cookie name or value");
        return;
      }
      document.cookie = cookieToSet;
      hit(source);
      if (isCookieSetWithValue(document.cookie, name, value)) {
        window.location.reload();
      }
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function isCookieSetWithValue(cookieString, name, value) {
      return cookieString.split(";").some(function (cookieStr) {
        var pos = cookieStr.indexOf("=");
        if (pos === -1) {
          return false;
        }
        var cookieName = cookieStr.slice(0, pos).trim();
        var cookieValue = cookieStr.slice(pos + 1).trim();
        return name === cookieName && value === cookieValue;
      });
    }
    function getLimitedCookieValue(value) {
      if (!value) {
        return null;
      }
      var allowedCookieValues = new Set(["true", "t", "false", "f", "yes", "y", "no", "n", "ok", "on", "off", "accept", "accepted", "notaccepted", "reject", "rejected", "allow", "allowed", "disallow", "deny", "enable", "enabled", "disable", "disabled", "necessary", "required", "hide", "hidden", "essential", "nonessential", "checked", "unchecked", "forbidden", "forever"]);
      var validValue;
      if (allowedCookieValues.has(value.toLowerCase())) {
        validValue = value;
      } else if (/^\d+$/.test(value)) {
        validValue = parseFloat(value);
        if (nativeIsNaN(validValue)) {
          return null;
        }
        if (Math.abs(validValue) < 0 || Math.abs(validValue) > 32767) {
          return null;
        }
      } else {
        return null;
      }
      return validValue;
    }
    function serializeCookie(name, rawValue, rawPath) {
      var domainValue = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var shouldEncodeValue = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : true;
      var HOST_PREFIX = "__Host-";
      var SECURE_PREFIX = "__Secure-";
      var COOKIE_BREAKER = ";";
      if (!shouldEncodeValue && `${rawValue}`.includes(COOKIE_BREAKER) || name.includes(COOKIE_BREAKER)) {
        return null;
      }
      var value = shouldEncodeValue ? encodeURIComponent(rawValue) : rawValue;
      var resultCookie = `${name}=${value}`;
      if (name.startsWith(HOST_PREFIX)) {
        resultCookie += "; path=/; secure";
        if (domainValue) {
          console.debug(`Domain value: "${domainValue}" has been ignored, because is not allowed for __Host- prefixed cookies`);
        }
        return resultCookie;
      }
      var path = getCookiePath(rawPath);
      if (path) {
        resultCookie += `; ${path}`;
      }
      if (name.startsWith(SECURE_PREFIX)) {
        resultCookie += "; secure";
      }
      if (domainValue) {
        resultCookie += `; domain=${domainValue}`;
      }
      return resultCookie;
    }
    function isValidCookiePath(rawPath) {
      return rawPath === "/" || rawPath === "none";
    }
    function getCookiePath(rawPath) {
      if (rawPath === "/") {
        return "path=/";
      }
      return "";
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      setCookieReload.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function setLocalStorageItem(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function setLocalStorageItem(source, key, value) {
      if (typeof key === "undefined") {
        logMessage(source, "Item key should be specified.");
        return;
      }
      var validValue;
      try {
        validValue = getLimitedStorageItemValue(value);
      } catch (_unused) {
        logMessage(source, `Invalid storage item value: '${value}'`);
        return;
      }
      var {
        localStorage: localStorage
      } = window;
      if (validValue === "$remove$") {
        removeStorageItem(source, localStorage, key);
      } else {
        setStorageItem(source, localStorage, key, validValue);
      }
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function setStorageItem(source, storage, key, value) {
      try {
        storage.setItem(key, value);
      } catch (e) {
        var message = `Unable to set storage item due to: ${e.message}`;
        logMessage(source, message);
      }
    }
    function removeStorageItem(source, storage, key) {
      try {
        if (key.startsWith("/") && (key.endsWith("/") || key.endsWith("/i")) && isValidStrPattern(key)) {
          var regExpKey = toRegExp(key);
          var storageKeys = Object.keys(storage);
          storageKeys.forEach(function (storageKey) {
            if (regExpKey.test(storageKey)) {
              storage.removeItem(storageKey);
            }
          });
        } else {
          storage.removeItem(key);
        }
      } catch (e) {
        var message = `Unable to remove storage item due to: ${e.message}`;
        logMessage(source, message);
      }
    }
    function getLimitedStorageItemValue(value) {
      if (typeof value !== "string") {
        throw new Error("Invalid value");
      }
      var allowedStorageValues = new Set(["undefined", "false", "true", "null", "", "yes", "no", "on", "off", "accept", "accepted", "reject", "rejected", "allowed", "denied", "forbidden", "forever"]);
      var validValue;
      if (allowedStorageValues.has(value.toLowerCase())) {
        validValue = value;
      } else if (value === "emptyArr") {
        validValue = "[]";
      } else if (value === "emptyObj") {
        validValue = "{}";
      } else if (/^\d+$/.test(value)) {
        validValue = parseFloat(value);
        if (nativeIsNaN(validValue)) {
          throw new Error("Invalid value");
        }
        if (Math.abs(validValue) > 32767) {
          throw new Error("Invalid value");
        }
      } else if (value === "$remove$") {
        validValue = "$remove$";
      } else {
        throw new Error("Invalid value");
      }
      return validValue;
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      setLocalStorageItem.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function setPopadsDummy(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function setPopadsDummy(source) {
      delete window.PopAds;
      delete window.popns;
      Object.defineProperties(window, {
        PopAds: {
          get: function get() {
            hit(source);
            return {};
          }
        },
        popns: {
          get: function get() {
            hit(source);
            return {};
          }
        }
      });
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      setPopadsDummy.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function setSessionStorageItem(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function setSessionStorageItem(source, key, value) {
      if (typeof key === "undefined") {
        logMessage(source, "Item key should be specified.");
        return;
      }
      var validValue;
      try {
        validValue = getLimitedStorageItemValue(value);
      } catch (_unused) {
        logMessage(source, `Invalid storage item value: '${value}'`);
        return;
      }
      var {
        sessionStorage: sessionStorage
      } = window;
      if (validValue === "$remove$") {
        removeStorageItem(source, sessionStorage, key);
      } else {
        setStorageItem(source, sessionStorage, key, validValue);
      }
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function setStorageItem(source, storage, key, value) {
      try {
        storage.setItem(key, value);
      } catch (e) {
        var message = `Unable to set storage item due to: ${e.message}`;
        logMessage(source, message);
      }
    }
    function removeStorageItem(source, storage, key) {
      try {
        if (key.startsWith("/") && (key.endsWith("/") || key.endsWith("/i")) && isValidStrPattern(key)) {
          var regExpKey = toRegExp(key);
          var storageKeys = Object.keys(storage);
          storageKeys.forEach(function (storageKey) {
            if (regExpKey.test(storageKey)) {
              storage.removeItem(storageKey);
            }
          });
        } else {
          storage.removeItem(key);
        }
      } catch (e) {
        var message = `Unable to remove storage item due to: ${e.message}`;
        logMessage(source, message);
      }
    }
    function getLimitedStorageItemValue(value) {
      if (typeof value !== "string") {
        throw new Error("Invalid value");
      }
      var allowedStorageValues = new Set(["undefined", "false", "true", "null", "", "yes", "no", "on", "off", "accept", "accepted", "reject", "rejected", "allowed", "denied", "forbidden", "forever"]);
      var validValue;
      if (allowedStorageValues.has(value.toLowerCase())) {
        validValue = value;
      } else if (value === "emptyArr") {
        validValue = "[]";
      } else if (value === "emptyObj") {
        validValue = "{}";
      } else if (/^\d+$/.test(value)) {
        validValue = parseFloat(value);
        if (nativeIsNaN(validValue)) {
          throw new Error("Invalid value");
        }
        if (Math.abs(validValue) > 32767) {
          throw new Error("Invalid value");
        }
      } else if (value === "$remove$") {
        validValue = "$remove$";
      } else {
        throw new Error("Invalid value");
      }
      return validValue;
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      setSessionStorageItem.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function spoofCSS(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function spoofCSS(source, selectors, cssPropertyName, cssPropertyValue) {
      if (!selectors) {
        return;
      }
      var uboAliases = ["spoof-css.js", "ubo-spoof-css.js", "ubo-spoof-css"];
      function convertToCamelCase(cssProperty) {
        if (!cssProperty.includes("-")) {
          return cssProperty;
        }
        var splittedProperty = cssProperty.split("-");
        var firstPart = splittedProperty[0];
        var secondPart = splittedProperty[1];
        return `${firstPart}${secondPart[0].toUpperCase()}${secondPart.slice(1)}`;
      }
      var shouldDebug = !!(cssPropertyName === "debug" && cssPropertyValue);
      var propToValueMap = new Map();
      if (uboAliases.includes(source.name)) {
        var {
          args: args
        } = source;
        var arrayOfProperties = [];
        var isDebug = args.at(-2);
        if (isDebug === "debug") {
          arrayOfProperties = args.slice(1, -2);
        } else {
          arrayOfProperties = args.slice(1);
        }
        for (var i = 0; i < arrayOfProperties.length; i += 2) {
          if (arrayOfProperties[i] === "") {
            break;
          }
          propToValueMap.set(convertToCamelCase(arrayOfProperties[i]), arrayOfProperties[i + 1]);
        }
      } else if (cssPropertyName && cssPropertyValue && !shouldDebug) {
        propToValueMap.set(convertToCamelCase(cssPropertyName), cssPropertyValue);
      }
      var spoofStyle = function spoofStyle(cssProperty, realCssValue) {
        return propToValueMap.has(cssProperty) ? propToValueMap.get(cssProperty) : realCssValue;
      };
      var setRectValue = function setRectValue(rect, prop, value) {
        Object.defineProperty(rect, prop, {
          value: parseFloat(value)
        });
      };
      var getter = function getter(target, prop, receiver) {
        hit(source);
        if (prop === "toString") {
          return target.toString.bind(target);
        }
        return Reflect.get(target, prop, receiver);
      };
      var getComputedStyleWrapper = function getComputedStyleWrapper(target, thisArg, args) {
        if (shouldDebug) {
          debugger;
        }
        var style = Reflect.apply(target, thisArg, args);
        if (!args[0].matches(selectors)) {
          return style;
        }
        var proxiedStyle = new Proxy(style, {
          get(target, prop) {
            var CSSStyleProp = target[prop];
            if (typeof CSSStyleProp !== "function") {
              return spoofStyle(prop, CSSStyleProp || "");
            }
            if (prop !== "getPropertyValue") {
              return CSSStyleProp.bind(target);
            }
            var getPropertyValueFunc = new Proxy(CSSStyleProp, {
              apply(target, thisArg, args) {
                var cssName = args[0];
                var cssValue = thisArg[cssName];
                return spoofStyle(cssName, cssValue);
              },
              get: getter
            });
            return getPropertyValueFunc;
          },
          getOwnPropertyDescriptor(target, prop) {
            if (propToValueMap.has(prop)) {
              return {
                configurable: true,
                enumerable: true,
                value: propToValueMap.get(prop),
                writable: true
              };
            }
            return Reflect.getOwnPropertyDescriptor(target, prop);
          }
        });
        hit(source);
        return proxiedStyle;
      };
      var getComputedStyleHandler = {
        apply: getComputedStyleWrapper,
        get: getter
      };
      window.getComputedStyle = new Proxy(window.getComputedStyle, getComputedStyleHandler);
      var getBoundingClientRectWrapper = function getBoundingClientRectWrapper(target, thisArg, args) {
        if (shouldDebug) {
          debugger;
        }
        var rect = Reflect.apply(target, thisArg, args);
        if (!thisArg.matches(selectors)) {
          return rect;
        }
        var {
          top: top,
          bottom: bottom,
          height: height,
          width: width,
          left: left,
          right: right
        } = rect;
        var newDOMRect = new window.DOMRect(rect.x, rect.y, top, bottom, width, height, left, right);
        if (propToValueMap.has("top")) {
          setRectValue(newDOMRect, "top", propToValueMap.get("top"));
        }
        if (propToValueMap.has("bottom")) {
          setRectValue(newDOMRect, "bottom", propToValueMap.get("bottom"));
        }
        if (propToValueMap.has("left")) {
          setRectValue(newDOMRect, "left", propToValueMap.get("left"));
        }
        if (propToValueMap.has("right")) {
          setRectValue(newDOMRect, "right", propToValueMap.get("right"));
        }
        if (propToValueMap.has("height")) {
          setRectValue(newDOMRect, "height", propToValueMap.get("height"));
        }
        if (propToValueMap.has("width")) {
          setRectValue(newDOMRect, "width", propToValueMap.get("width"));
        }
        hit(source);
        return newDOMRect;
      };
      var getBoundingClientRectHandler = {
        apply: getBoundingClientRectWrapper,
        get: getter
      };
      window.Element.prototype.getBoundingClientRect = new Proxy(window.Element.prototype.getBoundingClientRect, getBoundingClientRectHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      spoofCSS.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedClickElement(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedClickElement(source, selectors) {
      var extraMatch = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : "";
      var delay = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : NaN;
      var reload = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : "";
      if (!selectors) {
        return;
      }
      var SHADOW_COMBINATOR = " >>> ";
      var OBSERVER_TIMEOUT_MS = 1e4;
      var THROTTLE_DELAY_MS = 20;
      var STATIC_CLICK_DELAY_MS = 150;
      var STATIC_RELOAD_DELAY_MS = 500;
      var COOKIE_MATCH_MARKER = "cookie:";
      var LOCAL_STORAGE_MATCH_MARKER = "localStorage:";
      var TEXT_MATCH_MARKER = "containsText:";
      var RELOAD_ON_FINAL_CLICK_MARKER = "reloadAfterClick";
      var SELECTORS_DELIMITER = ",";
      var COOKIE_STRING_DELIMITER = ";";
      var COLON = ":";
      var EXTRA_MATCH_DELIMITER = /(,\s*){1}(?=!?cookie:|!?localStorage:|containsText:)/;
      var sleep = function sleep(delayMs) {
        return new Promise(function (resolve) {
          setTimeout(resolve, delayMs);
        });
      };
      if (selectors.includes(SHADOW_COMBINATOR)) {
        var attachShadowWrapper = function attachShadowWrapper(target, thisArg, argumentsList) {
          var _argumentsList$;
          var mode = (_argumentsList$ = argumentsList[0]) === null || _argumentsList$ === void 0 ? void 0 : _argumentsList$.mode;
          if (mode === "closed") {
            argumentsList[0].mode = "open";
          }
          return Reflect.apply(target, thisArg, argumentsList);
        };
        var attachShadowHandler = {
          apply: attachShadowWrapper
        };
        window.Element.prototype.attachShadow = new Proxy(window.Element.prototype.attachShadow, attachShadowHandler);
      }
      var parsedDelay;
      if (delay) {
        parsedDelay = parseInt(String(delay), 10);
        var isValidDelay = !Number.isNaN(parsedDelay) || parsedDelay < OBSERVER_TIMEOUT_MS;
        if (!isValidDelay) {
          var message = `Passed delay '${delay}' is invalid or bigger than ${OBSERVER_TIMEOUT_MS} ms`;
          logMessage(source, message);
          return;
        }
      }
      var canClick = !parsedDelay;
      var cookieMatches = [];
      var localStorageMatches = [];
      var textMatches = "";
      var isInvertedMatchCookie = false;
      var isInvertedMatchLocalStorage = false;
      if (extraMatch) {
        var parsedExtraMatch = extraMatch.split(EXTRA_MATCH_DELIMITER).map(function (matchStr) {
          return matchStr.trim();
        });
        parsedExtraMatch.forEach(function (matchStr) {
          if (matchStr.includes(COOKIE_MATCH_MARKER)) {
            var {
              isInvertedMatch: isInvertedMatch,
              matchValue: matchValue
            } = parseMatchArg(matchStr);
            isInvertedMatchCookie = isInvertedMatch;
            var cookieMatch = matchValue.replace(COOKIE_MATCH_MARKER, "");
            cookieMatches.push(cookieMatch);
          }
          if (matchStr.includes(LOCAL_STORAGE_MATCH_MARKER)) {
            var {
              isInvertedMatch: _isInvertedMatch,
              matchValue: _matchValue
            } = parseMatchArg(matchStr);
            isInvertedMatchLocalStorage = _isInvertedMatch;
            var localStorageMatch = _matchValue.replace(LOCAL_STORAGE_MATCH_MARKER, "");
            localStorageMatches.push(localStorageMatch);
          }
          if (matchStr.includes(TEXT_MATCH_MARKER)) {
            var {
              matchValue: _matchValue2
            } = parseMatchArg(matchStr);
            var textMatch = _matchValue2.replace(TEXT_MATCH_MARKER, "");
            textMatches = textMatch;
          }
        });
      }
      if (cookieMatches.length > 0) {
        var parsedCookieMatches = parseCookieString(cookieMatches.join(COOKIE_STRING_DELIMITER));
        var parsedCookies = parseCookieString(document.cookie);
        var cookieKeys = Object.keys(parsedCookies);
        if (cookieKeys.length === 0) {
          return;
        }
        var cookiesMatched = Object.keys(parsedCookieMatches).every(function (key) {
          var valueMatch = parsedCookieMatches[key] ? toRegExp(parsedCookieMatches[key]) : null;
          var keyMatch = toRegExp(key);
          return cookieKeys.some(function (cookieKey) {
            var keysMatched = keyMatch.test(cookieKey);
            if (!keysMatched) {
              return false;
            }
            if (!valueMatch) {
              return true;
            }
            var parsedCookieValue = parsedCookies[cookieKey];
            if (!parsedCookieValue) {
              return false;
            }
            return valueMatch.test(parsedCookieValue);
          });
        });
        var shouldRun = cookiesMatched !== isInvertedMatchCookie;
        if (!shouldRun) {
          return;
        }
      }
      if (localStorageMatches.length > 0) {
        var localStorageMatched = localStorageMatches.every(function (str) {
          var itemValue = window.localStorage.getItem(str);
          return itemValue || itemValue === "";
        });
        var _shouldRun = localStorageMatched !== isInvertedMatchLocalStorage;
        if (!_shouldRun) {
          return;
        }
      }
      var textMatchRegexp = textMatches ? toRegExp(textMatches) : null;
      var selectorsSequence = selectors.split(SELECTORS_DELIMITER).map(function (selector) {
        return selector.trim();
      });
      var createElementObj = function createElementObj(element, selector) {
        return {
          element: element || null,
          clicked: false,
          selectorText: selector || null
        };
      };
      var elementsSequence = Array(selectorsSequence.length).fill(createElementObj(null));
      var findAndClickElement = function findAndClickElement(elementObj) {
        try {
          if (!elementObj.selectorText) {
            return;
          }
          var element = queryShadowSelector(elementObj.selectorText);
          if (!element) {
            logMessage(source, `Could not find element: '${elementObj.selectorText}'`);
            return;
          }
          element.click();
          elementObj.clicked = true;
        } catch (error) {
          logMessage(source, `Could not click element: '${elementObj.selectorText}'`);
        }
      };
      var shouldReloadAfterClick = false;
      var reloadDelayMs = STATIC_RELOAD_DELAY_MS;
      if (reload) {
        var reloadSplit = reload.split(COLON);
        var reloadMarker = reloadSplit[0];
        var reloadValue = reloadSplit[1];
        if (reloadMarker !== RELOAD_ON_FINAL_CLICK_MARKER) {
          logMessage(source, `Passed reload option '${reload}' is invalid`);
          return;
        }
        if (reloadValue) {
          var passedReload = Number(reloadValue);
          if (Number.isNaN(passedReload)) {
            logMessage(source, `Passed reload delay value '${passedReload}' is invalid`);
            return;
          }
          if (passedReload > OBSERVER_TIMEOUT_MS) {
            logMessage(source, `Passed reload delay value '${passedReload}' is bigger than maximum ${OBSERVER_TIMEOUT_MS} ms`);
            return;
          }
          reloadDelayMs = passedReload;
        }
        shouldReloadAfterClick = true;
      }
      var canReload = true;
      var clickElementsBySequence = async function clickElementsBySequence() {
        for (var i = 0; i < elementsSequence.length; i += 1) {
          var elementObj = elementsSequence[i];
          if (i >= 1) {
            await sleep(STATIC_CLICK_DELAY_MS);
          }
          if (!elementObj.element) {
            break;
          }
          if (!elementObj.clicked) {
            if (elementObj.element.isConnected) {
              elementObj.element.click();
              elementObj.clicked = true;
            } else {
              findAndClickElement(elementObj);
            }
          }
        }
        var allElementsClicked = elementsSequence.every(function (elementObj) {
          return elementObj.clicked === true;
        });
        if (allElementsClicked) {
          if (shouldReloadAfterClick && canReload) {
            canReload = false;
            setTimeout(function () {
              window.location.reload();
            }, reloadDelayMs);
          }
          hit(source);
        }
      };
      var handleElement = function handleElement(element, i, selector) {
        var elementObj = createElementObj(element, selector);
        elementsSequence[i] = elementObj;
        if (canClick) {
          clickElementsBySequence();
        }
      };
      var fulfillAndHandleSelectors = function fulfillAndHandleSelectors() {
        var fulfilledSelectors = [];
        selectorsSequence.forEach(function (selector, i) {
          if (!selector) {
            return;
          }
          var element = queryShadowSelector(selector, document.documentElement, textMatchRegexp);
          if (!element) {
            return;
          }
          handleElement(element, i, selector);
          fulfilledSelectors.push(selector);
        });
        selectorsSequence = selectorsSequence.map(function (selector) {
          return selector && fulfilledSelectors.includes(selector) ? null : selector;
        });
        return selectorsSequence;
      };
      var findElements = function findElements(mutations, observer) {
        selectorsSequence = fulfillAndHandleSelectors();
        var allSelectorsFulfilled = selectorsSequence.every(function (selector) {
          return selector === null;
        });
        if (allSelectorsFulfilled) {
          observer.disconnect();
        }
      };
      var initializeMutationObserver = function initializeMutationObserver() {
        var observer = new MutationObserver(throttle(findElements, THROTTLE_DELAY_MS));
        observer.observe(document.documentElement, {
          attributes: true,
          childList: true,
          subtree: true
        });
        setTimeout(function () {
          return observer.disconnect();
        }, OBSERVER_TIMEOUT_MS);
      };
      var checkInitialElements = function checkInitialElements() {
        var foundElements = selectorsSequence.every(function (selector) {
          if (!selector) {
            return false;
          }
          var element = queryShadowSelector(selector, document.documentElement, textMatchRegexp);
          return !!element;
        });
        if (foundElements) {
          fulfillAndHandleSelectors();
        } else {
          initializeMutationObserver();
        }
      };
      checkInitialElements();
      if (parsedDelay) {
        setTimeout(function () {
          clickElementsBySequence();
          canClick = true;
        }, parsedDelay);
      }
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function parseCookieString(cookieString) {
      var COOKIE_DELIMITER = "=";
      var COOKIE_PAIRS_DELIMITER = ";";
      var cookieChunks = cookieString.split(COOKIE_PAIRS_DELIMITER);
      var cookieData = {};
      cookieChunks.forEach(function (singleCookie) {
        var cookieKey;
        var cookieValue = "";
        var delimiterIndex = singleCookie.indexOf(COOKIE_DELIMITER);
        if (delimiterIndex === -1) {
          cookieKey = singleCookie.trim();
        } else {
          cookieKey = singleCookie.slice(0, delimiterIndex).trim();
          cookieValue = singleCookie.slice(delimiterIndex + 1);
        }
        cookieData[cookieKey] = cookieValue || null;
      });
      return cookieData;
    }
    function throttle(cb, delay) {
      var wait = false;
      var savedArgs;
      var _wrapper = function wrapper() {
        for (var _len = arguments.length, args = new Array(_len), _key = 0; _key < _len; _key++) {
          args[_key] = arguments[_key];
        }
        if (wait) {
          savedArgs = args;
          return;
        }
        cb(...args);
        wait = true;
        setTimeout(function () {
          wait = false;
          if (savedArgs) {
            _wrapper(...savedArgs);
            savedArgs = null;
          }
        }, delay);
      };
      return _wrapper;
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function parseMatchArg(match) {
      var INVERT_MARKER = "!";
      var isInvertedMatch = match ? match === null || match === void 0 ? void 0 : match.startsWith(INVERT_MARKER) : false;
      var matchValue = isInvertedMatch ? match.slice(1) : match;
      var matchRegexp = toRegExp(matchValue);
      return {
        isInvertedMatch: isInvertedMatch,
        matchRegexp: matchRegexp,
        matchValue: matchValue
      };
    }
    function queryShadowSelector(selector) {
      var context = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : document.documentElement;
      var textContent = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : null;
      var SHADOW_COMBINATOR = " >>> ";
      var pos = selector.indexOf(SHADOW_COMBINATOR);
      if (pos === -1) {
        if (textContent) {
          return findElementWithText(context, selector, textContent);
        }
        return context.querySelector(selector);
      }
      var shadowHostSelector = selector.slice(0, pos).trim();
      var elem = context.querySelector(shadowHostSelector);
      if (!elem || !elem.shadowRoot) {
        return null;
      }
      var shadowRootSelector = selector.slice(pos + SHADOW_COMBINATOR.length).trim();
      return queryShadowSelector(shadowRootSelector, elem.shadowRoot, textContent);
    }
    function doesElementContainText(element, matchRegexp) {
      var {
        textContent: textContent
      } = element;
      if (!textContent) {
        return false;
      }
      return matchRegexp.test(textContent);
    }
    function findElementWithText(rootElement, selector, matchRegexp) {
      var elements = rootElement.querySelectorAll(selector);
      for (var i = 0; i < elements.length; i += 1) {
        if (doesElementContainText(elements[i], matchRegexp)) {
          return elements[i];
        }
      }
      return null;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedClickElement.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedCreateElement(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedCreateElement(source, parentSelector, tagName) {
      var attributePairs = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var textContent = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : "";
      var cleanupDelayMs = arguments.length > 5 && arguments[5] !== undefined ? arguments[5] : NaN;
      if (!parentSelector || !tagName) {
        return;
      }
      var IFRAME_WINDOW_NAME = "trusted-create-element-window";
      if (window.name === IFRAME_WINDOW_NAME) {
        return;
      }
      var logError = function logError(prefix, error) {
        logMessage(source, `${prefix} due to ${getErrorMessage(error)}`);
      };
      var element;
      try {
        element = document.createElement(tagName);
        element.textContent = textContent;
      } catch (e) {
        logError(`Cannot create element with tag name '${tagName}'`, e);
        return;
      }
      var attributes = [];
      try {
        attributes = parseAttributePairs(attributePairs);
      } catch (e) {
        logError(`Cannot parse attributePairs param: '${attributePairs}'`, e);
        return;
      }
      attributes.forEach(function (attr) {
        try {
          element.setAttribute(attr.name, attr.value);
        } catch (e) {
          logError(`Cannot set attribute '${attr.name}' with value '${attr.value}'`, e);
        }
      });
      var timerId;
      var elementCreated = false;
      var elementRemoved = false;
      var findParentAndAppendEl = function findParentAndAppendEl(parentElSelector, el, removeElDelayMs) {
        var parentEl;
        try {
          parentEl = document.querySelector(parentElSelector);
        } catch (e) {
          logError(`Cannot find parent element by selector '${parentElSelector}'`, e);
          return false;
        }
        if (!parentEl) {
          logMessage(source, `No parent element found by selector: '${parentElSelector}'`);
          return false;
        }
        try {
          if (!parentEl.contains(el)) {
            parentEl.append(el);
          }
          if (el instanceof HTMLIFrameElement && el.contentWindow) {
            el.contentWindow.name = IFRAME_WINDOW_NAME;
          }
          elementCreated = true;
          hit(source);
        } catch (e) {
          logError(`Cannot append child to parent by selector '${parentElSelector}'`, e);
          return false;
        }
        if (!nativeIsNaN(removeElDelayMs)) {
          timerId = setTimeout(function () {
            el.remove();
            elementRemoved = true;
            clearTimeout(timerId);
          }, removeElDelayMs);
        }
        return true;
      };
      if (!findParentAndAppendEl(parentSelector, element, cleanupDelayMs)) {
        observeDocumentWithTimeout(function (mutations, observer) {
          if (elementRemoved || elementCreated || findParentAndAppendEl(parentSelector, element, cleanupDelayMs)) {
            observer.disconnect();
          }
        });
      }
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function observeDocumentWithTimeout(callback) {
      var options = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : {
        subtree: true,
        childList: true
      };
      var timeout = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : 1e4;
      var documentObserver = new MutationObserver(function (mutations, observer) {
        observer.disconnect();
        callback(mutations, observer);
        observer.observe(document.documentElement, options);
      });
      documentObserver.observe(document.documentElement, options);
      if (typeof timeout === "number") {
        setTimeout(function () {
          return documentObserver.disconnect();
        }, timeout);
      }
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function parseAttributePairs(input) {
      if (!input) {
        return [];
      }
      var NAME_VALUE_SEPARATOR = "=";
      var PAIRS_SEPARATOR = " ";
      var SINGLE_QUOTE = "'";
      var DOUBLE_QUOTE = '"';
      var BACKSLASH = "\\";
      var pairs = [];
      for (var i = 0; i < input.length; i += 1) {
        var name = "";
        var value = "";
        while (i < input.length && input[i] !== NAME_VALUE_SEPARATOR && input[i] !== PAIRS_SEPARATOR) {
          name += input[i];
          i += 1;
        }
        if (i < input.length && input[i] === NAME_VALUE_SEPARATOR) {
          i += 1;
          var quote = null;
          if (input[i] === SINGLE_QUOTE || input[i] === DOUBLE_QUOTE) {
            quote = input[i];
            i += 1;
            for (; i < input.length; i += 1) {
              if (input[i] === quote) {
                if (input[i - 1] === BACKSLASH) {
                  value = `${value.slice(0, -1)}${quote}`;
                } else {
                  i += 1;
                  quote = null;
                  break;
                }
              } else {
                value += input[i];
              }
            }
            if (quote !== null) {
              throw new Error(`Unbalanced quote for attribute value: '${input}'`);
            }
          } else {
            throw new Error(`Attribute value should be quoted: "${input.slice(i)}"`);
          }
        }
        name = name.trim();
        value = value.trim();
        if (!name) {
          if (!value) {
            continue;
          }
          throw new Error(`Attribute name before '=' should be specified: '${input}'`);
        }
        pairs.push({
          name: name,
          value: value
        });
        if (input[i] && input[i] !== PAIRS_SEPARATOR) {
          throw new Error(`No space before attribute: '${input.slice(i)}'`);
        }
      }
      return pairs;
    }
    function getErrorMessage(error) {
      var isErrorWithMessage = function isErrorWithMessage(e) {
        return typeof e === "object" && e !== null && "message" in e && typeof e.message === "string";
      };
      if (isErrorWithMessage(error)) {
        return error.message;
      }
      try {
        return new Error(JSON.stringify(error)).message;
      } catch (_unused) {
        return new Error(String(error)).message;
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedCreateElement.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedDispatchEvent(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedDispatchEvent(source, event, target) {
      if (!event) {
        return;
      }
      var hasBeenDispatched = false;
      var eventTarget = document;
      if (target === "window") {
        eventTarget = window;
      }
      var events = new Set();
      var dispatch = function dispatch() {
        var customEvent = new Event(event);
        if (typeof target === "string" && target !== "window") {
          eventTarget = document.querySelector(target);
        }
        var isEventAdded = events.has(event);
        if (!hasBeenDispatched && isEventAdded && eventTarget) {
          hasBeenDispatched = true;
          hit(source);
          eventTarget.dispatchEvent(customEvent);
        }
      };
      var wrapper = function wrapper(eventListener, thisArg, args) {
        var eventName = args[0];
        if (thisArg && eventName) {
          events.add(eventName);
          setTimeout(function () {
            dispatch();
          }, 1);
        }
        return Reflect.apply(eventListener, thisArg, args);
      };
      var handler = {
        apply: wrapper
      };
      EventTarget.prototype.addEventListener = new Proxy(EventTarget.prototype.addEventListener, handler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedDispatchEvent.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedPruneInboundObject(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedPruneInboundObject(source, functionName, propsToRemove, requiredInitialProps) {
      var stack = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : "";
      if (!functionName) {
        return;
      }
      var nativeObjects = {
        nativeStringify: window.JSON.stringify
      };
      var {
        base: base,
        prop: prop
      } = getPropertyInChain(window, functionName);
      if (!base || !prop || typeof base[prop] !== "function") {
        var message = `${functionName} is not a function`;
        logMessage(source, message);
        return;
      }
      var prunePaths = getPrunePath(propsToRemove);
      var requiredPaths = getPrunePath(requiredInitialProps);
      var objectWrapper = function objectWrapper(target, thisArg, args) {
        var data = args[0];
        if (typeof data === "object") {
          data = jsonPruner(source, data, prunePaths, requiredPaths, stack, nativeObjects);
          args[0] = data;
        }
        return Reflect.apply(target, thisArg, args);
      };
      var objectHandler = {
        apply: objectWrapper
      };
      base[prop] = new Proxy(base[prop], objectHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function matchStackTrace(stackMatch, stackTrace) {
      if (!stackMatch || stackMatch === "") {
        return true;
      }
      var regExpValues = backupRegExpValues();
      if (shouldAbortInlineOrInjectedScript(stackMatch, stackTrace)) {
        if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
          restoreRegExpValues(regExpValues);
        }
        return true;
      }
      var stackRegexp = toRegExp(stackMatch);
      var refinedStackTrace = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      }).join("\n");
      if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
        restoreRegExpValues(regExpValues);
      }
      return getNativeRegexpTest().call(stackRegexp, refinedStackTrace);
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function getWildcardPropertyInChain(base, chain) {
      var lookThrough = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var output = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : [];
      var pos = chain.indexOf(".");
      if (pos === -1) {
        if (chain === "*" || chain === "[]") {
          for (var key in base) {
            if (Object.prototype.hasOwnProperty.call(base, key)) {
              output.push({
                base: base,
                prop: key
              });
            }
          }
        } else {
          output.push({
            base: base,
            prop: chain
          });
        }
        return output;
      }
      var prop = chain.slice(0, pos);
      var shouldLookThrough = prop === "[]" && Array.isArray(base) || prop === "*" && base instanceof Object;
      if (shouldLookThrough) {
        var nextProp = chain.slice(pos + 1);
        var baseKeys = Object.keys(base);
        baseKeys.forEach(function (key) {
          var item = base[key];
          getWildcardPropertyInChain(item, nextProp, lookThrough, output);
        });
      }
      if (Array.isArray(base)) {
        base.forEach(function (key) {
          var nextBase = key;
          if (nextBase !== undefined) {
            getWildcardPropertyInChain(nextBase, chain, lookThrough, output);
          }
        });
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if (nextBase !== undefined) {
        getWildcardPropertyInChain(nextBase, chain, lookThrough, output);
      }
      return output;
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function isPruningNeeded(source, root, prunePaths, requiredPaths, stack, nativeObjects) {
      if (!root) {
        return false;
      }
      var {
        nativeStringify: nativeStringify
      } = nativeObjects;
      var shouldProcess;
      if (prunePaths.length === 0 && requiredPaths.length > 0) {
        var rootString = nativeStringify(root);
        var matchRegex = toRegExp(requiredPaths.join(""));
        var shouldLog = matchRegex.test(rootString);
        if (shouldLog) {
          logMessage(source, `${window.location.hostname}\n${nativeStringify(root, null, 2)}\nStack trace:\n${new Error().stack}`, true);
          if (root && typeof root === "object") {
            logMessage(source, root, true, false);
          }
          shouldProcess = false;
          return shouldProcess;
        }
      }
      if (stack && !matchStackTrace(stack, new Error().stack || "")) {
        shouldProcess = false;
        return shouldProcess;
      }
      var wildcardSymbols = [".*.", "*.", ".*", ".[].", "[].", ".[]"];
      var _loop = function _loop() {
          var requiredPath = requiredPaths[i];
          var lastNestedPropName = requiredPath.split(".").pop();
          var hasWildcard = wildcardSymbols.some(function (symbol) {
            return requiredPath.includes(symbol);
          });
          var details = getWildcardPropertyInChain(root, requiredPath, hasWildcard);
          if (!details.length) {
            shouldProcess = false;
            return {
              v: shouldProcess
            };
          }
          shouldProcess = !hasWildcard;
          for (var j = 0; j < details.length; j += 1) {
            var hasRequiredProp = typeof lastNestedPropName === "string" && details[j].base[lastNestedPropName] !== undefined;
            if (hasWildcard) {
              shouldProcess = hasRequiredProp || shouldProcess;
            } else {
              shouldProcess = hasRequiredProp && shouldProcess;
            }
          }
        },
        _ret;
      for (var i = 0; i < requiredPaths.length; i += 1) {
        _ret = _loop();
        if (_ret) return _ret.v;
      }
      return shouldProcess;
    }
    function jsonPruner(source, root, prunePaths, requiredPaths, stack, nativeObjects) {
      var {
        nativeStringify: nativeStringify
      } = nativeObjects;
      if (prunePaths.length === 0 && requiredPaths.length === 0) {
        logMessage(source, `${window.location.hostname}\n${nativeStringify(root, null, 2)}\nStack trace:\n${new Error().stack}`, true);
        if (root && typeof root === "object") {
          logMessage(source, root, true, false);
        }
        return root;
      }
      try {
        if (isPruningNeeded(source, root, prunePaths, requiredPaths, stack, nativeObjects) === false) {
          return root;
        }
        prunePaths.forEach(function (path) {
          var ownerObjArr = getWildcardPropertyInChain(root, path, true);
          ownerObjArr.forEach(function (ownerObj) {
            if (ownerObj !== undefined && ownerObj.base) {
              delete ownerObj.base[ownerObj.prop];
              hit(source);
            }
          });
        });
      } catch (e) {
        logMessage(source, e);
      }
      return root;
    }
    function getPrunePath(props) {
      var validPropsString = typeof props === "string" && props !== undefined && props !== "";
      return validPropsString ? props.split(/ +/) : [];
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function getNativeRegexpTest() {
      var descriptor = Object.getOwnPropertyDescriptor(RegExp.prototype, "test");
      var nativeRegexTest = descriptor === null || descriptor === void 0 ? void 0 : descriptor.value;
      if (descriptor && typeof descriptor.value === "function") {
        return nativeRegexTest;
      }
      throw new Error("RegExp.prototype.test is not a function");
    }
    function shouldAbortInlineOrInjectedScript(stackMatch, stackTrace) {
      var INLINE_SCRIPT_STRING = "inlineScript";
      var INJECTED_SCRIPT_STRING = "injectedScript";
      var INJECTED_SCRIPT_MARKER = "<anonymous>";
      var isInlineScript = function isInlineScript(match) {
        return match.includes(INLINE_SCRIPT_STRING);
      };
      var isInjectedScript = function isInjectedScript(match) {
        return match.includes(INJECTED_SCRIPT_STRING);
      };
      if (!(isInlineScript(stackMatch) || isInjectedScript(stackMatch))) {
        return false;
      }
      var documentURL = window.location.href;
      var pos = documentURL.indexOf("#");
      if (pos !== -1) {
        documentURL = documentURL.slice(0, pos);
      }
      var stackSteps = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      });
      var stackLines = stackSteps.map(function (line) {
        var stack;
        var getStackTraceValues = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(line);
        if (getStackTraceValues) {
          var _stackURL, _stackURL2;
          var stackURL = getStackTraceValues[2];
          var stackLine = getStackTraceValues[3];
          var stackCol = getStackTraceValues[4];
          if ((_stackURL = stackURL) !== null && _stackURL !== void 0 && _stackURL.startsWith("(")) {
            stackURL = stackURL.slice(1);
          }
          if ((_stackURL2 = stackURL) !== null && _stackURL2 !== void 0 && _stackURL2.startsWith(INJECTED_SCRIPT_MARKER)) {
            var _stackFunction;
            stackURL = INJECTED_SCRIPT_STRING;
            var stackFunction = getStackTraceValues[1] !== undefined ? getStackTraceValues[1].slice(0, -1) : line.slice(0, getStackTraceValues.index).trim();
            if ((_stackFunction = stackFunction) !== null && _stackFunction !== void 0 && _stackFunction.startsWith("at")) {
              stackFunction = stackFunction.slice(2).trim();
            }
            stack = `${stackFunction} ${stackURL}${stackLine}${stackCol}`.trim();
          } else if (stackURL === documentURL) {
            stack = `${INLINE_SCRIPT_STRING}${stackLine}${stackCol}`.trim();
          } else {
            stack = `${stackURL}${stackLine}${stackCol}`.trim();
          }
        } else {
          stack = line;
        }
        return stack;
      });
      if (stackLines) {
        for (var index = 0; index < stackLines.length; index += 1) {
          if (isInlineScript(stackMatch) && stackLines[index].startsWith(INLINE_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
          if (isInjectedScript(stackMatch) && stackLines[index].startsWith(INJECTED_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
        }
      }
      return false;
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    function backupRegExpValues() {
      try {
        var arrayOfRegexpValues = [];
        for (var index = 1; index < 10; index += 1) {
          var value = `$${index}`;
          if (!RegExp[value]) {
            break;
          }
          arrayOfRegexpValues.push(RegExp[value]);
        }
        return arrayOfRegexpValues;
      } catch (error) {
        return [];
      }
    }
    function restoreRegExpValues(array) {
      if (!array.length) {
        return;
      }
      try {
        var stringPattern = "";
        if (array.length === 1) {
          stringPattern = `(${array[0]})`;
        } else {
          stringPattern = array.reduce(function (accumulator, currentValue, currentIndex) {
            if (currentIndex === 1) {
              return `(${accumulator}),(${currentValue})`;
            }
            return `${accumulator},(${currentValue})`;
          });
        }
        var regExpGroup = new RegExp(stringPattern);
        array.toString().replace(regExpGroup, "");
      } catch (error) {
        var message = `Failed to restore RegExp values: ${error}`;
        console.log(message);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedPruneInboundObject.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedReplaceFetchResponse(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedReplaceFetchResponse(source) {
      var pattern = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : "";
      var replacement = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : "";
      var propsToMatch = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var verbose = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : false;
      if (typeof fetch === "undefined" || typeof Proxy === "undefined" || typeof Response === "undefined") {
        return;
      }
      if (pattern === "" && replacement !== "") {
        logMessage(source, "Pattern argument should not be empty string");
        return;
      }
      var shouldLog = pattern === "" && replacement === "";
      var shouldLogContent = verbose === "true";
      var nativeRequestClone = Request.prototype.clone;
      var nativeFetch = fetch;
      var shouldReplace = false;
      var fetchData;
      var handlerWrapper = function handlerWrapper(target, thisArg, args) {
        fetchData = getFetchData(args, nativeRequestClone);
        if (shouldLog) {
          logMessage(source, `fetch( ${objectToString(fetchData)} )`, true);
          hit(source);
          return Reflect.apply(target, thisArg, args);
        }
        shouldReplace = matchRequestProps(source, propsToMatch, fetchData);
        if (!shouldReplace) {
          return Reflect.apply(target, thisArg, args);
        }
        return nativeFetch.apply(null, args).then(function (response) {
          return response.text().then(function (bodyText) {
            var patternRegexp = pattern === "*" ? /(\n|.)*/ : toRegExp(pattern);
            if (shouldLogContent) {
              logMessage(source, `Original text content: ${bodyText}`);
            }
            var modifiedTextContent = bodyText.replace(patternRegexp, replacement);
            if (shouldLogContent) {
              logMessage(source, `Modified text content: ${modifiedTextContent}`);
            }
            var forgedResponse = forgeResponse(response, modifiedTextContent);
            hit(source);
            return forgedResponse;
          }).catch(function () {
            var fetchDataStr = objectToString(fetchData);
            var message = `Response body can't be converted to text: ${fetchDataStr}`;
            logMessage(source, message);
            return Reflect.apply(target, thisArg, args);
          });
        }).catch(function () {
          return Reflect.apply(target, thisArg, args);
        });
      };
      var fetchHandler = {
        apply: handlerWrapper
      };
      fetch = new Proxy(fetch, fetchHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function getFetchData(args, nativeRequestClone) {
      var fetchPropsObj = {};
      var resource = args[0];
      var fetchUrl;
      var fetchInit;
      if (resource instanceof Request) {
        var realData = nativeRequestClone.call(resource);
        var requestData = getRequestData(realData);
        fetchUrl = requestData.url;
        fetchInit = requestData;
      } else {
        fetchUrl = resource;
        fetchInit = args[1];
      }
      fetchPropsObj.url = fetchUrl;
      if (fetchInit instanceof Object) {
        var props = Object.keys(fetchInit);
        props.forEach(function (prop) {
          fetchPropsObj[prop] = fetchInit[prop];
        });
      }
      return fetchPropsObj;
    }
    function objectToString(obj) {
      if (!obj || typeof obj !== "object") {
        return String(obj);
      }
      if (isEmptyObject(obj)) {
        return "{}";
      }
      return Object.entries(obj).map(function (pair) {
        var key = pair[0];
        var value = pair[1];
        var recordValueStr = value;
        if (value instanceof Object) {
          recordValueStr = `{ ${objectToString(value)} }`;
        }
        return `${key}:"${recordValueStr}"`;
      }).join(" ");
    }
    function matchRequestProps(source, propsToMatch, requestData) {
      if (propsToMatch === "" || propsToMatch === "*") {
        return true;
      }
      var isMatched;
      var parsedData = parseMatchProps(propsToMatch);
      if (!isValidParsedData(parsedData)) {
        logMessage(source, `Invalid parameter: ${propsToMatch}`);
        isMatched = false;
      } else {
        var matchData = getMatchPropsData(parsedData);
        var matchKeys = Object.keys(matchData);
        isMatched = matchKeys.every(function (matchKey) {
          var matchValue = matchData[matchKey];
          var dataValue = requestData[matchKey];
          return Object.prototype.hasOwnProperty.call(requestData, matchKey) && typeof dataValue === "string" && (matchValue === null || matchValue === void 0 ? void 0 : matchValue.test(dataValue));
        });
      }
      return isMatched;
    }
    function forgeResponse(response, textContent) {
      var {
        bodyUsed: bodyUsed,
        headers: headers,
        ok: ok,
        redirected: redirected,
        status: status,
        statusText: statusText,
        type: type,
        url: url
      } = response;
      var forgedResponse = new Response(textContent, {
        status: status,
        statusText: statusText,
        headers: headers
      });
      Object.defineProperties(forgedResponse, {
        url: {
          value: url
        },
        type: {
          value: type
        },
        ok: {
          value: ok
        },
        bodyUsed: {
          value: bodyUsed
        },
        redirected: {
          value: redirected
        }
      });
      return forgedResponse;
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    function getRequestData(request) {
      var requestInitOptions = getRequestProps();
      var entries = requestInitOptions.map(function (key) {
        var value = request[key];
        return [key, value];
      });
      return Object.fromEntries(entries);
    }
    function getRequestProps() {
      return ["url", "method", "headers", "body", "credentials", "cache", "redirect", "referrer", "referrerPolicy", "integrity", "keepalive", "signal", "mode"];
    }
    function parseMatchProps(propsToMatchStr) {
      var PROPS_DIVIDER = " ";
      var PAIRS_MARKER = ":";
      var isRequestProp = function isRequestProp(prop) {
        return getRequestProps().includes(prop);
      };
      var propsObj = {};
      var props = propsToMatchStr.split(PROPS_DIVIDER);
      props.forEach(function (prop) {
        var dividerInd = prop.indexOf(PAIRS_MARKER);
        var key = prop.slice(0, dividerInd);
        if (isRequestProp(key)) {
          var value = prop.slice(dividerInd + 1);
          propsObj[key] = value;
        } else {
          propsObj.url = prop;
        }
      });
      return propsObj;
    }
    function isValidParsedData(data) {
      return Object.values(data).every(function (value) {
        return isValidStrPattern(value);
      });
    }
    function getMatchPropsData(data) {
      var matchData = {};
      var dataKeys = Object.keys(data);
      dataKeys.forEach(function (key) {
        matchData[key] = toRegExp(data[key]);
      });
      return matchData;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedReplaceFetchResponse.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedReplaceNodeText(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedReplaceNodeText(source, nodeName, textMatch, pattern, replacement) {
      var {
        selector: selector,
        nodeNameMatch: nodeNameMatch,
        textContentMatch: textContentMatch,
        patternMatch: patternMatch
      } = parseNodeTextParams(nodeName, textMatch, pattern);
      for (var _len = arguments.length, extraArgs = new Array(_len > 5 ? _len - 5 : 0), _key = 5; _key < _len; _key++) {
        extraArgs[_key - 5] = arguments[_key];
      }
      var shouldLog = extraArgs.includes("verbose");
      var handleNodes = function handleNodes(nodes) {
        return nodes.forEach(function (node) {
          var shouldReplace = isTargetNode(node, nodeNameMatch, textContentMatch);
          if (shouldReplace) {
            if (shouldLog) {
              var originalText = node.textContent;
              if (originalText) {
                logMessage(source, `Original text content: ${originalText}`);
              }
            }
            replaceNodeText(source, node, patternMatch, replacement);
            if (shouldLog) {
              var modifiedText = node.textContent;
              if (modifiedText) {
                logMessage(source, `Modified text content: ${modifiedText}`);
              }
            }
          }
        });
      };
      if (document.documentElement) {
        handleExistingNodes(selector, handleNodes);
      }
      observeDocumentWithTimeout(function (mutations) {
        return handleMutations(mutations, handleNodes);
      });
    }
    function observeDocumentWithTimeout(callback) {
      var options = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : {
        subtree: true,
        childList: true
      };
      var timeout = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : 1e4;
      var documentObserver = new MutationObserver(function (mutations, observer) {
        observer.disconnect();
        callback(mutations, observer);
        observer.observe(document.documentElement, options);
      });
      documentObserver.observe(document.documentElement, options);
      if (typeof timeout === "number") {
        setTimeout(function () {
          return documentObserver.disconnect();
        }, timeout);
      }
    }
    function handleExistingNodes(selector, handler, parentSelector) {
      var processNodes = function processNodes(parent) {
        if (selector === "#text") {
          var textNodes = nodeListToArray(parent.childNodes).filter(function (node) {
            return node.nodeType === Node.TEXT_NODE;
          });
          handler(textNodes);
        } else {
          var _nodes = nodeListToArray(parent.querySelectorAll(selector));
          handler(_nodes);
        }
      };
      var parents = [document];
      parents.forEach(function (parent) {
        return processNodes(parent);
      });
    }
    function handleMutations(mutations, handler, selector, parentSelector) {
      var addedNodes = getAddedNodes(mutations);
      {
        handler(addedNodes);
      }
    }
    function replaceNodeText(source, node, pattern, replacement) {
      var {
        textContent: textContent
      } = node;
      if (textContent) {
        if (node.nodeName === "SCRIPT" && window.trustedTypes && window.trustedTypes.createPolicy) {
          var policy = window.trustedTypes.createPolicy("AGPolicy", {
            createScript: function createScript(string) {
              return string;
            }
          });
          var modifiedText = textContent.replace(pattern, replacement);
          var trustedReplacement = policy.createScript(modifiedText);
          node.textContent = trustedReplacement;
        } else {
          node.textContent = textContent.replace(pattern, replacement);
        }
        hit(source);
      }
    }
    function isTargetNode(node, nodeNameMatch, textContentMatch) {
      var {
        nodeName: nodeName,
        textContent: textContent
      } = node;
      var nodeNameLowerCase = nodeName.toLowerCase();
      return textContent !== null && textContent !== "" && (nodeNameMatch instanceof RegExp ? nodeNameMatch.test(nodeNameLowerCase) : nodeNameMatch === nodeNameLowerCase) && (textContentMatch instanceof RegExp ? textContentMatch.test(textContent) : textContent.includes(textContentMatch));
    }
    function parseNodeTextParams(nodeName, textMatch) {
      var pattern = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : null;
      var REGEXP_START_MARKER = "/";
      var isStringNameMatch = !(nodeName.startsWith(REGEXP_START_MARKER) && nodeName.endsWith(REGEXP_START_MARKER));
      var selector = isStringNameMatch ? nodeName : "*";
      var nodeNameMatch = isStringNameMatch ? nodeName : toRegExp(nodeName);
      var textContentMatch = !textMatch.startsWith(REGEXP_START_MARKER) ? textMatch : toRegExp(textMatch);
      var patternMatch;
      if (pattern) {
        patternMatch = !pattern.startsWith(REGEXP_START_MARKER) ? pattern : toRegExp(pattern);
      }
      return {
        selector: selector,
        nodeNameMatch: nodeNameMatch,
        textContentMatch: textContentMatch,
        patternMatch: patternMatch
      };
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function nodeListToArray(nodeList) {
      var nodes = [];
      for (var i = 0; i < nodeList.length; i += 1) {
        nodes.push(nodeList[i]);
      }
      return nodes;
    }
    function getAddedNodes(mutations) {
      var nodes = [];
      for (var i = 0; i < mutations.length; i += 1) {
        var {
          addedNodes: addedNodes
        } = mutations[i];
        for (var j = 0; j < addedNodes.length; j += 1) {
          nodes.push(addedNodes[j]);
        }
      }
      return nodes;
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedReplaceNodeText.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedReplaceOutboundText(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedReplaceOutboundText(source, methodPath) {
      var textToReplace = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : "";
      var replacement = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var decodeMethod = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : "";
      var stack = arguments.length > 5 && arguments[5] !== undefined ? arguments[5] : "";
      var logContent = arguments.length > 6 && arguments[6] !== undefined ? arguments[6] : "";
      if (!methodPath) {
        return;
      }
      var getPathParts = getPropertyInChain;
      var {
        base: base,
        chain: chain,
        prop: prop
      } = getPathParts(window, methodPath);
      if (typeof chain !== "undefined") {
        logMessage(source, `Could not reach the end of the prop chain: ${methodPath}`);
        return;
      }
      var nativeMethod = base[prop];
      if (!nativeMethod || typeof nativeMethod !== "function") {
        logMessage(source, `Could not retrieve the method: ${methodPath}`);
        return;
      }
      var isValidBase64 = function isValidBase64(str) {
        try {
          if (str === "") {
            return false;
          }
          var decodedString = atob(str);
          var encodedString = btoa(decodedString);
          var stringWithoutPadding = str.replace(/=+$/, "");
          var encodedStringWithoutPadding = encodedString.replace(/=+$/, "");
          return encodedStringWithoutPadding === stringWithoutPadding;
        } catch (e) {
          return false;
        }
      };
      var decodeAndReplaceContent = function decodeAndReplaceContent(content, pattern, textReplacement, decode, log) {
        switch (decode) {
          case "base64":
            try {
              if (!isValidBase64(content)) {
                logMessage(source, `Text content is not a valid base64 encoded string: ${content}`);
                return content;
              }
              var decodedContent = atob(content);
              if (log) {
                logMessage(source, `Decoded text content: ${decodedContent}`);
              }
              var modifiedContent = textToReplace ? decodedContent.replace(pattern, textReplacement) : decodedContent;
              if (log) {
                var message = modifiedContent !== decodedContent ? `Modified decoded text content: ${modifiedContent}` : "Decoded text content was not modified";
                logMessage(source, message);
              }
              var encodedContent = btoa(modifiedContent);
              return encodedContent;
            } catch (e) {
              return content;
            }
          default:
            return content.replace(pattern, textReplacement);
        }
      };
      var logOriginalContent = !textToReplace || !!logContent;
      var logModifiedContent = !!logContent;
      var logDecodedContent = !!decodeMethod && !!logContent;
      var isMatchingSuspended = false;
      var objectWrapper = function objectWrapper(target, thisArg, argumentsList) {
        if (isMatchingSuspended) {
          return Reflect.apply(target, thisArg, argumentsList);
        }
        isMatchingSuspended = true;
        hit(source);
        var result = Reflect.apply(target, thisArg, argumentsList);
        if (stack && !matchStackTrace(stack, new Error().stack || "")) {
          return result;
        }
        if (typeof result === "string") {
          if (logOriginalContent) {
            logMessage(source, `Original text content: ${result}`);
          }
          var patternRegexp = toRegExp(textToReplace);
          var modifiedContent = textToReplace || logDecodedContent ? decodeAndReplaceContent(result, patternRegexp, replacement, decodeMethod, logContent) : result;
          if (logModifiedContent) {
            var message = modifiedContent !== result ? `Modified text content: ${modifiedContent}` : "Text content was not modified";
            logMessage(source, message);
          }
          isMatchingSuspended = false;
          return modifiedContent;
        }
        isMatchingSuspended = false;
        logMessage(source, "Content is not a string");
        return result;
      };
      var objectHandler = {
        apply: objectWrapper
      };
      base[prop] = new Proxy(nativeMethod, objectHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function matchStackTrace(stackMatch, stackTrace) {
      if (!stackMatch || stackMatch === "") {
        return true;
      }
      var regExpValues = backupRegExpValues();
      if (shouldAbortInlineOrInjectedScript(stackMatch, stackTrace)) {
        if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
          restoreRegExpValues(regExpValues);
        }
        return true;
      }
      var stackRegexp = toRegExp(stackMatch);
      var refinedStackTrace = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      }).join("\n");
      if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
        restoreRegExpValues(regExpValues);
      }
      return getNativeRegexpTest().call(stackRegexp, refinedStackTrace);
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function shouldAbortInlineOrInjectedScript(stackMatch, stackTrace) {
      var INLINE_SCRIPT_STRING = "inlineScript";
      var INJECTED_SCRIPT_STRING = "injectedScript";
      var INJECTED_SCRIPT_MARKER = "<anonymous>";
      var isInlineScript = function isInlineScript(match) {
        return match.includes(INLINE_SCRIPT_STRING);
      };
      var isInjectedScript = function isInjectedScript(match) {
        return match.includes(INJECTED_SCRIPT_STRING);
      };
      if (!(isInlineScript(stackMatch) || isInjectedScript(stackMatch))) {
        return false;
      }
      var documentURL = window.location.href;
      var pos = documentURL.indexOf("#");
      if (pos !== -1) {
        documentURL = documentURL.slice(0, pos);
      }
      var stackSteps = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      });
      var stackLines = stackSteps.map(function (line) {
        var stack;
        var getStackTraceValues = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(line);
        if (getStackTraceValues) {
          var _stackURL, _stackURL2;
          var stackURL = getStackTraceValues[2];
          var stackLine = getStackTraceValues[3];
          var stackCol = getStackTraceValues[4];
          if ((_stackURL = stackURL) !== null && _stackURL !== void 0 && _stackURL.startsWith("(")) {
            stackURL = stackURL.slice(1);
          }
          if ((_stackURL2 = stackURL) !== null && _stackURL2 !== void 0 && _stackURL2.startsWith(INJECTED_SCRIPT_MARKER)) {
            var _stackFunction;
            stackURL = INJECTED_SCRIPT_STRING;
            var stackFunction = getStackTraceValues[1] !== undefined ? getStackTraceValues[1].slice(0, -1) : line.slice(0, getStackTraceValues.index).trim();
            if ((_stackFunction = stackFunction) !== null && _stackFunction !== void 0 && _stackFunction.startsWith("at")) {
              stackFunction = stackFunction.slice(2).trim();
            }
            stack = `${stackFunction} ${stackURL}${stackLine}${stackCol}`.trim();
          } else if (stackURL === documentURL) {
            stack = `${INLINE_SCRIPT_STRING}${stackLine}${stackCol}`.trim();
          } else {
            stack = `${stackURL}${stackLine}${stackCol}`.trim();
          }
        } else {
          stack = line;
        }
        return stack;
      });
      if (stackLines) {
        for (var index = 0; index < stackLines.length; index += 1) {
          if (isInlineScript(stackMatch) && stackLines[index].startsWith(INLINE_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
          if (isInjectedScript(stackMatch) && stackLines[index].startsWith(INJECTED_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
        }
      }
      return false;
    }
    function getNativeRegexpTest() {
      var descriptor = Object.getOwnPropertyDescriptor(RegExp.prototype, "test");
      var nativeRegexTest = descriptor === null || descriptor === void 0 ? void 0 : descriptor.value;
      if (descriptor && typeof descriptor.value === "function") {
        return nativeRegexTest;
      }
      throw new Error("RegExp.prototype.test is not a function");
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    function backupRegExpValues() {
      try {
        var arrayOfRegexpValues = [];
        for (var index = 1; index < 10; index += 1) {
          var value = `$${index}`;
          if (!RegExp[value]) {
            break;
          }
          arrayOfRegexpValues.push(RegExp[value]);
        }
        return arrayOfRegexpValues;
      } catch (error) {
        return [];
      }
    }
    function restoreRegExpValues(array) {
      if (!array.length) {
        return;
      }
      try {
        var stringPattern = "";
        if (array.length === 1) {
          stringPattern = `(${array[0]})`;
        } else {
          stringPattern = array.reduce(function (accumulator, currentValue, currentIndex) {
            if (currentIndex === 1) {
              return `(${accumulator}),(${currentValue})`;
            }
            return `${accumulator},(${currentValue})`;
          });
        }
        var regExpGroup = new RegExp(stringPattern);
        array.toString().replace(regExpGroup, "");
      } catch (error) {
        var message = `Failed to restore RegExp values: ${error}`;
        console.log(message);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedReplaceOutboundText.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedReplaceXhrResponse(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedReplaceXhrResponse(source) {
      var pattern = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : "";
      var replacement = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : "";
      var propsToMatch = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var verbose = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : false;
      if (typeof Proxy === "undefined") {
        return;
      }
      if (pattern === "" && replacement !== "") {
        var message = "Pattern argument should not be empty string.";
        logMessage(source, message);
        return;
      }
      var shouldLog = pattern === "" && replacement === "";
      var shouldLogContent = verbose === "true";
      var nativeOpen = window.XMLHttpRequest.prototype.open;
      var nativeSend = window.XMLHttpRequest.prototype.send;
      var xhrData;
      var openWrapper = function openWrapper(target, thisArg, args) {
        xhrData = getXhrData.apply(null, args);
        if (shouldLog) {
          var _message = `xhr( ${objectToString(xhrData)} )`;
          logMessage(source, _message, true);
          hit(source);
          return Reflect.apply(target, thisArg, args);
        }
        if (matchRequestProps(source, propsToMatch, xhrData)) {
          thisArg.shouldBePrevented = true;
          thisArg.headersReceived = !!thisArg.headersReceived;
        }
        if (thisArg.shouldBePrevented && !thisArg.headersReceived) {
          thisArg.headersReceived = true;
          thisArg.collectedHeaders = [];
          var setRequestHeaderWrapper = function setRequestHeaderWrapper(target, thisArg, args) {
            thisArg.collectedHeaders.push(args);
            return Reflect.apply(target, thisArg, args);
          };
          var setRequestHeaderHandler = {
            apply: setRequestHeaderWrapper
          };
          thisArg.setRequestHeader = new Proxy(thisArg.setRequestHeader, setRequestHeaderHandler);
        }
        return Reflect.apply(target, thisArg, args);
      };
      var sendWrapper = function sendWrapper(target, thisArg, args) {
        if (!thisArg.shouldBePrevented) {
          return Reflect.apply(target, thisArg, args);
        }
        var forgedRequest = new XMLHttpRequest();
        forgedRequest.addEventListener("readystatechange", function () {
          if (forgedRequest.readyState !== 4) {
            return;
          }
          var {
            readyState: readyState,
            response: response,
            responseText: responseText,
            responseURL: responseURL,
            responseXML: responseXML,
            status: status,
            statusText: statusText
          } = forgedRequest;
          var content = responseText || response;
          if (typeof content !== "string") {
            return;
          }
          var patternRegexp = pattern === "*" ? /(\n|.)*/ : toRegExp(pattern);
          if (shouldLogContent) {
            logMessage(source, `Original text content: ${content}`);
          }
          var modifiedContent = content.replace(patternRegexp, replacement);
          if (shouldLogContent) {
            logMessage(source, `Modified text content: ${modifiedContent}`);
          }
          Object.defineProperties(thisArg, {
            readyState: {
              value: readyState,
              writable: false
            },
            responseURL: {
              value: responseURL,
              writable: false
            },
            responseXML: {
              value: responseXML,
              writable: false
            },
            status: {
              value: status,
              writable: false
            },
            statusText: {
              value: statusText,
              writable: false
            },
            response: {
              value: modifiedContent,
              writable: false
            },
            responseText: {
              value: modifiedContent,
              writable: false
            }
          });
          setTimeout(function () {
            var stateEvent = new Event("readystatechange");
            thisArg.dispatchEvent(stateEvent);
            var loadEvent = new Event("load");
            thisArg.dispatchEvent(loadEvent);
            var loadEndEvent = new Event("loadend");
            thisArg.dispatchEvent(loadEndEvent);
          }, 1);
          hit(source);
        });
        nativeOpen.apply(forgedRequest, [xhrData.method, xhrData.url]);
        thisArg.collectedHeaders.forEach(function (header) {
          var name = header[0];
          var value = header[1];
          forgedRequest.setRequestHeader(name, value);
        });
        thisArg.collectedHeaders = [];
        try {
          nativeSend.call(forgedRequest, args);
        } catch (_unused) {
          return Reflect.apply(target, thisArg, args);
        }
        return undefined;
      };
      var openHandler = {
        apply: openWrapper
      };
      var sendHandler = {
        apply: sendWrapper
      };
      XMLHttpRequest.prototype.open = new Proxy(XMLHttpRequest.prototype.open, openHandler);
      XMLHttpRequest.prototype.send = new Proxy(XMLHttpRequest.prototype.send, sendHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function objectToString(obj) {
      if (!obj || typeof obj !== "object") {
        return String(obj);
      }
      if (isEmptyObject(obj)) {
        return "{}";
      }
      return Object.entries(obj).map(function (pair) {
        var key = pair[0];
        var value = pair[1];
        var recordValueStr = value;
        if (value instanceof Object) {
          recordValueStr = `{ ${objectToString(value)} }`;
        }
        return `${key}:"${recordValueStr}"`;
      }).join(" ");
    }
    function matchRequestProps(source, propsToMatch, requestData) {
      if (propsToMatch === "" || propsToMatch === "*") {
        return true;
      }
      var isMatched;
      var parsedData = parseMatchProps(propsToMatch);
      if (!isValidParsedData(parsedData)) {
        logMessage(source, `Invalid parameter: ${propsToMatch}`);
        isMatched = false;
      } else {
        var matchData = getMatchPropsData(parsedData);
        var matchKeys = Object.keys(matchData);
        isMatched = matchKeys.every(function (matchKey) {
          var matchValue = matchData[matchKey];
          var dataValue = requestData[matchKey];
          return Object.prototype.hasOwnProperty.call(requestData, matchKey) && typeof dataValue === "string" && (matchValue === null || matchValue === void 0 ? void 0 : matchValue.test(dataValue));
        });
      }
      return isMatched;
    }
    function getXhrData(method, url, async, user, password) {
      return {
        method: method,
        url: url,
        async: async,
        user: user,
        password: password
      };
    }
    function getMatchPropsData(data) {
      var matchData = {};
      var dataKeys = Object.keys(data);
      dataKeys.forEach(function (key) {
        matchData[key] = toRegExp(data[key]);
      });
      return matchData;
    }
    function getRequestProps() {
      return ["url", "method", "headers", "body", "credentials", "cache", "redirect", "referrer", "referrerPolicy", "integrity", "keepalive", "signal", "mode"];
    }
    function isValidParsedData(data) {
      return Object.values(data).every(function (value) {
        return isValidStrPattern(value);
      });
    }
    function parseMatchProps(propsToMatchStr) {
      var PROPS_DIVIDER = " ";
      var PAIRS_MARKER = ":";
      var isRequestProp = function isRequestProp(prop) {
        return getRequestProps().includes(prop);
      };
      var propsObj = {};
      var props = propsToMatchStr.split(PROPS_DIVIDER);
      props.forEach(function (prop) {
        var dividerInd = prop.indexOf(PAIRS_MARKER);
        var key = prop.slice(0, dividerInd);
        if (isRequestProp(key)) {
          var value = prop.slice(dividerInd + 1);
          propsObj[key] = value;
        } else {
          propsObj.url = prop;
        }
      });
      return propsObj;
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedReplaceXhrResponse.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedSetAttr(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedSetAttr(source, selector, attr) {
      var value = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      if (!selector || !attr) {
        return;
      }
      setAttributeBySelector(source, selector, attr, value);
      observeDOMChanges(function () {
        return setAttributeBySelector(source, selector, attr, value);
      }, true);
    }
    function setAttributeBySelector(source, selector, attribute, value) {
      var attributeSetter = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : defaultAttributeSetter;
      var elements;
      try {
        elements = document.querySelectorAll(selector);
      } catch (_unused) {
        logMessage(source, `Failed to find elements matching selector "${selector}"`);
        return;
      }
      if (!elements || elements.length === 0) {
        return;
      }
      try {
        elements.forEach(function (elem) {
          return attributeSetter(elem, attribute, value);
        });
        hit(source);
      } catch (_unused2) {
        logMessage(source, `Failed to set [${attribute}="${value}"] to each of selected elements.`);
      }
    }
    function observeDOMChanges(callback) {
      var observeAttrs = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : false;
      var attrsToObserve = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : [];
      var THROTTLE_DELAY_MS = 20;
      var observer = new MutationObserver(throttle(callbackWrapper, THROTTLE_DELAY_MS));
      var connect = function connect() {
        if (attrsToObserve.length > 0) {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs,
            attributeFilter: attrsToObserve
          });
        } else {
          observer.observe(document.documentElement, {
            childList: true,
            subtree: true,
            attributes: observeAttrs
          });
        }
      };
      var disconnect = function disconnect() {
        observer.disconnect();
      };
      function callbackWrapper() {
        disconnect();
        callback();
        connect();
      }
      connect();
    }
    function defaultAttributeSetter(elem, attribute, value) {
      return elem.setAttribute(attribute, value);
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function throttle(cb, delay) {
      var wait = false;
      var savedArgs;
      var _wrapper = function wrapper() {
        for (var _len = arguments.length, args = new Array(_len), _key = 0; _key < _len; _key++) {
          args[_key] = arguments[_key];
        }
        if (wait) {
          savedArgs = args;
          return;
        }
        cb(...args);
        wait = true;
        setTimeout(function () {
          wait = false;
          if (savedArgs) {
            _wrapper(...savedArgs);
            savedArgs = null;
          }
        }, delay);
      };
      return _wrapper;
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedSetAttr.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedSetConstant(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedSetConstant(source, property, value, stack) {
      if (!property || !matchStackTrace(stack, new Error().stack)) {
        return;
      }
      var constantValue;
      try {
        constantValue = inferValue(value);
      } catch (e) {
        logMessage(source, e);
        return;
      }
      var canceled = false;
      var mustCancel = function mustCancel(value) {
        if (canceled) {
          return canceled;
        }
        canceled = value !== undefined && constantValue !== undefined && typeof value !== typeof constantValue && value !== null;
        return canceled;
      };
      var trapProp = function trapProp(base, prop, configurable, handler) {
        if (!handler.init(base[prop])) {
          return false;
        }
        var origDescriptor = Object.getOwnPropertyDescriptor(base, prop);
        var prevSetter;
        if (origDescriptor instanceof Object) {
          if (!origDescriptor.configurable) {
            var message = `Property '${prop}' is not configurable`;
            logMessage(source, message);
            return false;
          }
          base[prop] = constantValue;
          if (origDescriptor.set instanceof Function) {
            prevSetter = origDescriptor.set;
          }
        }
        Object.defineProperty(base, prop, {
          configurable: configurable,
          get() {
            return handler.get();
          },
          set(a) {
            if (prevSetter !== undefined) {
              prevSetter(a);
            }
            handler.set(a);
          }
        });
        return true;
      };
      var _setChainPropAccess = function setChainPropAccess(owner, property) {
        var chainInfo = getPropertyInChain(owner, property);
        var {
          base: base
        } = chainInfo;
        var {
          prop: prop,
          chain: chain
        } = chainInfo;
        var inChainPropHandler = {
          factValue: undefined,
          init(a) {
            this.factValue = a;
            return true;
          },
          get() {
            return this.factValue;
          },
          set(a) {
            if (this.factValue === a) {
              return;
            }
            this.factValue = a;
            if (a instanceof Object) {
              _setChainPropAccess(a, chain);
            }
          }
        };
        var endPropHandler = {
          init(a) {
            if (mustCancel(a)) {
              return false;
            }
            return true;
          },
          get() {
            return constantValue;
          },
          set(a) {
            if (!mustCancel(a)) {
              return;
            }
            constantValue = a;
          }
        };
        if (!chain) {
          var isTrapped = trapProp(base, prop, false, endPropHandler);
          if (isTrapped) {
            hit(source);
          }
          return;
        }
        if (base !== undefined && base[prop] === null) {
          trapProp(base, prop, true, inChainPropHandler);
          return;
        }
        if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
          trapProp(base, prop, true, inChainPropHandler);
        }
        var propValue = owner[prop];
        if (propValue instanceof Object || typeof propValue === "object" && propValue !== null) {
          _setChainPropAccess(propValue, chain);
        }
        trapProp(base, prop, true, inChainPropHandler);
      };
      _setChainPropAccess(window, property);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function inferValue(value) {
      if (value === "undefined") {
        return undefined;
      }
      if (value === "false") {
        return false;
      }
      if (value === "true") {
        return true;
      }
      if (value === "null") {
        return null;
      }
      if (value === "NaN") {
        return NaN;
      }
      if (value.startsWith("/") && value.endsWith("/")) {
        return toRegExp(value);
      }
      var MAX_ALLOWED_NUM = 32767;
      var numVal = Number(value);
      if (!nativeIsNaN(numVal)) {
        if (Math.abs(numVal) > MAX_ALLOWED_NUM) {
          throw new Error("number values bigger than 32767 are not allowed");
        }
        return numVal;
      }
      var errorMessage = `'${value}' value type can't be inferred`;
      try {
        var parsableVal = JSON.parse(value);
        if (parsableVal instanceof Object || typeof parsableVal === "string") {
          return parsableVal;
        }
      } catch (e) {
        errorMessage += `: ${e}`;
      }
      throw new TypeError(errorMessage);
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function matchStackTrace(stackMatch, stackTrace) {
      if (!stackMatch || stackMatch === "") {
        return true;
      }
      var regExpValues = backupRegExpValues();
      if (shouldAbortInlineOrInjectedScript(stackMatch, stackTrace)) {
        if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
          restoreRegExpValues(regExpValues);
        }
        return true;
      }
      var stackRegexp = toRegExp(stackMatch);
      var refinedStackTrace = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      }).join("\n");
      if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
        restoreRegExpValues(regExpValues);
      }
      return getNativeRegexpTest().call(stackRegexp, refinedStackTrace);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    function getNativeRegexpTest() {
      var descriptor = Object.getOwnPropertyDescriptor(RegExp.prototype, "test");
      var nativeRegexTest = descriptor === null || descriptor === void 0 ? void 0 : descriptor.value;
      if (descriptor && typeof descriptor.value === "function") {
        return nativeRegexTest;
      }
      throw new Error("RegExp.prototype.test is not a function");
    }
    function shouldAbortInlineOrInjectedScript(stackMatch, stackTrace) {
      var INLINE_SCRIPT_STRING = "inlineScript";
      var INJECTED_SCRIPT_STRING = "injectedScript";
      var INJECTED_SCRIPT_MARKER = "<anonymous>";
      var isInlineScript = function isInlineScript(match) {
        return match.includes(INLINE_SCRIPT_STRING);
      };
      var isInjectedScript = function isInjectedScript(match) {
        return match.includes(INJECTED_SCRIPT_STRING);
      };
      if (!(isInlineScript(stackMatch) || isInjectedScript(stackMatch))) {
        return false;
      }
      var documentURL = window.location.href;
      var pos = documentURL.indexOf("#");
      if (pos !== -1) {
        documentURL = documentURL.slice(0, pos);
      }
      var stackSteps = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      });
      var stackLines = stackSteps.map(function (line) {
        var stack;
        var getStackTraceValues = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(line);
        if (getStackTraceValues) {
          var _stackURL, _stackURL2;
          var stackURL = getStackTraceValues[2];
          var stackLine = getStackTraceValues[3];
          var stackCol = getStackTraceValues[4];
          if ((_stackURL = stackURL) !== null && _stackURL !== void 0 && _stackURL.startsWith("(")) {
            stackURL = stackURL.slice(1);
          }
          if ((_stackURL2 = stackURL) !== null && _stackURL2 !== void 0 && _stackURL2.startsWith(INJECTED_SCRIPT_MARKER)) {
            var _stackFunction;
            stackURL = INJECTED_SCRIPT_STRING;
            var stackFunction = getStackTraceValues[1] !== undefined ? getStackTraceValues[1].slice(0, -1) : line.slice(0, getStackTraceValues.index).trim();
            if ((_stackFunction = stackFunction) !== null && _stackFunction !== void 0 && _stackFunction.startsWith("at")) {
              stackFunction = stackFunction.slice(2).trim();
            }
            stack = `${stackFunction} ${stackURL}${stackLine}${stackCol}`.trim();
          } else if (stackURL === documentURL) {
            stack = `${INLINE_SCRIPT_STRING}${stackLine}${stackCol}`.trim();
          } else {
            stack = `${stackURL}${stackLine}${stackCol}`.trim();
          }
        } else {
          stack = line;
        }
        return stack;
      });
      if (stackLines) {
        for (var index = 0; index < stackLines.length; index += 1) {
          if (isInlineScript(stackMatch) && stackLines[index].startsWith(INLINE_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
          if (isInjectedScript(stackMatch) && stackLines[index].startsWith(INJECTED_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
        }
      }
      return false;
    }
    function backupRegExpValues() {
      try {
        var arrayOfRegexpValues = [];
        for (var index = 1; index < 10; index += 1) {
          var value = `$${index}`;
          if (!RegExp[value]) {
            break;
          }
          arrayOfRegexpValues.push(RegExp[value]);
        }
        return arrayOfRegexpValues;
      } catch (error) {
        return [];
      }
    }
    function restoreRegExpValues(array) {
      if (!array.length) {
        return;
      }
      try {
        var stringPattern = "";
        if (array.length === 1) {
          stringPattern = `(${array[0]})`;
        } else {
          stringPattern = array.reduce(function (accumulator, currentValue, currentIndex) {
            if (currentIndex === 1) {
              return `(${accumulator}),(${currentValue})`;
            }
            return `${accumulator},(${currentValue})`;
          });
        }
        var regExpGroup = new RegExp(stringPattern);
        array.toString().replace(regExpGroup, "");
      } catch (error) {
        var message = `Failed to restore RegExp values: ${error}`;
        console.log(message);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedSetConstant.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedSetCookie(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedSetCookie(source, name, value) {
      var offsetExpiresSec = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var path = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : "/";
      var domain = arguments.length > 5 && arguments[5] !== undefined ? arguments[5] : "";
      if (typeof name === "undefined") {
        logMessage(source, "Cookie name should be specified");
        return;
      }
      if (typeof value === "undefined") {
        logMessage(source, "Cookie value should be specified");
        return;
      }
      var parsedValue = parseKeywordValue(value);
      if (!isValidCookiePath(path)) {
        logMessage(source, `Invalid cookie path: '${path}'`);
        return;
      }
      if (!document.location.origin.includes(domain)) {
        logMessage(source, `Cookie domain not matched by origin: '${domain}'`);
        return;
      }
      var cookieToSet = serializeCookie(name, parsedValue, path, domain, false);
      if (!cookieToSet) {
        logMessage(source, "Invalid cookie name or value");
        return;
      }
      if (offsetExpiresSec) {
        var parsedOffsetMs = getTrustedCookieOffsetMs(offsetExpiresSec);
        if (!parsedOffsetMs) {
          logMessage(source, `Invalid offsetExpiresSec value: ${offsetExpiresSec}`);
          return;
        }
        var expires = Date.now() + parsedOffsetMs;
        cookieToSet += `; expires=${new Date(expires).toUTCString()}`;
      }
      document.cookie = cookieToSet;
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function serializeCookie(name, rawValue, rawPath) {
      var domainValue = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var shouldEncodeValue = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : true;
      var HOST_PREFIX = "__Host-";
      var SECURE_PREFIX = "__Secure-";
      var COOKIE_BREAKER = ";";
      if (!shouldEncodeValue && `${rawValue}`.includes(COOKIE_BREAKER) || name.includes(COOKIE_BREAKER)) {
        return null;
      }
      var value = shouldEncodeValue ? encodeURIComponent(rawValue) : rawValue;
      var resultCookie = `${name}=${value}`;
      if (name.startsWith(HOST_PREFIX)) {
        resultCookie += "; path=/; secure";
        if (domainValue) {
          console.debug(`Domain value: "${domainValue}" has been ignored, because is not allowed for __Host- prefixed cookies`);
        }
        return resultCookie;
      }
      var path = getCookiePath(rawPath);
      if (path) {
        resultCookie += `; ${path}`;
      }
      if (name.startsWith(SECURE_PREFIX)) {
        resultCookie += "; secure";
      }
      if (domainValue) {
        resultCookie += `; domain=${domainValue}`;
      }
      return resultCookie;
    }
    function isValidCookiePath(rawPath) {
      return rawPath === "/" || rawPath === "none";
    }
    function getTrustedCookieOffsetMs(offsetExpiresSec) {
      var ONE_YEAR_EXPIRATION_KEYWORD = "1year";
      var ONE_DAY_EXPIRATION_KEYWORD = "1day";
      var MS_IN_SEC = 1e3;
      var SECONDS_IN_YEAR = 365 * 24 * 60 * 60;
      var SECONDS_IN_DAY = 24 * 60 * 60;
      var parsedSec;
      if (offsetExpiresSec === ONE_YEAR_EXPIRATION_KEYWORD) {
        parsedSec = SECONDS_IN_YEAR;
      } else if (offsetExpiresSec === ONE_DAY_EXPIRATION_KEYWORD) {
        parsedSec = SECONDS_IN_DAY;
      } else {
        parsedSec = Number.parseInt(offsetExpiresSec, 10);
        if (Number.isNaN(parsedSec)) {
          return null;
        }
      }
      return parsedSec * MS_IN_SEC;
    }
    function parseKeywordValue(rawValue) {
      var NOW_VALUE_KEYWORD = "$now$";
      var CURRENT_DATE_KEYWORD = "$currentDate$";
      var CURRENT_ISO_DATE_KEYWORD = "$currentISODate$";
      var parsedValue = rawValue;
      if (rawValue === NOW_VALUE_KEYWORD) {
        parsedValue = Date.now().toString();
      } else if (rawValue === CURRENT_DATE_KEYWORD) {
        parsedValue = Date();
      } else if (rawValue === CURRENT_ISO_DATE_KEYWORD) {
        parsedValue = new Date().toISOString();
      }
      return parsedValue;
    }
    function getCookiePath(rawPath) {
      if (rawPath === "/") {
        return "path=/";
      }
      return "";
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedSetCookie.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedSetCookieReload(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedSetCookieReload(source, name, value) {
      var offsetExpiresSec = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var path = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : "/";
      var domain = arguments.length > 5 && arguments[5] !== undefined ? arguments[5] : "";
      if (typeof name === "undefined") {
        logMessage(source, "Cookie name should be specified");
        return;
      }
      if (typeof value === "undefined") {
        logMessage(source, "Cookie value should be specified");
        return;
      }
      if (isCookieSetWithValue(document.cookie, name, value)) {
        return;
      }
      var parsedValue = parseKeywordValue(value);
      if (!isValidCookiePath(path)) {
        logMessage(source, `Invalid cookie path: '${path}'`);
        return;
      }
      if (!document.location.origin.includes(domain)) {
        logMessage(source, `Cookie domain not matched by origin: '${domain}'`);
        return;
      }
      var cookieToSet = serializeCookie(name, parsedValue, path, domain, false);
      if (!cookieToSet) {
        logMessage(source, "Invalid cookie name or value");
        return;
      }
      if (offsetExpiresSec) {
        var parsedOffsetMs = getTrustedCookieOffsetMs(offsetExpiresSec);
        if (!parsedOffsetMs) {
          logMessage(source, `Invalid offsetExpiresSec value: ${offsetExpiresSec}`);
          return;
        }
        var expires = Date.now() + parsedOffsetMs;
        cookieToSet += `; expires=${new Date(expires).toUTCString()}`;
      }
      document.cookie = cookieToSet;
      hit(source);
      var cookieValueToCheck = parseCookieString(document.cookie)[name];
      if (isCookieSetWithValue(document.cookie, name, cookieValueToCheck)) {
        window.location.reload();
      }
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function isCookieSetWithValue(cookieString, name, value) {
      return cookieString.split(";").some(function (cookieStr) {
        var pos = cookieStr.indexOf("=");
        if (pos === -1) {
          return false;
        }
        var cookieName = cookieStr.slice(0, pos).trim();
        var cookieValue = cookieStr.slice(pos + 1).trim();
        return name === cookieName && value === cookieValue;
      });
    }
    function serializeCookie(name, rawValue, rawPath) {
      var domainValue = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var shouldEncodeValue = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : true;
      var HOST_PREFIX = "__Host-";
      var SECURE_PREFIX = "__Secure-";
      var COOKIE_BREAKER = ";";
      if (!shouldEncodeValue && `${rawValue}`.includes(COOKIE_BREAKER) || name.includes(COOKIE_BREAKER)) {
        return null;
      }
      var value = shouldEncodeValue ? encodeURIComponent(rawValue) : rawValue;
      var resultCookie = `${name}=${value}`;
      if (name.startsWith(HOST_PREFIX)) {
        resultCookie += "; path=/; secure";
        if (domainValue) {
          console.debug(`Domain value: "${domainValue}" has been ignored, because is not allowed for __Host- prefixed cookies`);
        }
        return resultCookie;
      }
      var path = getCookiePath(rawPath);
      if (path) {
        resultCookie += `; ${path}`;
      }
      if (name.startsWith(SECURE_PREFIX)) {
        resultCookie += "; secure";
      }
      if (domainValue) {
        resultCookie += `; domain=${domainValue}`;
      }
      return resultCookie;
    }
    function isValidCookiePath(rawPath) {
      return rawPath === "/" || rawPath === "none";
    }
    function getTrustedCookieOffsetMs(offsetExpiresSec) {
      var ONE_YEAR_EXPIRATION_KEYWORD = "1year";
      var ONE_DAY_EXPIRATION_KEYWORD = "1day";
      var MS_IN_SEC = 1e3;
      var SECONDS_IN_YEAR = 365 * 24 * 60 * 60;
      var SECONDS_IN_DAY = 24 * 60 * 60;
      var parsedSec;
      if (offsetExpiresSec === ONE_YEAR_EXPIRATION_KEYWORD) {
        parsedSec = SECONDS_IN_YEAR;
      } else if (offsetExpiresSec === ONE_DAY_EXPIRATION_KEYWORD) {
        parsedSec = SECONDS_IN_DAY;
      } else {
        parsedSec = Number.parseInt(offsetExpiresSec, 10);
        if (Number.isNaN(parsedSec)) {
          return null;
        }
      }
      return parsedSec * MS_IN_SEC;
    }
    function parseKeywordValue(rawValue) {
      var NOW_VALUE_KEYWORD = "$now$";
      var CURRENT_DATE_KEYWORD = "$currentDate$";
      var CURRENT_ISO_DATE_KEYWORD = "$currentISODate$";
      var parsedValue = rawValue;
      if (rawValue === NOW_VALUE_KEYWORD) {
        parsedValue = Date.now().toString();
      } else if (rawValue === CURRENT_DATE_KEYWORD) {
        parsedValue = Date();
      } else if (rawValue === CURRENT_ISO_DATE_KEYWORD) {
        parsedValue = new Date().toISOString();
      }
      return parsedValue;
    }
    function parseCookieString(cookieString) {
      var COOKIE_DELIMITER = "=";
      var COOKIE_PAIRS_DELIMITER = ";";
      var cookieChunks = cookieString.split(COOKIE_PAIRS_DELIMITER);
      var cookieData = {};
      cookieChunks.forEach(function (singleCookie) {
        var cookieKey;
        var cookieValue = "";
        var delimiterIndex = singleCookie.indexOf(COOKIE_DELIMITER);
        if (delimiterIndex === -1) {
          cookieKey = singleCookie.trim();
        } else {
          cookieKey = singleCookie.slice(0, delimiterIndex).trim();
          cookieValue = singleCookie.slice(delimiterIndex + 1);
        }
        cookieData[cookieKey] = cookieValue || null;
      });
      return cookieData;
    }
    function getCookiePath(rawPath) {
      if (rawPath === "/") {
        return "path=/";
      }
      return "";
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedSetCookieReload.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedSetLocalStorageItem(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedSetLocalStorageItem(source, key, value) {
      if (typeof key === "undefined") {
        logMessage(source, "Item key should be specified");
        return;
      }
      if (typeof value === "undefined") {
        logMessage(source, "Item value should be specified");
        return;
      }
      var parsedValue = parseKeywordValue(value);
      var {
        localStorage: localStorage
      } = window;
      setStorageItem(source, localStorage, key, parsedValue);
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function setStorageItem(source, storage, key, value) {
      try {
        storage.setItem(key, value);
      } catch (e) {
        var message = `Unable to set storage item due to: ${e.message}`;
        logMessage(source, message);
      }
    }
    function parseKeywordValue(rawValue) {
      var NOW_VALUE_KEYWORD = "$now$";
      var CURRENT_DATE_KEYWORD = "$currentDate$";
      var CURRENT_ISO_DATE_KEYWORD = "$currentISODate$";
      var parsedValue = rawValue;
      if (rawValue === NOW_VALUE_KEYWORD) {
        parsedValue = Date.now().toString();
      } else if (rawValue === CURRENT_DATE_KEYWORD) {
        parsedValue = Date();
      } else if (rawValue === CURRENT_ISO_DATE_KEYWORD) {
        parsedValue = new Date().toISOString();
      }
      return parsedValue;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedSetLocalStorageItem.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedSetSessionStorageItem(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedSetSessionStorageItem(source, key, value) {
      if (typeof key === "undefined") {
        logMessage(source, "Item key should be specified");
        return;
      }
      if (typeof value === "undefined") {
        logMessage(source, "Item value should be specified");
        return;
      }
      var parsedValue = parseKeywordValue(value);
      var {
        sessionStorage: sessionStorage
      } = window;
      setStorageItem(source, sessionStorage, key, parsedValue);
      hit(source);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function setStorageItem(source, storage, key, value) {
      try {
        storage.setItem(key, value);
      } catch (e) {
        var message = `Unable to set storage item due to: ${e.message}`;
        logMessage(source, message);
      }
    }
    function parseKeywordValue(rawValue) {
      var NOW_VALUE_KEYWORD = "$now$";
      var CURRENT_DATE_KEYWORD = "$currentDate$";
      var CURRENT_ISO_DATE_KEYWORD = "$currentISODate$";
      var parsedValue = rawValue;
      if (rawValue === NOW_VALUE_KEYWORD) {
        parsedValue = Date.now().toString();
      } else if (rawValue === CURRENT_DATE_KEYWORD) {
        parsedValue = Date();
      } else if (rawValue === CURRENT_ISO_DATE_KEYWORD) {
        parsedValue = new Date().toISOString();
      }
      return parsedValue;
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedSetSessionStorageItem.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function trustedSuppressNativeMethod(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function trustedSuppressNativeMethod(source, methodPath, signatureStr) {
      var how = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "abort";
      var stack = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : "";
      if (!methodPath || !signatureStr) {
        return;
      }
      var IGNORE_ARG_SYMBOL = " ";
      var suppress = how === "abort" ? getAbortFunc() : function () {};
      var signatureMatcher;
      try {
        signatureMatcher = signatureStr.split("|").map(function (value) {
          return value === IGNORE_ARG_SYMBOL ? value : inferValue(value);
        });
      } catch (e) {
        logMessage(source, `Could not parse the signature matcher: ${getErrorMessage(e)}`);
        return;
      }
      var getPathParts = getPropertyInChain;
      var {
        base: base,
        chain: chain,
        prop: prop
      } = getPathParts(window, methodPath);
      if (typeof chain !== "undefined") {
        logMessage(source, `Could not reach the end of the prop chain: ${methodPath}`);
        return;
      }
      var nativeMethod = base[prop];
      if (!nativeMethod || typeof nativeMethod !== "function") {
        logMessage(source, `Could not retrieve the method: ${methodPath}`);
        return;
      }
      function matchMethodCall(nativeArguments, matchArguments) {
        return matchArguments.every(function (matcher, i) {
          if (matcher === IGNORE_ARG_SYMBOL) {
            return true;
          }
          var argument = nativeArguments[i];
          return isValueMatched(argument, matcher);
        });
      }
      var isMatchingSuspended = false;
      function apply(target, thisArg, argumentsList) {
        if (isMatchingSuspended) {
          return Reflect.apply(target, thisArg, argumentsList);
        }
        isMatchingSuspended = true;
        if (stack && !matchStackTrace(stack, new Error().stack || "")) {
          return Reflect.apply(target, thisArg, argumentsList);
        }
        var isMatching = matchMethodCall(argumentsList, signatureMatcher);
        isMatchingSuspended = false;
        if (isMatching) {
          hit(source);
          return suppress();
        }
        return Reflect.apply(target, thisArg, argumentsList);
      }
      base[prop] = new Proxy(nativeMethod, {
        apply: apply
      });
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function getPropertyInChain(base, chain) {
      var pos = chain.indexOf(".");
      if (pos === -1) {
        return {
          base: base,
          prop: chain
        };
      }
      var prop = chain.slice(0, pos);
      if (base === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      var nextBase = base[prop];
      chain = chain.slice(pos + 1);
      if ((base instanceof Object || typeof base === "object") && isEmptyObject(base)) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase === null) {
        return {
          base: base,
          prop: prop,
          chain: chain
        };
      }
      if (nextBase !== undefined) {
        return getPropertyInChain(nextBase, chain);
      }
      Object.defineProperty(base, prop, {
        configurable: true
      });
      return {
        base: base,
        prop: prop,
        chain: chain
      };
    }
    function inferValue(value) {
      if (value === "undefined") {
        return undefined;
      }
      if (value === "false") {
        return false;
      }
      if (value === "true") {
        return true;
      }
      if (value === "null") {
        return null;
      }
      if (value === "NaN") {
        return NaN;
      }
      if (value.startsWith("/") && value.endsWith("/")) {
        return toRegExp(value);
      }
      var MAX_ALLOWED_NUM = 32767;
      var numVal = Number(value);
      if (!nativeIsNaN(numVal)) {
        if (Math.abs(numVal) > MAX_ALLOWED_NUM) {
          throw new Error("number values bigger than 32767 are not allowed");
        }
        return numVal;
      }
      var errorMessage = `'${value}' value type can't be inferred`;
      try {
        var parsableVal = JSON.parse(value);
        if (parsableVal instanceof Object || typeof parsableVal === "string") {
          return parsableVal;
        }
      } catch (e) {
        errorMessage += `: ${e}`;
      }
      throw new TypeError(errorMessage);
    }
    function isValueMatched(value, matcher) {
      if (typeof value === "function") {
        return false;
      }
      if (nativeIsNaN(value)) {
        return nativeIsNaN(matcher);
      }
      if (value === null || typeof value === "undefined" || typeof value === "number" || typeof value === "boolean") {
        return value === matcher;
      }
      if (typeof value === "string") {
        if (typeof matcher === "string" || matcher instanceof RegExp) {
          return isStringMatched(value, matcher);
        }
        return false;
      }
      if (Array.isArray(value) && Array.isArray(matcher)) {
        return isArrayMatched(value, matcher);
      }
      if (isArbitraryObject(value) && isArbitraryObject(matcher)) {
        return isObjectMatched(value, matcher);
      }
      return false;
    }
    function getAbortFunc() {
      var rid = randomId();
      var isErrorHandlerSet = false;
      return function abort() {
        if (!isErrorHandlerSet) {
          window.onerror = createOnErrorHandler(rid);
          isErrorHandlerSet = true;
        }
        throw new ReferenceError(rid);
      };
    }
    function matchStackTrace(stackMatch, stackTrace) {
      if (!stackMatch || stackMatch === "") {
        return true;
      }
      var regExpValues = backupRegExpValues();
      if (shouldAbortInlineOrInjectedScript(stackMatch, stackTrace)) {
        if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
          restoreRegExpValues(regExpValues);
        }
        return true;
      }
      var stackRegexp = toRegExp(stackMatch);
      var refinedStackTrace = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      }).join("\n");
      if (regExpValues.length && regExpValues[0] !== RegExp.$1) {
        restoreRegExpValues(regExpValues);
      }
      return getNativeRegexpTest().call(stackRegexp, refinedStackTrace);
    }
    function getErrorMessage(error) {
      var isErrorWithMessage = function isErrorWithMessage(e) {
        return typeof e === "object" && e !== null && "message" in e && typeof e.message === "string";
      };
      if (isErrorWithMessage(error)) {
        return error.message;
      }
      try {
        return new Error(JSON.stringify(error)).message;
      } catch (_unused) {
        return new Error(String(error)).message;
      }
    }
    function shouldAbortInlineOrInjectedScript(stackMatch, stackTrace) {
      var INLINE_SCRIPT_STRING = "inlineScript";
      var INJECTED_SCRIPT_STRING = "injectedScript";
      var INJECTED_SCRIPT_MARKER = "<anonymous>";
      var isInlineScript = function isInlineScript(match) {
        return match.includes(INLINE_SCRIPT_STRING);
      };
      var isInjectedScript = function isInjectedScript(match) {
        return match.includes(INJECTED_SCRIPT_STRING);
      };
      if (!(isInlineScript(stackMatch) || isInjectedScript(stackMatch))) {
        return false;
      }
      var documentURL = window.location.href;
      var pos = documentURL.indexOf("#");
      if (pos !== -1) {
        documentURL = documentURL.slice(0, pos);
      }
      var stackSteps = stackTrace.split("\n").slice(2).map(function (line) {
        return line.trim();
      });
      var stackLines = stackSteps.map(function (line) {
        var stack;
        var getStackTraceValues = /(.*?@)?(\S+)(:\d+)(:\d+)\)?$/.exec(line);
        if (getStackTraceValues) {
          var _stackURL, _stackURL2;
          var stackURL = getStackTraceValues[2];
          var stackLine = getStackTraceValues[3];
          var stackCol = getStackTraceValues[4];
          if ((_stackURL = stackURL) !== null && _stackURL !== void 0 && _stackURL.startsWith("(")) {
            stackURL = stackURL.slice(1);
          }
          if ((_stackURL2 = stackURL) !== null && _stackURL2 !== void 0 && _stackURL2.startsWith(INJECTED_SCRIPT_MARKER)) {
            var _stackFunction;
            stackURL = INJECTED_SCRIPT_STRING;
            var stackFunction = getStackTraceValues[1] !== undefined ? getStackTraceValues[1].slice(0, -1) : line.slice(0, getStackTraceValues.index).trim();
            if ((_stackFunction = stackFunction) !== null && _stackFunction !== void 0 && _stackFunction.startsWith("at")) {
              stackFunction = stackFunction.slice(2).trim();
            }
            stack = `${stackFunction} ${stackURL}${stackLine}${stackCol}`.trim();
          } else if (stackURL === documentURL) {
            stack = `${INLINE_SCRIPT_STRING}${stackLine}${stackCol}`.trim();
          } else {
            stack = `${stackURL}${stackLine}${stackCol}`.trim();
          }
        } else {
          stack = line;
        }
        return stack;
      });
      if (stackLines) {
        for (var index = 0; index < stackLines.length; index += 1) {
          if (isInlineScript(stackMatch) && stackLines[index].startsWith(INLINE_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
          if (isInjectedScript(stackMatch) && stackLines[index].startsWith(INJECTED_SCRIPT_STRING) && stackLines[index].match(toRegExp(stackMatch))) {
            return true;
          }
        }
      }
      return false;
    }
    function getNativeRegexpTest() {
      var descriptor = Object.getOwnPropertyDescriptor(RegExp.prototype, "test");
      var nativeRegexTest = descriptor === null || descriptor === void 0 ? void 0 : descriptor.value;
      if (descriptor && typeof descriptor.value === "function") {
        return nativeRegexTest;
      }
      throw new Error("RegExp.prototype.test is not a function");
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function nativeIsNaN(num) {
      var native = Number.isNaN || window.isNaN;
      return native(num);
    }
    function randomId() {
      return Math.random().toString(36).slice(2, 9);
    }
    function createOnErrorHandler(rid) {
      var nativeOnError = window.onerror;
      return function onError(error) {
        if (typeof error === "string" && error.includes(rid)) {
          return true;
        }
        if (nativeOnError instanceof Function) {
          for (var _len = arguments.length, args = new Array(_len > 1 ? _len - 1 : 0), _key = 1; _key < _len; _key++) {
            args[_key - 1] = arguments[_key];
          }
          return nativeOnError.apply(window, [error, ...args]);
        }
        return false;
      };
    }
    function isEmptyObject(obj) {
      return Object.keys(obj).length === 0 && !obj.prototype;
    }
    function isArbitraryObject(value) {
      return value !== null && typeof value === "object" && !Array.isArray(value) && !(value instanceof RegExp);
    }
    function isStringMatched(str, matcher) {
      if (typeof matcher === "string") {
        if (matcher === "") {
          return str === matcher;
        }
        return str.includes(matcher);
      }
      if (matcher instanceof RegExp) {
        return matcher.test(str);
      }
      return false;
    }
    function isArrayMatched(array, matcher) {
      if (array.length === 0) {
        return matcher.length === 0;
      }
      if (matcher.length === 0) {
        return false;
      }
      var _loop = function _loop() {
          var matcherValue = matcher[i];
          var isMatching = array.some(function (arrItem) {
            return isValueMatched(arrItem, matcherValue);
          });
          if (!isMatching) {
            return {
              v: false
            };
          }
          return 0;
        },
        _ret;
      for (var i = 0; i < matcher.length; i += 1) {
        _ret = _loop();
        if (_ret === 0) continue;
        if (_ret) return _ret.v;
      }
      return true;
    }
    function isObjectMatched(obj, matcher) {
      var matcherKeys = Object.keys(matcher);
      for (var i = 0; i < matcherKeys.length; i += 1) {
        var key = matcherKeys[i];
        var value = obj[key];
        if (!isValueMatched(value, matcher[key])) {
          return false;
        }
        continue;
      }
      return true;
    }
    function backupRegExpValues() {
      try {
        var arrayOfRegexpValues = [];
        for (var index = 1; index < 10; index += 1) {
          var value = `$${index}`;
          if (!RegExp[value]) {
            break;
          }
          arrayOfRegexpValues.push(RegExp[value]);
        }
        return arrayOfRegexpValues;
      } catch (error) {
        return [];
      }
    }
    function restoreRegExpValues(array) {
      if (!array.length) {
        return;
      }
      try {
        var stringPattern = "";
        if (array.length === 1) {
          stringPattern = `(${array[0]})`;
        } else {
          stringPattern = array.reduce(function (accumulator, currentValue, currentIndex) {
            if (currentIndex === 1) {
              return `(${accumulator}),(${currentValue})`;
            }
            return `${accumulator},(${currentValue})`;
          });
        }
        var regExpGroup = new RegExp(stringPattern);
        array.toString().replace(regExpGroup, "");
      } catch (error) {
        var message = `Failed to restore RegExp values: ${error}`;
        console.log(message);
      }
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      trustedSuppressNativeMethod.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  function xmlPrune(source, args) {
    var flag = "done";
    var uniqueIdentifier = source.uniqueId + source.name + "_" + (Array.isArray(args) ? args.join("_") : "");
    if (source.uniqueId) {
      if (Window.prototype.toString[uniqueIdentifier] === flag) {
        return;
      }
    }
    function xmlPrune(source, propsToRemove) {
      var optionalProp = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : "";
      var urlToMatch = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : "";
      var verbose = arguments.length > 4 && arguments[4] !== undefined ? arguments[4] : false;
      if (typeof Reflect === "undefined" || typeof fetch === "undefined" || typeof Proxy === "undefined" || typeof Response === "undefined") {
        return;
      }
      var shouldPruneResponse = false;
      var shouldLogContent = verbose === "true";
      var urlMatchRegexp = toRegExp(urlToMatch);
      var XPATH_MARKER = "xpath(";
      var isXpath = propsToRemove && propsToRemove.startsWith(XPATH_MARKER);
      var getXPathElements = function getXPathElements(contextNode) {
        var matchedElements = [];
        try {
          var elementsToRemove = propsToRemove.slice(XPATH_MARKER.length, -1);
          var xpathResult = contextNode.evaluate(elementsToRemove, contextNode, null, XPathResult.UNORDERED_NODE_SNAPSHOT_TYPE, null);
          for (var i = 0; i < xpathResult.snapshotLength; i += 1) {
            matchedElements.push(xpathResult.snapshotItem(i));
          }
        } catch (ex) {
          var message = `Invalid XPath parameter: ${propsToRemove}\n${ex}`;
          logMessage(source, message);
        }
        return matchedElements;
      };
      var xPathPruning = function xPathPruning(xPathElements) {
        xPathElements.forEach(function (element) {
          if (element.nodeType === 1) {
            element.remove();
          } else if (element.nodeType === 2) {
            element.ownerElement.removeAttribute(element.nodeName);
          }
        });
      };
      var isXML = function isXML(text) {
        if (typeof text === "string") {
          var trimmedText = text.trim();
          if (trimmedText.startsWith("<") && trimmedText.endsWith(">")) {
            return true;
          }
        }
        return false;
      };
      var createXMLDocument = function createXMLDocument(text) {
        var xmlParser = new DOMParser();
        var xmlDocument = xmlParser.parseFromString(text, "text/xml");
        return xmlDocument;
      };
      var isPruningNeeded = function isPruningNeeded(response, propsToRemove) {
        if (!isXML(response)) {
          return false;
        }
        var docXML = createXMLDocument(response);
        return isXpath ? getXPathElements(docXML) : !!docXML.querySelector(propsToRemove);
      };
      var pruneXML = function pruneXML(text) {
        if (!isXML(text)) {
          shouldPruneResponse = false;
          return text;
        }
        var xmlDoc = createXMLDocument(text);
        var errorNode = xmlDoc.querySelector("parsererror");
        if (errorNode) {
          return text;
        }
        if (optionalProp !== "" && xmlDoc.querySelector(optionalProp) === null) {
          shouldPruneResponse = false;
          return text;
        }
        var elements = isXpath ? getXPathElements(xmlDoc) : xmlDoc.querySelectorAll(propsToRemove);
        if (!elements.length) {
          shouldPruneResponse = false;
          return text;
        }
        if (shouldLogContent) {
          var cloneXmlDoc = xmlDoc.cloneNode(true);
          logMessage(source, "Original xml:");
          logMessage(source, cloneXmlDoc, true, false);
        }
        if (isXpath) {
          xPathPruning(elements);
        } else {
          elements.forEach(function (elem) {
            elem.remove();
          });
        }
        if (shouldLogContent) {
          logMessage(source, "Modified xml:");
          logMessage(source, xmlDoc, true, false);
        }
        var serializer = new XMLSerializer();
        text = serializer.serializeToString(xmlDoc);
        return text;
      };
      var nativeOpen = window.XMLHttpRequest.prototype.open;
      var nativeSend = window.XMLHttpRequest.prototype.send;
      var xhrData;
      var openWrapper = function openWrapper(target, thisArg, args) {
        xhrData = getXhrData.apply(null, args);
        if (matchRequestProps(source, urlToMatch, xhrData)) {
          thisArg.shouldBePruned = true;
        }
        if (thisArg.shouldBePruned) {
          thisArg.collectedHeaders = [];
          var setRequestHeaderWrapper = function setRequestHeaderWrapper(target, thisArg, args) {
            thisArg.collectedHeaders.push(args);
            return Reflect.apply(target, thisArg, args);
          };
          var setRequestHeaderHandler = {
            apply: setRequestHeaderWrapper
          };
          thisArg.setRequestHeader = new Proxy(thisArg.setRequestHeader, setRequestHeaderHandler);
        }
        return Reflect.apply(target, thisArg, args);
      };
      var sendWrapper = function sendWrapper(target, thisArg, args) {
        var allowedResponseTypeValues = ["", "text"];
        if (!thisArg.shouldBePruned || !allowedResponseTypeValues.includes(thisArg.responseType)) {
          return Reflect.apply(target, thisArg, args);
        }
        var forgedRequest = new XMLHttpRequest();
        forgedRequest.addEventListener("readystatechange", function () {
          if (forgedRequest.readyState !== 4) {
            return;
          }
          var {
            readyState: readyState,
            response: response,
            responseText: responseText,
            responseURL: responseURL,
            responseXML: responseXML,
            status: status,
            statusText: statusText
          } = forgedRequest;
          var content = responseText || response;
          if (typeof content !== "string") {
            return;
          }
          if (!propsToRemove) {
            if (isXML(response)) {
              var message = `XMLHttpRequest.open() URL: ${responseURL}\nresponse: ${response}`;
              logMessage(source, message);
              logMessage(source, createXMLDocument(response), true, false);
            }
          } else {
            shouldPruneResponse = isPruningNeeded(response, propsToRemove);
          }
          var responseContent = shouldPruneResponse ? pruneXML(response) : response;
          Object.defineProperties(thisArg, {
            readyState: {
              value: readyState,
              writable: false
            },
            responseURL: {
              value: responseURL,
              writable: false
            },
            responseXML: {
              value: responseXML,
              writable: false
            },
            status: {
              value: status,
              writable: false
            },
            statusText: {
              value: statusText,
              writable: false
            },
            response: {
              value: responseContent,
              writable: false
            },
            responseText: {
              value: responseContent,
              writable: false
            }
          });
          setTimeout(function () {
            var stateEvent = new Event("readystatechange");
            thisArg.dispatchEvent(stateEvent);
            var loadEvent = new Event("load");
            thisArg.dispatchEvent(loadEvent);
            var loadEndEvent = new Event("loadend");
            thisArg.dispatchEvent(loadEndEvent);
          }, 1);
          hit(source);
        });
        nativeOpen.apply(forgedRequest, [xhrData.method, xhrData.url]);
        thisArg.collectedHeaders.forEach(function (header) {
          var name = header[0];
          var value = header[1];
          forgedRequest.setRequestHeader(name, value);
        });
        thisArg.collectedHeaders = [];
        try {
          nativeSend.call(forgedRequest, args);
        } catch (_unused) {
          return Reflect.apply(target, thisArg, args);
        }
        return undefined;
      };
      var openHandler = {
        apply: openWrapper
      };
      var sendHandler = {
        apply: sendWrapper
      };
      XMLHttpRequest.prototype.open = new Proxy(XMLHttpRequest.prototype.open, openHandler);
      XMLHttpRequest.prototype.send = new Proxy(XMLHttpRequest.prototype.send, sendHandler);
      var nativeFetch = window.fetch;
      var fetchWrapper = async function fetchWrapper(target, thisArg, args) {
        var fetchURL = args[0] instanceof Request ? args[0].url : args[0];
        if (typeof fetchURL !== "string" || fetchURL.length === 0) {
          return Reflect.apply(target, thisArg, args);
        }
        if (urlMatchRegexp.test(fetchURL)) {
          var response = await nativeFetch(...args);
          var clonedResponse = response.clone();
          var responseText = await response.text();
          shouldPruneResponse = isPruningNeeded(responseText, propsToRemove);
          if (!shouldPruneResponse) {
            var message = `fetch URL: ${fetchURL}\nresponse text: ${responseText}`;
            logMessage(source, message);
            logMessage(source, createXMLDocument(responseText), true, false);
            return clonedResponse;
          }
          var prunedText = pruneXML(responseText);
          if (shouldPruneResponse) {
            hit(source);
            return new Response(prunedText, {
              status: response.status,
              statusText: response.statusText,
              headers: response.headers
            });
          }
          return clonedResponse;
        }
        return Reflect.apply(target, thisArg, args);
      };
      var fetchHandler = {
        apply: fetchWrapper
      };
      window.fetch = new Proxy(window.fetch, fetchHandler);
    }
    function hit(source) {
      var ADGUARD_PREFIX = "[AdGuard]";
      if (!source.verbose) {
        return;
      }
      try {
        var trace = console.trace.bind(console);
        var label = `${ADGUARD_PREFIX} `;
        if (source.engine === "corelibs") {
          label += source.ruleText;
        } else {
          if (source.domainName) {
            label += `${source.domainName}`;
          }
          if (source.args) {
            label += `#%#//scriptlet('${source.name}', '${source.args.join("', '")}')`;
          } else {
            label += `#%#//scriptlet('${source.name}')`;
          }
        }
        if (trace) {
          trace(label);
        }
      } catch (e) {}
      if (typeof window.__debug === "function") {
        window.__debug(source);
      }
    }
    function logMessage(source, message) {
      var forced = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
      var convertMessageToString = arguments.length > 3 && arguments[3] !== undefined ? arguments[3] : true;
      var {
        name: name,
        verbose: verbose
      } = source;
      if (!forced && !verbose) {
        return;
      }
      var nativeConsole = console.log;
      if (!convertMessageToString) {
        nativeConsole(`${name}:`, message);
        return;
      }
      nativeConsole(`${name}: ${message}`);
    }
    function toRegExp(rawInput) {
      var input = rawInput || "";
      var DEFAULT_VALUE = ".?";
      var FORWARD_SLASH = "/";
      if (input === "") {
        return new RegExp(DEFAULT_VALUE);
      }
      var delimiterIndex = input.lastIndexOf(FORWARD_SLASH);
      var flagsPart = input.substring(delimiterIndex + 1);
      var regExpPart = input.substring(0, delimiterIndex + 1);
      var isValidRegExpFlag = function isValidRegExpFlag(flag) {
        if (!flag) {
          return false;
        }
        try {
          new RegExp("", flag);
          return true;
        } catch (ex) {
          return false;
        }
      };
      var getRegExpFlags = function getRegExpFlags(regExpStr, flagsStr) {
        if (regExpStr.startsWith(FORWARD_SLASH) && regExpStr.endsWith(FORWARD_SLASH) && !regExpStr.endsWith("\\/") && isValidRegExpFlag(flagsStr)) {
          return flagsStr;
        }
        return "";
      };
      var flags = getRegExpFlags(regExpPart, flagsPart);
      if (input.startsWith(FORWARD_SLASH) && input.endsWith(FORWARD_SLASH) || flags) {
        var regExpInput = flags ? regExpPart : input;
        return new RegExp(regExpInput.slice(1, -1), flags);
      }
      var escaped = input.replace(/\\'/g, "'").replace(/\\"/g, '"').replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      return new RegExp(escaped);
    }
    function getXhrData(method, url, async, user, password) {
      return {
        method: method,
        url: url,
        async: async,
        user: user,
        password: password
      };
    }
    function matchRequestProps(source, propsToMatch, requestData) {
      if (propsToMatch === "" || propsToMatch === "*") {
        return true;
      }
      var isMatched;
      var parsedData = parseMatchProps(propsToMatch);
      if (!isValidParsedData(parsedData)) {
        logMessage(source, `Invalid parameter: ${propsToMatch}`);
        isMatched = false;
      } else {
        var matchData = getMatchPropsData(parsedData);
        var matchKeys = Object.keys(matchData);
        isMatched = matchKeys.every(function (matchKey) {
          var matchValue = matchData[matchKey];
          var dataValue = requestData[matchKey];
          return Object.prototype.hasOwnProperty.call(requestData, matchKey) && typeof dataValue === "string" && (matchValue === null || matchValue === void 0 ? void 0 : matchValue.test(dataValue));
        });
      }
      return isMatched;
    }
    function getMatchPropsData(data) {
      var matchData = {};
      var dataKeys = Object.keys(data);
      dataKeys.forEach(function (key) {
        matchData[key] = toRegExp(data[key]);
      });
      return matchData;
    }
    function getRequestProps() {
      return ["url", "method", "headers", "body", "credentials", "cache", "redirect", "referrer", "referrerPolicy", "integrity", "keepalive", "signal", "mode"];
    }
    function isValidParsedData(data) {
      return Object.values(data).every(function (value) {
        return isValidStrPattern(value);
      });
    }
    function parseMatchProps(propsToMatchStr) {
      var PROPS_DIVIDER = " ";
      var PAIRS_MARKER = ":";
      var isRequestProp = function isRequestProp(prop) {
        return getRequestProps().includes(prop);
      };
      var propsObj = {};
      var props = propsToMatchStr.split(PROPS_DIVIDER);
      props.forEach(function (prop) {
        var dividerInd = prop.indexOf(PAIRS_MARKER);
        var key = prop.slice(0, dividerInd);
        if (isRequestProp(key)) {
          var value = prop.slice(dividerInd + 1);
          propsObj[key] = value;
        } else {
          propsObj.url = prop;
        }
      });
      return propsObj;
    }
    function isValidStrPattern(input) {
      var FORWARD_SLASH = "/";
      var str = escapeRegExp(input);
      if (input[0] === FORWARD_SLASH && input[input.length - 1] === FORWARD_SLASH) {
        str = input.slice(1, -1);
      }
      var isValid;
      try {
        isValid = new RegExp(str);
        isValid = true;
      } catch (e) {
        isValid = false;
      }
      return isValid;
    }
    function escapeRegExp(str) {
      return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    }
    var updatedArgs = args ? [].concat(source).concat(args) : [source];
    try {
      xmlPrune.apply(this, updatedArgs);
      if (source.uniqueId) {
        Object.defineProperty(Window.prototype.toString, uniqueIdentifier, {
          value: flag,
          enumerable: false,
          writable: false,
          configurable: false
        });
      }
    } catch (e) {
      console.log(e);
    }
  }
  var scriptletsMap = {
    "amazon-apstag": AmazonApstag,
    "ubo-amazon_apstag.js": AmazonApstag,
    "amazon_apstag.js": AmazonApstag,
    "didomi-loader": DidomiLoader,
    fingerprintjs2: Fingerprintjs2,
    "ubo-fingerprint2.js": Fingerprintjs2,
    "fingerprint2.js": Fingerprintjs2,
    fingerprintjs3: Fingerprintjs3,
    "ubo-fingerprint3.js": Fingerprintjs3,
    "fingerprint3.js": Fingerprintjs3,
    gemius: Gemius,
    "google-analytics-ga": GoogleAnalyticsGa,
    "ubo-google-analytics_ga.js": GoogleAnalyticsGa,
    "google-analytics_ga.js": GoogleAnalyticsGa,
    "google-analytics": GoogleAnalytics,
    "ubo-google-analytics_analytics.js": GoogleAnalytics,
    "google-analytics_analytics.js": GoogleAnalytics,
    "googletagmanager-gtm": GoogleAnalytics,
    "ubo-googletagmanager_gtm.js": GoogleAnalytics,
    "googletagmanager_gtm.js": GoogleAnalytics,
    "google-ima3": GoogleIma3,
    "ubo-google-ima.js": GoogleIma3,
    "google-ima.js": GoogleIma3,
    "googlesyndication-adsbygoogle": GoogleSyndicationAdsByGoogle,
    "ubo-googlesyndication_adsbygoogle.js": GoogleSyndicationAdsByGoogle,
    "googlesyndication_adsbygoogle.js": GoogleSyndicationAdsByGoogle,
    "googletagservices-gpt": GoogleTagServicesGpt,
    "ubo-googletagservices_gpt.js": GoogleTagServicesGpt,
    "googletagservices_gpt.js": GoogleTagServicesGpt,
    matomo: Matomo,
    "naver-wcslog": NaverWcslog,
    "pardot-1.0": Pardot,
    prebid: Prebid,
    "scorecardresearch-beacon": ScoreCardResearchBeacon,
    "ubo-scorecardresearch_beacon.js": ScoreCardResearchBeacon,
    "scorecardresearch_beacon.js": ScoreCardResearchBeacon,
    "abort-current-inline-script": abortCurrentInlineScript,
    "abort-current-script.js": abortCurrentInlineScript,
    "ubo-abort-current-script.js": abortCurrentInlineScript,
    "acs.js": abortCurrentInlineScript,
    "ubo-acs.js": abortCurrentInlineScript,
    "ubo-abort-current-script": abortCurrentInlineScript,
    "ubo-acs": abortCurrentInlineScript,
    "abort-current-inline-script.js": abortCurrentInlineScript,
    "ubo-abort-current-inline-script.js": abortCurrentInlineScript,
    "acis.js": abortCurrentInlineScript,
    "ubo-acis.js": abortCurrentInlineScript,
    "ubo-abort-current-inline-script": abortCurrentInlineScript,
    "ubo-acis": abortCurrentInlineScript,
    "abp-abort-current-inline-script": abortCurrentInlineScript,
    "abort-on-property-read": abortOnPropertyRead,
    "abort-on-property-read.js": abortOnPropertyRead,
    "ubo-abort-on-property-read.js": abortOnPropertyRead,
    "aopr.js": abortOnPropertyRead,
    "ubo-aopr.js": abortOnPropertyRead,
    "ubo-abort-on-property-read": abortOnPropertyRead,
    "ubo-aopr": abortOnPropertyRead,
    "abp-abort-on-property-read": abortOnPropertyRead,
    "abort-on-property-write": abortOnPropertyWrite,
    "abort-on-property-write.js": abortOnPropertyWrite,
    "ubo-abort-on-property-write.js": abortOnPropertyWrite,
    "aopw.js": abortOnPropertyWrite,
    "ubo-aopw.js": abortOnPropertyWrite,
    "ubo-abort-on-property-write": abortOnPropertyWrite,
    "ubo-aopw": abortOnPropertyWrite,
    "abp-abort-on-property-write": abortOnPropertyWrite,
    "abort-on-stack-trace": abortOnStackTrace,
    "abort-on-stack-trace.js": abortOnStackTrace,
    "ubo-abort-on-stack-trace.js": abortOnStackTrace,
    "aost.js": abortOnStackTrace,
    "ubo-aost.js": abortOnStackTrace,
    "ubo-abort-on-stack-trace": abortOnStackTrace,
    "ubo-aost": abortOnStackTrace,
    "abp-abort-on-stack-trace": abortOnStackTrace,
    "adjust-setInterval": adjustSetInterval,
    "nano-setInterval-booster.js": adjustSetInterval,
    "ubo-nano-setInterval-booster.js": adjustSetInterval,
    "nano-sib.js": adjustSetInterval,
    "ubo-nano-sib.js": adjustSetInterval,
    "adjust-setInterval.js": adjustSetInterval,
    "ubo-adjust-setInterval.js": adjustSetInterval,
    "ubo-nano-setInterval-booster": adjustSetInterval,
    "ubo-nano-sib": adjustSetInterval,
    "ubo-adjust-setInterval": adjustSetInterval,
    "adjust-setTimeout": adjustSetTimeout,
    "adjust-setTimeout.js": adjustSetTimeout,
    "ubo-adjust-setTimeout.js": adjustSetTimeout,
    "nano-setTimeout-booster.js": adjustSetTimeout,
    "ubo-nano-setTimeout-booster.js": adjustSetTimeout,
    "nano-stb.js": adjustSetTimeout,
    "ubo-nano-stb.js": adjustSetTimeout,
    "ubo-adjust-setTimeout": adjustSetTimeout,
    "ubo-nano-setTimeout-booster": adjustSetTimeout,
    "ubo-nano-stb": adjustSetTimeout,
    "call-nothrow": callNoThrow,
    "call-nothrow.js": callNoThrow,
    "ubo-call-nothrow.js": callNoThrow,
    "ubo-call-nothrow": callNoThrow,
    "debug-current-inline-script": debugCurrentInlineScript,
    "debug-on-property-read": debugOnPropertyRead,
    "debug-on-property-write": debugOnPropertyWrite,
    "dir-string": dirString,
    "disable-newtab-links": disableNewtabLinks,
    "disable-newtab-links.js": disableNewtabLinks,
    "ubo-disable-newtab-links.js": disableNewtabLinks,
    "ubo-disable-newtab-links": disableNewtabLinks,
    "evaldata-prune": evalDataPrune,
    "evaldata-prune.js": evalDataPrune,
    "ubo-evaldata-prune.js": evalDataPrune,
    "ubo-evaldata-prune": evalDataPrune,
    "close-window": forceWindowClose,
    "window-close-if.js": forceWindowClose,
    "ubo-window-close-if.js": forceWindowClose,
    "ubo-window-close-if": forceWindowClose,
    "close-window.js": forceWindowClose,
    "ubo-close-window.js": forceWindowClose,
    "ubo-close-window": forceWindowClose,
    "hide-in-shadow-dom": hideInShadowDom,
    "href-sanitizer": hrefSanitizer,
    "href-sanitizer.js": hrefSanitizer,
    "ubo-href-sanitizer.js": hrefSanitizer,
    "ubo-href-sanitizer": hrefSanitizer,
    "inject-css-in-shadow-dom": injectCssInShadowDom,
    "json-prune-fetch-response": jsonPruneFetchResponse,
    "json-prune-fetch-response.js": jsonPruneFetchResponse,
    "ubo-json-prune-fetch-response.js": jsonPruneFetchResponse,
    "ubo-json-prune-fetch-response": jsonPruneFetchResponse,
    "json-prune": jsonPrune,
    "json-prune.js": jsonPrune,
    "ubo-json-prune.js": jsonPrune,
    "ubo-json-prune": jsonPrune,
    "abp-json-prune": jsonPrune,
    "json-prune-xhr-response": jsonPruneXhrResponse,
    "json-prune-xhr-response.js": jsonPruneXhrResponse,
    "ubo-json-prune-xhr-response.js": jsonPruneXhrResponse,
    "ubo-json-prune-xhr-response": jsonPruneXhrResponse,
    "log-addEventListener": logAddEventListener,
    "addEventListener-logger.js": logAddEventListener,
    "ubo-addEventListener-logger.js": logAddEventListener,
    "aell.js": logAddEventListener,
    "ubo-aell.js": logAddEventListener,
    "ubo-addEventListener-logger": logAddEventListener,
    "ubo-aell": logAddEventListener,
    "log-eval": logEval,
    log: log$1,
    "abp-log": log$1,
    "log-on-stack-trace": logOnStackTrace,
    "m3u-prune": m3uPrune,
    "m3u-prune.js": m3uPrune,
    "ubo-m3u-prune.js": m3uPrune,
    "ubo-m3u-prune": m3uPrune,
    "metrika-yandex-tag": metrikaYandexTag,
    "metrika-yandex-watch": metrikaYandexWatch,
    "no-protected-audience": noProtectedAudience,
    "no-topics": noTopics,
    noeval: noeval,
    "noeval.js": noeval,
    "silent-noeval.js": noeval,
    "ubo-noeval.js": noeval,
    "ubo-silent-noeval.js": noeval,
    "ubo-noeval": noeval,
    "ubo-silent-noeval": noeval,
    nowebrtc: nowebrtc,
    "nowebrtc.js": nowebrtc,
    "ubo-nowebrtc.js": nowebrtc,
    "ubo-nowebrtc": nowebrtc,
    "prevent-addEventListener": preventAddEventListener,
    "addEventListener-defuser.js": preventAddEventListener,
    "ubo-addEventListener-defuser.js": preventAddEventListener,
    "aeld.js": preventAddEventListener,
    "ubo-aeld.js": preventAddEventListener,
    "ubo-addEventListener-defuser": preventAddEventListener,
    "ubo-aeld": preventAddEventListener,
    "abp-prevent-listener": preventAddEventListener,
    "prevent-adfly": preventAdfly,
    "prevent-bab": preventBab,
    "prevent-canvas": preventCanvas,
    "prevent-canvas.js": preventCanvas,
    "ubo-prevent-canvas.js": preventCanvas,
    "ubo-prevent-canvas": preventCanvas,
    "prevent-element-src-loading": preventElementSrcLoading,
    "prevent-eval-if": preventEvalIf,
    "noeval-if.js": preventEvalIf,
    "ubo-noeval-if.js": preventEvalIf,
    "ubo-noeval-if": preventEvalIf,
    "prevent-fab-3.2.0": preventFab,
    "nofab.js": preventFab,
    "ubo-nofab.js": preventFab,
    "fuckadblock.js-3.2.0": preventFab,
    "ubo-fuckadblock.js-3.2.0": preventFab,
    "ubo-nofab": preventFab,
    "prevent-fetch": preventFetch,
    "prevent-fetch.js": preventFetch,
    "ubo-prevent-fetch.js": preventFetch,
    "ubo-prevent-fetch": preventFetch,
    "no-fetch-if.js": preventFetch,
    "ubo-no-fetch-if.js": preventFetch,
    "ubo-no-fetch-if": preventFetch,
    "prevent-popads-net": preventPopadsNet,
    "popads.net.js": preventPopadsNet,
    "ubo-popads.net.js": preventPopadsNet,
    "ubo-popads.net": preventPopadsNet,
    "prevent-refresh": preventRefresh,
    "prevent-refresh.js": preventRefresh,
    "refresh-defuser.js": preventRefresh,
    "refresh-defuser": preventRefresh,
    "ubo-prevent-refresh.js": preventRefresh,
    "ubo-prevent-refresh": preventRefresh,
    "ubo-refresh-defuser.js": preventRefresh,
    "ubo-refresh-defuser": preventRefresh,
    "prevent-requestAnimationFrame": preventRequestAnimationFrame,
    "no-requestAnimationFrame-if.js": preventRequestAnimationFrame,
    "ubo-no-requestAnimationFrame-if.js": preventRequestAnimationFrame,
    "norafif.js": preventRequestAnimationFrame,
    "ubo-norafif.js": preventRequestAnimationFrame,
    "ubo-no-requestAnimationFrame-if": preventRequestAnimationFrame,
    "ubo-norafif": preventRequestAnimationFrame,
    "prevent-setInterval": preventSetInterval,
    "no-setInterval-if.js": preventSetInterval,
    "ubo-no-setInterval-if.js": preventSetInterval,
    "setInterval-defuser.js": preventSetInterval,
    "ubo-setInterval-defuser.js": preventSetInterval,
    "nosiif.js": preventSetInterval,
    "ubo-nosiif.js": preventSetInterval,
    "sid.js": preventSetInterval,
    "ubo-sid.js": preventSetInterval,
    "ubo-no-setInterval-if": preventSetInterval,
    "ubo-setInterval-defuser": preventSetInterval,
    "ubo-nosiif": preventSetInterval,
    "ubo-sid": preventSetInterval,
    "prevent-setTimeout": preventSetTimeout,
    "no-setTimeout-if.js": preventSetTimeout,
    "ubo-no-setTimeout-if.js": preventSetTimeout,
    "nostif.js": preventSetTimeout,
    "ubo-nostif.js": preventSetTimeout,
    "ubo-no-setTimeout-if": preventSetTimeout,
    "ubo-nostif": preventSetTimeout,
    "setTimeout-defuser.js": preventSetTimeout,
    "ubo-setTimeout-defuser.js": preventSetTimeout,
    "ubo-setTimeout-defuser": preventSetTimeout,
    "std.js": preventSetTimeout,
    "ubo-std.js": preventSetTimeout,
    "ubo-std": preventSetTimeout,
    "prevent-window-open": preventWindowOpen,
    "window.open-defuser.js": preventWindowOpen,
    "ubo-window.open-defuser.js": preventWindowOpen,
    "ubo-window.open-defuser": preventWindowOpen,
    "nowoif.js": preventWindowOpen,
    "ubo-nowoif.js": preventWindowOpen,
    "ubo-nowoif": preventWindowOpen,
    "no-window-open-if.js": preventWindowOpen,
    "ubo-no-window-open-if.js": preventWindowOpen,
    "ubo-no-window-open-if": preventWindowOpen,
    "prevent-xhr": preventXHR,
    "no-xhr-if.js": preventXHR,
    "ubo-no-xhr-if.js": preventXHR,
    "ubo-no-xhr-if": preventXHR,
    "remove-attr": removeAttr,
    "remove-attr.js": removeAttr,
    "ubo-remove-attr.js": removeAttr,
    "ra.js": removeAttr,
    "ubo-ra.js": removeAttr,
    "ubo-remove-attr": removeAttr,
    "ubo-ra": removeAttr,
    "remove-class": removeClass,
    "remove-class.js": removeClass,
    "ubo-remove-class.js": removeClass,
    "rc.js": removeClass,
    "ubo-rc.js": removeClass,
    "ubo-remove-class": removeClass,
    "ubo-rc": removeClass,
    "remove-cookie": removeCookie,
    "cookie-remover.js": removeCookie,
    "ubo-cookie-remover.js": removeCookie,
    "ubo-cookie-remover": removeCookie,
    "remove-cookie.js": removeCookie,
    "ubo-remove-cookie.js": removeCookie,
    "ubo-remove-cookie": removeCookie,
    "abp-cookie-remover": removeCookie,
    "remove-in-shadow-dom": removeInShadowDom,
    "remove-node-text": removeNodeText,
    "remove-node-text.js": removeNodeText,
    "ubo-remove-node-text.js": removeNodeText,
    "rmnt.js": removeNodeText,
    "ubo-rmnt.js": removeNodeText,
    "ubo-remove-node-text": removeNodeText,
    "ubo-rmnt": removeNodeText,
    "set-attr": setAttr,
    "set-attr.js": setAttr,
    "ubo-set-attr.js": setAttr,
    "ubo-set-attr": setAttr,
    "set-constant": setConstant,
    "set-constant.js": setConstant,
    "ubo-set-constant.js": setConstant,
    "set.js": setConstant,
    "ubo-set.js": setConstant,
    "ubo-set-constant": setConstant,
    "ubo-set": setConstant,
    "abp-override-property-read": setConstant,
    "set-cookie": setCookie,
    "set-cookie.js": setCookie,
    "ubo-set-cookie.js": setCookie,
    "ubo-set-cookie": setCookie,
    "set-cookie-reload": setCookieReload,
    "set-cookie-reload.js": setCookieReload,
    "ubo-set-cookie-reload.js": setCookieReload,
    "ubo-set-cookie-reload": setCookieReload,
    "set-local-storage-item": setLocalStorageItem,
    "set-local-storage-item.js": setLocalStorageItem,
    "ubo-set-local-storage-item.js": setLocalStorageItem,
    "ubo-set-local-storage-item": setLocalStorageItem,
    "set-popads-dummy": setPopadsDummy,
    "popads-dummy.js": setPopadsDummy,
    "ubo-popads-dummy.js": setPopadsDummy,
    "ubo-popads-dummy": setPopadsDummy,
    "set-session-storage-item": setSessionStorageItem,
    "set-session-storage-item.js": setSessionStorageItem,
    "ubo-set-session-storage-item.js": setSessionStorageItem,
    "ubo-set-session-storage-item": setSessionStorageItem,
    "spoof-css": spoofCSS,
    "spoof-css.js": spoofCSS,
    "ubo-spoof-css.js": spoofCSS,
    "ubo-spoof-css": spoofCSS,
    "trusted-click-element": trustedClickElement,
    "trusted-create-element": trustedCreateElement,
    "trusted-dispatch-event": trustedDispatchEvent,
    "trusted-prune-inbound-object": trustedPruneInboundObject,
    "trusted-replace-fetch-response": trustedReplaceFetchResponse,
    "trusted-replace-node-text": trustedReplaceNodeText,
    "trusted-replace-outbound-text": trustedReplaceOutboundText,
    "trusted-replace-xhr-response": trustedReplaceXhrResponse,
    "trusted-set-attr": trustedSetAttr,
    "trusted-set-constant": trustedSetConstant,
    "trusted-set-cookie": trustedSetCookie,
    "trusted-set-cookie-reload": trustedSetCookieReload,
    "trusted-set-local-storage-item": trustedSetLocalStorageItem,
    "trusted-set-session-storage-item": trustedSetSessionStorageItem,
    "trusted-suppress-native-method": trustedSuppressNativeMethod,
    "xml-prune": xmlPrune,
    "xml-prune.js": xmlPrune,
    "ubo-xml-prune.js": xmlPrune,
    "ubo-xml-prune": xmlPrune
  };
  var getScriptletFunction = function getScriptletFunction(name) {
    return scriptletsMap[name];
  };
  function passSourceAndProps(source, code) {
    var redirect = arguments.length > 2 && arguments[2] !== undefined ? arguments[2] : false;
    var sourceString = JSON.stringify(source);
    var argsString = source.args ? `[${source.args.map(function (arg) {
      return JSON.stringify(arg);
    })}]` : undefined;
    var params = argsString ? `${sourceString}, ${argsString}` : sourceString;
    if (redirect) {
      return `(function(source, args){\n${code}\n})(${params});`;
    }
    return `(${code})(${params});`;
  }
  function wrapInNonameFunc(code) {
    return `function(source, args){\n${code}\n}`;
  }
  function getScriptletCode$1(source) {
    var scriptletFunction = getScriptletFunction(source.name);
    if (typeof scriptletFunction !== "function") {
      throw new Error(`Error: cannot invoke scriptlet with name: '${source.name}'`);
    }
    var scriptletFunctionString = scriptletFunction.toString();
    var result = source.engine === "corelibs" || source.engine === "test" ? wrapInNonameFunc(scriptletFunctionString) : passSourceAndProps(source, scriptletFunctionString);
    return result;
  }
  var scriptlets = {
    invoke: getScriptletCode$1,
    getScriptletFunction: getScriptletFunction
  };

  /* eslint-disable @typescript-eslint/no-explicit-any */
  // currentLevel holds the active logging level.
  // It remains null until the logger is explicitly initialized.
  let currentLevel$1 = null;
  // logPrefix holds the configurable prefix for all log messages.
  let logPrefix$1 = '';
  // pendingLogs stores log messages that are buffered until the logger is
  // initialized. Each pending log is stored as an array so that it can be
  // re-spread into `console.log`.
  let pendingLogs$1 = [];
  /**
   * Logs messages with an ISO 8601 timestamp and a configurable prefix.
   *
   * This function accepts a variable number of parameters to mirror the interface
   * of `console.log`.
   *
   * Behavior:
   * - If the logger is not yet initialized (currentLevel is null), the log entry
   *   is buffered.
   * - If the logger is initialized with the 'log' level, the message is
   *   immediately output to the console with the configured prefix.
   * - If the logger is initialized with the 'discard' level, the log entry is
   *   ignored.
   *
   * @param args - The log message and additional parameters.
   */
  function log$2() {
    const timestamp = `[${new Date().toISOString()}]`;
    for (var _len3 = arguments.length, args = new Array(_len3), _key3 = 0; _key3 < _len3; _key3++) {
      args[_key3] = arguments[_key3];
    }
    if (currentLevel$1 === null) {
      // Buffer the message until the logger is initialized.
      pendingLogs$1.push([timestamp, ...args]);
    } else if (currentLevel$1 === 'log') {
      // Output the timestamp, prefix, and the log message.
      // eslint-disable-next-line no-console
      console.log(timestamp, logPrefix$1, ...args);
    }
    // If currentLevel is 'discard', the log entry is ignored.
  }
  /**
   * Initializes the logger by setting the logging behavior and the message
   * prefix.
   *
   * After initialization, future log messages behave according to the specified
   * logging level:
   *
   * - 'log': Future messages are immediately output to the console with the
   *          configured prefix, and any buffered messages are flushed.
   * - 'discard': Both buffered and future log messages are dropped.
   *
   * @param level - The logging level to set:
   *   - 'log' to output log messages.
   *   - 'discard' to ignore log messages.
   * @param prefix - The configurable prefix to be added to every log message.
   */
  function initLogger$1(level, prefix) {
    logPrefix$1 = prefix;
    currentLevel$1 = level;
    if (currentLevel$1 === 'log') {
      // Flush all buffered log messages to the console using the configured
      // prefix.
      pendingLogs$1.forEach(entry => {
        // eslint-disable-next-line no-console
        console.log(entry[0], logPrefix$1, ...entry.slice(1));
      });
    }
    // Clear the buffer regardless of the logging level.
    pendingLogs$1 = [];
  }
  const version = "3.0.0";

  /**
   * @file Contains the implementation of the content script.
   */
  /**
   * Executes code in the context of the page via new script tag and text content.
   *
   * @param {string} code String of scripts to be executed.
   * @returns {boolean} Returns true if code was executed, otherwise returns false.
   */
  const executeScriptsViaTextContent = code => {
    const scriptTag = document.createElement('script');
    scriptTag.setAttribute('type', 'text/javascript');
    scriptTag.textContent = code;
    const parent = document.head || document.documentElement;
    parent.appendChild(scriptTag);
    if (scriptTag.parentNode) {
      scriptTag.parentNode.removeChild(scriptTag);
      return false;
    }
    return true;
  };
  /**
   * Executes code in the context of page via new script tag and blob. We use
   * this way as a fallback if we fail to inject via textContent.
   *
   * @param {string} code String of scripts to be executed
   * @returns {boolean} Returns true if code was executed, otherwise returns false.
   */
  const executeScriptsViaBlob = code => {
    const blob = new Blob([code], {
      type: 'text/javascript'
    });
    const url = URL.createObjectURL(blob);
    const scriptTag = document.createElement('script');
    scriptTag.src = url;
    const parent = document.head || document.documentElement;
    parent.appendChild(scriptTag);
    URL.revokeObjectURL(url);
    if (scriptTag.parentNode) {
      scriptTag.parentNode.removeChild(scriptTag);
      return false;
    }
    return true;
  };
  /**
   * Execute scripts in a page context and cleanup itself when execution
   * completes.
   *
   * @param {string[]} scripts Array of scripts to execute.
   */
  const executeScripts = function () {
    let scripts = arguments.length > 0 && arguments[0] !== undefined ? arguments[0] : [];
    scripts.unshift('( function () { try {');
    // we use this script detect if the script was applied,
    // if the script tag was removed, then it means that code was applied, otherwise no
    scripts.push(';document.currentScript.remove();');
    scripts.push("} catch (ex) { console.error('Error executing AG js: ' + ex); } })();");
    const code = scripts.join('\r\n');
    if (!executeScriptsViaTextContent(code)) {
      if (!executeScriptsViaBlob(code)) {
        log$2('Failed to execute scripts');
      }
    }
  };
  /**
   * Applies JS injections.
   *
   * @param {string[]} scripts Array with JS scripts.
   */
  const applyScripts = scripts => {
    if (!scripts || scripts.length === 0) {
      return;
    }
    executeScripts(scripts);
  };
  /**
   * Protects specified style element from changes to the current document
   * Add a mutation observer, which is adds our rules again if it was removed
   *
   * @param {HTMLElement} protectStyleEl protected style element.
   */
  const protectStyleElementContent = protectStyleEl => {
    const {
      MutationObserver
    } = window;
    if (!MutationObserver) {
      return;
    }
    // Observer, which observe protectStyleEl inner changes, without deleting
    // styleEl.
    const innerObserver = new MutationObserver(mutations => {
      for (let i = 0; i < mutations.length; i += 1) {
        const m = mutations[i];
        if (protectStyleEl.hasAttribute('mod') && protectStyleEl.getAttribute('mod') === 'inner') {
          protectStyleEl.removeAttribute('mod');
          break;
        }
        protectStyleEl.setAttribute('mod', 'inner');
        let isProtectStyleElModified = false;
        // There are two mutually exclusive situations:
        //
        // 1. There were changes to the inner text of protectStyleEl.
        // 2. The whole "text" element of protectStyleEl was removed.
        if (m.removedNodes.length > 0) {
          for (let j = 0; j < m.removedNodes.length; j += 1) {
            isProtectStyleElModified = true;
            protectStyleEl.appendChild(m.removedNodes[j]);
          }
        } else if (m.oldValue) {
          isProtectStyleElModified = true;
          // eslint-disable-next-line no-param-reassign
          protectStyleEl.textContent = m.oldValue;
        }
        if (!isProtectStyleElModified) {
          protectStyleEl.removeAttribute('mod');
        }
      }
    });
    innerObserver.observe(protectStyleEl, {
      childList: true,
      characterData: true,
      subtree: true,
      characterDataOldValue: true
    });
  };
  /**
   * Makes sure that we're dealing with CSS rules (selector + style)
   *
   * @param {string[]} css Array of CSS selectors (for hiding elemets) or full CSS rules.
   * @returns {string[]} Array of CSS rules.
   */
  const toCSSRules = css => {
    return css.filter(s => s.length > 0).map(s => s.trim()).map(s => {
      return s[s.length - 1] !== '}' ? `${s} {display:none!important;}` : s;
    });
  };
  /**
   * Applies css stylesheet.
   *
   * @param {string[]} css Array of CSS rules to apply.
   */
  const applyCss = css => {
    if (!css || !css.length) {
      return;
    }
    try {
      const styleElement = document.createElement('style');
      styleElement.setAttribute('type', 'text/css');
      (document.head || document.documentElement).appendChild(styleElement);
      if (styleElement.sheet) {
        const cssRules = toCSSRules(css);
        for (const style of cssRules) {
          styleElement.sheet.insertRule(style);
        }
      }
      protectStyleElementContent(styleElement);
    } catch (e) {
      log$2('Failed to apply CSS', e);
    }
  };
  /**
   * Applies Extended Css stylesheet.
   *
   * @param {string[]} extendedCss Array with ExtendedCss rules.
   */
  const applyExtendedCss = extendedCss => {
    if (!extendedCss || !extendedCss.length) {
      return;
    }
    try {
      const cssRules = toCSSRules(extendedCss);
      const extCss = new ExtendedCss({
        cssRules
      });
      extCss.apply();
    } catch (e) {
      log$2('Failed to apply extended CSS', e);
    }
  };
  /**
   * Converts scriptlet to the code that can be executed.
   *
   * @param {Scriptlet} scriptlet Scriptlet data (name and arguments)
   * @param {boolean} verbose Whether to log verbose output
   * @returns {string} Scriptlet code
   */
  const getScriptletCode = (scriptlet, verbose) => {
    try {
      const scriptletSource = {
        engine: 'safari-extension',
        name: scriptlet.name,
        args: scriptlet.args,
        version: version,
        verbose
      };
      return scriptlets.invoke(scriptletSource);
    } catch (e) {
      log$2(`Failed to get scriptlet code ${scriptlet.name}`, e);
    }
    return '';
  };
  /**
   * Applies scriptlets.
   *
   * @param {Scriptlet[]} scriptlets Array with scriptlets data.
   * @param {boolean} verbose Whether to log verbose output.
   */
  const applyScriptlets = (scriptlets, verbose) => {
    if (!scriptlets || !scriptlets.length) {
      return;
    }
    const getCode = scriptlet => getScriptletCode(scriptlet, verbose);
    const scripts = scriptlets.map(getCode);
    executeScripts(scripts);
  };
  /**
   * Content script that applies all the rules from the configuration.
   */
  class ContentScript {
    constructor(configuration) {
      _defineProperty2(this, "configuration", void 0);
      this.configuration = configuration;
    }
    /**
     * Runs the content script on the page.
     *
     * @param verbose Whether to log verbose output.
     * @param prefix Prefix for log messages.
     */
    run() {
      let verbose = arguments.length > 0 && arguments[0] !== undefined ? arguments[0] : false;
      let prefix = arguments.length > 1 && arguments[1] !== undefined ? arguments[1] : '[AdGuard Extension]';
      if (verbose) {
        initLogger$1('log', prefix);
      } else {
        initLogger$1('discard', '');
      }
      log$2('Starting content script execution...');
      applyCss(this.configuration.css);
      applyExtendedCss(this.configuration.extendedCss);
      applyScriptlets(this.configuration.scriptlets, verbose);
      applyScripts(this.configuration.js);
      log$2('Finished content script execution');
    }
  }

  /* eslint-disable @typescript-eslint/no-explicit-any */
  // currentLevel holds the active logging level.
  // It remains null until the logger is explicitly initialized.
  let currentLevel = null;
  // logPrefix holds the configurable prefix for all log messages.
  let logPrefix = '';
  // pendingLogs stores log messages that are buffered until the logger is
  // initialized. Each pending log is stored as an array so that it can be
  // re-spread into `console.log`.
  let pendingLogs = [];
  /**
   * Logs messages with an ISO 8601 timestamp and a configurable prefix.
   *
   * This function accepts a variable number of parameters to mirror the interface
   * of `console.log`.
   *
   * Behavior:
   * - If the logger is not yet initialized (currentLevel is null), the log entry
   *   is buffered.
   * - If the logger is initialized with the 'log' level, the message is
   *   immediately output to the console with the configured prefix.
   * - If the logger is initialized with the 'discard' level, the log entry is
   *   ignored.
   *
   * @param args - The log message and additional parameters.
   */
  function log() {
    const timestamp = `[${new Date().toISOString()}]`;
    for (var _len4 = arguments.length, args = new Array(_len4), _key4 = 0; _key4 < _len4; _key4++) {
      args[_key4] = arguments[_key4];
    }
    if (currentLevel === null) {
      // Buffer the message until the logger is initialized.
      pendingLogs.push([timestamp, ...args]);
    } else if (currentLevel === 'log') {
      // Output the timestamp, prefix, and the log message.
      // eslint-disable-next-line no-console
      console.log(timestamp, logPrefix, ...args);
    }
    // If currentLevel is 'discard', the log entry is ignored.
  }
  /**
   * Initializes the logger by setting the logging behavior and the message
   * prefix.
   *
   * After initialization, future log messages behave according to the specified
   * logging level:
   *
   * - 'log': Future messages are immediately output to the console with the
   *          configured prefix, and any buffered messages are flushed.
   * - 'discard': Both buffered and future log messages are dropped.
   *
   * @param level - The logging level to set:
   *   - 'log' to output log messages.
   *   - 'discard' to ignore log messages.
   * @param prefix - The configurable prefix to be added to every log message.
   */
  function initLogger(level, prefix) {
    logPrefix = prefix;
    currentLevel = level;
    if (currentLevel === 'log') {
      // Flush all buffered log messages to the console using the configured
      // prefix.
      pendingLogs.forEach(entry => {
        // eslint-disable-next-line no-console
        console.log(entry[0], logPrefix, ...entry.slice(1));
      });
    }
    // Clear the buffer regardless of the logging level.
    pendingLogs = [];
  }

  /**
   * @file Handles delaying and dispatching of DOMContentLoaded and load events.
   */
  /**
   * The interceptors delay the events until either a response is received or the
   * timeout expires. If the events have already fired, no interceptors are added.
   *
   * @param timeout - Timeout in milliseconds after which the events are forced
   *                  (if not already handled).
   * @returns A function which, when invoked, cancels the timeout and dispatches
   *         (or removes) the interceptors.
   */
  function setupDelayedEventDispatcher() {
    let timeout = arguments.length > 0 && arguments[0] !== undefined ? arguments[0] : 100;
    const interceptors = [];
    const events = [{
      name: 'DOMContentLoaded',
      options: {
        bubbles: true,
        cancelable: false
      },
      target: document
    }, {
      name: 'load',
      options: {
        bubbles: false,
        cancelable: false
      },
      target: window
    }];
    events.forEach(ev => {
      const interceptor = {
        name: ev.name,
        options: ev.options,
        intercepted: false,
        target: ev.target,
        listener: event => {
          // Prevent immediate propagation.
          event.stopImmediatePropagation();
          interceptor.intercepted = true;
          log(`${ev.name} event has been intercepted.`);
        }
      };
      interceptors.push(interceptor);
      interceptor.target.addEventListener(ev.name, interceptor.listener, {
        capture: true
      });
    });
    let dispatched = false;
    const dispatchEvents = trigger => {
      if (dispatched) return;
      dispatched = true;
      interceptors.forEach(interceptor => {
        // Remove the interceptor listener.
        interceptor.target.removeEventListener(interceptor.name, interceptor.listener, {
          capture: true
        });
        if (interceptor.intercepted) {
          // If intercepted, dispatch the event manually so downstream listeners eventually receive it.
          const newEvent = new Event(interceptor.name, interceptor.options);
          interceptor.target.dispatchEvent(newEvent);
          const targetName = interceptor.target === document ? 'document' : 'window';
          log(`${interceptor.name} event re-dispatched due to ${trigger} on ${targetName}.`);
        } else {
          log(`Interceptor for ${interceptor.name} removed due to ${trigger}.`);
        }
      });
    };
    // Set a timer to automatically dispatch the events after the timeout.
    const timer = setTimeout(() => {
      dispatchEvents('timeout');
    }, timeout);
    // Return a function to cancel the timer and dispatch events immediately.
    return () => {
      clearTimeout(timer);
      dispatchEvents('response received');
    };
  }

  /**
   * @file App extension content script.
   *
   * The script initializes content script functionality by listening
   * for messages from the Safari extension. It uses a delayed dispatcher
   * to handle DOM events and sends a rule request message to the extension.
   */
  log('Content script is starting...');
  // Initialize the delayed event dispatcher. This may intercept DOMContentLoaded
  // and load events. The delay of 100ms is used as a buffer to capture critical
  // initial events while waiting for the rules response.
  const cancelDelayedDispatchAndDispatch = setupDelayedEventDispatcher(100);
  // Generate a pseudo-unique request ID for properly tracing the response to the
  // request that was sent by this instance of a SFSafariContentScript.
  // We will only accept responses to this specific request.
  const requestId = Math.random().toString(36);
  /**
   * Callback function to handle response messages from the Safari extension.
   *
   * This function processes the rules response message:
   * - If a configuration payload is received, it instantiates and runs the
   *   ContentScript.
   * - It logs the elapsed time between the request and the response for
   *   performance monitoring.
   * - It toggles verbose logging based on the configuration included in
   *   the response.
   * - It cancels any pending delayed event dispatch logic to allow the page's
   *   natural event flow.
   *
   * @param event SafariExtensionMessageEvent - The message event from the
   * extension.
   */
  const handleMessage = event => {
    log('Received message: ', event);
    // Cast the received event message to our expected
    // RequestRulesResponseMessage type.
    const message = event.message;
    if ((message === null || message === void 0 ? void 0 : message.requestId) !== requestId) {
      log('Received response for a different request ID: ', message === null || message === void 0 ? void 0 : message.requestId);
      return;
    }
    // If the configuration payload exists, run the ContentScript with it.
    if (message !== null && message !== void 0 && message.payload) {
      const configuration = message.payload;
      new ContentScript(configuration).run();
      log('ContentScript applied');
    }
    // Compute the elapsed time since the rules request was initiated.
    const elapsed = new Date().getTime() - ((message === null || message === void 0 ? void 0 : message.requestedAt) ?? 0);
    log('Elapsed on messaging: ', elapsed);
    // Initialize the logger using the verbose flag from the response:
    // If verbose, use a prefix; otherwise, disable logging.
    if (message !== null && message !== void 0 && message.verbose) {
      initLogger('log', '[AdGuard Sample App Extension]');
    } else {
      initLogger('discard', '');
    }
    // Cancel the pending delayed event dispatch and process any queued events.
    cancelDelayedDispatchAndDispatch();
  };
  /**
   * Returns the top-level URL of the current page or null if we're not
   * in an iframe.
   *
   * @returns {string | null} The top-level URL or null if we're not in an iframe.
   */
  function getTopUrl() {
    try {
      if (window.top === window.self) {
        return null;
      }
      if (!window.top) {
        // window.top cannot be null under normal circumstances so assume
        // we're in an iframe.
        return 'https://third-party-domain.com/';
      }
      return window.top.location.href;
    } catch (ex) {
      log('Failed to get top URL: ', ex);
      // Return a random third-party domain as this error signals us
      // that we're in a third-party frame.
      return 'https://third-party-domain.com/';
    }
  }
  // Prepare the message to request configuration rules for the current page.
  const message = {
    requestId,
    url: window.location.href,
    topUrl: getTopUrl(),
    requestedAt: new Date().getTime()
  };
  // Dispatch the "requestRules" message to the Safari extension.
  safari.extension.dispatchMessage('requestRules', message);
  // Register the event listener for incoming messages from the extension.
  safari.self.addEventListener('message', handleMessage);
})();
