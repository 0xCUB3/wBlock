"use strict";
var ExtendedCss = (() => {
  var __defProp = Object.defineProperty;
  var __name = (target, value) =>
    __defProp(target, "name", { value, configurable: true });

  // src/selector/nodes.ts
  var NODE = {
    SELECTOR_LIST: "SelectorList",
    SELECTOR: "Selector",
    REGULAR_SELECTOR: "RegularSelector",
    EXTENDED_SELECTOR: "ExtendedSelector",
    ABSOLUTE_PSEUDO_CLASS: "AbsolutePseudoClass",
    RELATIVE_PSEUDO_CLASS: "RelativePseudoClass",
  };
  var AnySelectorNode = class {
    constructor(type) {
      this.children = [];
      this.type = type;
    }
    addChild(child) {
      this.children.push(child);
    }
  };
  __name(AnySelectorNode, "AnySelectorNode");
  var RegularSelectorNode = class extends AnySelectorNode {
    constructor(value) {
      super(NODE.REGULAR_SELECTOR);
      this.value = value;
    }
  };
  __name(RegularSelectorNode, "RegularSelectorNode");
  var RelativePseudoClassNode = class extends AnySelectorNode {
    constructor(name) {
      super(NODE.RELATIVE_PSEUDO_CLASS);
      this.name = name;
    }
  };
  __name(RelativePseudoClassNode, "RelativePseudoClassNode");
  var AbsolutePseudoClassNode = class extends AnySelectorNode {
    constructor(name) {
      super(NODE.ABSOLUTE_PSEUDO_CLASS);
      this.value = "";
      this.name = name;
    }
  };
  __name(AbsolutePseudoClassNode, "AbsolutePseudoClassNode");

  // package.json
  var version = "2.1.1";

  // src/common/constants.ts
  var EXTENDED_CSS_VERSION = version;
  var LEFT_SQUARE_BRACKET = "[";
  var RIGHT_SQUARE_BRACKET = "]";
  var LEFT_PARENTHESIS = "(";
  var RIGHT_PARENTHESIS = ")";
  var LEFT_CURLY_BRACKET = "{";
  var RIGHT_CURLY_BRACKET = "}";
  var BRACKET = {
    SQUARE: {
      LEFT: LEFT_SQUARE_BRACKET,
      RIGHT: RIGHT_SQUARE_BRACKET,
    },
    PARENTHESES: {
      LEFT: LEFT_PARENTHESIS,
      RIGHT: RIGHT_PARENTHESIS,
    },
    CURLY: {
      LEFT: LEFT_CURLY_BRACKET,
      RIGHT: RIGHT_CURLY_BRACKET,
    },
  };
  var SLASH = "/";
  var BACKSLASH = "\\";
  var SPACE = " ";
  var COMMA = ",";
  var DOT = ".";
  var SEMICOLON = ";";
  var COLON = ":";
  var SINGLE_QUOTE = "'";
  var DOUBLE_QUOTE = '"';
  var CARET = "^";
  var DOLLAR_SIGN = "$";
  var EQUAL_SIGN = "=";
  var TAB = "	";
  var CARRIAGE_RETURN = "\r";
  var LINE_FEED = "\n";
  var FORM_FEED = "\f";
  var WHITE_SPACE_CHARACTERS = [
    SPACE,
    TAB,
    CARRIAGE_RETURN,
    LINE_FEED,
    FORM_FEED,
  ];
  var ASTERISK = "*";
  var ID_MARKER = "#";
  var CLASS_MARKER = DOT;
  var DESCENDANT_COMBINATOR = SPACE;
  var CHILD_COMBINATOR = ">";
  var NEXT_SIBLING_COMBINATOR = "+";
  var SUBSEQUENT_SIBLING_COMBINATOR = "~";
  var COMBINATORS = [
    DESCENDANT_COMBINATOR,
    CHILD_COMBINATOR,
    NEXT_SIBLING_COMBINATOR,
    SUBSEQUENT_SIBLING_COMBINATOR,
  ];
  var SUPPORTED_SELECTOR_MARKS = [
    LEFT_SQUARE_BRACKET,
    RIGHT_SQUARE_BRACKET,
    LEFT_PARENTHESIS,
    RIGHT_PARENTHESIS,
    LEFT_CURLY_BRACKET,
    RIGHT_CURLY_BRACKET,
    SLASH,
    BACKSLASH,
    SEMICOLON,
    COLON,
    COMMA,
    SINGLE_QUOTE,
    DOUBLE_QUOTE,
    CARET,
    DOLLAR_SIGN,
    ASTERISK,
    ID_MARKER,
    CLASS_MARKER,
    DESCENDANT_COMBINATOR,
    CHILD_COMBINATOR,
    NEXT_SIBLING_COMBINATOR,
    SUBSEQUENT_SIBLING_COMBINATOR,
    TAB,
    CARRIAGE_RETURN,
    LINE_FEED,
    FORM_FEED,
  ];
  var SUPPORTED_STYLE_DECLARATION_MARKS = [
    COLON,
    SEMICOLON,
    SINGLE_QUOTE,
    DOUBLE_QUOTE,
    BACKSLASH,
    SPACE,
    TAB,
    CARRIAGE_RETURN,
    LINE_FEED,
    FORM_FEED,
  ];
  var CONTAINS_PSEUDO = "contains";
  var HAS_TEXT_PSEUDO = "has-text";
  var ABP_CONTAINS_PSEUDO = "-abp-contains";
  var MATCHES_CSS_PSEUDO = "matches-css";
  var MATCHES_CSS_BEFORE_PSEUDO = "matches-css-before";
  var MATCHES_CSS_AFTER_PSEUDO = "matches-css-after";
  var MATCHES_ATTR_PSEUDO_CLASS_MARKER = "matches-attr";
  var MATCHES_PROPERTY_PSEUDO_CLASS_MARKER = "matches-property";
  var XPATH_PSEUDO_CLASS_MARKER = "xpath";
  var NTH_ANCESTOR_PSEUDO_CLASS_MARKER = "nth-ancestor";
  var CONTAINS_PSEUDO_NAMES = [
    CONTAINS_PSEUDO,
    HAS_TEXT_PSEUDO,
    ABP_CONTAINS_PSEUDO,
  ];
  var UPWARD_PSEUDO_CLASS_MARKER = "upward";
  var REMOVE_PSEUDO_MARKER = "remove";
  var HAS_PSEUDO_CLASS_MARKER = "has";
  var ABP_HAS_PSEUDO_CLASS_MARKER = "-abp-has";
  var HAS_PSEUDO_CLASS_MARKERS = [
    HAS_PSEUDO_CLASS_MARKER,
    ABP_HAS_PSEUDO_CLASS_MARKER,
  ];
  var IS_PSEUDO_CLASS_MARKER = "is";
  var NOT_PSEUDO_CLASS_MARKER = "not";
  var ABSOLUTE_PSEUDO_CLASSES = [
    CONTAINS_PSEUDO,
    HAS_TEXT_PSEUDO,
    ABP_CONTAINS_PSEUDO,
    MATCHES_CSS_PSEUDO,
    MATCHES_CSS_BEFORE_PSEUDO,
    MATCHES_CSS_AFTER_PSEUDO,
    MATCHES_ATTR_PSEUDO_CLASS_MARKER,
    MATCHES_PROPERTY_PSEUDO_CLASS_MARKER,
    XPATH_PSEUDO_CLASS_MARKER,
    NTH_ANCESTOR_PSEUDO_CLASS_MARKER,
    UPWARD_PSEUDO_CLASS_MARKER,
  ];
  var RELATIVE_PSEUDO_CLASSES = [
    ...HAS_PSEUDO_CLASS_MARKERS,
    IS_PSEUDO_CLASS_MARKER,
    NOT_PSEUDO_CLASS_MARKER,
  ];
  var SUPPORTED_PSEUDO_CLASSES = [
    ...ABSOLUTE_PSEUDO_CLASSES,
    ...RELATIVE_PSEUDO_CLASSES,
  ];
  var OPTIMIZATION_PSEUDO_CLASSES = [
    NOT_PSEUDO_CLASS_MARKER,
    IS_PSEUDO_CLASS_MARKER,
  ];
  var SCOPE_CSS_PSEUDO_CLASS = ":scope";
  var REGULAR_PSEUDO_ELEMENTS = {
    AFTER: "after",
    BACKDROP: "backdrop",
    BEFORE: "before",
    CUE: "cue",
    CUE_REGION: "cue-region",
    FIRST_LETTER: "first-letter",
    FIRST_LINE: "first-line",
    FILE_SELECTION_BUTTON: "file-selector-button",
    GRAMMAR_ERROR: "grammar-error",
    MARKER: "marker",
    PART: "part",
    PLACEHOLDER: "placeholder",
    SELECTION: "selection",
    SLOTTED: "slotted",
    SPELLING_ERROR: "spelling-error",
    TARGET_TEXT: "target-text",
  };
  var AT_RULE_MARKER = "@";
  var CONTENT_CSS_PROPERTY = "content";
  var PSEUDO_PROPERTY_POSITIVE_VALUE = "true";
  var DEBUG_PSEUDO_PROPERTY_GLOBAL_VALUE = "global";
  var NO_SELECTOR_ERROR_PREFIX = "Selector should be defined";
  var STYLE_ERROR_PREFIX = {
    NO_STYLE: "No style declaration found",
    NO_SELECTOR: `${NO_SELECTOR_ERROR_PREFIX} before style declaration in stylesheet`,
    INVALID_STYLE: "Invalid style declaration",
    UNCLOSED_STYLE: "Unclosed style declaration",
    NO_PROPERTY: "Missing style property in declaration",
    NO_VALUE: "Missing style value in declaration",
    NO_STYLE_OR_REMOVE:
      "Style should be declared or :remove() pseudo-class should used",
    NO_COMMENT: "Comments are not supported",
  };
  var NO_AT_RULE_ERROR_PREFIX = "At-rules are not supported";
  var REMOVE_ERROR_PREFIX = {
    INVALID_REMOVE: "Invalid :remove() pseudo-class in selector",
    NO_TARGET_SELECTOR: `${NO_SELECTOR_ERROR_PREFIX} before :remove() pseudo-class`,
    MULTIPLE_USAGE: "Pseudo-class :remove() appears more than once in selector",
    INVALID_POSITION: "Pseudo-class :remove() should be at the end of selector",
  };
  var MATCHING_ELEMENT_ERROR_PREFIX = "Error while matching element";
  var MAX_STYLE_PROTECTION_COUNT = 50;

  // src/selector/converter.ts
  var REGEXP_VALID_OLD_SYNTAX =
    /\[-(?:ext)-([a-z-_]+)=(["'])((?:(?=(\\?))\4.)*?)\2\]/g;
  var INVALID_OLD_SYNTAX_MARKER = "[-ext-";
  var evaluateMatch = /* @__PURE__ */ __name(
    (match, name, quoteChar, rawValue) => {
      const re = new RegExp(`([^\\\\]|^)\\\\${quoteChar}`, "g");
      const value = rawValue.replace(re, `$1${quoteChar}`);
      return `:${name}(${value})`;
    },
    "evaluateMatch",
  );
  var SCOPE_MARKER_REGEXP = /\(:scope >/g;
  var SCOPE_REPLACER = "(>";
  var MATCHES_CSS_PSEUDO_ELEMENT_REGEXP = /(:matches-css)-(before|after)\(/g;
  var convertMatchesCss = /* @__PURE__ */ __name(
    (match, extendedPseudoClass, regularPseudoElement) => {
      return `${extendedPseudoClass}${BRACKET.PARENTHESES.LEFT}${regularPseudoElement}${COMMA}`;
    },
    "convertMatchesCss",
  );
  var normalize = /* @__PURE__ */ __name((selector) => {
    const normalizedSelector = selector
      .replace(REGEXP_VALID_OLD_SYNTAX, evaluateMatch)
      .replace(SCOPE_MARKER_REGEXP, SCOPE_REPLACER)
      .replace(MATCHES_CSS_PSEUDO_ELEMENT_REGEXP, convertMatchesCss);
    if (normalizedSelector.includes(INVALID_OLD_SYNTAX_MARKER)) {
      throw new Error(
        `Invalid extended-css old syntax selector: '${selector}'`,
      );
    }
    return normalizedSelector;
  }, "normalize");
  var convert = /* @__PURE__ */ __name((rawSelector) => {
    const trimmedSelector = rawSelector.trim();
    return normalize(trimmedSelector);
  }, "convert");

  // src/common/tokenizer.ts
  var TOKEN_TYPE = {
    MARK: "mark",
    WORD: "word",
  };
  var tokenize = /* @__PURE__ */ __name((input, supportedMarks) => {
    let wordBuffer = "";
    const tokens = [];
    const selectorSymbols = input.split("");
    selectorSymbols.forEach((symbol) => {
      if (supportedMarks.includes(symbol)) {
        if (wordBuffer.length > 0) {
          tokens.push({ type: TOKEN_TYPE.WORD, value: wordBuffer });
          wordBuffer = "";
        }
        tokens.push({ type: TOKEN_TYPE.MARK, value: symbol });
        return;
      }
      wordBuffer += symbol;
    });
    if (wordBuffer.length > 0) {
      tokens.push({ type: TOKEN_TYPE.WORD, value: wordBuffer });
    }
    return tokens;
  }, "tokenize");

  // src/selector/tokenizer.ts
  var tokenizeSelector = /* @__PURE__ */ __name((rawSelector) => {
    const selector = convert(rawSelector);
    return tokenize(selector, SUPPORTED_SELECTOR_MARKS);
  }, "tokenizeSelector");
  var tokenizeAttribute = /* @__PURE__ */ __name((attribute) => {
    return tokenize(attribute, [...SUPPORTED_SELECTOR_MARKS, EQUAL_SIGN]);
  }, "tokenizeAttribute");

  // src/common/utils/arrays.ts
  var flatten = /* @__PURE__ */ __name((input) => {
    const stack = [];
    input.forEach((el) => stack.push(el));
    const res = [];
    while (stack.length) {
      const next = stack.pop();
      if (!next) {
        throw new Error("Unable to make array flat");
      }
      if (Array.isArray(next)) {
        next.forEach((el) => stack.push(el));
      } else {
        res.push(next);
      }
    }
    return res.reverse();
  }, "flatten");
  var getFirst = /* @__PURE__ */ __name((array) => {
    return array[0];
  }, "getFirst");
  var getLast = /* @__PURE__ */ __name((array) => {
    return array[array.length - 1];
  }, "getLast");
  var getPrevToLast = /* @__PURE__ */ __name((array) => {
    return array[array.length - 2];
  }, "getPrevToLast");
  var getItemByIndex = /* @__PURE__ */ __name((array, index, errorMessage) => {
    const indexChild = array[index];
    if (!indexChild) {
      throw new Error(errorMessage || `No array item found by index ${index}`);
    }
    return indexChild;
  }, "getItemByIndex");

  // src/selector/utils/ast-node-helpers.ts
  var NO_REGULAR_SELECTOR_ERROR =
    "At least one of Selector node children should be RegularSelector";
  var isSelectorListNode = /* @__PURE__ */ __name((astNode) => {
    return astNode?.type === NODE.SELECTOR_LIST;
  }, "isSelectorListNode");
  var isSelectorNode = /* @__PURE__ */ __name((astNode) => {
    return astNode?.type === NODE.SELECTOR;
  }, "isSelectorNode");
  var isRegularSelectorNode = /* @__PURE__ */ __name((astNode) => {
    return astNode?.type === NODE.REGULAR_SELECTOR;
  }, "isRegularSelectorNode");
  var isExtendedSelectorNode = /* @__PURE__ */ __name((astNode) => {
    return astNode.type === NODE.EXTENDED_SELECTOR;
  }, "isExtendedSelectorNode");
  var isAbsolutePseudoClassNode = /* @__PURE__ */ __name((astNode) => {
    return astNode?.type === NODE.ABSOLUTE_PSEUDO_CLASS;
  }, "isAbsolutePseudoClassNode");
  var isRelativePseudoClassNode = /* @__PURE__ */ __name((astNode) => {
    return astNode?.type === NODE.RELATIVE_PSEUDO_CLASS;
  }, "isRelativePseudoClassNode");
  var getNodeName = /* @__PURE__ */ __name((astNode) => {
    if (astNode === null) {
      throw new Error("Ast node should be defined");
    }
    if (
      !isAbsolutePseudoClassNode(astNode) &&
      !isRelativePseudoClassNode(astNode)
    ) {
      throw new Error(
        "Only AbsolutePseudoClass or RelativePseudoClass ast node can have a name",
      );
    }
    if (!astNode.name) {
      throw new Error("Extended pseudo-class should have a name");
    }
    return astNode.name;
  }, "getNodeName");
  var getNodeValue = /* @__PURE__ */ __name((astNode, errorMessage) => {
    if (astNode === null) {
      throw new Error("Ast node should be defined");
    }
    if (
      !isRegularSelectorNode(astNode) &&
      !isAbsolutePseudoClassNode(astNode)
    ) {
      throw new Error(
        "Only RegularSelector ot AbsolutePseudoClass ast node can have a value",
      );
    }
    if (!astNode.value) {
      throw new Error(
        errorMessage ||
          "Ast RegularSelector ot AbsolutePseudoClass node should have a value",
      );
    }
    return astNode.value;
  }, "getNodeValue");
  var getRegularSelectorNodes = /* @__PURE__ */ __name((children) => {
    return children.filter(isRegularSelectorNode);
  }, "getRegularSelectorNodes");
  var getFirstRegularChild = /* @__PURE__ */ __name(
    (children, errorMessage) => {
      const regularSelectorNodes = getRegularSelectorNodes(children);
      const firstRegularSelectorNode = getFirst(regularSelectorNodes);
      if (!firstRegularSelectorNode) {
        throw new Error(errorMessage || NO_REGULAR_SELECTOR_ERROR);
      }
      return firstRegularSelectorNode;
    },
    "getFirstRegularChild",
  );
  var getLastRegularChild = /* @__PURE__ */ __name((children) => {
    const regularSelectorNodes = getRegularSelectorNodes(children);
    const lastRegularSelectorNode = getLast(regularSelectorNodes);
    if (!lastRegularSelectorNode) {
      throw new Error(NO_REGULAR_SELECTOR_ERROR);
    }
    return lastRegularSelectorNode;
  }, "getLastRegularChild");
  var getNodeOnlyChild = /* @__PURE__ */ __name((node, errorMessage) => {
    if (node.children.length !== 1) {
      throw new Error(errorMessage);
    }
    const onlyChild = getFirst(node.children);
    if (!onlyChild) {
      throw new Error(errorMessage);
    }
    return onlyChild;
  }, "getNodeOnlyChild");
  var getPseudoClassNode = /* @__PURE__ */ __name((extendedSelectorNode) => {
    return getNodeOnlyChild(
      extendedSelectorNode,
      "Extended selector should be specified",
    );
  }, "getPseudoClassNode");
  var getRelativeSelectorListNode = /* @__PURE__ */ __name(
    (pseudoClassNode) => {
      if (!isRelativePseudoClassNode(pseudoClassNode)) {
        throw new Error(
          "Only RelativePseudoClass node can have relative SelectorList node as child",
        );
      }
      return getNodeOnlyChild(
        pseudoClassNode,
        `Missing arg for :${getNodeName(pseudoClassNode)}() pseudo-class`,
      );
    },
    "getRelativeSelectorListNode",
  );

  // src/selector/utils/parser-predicates.ts
  var ATTRIBUTE_CASE_INSENSITIVE_FLAG = "i";
  var POSSIBLE_MARKS_BEFORE_REGEXP = {
    COMMON: [
      BRACKET.PARENTHESES.LEFT,
      SINGLE_QUOTE,
      DOUBLE_QUOTE,
      EQUAL_SIGN,
      DOT,
      COLON,
      SPACE,
    ],
    CONTAINS: [BRACKET.PARENTHESES.LEFT, SINGLE_QUOTE, DOUBLE_QUOTE],
  };
  var isSupportedPseudoClass = /* @__PURE__ */ __name((tokenValue) => {
    return SUPPORTED_PSEUDO_CLASSES.includes(tokenValue);
  }, "isSupportedPseudoClass");
  var isOptimizationPseudoClass = /* @__PURE__ */ __name((name) => {
    return OPTIMIZATION_PSEUDO_CLASSES.includes(name);
  }, "isOptimizationPseudoClass");
  var doesRegularContinueAfterSpace = /* @__PURE__ */ __name(
    (nextTokenType, nextTokenValue) => {
      if (!nextTokenType || !nextTokenValue) {
        return false;
      }
      return (
        COMBINATORS.includes(nextTokenValue) ||
        nextTokenType === TOKEN_TYPE.WORD ||
        nextTokenValue === ASTERISK ||
        nextTokenValue === ID_MARKER ||
        nextTokenValue === CLASS_MARKER ||
        nextTokenValue === COLON ||
        nextTokenValue === SINGLE_QUOTE ||
        nextTokenValue === DOUBLE_QUOTE ||
        nextTokenValue === BRACKET.SQUARE.LEFT
      );
    },
    "doesRegularContinueAfterSpace",
  );
  var isRegexpOpening = /* @__PURE__ */ __name(
    (context, prevTokenValue, bufferNodeValue) => {
      const lastExtendedPseudoClassName = getLast(
        context.extendedPseudoNamesStack,
      );
      if (!lastExtendedPseudoClassName) {
        throw new Error(
          "Regexp pattern allowed only in arg of extended pseudo-class",
        );
      }
      if (CONTAINS_PSEUDO_NAMES.includes(lastExtendedPseudoClassName)) {
        return POSSIBLE_MARKS_BEFORE_REGEXP.CONTAINS.includes(prevTokenValue);
      }
      if (
        prevTokenValue === SLASH &&
        lastExtendedPseudoClassName !== XPATH_PSEUDO_CLASS_MARKER
      ) {
        const rawArgDesc = bufferNodeValue
          ? `in arg part: '${bufferNodeValue}'`
          : "arg";
        throw new Error(
          `Invalid regexp pattern for :${lastExtendedPseudoClassName}() pseudo-class ${rawArgDesc}`,
        );
      }
      return POSSIBLE_MARKS_BEFORE_REGEXP.COMMON.includes(prevTokenValue);
    },
    "isRegexpOpening",
  );
  var isAttributeOpening = /* @__PURE__ */ __name(
    (tokenValue, prevTokenValue) => {
      return tokenValue === BRACKET.SQUARE.LEFT && prevTokenValue !== BACKSLASH;
    },
    "isAttributeOpening",
  );
  var isAttributeClosing = /* @__PURE__ */ __name((context) => {
    if (!context.isAttributeBracketsOpen) {
      return false;
    }
    const noSpaceAttr = context.attributeBuffer.split(SPACE).join("");
    const attrTokens = tokenizeAttribute(noSpaceAttr);
    const firstAttrToken = getFirst(attrTokens);
    const firstAttrTokenType = firstAttrToken?.type;
    const firstAttrTokenValue = firstAttrToken?.value;
    if (
      firstAttrTokenType === TOKEN_TYPE.MARK &&
      firstAttrTokenValue !== BACKSLASH
    ) {
      throw new Error(
        `'[${context.attributeBuffer}]' is not a valid attribute due to '${firstAttrTokenValue}' at start of it`,
      );
    }
    const lastAttrToken = getLast(attrTokens);
    const lastAttrTokenType = lastAttrToken?.type;
    const lastAttrTokenValue = lastAttrToken?.value;
    if (lastAttrTokenValue === EQUAL_SIGN) {
      throw new Error(
        `'[${context.attributeBuffer}]' is not a valid attribute due to '${EQUAL_SIGN}'`,
      );
    }
    const equalSignIndex = attrTokens.findIndex((token) => {
      return token.type === TOKEN_TYPE.MARK && token.value === EQUAL_SIGN;
    });
    const prevToLastAttrTokenValue = getPrevToLast(attrTokens)?.value;
    if (equalSignIndex === -1) {
      if (lastAttrTokenType === TOKEN_TYPE.WORD) {
        return true;
      }
      return (
        prevToLastAttrTokenValue === BACKSLASH &&
        (lastAttrTokenValue === DOUBLE_QUOTE ||
          lastAttrTokenValue === SINGLE_QUOTE)
      );
    }
    const nextToEqualSignToken = getItemByIndex(attrTokens, equalSignIndex + 1);
    const nextToEqualSignTokenValue = nextToEqualSignToken.value;
    const isAttrValueQuote =
      nextToEqualSignTokenValue === SINGLE_QUOTE ||
      nextToEqualSignTokenValue === DOUBLE_QUOTE;
    if (!isAttrValueQuote) {
      if (lastAttrTokenType === TOKEN_TYPE.WORD) {
        return true;
      }
      throw new Error(
        `'[${context.attributeBuffer}]' is not a valid attribute`,
      );
    }
    if (
      lastAttrTokenType === TOKEN_TYPE.WORD &&
      lastAttrTokenValue?.toLocaleLowerCase() ===
        ATTRIBUTE_CASE_INSENSITIVE_FLAG
    ) {
      return prevToLastAttrTokenValue === nextToEqualSignTokenValue;
    }
    return lastAttrTokenValue === nextToEqualSignTokenValue;
  }, "isAttributeClosing");
  var isWhiteSpaceChar = /* @__PURE__ */ __name((tokenValue) => {
    if (!tokenValue) {
      return false;
    }
    return WHITE_SPACE_CHARACTERS.includes(tokenValue);
  }, "isWhiteSpaceChar");

  // src/selector/utils/common-predicates.ts
  var isAbsolutePseudoClass = /* @__PURE__ */ __name((str) => {
    return ABSOLUTE_PSEUDO_CLASSES.includes(str);
  }, "isAbsolutePseudoClass");
  var isRelativePseudoClass = /* @__PURE__ */ __name((str) => {
    return RELATIVE_PSEUDO_CLASSES.includes(str);
  }, "isRelativePseudoClass");

  // src/selector/utils/parser-ast-node-helpers.ts
  var getBufferNode = /* @__PURE__ */ __name((context) => {
    if (context.pathToBufferNode.length === 0) {
      return null;
    }
    return getLast(context.pathToBufferNode) || null;
  }, "getBufferNode");
  var getBufferNodeParent = /* @__PURE__ */ __name((context) => {
    if (context.pathToBufferNode.length < 2) {
      return null;
    }
    return getPrevToLast(context.pathToBufferNode) || null;
  }, "getBufferNodeParent");
  var getContextLastRegularSelectorNode = /* @__PURE__ */ __name((context) => {
    const bufferNode = getBufferNode(context);
    if (!bufferNode) {
      throw new Error("No bufferNode found");
    }
    if (!isSelectorNode(bufferNode)) {
      throw new Error("Unsupported bufferNode type");
    }
    const lastRegularSelectorNode = getLastRegularChild(bufferNode.children);
    context.pathToBufferNode.push(lastRegularSelectorNode);
    return lastRegularSelectorNode;
  }, "getContextLastRegularSelectorNode");
  var updateBufferNode = /* @__PURE__ */ __name((context, tokenValue) => {
    const bufferNode = getBufferNode(context);
    if (bufferNode === null) {
      throw new Error("No bufferNode to update");
    }
    if (isAbsolutePseudoClassNode(bufferNode)) {
      bufferNode.value += tokenValue;
    } else if (isRegularSelectorNode(bufferNode)) {
      bufferNode.value += tokenValue;
      if (context.isAttributeBracketsOpen) {
        context.attributeBuffer += tokenValue;
      }
    } else {
      throw new Error(
        `${bufferNode.type} node cannot be updated. Only RegularSelector and AbsolutePseudoClass are supported`,
      );
    }
  }, "updateBufferNode");
  var addSelectorListNode = /* @__PURE__ */ __name((context) => {
    const selectorListNode = new AnySelectorNode(NODE.SELECTOR_LIST);
    context.ast = selectorListNode;
    context.pathToBufferNode.push(selectorListNode);
  }, "addSelectorListNode");
  var addAstNodeByType = /* @__PURE__ */ __name(
    (context, type, tokenValue = "") => {
      const bufferNode = getBufferNode(context);
      if (bufferNode === null) {
        throw new Error("No buffer node");
      }
      let node;
      if (type === NODE.REGULAR_SELECTOR) {
        node = new RegularSelectorNode(tokenValue);
      } else if (type === NODE.ABSOLUTE_PSEUDO_CLASS) {
        node = new AbsolutePseudoClassNode(tokenValue);
      } else if (type === NODE.RELATIVE_PSEUDO_CLASS) {
        node = new RelativePseudoClassNode(tokenValue);
      } else {
        node = new AnySelectorNode(type);
      }
      bufferNode.addChild(node);
      context.pathToBufferNode.push(node);
    },
    "addAstNodeByType",
  );
  var initAst = /* @__PURE__ */ __name((context, tokenValue) => {
    addSelectorListNode(context);
    addAstNodeByType(context, NODE.SELECTOR);
    addAstNodeByType(context, NODE.REGULAR_SELECTOR, tokenValue);
  }, "initAst");
  var initRelativeSubtree = /* @__PURE__ */ __name(
    (context, tokenValue = "") => {
      addAstNodeByType(context, NODE.SELECTOR_LIST);
      addAstNodeByType(context, NODE.SELECTOR);
      addAstNodeByType(context, NODE.REGULAR_SELECTOR, tokenValue);
    },
    "initRelativeSubtree",
  );
  var upToClosest = /* @__PURE__ */ __name((context, parentType) => {
    for (let i = context.pathToBufferNode.length - 1; i >= 0; i -= 1) {
      if (context.pathToBufferNode[i]?.type === parentType) {
        context.pathToBufferNode = context.pathToBufferNode.slice(0, i + 1);
        break;
      }
    }
  }, "upToClosest");
  var getUpdatedBufferNode = /* @__PURE__ */ __name((context) => {
    const bufferNode = getBufferNode(context);
    if (
      bufferNode &&
      isSelectorListNode(bufferNode) &&
      isRelativePseudoClassNode(getBufferNodeParent(context))
    ) {
      return bufferNode;
    }
    upToClosest(context, NODE.SELECTOR);
    const selectorNode = getBufferNode(context);
    if (!selectorNode) {
      throw new Error(
        "No SelectorNode, impossible to continue selector parsing by ExtendedCss",
      );
    }
    const lastSelectorNodeChild = getLast(selectorNode.children);
    const hasExtended =
      lastSelectorNodeChild &&
      isExtendedSelectorNode(lastSelectorNodeChild) &&
      context.standardPseudoBracketsStack.length === 0;
    const supposedPseudoClassNode =
      hasExtended && getFirst(lastSelectorNodeChild.children);
    let newNeededBufferNode = selectorNode;
    if (supposedPseudoClassNode) {
      const lastExtendedPseudoName =
        hasExtended && supposedPseudoClassNode.name;
      const isLastExtendedNameRelative =
        lastExtendedPseudoName && isRelativePseudoClass(lastExtendedPseudoName);
      const isLastExtendedNameAbsolute =
        lastExtendedPseudoName && isAbsolutePseudoClass(lastExtendedPseudoName);
      const hasRelativeExtended =
        isLastExtendedNameRelative &&
        context.extendedPseudoBracketsStack.length > 0 &&
        context.extendedPseudoBracketsStack.length ===
          context.extendedPseudoNamesStack.length;
      const hasAbsoluteExtended =
        isLastExtendedNameAbsolute &&
        lastExtendedPseudoName === getLast(context.extendedPseudoNamesStack);
      if (hasRelativeExtended) {
        context.pathToBufferNode.push(lastSelectorNodeChild);
        newNeededBufferNode = supposedPseudoClassNode;
      } else if (hasAbsoluteExtended) {
        context.pathToBufferNode.push(lastSelectorNodeChild);
        newNeededBufferNode = supposedPseudoClassNode;
      }
    } else if (hasExtended) {
      newNeededBufferNode = selectorNode;
    } else {
      newNeededBufferNode = getContextLastRegularSelectorNode(context);
    }
    context.pathToBufferNode.push(newNeededBufferNode);
    return newNeededBufferNode;
  }, "getUpdatedBufferNode");
  var handleNextTokenOnColon = /* @__PURE__ */ __name(
    (context, selector, tokenValue, nextTokenValue, nextToNextTokenValue) => {
      if (!nextTokenValue) {
        throw new Error(
          `Invalid colon ':' at the end of selector: '${selector}'`,
        );
      }
      if (!isSupportedPseudoClass(nextTokenValue.toLowerCase())) {
        if (nextTokenValue.toLowerCase() === REMOVE_PSEUDO_MARKER) {
          throw new Error(
            `${REMOVE_ERROR_PREFIX.INVALID_REMOVE}: '${selector}'`,
          );
        }
        updateBufferNode(context, tokenValue);
        if (
          nextToNextTokenValue &&
          nextToNextTokenValue === BRACKET.PARENTHESES.LEFT &&
          !context.isAttributeBracketsOpen
        ) {
          context.standardPseudoNamesStack.push(nextTokenValue);
        }
      } else {
        if (
          HAS_PSEUDO_CLASS_MARKERS.includes(nextTokenValue) &&
          context.standardPseudoNamesStack.length > 0
        ) {
          throw new Error(
            `Usage of :${nextTokenValue}() pseudo-class is not allowed inside regular pseudo: '${getLast(context.standardPseudoNamesStack)}'`,
          );
        } else {
          upToClosest(context, NODE.SELECTOR);
          addAstNodeByType(context, NODE.EXTENDED_SELECTOR);
        }
      }
    },
    "handleNextTokenOnColon",
  );

  // src/selector/utils/parser-ast-optimizer.ts
  var IS_OR_NOT_PSEUDO_SELECTING_ROOT = `html ${ASTERISK}`;
  var hasExtendedSelector = /* @__PURE__ */ __name((selectorList) => {
    return selectorList.children.some((selectorNode) => {
      return selectorNode.children.some((selectorNodeChild) => {
        return isExtendedSelectorNode(selectorNodeChild);
      });
    });
  }, "hasExtendedSelector");
  var selectorListOfRegularsToString = /* @__PURE__ */ __name(
    (selectorList) => {
      const standardCssSelectors = selectorList.children.map((selectorNode) => {
        const selectorOnlyChild = getNodeOnlyChild(
          selectorNode,
          "Ast Selector node should have RegularSelector node",
        );
        return getNodeValue(selectorOnlyChild);
      });
      return standardCssSelectors.join(`${COMMA}${SPACE}`);
    },
    "selectorListOfRegularsToString",
  );
  var updateNodeChildren = /* @__PURE__ */ __name((node, newChildren) => {
    node.children = newChildren;
    return node;
  }, "updateNodeChildren");
  var shouldOptimizeExtendedSelector = /* @__PURE__ */ __name(
    (currExtendedSelectorNode) => {
      if (currExtendedSelectorNode === null) {
        return false;
      }
      const extendedPseudoClassNode = getPseudoClassNode(
        currExtendedSelectorNode,
      );
      const pseudoName = getNodeName(extendedPseudoClassNode);
      if (isAbsolutePseudoClass(pseudoName)) {
        return false;
      }
      const relativeSelectorList = getRelativeSelectorListNode(
        extendedPseudoClassNode,
      );
      const innerSelectorNodes = relativeSelectorList.children;
      if (isOptimizationPseudoClass(pseudoName)) {
        const areAllSelectorNodeChildrenRegular = innerSelectorNodes.every(
          (selectorNode) => {
            try {
              const selectorOnlyChild = getNodeOnlyChild(
                selectorNode,
                "Selector node should have RegularSelector",
              );
              return isRegularSelectorNode(selectorOnlyChild);
            } catch (e) {
              return false;
            }
          },
        );
        if (areAllSelectorNodeChildrenRegular) {
          return true;
        }
      }
      return innerSelectorNodes.some((selectorNode) => {
        return selectorNode.children.some((selectorNodeChild) => {
          if (!isExtendedSelectorNode(selectorNodeChild)) {
            return false;
          }
          return shouldOptimizeExtendedSelector(selectorNodeChild);
        });
      });
    },
    "shouldOptimizeExtendedSelector",
  );
  var getOptimizedExtendedSelector = /* @__PURE__ */ __name(
    (currExtendedSelectorNode, prevRegularSelectorNode) => {
      if (!currExtendedSelectorNode) {
        return null;
      }
      const extendedPseudoClassNode = getPseudoClassNode(
        currExtendedSelectorNode,
      );
      const relativeSelectorList = getRelativeSelectorListNode(
        extendedPseudoClassNode,
      );
      const hasInnerExtendedSelector =
        hasExtendedSelector(relativeSelectorList);
      if (!hasInnerExtendedSelector) {
        const relativeSelectorListStr =
          selectorListOfRegularsToString(relativeSelectorList);
        const pseudoName = getNodeName(extendedPseudoClassNode);
        const optimizedExtendedStr = `${COLON}${pseudoName}${BRACKET.PARENTHESES.LEFT}${relativeSelectorListStr}${BRACKET.PARENTHESES.RIGHT}`;
        prevRegularSelectorNode.value = `${getNodeValue(prevRegularSelectorNode)}${optimizedExtendedStr}`;
        return null;
      }
      const optimizedRelativeSelectorList =
        optimizeSelectorListNode(relativeSelectorList);
      const optimizedExtendedPseudoClassNode = updateNodeChildren(
        extendedPseudoClassNode,
        [optimizedRelativeSelectorList],
      );
      return updateNodeChildren(currExtendedSelectorNode, [
        optimizedExtendedPseudoClassNode,
      ]);
    },
    "getOptimizedExtendedSelector",
  );
  var optimizeCurrentRegularSelector = /* @__PURE__ */ __name(
    (current, previous) => {
      previous.value = `${getNodeValue(previous)}${SPACE}${getNodeValue(current)}`;
    },
    "optimizeCurrentRegularSelector",
  );
  var optimizeSelectorNode = /* @__PURE__ */ __name((selectorNode) => {
    const rawSelectorNodeChildren = selectorNode.children;
    const optimizedChildrenList = [];
    let currentIndex = 0;
    while (currentIndex < rawSelectorNodeChildren.length) {
      const currentChild = getItemByIndex(
        rawSelectorNodeChildren,
        currentIndex,
        "currentChild should be specified",
      );
      if (currentIndex === 0) {
        optimizedChildrenList.push(currentChild);
      } else {
        const prevRegularChild = getLastRegularChild(optimizedChildrenList);
        if (isExtendedSelectorNode(currentChild)) {
          let optimizedExtendedSelector = null;
          let isOptimizationNeeded =
            shouldOptimizeExtendedSelector(currentChild);
          optimizedExtendedSelector = currentChild;
          while (isOptimizationNeeded) {
            optimizedExtendedSelector = getOptimizedExtendedSelector(
              optimizedExtendedSelector,
              prevRegularChild,
            );
            isOptimizationNeeded = shouldOptimizeExtendedSelector(
              optimizedExtendedSelector,
            );
          }
          if (optimizedExtendedSelector !== null) {
            optimizedChildrenList.push(optimizedExtendedSelector);
            const optimizedPseudoClass = getPseudoClassNode(
              optimizedExtendedSelector,
            );
            const optimizedPseudoName = getNodeName(optimizedPseudoClass);
            if (
              getNodeValue(prevRegularChild) === ASTERISK &&
              isOptimizationPseudoClass(optimizedPseudoName)
            ) {
              prevRegularChild.value = IS_OR_NOT_PSEUDO_SELECTING_ROOT;
            }
          }
        } else if (isRegularSelectorNode(currentChild)) {
          const lastOptimizedChild = getLast(optimizedChildrenList) || null;
          if (isRegularSelectorNode(lastOptimizedChild)) {
            optimizeCurrentRegularSelector(currentChild, prevRegularChild);
          }
        }
      }
      currentIndex += 1;
    }
    return updateNodeChildren(selectorNode, optimizedChildrenList);
  }, "optimizeSelectorNode");
  var optimizeSelectorListNode = /* @__PURE__ */ __name((selectorListNode) => {
    return updateNodeChildren(
      selectorListNode,
      selectorListNode.children.map((s) => optimizeSelectorNode(s)),
    );
  }, "optimizeSelectorListNode");
  var optimizeAst = /* @__PURE__ */ __name((ast) => {
    return optimizeSelectorListNode(ast);
  }, "optimizeAst");

  // src/selector/parser.ts
  var XPATH_PSEUDO_SELECTING_ROOT = "body";
  var NO_WHITESPACE_ERROR_PREFIX =
    "No white space is allowed before or after extended pseudo-class name in selector";
  var parse = /* @__PURE__ */ __name((selector) => {
    const tokens = tokenizeSelector(selector);
    const context = {
      ast: null,
      pathToBufferNode: [],
      extendedPseudoNamesStack: [],
      extendedPseudoBracketsStack: [],
      standardPseudoNamesStack: [],
      standardPseudoBracketsStack: [],
      isAttributeBracketsOpen: false,
      attributeBuffer: "",
      isRegexpOpen: false,
      shouldOptimize: false,
    };
    let i = 0;
    while (i < tokens.length) {
      const token = tokens[i];
      if (!token) {
        break;
      }
      const { type: tokenType, value: tokenValue } = token;
      const nextToken = tokens[i + 1];
      const nextTokenType = nextToken?.type;
      const nextTokenValue = nextToken?.value;
      const nextToNextToken = tokens[i + 2];
      const nextToNextTokenValue = nextToNextToken?.value;
      const previousToken = tokens[i - 1];
      const prevTokenType = previousToken?.type;
      const prevTokenValue = previousToken?.value;
      const previousToPreviousToken = tokens[i - 2];
      const prevToPrevTokenValue = previousToPreviousToken?.value;
      let bufferNode = getBufferNode(context);
      switch (tokenType) {
        case TOKEN_TYPE.WORD:
          if (bufferNode === null) {
            initAst(context, tokenValue);
          } else if (isSelectorListNode(bufferNode)) {
            addAstNodeByType(context, NODE.SELECTOR);
            addAstNodeByType(context, NODE.REGULAR_SELECTOR, tokenValue);
          } else if (isRegularSelectorNode(bufferNode)) {
            updateBufferNode(context, tokenValue);
          } else if (isExtendedSelectorNode(bufferNode)) {
            if (
              isWhiteSpaceChar(nextTokenValue) &&
              nextToNextTokenValue === BRACKET.PARENTHESES.LEFT
            ) {
              throw new Error(`${NO_WHITESPACE_ERROR_PREFIX}: '${selector}'`);
            }
            const lowerCaseTokenValue = tokenValue.toLowerCase();
            context.extendedPseudoNamesStack.push(lowerCaseTokenValue);
            if (isAbsolutePseudoClass(lowerCaseTokenValue)) {
              addAstNodeByType(
                context,
                NODE.ABSOLUTE_PSEUDO_CLASS,
                lowerCaseTokenValue,
              );
            } else {
              addAstNodeByType(
                context,
                NODE.RELATIVE_PSEUDO_CLASS,
                lowerCaseTokenValue,
              );
              if (isOptimizationPseudoClass(lowerCaseTokenValue)) {
                context.shouldOptimize = true;
              }
            }
          } else if (isAbsolutePseudoClassNode(bufferNode)) {
            updateBufferNode(context, tokenValue);
          } else if (isRelativePseudoClassNode(bufferNode)) {
            initRelativeSubtree(context, tokenValue);
          }
          break;
        case TOKEN_TYPE.MARK:
          switch (tokenValue) {
            case COMMA:
              if (
                !bufferNode ||
                (typeof bufferNode !== "undefined" && !nextTokenValue)
              ) {
                throw new Error(`'${selector}' is not a valid selector`);
              } else if (isRegularSelectorNode(bufferNode)) {
                if (context.isAttributeBracketsOpen) {
                  updateBufferNode(context, tokenValue);
                } else {
                  upToClosest(context, NODE.SELECTOR_LIST);
                }
              } else if (isAbsolutePseudoClassNode(bufferNode)) {
                updateBufferNode(context, tokenValue);
              } else if (isSelectorNode(bufferNode)) {
                upToClosest(context, NODE.SELECTOR_LIST);
              }
              break;
            case SPACE:
              if (
                isRegularSelectorNode(bufferNode) &&
                !context.isAttributeBracketsOpen
              ) {
                bufferNode = getUpdatedBufferNode(context);
              }
              if (isRegularSelectorNode(bufferNode)) {
                if (
                  !context.isAttributeBracketsOpen &&
                  ((prevTokenValue === COLON &&
                    nextTokenType === TOKEN_TYPE.WORD) ||
                    (prevTokenType === TOKEN_TYPE.WORD &&
                      nextTokenValue === BRACKET.PARENTHESES.LEFT))
                ) {
                  throw new Error(`'${selector}' is not a valid selector`);
                }
                if (
                  !nextTokenValue ||
                  doesRegularContinueAfterSpace(
                    nextTokenType,
                    nextTokenValue,
                  ) ||
                  context.isAttributeBracketsOpen
                ) {
                  updateBufferNode(context, tokenValue);
                }
              }
              if (isAbsolutePseudoClassNode(bufferNode)) {
                updateBufferNode(context, tokenValue);
              }
              if (isRelativePseudoClassNode(bufferNode)) {
                initRelativeSubtree(context);
              }
              if (isSelectorNode(bufferNode)) {
                if (
                  doesRegularContinueAfterSpace(nextTokenType, nextTokenValue)
                ) {
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
              if (COMBINATORS.includes(tokenValue)) {
                if (bufferNode === null) {
                  throw new Error(`'${selector}' is not a valid selector`);
                }
                bufferNode = getUpdatedBufferNode(context);
              }
              if (bufferNode === null) {
                initAst(context, tokenValue);
                if (isAttributeOpening(tokenValue, prevTokenValue)) {
                  context.isAttributeBracketsOpen = true;
                }
              } else if (isRegularSelectorNode(bufferNode)) {
                if (
                  tokenValue === BRACKET.CURLY.LEFT &&
                  !(context.isAttributeBracketsOpen || context.isRegexpOpen)
                ) {
                  throw new Error(`'${selector}' is not a valid selector`);
                }
                updateBufferNode(context, tokenValue);
                if (isAttributeOpening(tokenValue, prevTokenValue)) {
                  context.isAttributeBracketsOpen = true;
                }
              } else if (isAbsolutePseudoClassNode(bufferNode)) {
                updateBufferNode(context, tokenValue);
                if (
                  tokenValue === SLASH &&
                  context.extendedPseudoNamesStack.length > 0
                ) {
                  if (
                    prevTokenValue === SLASH &&
                    prevToPrevTokenValue === BACKSLASH
                  ) {
                    context.isRegexpOpen = false;
                  } else if (prevTokenValue && prevTokenValue !== BACKSLASH) {
                    if (
                      isRegexpOpening(
                        context,
                        prevTokenValue,
                        getNodeValue(bufferNode),
                      )
                    ) {
                      context.isRegexpOpen = !context.isRegexpOpen;
                    } else {
                      context.isRegexpOpen = false;
                    }
                  }
                }
              } else if (isRelativePseudoClassNode(bufferNode)) {
                initRelativeSubtree(context, tokenValue);
                if (isAttributeOpening(tokenValue, prevTokenValue)) {
                  context.isAttributeBracketsOpen = true;
                }
              } else if (isSelectorNode(bufferNode)) {
                if (COMBINATORS.includes(tokenValue)) {
                  addAstNodeByType(context, NODE.REGULAR_SELECTOR, tokenValue);
                } else if (!context.isRegexpOpen) {
                  bufferNode = getContextLastRegularSelectorNode(context);
                  updateBufferNode(context, tokenValue);
                  if (isAttributeOpening(tokenValue, prevTokenValue)) {
                    context.isAttributeBracketsOpen = true;
                  }
                }
              } else if (isSelectorListNode(bufferNode)) {
                addAstNodeByType(context, NODE.SELECTOR);
                addAstNodeByType(context, NODE.REGULAR_SELECTOR, tokenValue);
                if (isAttributeOpening(tokenValue, prevTokenValue)) {
                  context.isAttributeBracketsOpen = true;
                }
              }
              break;
            case BRACKET.SQUARE.RIGHT:
              if (isRegularSelectorNode(bufferNode)) {
                if (
                  !context.isAttributeBracketsOpen &&
                  prevTokenValue !== BACKSLASH
                ) {
                  throw new Error(
                    `'${selector}' is not a valid selector due to '${tokenValue}' after '${getNodeValue(bufferNode)}'`,
                  );
                }
                if (isAttributeClosing(context)) {
                  context.isAttributeBracketsOpen = false;
                  context.attributeBuffer = "";
                }
                updateBufferNode(context, tokenValue);
              }
              if (isAbsolutePseudoClassNode(bufferNode)) {
                updateBufferNode(context, tokenValue);
              }
              break;
            case COLON:
              if (
                isWhiteSpaceChar(nextTokenValue) &&
                nextToNextTokenValue &&
                SUPPORTED_PSEUDO_CLASSES.includes(nextToNextTokenValue)
              ) {
                throw new Error(`${NO_WHITESPACE_ERROR_PREFIX}: '${selector}'`);
              }
              if (bufferNode === null) {
                if (nextTokenValue === XPATH_PSEUDO_CLASS_MARKER) {
                  initAst(context, XPATH_PSEUDO_SELECTING_ROOT);
                } else if (
                  nextTokenValue === UPWARD_PSEUDO_CLASS_MARKER ||
                  nextTokenValue === NTH_ANCESTOR_PSEUDO_CLASS_MARKER
                ) {
                  throw new Error(
                    `${NO_SELECTOR_ERROR_PREFIX} before :${nextTokenValue}() pseudo-class`,
                  );
                } else {
                  initAst(context, ASTERISK);
                }
                bufferNode = getBufferNode(context);
              }
              if (isSelectorListNode(bufferNode)) {
                addAstNodeByType(context, NODE.SELECTOR);
                addAstNodeByType(context, NODE.REGULAR_SELECTOR);
                bufferNode = getBufferNode(context);
              }
              if (isRegularSelectorNode(bufferNode)) {
                if (
                  (prevTokenValue && COMBINATORS.includes(prevTokenValue)) ||
                  prevTokenValue === COMMA
                ) {
                  updateBufferNode(context, ASTERISK);
                }
                handleNextTokenOnColon(
                  context,
                  selector,
                  tokenValue,
                  nextTokenValue,
                  nextToNextTokenValue,
                );
              }
              if (isSelectorNode(bufferNode)) {
                if (!nextTokenValue) {
                  throw new Error(
                    `Invalid colon ':' at the end of selector: '${selector}'`,
                  );
                }
                if (isSupportedPseudoClass(nextTokenValue.toLowerCase())) {
                  addAstNodeByType(context, NODE.EXTENDED_SELECTOR);
                } else if (
                  nextTokenValue.toLowerCase() === REMOVE_PSEUDO_MARKER
                ) {
                  throw new Error(
                    `${REMOVE_ERROR_PREFIX.INVALID_REMOVE}: '${selector}'`,
                  );
                } else {
                  bufferNode = getContextLastRegularSelectorNode(context);
                  handleNextTokenOnColon(
                    context,
                    selector,
                    tokenValue,
                    nextTokenType,
                    nextToNextTokenValue,
                  );
                }
              }
              if (isAbsolutePseudoClassNode(bufferNode)) {
                if (
                  getNodeName(bufferNode) === XPATH_PSEUDO_CLASS_MARKER &&
                  nextTokenValue &&
                  SUPPORTED_PSEUDO_CLASSES.includes(nextTokenValue) &&
                  nextToNextTokenValue === BRACKET.PARENTHESES.LEFT
                ) {
                  throw new Error(
                    `:xpath() pseudo-class should be the last in selector: '${selector}'`,
                  );
                }
                updateBufferNode(context, tokenValue);
              }
              if (isRelativePseudoClassNode(bufferNode)) {
                if (!nextTokenValue) {
                  throw new Error(
                    `Invalid pseudo-class arg at the end of selector: '${selector}'`,
                  );
                }
                initRelativeSubtree(context, ASTERISK);
                if (!isSupportedPseudoClass(nextTokenValue.toLowerCase())) {
                  updateBufferNode(context, tokenValue);
                  if (nextToNextTokenValue === BRACKET.PARENTHESES.LEFT) {
                    context.standardPseudoNamesStack.push(nextTokenValue);
                  }
                } else {
                  upToClosest(context, NODE.SELECTOR);
                  addAstNodeByType(context, NODE.EXTENDED_SELECTOR);
                }
              }
              break;
            case BRACKET.PARENTHESES.LEFT:
              if (isAbsolutePseudoClassNode(bufferNode)) {
                if (
                  getNodeName(bufferNode) !== XPATH_PSEUDO_CLASS_MARKER &&
                  context.isRegexpOpen
                ) {
                  updateBufferNode(context, tokenValue);
                } else {
                  context.extendedPseudoBracketsStack.push(tokenValue);
                  if (
                    context.extendedPseudoBracketsStack.length >
                    context.extendedPseudoNamesStack.length
                  ) {
                    updateBufferNode(context, tokenValue);
                  }
                }
              }
              if (isRegularSelectorNode(bufferNode)) {
                if (context.standardPseudoNamesStack.length > 0) {
                  updateBufferNode(context, tokenValue);
                  context.standardPseudoBracketsStack.push(tokenValue);
                }
                if (context.isAttributeBracketsOpen) {
                  updateBufferNode(context, tokenValue);
                }
              }
              if (isRelativePseudoClassNode(bufferNode)) {
                context.extendedPseudoBracketsStack.push(tokenValue);
              }
              break;
            case BRACKET.PARENTHESES.RIGHT:
              if (isAbsolutePseudoClassNode(bufferNode)) {
                if (
                  getNodeName(bufferNode) !== XPATH_PSEUDO_CLASS_MARKER &&
                  context.isRegexpOpen
                ) {
                  updateBufferNode(context, tokenValue);
                } else {
                  context.extendedPseudoBracketsStack.pop();
                  if (getNodeName(bufferNode) !== XPATH_PSEUDO_CLASS_MARKER) {
                    context.extendedPseudoNamesStack.pop();
                    if (
                      context.extendedPseudoBracketsStack.length >
                      context.extendedPseudoNamesStack.length
                    ) {
                      updateBufferNode(context, tokenValue);
                    } else if (
                      context.extendedPseudoBracketsStack.length >= 0 &&
                      context.extendedPseudoNamesStack.length >= 0
                    ) {
                      upToClosest(context, NODE.SELECTOR);
                    }
                  } else {
                    if (
                      context.extendedPseudoBracketsStack.length <
                      context.extendedPseudoNamesStack.length
                    ) {
                      context.extendedPseudoNamesStack.pop();
                    } else {
                      updateBufferNode(context, tokenValue);
                    }
                  }
                }
              }
              if (isRegularSelectorNode(bufferNode)) {
                if (context.isAttributeBracketsOpen) {
                  updateBufferNode(context, tokenValue);
                } else if (
                  context.standardPseudoNamesStack.length > 0 &&
                  context.standardPseudoBracketsStack.length > 0
                ) {
                  updateBufferNode(context, tokenValue);
                  context.standardPseudoBracketsStack.pop();
                  const lastStandardPseudo =
                    context.standardPseudoNamesStack.pop();
                  if (!lastStandardPseudo) {
                    throw new Error(
                      `Parsing error. Invalid selector: ${selector}`,
                    );
                  }
                  if (
                    Object.values(REGULAR_PSEUDO_ELEMENTS).includes(
                      lastStandardPseudo,
                    ) &&
                    nextTokenValue === COLON &&
                    nextToNextTokenValue &&
                    HAS_PSEUDO_CLASS_MARKERS.includes(nextToNextTokenValue)
                  ) {
                    throw new Error(
                      `Usage of :${nextToNextTokenValue}() pseudo-class is not allowed after any regular pseudo-element: '${lastStandardPseudo}'`,
                    );
                  }
                } else {
                  context.extendedPseudoBracketsStack.pop();
                  context.extendedPseudoNamesStack.pop();
                  upToClosest(context, NODE.EXTENDED_SELECTOR);
                  upToClosest(context, NODE.SELECTOR);
                }
              }
              if (isSelectorNode(bufferNode)) {
                context.extendedPseudoBracketsStack.pop();
                context.extendedPseudoNamesStack.pop();
                upToClosest(context, NODE.EXTENDED_SELECTOR);
                upToClosest(context, NODE.SELECTOR);
              }
              if (isRelativePseudoClassNode(bufferNode)) {
                if (
                  context.extendedPseudoNamesStack.length > 0 &&
                  context.extendedPseudoBracketsStack.length > 0
                ) {
                  context.extendedPseudoBracketsStack.pop();
                  context.extendedPseudoNamesStack.pop();
                }
              }
              break;
            case LINE_FEED:
            case FORM_FEED:
            case CARRIAGE_RETURN:
              throw new Error(`'${selector}' is not a valid selector`);
            case TAB:
              if (
                isRegularSelectorNode(bufferNode) &&
                context.isAttributeBracketsOpen
              ) {
                updateBufferNode(context, tokenValue);
              } else {
                throw new Error(`'${selector}' is not a valid selector`);
              }
          }
          break;
        default:
          throw new Error(`Unknown type of token: '${tokenValue}'`);
      }
      i += 1;
    }
    if (context.ast === null) {
      throw new Error(`'${selector}' is not a valid selector`);
    }
    if (
      context.extendedPseudoNamesStack.length > 0 ||
      context.extendedPseudoBracketsStack.length > 0
    ) {
      throw new Error(
        `Unbalanced brackets for extended pseudo-class: '${getLast(context.extendedPseudoNamesStack)}'`,
      );
    }
    if (context.isAttributeBracketsOpen) {
      throw new Error(
        `Unbalanced attribute brackets in selector: '${selector}'`,
      );
    }
    return context.shouldOptimize ? optimizeAst(context.ast) : context.ast;
  }, "parse");

  // src/common/utils/natives.ts
  var natives = {
    MutationObserver: window.MutationObserver || window.WebKitMutationObserver,
  };
  var NativeTextContent = class {
    constructor() {
      this.nativeNode = window.Node || Node;
    }
    setGetter() {
      this.getter = Object.getOwnPropertyDescriptor(
        this.nativeNode.prototype,
        "textContent",
      )?.get;
    }
  };
  __name(NativeTextContent, "NativeTextContent");
  var nativeTextContent = new NativeTextContent();

  // src/common/utils/nodes.ts
  var getNodeTextContent = /* @__PURE__ */ __name((domElement) => {
    if (nativeTextContent.getter) {
      return nativeTextContent.getter.apply(domElement);
    }
    return domElement.textContent || "";
  }, "getNodeTextContent");
  var getElementSelectorDesc = /* @__PURE__ */ __name((element) => {
    let selectorText = element.tagName.toLowerCase();
    selectorText += Array.from(element.attributes)
      .map((attr) => {
        return `[${attr.name}="${element.getAttribute(attr.name)}"]`;
      })
      .join("");
    return selectorText;
  }, "getElementSelectorDesc");
  var getElementSelectorPath = /* @__PURE__ */ __name((inputEl) => {
    if (!(inputEl instanceof Element)) {
      throw new Error("Function received argument with wrong type");
    }
    let el;
    el = inputEl;
    const path = [];
    while (!!el && el.nodeType === Node.ELEMENT_NODE) {
      let selector = el.nodeName.toLowerCase();
      if (el.id && typeof el.id === "string") {
        selector += `#${el.id}`;
        path.unshift(selector);
        break;
      }
      let sibling = el;
      let nth = 1;
      while (sibling.previousElementSibling) {
        sibling = sibling.previousElementSibling;
        if (
          sibling.nodeType === Node.ELEMENT_NODE &&
          sibling.nodeName.toLowerCase() === selector
        ) {
          nth += 1;
        }
      }
      if (nth !== 1) {
        selector += `:nth-of-type(${nth})`;
      }
      path.unshift(selector);
      el = el.parentElement;
    }
    return path.join(" > ");
  }, "getElementSelectorPath");
  var isHtmlElement = /* @__PURE__ */ __name((element) => {
    return element instanceof HTMLElement;
  }, "isHtmlElement");
  var getParent = /* @__PURE__ */ __name((element, errorMessage) => {
    const { parentElement } = element;
    if (!parentElement) {
      throw new Error(errorMessage || "Element does no have parent element");
    }
    return parentElement;
  }, "getParent");

  // src/common/utils/error.ts
  var isErrorWithMessage = /* @__PURE__ */ __name((error) => {
    return (
      typeof error === "object" &&
      error !== null &&
      "message" in error &&
      typeof error.message === "string"
    );
  }, "isErrorWithMessage");
  var toErrorWithMessage = /* @__PURE__ */ __name((maybeError) => {
    if (isErrorWithMessage(maybeError)) {
      return maybeError;
    }
    try {
      return new Error(JSON.stringify(maybeError));
    } catch {
      return new Error(String(maybeError));
    }
  }, "toErrorWithMessage");
  var getErrorMessage = /* @__PURE__ */ __name((error) => {
    return toErrorWithMessage(error).message;
  }, "getErrorMessage");

  // src/common/utils/logger.ts
  var logger = {
    error:
      typeof console !== "undefined" && console.error && console.error.bind
        ? console.error.bind(window.console)
        : console.error,
    info:
      typeof console !== "undefined" && console.info && console.info.bind
        ? console.info.bind(window.console)
        : console.info,
  };

  // src/common/utils/strings.ts
  var removeSuffix = /* @__PURE__ */ __name((str, suffix) => {
    const index = str.indexOf(suffix, str.length - suffix.length);
    if (index >= 0) {
      return str.substring(0, index);
    }
    return str;
  }, "removeSuffix");
  var replaceAll = /* @__PURE__ */ __name((input, pattern, replacement) => {
    if (!input) {
      return input;
    }
    return input.split(pattern).join(replacement);
  }, "replaceAll");
  var toRegExp = /* @__PURE__ */ __name((str) => {
    if (str.startsWith(SLASH) && str.endsWith(SLASH)) {
      return new RegExp(str.slice(1, -1));
    }
    const escaped = str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
    return new RegExp(escaped);
  }, "toRegExp");
  var convertTypeIntoString = /* @__PURE__ */ __name((value) => {
    let output;
    switch (value) {
      case void 0:
        output = "undefined";
        break;
      case null:
        output = "null";
        break;
      default:
        output = value.toString();
    }
    return output;
  }, "convertTypeIntoString");
  var convertTypeFromString = /* @__PURE__ */ __name((value) => {
    const numValue = Number(value);
    let output;
    if (!Number.isNaN(numValue)) {
      output = numValue;
    } else {
      switch (value) {
        case "undefined":
          output = void 0;
          break;
        case "null":
          output = null;
          break;
        case "true":
          output = true;
          break;
        case "false":
          output = false;
          break;
        default:
          output = value;
      }
    }
    return output;
  }, "convertTypeFromString");

  // src/common/utils/user-agents.ts
  var SAFARI_USER_AGENT_REGEXP = /\sVersion\/(\d{2}\.\d)(.+\s|\s)(Safari)\//;
  var isSafariBrowser = SAFARI_USER_AGENT_REGEXP.test(navigator.userAgent);
  var isUserAgentSupported = /* @__PURE__ */ __name((userAgent) => {
    if (userAgent.includes("MSIE") || userAgent.includes("Trident/")) {
      return false;
    }
    return true;
  }, "isUserAgentSupported");
  var isBrowserSupported = /* @__PURE__ */ __name(() => {
    return isUserAgentSupported(navigator.userAgent);
  }, "isBrowserSupported");

  // src/selector/utils/absolute-matcher.ts
  var CSS_PROPERTY = {
    BACKGROUND: "background",
    BACKGROUND_IMAGE: "background-image",
    CONTENT: "content",
    OPACITY: "opacity",
  };
  var REGEXP_ANY_SYMBOL = ".*";
  var REGEXP_WITH_FLAGS_REGEXP = /^\s*\/.*\/[gmisuy]*\s*$/;
  var removeContentQuotes = /* @__PURE__ */ __name((str) => {
    return str.replace(/^(["'])([\s\S]*)\1$/, "$2");
  }, "removeContentQuotes");
  var addUrlPropertyQuotes = /* @__PURE__ */ __name((str) => {
    if (!str.includes('url("')) {
      const re = /url\((.*?)\)/g;
      return str.replace(re, 'url("$1")');
    }
    return str;
  }, "addUrlPropertyQuotes");
  var addUrlQuotesTo = {
    regexpArg: (str) => {
      const re = /(\^)?url(\\)?\\\((\w|\[\w)/g;
      return str.replace(re, '$1url$2\\(\\"?$3');
    },
    noneRegexpArg: addUrlPropertyQuotes,
  };
  var escapeRegExp = /* @__PURE__ */ __name((str) => {
    const specials = [
      ".",
      "+",
      "?",
      "$",
      "{",
      "}",
      "(",
      ")",
      "[",
      "]",
      "\\",
      "/",
    ];
    const specialsRegex = new RegExp(`[${specials.join("\\")}]`, "g");
    return str.replace(specialsRegex, "\\$&");
  }, "escapeRegExp");
  var convertStyleMatchValueToRegexp = /* @__PURE__ */ __name((rawValue) => {
    let value;
    if (rawValue.startsWith(SLASH) && rawValue.endsWith(SLASH)) {
      value = addUrlQuotesTo.regexpArg(rawValue);
      value = value.slice(1, -1);
    } else {
      value = addUrlQuotesTo.noneRegexpArg(rawValue);
      value = value.replace(/\\([\\()[\]"])/g, "$1");
      value = escapeRegExp(value);
      value = replaceAll(value, ASTERISK, REGEXP_ANY_SYMBOL);
    }
    return new RegExp(value, "i");
  }, "convertStyleMatchValueToRegexp");
  var normalizePropertyValue = /* @__PURE__ */ __name(
    (propertyName, propertyValue) => {
      let normalized = "";
      switch (propertyName) {
        case CSS_PROPERTY.BACKGROUND:
        case CSS_PROPERTY.BACKGROUND_IMAGE:
          normalized = addUrlPropertyQuotes(propertyValue);
          break;
        case CSS_PROPERTY.CONTENT:
          normalized = removeContentQuotes(propertyValue);
          break;
        case CSS_PROPERTY.OPACITY:
          normalized = isSafariBrowser
            ? (Math.round(parseFloat(propertyValue) * 100) / 100).toString()
            : propertyValue;
          break;
        default:
          normalized = propertyValue;
      }
      return normalized;
    },
    "normalizePropertyValue",
  );
  var getComputedStylePropertyValue = /* @__PURE__ */ __name(
    (domElement, propertyName, regularPseudoElement) => {
      const style = window.getComputedStyle(domElement, regularPseudoElement);
      const propertyValue = style.getPropertyValue(propertyName);
      return normalizePropertyValue(propertyName, propertyValue);
    },
    "getComputedStylePropertyValue",
  );
  var getPseudoArgData = /* @__PURE__ */ __name((pseudoArg, separator) => {
    const index = pseudoArg.indexOf(separator);
    let name;
    let value;
    if (index > -1) {
      name = pseudoArg.substring(0, index).trim();
      value = pseudoArg.substring(index + 1).trim();
    } else {
      name = pseudoArg;
    }
    return { name, value };
  }, "getPseudoArgData");
  var parseStyleMatchArg = /* @__PURE__ */ __name((pseudoName, rawArg) => {
    const { name, value } = getPseudoArgData(rawArg, COMMA);
    let regularPseudoElement = name;
    let styleMatchArg = value;
    if (!Object.values(REGULAR_PSEUDO_ELEMENTS).includes(name)) {
      regularPseudoElement = null;
      styleMatchArg = rawArg;
    }
    if (!styleMatchArg) {
      throw new Error(
        `Required style property argument part is missing in :${pseudoName}() arg: '${rawArg}'`,
      );
    }
    if (regularPseudoElement) {
      regularPseudoElement = `${COLON}${COLON}${regularPseudoElement}`;
    }
    return { regularPseudoElement, styleMatchArg };
  }, "parseStyleMatchArg");
  var isStyleMatched = /* @__PURE__ */ __name((argsData) => {
    const { pseudoName, pseudoArg, domElement } = argsData;
    const { regularPseudoElement, styleMatchArg } = parseStyleMatchArg(
      pseudoName,
      pseudoArg,
    );
    const { name: matchName, value: matchValue } = getPseudoArgData(
      styleMatchArg,
      COLON,
    );
    if (!matchName || !matchValue) {
      throw new Error(
        `Required property name or value is missing in :${pseudoName}() arg: '${styleMatchArg}'`,
      );
    }
    let valueRegexp;
    try {
      valueRegexp = convertStyleMatchValueToRegexp(matchValue);
    } catch (e) {
      logger.error(getErrorMessage(e));
      throw new Error(
        `Invalid argument of :${pseudoName}() pseudo-class: '${styleMatchArg}'`,
      );
    }
    const value = getComputedStylePropertyValue(
      domElement,
      matchName,
      regularPseudoElement,
    );
    return valueRegexp && valueRegexp.test(value);
  }, "isStyleMatched");
  var validateStrMatcherArg = /* @__PURE__ */ __name((arg) => {
    if (arg.includes(SLASH)) {
      return false;
    }
    if (!/^[\w-]+$/.test(arg)) {
      return false;
    }
    return true;
  }, "validateStrMatcherArg");
  var getValidMatcherArg = /* @__PURE__ */ __name(
    (rawArg, isWildcardAllowed = false) => {
      let arg;
      if (
        rawArg.length > 1 &&
        rawArg.startsWith(DOUBLE_QUOTE) &&
        rawArg.endsWith(DOUBLE_QUOTE)
      ) {
        rawArg = rawArg.slice(1, -1);
      }
      if (rawArg === "") {
        throw new Error("Argument should be specified. Empty arg is invalid.");
      }
      if (rawArg.startsWith(SLASH) && rawArg.endsWith(SLASH)) {
        if (rawArg.length > 2) {
          arg = toRegExp(rawArg);
        } else {
          throw new Error(`Invalid regexp: '${rawArg}'`);
        }
      } else if (rawArg.includes(ASTERISK)) {
        if (rawArg === ASTERISK && !isWildcardAllowed) {
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
    },
    "getValidMatcherArg",
  );
  var getRawMatchingData = /* @__PURE__ */ __name((pseudoName, pseudoArg) => {
    const { name: rawName, value: rawValue } = getPseudoArgData(
      pseudoArg,
      EQUAL_SIGN,
    );
    if (!rawName) {
      throw new Error(
        `Required attribute name is missing in :${pseudoName} arg: ${pseudoArg}`,
      );
    }
    return { rawName, rawValue };
  }, "getRawMatchingData");
  var isAttributeMatched = /* @__PURE__ */ __name((argsData) => {
    const { pseudoName, pseudoArg, domElement } = argsData;
    const elementAttributes = domElement.attributes;
    if (elementAttributes.length === 0) {
      return false;
    }
    const { rawName: rawAttrName, rawValue: rawAttrValue } = getRawMatchingData(
      pseudoName,
      pseudoArg,
    );
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
      const isNameMatched =
        attrNameMatch instanceof RegExp
          ? attrNameMatch.test(attr.name)
          : attrNameMatch === attr.name;
      if (!rawAttrValue) {
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
        const isValueMatched =
          attrValueMatch instanceof RegExp
            ? attrValueMatch.test(attr.value)
            : attrValueMatch === attr.value;
        isMatched = isNameMatched && isValueMatched;
      }
      i += 1;
    }
    return isMatched;
  }, "isAttributeMatched");
  var parseRawPropChain = /* @__PURE__ */ __name((input) => {
    if (
      input.length > 1 &&
      input.startsWith(DOUBLE_QUOTE) &&
      input.endsWith(DOUBLE_QUOTE)
    ) {
      input = input.slice(1, -1);
    }
    const chainChunks = input.split(DOT);
    const chainPatterns = [];
    let patternBuffer = "";
    let isRegexpPattern = false;
    let i = 0;
    while (i < chainChunks.length) {
      const chunk = getItemByIndex(
        chainChunks,
        i,
        `Invalid pseudo-class arg: '${input}'`,
      );
      if (
        chunk.startsWith(SLASH) &&
        chunk.endsWith(SLASH) &&
        chunk.length > 2
      ) {
        chainPatterns.push(chunk);
      } else if (chunk.startsWith(SLASH)) {
        isRegexpPattern = true;
        patternBuffer += chunk;
      } else if (chunk.endsWith(SLASH)) {
        isRegexpPattern = false;
        patternBuffer += `.${chunk}`;
        chainPatterns.push(patternBuffer);
        patternBuffer = "";
      } else {
        if (isRegexpPattern) {
          patternBuffer += chunk;
        } else {
          chainPatterns.push(chunk);
        }
      }
      i += 1;
    }
    if (patternBuffer.length > 0) {
      throw new Error(`Invalid regexp property pattern '${input}'`);
    }
    const chainMatchPatterns = chainPatterns.map((pattern) => {
      if (pattern.length === 0) {
        throw new Error(
          `Empty pattern '${pattern}' is invalid in chain '${input}'`,
        );
      }
      let validPattern;
      try {
        validPattern = getValidMatcherArg(pattern, true);
      } catch (e) {
        logger.error(getErrorMessage(e));
        throw new Error(
          `Invalid property pattern '${pattern}' in property chain '${input}'`,
        );
      }
      return validPattern;
    });
    return chainMatchPatterns;
  }, "parseRawPropChain");
  var filterRootsByRegexpChain = /* @__PURE__ */ __name(
    (base, chain, output = []) => {
      const tempProp = getFirst(chain);
      if (chain.length === 1) {
        let key;
        for (key in base) {
          if (tempProp instanceof RegExp) {
            if (tempProp.test(key)) {
              output.push({
                base,
                prop: key,
                value: base[key],
              });
            }
          } else if (tempProp === key) {
            output.push({
              base,
              prop: tempProp,
              value: base[key],
            });
          }
        }
        return output;
      }
      if (tempProp instanceof RegExp) {
        const nextProp = chain.slice(1);
        const baseKeys = [];
        for (const key in base) {
          if (tempProp.test(key)) {
            baseKeys.push(key);
          }
        }
        baseKeys.forEach((key) => {
          const item = Object.getOwnPropertyDescriptor(base, key)?.value;
          filterRootsByRegexpChain(item, nextProp, output);
        });
      }
      if (base && typeof tempProp === "string") {
        const nextBase = Object.getOwnPropertyDescriptor(base, tempProp)?.value;
        chain = chain.slice(1);
        if (nextBase !== void 0) {
          filterRootsByRegexpChain(nextBase, chain, output);
        }
      }
      return output;
    },
    "filterRootsByRegexpChain",
  );
  var isPropertyMatched = /* @__PURE__ */ __name((argsData) => {
    const { pseudoName, pseudoArg, domElement } = argsData;
    const { rawName: rawPropertyName, rawValue: rawPropertyValue } =
      getRawMatchingData(pseudoName, pseudoArg);
    if (rawPropertyName.includes("\\/") || rawPropertyName.includes("\\.")) {
      throw new Error(
        `Invalid :${pseudoName} name pattern: ${rawPropertyName}`,
      );
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
          const realValue = ownerObjArr[i]?.value;
          if (propValueMatch instanceof RegExp) {
            isMatched = propValueMatch.test(convertTypeIntoString(realValue));
          } else {
            if (realValue === "null" || realValue === "undefined") {
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
  }, "isPropertyMatched");
  var isTextMatched = /* @__PURE__ */ __name((argsData) => {
    const { pseudoName, pseudoArg, domElement } = argsData;
    const textContent = getNodeTextContent(domElement);
    let isTextContentMatched;
    let pseudoArgToMatch = pseudoArg;
    if (
      pseudoArgToMatch.startsWith(SLASH) &&
      REGEXP_WITH_FLAGS_REGEXP.test(pseudoArgToMatch)
    ) {
      const flagsIndex = pseudoArgToMatch.lastIndexOf("/");
      const flagsStr = pseudoArgToMatch.substring(flagsIndex + 1);
      pseudoArgToMatch = pseudoArgToMatch
        .substring(0, flagsIndex + 1)
        .slice(1, -1)
        .replace(/\\([\\"])/g, "$1");
      let regex;
      try {
        regex = new RegExp(pseudoArgToMatch, flagsStr);
      } catch (e) {
        throw new Error(
          `Invalid argument of :${pseudoName}() pseudo-class: ${pseudoArg}`,
        );
      }
      isTextContentMatched = regex.test(textContent);
    } else {
      pseudoArgToMatch = pseudoArgToMatch.replace(/\\([\\()[\]"])/g, "$1");
      isTextContentMatched = textContent.includes(pseudoArgToMatch);
    }
    return isTextContentMatched;
  }, "isTextMatched");

  // src/selector/utils/absolute-finder.ts
  var getValidNumberAncestorArg = /* @__PURE__ */ __name(
    (rawArg, pseudoName) => {
      const deep = Number(rawArg);
      if (Number.isNaN(deep) || deep < 1 || deep >= 256) {
        throw new Error(
          `Invalid argument of :${pseudoName} pseudo-class: '${rawArg}'`,
        );
      }
      return deep;
    },
    "getValidNumberAncestorArg",
  );
  var getNthAncestor = /* @__PURE__ */ __name((domElement, nth, pseudoName) => {
    let ancestor = null;
    let i = 0;
    while (i < nth) {
      ancestor = domElement.parentElement;
      if (!ancestor) {
        throw new Error(
          `Out of DOM: Argument of :${pseudoName}() pseudo-class is too big \u2014 '${nth}'.`,
        );
      }
      domElement = ancestor;
      i += 1;
    }
    return ancestor;
  }, "getNthAncestor");
  var validateStandardSelector = /* @__PURE__ */ __name((selector) => {
    let isValid;
    try {
      document.querySelectorAll(selector);
      isValid = true;
    } catch (e) {
      isValid = false;
    }
    return isValid;
  }, "validateStandardSelector");

  // src/selector/utils/absolute-processor.ts
  var matcherWrapper = /* @__PURE__ */ __name(
    (callback, argsData, errorMessage) => {
      let isMatched;
      try {
        isMatched = callback(argsData);
      } catch (e) {
        logger.error(getErrorMessage(e));
        throw new Error(errorMessage);
      }
      return isMatched;
    },
    "matcherWrapper",
  );
  var getAbsolutePseudoError = /* @__PURE__ */ __name(
    (propDesc, pseudoName, pseudoArg) => {
      return `${MATCHING_ELEMENT_ERROR_PREFIX} ${propDesc}, may be invalid :${pseudoName}() pseudo-class arg: '${pseudoArg}'`;
    },
    "getAbsolutePseudoError",
  );
  var isMatchedByAbsolutePseudo = /* @__PURE__ */ __name(
    (domElement, pseudoName, pseudoArg) => {
      let argsData;
      let errorMessage;
      let callback;
      switch (pseudoName) {
        case CONTAINS_PSEUDO:
        case HAS_TEXT_PSEUDO:
        case ABP_CONTAINS_PSEUDO:
          callback = isTextMatched;
          argsData = { pseudoName, pseudoArg, domElement };
          errorMessage = getAbsolutePseudoError(
            "text content",
            pseudoName,
            pseudoArg,
          );
          break;
        case MATCHES_CSS_PSEUDO:
        case MATCHES_CSS_AFTER_PSEUDO:
        case MATCHES_CSS_BEFORE_PSEUDO:
          callback = isStyleMatched;
          argsData = { pseudoName, pseudoArg, domElement };
          errorMessage = getAbsolutePseudoError("style", pseudoName, pseudoArg);
          break;
        case MATCHES_ATTR_PSEUDO_CLASS_MARKER:
          callback = isAttributeMatched;
          argsData = { domElement, pseudoName, pseudoArg };
          errorMessage = getAbsolutePseudoError(
            "attributes",
            pseudoName,
            pseudoArg,
          );
          break;
        case MATCHES_PROPERTY_PSEUDO_CLASS_MARKER:
          callback = isPropertyMatched;
          argsData = { domElement, pseudoName, pseudoArg };
          errorMessage = getAbsolutePseudoError(
            "properties",
            pseudoName,
            pseudoArg,
          );
          break;
        default:
          throw new Error(`Unknown absolute pseudo-class :${pseudoName}()`);
      }
      return matcherWrapper(callback, argsData, errorMessage);
    },
    "isMatchedByAbsolutePseudo",
  );
  var findByAbsolutePseudoPseudo = {
    nthAncestor: (domElements, rawPseudoArg, pseudoName) => {
      const deep = getValidNumberAncestorArg(rawPseudoArg, pseudoName);
      const ancestors = domElements
        .map((domElement) => {
          let ancestor = null;
          try {
            ancestor = getNthAncestor(domElement, deep, pseudoName);
          } catch (e) {
            logger.error(getErrorMessage(e));
          }
          return ancestor;
        })
        .filter(isHtmlElement);
      return ancestors;
    },
    xpath: (domElements, rawPseudoArg) => {
      const foundElements = domElements.map((domElement) => {
        const result = [];
        let xpathResult;
        try {
          xpathResult = document.evaluate(
            rawPseudoArg,
            domElement,
            null,
            window.XPathResult.UNORDERED_NODE_ITERATOR_TYPE,
            null,
          );
        } catch (e) {
          logger.error(getErrorMessage(e));
          throw new Error(
            `Invalid argument of :xpath() pseudo-class: '${rawPseudoArg}'`,
          );
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
    upward: (domElements, rawPseudoArg) => {
      if (!validateStandardSelector(rawPseudoArg)) {
        throw new Error(
          `Invalid argument of :upward pseudo-class: '${rawPseudoArg}'`,
        );
      }
      const closestAncestors = domElements
        .map((domElement) => {
          const parent = domElement.parentElement;
          if (!parent) {
            return null;
          }
          return parent.closest(rawPseudoArg);
        })
        .filter(isHtmlElement);
      return closestAncestors;
    },
  };

  // src/selector/utils/query-helpers.ts
  var scopeDirectChildren = `${SCOPE_CSS_PSEUDO_CLASS}${CHILD_COMBINATOR}`;
  var scopeAnyChildren = `${SCOPE_CSS_PSEUDO_CLASS}${DESCENDANT_COMBINATOR}`;
  var getFirstInnerRegularChild = /* @__PURE__ */ __name(
    (selectorNode, pseudoName) => {
      return getFirstRegularChild(
        selectorNode.children,
        `RegularSelector is missing for :${pseudoName}() pseudo-class`,
      );
    },
    "getFirstInnerRegularChild",
  );
  var hasRelativesBySelectorList = /* @__PURE__ */ __name((argsData) => {
    const { element, relativeSelectorList, pseudoName } = argsData;
    return relativeSelectorList.children.every((selectorNode) => {
      const relativeRegularSelector = getFirstInnerRegularChild(
        selectorNode,
        pseudoName,
      );
      let specifiedSelector = "";
      let rootElement = null;
      const regularSelector = getNodeValue(relativeRegularSelector);
      if (
        regularSelector.startsWith(NEXT_SIBLING_COMBINATOR) ||
        regularSelector.startsWith(SUBSEQUENT_SIBLING_COMBINATOR)
      ) {
        rootElement = element.parentElement;
        const elementSelectorText = getElementSelectorDesc(element);
        specifiedSelector = `${scopeDirectChildren}${elementSelectorText}${regularSelector}`;
      } else if (regularSelector === ASTERISK) {
        rootElement = element;
        specifiedSelector = `${scopeAnyChildren}${ASTERISK}`;
      } else {
        specifiedSelector = `${scopeAnyChildren}${regularSelector}`;
        rootElement = element;
      }
      if (!rootElement) {
        throw new Error(
          `Selection by :${pseudoName}() pseudo-class is not possible`,
        );
      }
      let relativeElements;
      try {
        relativeElements = getElementsForSelectorNode(
          selectorNode,
          rootElement,
          specifiedSelector,
        );
      } catch (e) {
        logger.error(getErrorMessage(e));
        throw new Error(
          `Invalid selector for :${pseudoName}() pseudo-class: '${regularSelector}'`,
        );
      }
      return relativeElements.length > 0;
    });
  }, "hasRelativesBySelectorList");
  var isAnyElementBySelectorList = /* @__PURE__ */ __name((argsData) => {
    const { element, relativeSelectorList, pseudoName } = argsData;
    return relativeSelectorList.children.some((selectorNode) => {
      const relativeRegularSelector = getFirstInnerRegularChild(
        selectorNode,
        pseudoName,
      );
      const rootElement = getParent(
        element,
        `Selection by :${pseudoName}() pseudo-class is not possible`,
      );
      const specifiedSelector = `${scopeDirectChildren}${getNodeValue(relativeRegularSelector)}`;
      let anyElements;
      try {
        anyElements = getElementsForSelectorNode(
          selectorNode,
          rootElement,
          specifiedSelector,
        );
      } catch (e) {
        return false;
      }
      return anyElements.includes(element);
    });
  }, "isAnyElementBySelectorList");
  var notElementBySelectorList = /* @__PURE__ */ __name((argsData) => {
    const { element, relativeSelectorList, pseudoName } = argsData;
    return relativeSelectorList.children.every((selectorNode) => {
      const relativeRegularSelector = getFirstInnerRegularChild(
        selectorNode,
        pseudoName,
      );
      const rootElement = getParent(
        element,
        `Selection by :${pseudoName}() pseudo-class is not possible`,
      );
      const specifiedSelector = `${scopeDirectChildren}${getNodeValue(relativeRegularSelector)}`;
      let anyElements;
      try {
        anyElements = getElementsForSelectorNode(
          selectorNode,
          rootElement,
          specifiedSelector,
        );
      } catch (e) {
        logger.error(getErrorMessage(e));
        throw new Error(
          `Invalid selector for :${pseudoName}() pseudo-class: '${getNodeValue(relativeRegularSelector)}'`,
        );
      }
      return !anyElements.includes(element);
    });
  }, "notElementBySelectorList");
  var getByRegularSelector = /* @__PURE__ */ __name(
    (regularSelectorNode, root, specifiedSelector) => {
      const selectorText = specifiedSelector
        ? specifiedSelector
        : getNodeValue(regularSelectorNode);
      let selectedElements = [];
      try {
        selectedElements = Array.from(root.querySelectorAll(selectorText));
      } catch (e) {
        throw new Error(
          `Error: unable to select by '${selectorText}' \u2014 ${getErrorMessage(e)}`,
        );
      }
      return selectedElements;
    },
    "getByRegularSelector",
  );
  var getByExtendedSelector = /* @__PURE__ */ __name(
    (domElements, extendedSelectorNode) => {
      let foundElements = [];
      const extendedPseudoClassNode = getPseudoClassNode(extendedSelectorNode);
      const pseudoName = getNodeName(extendedPseudoClassNode);
      if (isAbsolutePseudoClass(pseudoName)) {
        const absolutePseudoArg = getNodeValue(
          extendedPseudoClassNode,
          `Missing arg for :${pseudoName}() pseudo-class`,
        );
        if (pseudoName === NTH_ANCESTOR_PSEUDO_CLASS_MARKER) {
          foundElements = findByAbsolutePseudoPseudo.nthAncestor(
            domElements,
            absolutePseudoArg,
            pseudoName,
          );
        } else if (pseudoName === XPATH_PSEUDO_CLASS_MARKER) {
          try {
            document.createExpression(absolutePseudoArg, null);
          } catch (e) {
            throw new Error(
              `Invalid argument of :${pseudoName}() pseudo-class: '${absolutePseudoArg}'`,
            );
          }
          foundElements = findByAbsolutePseudoPseudo.xpath(
            domElements,
            absolutePseudoArg,
          );
        } else if (pseudoName === UPWARD_PSEUDO_CLASS_MARKER) {
          if (Number.isNaN(Number(absolutePseudoArg))) {
            foundElements = findByAbsolutePseudoPseudo.upward(
              domElements,
              absolutePseudoArg,
            );
          } else {
            foundElements = findByAbsolutePseudoPseudo.nthAncestor(
              domElements,
              absolutePseudoArg,
              pseudoName,
            );
          }
        } else {
          foundElements = domElements.filter((element) => {
            return isMatchedByAbsolutePseudo(
              element,
              pseudoName,
              absolutePseudoArg,
            );
          });
        }
      } else if (isRelativePseudoClass(pseudoName)) {
        const relativeSelectorList = getRelativeSelectorListNode(
          extendedPseudoClassNode,
        );
        let relativePredicate;
        switch (pseudoName) {
          case HAS_PSEUDO_CLASS_MARKER:
          case ABP_HAS_PSEUDO_CLASS_MARKER:
            relativePredicate = /* @__PURE__ */ __name(
              (element) =>
                hasRelativesBySelectorList({
                  element,
                  relativeSelectorList,
                  pseudoName,
                }),
              "relativePredicate",
            );
            break;
          case IS_PSEUDO_CLASS_MARKER:
            relativePredicate = /* @__PURE__ */ __name(
              (element) =>
                isAnyElementBySelectorList({
                  element,
                  relativeSelectorList,
                  pseudoName,
                }),
              "relativePredicate",
            );
            break;
          case NOT_PSEUDO_CLASS_MARKER:
            relativePredicate = /* @__PURE__ */ __name(
              (element) =>
                notElementBySelectorList({
                  element,
                  relativeSelectorList,
                  pseudoName,
                }),
              "relativePredicate",
            );
            break;
          default:
            throw new Error(`Unknown relative pseudo-class: '${pseudoName}'`);
        }
        foundElements = domElements.filter(relativePredicate);
      } else {
        throw new Error(`Unknown extended pseudo-class: '${pseudoName}'`);
      }
      return foundElements;
    },
    "getByExtendedSelector",
  );
  var getByFollowingRegularSelector = /* @__PURE__ */ __name(
    (domElements, regularSelectorNode) => {
      let foundElements = [];
      const value = getNodeValue(regularSelectorNode);
      if (value.startsWith(CHILD_COMBINATOR)) {
        foundElements = domElements.map((root) => {
          const specifiedSelector = `${SCOPE_CSS_PSEUDO_CLASS}${value}`;
          return getByRegularSelector(
            regularSelectorNode,
            root,
            specifiedSelector,
          );
        });
      } else if (
        value.startsWith(NEXT_SIBLING_COMBINATOR) ||
        value.startsWith(SUBSEQUENT_SIBLING_COMBINATOR)
      ) {
        foundElements = domElements.map((element) => {
          const rootElement = element.parentElement;
          if (!rootElement) {
            return [];
          }
          const elementSelectorText = getElementSelectorDesc(element);
          const specifiedSelector = `${scopeDirectChildren}${elementSelectorText}${value}`;
          const selected = getByRegularSelector(
            regularSelectorNode,
            rootElement,
            specifiedSelector,
          );
          return selected;
        });
      } else {
        foundElements = domElements.map((root) => {
          const specifiedSelector = `${scopeAnyChildren}${getNodeValue(regularSelectorNode)}`;
          return getByRegularSelector(
            regularSelectorNode,
            root,
            specifiedSelector,
          );
        });
      }
      return flatten(foundElements);
    },
    "getByFollowingRegularSelector",
  );
  var getElementsForSelectorNode = /* @__PURE__ */ __name(
    (selectorNode, root, specifiedSelector) => {
      let selectedElements = [];
      let i = 0;
      while (i < selectorNode.children.length) {
        const selectorNodeChild = getItemByIndex(
          selectorNode.children,
          i,
          "selectorNodeChild should be specified",
        );
        if (i === 0) {
          selectedElements = getByRegularSelector(
            selectorNodeChild,
            root,
            specifiedSelector,
          );
        } else if (isExtendedSelectorNode(selectorNodeChild)) {
          selectedElements = getByExtendedSelector(
            selectedElements,
            selectorNodeChild,
          );
        } else if (isRegularSelectorNode(selectorNodeChild)) {
          selectedElements = getByFollowingRegularSelector(
            selectedElements,
            selectorNodeChild,
          );
        }
        i += 1;
      }
      return selectedElements;
    },
    "getElementsForSelectorNode",
  );

  // src/selector/query.ts
  var selectElementsByAst = /* @__PURE__ */ __name((ast, doc = document) => {
    const selectedElements = [];
    ast.children.forEach((selectorNode) => {
      selectedElements.push(...getElementsForSelectorNode(selectorNode, doc));
    });
    const uniqueElements = [...new Set(flatten(selectedElements))];
    return uniqueElements;
  }, "selectElementsByAst");
  var ExtCssDocument = class {
    constructor() {
      this.astCache = /* @__PURE__ */ new Map();
    }
    saveAstToCache(selector, ast) {
      this.astCache.set(selector, ast);
    }
    getAstFromCache(selector) {
      const cachedAst = this.astCache.get(selector) || null;
      return cachedAst;
    }
    getSelectorAst(selector) {
      let ast = this.getAstFromCache(selector);
      if (!ast) {
        ast = parse(selector);
      }
      this.saveAstToCache(selector, ast);
      return ast;
    }
    querySelectorAll(selector) {
      const ast = this.getSelectorAst(selector);
      return selectElementsByAst(ast);
    }
  };
  __name(ExtCssDocument, "ExtCssDocument");
  var extCssDocument = new ExtCssDocument();

  // src/common/utils/objects.ts
  var getObjectFromEntries = /* @__PURE__ */ __name((entries) => {
    const object = {};
    entries.forEach((el) => {
      const [key, value] = el;
      object[key] = value;
    });
    return object;
  }, "getObjectFromEntries");

  // src/css-rule/helpers.ts
  var DEBUG_PSEUDO_PROPERTY_KEY = "debug";
  var parseRemoveSelector = /* @__PURE__ */ __name((rawSelector) => {
    const VALID_REMOVE_MARKER = `${COLON}${REMOVE_PSEUDO_MARKER}${BRACKET.PARENTHESES.LEFT}${BRACKET.PARENTHESES.RIGHT}`;
    const INVALID_REMOVE_MARKER = `${COLON}${REMOVE_PSEUDO_MARKER}${BRACKET.PARENTHESES.LEFT}`;
    let selector;
    let shouldRemove = false;
    const firstIndex = rawSelector.indexOf(VALID_REMOVE_MARKER);
    if (firstIndex === 0) {
      throw new Error(
        `${REMOVE_ERROR_PREFIX.NO_TARGET_SELECTOR}: '${rawSelector}'`,
      );
    } else if (firstIndex > 0) {
      if (firstIndex !== rawSelector.lastIndexOf(VALID_REMOVE_MARKER)) {
        throw new Error(
          `${REMOVE_ERROR_PREFIX.MULTIPLE_USAGE}: '${rawSelector}'`,
        );
      } else if (firstIndex + VALID_REMOVE_MARKER.length < rawSelector.length) {
        throw new Error(
          `${REMOVE_ERROR_PREFIX.INVALID_POSITION}: '${rawSelector}'`,
        );
      } else {
        selector = rawSelector.substring(0, firstIndex);
        shouldRemove = true;
      }
    } else if (rawSelector.includes(INVALID_REMOVE_MARKER)) {
      throw new Error(
        `${REMOVE_ERROR_PREFIX.INVALID_REMOVE}: '${rawSelector}'`,
      );
    } else {
      selector = rawSelector;
    }
    const stylesOfSelector = shouldRemove
      ? [
          {
            property: REMOVE_PSEUDO_MARKER,
            value: PSEUDO_PROPERTY_POSITIVE_VALUE,
          },
        ]
      : [];
    return { selector, stylesOfSelector };
  }, "parseRemoveSelector");
  var parseSelectorRulePart = /* @__PURE__ */ __name(
    (selectorBuffer, extCssDoc) => {
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
        stylesOfSelector = removeSelectorData.stylesOfSelector;
        ast = extCssDoc.getSelectorAst(selector);
        success = true;
      } catch (e) {
        success = false;
      }
      return { success, selector, ast, stylesOfSelector };
    },
    "parseSelectorRulePart",
  );
  var createRawResultsMap = /* @__PURE__ */ __name(() => {
    return /* @__PURE__ */ new Map();
  }, "createRawResultsMap");
  var saveToRawResults = /* @__PURE__ */ __name((rawResults, rawRuleData) => {
    const { selector, ast, rawStyles } = rawRuleData;
    if (!rawStyles) {
      throw new Error(`No style declaration for selector: '${selector}'`);
    }
    if (!ast) {
      throw new Error(`No ast parsed for selector: '${selector}'`);
    }
    const storedRuleData = rawResults.get(selector);
    if (!storedRuleData) {
      rawResults.set(selector, { ast, styles: rawStyles });
    } else {
      storedRuleData.styles.push(...rawStyles);
    }
  }, "saveToRawResults");
  var isRemoveSetInStyles = /* @__PURE__ */ __name((styles) => {
    return styles.some((s) => {
      return (
        s.property === REMOVE_PSEUDO_MARKER &&
        s.value === PSEUDO_PROPERTY_POSITIVE_VALUE
      );
    });
  }, "isRemoveSetInStyles");
  var getDebugStyleValue = /* @__PURE__ */ __name((styles) => {
    const debugStyle = styles.find((s) => {
      return s.property === DEBUG_PSEUDO_PROPERTY_KEY;
    });
    return debugStyle?.value;
  }, "getDebugStyleValue");
  var prepareRuleData = /* @__PURE__ */ __name((rawRuleData) => {
    const { selector, ast, rawStyles } = rawRuleData;
    if (!ast) {
      throw new Error(`AST should be parsed for selector: '${selector}'`);
    }
    if (!rawStyles) {
      throw new Error(`Styles should be parsed for selector: '${selector}'`);
    }
    const ruleData = { selector, ast };
    const debugValue = getDebugStyleValue(rawStyles);
    const shouldRemove = isRemoveSetInStyles(rawStyles);
    let styles = rawStyles;
    if (debugValue) {
      styles = rawStyles.filter(
        (s) => s.property !== DEBUG_PSEUDO_PROPERTY_KEY,
      );
      if (
        debugValue === PSEUDO_PROPERTY_POSITIVE_VALUE ||
        debugValue === DEBUG_PSEUDO_PROPERTY_GLOBAL_VALUE
      ) {
        ruleData.debug = debugValue;
      }
    }
    if (shouldRemove) {
      ruleData.style = {
        [REMOVE_PSEUDO_MARKER]: PSEUDO_PROPERTY_POSITIVE_VALUE,
      };
      const contentStyle = styles.find(
        (s) => s.property === CONTENT_CSS_PROPERTY,
      );
      if (contentStyle) {
        ruleData.style[CONTENT_CSS_PROPERTY] = contentStyle.value;
      }
    } else {
      if (styles.length > 0) {
        const stylesAsEntries = styles.map((style) => {
          const { property, value } = style;
          return [property, value];
        });
        const preparedStyleData = getObjectFromEntries(stylesAsEntries);
        ruleData.style = preparedStyleData;
      }
    }
    return ruleData;
  }, "prepareRuleData");
  var combineRulesData = /* @__PURE__ */ __name((rawResults) => {
    const results = [];
    rawResults.forEach((value, key) => {
      const selector = key;
      const { ast, styles: rawStyles } = value;
      results.push(prepareRuleData({ selector, ast, rawStyles }));
    });
    return results;
  }, "combineRulesData");

  // src/style-block/tokenizer.ts
  var tokenizeStyleBlock = /* @__PURE__ */ __name((rawStyle) => {
    const styleDeclaration = rawStyle.trim();
    return tokenize(styleDeclaration, SUPPORTED_STYLE_DECLARATION_MARKS);
  }, "tokenizeStyleBlock");

  // src/style-block/parser.ts
  var DECLARATION_PART = {
    PROPERTY: "property",
    VALUE: "value",
  };
  var isValueQuotesOpen = /* @__PURE__ */ __name((context) => {
    return context.bufferValue !== "" && context.valueQuoteMark !== null;
  }, "isValueQuotesOpen");
  var collectStyle = /* @__PURE__ */ __name((context) => {
    context.styles.push({
      property: context.bufferProperty.trim(),
      value: context.bufferValue.trim(),
    });
    context.bufferProperty = "";
    context.bufferValue = "";
  }, "collectStyle");
  var processPropertyToken = /* @__PURE__ */ __name(
    (context, styleBlock, token) => {
      const { value: tokenValue } = token;
      switch (token.type) {
        case TOKEN_TYPE.WORD:
          if (context.bufferProperty.length > 0) {
            throw new Error(
              `Invalid style property in style block: '${styleBlock}'`,
            );
          }
          context.bufferProperty += tokenValue;
          break;
        case TOKEN_TYPE.MARK:
          if (tokenValue === COLON) {
            if (context.bufferProperty.trim().length === 0) {
              throw new Error(
                `Missing style property before ':' in style block: '${styleBlock}'`,
              );
            }
            context.bufferProperty = context.bufferProperty.trim();
            context.processing = DECLARATION_PART.VALUE;
          } else if (WHITE_SPACE_CHARACTERS.includes(tokenValue)) {
          } else {
            throw new Error(
              `Invalid style declaration in style block: '${styleBlock}'`,
            );
          }
          break;
        default:
          throw new Error(
            `Unsupported style property character: '${tokenValue}' in style block: '${styleBlock}'`,
          );
      }
    },
    "processPropertyToken",
  );
  var processValueToken = /* @__PURE__ */ __name(
    (context, styleBlock, token) => {
      const { value: tokenValue } = token;
      if (token.type === TOKEN_TYPE.WORD) {
        context.bufferValue += tokenValue;
      } else {
        switch (tokenValue) {
          case COLON:
            if (!isValueQuotesOpen(context)) {
              throw new Error(
                `Invalid style value for property '${context.bufferProperty}' in style block: '${styleBlock}'`,
              );
            }
            context.bufferValue += tokenValue;
            break;
          case SEMICOLON:
            if (isValueQuotesOpen(context)) {
              context.bufferValue += tokenValue;
            } else {
              collectStyle(context);
              context.processing = DECLARATION_PART.PROPERTY;
            }
            break;
          case SINGLE_QUOTE:
          case DOUBLE_QUOTE:
            if (context.valueQuoteMark === null) {
              context.valueQuoteMark = tokenValue;
            } else if (
              !context.bufferValue.endsWith(BACKSLASH) &&
              context.valueQuoteMark === tokenValue
            ) {
              context.valueQuoteMark = null;
            }
            context.bufferValue += tokenValue;
            break;
          case BACKSLASH:
            if (!isValueQuotesOpen(context)) {
              throw new Error(
                `Invalid style value for property '${context.bufferProperty}' in style block: '${styleBlock}'`,
              );
            }
            context.bufferValue += tokenValue;
            break;
          case SPACE:
          case TAB:
          case CARRIAGE_RETURN:
          case LINE_FEED:
          case FORM_FEED:
            if (context.bufferValue.length > 0) {
              context.bufferValue += tokenValue;
            }
            break;
          default:
            throw new Error(`Unknown style declaration token: '${tokenValue}'`);
        }
      }
    },
    "processValueToken",
  );
  var parseStyleBlock = /* @__PURE__ */ __name((rawStyleBlock) => {
    const styleBlock = rawStyleBlock.trim();
    const tokens = tokenizeStyleBlock(styleBlock);
    const context = {
      processing: DECLARATION_PART.PROPERTY,
      styles: [],
      bufferProperty: "",
      bufferValue: "",
      valueQuoteMark: null,
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
        throw new Error("Style declaration parsing failed");
      }
      i += 1;
    }
    if (isValueQuotesOpen(context)) {
      throw new Error(
        `Unbalanced style declaration quotes in style block: '${styleBlock}'`,
      );
    }
    if (context.bufferProperty.length > 0) {
      if (context.bufferValue.length === 0) {
        throw new Error(
          `Missing style value for property '${context.bufferProperty}' in style block '${styleBlock}'`,
        );
      }
      collectStyle(context);
    }
    if (context.styles.length === 0) {
      throw new Error(STYLE_ERROR_PREFIX.NO_STYLE);
    }
    return context.styles;
  }, "parseStyleBlock");

  // src/css-rule/parser.ts
  var getLeftCurlyBracketIndexes = /* @__PURE__ */ __name((cssRule) => {
    const indexes = [];
    for (let i = 0; i < cssRule.length; i += 1) {
      if (cssRule[i] === BRACKET.CURLY.LEFT) {
        indexes.push(i);
      }
    }
    return indexes;
  }, "getLeftCurlyBracketIndexes");
  var parseRule = /* @__PURE__ */ __name((rawCssRule, extCssDoc) => {
    const cssRule = rawCssRule.trim();
    if (
      cssRule.includes(`${SLASH}${ASTERISK}`) &&
      cssRule.includes(`${ASTERISK}${SLASH}`)
    ) {
      throw new Error(STYLE_ERROR_PREFIX.NO_COMMENT);
    }
    const leftCurlyBracketIndexes = getLeftCurlyBracketIndexes(cssRule);
    if (getFirst(leftCurlyBracketIndexes) === 0) {
      throw new Error(NO_SELECTOR_ERROR_PREFIX);
    }
    let selectorData;
    if (
      leftCurlyBracketIndexes.length > 0 &&
      !cssRule.includes(BRACKET.CURLY.RIGHT)
    ) {
      throw new Error(
        `${STYLE_ERROR_PREFIX.NO_STYLE} OR ${STYLE_ERROR_PREFIX.UNCLOSED_STYLE}`,
      );
    }
    if (
      leftCurlyBracketIndexes.length === 0 ||
      !cssRule.includes(BRACKET.CURLY.RIGHT)
    ) {
      try {
        selectorData = parseSelectorRulePart(cssRule, extCssDoc);
        if (selectorData.success) {
          if (selectorData.stylesOfSelector?.length === 0) {
            throw new Error(STYLE_ERROR_PREFIX.NO_STYLE_OR_REMOVE);
          }
          return {
            selector: selectorData.selector.trim(),
            ast: selectorData.ast,
            rawStyles: selectorData.stylesOfSelector,
          };
        } else {
          throw new Error("Invalid selector");
        }
      } catch (e) {
        throw new Error(getErrorMessage(e));
      }
    }
    let selectorBuffer;
    let styleBlockBuffer;
    const rawRuleData = {
      selector: "",
    };
    for (let i = leftCurlyBracketIndexes.length - 1; i > -1; i -= 1) {
      const index = leftCurlyBracketIndexes[i];
      if (!index) {
        throw new Error(
          `Impossible to continue, no '{' to process for rule: '${cssRule}'`,
        );
      }
      selectorBuffer = cssRule.slice(0, index);
      styleBlockBuffer = cssRule.slice(index + 1, cssRule.length - 1);
      selectorData = parseSelectorRulePart(selectorBuffer, extCssDoc);
      if (selectorData.success) {
        rawRuleData.selector = selectorData.selector.trim();
        rawRuleData.ast = selectorData.ast;
        rawRuleData.rawStyles = selectorData.stylesOfSelector;
        const parsedStyles = parseStyleBlock(styleBlockBuffer);
        rawRuleData.rawStyles?.push(...parsedStyles);
        break;
      } else {
        continue;
      }
    }
    if (rawRuleData.selector?.length === 0) {
      throw new Error("Selector in not valid");
    }
    return rawRuleData;
  }, "parseRule");
  var parseRules = /* @__PURE__ */ __name((rawCssRules, extCssDoc) => {
    const rawResults = createRawResultsMap();
    const warnings = [];
    const uniqueRules = [...new Set(rawCssRules.map((r) => r.trim()))];
    uniqueRules.forEach((rule) => {
      try {
        saveToRawResults(rawResults, parseRule(rule, extCssDoc));
      } catch (e) {
        const errorMessage = getErrorMessage(e);
        warnings.push(`'${rule}' - error: '${errorMessage}'`);
      }
    });
    if (warnings.length > 0) {
      logger.info(`Invalid rules:
  ${warnings.join("\n  ")}`);
    }
    return combineRulesData(rawResults);
  }, "parseRules");

  // src/stylesheet/parser.ts
  var REGEXP_DECLARATION_END = /[;}]/g;
  var REGEXP_DECLARATION_DIVIDER = /[;:}]/g;
  var REGEXP_NON_WHITESPACE = /\S/g;
  var restoreRuleAcc = /* @__PURE__ */ __name((context) => {
    context.rawRuleData = {
      selector: "",
    };
  }, "restoreRuleAcc");
  var parseSelectorPart = /* @__PURE__ */ __name((context, extCssDoc) => {
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
        throw new Error(
          `${STYLE_ERROR_PREFIX.NO_STYLE_OR_REMOVE}: '${context.cssToParse}'`,
        );
      }
      context.cssToParse = "";
    }
    let stylesOfSelector = [];
    let success = false;
    let ast;
    try {
      selector = removeSelectorData.selector;
      stylesOfSelector = removeSelectorData.stylesOfSelector;
      ast = extCssDoc.getSelectorAst(selector);
      success = true;
    } catch (e) {
      success = false;
    }
    if (context.nextIndex > 0) {
      context.cssToParse = context.cssToParse.slice(context.nextIndex);
    }
    return { success, selector, ast, stylesOfSelector };
  }, "parseSelectorPart");
  var parseUntilClosingBracket = /* @__PURE__ */ __name((context, styles) => {
    REGEXP_DECLARATION_DIVIDER.lastIndex = context.nextIndex;
    let match = REGEXP_DECLARATION_DIVIDER.exec(context.cssToParse);
    if (match === null) {
      throw new Error(
        `${STYLE_ERROR_PREFIX.INVALID_STYLE}: '${context.cssToParse}'`,
      );
    }
    let matchPos = match.index;
    let matched = match[0];
    if (matched === BRACKET.CURLY.RIGHT) {
      const declarationChunk = context.cssToParse.slice(
        context.nextIndex,
        matchPos,
      );
      if (declarationChunk.trim().length === 0) {
        if (styles.length === 0) {
          throw new Error(
            `${STYLE_ERROR_PREFIX.NO_STYLE}: '${context.cssToParse}'`,
          );
        }
      } else {
        throw new Error(
          `${STYLE_ERROR_PREFIX.INVALID_STYLE}: '${context.cssToParse}'`,
        );
      }
      return matchPos;
    }
    if (matched === COLON) {
      const colonIndex = matchPos;
      REGEXP_DECLARATION_END.lastIndex = colonIndex;
      match = REGEXP_DECLARATION_END.exec(context.cssToParse);
      if (match === null) {
        throw new Error(
          `${STYLE_ERROR_PREFIX.UNCLOSED_STYLE}: '${context.cssToParse}'`,
        );
      }
      matchPos = match.index;
      matched = match[0];
      const property = context.cssToParse
        .slice(context.nextIndex, colonIndex)
        .trim();
      if (property.length === 0) {
        throw new Error(
          `${STYLE_ERROR_PREFIX.NO_PROPERTY}: '${context.cssToParse}'`,
        );
      }
      const value = context.cssToParse.slice(colonIndex + 1, matchPos).trim();
      if (value.length === 0) {
        throw new Error(
          `${STYLE_ERROR_PREFIX.NO_VALUE}: '${context.cssToParse}'`,
        );
      }
      styles.push({ property, value });
      if (matched === BRACKET.CURLY.RIGHT) {
        return matchPos;
      }
    }
    context.cssToParse = context.cssToParse.slice(matchPos + 1);
    context.nextIndex = 0;
    return parseUntilClosingBracket(context, styles);
  }, "parseUntilClosingBracket");
  var parseNextStyle = /* @__PURE__ */ __name((context) => {
    const styles = [];
    const styleEndPos = parseUntilClosingBracket(context, styles);
    REGEXP_NON_WHITESPACE.lastIndex = styleEndPos + 1;
    const match = REGEXP_NON_WHITESPACE.exec(context.cssToParse);
    if (match === null) {
      context.cssToParse = "";
      return styles;
    }
    const matchPos = match.index;
    context.cssToParse = context.cssToParse.slice(matchPos);
    return styles;
  }, "parseNextStyle");
  var parseStylesheet = /* @__PURE__ */ __name((rawStylesheet, extCssDoc) => {
    const stylesheet = rawStylesheet.trim();
    if (
      stylesheet.includes(`${SLASH}${ASTERISK}`) &&
      stylesheet.includes(`${ASTERISK}${SLASH}`)
    ) {
      throw new Error(
        `${STYLE_ERROR_PREFIX.NO_COMMENT} in stylesheet: '${stylesheet}'`,
      );
    }
    const context = {
      isSelector: true,
      nextIndex: 0,
      cssToParse: stylesheet,
      selectorBuffer: "",
      rawRuleData: { selector: "" },
    };
    const rawResults = createRawResultsMap();
    let selectorData;
    while (context.cssToParse) {
      if (context.isSelector) {
        context.nextIndex = context.cssToParse.indexOf(BRACKET.CURLY.LEFT);
        if (context.selectorBuffer.length === 0 && context.nextIndex === 0) {
          throw new Error(
            `${STYLE_ERROR_PREFIX.NO_SELECTOR}: '${context.cssToParse}'`,
          );
        }
        if (context.nextIndex === -1) {
          context.selectorBuffer = context.cssToParse;
        } else {
          context.selectorBuffer += context.cssToParse.slice(
            0,
            context.nextIndex,
          );
        }
        selectorData = parseSelectorPart(context, extCssDoc);
        if (selectorData.success) {
          context.rawRuleData.selector = selectorData.selector.trim();
          context.rawRuleData.ast = selectorData.ast;
          context.rawRuleData.rawStyles = selectorData.stylesOfSelector;
          context.isSelector = false;
          if (context.nextIndex === -1) {
            saveToRawResults(rawResults, context.rawRuleData);
            restoreRuleAcc(context);
          } else {
            context.nextIndex = 1;
            context.selectorBuffer = "";
          }
        } else {
          context.selectorBuffer += BRACKET.CURLY.LEFT;
          context.cssToParse = context.cssToParse.slice(1);
        }
      } else {
        const parsedStyles = parseNextStyle(context);
        context.rawRuleData.rawStyles?.push(...parsedStyles);
        saveToRawResults(rawResults, context.rawRuleData);
        context.nextIndex = 0;
        restoreRuleAcc(context);
        context.isSelector = true;
      }
    }
    return combineRulesData(rawResults);
  }, "parseStylesheet");

  // src/common/utils/numbers.ts
  var isNumber = /* @__PURE__ */ __name((arg) => {
    return typeof arg === "number" && !Number.isNaN(arg);
  }, "isNumber");

  // src/extended-css/helpers/throttle-wrapper.ts
  var _ThrottleWrapper = class {
    constructor(callback) {
      this.callback = callback;
      this.executeCallback = this.executeCallback.bind(this);
    }
    executeCallback() {
      this.lastRunTime = performance.now();
      if (isNumber(this.timerId)) {
        clearTimeout(this.timerId);
        delete this.timerId;
      }
      this.callback();
    }
    run() {
      if (isNumber(this.timerId)) {
        return;
      }
      if (isNumber(this.lastRunTime)) {
        const elapsedTime = performance.now() - this.lastRunTime;
        if (elapsedTime < _ThrottleWrapper.THROTTLE_DELAY_MS) {
          this.timerId = window.setTimeout(
            this.executeCallback,
            _ThrottleWrapper.THROTTLE_DELAY_MS - elapsedTime,
          );
          return;
        }
      }
      this.timerId = window.setTimeout(this.executeCallback);
    }
  };
  var ThrottleWrapper = _ThrottleWrapper;
  __name(ThrottleWrapper, "ThrottleWrapper");
  ThrottleWrapper.THROTTLE_DELAY_MS = 150;

  // src/extended-css/helpers/event-tracker.ts
  var LAST_EVENT_TIMEOUT_MS = 10;
  var IGNORED_EVENTS = ["mouseover", "mouseleave", "mouseenter", "mouseout"];
  var SUPPORTED_EVENTS = [
    "keydown",
    "keypress",
    "keyup",
    "auxclick",
    "click",
    "contextmenu",
    "dblclick",
    "mousedown",
    "mouseenter",
    "mouseleave",
    "mousemove",
    "mouseover",
    "mouseout",
    "mouseup",
    "pointerlockchange",
    "pointerlockerror",
    "select",
    "wheel",
  ];
  var SAFARI_PROBLEMATIC_EVENTS = ["wheel"];
  var EventTracker = class {
    constructor() {
      this.getLastEventType = /* @__PURE__ */ __name(
        () => this.lastEventType,
        "getLastEventType",
      );
      this.getTimeSinceLastEvent = /* @__PURE__ */ __name(() => {
        if (!this.lastEventTime) {
          return null;
        }
        return Date.now() - this.lastEventTime;
      }, "getTimeSinceLastEvent");
      this.trackedEvents = isSafariBrowser
        ? SUPPORTED_EVENTS.filter(
            (event) => !SAFARI_PROBLEMATIC_EVENTS.includes(event),
          )
        : SUPPORTED_EVENTS;
      this.trackedEvents.forEach((eventName) => {
        document.documentElement.addEventListener(
          eventName,
          this.trackEvent,
          true,
        );
      });
    }
    trackEvent(event) {
      this.lastEventType = event.type;
      this.lastEventTime = Date.now();
    }
    isIgnoredEventType() {
      const lastEventType = this.getLastEventType();
      const sinceLastEventTime = this.getTimeSinceLastEvent();
      return (
        !!lastEventType &&
        IGNORED_EVENTS.includes(lastEventType) &&
        !!sinceLastEventTime &&
        sinceLastEventTime < LAST_EVENT_TIMEOUT_MS
      );
    }
    stopTracking() {
      this.trackedEvents.forEach((eventName) => {
        document.documentElement.removeEventListener(
          eventName,
          this.trackEvent,
          true,
        );
      });
    }
  };
  __name(EventTracker, "EventTracker");

  // src/extended-css/helpers/document-observer.ts
  function shouldIgnoreMutations(mutations) {
    return !mutations.some((m) => m.type !== "attributes");
  }
  __name(shouldIgnoreMutations, "shouldIgnoreMutations");
  function observeDocument(context) {
    if (context.isDomObserved) {
      return;
    }
    context.isDomObserved = true;
    context.domMutationObserver = new natives.MutationObserver((mutations) => {
      if (!mutations || mutations.length === 0) {
        return;
      }
      const eventTracker = new EventTracker();
      if (
        eventTracker.isIgnoredEventType() &&
        shouldIgnoreMutations(mutations)
      ) {
        return;
      }
      context.eventTracker = eventTracker;
      context.scheduler.run();
    });
    context.domMutationObserver.observe(document, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ["id", "class"],
    });
  }
  __name(observeDocument, "observeDocument");
  function disconnectDocument(context) {
    if (!context.isDomObserved) {
      return;
    }
    context.isDomObserved = false;
    if (context.domMutationObserver) {
      context.domMutationObserver.disconnect();
    }
    if (context.eventTracker) {
      context.eventTracker.stopTracking();
    }
  }
  __name(disconnectDocument, "disconnectDocument");

  // src/extended-css/helpers/style-setter.ts
  var CONTENT_ATTR_PREFIX_REGEXP = /^("|')adguard.+?/;
  var removeElement = /* @__PURE__ */ __name((context, affectedElement) => {
    const { node } = affectedElement;
    affectedElement.removed = true;
    const elementSelector = getElementSelectorPath(node);
    const elementRemovalsCounter =
      context.removalsStatistic[elementSelector] || 0;
    if (elementRemovalsCounter > MAX_STYLE_PROTECTION_COUNT) {
      logger.error(
        `ExtendedCss: infinite loop protection for selector: '${elementSelector}'`,
      );
      return;
    }
    if (node.parentElement) {
      node.parentElement.removeChild(node);
      context.removalsStatistic[elementSelector] = elementRemovalsCounter + 1;
    }
  }, "removeElement");
  var setStyleToElement = /* @__PURE__ */ __name((node, style) => {
    if (!(node instanceof HTMLElement)) {
      return;
    }
    Object.keys(style).forEach((prop) => {
      if (typeof node.style.getPropertyValue(prop.toString()) !== "undefined") {
        let value = style[prop];
        if (!value) {
          return;
        }
        if (
          prop === CONTENT_CSS_PROPERTY &&
          value.match(CONTENT_ATTR_PREFIX_REGEXP)
        ) {
          return;
        }
        value = removeSuffix(value.trim(), "!important").trim();
        node.style.setProperty(prop, value, "important");
      }
    });
  }, "setStyleToElement");
  var isIAffectedElement = /* @__PURE__ */ __name((affectedElement) => {
    return (
      "node" in affectedElement &&
      "rules" in affectedElement &&
      affectedElement.rules instanceof Array
    );
  }, "isIAffectedElement");
  var isAffectedElement = /* @__PURE__ */ __name((affectedElement) => {
    return (
      "node" in affectedElement &&
      "originalStyle" in affectedElement &&
      "rules" in affectedElement &&
      affectedElement.rules instanceof Array
    );
  }, "isAffectedElement");
  var applyStyle = /* @__PURE__ */ __name((context, rawAffectedElement) => {
    if (rawAffectedElement.protectionObserver) {
      return;
    }
    let affectedElement;
    if (context.beforeStyleApplied) {
      if (!isIAffectedElement(rawAffectedElement)) {
        throw new Error(
          "Returned IAffectedElement should have 'node' and 'rules' properties",
        );
      }
      affectedElement = context.beforeStyleApplied(rawAffectedElement);
      if (!affectedElement) {
        throw new Error(
          "Callback 'beforeStyleApplied' should return IAffectedElement",
        );
      }
    } else {
      affectedElement = rawAffectedElement;
    }
    if (!isAffectedElement(affectedElement)) {
      throw new Error(
        "Returned IAffectedElement should have 'node' and 'rules' properties",
      );
    }
    const { node, rules } = affectedElement;
    for (let i = 0; i < rules.length; i += 1) {
      const rule = rules[i];
      const selector = rule?.selector;
      const style = rule?.style;
      const debug = rule?.debug;
      if (style) {
        if (style[REMOVE_PSEUDO_MARKER] === PSEUDO_PROPERTY_POSITIVE_VALUE) {
          removeElement(context, affectedElement);
          return;
        }
        setStyleToElement(node, style);
      } else if (!debug) {
        throw new Error(
          `No style declaration in rule for selector: '${selector}'`,
        );
      }
    }
  }, "applyStyle");
  var revertStyle = /* @__PURE__ */ __name((affectedElement) => {
    if (affectedElement.protectionObserver) {
      affectedElement.protectionObserver.disconnect();
    }
    affectedElement.node.style.cssText = affectedElement.originalStyle;
  }, "revertStyle");

  // src/extended-css/helpers/mutation-observer.ts
  var ExtMutationObserver = class {
    constructor(protectionCallback) {
      this.styleProtectionCount = 0;
      this.observer = new natives.MutationObserver((mutations) => {
        if (!mutations.length) {
          return;
        }
        this.styleProtectionCount += 1;
        protectionCallback(mutations, this);
      });
    }
    observe(target, options) {
      if (this.styleProtectionCount < MAX_STYLE_PROTECTION_COUNT) {
        this.observer.observe(target, options);
      } else {
        logger.error("ExtendedCss: infinite loop protection for style");
      }
    }
    disconnect() {
      this.observer.disconnect();
    }
  };
  __name(ExtMutationObserver, "ExtMutationObserver");

  // src/extended-css/helpers/style-protector.ts
  var PROTECTION_OBSERVER_OPTIONS = {
    attributes: true,
    attributeOldValue: true,
    attributeFilter: ["style"],
  };
  var createProtectionCallback = /* @__PURE__ */ __name((styles) => {
    const protectionCallback = /* @__PURE__ */ __name(
      (mutations, extObserver) => {
        if (!mutations[0]) {
          return;
        }
        const { target } = mutations[0];
        extObserver.disconnect();
        styles.forEach((style) => {
          setStyleToElement(target, style);
        });
        extObserver.observe(target, PROTECTION_OBSERVER_OPTIONS);
      },
      "protectionCallback",
    );
    return protectionCallback;
  }, "createProtectionCallback");
  var protectStyleAttribute = /* @__PURE__ */ __name((node, rules) => {
    if (!natives.MutationObserver) {
      return null;
    }
    const styles = [];
    rules.forEach((ruleData) => {
      const { style } = ruleData;
      if (style) {
        styles.push(style);
      }
    });
    const protectionObserver = new ExtMutationObserver(
      createProtectionCallback(styles),
    );
    protectionObserver.observe(node, PROTECTION_OBSERVER_OPTIONS);
    return protectionObserver;
  }, "protectStyleAttribute");

  // src/extended-css/helpers/timing-stats.ts
  var STATS_DECIMAL_DIGITS_COUNT = 4;
  var TimingStats = class {
    constructor() {
      this.appliesTimings = [];
      this.appliesCount = 0;
      this.timingsSum = 0;
      this.meanTiming = 0;
      this.squaredSum = 0;
      this.standardDeviation = 0;
    }
    push(elapsedTimeMs) {
      this.appliesTimings.push(elapsedTimeMs);
      this.appliesCount += 1;
      this.timingsSum += elapsedTimeMs;
      this.meanTiming = this.timingsSum / this.appliesCount;
      this.squaredSum += elapsedTimeMs * elapsedTimeMs;
      this.standardDeviation = Math.sqrt(
        this.squaredSum / this.appliesCount - Math.pow(this.meanTiming, 2),
      );
    }
  };
  __name(TimingStats, "TimingStats");
  var beautifyTimingNumber = /* @__PURE__ */ __name((timestamp) => {
    return Number(timestamp.toFixed(STATS_DECIMAL_DIGITS_COUNT));
  }, "beautifyTimingNumber");
  var beautifyTimings = /* @__PURE__ */ __name((rawTimings) => {
    return {
      appliesTimings: rawTimings.appliesTimings.map((t) =>
        beautifyTimingNumber(t),
      ),
      appliesCount: beautifyTimingNumber(rawTimings.appliesCount),
      timingsSum: beautifyTimingNumber(rawTimings.timingsSum),
      meanTiming: beautifyTimingNumber(rawTimings.meanTiming),
      standardDeviation: beautifyTimingNumber(rawTimings.standardDeviation),
    };
  }, "beautifyTimings");
  var printTimingInfo = /* @__PURE__ */ __name((context) => {
    if (context.areTimingsPrinted) {
      return;
    }
    context.areTimingsPrinted = true;
    const timingsLogData = {};
    context.parsedRules.forEach((ruleData) => {
      if (ruleData.timingStats) {
        const { selector, style, debug, matchedElements } = ruleData;
        if (!style && !debug) {
          throw new Error(
            `Rule should have style declaration for selector: '${selector}'`,
          );
        }
        const selectorData = {
          selectorParsed: selector,
          timings: beautifyTimings(ruleData.timingStats),
        };
        if (
          style &&
          style[REMOVE_PSEUDO_MARKER] === PSEUDO_PROPERTY_POSITIVE_VALUE
        ) {
          selectorData.removed = true;
        } else {
          selectorData.styleApplied = style || null;
          selectorData.matchedElements = matchedElements;
        }
        timingsLogData[selector] = selectorData;
      }
    });
    if (Object.keys(timingsLogData).length === 0) {
      return;
    }
    logger.info(
      "[ExtendedCss] Timings in milliseconds for %o:\n%o",
      window.location.href,
      timingsLogData,
    );
  }, "printTimingInfo");

  // src/extended-css/helpers/rules-applier.ts
  var findAffectedElement = /* @__PURE__ */ __name((affElements, domNode) => {
    return affElements.find((affEl) => affEl.node === domNode);
  }, "findAffectedElement");
  var applyRule = /* @__PURE__ */ __name((context, ruleData) => {
    const isDebuggingMode = !!ruleData.debug || context.debug;
    let startTime;
    if (isDebuggingMode) {
      startTime = performance.now();
    }
    const { ast } = ruleData;
    const nodes = [];
    try {
      nodes.push(...selectElementsByAst(ast));
    } catch (e) {
      if (context.debug) {
        logger.error(getErrorMessage(e));
      }
    }
    nodes.forEach((node) => {
      let affectedElement = findAffectedElement(context.affectedElements, node);
      if (affectedElement) {
        affectedElement.rules.push(ruleData);
        applyStyle(context, affectedElement);
      } else {
        const originalStyle = node.style.cssText;
        affectedElement = {
          node,
          rules: [ruleData],
          originalStyle,
          protectionObserver: null,
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
  }, "applyRule");
  var applyRules = /* @__PURE__ */ __name((context) => {
    const newSelectedElements = [];
    disconnectDocument(context);
    context.parsedRules.forEach((ruleData) => {
      const nodes = applyRule(context, ruleData);
      Array.prototype.push.apply(newSelectedElements, nodes);
      if (ruleData.debug) {
        ruleData.matchedElements = nodes;
      }
    });
    let affLength = context.affectedElements.length;
    while (affLength) {
      const affectedElement = context.affectedElements[affLength - 1];
      if (!affectedElement) {
        break;
      }
      if (!newSelectedElements.includes(affectedElement.node)) {
        revertStyle(affectedElement);
        context.affectedElements.splice(affLength - 1, 1);
      } else if (!affectedElement.removed) {
        if (!affectedElement.protectionObserver) {
          affectedElement.protectionObserver = protectStyleAttribute(
            affectedElement.node,
            affectedElement.rules,
          );
        }
      }
      affLength -= 1;
    }
    observeDocument(context);
    printTimingInfo(context);
  }, "applyRules");

  // src/extended-css/extended-css.ts
  var ExtendedCss = class {
    constructor(configuration) {
      if (!configuration) {
        throw new Error("ExtendedCss configuration should be provided.");
      }
      this.applyRulesCallbackListener =
        this.applyRulesCallbackListener.bind(this);
      this.context = {
        beforeStyleApplied: configuration.beforeStyleApplied,
        debug: false,
        affectedElements: [],
        isDomObserved: false,
        removalsStatistic: {},
        parsedRules: [],
        scheduler: new ThrottleWrapper(this.applyRulesCallbackListener),
      };
      if (!isBrowserSupported()) {
        logger.error("Browser is not supported by ExtendedCss");
        return;
      }
      if (!configuration.styleSheet && !configuration.cssRules) {
        throw new Error(
          "ExtendedCss configuration should have 'styleSheet' or 'cssRules' defined.",
        );
      }
      if (configuration.styleSheet) {
        try {
          this.context.parsedRules.push(
            ...parseStylesheet(configuration.styleSheet, extCssDocument),
          );
        } catch (e) {
          throw new Error(
            `Pass the rules as configuration.cssRules since configuration.styleSheet cannot be parsed because of: '${getErrorMessage(e)}'`,
          );
        }
      }
      if (configuration.cssRules) {
        this.context.parsedRules.push(
          ...parseRules(configuration.cssRules, extCssDocument),
        );
      }
      this.context.debug =
        configuration.debug ||
        this.context.parsedRules.some((ruleData) => {
          return ruleData.debug === DEBUG_PSEUDO_PROPERTY_GLOBAL_VALUE;
        });
      if (
        this.context.beforeStyleApplied &&
        typeof this.context.beforeStyleApplied !== "function"
      ) {
        throw new Error(
          `Invalid configuration. Type of 'beforeStyleApplied' should be a function, received: '${typeof this.context.beforeStyleApplied}'`,
        );
      }
    }
    applyRulesCallbackListener() {
      applyRules(this.context);
    }
    init() {
      nativeTextContent.setGetter();
    }
    apply() {
      applyRules(this.context);
      if (document.readyState !== "complete") {
        document.addEventListener(
          "DOMContentLoaded",
          this.applyRulesCallbackListener,
          false,
        );
      }
    }
    dispose() {
      disconnectDocument(this.context);
      this.context.affectedElements.forEach((el) => {
        revertStyle(el);
      });
      document.removeEventListener(
        "DOMContentLoaded",
        this.applyRulesCallbackListener,
        false,
      );
    }
    getAffectedElements() {
      return this.context.affectedElements;
    }
    static query(selector, noTiming = true) {
      if (typeof selector !== "string") {
        throw new Error("Selector should be defined as a string.");
      }
      const start = performance.now();
      try {
        return extCssDocument.querySelectorAll(selector);
      } finally {
        const end = performance.now();
        if (!noTiming) {
          logger.info(
            `[ExtendedCss] Elapsed: ${Math.round((end - start) * 1e3)} \u03BCs.`,
          );
        }
      }
    }
    static validate(inputSelector) {
      try {
        const { selector } = parseRemoveSelector(inputSelector);
        ExtendedCss.query(selector);
        return { ok: true, error: null };
      } catch (e) {
        const error = `Error: Invalid selector: '${inputSelector}' -- ${getErrorMessage(e)}`;
        return { ok: false, error };
      }
    }
  };
  __name(ExtendedCss, "ExtendedCss");
  return ExtendedCss;
})();
