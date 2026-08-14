(function(f){if(typeof exports==="object"&&typeof module!=="undefined"){module.exports=f()}else if(typeof define==="function"&&define.amd){define([],f)}else{var g;if(typeof window!=="undefined"){g=window}else if(typeof global!=="undefined"){g=global}else if(typeof self!=="undefined"){g=self}else{g=this}g.OfflineStylus = f()}})(function(){var define,module,exports;return (function(){function r(e,n,t){function o(i,f){if(!n[i]){if(!e[i]){var c="function"==typeof require&&require;if(!f&&c)return c(i,!0);if(u)return u(i,!0);var a=new Error("Cannot find module '"+i+"'");throw a.code="MODULE_NOT_FOUND",a}var p=n[i]={exports:{}};e[i][0].call(p.exports,function(r){var n=e[i][1][r];return o(n||r)},p,p.exports,r,e,n,t)}return n[i].exports}for(var u="function"==typeof require&&require,i=0;i<t.length;i++)o(t[i]);return o}return r})()({1:[function(require,module,exports){
(function (global){(function (){
'use strict';

var possibleNames = require('possible-typed-array-names');

var g = typeof globalThis === 'undefined' ? global : globalThis;

/** @type {import('.')} */
module.exports = function availableTypedArrays() {
	var /** @type {ReturnType<typeof availableTypedArrays>} */ out = [];
	for (var i = 0; i < possibleNames.length; i++) {
		if (typeof g[possibleNames[i]] === 'function') {
			// @ts-expect-error
			out[out.length] = possibleNames[i];
		}
	}
	return out;
};

}).call(this)}).call(this,typeof global !== "undefined" ? global : typeof self !== "undefined" ? self : typeof window !== "undefined" ? window : {})
},{"possible-typed-array-names":53}],2:[function(require,module,exports){

},{}],3:[function(require,module,exports){
'use strict';

var bind = require('function-bind');

var $apply = require('./functionApply');
var $call = require('./functionCall');
var $reflectApply = require('./reflectApply');

/** @type {import('./actualApply')} */
module.exports = $reflectApply || bind.call($call, $apply);

},{"./functionApply":5,"./functionCall":6,"./reflectApply":8,"function-bind":25}],4:[function(require,module,exports){
'use strict';

var bind = require('function-bind');
var $apply = require('./functionApply');
var actualApply = require('./actualApply');

/** @type {import('./applyBind')} */
module.exports = function applyBind() {
	return actualApply(bind, $apply, arguments);
};

},{"./actualApply":3,"./functionApply":5,"function-bind":25}],5:[function(require,module,exports){
'use strict';

/** @type {import('./functionApply')} */
module.exports = Function.prototype.apply;

},{}],6:[function(require,module,exports){
'use strict';

/** @type {import('./functionCall')} */
module.exports = Function.prototype.call;

},{}],7:[function(require,module,exports){
'use strict';

var bind = require('function-bind');
var $TypeError = require('es-errors/type');

var $call = require('./functionCall');
var $actualApply = require('./actualApply');

/** @type {(args: [Function, thisArg?: unknown, ...args: unknown[]]) => Function} TODO FIXME, find a way to use import('.') */
module.exports = function callBindBasic(args) {
	if (args.length < 1 || typeof args[0] !== 'function') {
		throw new $TypeError('a function is required');
	}
	return $actualApply(bind, $call, args);
};

},{"./actualApply":3,"./functionCall":6,"es-errors/type":19,"function-bind":25}],8:[function(require,module,exports){
'use strict';

/** @type {import('./reflectApply')} */
module.exports = typeof Reflect !== 'undefined' && Reflect && Reflect.apply;

},{}],9:[function(require,module,exports){
'use strict';

var setFunctionLength = require('set-function-length');

var $defineProperty = require('es-define-property');

var callBindBasic = require('call-bind-apply-helpers');
var applyBind = require('call-bind-apply-helpers/applyBind');

module.exports = function callBind(originalFunction) {
	var func = callBindBasic(arguments);
	var adjustedLength = 1 + originalFunction.length - (arguments.length - 1);
	return setFunctionLength(
		func,
		adjustedLength > 0 ? adjustedLength : 0,
		true
	);
};

if ($defineProperty) {
	$defineProperty(module.exports, 'apply', { value: applyBind });
} else {
	module.exports.apply = applyBind;
}

},{"call-bind-apply-helpers":7,"call-bind-apply-helpers/applyBind":4,"es-define-property":13,"set-function-length":55}],10:[function(require,module,exports){
'use strict';

var GetIntrinsic = require('get-intrinsic');

var callBindBasic = require('call-bind-apply-helpers');

/** @type {(thisArg: string, searchString: string, position?: number) => number} */
var $indexOf = callBindBasic([GetIntrinsic('%String.prototype.indexOf%')]);

/** @type {import('.')} */
module.exports = function callBoundIntrinsic(name, allowMissing) {
	/* eslint no-extra-parens: 0 */

	var intrinsic = /** @type {(this: unknown, ...args: unknown[]) => unknown} */ (GetIntrinsic(name, !!allowMissing));
	if (typeof intrinsic === 'function' && $indexOf(name, '.prototype.') > -1) {
		return callBindBasic(/** @type {const} */ ([intrinsic]));
	}
	return intrinsic;
};

},{"call-bind-apply-helpers":7,"get-intrinsic":27}],11:[function(require,module,exports){
'use strict';

var $defineProperty = require('es-define-property');

var $SyntaxError = require('es-errors/syntax');
var $TypeError = require('es-errors/type');

var gopd = require('gopd');

/** @type {import('.')} */
module.exports = function defineDataProperty(
	obj,
	property,
	value
) {
	if (!obj || (typeof obj !== 'object' && typeof obj !== 'function')) {
		throw new $TypeError('`obj` must be an object or a function`');
	}
	if (typeof property !== 'string' && typeof property !== 'symbol') {
		throw new $TypeError('`property` must be a string or a symbol`');
	}
	if (arguments.length > 3 && typeof arguments[3] !== 'boolean' && arguments[3] !== null) {
		throw new $TypeError('`nonEnumerable`, if provided, must be a boolean or null');
	}
	if (arguments.length > 4 && typeof arguments[4] !== 'boolean' && arguments[4] !== null) {
		throw new $TypeError('`nonWritable`, if provided, must be a boolean or null');
	}
	if (arguments.length > 5 && typeof arguments[5] !== 'boolean' && arguments[5] !== null) {
		throw new $TypeError('`nonConfigurable`, if provided, must be a boolean or null');
	}
	if (arguments.length > 6 && typeof arguments[6] !== 'boolean') {
		throw new $TypeError('`loose`, if provided, must be a boolean');
	}

	var nonEnumerable = arguments.length > 3 ? arguments[3] : null;
	var nonWritable = arguments.length > 4 ? arguments[4] : null;
	var nonConfigurable = arguments.length > 5 ? arguments[5] : null;
	var loose = arguments.length > 6 ? arguments[6] : false;

	/* @type {false | TypedPropertyDescriptor<unknown>} */
	var desc = !!gopd && gopd(obj, property);

	if ($defineProperty) {
		$defineProperty(obj, property, {
			configurable: nonConfigurable === null && desc ? desc.configurable : !nonConfigurable,
			enumerable: nonEnumerable === null && desc ? desc.enumerable : !nonEnumerable,
			value: value,
			writable: nonWritable === null && desc ? desc.writable : !nonWritable
		});
	} else if (loose || (!nonEnumerable && !nonWritable && !nonConfigurable)) {
		// must fall back to [[Set]], and was not explicitly asked to make non-enumerable, non-writable, or non-configurable
		obj[property] = value; // eslint-disable-line no-param-reassign
	} else {
		throw new $SyntaxError('This environment does not support defining a property as non-configurable, non-writable, or non-enumerable.');
	}
};

},{"es-define-property":13,"es-errors/syntax":18,"es-errors/type":19,"gopd":32}],12:[function(require,module,exports){
'use strict';

var callBind = require('call-bind-apply-helpers');
var gOPD = require('gopd');

var hasProtoAccessor;
try {
	// eslint-disable-next-line no-extra-parens, no-proto
	hasProtoAccessor = /** @type {{ __proto__?: typeof Array.prototype }} */ ([]).__proto__ === Array.prototype;
} catch (e) {
	if (!e || typeof e !== 'object' || !('code' in e) || e.code !== 'ERR_PROTO_ACCESS') {
		throw e;
	}
}

// eslint-disable-next-line no-extra-parens
var desc = !!hasProtoAccessor && gOPD && gOPD(Object.prototype, /** @type {keyof typeof Object.prototype} */ ('__proto__'));

var $Object = Object;
var $getPrototypeOf = $Object.getPrototypeOf;

/** @type {import('./get')} */
module.exports = desc && typeof desc.get === 'function'
	? callBind([desc.get])
	: typeof $getPrototypeOf === 'function'
		? /** @type {import('./get')} */ function getDunder(value) {
			// eslint-disable-next-line eqeqeq
			return $getPrototypeOf(value == null ? value : $Object(value));
		}
		: false;

},{"call-bind-apply-helpers":7,"gopd":32}],13:[function(require,module,exports){
'use strict';

/** @type {import('.')} */
var $defineProperty = Object.defineProperty || false;
if ($defineProperty) {
	try {
		$defineProperty({}, 'a', { value: 1 });
	} catch (e) {
		// IE 8 has a broken defineProperty
		$defineProperty = false;
	}
}

module.exports = $defineProperty;

},{}],14:[function(require,module,exports){
'use strict';

/** @type {import('./eval')} */
module.exports = EvalError;

},{}],15:[function(require,module,exports){
'use strict';

/** @type {import('.')} */
module.exports = Error;

},{}],16:[function(require,module,exports){
'use strict';

/** @type {import('./range')} */
module.exports = RangeError;

},{}],17:[function(require,module,exports){
'use strict';

/** @type {import('./ref')} */
module.exports = ReferenceError;

},{}],18:[function(require,module,exports){
'use strict';

/** @type {import('./syntax')} */
module.exports = SyntaxError;

},{}],19:[function(require,module,exports){
'use strict';

/** @type {import('./type')} */
module.exports = TypeError;

},{}],20:[function(require,module,exports){
'use strict';

/** @type {import('./uri')} */
module.exports = URIError;

},{}],21:[function(require,module,exports){
'use strict';

/** @type {import('.')} */
module.exports = Object;

},{}],22:[function(require,module,exports){
// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

'use strict';

var R = typeof Reflect === 'object' ? Reflect : null
var ReflectApply = R && typeof R.apply === 'function'
  ? R.apply
  : function ReflectApply(target, receiver, args) {
    return Function.prototype.apply.call(target, receiver, args);
  }

var ReflectOwnKeys
if (R && typeof R.ownKeys === 'function') {
  ReflectOwnKeys = R.ownKeys
} else if (Object.getOwnPropertySymbols) {
  ReflectOwnKeys = function ReflectOwnKeys(target) {
    return Object.getOwnPropertyNames(target)
      .concat(Object.getOwnPropertySymbols(target));
  };
} else {
  ReflectOwnKeys = function ReflectOwnKeys(target) {
    return Object.getOwnPropertyNames(target);
  };
}

function ProcessEmitWarning(warning) {
  if (console && console.warn) console.warn(warning);
}

var NumberIsNaN = Number.isNaN || function NumberIsNaN(value) {
  return value !== value;
}

function EventEmitter() {
  EventEmitter.init.call(this);
}
module.exports = EventEmitter;
module.exports.once = once;

// Backwards-compat with node 0.10.x
EventEmitter.EventEmitter = EventEmitter;

EventEmitter.prototype._events = undefined;
EventEmitter.prototype._eventsCount = 0;
EventEmitter.prototype._maxListeners = undefined;

// By default EventEmitters will print a warning if more than 10 listeners are
// added to it. This is a useful default which helps finding memory leaks.
var defaultMaxListeners = 10;

function checkListener(listener) {
  if (typeof listener !== 'function') {
    throw new TypeError('The "listener" argument must be of type Function. Received type ' + typeof listener);
  }
}

Object.defineProperty(EventEmitter, 'defaultMaxListeners', {
  enumerable: true,
  get: function() {
    return defaultMaxListeners;
  },
  set: function(arg) {
    if (typeof arg !== 'number' || arg < 0 || NumberIsNaN(arg)) {
      throw new RangeError('The value of "defaultMaxListeners" is out of range. It must be a non-negative number. Received ' + arg + '.');
    }
    defaultMaxListeners = arg;
  }
});

EventEmitter.init = function() {

  if (this._events === undefined ||
      this._events === Object.getPrototypeOf(this)._events) {
    this._events = Object.create(null);
    this._eventsCount = 0;
  }

  this._maxListeners = this._maxListeners || undefined;
};

// Obviously not all Emitters should be limited to 10. This function allows
// that to be increased. Set to zero for unlimited.
EventEmitter.prototype.setMaxListeners = function setMaxListeners(n) {
  if (typeof n !== 'number' || n < 0 || NumberIsNaN(n)) {
    throw new RangeError('The value of "n" is out of range. It must be a non-negative number. Received ' + n + '.');
  }
  this._maxListeners = n;
  return this;
};

function _getMaxListeners(that) {
  if (that._maxListeners === undefined)
    return EventEmitter.defaultMaxListeners;
  return that._maxListeners;
}

EventEmitter.prototype.getMaxListeners = function getMaxListeners() {
  return _getMaxListeners(this);
};

EventEmitter.prototype.emit = function emit(type) {
  var args = [];
  for (var i = 1; i < arguments.length; i++) args.push(arguments[i]);
  var doError = (type === 'error');

  var events = this._events;
  if (events !== undefined)
    doError = (doError && events.error === undefined);
  else if (!doError)
    return false;

  // If there is no 'error' event listener then throw.
  if (doError) {
    var er;
    if (args.length > 0)
      er = args[0];
    if (er instanceof Error) {
      // Note: The comments on the `throw` lines are intentional, they show
      // up in Node's output if this results in an unhandled exception.
      throw er; // Unhandled 'error' event
    }
    // At least give some kind of context to the user
    var err = new Error('Unhandled error.' + (er ? ' (' + er.message + ')' : ''));
    err.context = er;
    throw err; // Unhandled 'error' event
  }

  var handler = events[type];

  if (handler === undefined)
    return false;

  if (typeof handler === 'function') {
    ReflectApply(handler, this, args);
  } else {
    var len = handler.length;
    var listeners = arrayClone(handler, len);
    for (var i = 0; i < len; ++i)
      ReflectApply(listeners[i], this, args);
  }

  return true;
};

function _addListener(target, type, listener, prepend) {
  var m;
  var events;
  var existing;

  checkListener(listener);

  events = target._events;
  if (events === undefined) {
    events = target._events = Object.create(null);
    target._eventsCount = 0;
  } else {
    // To avoid recursion in the case that type === "newListener"! Before
    // adding it to the listeners, first emit "newListener".
    if (events.newListener !== undefined) {
      target.emit('newListener', type,
                  listener.listener ? listener.listener : listener);

      // Re-assign `events` because a newListener handler could have caused the
      // this._events to be assigned to a new object
      events = target._events;
    }
    existing = events[type];
  }

  if (existing === undefined) {
    // Optimize the case of one listener. Don't need the extra array object.
    existing = events[type] = listener;
    ++target._eventsCount;
  } else {
    if (typeof existing === 'function') {
      // Adding the second element, need to change to array.
      existing = events[type] =
        prepend ? [listener, existing] : [existing, listener];
      // If we've already got an array, just append.
    } else if (prepend) {
      existing.unshift(listener);
    } else {
      existing.push(listener);
    }

    // Check for listener leak
    m = _getMaxListeners(target);
    if (m > 0 && existing.length > m && !existing.warned) {
      existing.warned = true;
      // No error code for this since it is a Warning
      // eslint-disable-next-line no-restricted-syntax
      var w = new Error('Possible EventEmitter memory leak detected. ' +
                          existing.length + ' ' + String(type) + ' listeners ' +
                          'added. Use emitter.setMaxListeners() to ' +
                          'increase limit');
      w.name = 'MaxListenersExceededWarning';
      w.emitter = target;
      w.type = type;
      w.count = existing.length;
      ProcessEmitWarning(w);
    }
  }

  return target;
}

EventEmitter.prototype.addListener = function addListener(type, listener) {
  return _addListener(this, type, listener, false);
};

EventEmitter.prototype.on = EventEmitter.prototype.addListener;

EventEmitter.prototype.prependListener =
    function prependListener(type, listener) {
      return _addListener(this, type, listener, true);
    };

function onceWrapper() {
  if (!this.fired) {
    this.target.removeListener(this.type, this.wrapFn);
    this.fired = true;
    if (arguments.length === 0)
      return this.listener.call(this.target);
    return this.listener.apply(this.target, arguments);
  }
}

function _onceWrap(target, type, listener) {
  var state = { fired: false, wrapFn: undefined, target: target, type: type, listener: listener };
  var wrapped = onceWrapper.bind(state);
  wrapped.listener = listener;
  state.wrapFn = wrapped;
  return wrapped;
}

EventEmitter.prototype.once = function once(type, listener) {
  checkListener(listener);
  this.on(type, _onceWrap(this, type, listener));
  return this;
};

EventEmitter.prototype.prependOnceListener =
    function prependOnceListener(type, listener) {
      checkListener(listener);
      this.prependListener(type, _onceWrap(this, type, listener));
      return this;
    };

// Emits a 'removeListener' event if and only if the listener was removed.
EventEmitter.prototype.removeListener =
    function removeListener(type, listener) {
      var list, events, position, i, originalListener;

      checkListener(listener);

      events = this._events;
      if (events === undefined)
        return this;

      list = events[type];
      if (list === undefined)
        return this;

      if (list === listener || list.listener === listener) {
        if (--this._eventsCount === 0)
          this._events = Object.create(null);
        else {
          delete events[type];
          if (events.removeListener)
            this.emit('removeListener', type, list.listener || listener);
        }
      } else if (typeof list !== 'function') {
        position = -1;

        for (i = list.length - 1; i >= 0; i--) {
          if (list[i] === listener || list[i].listener === listener) {
            originalListener = list[i].listener;
            position = i;
            break;
          }
        }

        if (position < 0)
          return this;

        if (position === 0)
          list.shift();
        else {
          spliceOne(list, position);
        }

        if (list.length === 1)
          events[type] = list[0];

        if (events.removeListener !== undefined)
          this.emit('removeListener', type, originalListener || listener);
      }

      return this;
    };

EventEmitter.prototype.off = EventEmitter.prototype.removeListener;

EventEmitter.prototype.removeAllListeners =
    function removeAllListeners(type) {
      var listeners, events, i;

      events = this._events;
      if (events === undefined)
        return this;

      // not listening for removeListener, no need to emit
      if (events.removeListener === undefined) {
        if (arguments.length === 0) {
          this._events = Object.create(null);
          this._eventsCount = 0;
        } else if (events[type] !== undefined) {
          if (--this._eventsCount === 0)
            this._events = Object.create(null);
          else
            delete events[type];
        }
        return this;
      }

      // emit removeListener for all listeners on all events
      if (arguments.length === 0) {
        var keys = Object.keys(events);
        var key;
        for (i = 0; i < keys.length; ++i) {
          key = keys[i];
          if (key === 'removeListener') continue;
          this.removeAllListeners(key);
        }
        this.removeAllListeners('removeListener');
        this._events = Object.create(null);
        this._eventsCount = 0;
        return this;
      }

      listeners = events[type];

      if (typeof listeners === 'function') {
        this.removeListener(type, listeners);
      } else if (listeners !== undefined) {
        // LIFO order
        for (i = listeners.length - 1; i >= 0; i--) {
          this.removeListener(type, listeners[i]);
        }
      }

      return this;
    };

function _listeners(target, type, unwrap) {
  var events = target._events;

  if (events === undefined)
    return [];

  var evlistener = events[type];
  if (evlistener === undefined)
    return [];

  if (typeof evlistener === 'function')
    return unwrap ? [evlistener.listener || evlistener] : [evlistener];

  return unwrap ?
    unwrapListeners(evlistener) : arrayClone(evlistener, evlistener.length);
}

EventEmitter.prototype.listeners = function listeners(type) {
  return _listeners(this, type, true);
};

EventEmitter.prototype.rawListeners = function rawListeners(type) {
  return _listeners(this, type, false);
};

EventEmitter.listenerCount = function(emitter, type) {
  if (typeof emitter.listenerCount === 'function') {
    return emitter.listenerCount(type);
  } else {
    return listenerCount.call(emitter, type);
  }
};

EventEmitter.prototype.listenerCount = listenerCount;
function listenerCount(type) {
  var events = this._events;

  if (events !== undefined) {
    var evlistener = events[type];

    if (typeof evlistener === 'function') {
      return 1;
    } else if (evlistener !== undefined) {
      return evlistener.length;
    }
  }

  return 0;
}

EventEmitter.prototype.eventNames = function eventNames() {
  return this._eventsCount > 0 ? ReflectOwnKeys(this._events) : [];
};

function arrayClone(arr, n) {
  var copy = new Array(n);
  for (var i = 0; i < n; ++i)
    copy[i] = arr[i];
  return copy;
}

function spliceOne(list, index) {
  for (; index + 1 < list.length; index++)
    list[index] = list[index + 1];
  list.pop();
}

function unwrapListeners(arr) {
  var ret = new Array(arr.length);
  for (var i = 0; i < ret.length; ++i) {
    ret[i] = arr[i].listener || arr[i];
  }
  return ret;
}

function once(emitter, name) {
  return new Promise(function (resolve, reject) {
    function errorListener(err) {
      emitter.removeListener(name, resolver);
      reject(err);
    }

    function resolver() {
      if (typeof emitter.removeListener === 'function') {
        emitter.removeListener('error', errorListener);
      }
      resolve([].slice.call(arguments));
    };

    eventTargetAgnosticAddListener(emitter, name, resolver, { once: true });
    if (name !== 'error') {
      addErrorHandlerIfEventEmitter(emitter, errorListener, { once: true });
    }
  });
}

function addErrorHandlerIfEventEmitter(emitter, handler, flags) {
  if (typeof emitter.on === 'function') {
    eventTargetAgnosticAddListener(emitter, 'error', handler, flags);
  }
}

function eventTargetAgnosticAddListener(emitter, name, listener, flags) {
  if (typeof emitter.on === 'function') {
    if (flags.once) {
      emitter.once(name, listener);
    } else {
      emitter.on(name, listener);
    }
  } else if (typeof emitter.addEventListener === 'function') {
    // EventTarget does not have `error` event semantics like Node
    // EventEmitters, we do not listen for `error` events here.
    emitter.addEventListener(name, function wrapListener(arg) {
      // IE does not have builtin `{ once: true }` support so we
      // have to do it manually.
      if (flags.once) {
        emitter.removeEventListener(name, wrapListener);
      }
      listener(arg);
    });
  } else {
    throw new TypeError('The "emitter" argument must be of type EventEmitter. Received type ' + typeof emitter);
  }
}

},{}],23:[function(require,module,exports){
'use strict';

var isCallable = require('is-callable');

var toStr = Object.prototype.toString;
var hasOwnProperty = Object.prototype.hasOwnProperty;

/** @type {<This, A extends readonly unknown[]>(arr: A, iterator: (this: This | void, value: A[number], index: number, arr: A) => void, receiver: This | undefined) => void} */
var forEachArray = function forEachArray(array, iterator, receiver) {
    for (var i = 0, len = array.length; i < len; i++) {
        if (hasOwnProperty.call(array, i)) {
            if (receiver == null) {
                iterator(array[i], i, array);
            } else {
                iterator.call(receiver, array[i], i, array);
            }
        }
    }
};

/** @type {<This, S extends string>(string: S, iterator: (this: This | void, value: S[number], index: number, string: S) => void, receiver: This | undefined) => void} */
var forEachString = function forEachString(string, iterator, receiver) {
    for (var i = 0, len = string.length; i < len; i++) {
        // no such thing as a sparse string.
        if (receiver == null) {
            iterator(string.charAt(i), i, string);
        } else {
            iterator.call(receiver, string.charAt(i), i, string);
        }
    }
};

/** @type {<This, O>(obj: O, iterator: (this: This | void, value: O[keyof O], index: keyof O, obj: O) => void, receiver: This | undefined) => void} */
var forEachObject = function forEachObject(object, iterator, receiver) {
    for (var k in object) {
        if (hasOwnProperty.call(object, k)) {
            if (receiver == null) {
                iterator(object[k], k, object);
            } else {
                iterator.call(receiver, object[k], k, object);
            }
        }
    }
};

/** @type {(x: unknown) => x is readonly unknown[]} */
function isArray(x) {
    return toStr.call(x) === '[object Array]';
}

/** @type {import('.')._internal} */
module.exports = function forEach(list, iterator, thisArg) {
    if (!isCallable(iterator)) {
        throw new TypeError('iterator must be a function');
    }

    var receiver;
    if (arguments.length >= 3) {
        receiver = thisArg;
    }

    if (isArray(list)) {
        forEachArray(list, iterator, receiver);
    } else if (typeof list === 'string') {
        forEachString(list, iterator, receiver);
    } else {
        forEachObject(list, iterator, receiver);
    }
};

},{"is-callable":40}],24:[function(require,module,exports){
'use strict';

/* eslint no-invalid-this: 1 */

var ERROR_MESSAGE = 'Function.prototype.bind called on incompatible ';
var toStr = Object.prototype.toString;
var max = Math.max;
var funcType = '[object Function]';

var concatty = function concatty(a, b) {
    var arr = [];

    for (var i = 0; i < a.length; i += 1) {
        arr[i] = a[i];
    }
    for (var j = 0; j < b.length; j += 1) {
        arr[j + a.length] = b[j];
    }

    return arr;
};

var slicy = function slicy(arrLike, offset) {
    var arr = [];
    for (var i = offset || 0, j = 0; i < arrLike.length; i += 1, j += 1) {
        arr[j] = arrLike[i];
    }
    return arr;
};

var joiny = function (arr, joiner) {
    var str = '';
    for (var i = 0; i < arr.length; i += 1) {
        str += arr[i];
        if (i + 1 < arr.length) {
            str += joiner;
        }
    }
    return str;
};

module.exports = function bind(that) {
    var target = this;
    if (typeof target !== 'function' || toStr.apply(target) !== funcType) {
        throw new TypeError(ERROR_MESSAGE + target);
    }
    var args = slicy(arguments, 1);

    var bound;
    var binder = function () {
        if (this instanceof bound) {
            var result = target.apply(
                this,
                concatty(args, arguments)
            );
            if (Object(result) === result) {
                return result;
            }
            return this;
        }
        return target.apply(
            that,
            concatty(args, arguments)
        );

    };

    var boundLength = max(0, target.length - args.length);
    var boundArgs = [];
    for (var i = 0; i < boundLength; i++) {
        boundArgs[i] = '$' + i;
    }

    bound = Function('binder', 'return function (' + joiny(boundArgs, ',') + '){ return binder.apply(this,arguments); }')(binder);

    if (target.prototype) {
        var Empty = function Empty() {};
        Empty.prototype = target.prototype;
        bound.prototype = new Empty();
        Empty.prototype = null;
    }

    return bound;
};

},{}],25:[function(require,module,exports){
'use strict';

var implementation = require('./implementation');

module.exports = Function.prototype.bind || implementation;

},{"./implementation":24}],26:[function(require,module,exports){
'use strict';

/** @type {GeneratorFunctionConstructor | false} */
var cached;

/** @type {import('./index.js')} */
module.exports = function getGeneratorFunction() {
	if (typeof cached === 'undefined') {
		try {
			// eslint-disable-next-line no-new-func
			cached = Function('return function* () {}')().constructor;
		} catch (e) {
			cached = false;
		}
	}
	return cached;
};


},{}],27:[function(require,module,exports){
'use strict';

var undefined;

var $Object = require('es-object-atoms');

var $Error = require('es-errors');
var $EvalError = require('es-errors/eval');
var $RangeError = require('es-errors/range');
var $ReferenceError = require('es-errors/ref');
var $SyntaxError = require('es-errors/syntax');
var $TypeError = require('es-errors/type');
var $URIError = require('es-errors/uri');

var abs = require('math-intrinsics/abs');
var floor = require('math-intrinsics/floor');
var max = require('math-intrinsics/max');
var min = require('math-intrinsics/min');
var pow = require('math-intrinsics/pow');
var round = require('math-intrinsics/round');
var sign = require('math-intrinsics/sign');

var $Function = Function;

// eslint-disable-next-line consistent-return
var getEvalledConstructor = function (expressionSyntax) {
	try {
		return $Function('"use strict"; return (' + expressionSyntax + ').constructor;')();
	} catch (e) {}
};

var $gOPD = require('gopd');
var $defineProperty = require('es-define-property');

var throwTypeError = function () {
	throw new $TypeError();
};
var ThrowTypeError = $gOPD
	? (function () {
		try {
			// eslint-disable-next-line no-unused-expressions, no-caller, no-restricted-properties
			arguments.callee; // IE 8 does not throw here
			return throwTypeError;
		} catch (calleeThrows) {
			try {
				// IE 8 throws on Object.getOwnPropertyDescriptor(arguments, '')
				return $gOPD(arguments, 'callee').get;
			} catch (gOPDthrows) {
				return throwTypeError;
			}
		}
	}())
	: throwTypeError;

var hasSymbols = require('has-symbols')();

var getProto = require('get-proto');
var $ObjectGPO = require('get-proto/Object.getPrototypeOf');
var $ReflectGPO = require('get-proto/Reflect.getPrototypeOf');

var $apply = require('call-bind-apply-helpers/functionApply');
var $call = require('call-bind-apply-helpers/functionCall');

var needsEval = {};

var TypedArray = typeof Uint8Array === 'undefined' || !getProto ? undefined : getProto(Uint8Array);

var INTRINSICS = {
	__proto__: null,
	'%AggregateError%': typeof AggregateError === 'undefined' ? undefined : AggregateError,
	'%Array%': Array,
	'%ArrayBuffer%': typeof ArrayBuffer === 'undefined' ? undefined : ArrayBuffer,
	'%ArrayIteratorPrototype%': hasSymbols && getProto ? getProto([][Symbol.iterator]()) : undefined,
	'%AsyncFromSyncIteratorPrototype%': undefined,
	'%AsyncFunction%': needsEval,
	'%AsyncGenerator%': needsEval,
	'%AsyncGeneratorFunction%': needsEval,
	'%AsyncIteratorPrototype%': needsEval,
	'%Atomics%': typeof Atomics === 'undefined' ? undefined : Atomics,
	'%BigInt%': typeof BigInt === 'undefined' ? undefined : BigInt,
	'%BigInt64Array%': typeof BigInt64Array === 'undefined' ? undefined : BigInt64Array,
	'%BigUint64Array%': typeof BigUint64Array === 'undefined' ? undefined : BigUint64Array,
	'%Boolean%': Boolean,
	'%DataView%': typeof DataView === 'undefined' ? undefined : DataView,
	'%Date%': Date,
	'%decodeURI%': decodeURI,
	'%decodeURIComponent%': decodeURIComponent,
	'%encodeURI%': encodeURI,
	'%encodeURIComponent%': encodeURIComponent,
	'%Error%': $Error,
	'%eval%': eval, // eslint-disable-line no-eval
	'%EvalError%': $EvalError,
	'%Float16Array%': typeof Float16Array === 'undefined' ? undefined : Float16Array,
	'%Float32Array%': typeof Float32Array === 'undefined' ? undefined : Float32Array,
	'%Float64Array%': typeof Float64Array === 'undefined' ? undefined : Float64Array,
	'%FinalizationRegistry%': typeof FinalizationRegistry === 'undefined' ? undefined : FinalizationRegistry,
	'%Function%': $Function,
	'%GeneratorFunction%': needsEval,
	'%Int8Array%': typeof Int8Array === 'undefined' ? undefined : Int8Array,
	'%Int16Array%': typeof Int16Array === 'undefined' ? undefined : Int16Array,
	'%Int32Array%': typeof Int32Array === 'undefined' ? undefined : Int32Array,
	'%isFinite%': isFinite,
	'%isNaN%': isNaN,
	'%IteratorPrototype%': hasSymbols && getProto ? getProto(getProto([][Symbol.iterator]())) : undefined,
	'%JSON%': typeof JSON === 'object' ? JSON : undefined,
	'%Map%': typeof Map === 'undefined' ? undefined : Map,
	'%MapIteratorPrototype%': typeof Map === 'undefined' || !hasSymbols || !getProto ? undefined : getProto(new Map()[Symbol.iterator]()),
	'%Math%': Math,
	'%Number%': Number,
	'%Object%': $Object,
	'%Object.getOwnPropertyDescriptor%': $gOPD,
	'%parseFloat%': parseFloat,
	'%parseInt%': parseInt,
	'%Promise%': typeof Promise === 'undefined' ? undefined : Promise,
	'%Proxy%': typeof Proxy === 'undefined' ? undefined : Proxy,
	'%RangeError%': $RangeError,
	'%ReferenceError%': $ReferenceError,
	'%Reflect%': typeof Reflect === 'undefined' ? undefined : Reflect,
	'%RegExp%': RegExp,
	'%Set%': typeof Set === 'undefined' ? undefined : Set,
	'%SetIteratorPrototype%': typeof Set === 'undefined' || !hasSymbols || !getProto ? undefined : getProto(new Set()[Symbol.iterator]()),
	'%SharedArrayBuffer%': typeof SharedArrayBuffer === 'undefined' ? undefined : SharedArrayBuffer,
	'%String%': String,
	'%StringIteratorPrototype%': hasSymbols && getProto ? getProto(''[Symbol.iterator]()) : undefined,
	'%Symbol%': hasSymbols ? Symbol : undefined,
	'%SyntaxError%': $SyntaxError,
	'%ThrowTypeError%': ThrowTypeError,
	'%TypedArray%': TypedArray,
	'%TypeError%': $TypeError,
	'%Uint8Array%': typeof Uint8Array === 'undefined' ? undefined : Uint8Array,
	'%Uint8ClampedArray%': typeof Uint8ClampedArray === 'undefined' ? undefined : Uint8ClampedArray,
	'%Uint16Array%': typeof Uint16Array === 'undefined' ? undefined : Uint16Array,
	'%Uint32Array%': typeof Uint32Array === 'undefined' ? undefined : Uint32Array,
	'%URIError%': $URIError,
	'%WeakMap%': typeof WeakMap === 'undefined' ? undefined : WeakMap,
	'%WeakRef%': typeof WeakRef === 'undefined' ? undefined : WeakRef,
	'%WeakSet%': typeof WeakSet === 'undefined' ? undefined : WeakSet,

	'%Function.prototype.call%': $call,
	'%Function.prototype.apply%': $apply,
	'%Object.defineProperty%': $defineProperty,
	'%Object.getPrototypeOf%': $ObjectGPO,
	'%Math.abs%': abs,
	'%Math.floor%': floor,
	'%Math.max%': max,
	'%Math.min%': min,
	'%Math.pow%': pow,
	'%Math.round%': round,
	'%Math.sign%': sign,
	'%Reflect.getPrototypeOf%': $ReflectGPO
};

if (getProto) {
	try {
		null.error; // eslint-disable-line no-unused-expressions
	} catch (e) {
		// https://github.com/tc39/proposal-shadowrealm/pull/384#issuecomment-1364264229
		var errorProto = getProto(getProto(e));
		INTRINSICS['%Error.prototype%'] = errorProto;
	}
}

var doEval = function doEval(name) {
	var value;
	if (name === '%AsyncFunction%') {
		value = getEvalledConstructor('async function () {}');
	} else if (name === '%GeneratorFunction%') {
		value = getEvalledConstructor('function* () {}');
	} else if (name === '%AsyncGeneratorFunction%') {
		value = getEvalledConstructor('async function* () {}');
	} else if (name === '%AsyncGenerator%') {
		var fn = doEval('%AsyncGeneratorFunction%');
		if (fn) {
			value = fn.prototype;
		}
	} else if (name === '%AsyncIteratorPrototype%') {
		var gen = doEval('%AsyncGenerator%');
		if (gen && getProto) {
			value = getProto(gen.prototype);
		}
	}

	INTRINSICS[name] = value;

	return value;
};

var LEGACY_ALIASES = {
	__proto__: null,
	'%ArrayBufferPrototype%': ['ArrayBuffer', 'prototype'],
	'%ArrayPrototype%': ['Array', 'prototype'],
	'%ArrayProto_entries%': ['Array', 'prototype', 'entries'],
	'%ArrayProto_forEach%': ['Array', 'prototype', 'forEach'],
	'%ArrayProto_keys%': ['Array', 'prototype', 'keys'],
	'%ArrayProto_values%': ['Array', 'prototype', 'values'],
	'%AsyncFunctionPrototype%': ['AsyncFunction', 'prototype'],
	'%AsyncGenerator%': ['AsyncGeneratorFunction', 'prototype'],
	'%AsyncGeneratorPrototype%': ['AsyncGeneratorFunction', 'prototype', 'prototype'],
	'%BooleanPrototype%': ['Boolean', 'prototype'],
	'%DataViewPrototype%': ['DataView', 'prototype'],
	'%DatePrototype%': ['Date', 'prototype'],
	'%ErrorPrototype%': ['Error', 'prototype'],
	'%EvalErrorPrototype%': ['EvalError', 'prototype'],
	'%Float32ArrayPrototype%': ['Float32Array', 'prototype'],
	'%Float64ArrayPrototype%': ['Float64Array', 'prototype'],
	'%FunctionPrototype%': ['Function', 'prototype'],
	'%Generator%': ['GeneratorFunction', 'prototype'],
	'%GeneratorPrototype%': ['GeneratorFunction', 'prototype', 'prototype'],
	'%Int8ArrayPrototype%': ['Int8Array', 'prototype'],
	'%Int16ArrayPrototype%': ['Int16Array', 'prototype'],
	'%Int32ArrayPrototype%': ['Int32Array', 'prototype'],
	'%JSONParse%': ['JSON', 'parse'],
	'%JSONStringify%': ['JSON', 'stringify'],
	'%MapPrototype%': ['Map', 'prototype'],
	'%NumberPrototype%': ['Number', 'prototype'],
	'%ObjectPrototype%': ['Object', 'prototype'],
	'%ObjProto_toString%': ['Object', 'prototype', 'toString'],
	'%ObjProto_valueOf%': ['Object', 'prototype', 'valueOf'],
	'%PromisePrototype%': ['Promise', 'prototype'],
	'%PromiseProto_then%': ['Promise', 'prototype', 'then'],
	'%Promise_all%': ['Promise', 'all'],
	'%Promise_reject%': ['Promise', 'reject'],
	'%Promise_resolve%': ['Promise', 'resolve'],
	'%RangeErrorPrototype%': ['RangeError', 'prototype'],
	'%ReferenceErrorPrototype%': ['ReferenceError', 'prototype'],
	'%RegExpPrototype%': ['RegExp', 'prototype'],
	'%SetPrototype%': ['Set', 'prototype'],
	'%SharedArrayBufferPrototype%': ['SharedArrayBuffer', 'prototype'],
	'%StringPrototype%': ['String', 'prototype'],
	'%SymbolPrototype%': ['Symbol', 'prototype'],
	'%SyntaxErrorPrototype%': ['SyntaxError', 'prototype'],
	'%TypedArrayPrototype%': ['TypedArray', 'prototype'],
	'%TypeErrorPrototype%': ['TypeError', 'prototype'],
	'%Uint8ArrayPrototype%': ['Uint8Array', 'prototype'],
	'%Uint8ClampedArrayPrototype%': ['Uint8ClampedArray', 'prototype'],
	'%Uint16ArrayPrototype%': ['Uint16Array', 'prototype'],
	'%Uint32ArrayPrototype%': ['Uint32Array', 'prototype'],
	'%URIErrorPrototype%': ['URIError', 'prototype'],
	'%WeakMapPrototype%': ['WeakMap', 'prototype'],
	'%WeakSetPrototype%': ['WeakSet', 'prototype']
};

var bind = require('function-bind');
var hasOwn = require('hasown');
var $concat = bind.call($call, Array.prototype.concat);
var $spliceApply = bind.call($apply, Array.prototype.splice);
var $replace = bind.call($call, String.prototype.replace);
var $strSlice = bind.call($call, String.prototype.slice);
var $exec = bind.call($call, RegExp.prototype.exec);

/* adapted from https://github.com/lodash/lodash/blob/4.17.15/dist/lodash.js#L6735-L6744 */
var rePropName = /[^%.[\]]+|\[(?:(-?\d+(?:\.\d+)?)|(["'])((?:(?!\2)[^\\]|\\.)*?)\2)\]|(?=(?:\.|\[\])(?:\.|\[\]|%$))/g;
var reEscapeChar = /\\(\\)?/g; /** Used to match backslashes in property paths. */
var stringToPath = function stringToPath(string) {
	var first = $strSlice(string, 0, 1);
	var last = $strSlice(string, -1);
	if (first === '%' && last !== '%') {
		throw new $SyntaxError('invalid intrinsic syntax, expected closing `%`');
	} else if (last === '%' && first !== '%') {
		throw new $SyntaxError('invalid intrinsic syntax, expected opening `%`');
	}
	var result = [];
	$replace(string, rePropName, function (match, number, quote, subString) {
		result[result.length] = quote ? $replace(subString, reEscapeChar, '$1') : number || match;
	});
	return result;
};
/* end adaptation */

var getBaseIntrinsic = function getBaseIntrinsic(name, allowMissing) {
	var intrinsicName = name;
	var alias;
	if (hasOwn(LEGACY_ALIASES, intrinsicName)) {
		alias = LEGACY_ALIASES[intrinsicName];
		intrinsicName = '%' + alias[0] + '%';
	}

	if (hasOwn(INTRINSICS, intrinsicName)) {
		var value = INTRINSICS[intrinsicName];
		if (value === needsEval) {
			value = doEval(intrinsicName);
		}
		if (typeof value === 'undefined' && !allowMissing) {
			throw new $TypeError('intrinsic ' + name + ' exists, but is not available. Please file an issue!');
		}

		return {
			alias: alias,
			name: intrinsicName,
			value: value
		};
	}

	throw new $SyntaxError('intrinsic ' + name + ' does not exist!');
};

module.exports = function GetIntrinsic(name, allowMissing) {
	if (typeof name !== 'string' || name.length === 0) {
		throw new $TypeError('intrinsic name must be a non-empty string');
	}
	if (arguments.length > 1 && typeof allowMissing !== 'boolean') {
		throw new $TypeError('"allowMissing" argument must be a boolean');
	}

	if ($exec(/^%?[^%]*%?$/, name) === null) {
		throw new $SyntaxError('`%` may not be present anywhere but at the beginning and end of the intrinsic name');
	}
	var parts = stringToPath(name);
	var intrinsicBaseName = parts.length > 0 ? parts[0] : '';

	var intrinsic = getBaseIntrinsic('%' + intrinsicBaseName + '%', allowMissing);
	var intrinsicRealName = intrinsic.name;
	var value = intrinsic.value;
	var skipFurtherCaching = false;

	var alias = intrinsic.alias;
	if (alias) {
		intrinsicBaseName = alias[0];
		$spliceApply(parts, $concat([0, 1], alias));
	}

	for (var i = 1, isOwn = true; i < parts.length; i += 1) {
		var part = parts[i];
		var first = $strSlice(part, 0, 1);
		var last = $strSlice(part, -1);
		if (
			(
				(first === '"' || first === "'" || first === '`')
				|| (last === '"' || last === "'" || last === '`')
			)
			&& first !== last
		) {
			throw new $SyntaxError('property names with quotes must have matching quotes');
		}
		if (part === 'constructor' || !isOwn) {
			skipFurtherCaching = true;
		}

		intrinsicBaseName += '.' + part;
		intrinsicRealName = '%' + intrinsicBaseName + '%';

		if (hasOwn(INTRINSICS, intrinsicRealName)) {
			value = INTRINSICS[intrinsicRealName];
		} else if (value != null) {
			if (!(part in value)) {
				if (!allowMissing) {
					throw new $TypeError('base intrinsic for ' + name + ' exists, but the property is not available.');
				}
				return void undefined;
			}
			if ($gOPD && (i + 1) >= parts.length) {
				var desc = $gOPD(value, part);
				isOwn = !!desc;

				// By convention, when a data property is converted to an accessor
				// property to emulate a data property that does not suffer from
				// the override mistake, that accessor's getter is marked with
				// an `originalValue` property. Here, when we detect this, we
				// uphold the illusion by pretending to see that original data
				// property, i.e., returning the value rather than the getter
				// itself.
				if (isOwn && 'get' in desc && !('originalValue' in desc.get)) {
					value = desc.get;
				} else {
					value = value[part];
				}
			} else {
				isOwn = hasOwn(value, part);
				value = value[part];
			}

			if (isOwn && !skipFurtherCaching) {
				INTRINSICS[intrinsicRealName] = value;
			}
		}
	}
	return value;
};

},{"call-bind-apply-helpers/functionApply":5,"call-bind-apply-helpers/functionCall":6,"es-define-property":13,"es-errors":15,"es-errors/eval":14,"es-errors/range":16,"es-errors/ref":17,"es-errors/syntax":18,"es-errors/type":19,"es-errors/uri":20,"es-object-atoms":21,"function-bind":25,"get-proto":30,"get-proto/Object.getPrototypeOf":28,"get-proto/Reflect.getPrototypeOf":29,"gopd":32,"has-symbols":34,"hasown":37,"math-intrinsics/abs":44,"math-intrinsics/floor":45,"math-intrinsics/max":47,"math-intrinsics/min":48,"math-intrinsics/pow":49,"math-intrinsics/round":50,"math-intrinsics/sign":51}],28:[function(require,module,exports){
'use strict';

var $Object = require('es-object-atoms');

/** @type {import('./Object.getPrototypeOf')} */
module.exports = $Object.getPrototypeOf || null;

},{"es-object-atoms":21}],29:[function(require,module,exports){
'use strict';

/** @type {import('./Reflect.getPrototypeOf')} */
module.exports = (typeof Reflect !== 'undefined' && Reflect.getPrototypeOf) || null;

},{}],30:[function(require,module,exports){
'use strict';

var reflectGetProto = require('./Reflect.getPrototypeOf');
var originalGetProto = require('./Object.getPrototypeOf');

var getDunderProto = require('dunder-proto/get');

/** @type {import('.')} */
module.exports = reflectGetProto
	? function getProto(O) {
		// @ts-expect-error TS can't narrow inside a closure, for some reason
		return reflectGetProto(O);
	}
	: originalGetProto
		? function getProto(O) {
			if (!O || (typeof O !== 'object' && typeof O !== 'function')) {
				throw new TypeError('getProto: not an object');
			}
			// @ts-expect-error TS can't narrow inside a closure, for some reason
			return originalGetProto(O);
		}
		: getDunderProto
			? function getProto(O) {
				// @ts-expect-error TS can't narrow inside a closure, for some reason
				return getDunderProto(O);
			}
			: null;

},{"./Object.getPrototypeOf":28,"./Reflect.getPrototypeOf":29,"dunder-proto/get":12}],31:[function(require,module,exports){
'use strict';

/** @type {import('./gOPD')} */
module.exports = Object.getOwnPropertyDescriptor;

},{}],32:[function(require,module,exports){
'use strict';

/** @type {import('.')} */
var $gOPD = require('./gOPD');

if ($gOPD) {
	try {
		$gOPD([], 'length');
	} catch (e) {
		// IE 8 has a broken gOPD
		$gOPD = null;
	}
}

module.exports = $gOPD;

},{"./gOPD":31}],33:[function(require,module,exports){
'use strict';

var $defineProperty = require('es-define-property');

var hasPropertyDescriptors = function hasPropertyDescriptors() {
	return !!$defineProperty;
};

hasPropertyDescriptors.hasArrayLengthDefineBug = function hasArrayLengthDefineBug() {
	// node v0.6 has a bug where array lengths can be Set but not Defined
	if (!$defineProperty) {
		return null;
	}
	try {
		return $defineProperty([], 'length', { value: 1 }).length !== 1;
	} catch (e) {
		// In Firefox 4-22, defining length on an array throws an exception.
		return true;
	}
};

module.exports = hasPropertyDescriptors;

},{"es-define-property":13}],34:[function(require,module,exports){
'use strict';

var origSymbol = typeof Symbol !== 'undefined' && Symbol;
var hasSymbolSham = require('./shams');

/** @type {import('.')} */
module.exports = function hasNativeSymbols() {
	if (typeof origSymbol !== 'function') { return false; }
	if (typeof Symbol !== 'function') { return false; }
	if (typeof origSymbol('foo') !== 'symbol') { return false; }
	if (typeof Symbol('bar') !== 'symbol') { return false; }

	return hasSymbolSham();
};

},{"./shams":35}],35:[function(require,module,exports){
'use strict';

/** @type {import('./shams')} */
/* eslint complexity: [2, 18], max-statements: [2, 33] */
module.exports = function hasSymbols() {
	if (typeof Symbol !== 'function' || typeof Object.getOwnPropertySymbols !== 'function') { return false; }
	if (typeof Symbol.iterator === 'symbol') { return true; }

	/** @type {{ [k in symbol]?: unknown }} */
	var obj = {};
	var sym = Symbol('test');
	var symObj = Object(sym);
	if (typeof sym === 'string') { return false; }

	if (Object.prototype.toString.call(sym) !== '[object Symbol]') { return false; }
	if (Object.prototype.toString.call(symObj) !== '[object Symbol]') { return false; }

	// temp disabled per https://github.com/ljharb/object.assign/issues/17
	// if (sym instanceof Symbol) { return false; }
	// temp disabled per https://github.com/WebReflection/get-own-property-symbols/issues/4
	// if (!(symObj instanceof Symbol)) { return false; }

	// if (typeof Symbol.prototype.toString !== 'function') { return false; }
	// if (String(sym) !== Symbol.prototype.toString.call(sym)) { return false; }

	var symVal = 42;
	obj[sym] = symVal;
	for (var _ in obj) { return false; } // eslint-disable-line no-restricted-syntax, no-unreachable-loop
	if (typeof Object.keys === 'function' && Object.keys(obj).length !== 0) { return false; }

	if (typeof Object.getOwnPropertyNames === 'function' && Object.getOwnPropertyNames(obj).length !== 0) { return false; }

	var syms = Object.getOwnPropertySymbols(obj);
	if (syms.length !== 1 || syms[0] !== sym) { return false; }

	if (!Object.prototype.propertyIsEnumerable.call(obj, sym)) { return false; }

	if (typeof Object.getOwnPropertyDescriptor === 'function') {
		// eslint-disable-next-line no-extra-parens
		var descriptor = /** @type {PropertyDescriptor} */ (Object.getOwnPropertyDescriptor(obj, sym));
		if (descriptor.value !== symVal || descriptor.enumerable !== true) { return false; }
	}

	return true;
};

},{}],36:[function(require,module,exports){
'use strict';

var hasSymbols = require('has-symbols/shams');

/** @type {import('.')} */
module.exports = function hasToStringTagShams() {
	return hasSymbols() && !!Symbol.toStringTag;
};

},{"has-symbols/shams":35}],37:[function(require,module,exports){
'use strict';

var call = Function.prototype.call;
var $hasOwn = Object.prototype.hasOwnProperty;
var bind = require('function-bind');

/** @type {import('.')} */
module.exports = bind.call(call, $hasOwn);

},{"function-bind":25}],38:[function(require,module,exports){
if (typeof Object.create === 'function') {
  // implementation from standard node.js 'util' module
  module.exports = function inherits(ctor, superCtor) {
    if (superCtor) {
      ctor.super_ = superCtor
      ctor.prototype = Object.create(superCtor.prototype, {
        constructor: {
          value: ctor,
          enumerable: false,
          writable: true,
          configurable: true
        }
      })
    }
  };
} else {
  // old school shim for old browsers
  module.exports = function inherits(ctor, superCtor) {
    if (superCtor) {
      ctor.super_ = superCtor
      var TempCtor = function () {}
      TempCtor.prototype = superCtor.prototype
      ctor.prototype = new TempCtor()
      ctor.prototype.constructor = ctor
    }
  }
}

},{}],39:[function(require,module,exports){
'use strict';

var hasToStringTag = require('has-tostringtag/shams')();
var callBound = require('call-bound');

var $toString = callBound('Object.prototype.toString');

/** @type {import('.')} */
var isStandardArguments = function isArguments(value) {
	if (
		hasToStringTag
		&& value
		&& typeof value === 'object'
		&& Symbol.toStringTag in value
	) {
		return false;
	}
	return $toString(value) === '[object Arguments]';
};

/** @type {import('.')} */
var isLegacyArguments = function isArguments(value) {
	if (isStandardArguments(value)) {
		return true;
	}
	return value !== null
		&& typeof value === 'object'
		&& 'length' in value
		&& typeof value.length === 'number'
		&& value.length >= 0
		&& $toString(value) !== '[object Array]'
		&& 'callee' in value
		&& $toString(value.callee) === '[object Function]';
};

var supportsStandardArguments = (function () {
	return isStandardArguments(arguments);
}());

// @ts-expect-error TODO make this not error
isStandardArguments.isLegacyArguments = isLegacyArguments; // for tests

/** @type {import('.')} */
module.exports = supportsStandardArguments ? isStandardArguments : isLegacyArguments;

},{"call-bound":10,"has-tostringtag/shams":36}],40:[function(require,module,exports){
'use strict';

var fnToStr = Function.prototype.toString;
var reflectApply = typeof Reflect === 'object' && Reflect !== null && Reflect.apply;
var badArrayLike;
var isCallableMarker;
if (typeof reflectApply === 'function' && typeof Object.defineProperty === 'function') {
	try {
		badArrayLike = Object.defineProperty({}, 'length', {
			get: function () {
				throw isCallableMarker;
			}
		});
		isCallableMarker = {};
		// eslint-disable-next-line no-throw-literal
		reflectApply(function () { throw 42; }, null, badArrayLike);
	} catch (_) {
		if (_ !== isCallableMarker) {
			reflectApply = null;
		}
	}
} else {
	reflectApply = null;
}

var constructorRegex = /^\s*class\b/;
var isES6ClassFn = function isES6ClassFunction(value) {
	try {
		var fnStr = fnToStr.call(value);
		return constructorRegex.test(fnStr);
	} catch (e) {
		return false; // not a function
	}
};

var tryFunctionObject = function tryFunctionToStr(value) {
	try {
		if (isES6ClassFn(value)) { return false; }
		fnToStr.call(value);
		return true;
	} catch (e) {
		return false;
	}
};
var toStr = Object.prototype.toString;
var objectClass = '[object Object]';
var fnClass = '[object Function]';
var genClass = '[object GeneratorFunction]';
var ddaClass = '[object HTMLAllCollection]'; // IE 11
var ddaClass2 = '[object HTML document.all class]';
var ddaClass3 = '[object HTMLCollection]'; // IE 9-10
var hasToStringTag = typeof Symbol === 'function' && !!Symbol.toStringTag; // better: use `has-tostringtag`

var isIE68 = !(0 in [,]); // eslint-disable-line no-sparse-arrays, comma-spacing

var isDDA = function isDocumentDotAll() { return false; };
if (typeof document === 'object') {
	// Firefox 3 canonicalizes DDA to undefined when it's not accessed directly
	var all = document.all;
	if (toStr.call(all) === toStr.call(document.all)) {
		isDDA = function isDocumentDotAll(value) {
			/* globals document: false */
			// in IE 6-8, typeof document.all is "object" and it's truthy
			if ((isIE68 || !value) && (typeof value === 'undefined' || typeof value === 'object')) {
				try {
					var str = toStr.call(value);
					return (
						str === ddaClass
						|| str === ddaClass2
						|| str === ddaClass3 // opera 12.16
						|| str === objectClass // IE 6-8
					) && value('') == null; // eslint-disable-line eqeqeq
				} catch (e) { /**/ }
			}
			return false;
		};
	}
}

module.exports = reflectApply
	? function isCallable(value) {
		if (isDDA(value)) { return true; }
		if (!value) { return false; }
		if (typeof value !== 'function' && typeof value !== 'object') { return false; }
		try {
			reflectApply(value, null, badArrayLike);
		} catch (e) {
			if (e !== isCallableMarker) { return false; }
		}
		return !isES6ClassFn(value) && tryFunctionObject(value);
	}
	: function isCallable(value) {
		if (isDDA(value)) { return true; }
		if (!value) { return false; }
		if (typeof value !== 'function' && typeof value !== 'object') { return false; }
		if (hasToStringTag) { return tryFunctionObject(value); }
		if (isES6ClassFn(value)) { return false; }
		var strClass = toStr.call(value);
		if (strClass !== fnClass && strClass !== genClass && !(/^\[object HTML/).test(strClass)) { return false; }
		return tryFunctionObject(value);
	};

},{}],41:[function(require,module,exports){
'use strict';

var callBound = require('call-bound');
var safeRegexTest = require('safe-regex-test');
var isFnRegex = safeRegexTest(/^\s*(?:function)?\*/);
var hasToStringTag = require('has-tostringtag/shams')();
var getProto = require('get-proto');

var toStr = callBound('Object.prototype.toString');
var fnToStr = callBound('Function.prototype.toString');

var getGeneratorFunction = require('generator-function');

/** @type {import('.')} */
module.exports = function isGeneratorFunction(fn) {
	if (typeof fn !== 'function') {
		return false;
	}
	if (isFnRegex(fnToStr(fn))) {
		return true;
	}
	if (!hasToStringTag) {
		var str = toStr(fn);
		return str === '[object GeneratorFunction]';
	}
	if (!getProto) {
		return false;
	}
	var GeneratorFunction = getGeneratorFunction();
	return GeneratorFunction && getProto(fn) === GeneratorFunction.prototype;
};

},{"call-bound":10,"generator-function":26,"get-proto":30,"has-tostringtag/shams":36,"safe-regex-test":54}],42:[function(require,module,exports){
'use strict';

var callBound = require('call-bound');
var hasToStringTag = require('has-tostringtag/shams')();
var hasOwn = require('hasown');
var gOPD = require('gopd');

/** @type {import('.')} */
var fn;

if (hasToStringTag) {
	/** @type {(receiver: ThisParameterType<typeof RegExp.prototype.exec>, ...args: Parameters<typeof RegExp.prototype.exec>) => ReturnType<typeof RegExp.prototype.exec>} */
	var $exec = callBound('RegExp.prototype.exec');
	/** @type {object} */
	var isRegexMarker = {};

	var throwRegexMarker = function () {
		throw isRegexMarker;
	};
	/** @type {{ toString(): never, valueOf(): never, [Symbol.toPrimitive]?(): never }} */
	var badStringifier = {
		toString: throwRegexMarker,
		valueOf: throwRegexMarker
	};

	if (typeof Symbol.toPrimitive === 'symbol') {
		badStringifier[Symbol.toPrimitive] = throwRegexMarker;
	}

	/** @type {import('.')} */
	// @ts-expect-error TS can't figure out that the $exec call always throws
	// eslint-disable-next-line consistent-return
	fn = function isRegex(value) {
		if (!value || typeof value !== 'object') {
			return false;
		}

		// eslint-disable-next-line no-extra-parens
		var descriptor = /** @type {NonNullable<typeof gOPD>} */ (gOPD)(/** @type {{ lastIndex?: unknown }} */ (value), 'lastIndex');
		var hasLastIndexDataProperty = descriptor && hasOwn(descriptor, 'value');
		if (!hasLastIndexDataProperty) {
			return false;
		}

		try {
			// eslint-disable-next-line no-extra-parens
			$exec(value, /** @type {string} */ (/** @type {unknown} */ (badStringifier)));
		} catch (e) {
			return e === isRegexMarker;
		}
	};
} else {
	/** @type {(receiver: ThisParameterType<typeof Object.prototype.toString>, ...args: Parameters<typeof Object.prototype.toString>) => ReturnType<typeof Object.prototype.toString>} */
	var $toString = callBound('Object.prototype.toString');
	/** @const @type {'[object RegExp]'} */
	var regexClass = '[object RegExp]';

	/** @type {import('.')} */
	fn = function isRegex(value) {
		// In older browsers, typeof regex incorrectly returns 'function'
		if (!value || (typeof value !== 'object' && typeof value !== 'function')) {
			return false;
		}

		return $toString(value) === regexClass;
	};
}

module.exports = fn;

},{"call-bound":10,"gopd":32,"has-tostringtag/shams":36,"hasown":37}],43:[function(require,module,exports){
'use strict';

var whichTypedArray = require('which-typed-array');

/** @type {import('.')} */
module.exports = function isTypedArray(value) {
	return !!whichTypedArray(value);
};

},{"which-typed-array":59}],44:[function(require,module,exports){
'use strict';

/** @type {import('./abs')} */
module.exports = Math.abs;

},{}],45:[function(require,module,exports){
'use strict';

/** @type {import('./floor')} */
module.exports = Math.floor;

},{}],46:[function(require,module,exports){
'use strict';

/** @type {import('./isNaN')} */
module.exports = Number.isNaN || function isNaN(a) {
	return a !== a;
};

},{}],47:[function(require,module,exports){
'use strict';

/** @type {import('./max')} */
module.exports = Math.max;

},{}],48:[function(require,module,exports){
'use strict';

/** @type {import('./min')} */
module.exports = Math.min;

},{}],49:[function(require,module,exports){
'use strict';

/** @type {import('./pow')} */
module.exports = Math.pow;

},{}],50:[function(require,module,exports){
'use strict';

/** @type {import('./round')} */
module.exports = Math.round;

},{}],51:[function(require,module,exports){
'use strict';

var $isNaN = require('./isNaN');

/** @type {import('./sign')} */
module.exports = function sign(number) {
	if ($isNaN(number) || number === 0) {
		return number;
	}
	return number < 0 ? -1 : +1;
};

},{"./isNaN":46}],52:[function(require,module,exports){
(function (process){(function (){
// 'path' module extracted from Node.js v8.11.1 (only the posix part)
// transplited with Babel

// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

'use strict';

function assertPath(path) {
  if (typeof path !== 'string') {
    throw new TypeError('Path must be a string. Received ' + JSON.stringify(path));
  }
}

// Resolves . and .. elements in a path with directory names
function normalizeStringPosix(path, allowAboveRoot) {
  var res = '';
  var lastSegmentLength = 0;
  var lastSlash = -1;
  var dots = 0;
  var code;
  for (var i = 0; i <= path.length; ++i) {
    if (i < path.length)
      code = path.charCodeAt(i);
    else if (code === 47 /*/*/)
      break;
    else
      code = 47 /*/*/;
    if (code === 47 /*/*/) {
      if (lastSlash === i - 1 || dots === 1) {
        // NOOP
      } else if (lastSlash !== i - 1 && dots === 2) {
        if (res.length < 2 || lastSegmentLength !== 2 || res.charCodeAt(res.length - 1) !== 46 /*.*/ || res.charCodeAt(res.length - 2) !== 46 /*.*/) {
          if (res.length > 2) {
            var lastSlashIndex = res.lastIndexOf('/');
            if (lastSlashIndex !== res.length - 1) {
              if (lastSlashIndex === -1) {
                res = '';
                lastSegmentLength = 0;
              } else {
                res = res.slice(0, lastSlashIndex);
                lastSegmentLength = res.length - 1 - res.lastIndexOf('/');
              }
              lastSlash = i;
              dots = 0;
              continue;
            }
          } else if (res.length === 2 || res.length === 1) {
            res = '';
            lastSegmentLength = 0;
            lastSlash = i;
            dots = 0;
            continue;
          }
        }
        if (allowAboveRoot) {
          if (res.length > 0)
            res += '/..';
          else
            res = '..';
          lastSegmentLength = 2;
        }
      } else {
        if (res.length > 0)
          res += '/' + path.slice(lastSlash + 1, i);
        else
          res = path.slice(lastSlash + 1, i);
        lastSegmentLength = i - lastSlash - 1;
      }
      lastSlash = i;
      dots = 0;
    } else if (code === 46 /*.*/ && dots !== -1) {
      ++dots;
    } else {
      dots = -1;
    }
  }
  return res;
}

function _format(sep, pathObject) {
  var dir = pathObject.dir || pathObject.root;
  var base = pathObject.base || (pathObject.name || '') + (pathObject.ext || '');
  if (!dir) {
    return base;
  }
  if (dir === pathObject.root) {
    return dir + base;
  }
  return dir + sep + base;
}

var posix = {
  // path.resolve([from ...], to)
  resolve: function resolve() {
    var resolvedPath = '';
    var resolvedAbsolute = false;
    var cwd;

    for (var i = arguments.length - 1; i >= -1 && !resolvedAbsolute; i--) {
      var path;
      if (i >= 0)
        path = arguments[i];
      else {
        if (cwd === undefined)
          cwd = process.cwd();
        path = cwd;
      }

      assertPath(path);

      // Skip empty entries
      if (path.length === 0) {
        continue;
      }

      resolvedPath = path + '/' + resolvedPath;
      resolvedAbsolute = path.charCodeAt(0) === 47 /*/*/;
    }

    // At this point the path should be resolved to a full absolute path, but
    // handle relative paths to be safe (might happen when process.cwd() fails)

    // Normalize the path
    resolvedPath = normalizeStringPosix(resolvedPath, !resolvedAbsolute);

    if (resolvedAbsolute) {
      if (resolvedPath.length > 0)
        return '/' + resolvedPath;
      else
        return '/';
    } else if (resolvedPath.length > 0) {
      return resolvedPath;
    } else {
      return '.';
    }
  },

  normalize: function normalize(path) {
    assertPath(path);

    if (path.length === 0) return '.';

    var isAbsolute = path.charCodeAt(0) === 47 /*/*/;
    var trailingSeparator = path.charCodeAt(path.length - 1) === 47 /*/*/;

    // Normalize the path
    path = normalizeStringPosix(path, !isAbsolute);

    if (path.length === 0 && !isAbsolute) path = '.';
    if (path.length > 0 && trailingSeparator) path += '/';

    if (isAbsolute) return '/' + path;
    return path;
  },

  isAbsolute: function isAbsolute(path) {
    assertPath(path);
    return path.length > 0 && path.charCodeAt(0) === 47 /*/*/;
  },

  join: function join() {
    if (arguments.length === 0)
      return '.';
    var joined;
    for (var i = 0; i < arguments.length; ++i) {
      var arg = arguments[i];
      assertPath(arg);
      if (arg.length > 0) {
        if (joined === undefined)
          joined = arg;
        else
          joined += '/' + arg;
      }
    }
    if (joined === undefined)
      return '.';
    return posix.normalize(joined);
  },

  relative: function relative(from, to) {
    assertPath(from);
    assertPath(to);

    if (from === to) return '';

    from = posix.resolve(from);
    to = posix.resolve(to);

    if (from === to) return '';

    // Trim any leading backslashes
    var fromStart = 1;
    for (; fromStart < from.length; ++fromStart) {
      if (from.charCodeAt(fromStart) !== 47 /*/*/)
        break;
    }
    var fromEnd = from.length;
    var fromLen = fromEnd - fromStart;

    // Trim any leading backslashes
    var toStart = 1;
    for (; toStart < to.length; ++toStart) {
      if (to.charCodeAt(toStart) !== 47 /*/*/)
        break;
    }
    var toEnd = to.length;
    var toLen = toEnd - toStart;

    // Compare paths to find the longest common path from root
    var length = fromLen < toLen ? fromLen : toLen;
    var lastCommonSep = -1;
    var i = 0;
    for (; i <= length; ++i) {
      if (i === length) {
        if (toLen > length) {
          if (to.charCodeAt(toStart + i) === 47 /*/*/) {
            // We get here if `from` is the exact base path for `to`.
            // For example: from='/foo/bar'; to='/foo/bar/baz'
            return to.slice(toStart + i + 1);
          } else if (i === 0) {
            // We get here if `from` is the root
            // For example: from='/'; to='/foo'
            return to.slice(toStart + i);
          }
        } else if (fromLen > length) {
          if (from.charCodeAt(fromStart + i) === 47 /*/*/) {
            // We get here if `to` is the exact base path for `from`.
            // For example: from='/foo/bar/baz'; to='/foo/bar'
            lastCommonSep = i;
          } else if (i === 0) {
            // We get here if `to` is the root.
            // For example: from='/foo'; to='/'
            lastCommonSep = 0;
          }
        }
        break;
      }
      var fromCode = from.charCodeAt(fromStart + i);
      var toCode = to.charCodeAt(toStart + i);
      if (fromCode !== toCode)
        break;
      else if (fromCode === 47 /*/*/)
        lastCommonSep = i;
    }

    var out = '';
    // Generate the relative path based on the path difference between `to`
    // and `from`
    for (i = fromStart + lastCommonSep + 1; i <= fromEnd; ++i) {
      if (i === fromEnd || from.charCodeAt(i) === 47 /*/*/) {
        if (out.length === 0)
          out += '..';
        else
          out += '/..';
      }
    }

    // Lastly, append the rest of the destination (`to`) path that comes after
    // the common path parts
    if (out.length > 0)
      return out + to.slice(toStart + lastCommonSep);
    else {
      toStart += lastCommonSep;
      if (to.charCodeAt(toStart) === 47 /*/*/)
        ++toStart;
      return to.slice(toStart);
    }
  },

  _makeLong: function _makeLong(path) {
    return path;
  },

  dirname: function dirname(path) {
    assertPath(path);
    if (path.length === 0) return '.';
    var code = path.charCodeAt(0);
    var hasRoot = code === 47 /*/*/;
    var end = -1;
    var matchedSlash = true;
    for (var i = path.length - 1; i >= 1; --i) {
      code = path.charCodeAt(i);
      if (code === 47 /*/*/) {
          if (!matchedSlash) {
            end = i;
            break;
          }
        } else {
        // We saw the first non-path separator
        matchedSlash = false;
      }
    }

    if (end === -1) return hasRoot ? '/' : '.';
    if (hasRoot && end === 1) return '//';
    return path.slice(0, end);
  },

  basename: function basename(path, ext) {
    if (ext !== undefined && typeof ext !== 'string') throw new TypeError('"ext" argument must be a string');
    assertPath(path);

    var start = 0;
    var end = -1;
    var matchedSlash = true;
    var i;

    if (ext !== undefined && ext.length > 0 && ext.length <= path.length) {
      if (ext.length === path.length && ext === path) return '';
      var extIdx = ext.length - 1;
      var firstNonSlashEnd = -1;
      for (i = path.length - 1; i >= 0; --i) {
        var code = path.charCodeAt(i);
        if (code === 47 /*/*/) {
            // If we reached a path separator that was not part of a set of path
            // separators at the end of the string, stop now
            if (!matchedSlash) {
              start = i + 1;
              break;
            }
          } else {
          if (firstNonSlashEnd === -1) {
            // We saw the first non-path separator, remember this index in case
            // we need it if the extension ends up not matching
            matchedSlash = false;
            firstNonSlashEnd = i + 1;
          }
          if (extIdx >= 0) {
            // Try to match the explicit extension
            if (code === ext.charCodeAt(extIdx)) {
              if (--extIdx === -1) {
                // We matched the extension, so mark this as the end of our path
                // component
                end = i;
              }
            } else {
              // Extension does not match, so our result is the entire path
              // component
              extIdx = -1;
              end = firstNonSlashEnd;
            }
          }
        }
      }

      if (start === end) end = firstNonSlashEnd;else if (end === -1) end = path.length;
      return path.slice(start, end);
    } else {
      for (i = path.length - 1; i >= 0; --i) {
        if (path.charCodeAt(i) === 47 /*/*/) {
            // If we reached a path separator that was not part of a set of path
            // separators at the end of the string, stop now
            if (!matchedSlash) {
              start = i + 1;
              break;
            }
          } else if (end === -1) {
          // We saw the first non-path separator, mark this as the end of our
          // path component
          matchedSlash = false;
          end = i + 1;
        }
      }

      if (end === -1) return '';
      return path.slice(start, end);
    }
  },

  extname: function extname(path) {
    assertPath(path);
    var startDot = -1;
    var startPart = 0;
    var end = -1;
    var matchedSlash = true;
    // Track the state of characters (if any) we see before our first dot and
    // after any path separator we find
    var preDotState = 0;
    for (var i = path.length - 1; i >= 0; --i) {
      var code = path.charCodeAt(i);
      if (code === 47 /*/*/) {
          // If we reached a path separator that was not part of a set of path
          // separators at the end of the string, stop now
          if (!matchedSlash) {
            startPart = i + 1;
            break;
          }
          continue;
        }
      if (end === -1) {
        // We saw the first non-path separator, mark this as the end of our
        // extension
        matchedSlash = false;
        end = i + 1;
      }
      if (code === 46 /*.*/) {
          // If this is our first dot, mark it as the start of our extension
          if (startDot === -1)
            startDot = i;
          else if (preDotState !== 1)
            preDotState = 1;
      } else if (startDot !== -1) {
        // We saw a non-dot and non-path separator before our dot, so we should
        // have a good chance at having a non-empty extension
        preDotState = -1;
      }
    }

    if (startDot === -1 || end === -1 ||
        // We saw a non-dot character immediately before the dot
        preDotState === 0 ||
        // The (right-most) trimmed path component is exactly '..'
        preDotState === 1 && startDot === end - 1 && startDot === startPart + 1) {
      return '';
    }
    return path.slice(startDot, end);
  },

  format: function format(pathObject) {
    if (pathObject === null || typeof pathObject !== 'object') {
      throw new TypeError('The "pathObject" argument must be of type Object. Received type ' + typeof pathObject);
    }
    return _format('/', pathObject);
  },

  parse: function parse(path) {
    assertPath(path);

    var ret = { root: '', dir: '', base: '', ext: '', name: '' };
    if (path.length === 0) return ret;
    var code = path.charCodeAt(0);
    var isAbsolute = code === 47 /*/*/;
    var start;
    if (isAbsolute) {
      ret.root = '/';
      start = 1;
    } else {
      start = 0;
    }
    var startDot = -1;
    var startPart = 0;
    var end = -1;
    var matchedSlash = true;
    var i = path.length - 1;

    // Track the state of characters (if any) we see before our first dot and
    // after any path separator we find
    var preDotState = 0;

    // Get non-dir info
    for (; i >= start; --i) {
      code = path.charCodeAt(i);
      if (code === 47 /*/*/) {
          // If we reached a path separator that was not part of a set of path
          // separators at the end of the string, stop now
          if (!matchedSlash) {
            startPart = i + 1;
            break;
          }
          continue;
        }
      if (end === -1) {
        // We saw the first non-path separator, mark this as the end of our
        // extension
        matchedSlash = false;
        end = i + 1;
      }
      if (code === 46 /*.*/) {
          // If this is our first dot, mark it as the start of our extension
          if (startDot === -1) startDot = i;else if (preDotState !== 1) preDotState = 1;
        } else if (startDot !== -1) {
        // We saw a non-dot and non-path separator before our dot, so we should
        // have a good chance at having a non-empty extension
        preDotState = -1;
      }
    }

    if (startDot === -1 || end === -1 ||
    // We saw a non-dot character immediately before the dot
    preDotState === 0 ||
    // The (right-most) trimmed path component is exactly '..'
    preDotState === 1 && startDot === end - 1 && startDot === startPart + 1) {
      if (end !== -1) {
        if (startPart === 0 && isAbsolute) ret.base = ret.name = path.slice(1, end);else ret.base = ret.name = path.slice(startPart, end);
      }
    } else {
      if (startPart === 0 && isAbsolute) {
        ret.name = path.slice(1, startDot);
        ret.base = path.slice(1, end);
      } else {
        ret.name = path.slice(startPart, startDot);
        ret.base = path.slice(startPart, end);
      }
      ret.ext = path.slice(startDot, end);
    }

    if (startPart > 0) ret.dir = path.slice(0, startPart - 1);else if (isAbsolute) ret.dir = '/';

    return ret;
  },

  sep: '/',
  delimiter: ':',
  win32: null,
  posix: null
};

posix.posix = posix;

module.exports = posix;

}).call(this)}).call(this,require('_process'))
},{"_process":2}],53:[function(require,module,exports){
'use strict';

/** @type {import('.')} */
module.exports = [
	'Float16Array',
	'Float32Array',
	'Float64Array',
	'Int8Array',
	'Int16Array',
	'Int32Array',
	'Uint8Array',
	'Uint8ClampedArray',
	'Uint16Array',
	'Uint32Array',
	'BigInt64Array',
	'BigUint64Array'
];

},{}],54:[function(require,module,exports){
'use strict';

var callBound = require('call-bound');
var isRegex = require('is-regex');

var $exec = callBound('RegExp.prototype.exec');
var $TypeError = require('es-errors/type');

/** @type {import('.')} */
module.exports = function regexTester(regex) {
	if (!isRegex(regex)) {
		throw new $TypeError('`regex` must be a RegExp');
	}
	return function test(s) {
		return $exec(regex, s) !== null;
	};
};

},{"call-bound":10,"es-errors/type":19,"is-regex":42}],55:[function(require,module,exports){
'use strict';

var GetIntrinsic = require('get-intrinsic');
var define = require('define-data-property');
var hasDescriptors = require('has-property-descriptors')();
var gOPD = require('gopd');

var $TypeError = require('es-errors/type');
var $floor = GetIntrinsic('%Math.floor%');

/** @type {import('.')} */
module.exports = function setFunctionLength(fn, length) {
	if (typeof fn !== 'function') {
		throw new $TypeError('`fn` is not a function');
	}
	if (typeof length !== 'number' || length < 0 || length > 0xFFFFFFFF || $floor(length) !== length) {
		throw new $TypeError('`length` must be a positive 32-bit integer');
	}

	var loose = arguments.length > 2 && !!arguments[2];

	var functionLengthIsConfigurable = true;
	var functionLengthIsWritable = true;
	if ('length' in fn && gOPD) {
		var desc = gOPD(fn, 'length');
		if (desc && !desc.configurable) {
			functionLengthIsConfigurable = false;
		}
		if (desc && !desc.writable) {
			functionLengthIsWritable = false;
		}
	}

	if (functionLengthIsConfigurable || functionLengthIsWritable || !loose) {
		if (hasDescriptors) {
			define(/** @type {Parameters<define>[0]} */ (fn), 'length', length, true, true);
		} else {
			define(/** @type {Parameters<define>[0]} */ (fn), 'length', length);
		}
	}
	return fn;
};

},{"define-data-property":11,"es-errors/type":19,"get-intrinsic":27,"gopd":32,"has-property-descriptors":33}],56:[function(require,module,exports){
module.exports = function isBuffer(arg) {
  return arg && typeof arg === 'object'
    && typeof arg.copy === 'function'
    && typeof arg.fill === 'function'
    && typeof arg.readUInt8 === 'function';
}
},{}],57:[function(require,module,exports){
// Currently in sync with Node.js lib/internal/util/types.js
// https://github.com/nodejs/node/commit/112cc7c27551254aa2b17098fb774867f05ed0d9

'use strict';

var isArgumentsObject = require('is-arguments');
var isGeneratorFunction = require('is-generator-function');
var whichTypedArray = require('which-typed-array');
var isTypedArray = require('is-typed-array');

function uncurryThis(f) {
  return f.call.bind(f);
}

var BigIntSupported = typeof BigInt !== 'undefined';
var SymbolSupported = typeof Symbol !== 'undefined';

var ObjectToString = uncurryThis(Object.prototype.toString);

var numberValue = uncurryThis(Number.prototype.valueOf);
var stringValue = uncurryThis(String.prototype.valueOf);
var booleanValue = uncurryThis(Boolean.prototype.valueOf);

if (BigIntSupported) {
  var bigIntValue = uncurryThis(BigInt.prototype.valueOf);
}

if (SymbolSupported) {
  var symbolValue = uncurryThis(Symbol.prototype.valueOf);
}

function checkBoxedPrimitive(value, prototypeValueOf) {
  if (typeof value !== 'object') {
    return false;
  }
  try {
    prototypeValueOf(value);
    return true;
  } catch(e) {
    return false;
  }
}

exports.isArgumentsObject = isArgumentsObject;
exports.isGeneratorFunction = isGeneratorFunction;
exports.isTypedArray = isTypedArray;

// Taken from here and modified for better browser support
// https://github.com/sindresorhus/p-is-promise/blob/cda35a513bda03f977ad5cde3a079d237e82d7ef/index.js
function isPromise(input) {
	return (
		(
			typeof Promise !== 'undefined' &&
			input instanceof Promise
		) ||
		(
			input !== null &&
			typeof input === 'object' &&
			typeof input.then === 'function' &&
			typeof input.catch === 'function'
		)
	);
}
exports.isPromise = isPromise;

function isArrayBufferView(value) {
  if (typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView) {
    return ArrayBuffer.isView(value);
  }

  return (
    isTypedArray(value) ||
    isDataView(value)
  );
}
exports.isArrayBufferView = isArrayBufferView;


function isUint8Array(value) {
  return whichTypedArray(value) === 'Uint8Array';
}
exports.isUint8Array = isUint8Array;

function isUint8ClampedArray(value) {
  return whichTypedArray(value) === 'Uint8ClampedArray';
}
exports.isUint8ClampedArray = isUint8ClampedArray;

function isUint16Array(value) {
  return whichTypedArray(value) === 'Uint16Array';
}
exports.isUint16Array = isUint16Array;

function isUint32Array(value) {
  return whichTypedArray(value) === 'Uint32Array';
}
exports.isUint32Array = isUint32Array;

function isInt8Array(value) {
  return whichTypedArray(value) === 'Int8Array';
}
exports.isInt8Array = isInt8Array;

function isInt16Array(value) {
  return whichTypedArray(value) === 'Int16Array';
}
exports.isInt16Array = isInt16Array;

function isInt32Array(value) {
  return whichTypedArray(value) === 'Int32Array';
}
exports.isInt32Array = isInt32Array;

function isFloat32Array(value) {
  return whichTypedArray(value) === 'Float32Array';
}
exports.isFloat32Array = isFloat32Array;

function isFloat64Array(value) {
  return whichTypedArray(value) === 'Float64Array';
}
exports.isFloat64Array = isFloat64Array;

function isBigInt64Array(value) {
  return whichTypedArray(value) === 'BigInt64Array';
}
exports.isBigInt64Array = isBigInt64Array;

function isBigUint64Array(value) {
  return whichTypedArray(value) === 'BigUint64Array';
}
exports.isBigUint64Array = isBigUint64Array;

function isMapToString(value) {
  return ObjectToString(value) === '[object Map]';
}
isMapToString.working = (
  typeof Map !== 'undefined' &&
  isMapToString(new Map())
);

function isMap(value) {
  if (typeof Map === 'undefined') {
    return false;
  }

  return isMapToString.working
    ? isMapToString(value)
    : value instanceof Map;
}
exports.isMap = isMap;

function isSetToString(value) {
  return ObjectToString(value) === '[object Set]';
}
isSetToString.working = (
  typeof Set !== 'undefined' &&
  isSetToString(new Set())
);
function isSet(value) {
  if (typeof Set === 'undefined') {
    return false;
  }

  return isSetToString.working
    ? isSetToString(value)
    : value instanceof Set;
}
exports.isSet = isSet;

function isWeakMapToString(value) {
  return ObjectToString(value) === '[object WeakMap]';
}
isWeakMapToString.working = (
  typeof WeakMap !== 'undefined' &&
  isWeakMapToString(new WeakMap())
);
function isWeakMap(value) {
  if (typeof WeakMap === 'undefined') {
    return false;
  }

  return isWeakMapToString.working
    ? isWeakMapToString(value)
    : value instanceof WeakMap;
}
exports.isWeakMap = isWeakMap;

function isWeakSetToString(value) {
  return ObjectToString(value) === '[object WeakSet]';
}
isWeakSetToString.working = (
  typeof WeakSet !== 'undefined' &&
  isWeakSetToString(new WeakSet())
);
function isWeakSet(value) {
  return isWeakSetToString(value);
}
exports.isWeakSet = isWeakSet;

function isArrayBufferToString(value) {
  return ObjectToString(value) === '[object ArrayBuffer]';
}
isArrayBufferToString.working = (
  typeof ArrayBuffer !== 'undefined' &&
  isArrayBufferToString(new ArrayBuffer())
);
function isArrayBuffer(value) {
  if (typeof ArrayBuffer === 'undefined') {
    return false;
  }

  return isArrayBufferToString.working
    ? isArrayBufferToString(value)
    : value instanceof ArrayBuffer;
}
exports.isArrayBuffer = isArrayBuffer;

function isDataViewToString(value) {
  return ObjectToString(value) === '[object DataView]';
}
isDataViewToString.working = (
  typeof ArrayBuffer !== 'undefined' &&
  typeof DataView !== 'undefined' &&
  isDataViewToString(new DataView(new ArrayBuffer(1), 0, 1))
);
function isDataView(value) {
  if (typeof DataView === 'undefined') {
    return false;
  }

  return isDataViewToString.working
    ? isDataViewToString(value)
    : value instanceof DataView;
}
exports.isDataView = isDataView;

// Store a copy of SharedArrayBuffer in case it's deleted elsewhere
var SharedArrayBufferCopy = typeof SharedArrayBuffer !== 'undefined' ? SharedArrayBuffer : undefined;
function isSharedArrayBufferToString(value) {
  return ObjectToString(value) === '[object SharedArrayBuffer]';
}
function isSharedArrayBuffer(value) {
  if (typeof SharedArrayBufferCopy === 'undefined') {
    return false;
  }

  if (typeof isSharedArrayBufferToString.working === 'undefined') {
    isSharedArrayBufferToString.working = isSharedArrayBufferToString(new SharedArrayBufferCopy());
  }

  return isSharedArrayBufferToString.working
    ? isSharedArrayBufferToString(value)
    : value instanceof SharedArrayBufferCopy;
}
exports.isSharedArrayBuffer = isSharedArrayBuffer;

function isAsyncFunction(value) {
  return ObjectToString(value) === '[object AsyncFunction]';
}
exports.isAsyncFunction = isAsyncFunction;

function isMapIterator(value) {
  return ObjectToString(value) === '[object Map Iterator]';
}
exports.isMapIterator = isMapIterator;

function isSetIterator(value) {
  return ObjectToString(value) === '[object Set Iterator]';
}
exports.isSetIterator = isSetIterator;

function isGeneratorObject(value) {
  return ObjectToString(value) === '[object Generator]';
}
exports.isGeneratorObject = isGeneratorObject;

function isWebAssemblyCompiledModule(value) {
  return ObjectToString(value) === '[object WebAssembly.Module]';
}
exports.isWebAssemblyCompiledModule = isWebAssemblyCompiledModule;

function isNumberObject(value) {
  return checkBoxedPrimitive(value, numberValue);
}
exports.isNumberObject = isNumberObject;

function isStringObject(value) {
  return checkBoxedPrimitive(value, stringValue);
}
exports.isStringObject = isStringObject;

function isBooleanObject(value) {
  return checkBoxedPrimitive(value, booleanValue);
}
exports.isBooleanObject = isBooleanObject;

function isBigIntObject(value) {
  return BigIntSupported && checkBoxedPrimitive(value, bigIntValue);
}
exports.isBigIntObject = isBigIntObject;

function isSymbolObject(value) {
  return SymbolSupported && checkBoxedPrimitive(value, symbolValue);
}
exports.isSymbolObject = isSymbolObject;

function isBoxedPrimitive(value) {
  return (
    isNumberObject(value) ||
    isStringObject(value) ||
    isBooleanObject(value) ||
    isBigIntObject(value) ||
    isSymbolObject(value)
  );
}
exports.isBoxedPrimitive = isBoxedPrimitive;

function isAnyArrayBuffer(value) {
  return typeof Uint8Array !== 'undefined' && (
    isArrayBuffer(value) ||
    isSharedArrayBuffer(value)
  );
}
exports.isAnyArrayBuffer = isAnyArrayBuffer;

['isProxy', 'isExternal', 'isModuleNamespaceObject'].forEach(function(method) {
  Object.defineProperty(exports, method, {
    enumerable: false,
    value: function() {
      throw new Error(method + ' is not supported in userland');
    }
  });
});

},{"is-arguments":39,"is-generator-function":41,"is-typed-array":43,"which-typed-array":59}],58:[function(require,module,exports){
(function (process){(function (){
// Copyright Joyent, Inc. and other Node contributors.
//
// Permission is hereby granted, free of charge, to any person obtaining a
// copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to permit
// persons to whom the Software is furnished to do so, subject to the
// following conditions:
//
// The above copyright notice and this permission notice shall be included
// in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
// OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
// NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
// OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
// USE OR OTHER DEALINGS IN THE SOFTWARE.

var getOwnPropertyDescriptors = Object.getOwnPropertyDescriptors ||
  function getOwnPropertyDescriptors(obj) {
    var keys = Object.keys(obj);
    var descriptors = {};
    for (var i = 0; i < keys.length; i++) {
      descriptors[keys[i]] = Object.getOwnPropertyDescriptor(obj, keys[i]);
    }
    return descriptors;
  };

var formatRegExp = /%[sdj%]/g;
exports.format = function(f) {
  if (!isString(f)) {
    var objects = [];
    for (var i = 0; i < arguments.length; i++) {
      objects.push(inspect(arguments[i]));
    }
    return objects.join(' ');
  }

  var i = 1;
  var args = arguments;
  var len = args.length;
  var str = String(f).replace(formatRegExp, function(x) {
    if (x === '%%') return '%';
    if (i >= len) return x;
    switch (x) {
      case '%s': return String(args[i++]);
      case '%d': return Number(args[i++]);
      case '%j':
        try {
          return JSON.stringify(args[i++]);
        } catch (_) {
          return '[Circular]';
        }
      default:
        return x;
    }
  });
  for (var x = args[i]; i < len; x = args[++i]) {
    if (isNull(x) || !isObject(x)) {
      str += ' ' + x;
    } else {
      str += ' ' + inspect(x);
    }
  }
  return str;
};


// Mark that a method should not be used.
// Returns a modified function which warns once by default.
// If --no-deprecation is set, then it is a no-op.
exports.deprecate = function(fn, msg) {
  if (typeof process !== 'undefined' && process.noDeprecation === true) {
    return fn;
  }

  // Allow for deprecating things in the process of starting up.
  if (typeof process === 'undefined') {
    return function() {
      return exports.deprecate(fn, msg).apply(this, arguments);
    };
  }

  var warned = false;
  function deprecated() {
    if (!warned) {
      if (process.throwDeprecation) {
        throw new Error(msg);
      } else if (process.traceDeprecation) {
        console.trace(msg);
      } else {
        console.error(msg);
      }
      warned = true;
    }
    return fn.apply(this, arguments);
  }

  return deprecated;
};


var debugs = {};
var debugEnvRegex = /^$/;

if (typeof process !== 'undefined' && process && process.env && process.env.NODE_DEBUG) {
  var debugEnv = process.env.NODE_DEBUG;
  debugEnv = debugEnv.replace(/[|\\{}()[\]^$+?.]/g, '\\$&')
    .replace(/\*/g, '.*')
    .replace(/,/g, '$|^')
    .toUpperCase();
  debugEnvRegex = new RegExp('^' + debugEnv + '$', 'i');
}
exports.debuglog = function(set) {
  set = set.toUpperCase();
  if (!debugs[set]) {
    if (debugEnvRegex.test(set)) {
      var pid = process.pid;
      debugs[set] = function() {
        var msg = exports.format.apply(exports, arguments);
        console.error('%s %d: %s', set, pid, msg);
      };
    } else {
      debugs[set] = function() {};
    }
  }
  return debugs[set];
};


/**
 * Echos the value of a value. Trys to print the value out
 * in the best way possible given the different types.
 *
 * @param {Object} obj The object to print out.
 * @param {Object} opts Optional options object that alters the output.
 */
/* legacy: obj, showHidden, depth, colors*/
function inspect(obj, opts) {
  // default options
  var ctx = {
    seen: [],
    stylize: stylizeNoColor
  };
  // legacy...
  if (arguments.length >= 3) ctx.depth = arguments[2];
  if (arguments.length >= 4) ctx.colors = arguments[3];
  if (isBoolean(opts)) {
    // legacy...
    ctx.showHidden = opts;
  } else if (opts) {
    // got an "options" object
    exports._extend(ctx, opts);
  }
  // set default options
  if (isUndefined(ctx.showHidden)) ctx.showHidden = false;
  if (isUndefined(ctx.depth)) ctx.depth = 2;
  if (isUndefined(ctx.colors)) ctx.colors = false;
  if (isUndefined(ctx.customInspect)) ctx.customInspect = true;
  if (ctx.colors) ctx.stylize = stylizeWithColor;
  return formatValue(ctx, obj, ctx.depth);
}
exports.inspect = inspect;


// http://en.wikipedia.org/wiki/ANSI_escape_code#graphics
inspect.colors = {
  'bold' : [1, 22],
  'italic' : [3, 23],
  'underline' : [4, 24],
  'inverse' : [7, 27],
  'white' : [37, 39],
  'grey' : [90, 39],
  'black' : [30, 39],
  'blue' : [34, 39],
  'cyan' : [36, 39],
  'green' : [32, 39],
  'magenta' : [35, 39],
  'red' : [31, 39],
  'yellow' : [33, 39]
};

// Don't use 'blue' not visible on cmd.exe
inspect.styles = {
  'special': 'cyan',
  'number': 'yellow',
  'boolean': 'yellow',
  'undefined': 'grey',
  'null': 'bold',
  'string': 'green',
  'date': 'magenta',
  // "name": intentionally not styling
  'regexp': 'red'
};


function stylizeWithColor(str, styleType) {
  var style = inspect.styles[styleType];

  if (style) {
    return '\u001b[' + inspect.colors[style][0] + 'm' + str +
           '\u001b[' + inspect.colors[style][1] + 'm';
  } else {
    return str;
  }
}


function stylizeNoColor(str, styleType) {
  return str;
}


function arrayToHash(array) {
  var hash = {};

  array.forEach(function(val, idx) {
    hash[val] = true;
  });

  return hash;
}


function formatValue(ctx, value, recurseTimes) {
  // Provide a hook for user-specified inspect functions.
  // Check that value is an object with an inspect function on it
  if (ctx.customInspect &&
      value &&
      isFunction(value.inspect) &&
      // Filter out the util module, it's inspect function is special
      value.inspect !== exports.inspect &&
      // Also filter out any prototype objects using the circular check.
      !(value.constructor && value.constructor.prototype === value)) {
    var ret = value.inspect(recurseTimes, ctx);
    if (!isString(ret)) {
      ret = formatValue(ctx, ret, recurseTimes);
    }
    return ret;
  }

  // Primitive types cannot have properties
  var primitive = formatPrimitive(ctx, value);
  if (primitive) {
    return primitive;
  }

  // Look up the keys of the object.
  var keys = Object.keys(value);
  var visibleKeys = arrayToHash(keys);

  if (ctx.showHidden) {
    keys = Object.getOwnPropertyNames(value);
  }

  // IE doesn't make error fields non-enumerable
  // http://msdn.microsoft.com/en-us/library/ie/dww52sbt(v=vs.94).aspx
  if (isError(value)
      && (keys.indexOf('message') >= 0 || keys.indexOf('description') >= 0)) {
    return formatError(value);
  }

  // Some type of object without properties can be shortcutted.
  if (keys.length === 0) {
    if (isFunction(value)) {
      var name = value.name ? ': ' + value.name : '';
      return ctx.stylize('[Function' + name + ']', 'special');
    }
    if (isRegExp(value)) {
      return ctx.stylize(RegExp.prototype.toString.call(value), 'regexp');
    }
    if (isDate(value)) {
      return ctx.stylize(Date.prototype.toString.call(value), 'date');
    }
    if (isError(value)) {
      return formatError(value);
    }
  }

  var base = '', array = false, braces = ['{', '}'];

  // Make Array say that they are Array
  if (isArray(value)) {
    array = true;
    braces = ['[', ']'];
  }

  // Make functions say that they are functions
  if (isFunction(value)) {
    var n = value.name ? ': ' + value.name : '';
    base = ' [Function' + n + ']';
  }

  // Make RegExps say that they are RegExps
  if (isRegExp(value)) {
    base = ' ' + RegExp.prototype.toString.call(value);
  }

  // Make dates with properties first say the date
  if (isDate(value)) {
    base = ' ' + Date.prototype.toUTCString.call(value);
  }

  // Make error with message first say the error
  if (isError(value)) {
    base = ' ' + formatError(value);
  }

  if (keys.length === 0 && (!array || value.length == 0)) {
    return braces[0] + base + braces[1];
  }

  if (recurseTimes < 0) {
    if (isRegExp(value)) {
      return ctx.stylize(RegExp.prototype.toString.call(value), 'regexp');
    } else {
      return ctx.stylize('[Object]', 'special');
    }
  }

  ctx.seen.push(value);

  var output;
  if (array) {
    output = formatArray(ctx, value, recurseTimes, visibleKeys, keys);
  } else {
    output = keys.map(function(key) {
      return formatProperty(ctx, value, recurseTimes, visibleKeys, key, array);
    });
  }

  ctx.seen.pop();

  return reduceToSingleString(output, base, braces);
}


function formatPrimitive(ctx, value) {
  if (isUndefined(value))
    return ctx.stylize('undefined', 'undefined');
  if (isString(value)) {
    var simple = '\'' + JSON.stringify(value).replace(/^"|"$/g, '')
                                             .replace(/'/g, "\\'")
                                             .replace(/\\"/g, '"') + '\'';
    return ctx.stylize(simple, 'string');
  }
  if (isNumber(value))
    return ctx.stylize('' + value, 'number');
  if (isBoolean(value))
    return ctx.stylize('' + value, 'boolean');
  // For some reason typeof null is "object", so special case here.
  if (isNull(value))
    return ctx.stylize('null', 'null');
}


function formatError(value) {
  return '[' + Error.prototype.toString.call(value) + ']';
}


function formatArray(ctx, value, recurseTimes, visibleKeys, keys) {
  var output = [];
  for (var i = 0, l = value.length; i < l; ++i) {
    if (hasOwnProperty(value, String(i))) {
      output.push(formatProperty(ctx, value, recurseTimes, visibleKeys,
          String(i), true));
    } else {
      output.push('');
    }
  }
  keys.forEach(function(key) {
    if (!key.match(/^\d+$/)) {
      output.push(formatProperty(ctx, value, recurseTimes, visibleKeys,
          key, true));
    }
  });
  return output;
}


function formatProperty(ctx, value, recurseTimes, visibleKeys, key, array) {
  var name, str, desc;
  desc = Object.getOwnPropertyDescriptor(value, key) || { value: value[key] };
  if (desc.get) {
    if (desc.set) {
      str = ctx.stylize('[Getter/Setter]', 'special');
    } else {
      str = ctx.stylize('[Getter]', 'special');
    }
  } else {
    if (desc.set) {
      str = ctx.stylize('[Setter]', 'special');
    }
  }
  if (!hasOwnProperty(visibleKeys, key)) {
    name = '[' + key + ']';
  }
  if (!str) {
    if (ctx.seen.indexOf(desc.value) < 0) {
      if (isNull(recurseTimes)) {
        str = formatValue(ctx, desc.value, null);
      } else {
        str = formatValue(ctx, desc.value, recurseTimes - 1);
      }
      if (str.indexOf('\n') > -1) {
        if (array) {
          str = str.split('\n').map(function(line) {
            return '  ' + line;
          }).join('\n').slice(2);
        } else {
          str = '\n' + str.split('\n').map(function(line) {
            return '   ' + line;
          }).join('\n');
        }
      }
    } else {
      str = ctx.stylize('[Circular]', 'special');
    }
  }
  if (isUndefined(name)) {
    if (array && key.match(/^\d+$/)) {
      return str;
    }
    name = JSON.stringify('' + key);
    if (name.match(/^"([a-zA-Z_][a-zA-Z_0-9]*)"$/)) {
      name = name.slice(1, -1);
      name = ctx.stylize(name, 'name');
    } else {
      name = name.replace(/'/g, "\\'")
                 .replace(/\\"/g, '"')
                 .replace(/(^"|"$)/g, "'");
      name = ctx.stylize(name, 'string');
    }
  }

  return name + ': ' + str;
}


function reduceToSingleString(output, base, braces) {
  var numLinesEst = 0;
  var length = output.reduce(function(prev, cur) {
    numLinesEst++;
    if (cur.indexOf('\n') >= 0) numLinesEst++;
    return prev + cur.replace(/\u001b\[\d\d?m/g, '').length + 1;
  }, 0);

  if (length > 60) {
    return braces[0] +
           (base === '' ? '' : base + '\n ') +
           ' ' +
           output.join(',\n  ') +
           ' ' +
           braces[1];
  }

  return braces[0] + base + ' ' + output.join(', ') + ' ' + braces[1];
}


// NOTE: These type checking functions intentionally don't use `instanceof`
// because it is fragile and can be easily faked with `Object.create()`.
exports.types = require('./support/types');

function isArray(ar) {
  return Array.isArray(ar);
}
exports.isArray = isArray;

function isBoolean(arg) {
  return typeof arg === 'boolean';
}
exports.isBoolean = isBoolean;

function isNull(arg) {
  return arg === null;
}
exports.isNull = isNull;

function isNullOrUndefined(arg) {
  return arg == null;
}
exports.isNullOrUndefined = isNullOrUndefined;

function isNumber(arg) {
  return typeof arg === 'number';
}
exports.isNumber = isNumber;

function isString(arg) {
  return typeof arg === 'string';
}
exports.isString = isString;

function isSymbol(arg) {
  return typeof arg === 'symbol';
}
exports.isSymbol = isSymbol;

function isUndefined(arg) {
  return arg === void 0;
}
exports.isUndefined = isUndefined;

function isRegExp(re) {
  return isObject(re) && objectToString(re) === '[object RegExp]';
}
exports.isRegExp = isRegExp;
exports.types.isRegExp = isRegExp;

function isObject(arg) {
  return typeof arg === 'object' && arg !== null;
}
exports.isObject = isObject;

function isDate(d) {
  return isObject(d) && objectToString(d) === '[object Date]';
}
exports.isDate = isDate;
exports.types.isDate = isDate;

function isError(e) {
  return isObject(e) &&
      (objectToString(e) === '[object Error]' || e instanceof Error);
}
exports.isError = isError;
exports.types.isNativeError = isError;

function isFunction(arg) {
  return typeof arg === 'function';
}
exports.isFunction = isFunction;

function isPrimitive(arg) {
  return arg === null ||
         typeof arg === 'boolean' ||
         typeof arg === 'number' ||
         typeof arg === 'string' ||
         typeof arg === 'symbol' ||  // ES6 symbol
         typeof arg === 'undefined';
}
exports.isPrimitive = isPrimitive;

exports.isBuffer = require('./support/isBuffer');

function objectToString(o) {
  return Object.prototype.toString.call(o);
}


function pad(n) {
  return n < 10 ? '0' + n.toString(10) : n.toString(10);
}


var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
              'Oct', 'Nov', 'Dec'];

// 26 Feb 16:19:34
function timestamp() {
  var d = new Date();
  var time = [pad(d.getHours()),
              pad(d.getMinutes()),
              pad(d.getSeconds())].join(':');
  return [d.getDate(), months[d.getMonth()], time].join(' ');
}


// log is just a thin wrapper to console.log that prepends a timestamp
exports.log = function() {
  console.log('%s - %s', timestamp(), exports.format.apply(exports, arguments));
};


/**
 * Inherit the prototype methods from one constructor into another.
 *
 * The Function.prototype.inherits from lang.js rewritten as a standalone
 * function (not on Function.prototype). NOTE: If this file is to be loaded
 * during bootstrapping this function needs to be rewritten using some native
 * functions as prototype setup using normal JavaScript does not work as
 * expected during bootstrapping (see mirror.js in r114903).
 *
 * @param {function} ctor Constructor function which needs to inherit the
 *     prototype.
 * @param {function} superCtor Constructor function to inherit prototype from.
 */
exports.inherits = require('inherits');

exports._extend = function(origin, add) {
  // Don't do anything if add isn't an object
  if (!add || !isObject(add)) return origin;

  var keys = Object.keys(add);
  var i = keys.length;
  while (i--) {
    origin[keys[i]] = add[keys[i]];
  }
  return origin;
};

function hasOwnProperty(obj, prop) {
  return Object.prototype.hasOwnProperty.call(obj, prop);
}

var kCustomPromisifiedSymbol = typeof Symbol !== 'undefined' ? Symbol('util.promisify.custom') : undefined;

exports.promisify = function promisify(original) {
  if (typeof original !== 'function')
    throw new TypeError('The "original" argument must be of type Function');

  if (kCustomPromisifiedSymbol && original[kCustomPromisifiedSymbol]) {
    var fn = original[kCustomPromisifiedSymbol];
    if (typeof fn !== 'function') {
      throw new TypeError('The "util.promisify.custom" argument must be of type Function');
    }
    Object.defineProperty(fn, kCustomPromisifiedSymbol, {
      value: fn, enumerable: false, writable: false, configurable: true
    });
    return fn;
  }

  function fn() {
    var promiseResolve, promiseReject;
    var promise = new Promise(function (resolve, reject) {
      promiseResolve = resolve;
      promiseReject = reject;
    });

    var args = [];
    for (var i = 0; i < arguments.length; i++) {
      args.push(arguments[i]);
    }
    args.push(function (err, value) {
      if (err) {
        promiseReject(err);
      } else {
        promiseResolve(value);
      }
    });

    try {
      original.apply(this, args);
    } catch (err) {
      promiseReject(err);
    }

    return promise;
  }

  Object.setPrototypeOf(fn, Object.getPrototypeOf(original));

  if (kCustomPromisifiedSymbol) Object.defineProperty(fn, kCustomPromisifiedSymbol, {
    value: fn, enumerable: false, writable: false, configurable: true
  });
  return Object.defineProperties(
    fn,
    getOwnPropertyDescriptors(original)
  );
}

exports.promisify.custom = kCustomPromisifiedSymbol

function callbackifyOnRejected(reason, cb) {
  // `!reason` guard inspired by bluebird (Ref: https://goo.gl/t5IS6M).
  // Because `null` is a special error value in callbacks which means "no error
  // occurred", we error-wrap so the callback consumer can distinguish between
  // "the promise rejected with null" or "the promise fulfilled with undefined".
  if (!reason) {
    var newReason = new Error('Promise was rejected with a falsy value');
    newReason.reason = reason;
    reason = newReason;
  }
  return cb(reason);
}

function callbackify(original) {
  if (typeof original !== 'function') {
    throw new TypeError('The "original" argument must be of type Function');
  }

  // We DO NOT return the promise as it gives the user a false sense that
  // the promise is actually somehow related to the callback's execution
  // and that the callback throwing will reject the promise.
  function callbackified() {
    var args = [];
    for (var i = 0; i < arguments.length; i++) {
      args.push(arguments[i]);
    }

    var maybeCb = args.pop();
    if (typeof maybeCb !== 'function') {
      throw new TypeError('The last argument must be of type Function');
    }
    var self = this;
    var cb = function() {
      return maybeCb.apply(self, arguments);
    };
    // In true node style we process the callback on `nextTick` with all the
    // implications (stack, `uncaughtException`, `async_hooks`)
    original.apply(this, args)
      .then(function(ret) { process.nextTick(cb.bind(null, null, ret)) },
            function(rej) { process.nextTick(callbackifyOnRejected.bind(null, rej, cb)) });
  }

  Object.setPrototypeOf(callbackified, Object.getPrototypeOf(original));
  Object.defineProperties(callbackified,
                          getOwnPropertyDescriptors(original));
  return callbackified;
}
exports.callbackify = callbackify;

}).call(this)}).call(this,require('_process'))
},{"./support/isBuffer":56,"./support/types":57,"_process":2,"inherits":38}],59:[function(require,module,exports){
(function (global){(function (){
'use strict';

var forEach = require('for-each');
var availableTypedArrays = require('available-typed-arrays');
var callBind = require('call-bind');
var callBound = require('call-bound');
var gOPD = require('gopd');
var getProto = require('get-proto');

var $toString = callBound('Object.prototype.toString');
var hasToStringTag = require('has-tostringtag/shams')();

var g = typeof globalThis === 'undefined' ? global : globalThis;
var typedArrays = availableTypedArrays();

var $slice = callBound('String.prototype.slice');

/** @import { BoundSet, BoundSlice, Cache, Getter } from './types' */
/** @import { TypedArrayName } from '.' */

/** @type {<T = unknown>(array: readonly T[], value: unknown) => number} */
var $indexOf = callBound('Array.prototype.indexOf', true) || function indexOf(array, value) {
	for (var i = 0; i < array.length; i += 1) {
		if (array[i] === value) {
			return i;
		}
	}
	return -1;
};

/** @type {Cache} */
var cache = { __proto__: null };
if (hasToStringTag && gOPD && getProto) {
	forEach(typedArrays, function (typedArray) {
		var arr = new g[typedArray]();
		if (Symbol.toStringTag in arr && getProto) {
			var proto = getProto(arr);
			// @ts-expect-error TS won't narrow inside a closure
			var descriptor = gOPD(proto, Symbol.toStringTag);
			if (!descriptor && proto) {
				var superProto = getProto(proto);
				// @ts-expect-error TS won't narrow inside a closure
				descriptor = gOPD(superProto, Symbol.toStringTag);
			}
			if (descriptor && descriptor.get) {
				var bound = callBind(descriptor.get);
				cache[
					/** @type {`$${TypedArrayName}`} */
					('$' + typedArray)
				] = bound;
			}
		}
	});
} else {
	forEach(typedArrays, function (typedArray) {
		var arr = new g[typedArray]();
		var fn = arr.slice || arr.set;
		if (fn) {
			var bound = /** @type {BoundSlice | BoundSet} */ (
				// @ts-expect-error TODO FIXME
				callBind(fn)
			);
			cache[
				/** @type {`$${TypedArrayName}`} */
				('$' + typedArray)
			] = bound;
		}
	});
}

/** @type {(value: object) => false | TypedArrayName} */
function tryTypedArrays(value) {
	/** @type {ReturnType<typeof tryTypedArrays>} */ var found = false;
	forEach(
		/** @type {Record<`$${TypedArrayName}`, Getter>} */ (cache),
		/** @param {Getter} getter @param {`$${TypedArrayName}`} typedArray */
		function (getter, typedArray) {
			if (!found) {
				try {
					// @ts-expect-error a throw is fine here
					if ('$' + getter(value) === typedArray) {
						found = /** @type {TypedArrayName} */ ($slice(typedArray, 1));
					}
				} catch (e) { /**/ }
			}
		}
	);
	return found;
}

/** @type {(value: object) => false | TypedArrayName} */
function trySlices(value) {
	/** @type {ReturnType<typeof trySlices>} */ var found = false;
	forEach(
		/** @type {Record<`$${TypedArrayName}`, Getter>} */(cache),
		/** @param {Getter} getter @param {`$${TypedArrayName}`} name */ function (getter, name) {
			if (!found) {
				try {
					// @ts-expect-error a throw is fine here
					getter(value);
					found = /** @type {TypedArrayName} */ ($slice(name, 1));
				} catch (e) { /**/ }
			}
		}
	);
	return found;
}

/** @type {(tag: unknown) => tag is typeof typedArrays[number]} */
function isTATag(tag) {
	return $indexOf(typedArrays, tag) > -1;
}

/**
 * @type {import('.')}
 * @param {unknown} value
 */
module.exports = function whichTypedArray(value) {
	if (!value || typeof value !== 'object') {
		return false;
	}
	if (!hasToStringTag) {
		var tag = $slice($toString(value), 8, -1);
		if (isTATag(tag)) {
			return tag;
		}
		if (tag !== 'Object') {
			return false;
		}
		// node < 0.6 hits here on real Typed Arrays
		return trySlices(value);
	}
	if (!gOPD) { return null; } // unknown engine
	return tryTypedArrays(value);
};

}).call(this)}).call(this,typeof global !== "undefined" ? global : typeof self !== "undefined" ? self : typeof window !== "undefined" ? window : {})
},{"available-typed-arrays":1,"call-bind":9,"call-bound":10,"for-each":23,"get-proto":30,"gopd":32,"has-tostringtag/shams":36}],60:[function(require,module,exports){
/**
 * Get cache object by `name`.
 *
 * @param {String|Function} name
 * @param {Object} options
 * @return {Object}
 * @api private
 */

var getCache = module.exports = function(name, options){
  if ('function' == typeof name) return new name(options);

  var cache;
  switch (name){
    // Memory and filesystem caches are intentionally unavailable offline.
    default:
      cache = require('./null');
  }
  return new cache(options);
};

},{"./null":61}],61:[function(require,module,exports){
/**
 * Module dependencies.
 */

module.exports = class NullCache {

  /**
   * Set cache item with given `key` to `value`.
   *
   * @param {String} key
   * @param {Object} value
   * @api private
   */

  set(key, value) { };

  /**
   * Get cache item with given `key`.
   *
   * @param {String} key
   * @return {Object}
   * @api private
   */

  get(key) { };

  /**
   * Check if cache has given `key`.
   *
   * @param {String} key
   * @return {Boolean}
   * @api private
   */

  has(key) {
    return false;
  };

  /**
   * Generate key for the source `str` with `options`.
   *
   * @param {String} str
   * @param {Object} options
   * @return {String}
   * @api private
   */

  key(str, options) {
    return '';
  };
}
},{}],62:[function(require,module,exports){

/*!
 * Stylus - colors
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

module.exports = {
    aliceblue: [240, 248, 255, 1]
  , antiquewhite: [250, 235, 215, 1]
  , aqua: [0, 255, 255, 1]
  , aquamarine: [127, 255, 212, 1]
  , azure: [240, 255, 255, 1]
  , beige: [245, 245, 220, 1]
  , bisque: [255, 228, 196, 1]
  , black: [0, 0, 0, 1]
  , blanchedalmond: [255, 235, 205, 1]
  , blue: [0, 0, 255, 1]
  , blueviolet: [138, 43, 226, 1]
  , brown: [165, 42, 42, 1]
  , burlywood: [222, 184, 135, 1]
  , cadetblue: [95, 158, 160, 1]
  , chartreuse: [127, 255, 0, 1]
  , chocolate: [210, 105, 30, 1]
  , coral: [255, 127, 80, 1]
  , cornflowerblue: [100, 149, 237, 1]
  , cornsilk: [255, 248, 220, 1]
  , crimson: [220, 20, 60, 1]
  , cyan: [0, 255, 255, 1]
  , darkblue: [0, 0, 139, 1]
  , darkcyan: [0, 139, 139, 1]
  , darkgoldenrod: [184, 134, 11, 1]
  , darkgray: [169, 169, 169, 1]
  , darkgreen: [0, 100, 0, 1]
  , darkgrey: [169, 169, 169, 1]
  , darkkhaki: [189, 183, 107, 1]
  , darkmagenta: [139, 0, 139, 1]
  , darkolivegreen: [85, 107, 47, 1]
  , darkorange: [255, 140, 0, 1]
  , darkorchid: [153, 50, 204, 1]
  , darkred: [139, 0, 0, 1]
  , darksalmon: [233, 150, 122, 1]
  , darkseagreen: [143, 188, 143, 1]
  , darkslateblue: [72, 61, 139, 1]
  , darkslategray: [47, 79, 79, 1]
  , darkslategrey: [47, 79, 79, 1]
  , darkturquoise: [0, 206, 209, 1]
  , darkviolet: [148, 0, 211, 1]
  , deeppink: [255, 20, 147, 1]
  , deepskyblue: [0, 191, 255, 1]
  , dimgray: [105, 105, 105, 1]
  , dimgrey: [105, 105, 105, 1]
  , dodgerblue: [30, 144, 255, 1]
  , firebrick: [178, 34, 34, 1]
  , floralwhite: [255, 250, 240, 1]
  , forestgreen: [34, 139, 34, 1]
  , fuchsia: [255, 0, 255, 1]
  , gainsboro: [220, 220, 220, 1]
  , ghostwhite: [248, 248, 255, 1]
  , gold: [255, 215, 0, 1]
  , goldenrod: [218, 165, 32, 1]
  , gray: [128, 128, 128, 1]
  , green: [0, 128, 0, 1]
  , greenyellow: [173, 255, 47, 1]
  , grey: [128, 128, 128, 1]
  , honeydew: [240, 255, 240, 1]
  , hotpink: [255, 105, 180, 1]
  , indianred: [205, 92, 92, 1]
  , indigo: [75, 0, 130, 1]
  , ivory: [255, 255, 240, 1]
  , khaki: [240, 230, 140, 1]
  , lavender: [230, 230, 250, 1]
  , lavenderblush: [255, 240, 245, 1]
  , lawngreen: [124, 252, 0, 1]
  , lemonchiffon: [255, 250, 205, 1]
  , lightblue: [173, 216, 230, 1]
  , lightcoral: [240, 128, 128, 1]
  , lightcyan: [224, 255, 255, 1]
  , lightgoldenrodyellow: [250, 250, 210, 1]
  , lightgray: [211, 211, 211, 1]
  , lightgreen: [144, 238, 144, 1]
  , lightgrey: [211, 211, 211, 1]
  , lightpink: [255, 182, 193, 1]
  , lightsalmon: [255, 160, 122, 1]
  , lightseagreen: [32, 178, 170, 1]
  , lightskyblue: [135, 206, 250, 1]
  , lightslategray: [119, 136, 153, 1]
  , lightslategrey: [119, 136, 153, 1]
  , lightsteelblue: [176, 196, 222, 1]
  , lightyellow: [255, 255, 224, 1]
  , lime: [0, 255, 0, 1]
  , limegreen: [50, 205, 50, 1]
  , linen: [250, 240, 230, 1]
  , magenta: [255, 0, 255, 1]
  , maroon: [128, 0, 0, 1]
  , mediumaquamarine: [102, 205, 170, 1]
  , mediumblue: [0, 0, 205, 1]
  , mediumorchid: [186, 85, 211, 1]
  , mediumpurple: [147, 112, 219, 1]
  , mediumseagreen: [60, 179, 113, 1]
  , mediumslateblue: [123, 104, 238, 1]
  , mediumspringgreen: [0, 250, 154, 1]
  , mediumturquoise: [72, 209, 204, 1]
  , mediumvioletred: [199, 21, 133, 1]
  , midnightblue: [25, 25, 112, 1]
  , mintcream: [245, 255, 250, 1]
  , mistyrose: [255, 228, 225, 1]
  , moccasin: [255, 228, 181, 1]
  , navajowhite: [255, 222, 173, 1]
  , navy: [0, 0, 128, 1]
  , oldlace: [253, 245, 230, 1]
  , olive: [128, 128, 0, 1]
  , olivedrab: [107, 142, 35, 1]
  , orange: [255, 165, 0, 1]
  , orangered: [255, 69, 0, 1]
  , orchid: [218, 112, 214, 1]
  , palegoldenrod: [238, 232, 170, 1]
  , palegreen: [152, 251, 152, 1]
  , paleturquoise: [175, 238, 238, 1]
  , palevioletred: [219, 112, 147, 1]
  , papayawhip: [255, 239, 213, 1]
  , peachpuff: [255, 218, 185, 1]
  , peru: [205, 133, 63, 1]
  , pink: [255, 192, 203, 1]
  , plum: [221, 160, 221, 1]
  , powderblue: [176, 224, 230, 1]
  , purple: [128, 0, 128, 1]
  , red: [255, 0, 0, 1]
  , rosybrown: [188, 143, 143, 1]
  , royalblue: [65, 105, 225, 1]
  , saddlebrown: [139, 69, 19, 1]
  , salmon: [250, 128, 114, 1]
  , sandybrown: [244, 164, 96, 1]
  , seagreen: [46, 139, 87, 1]
  , seashell: [255, 245, 238, 1]
  , sienna: [160, 82, 45, 1]
  , silver: [192, 192, 192, 1]
  , skyblue: [135, 206, 235, 1]
  , slateblue: [106, 90, 205, 1]
  , slategray: [112, 128, 144, 1]
  , slategrey: [112, 128, 144, 1]
  , snow: [255, 250, 250, 1]
  , springgreen: [0, 255, 127, 1]
  , steelblue: [70, 130, 180, 1]
  , tan: [210, 180, 140, 1]
  , teal: [0, 128, 128, 1]
  , thistle: [216, 191, 216, 1]
  , tomato: [255, 99, 71, 1]
  , transparent: [0, 0, 0, 0]
  , turquoise: [64, 224, 208, 1]
  , violet: [238, 130, 238, 1]
  , wheat: [245, 222, 179, 1]
  , white: [255, 255, 255, 1]
  , whitesmoke: [245, 245, 245, 1]
  , yellow: [255, 255, 0, 1]
  , yellowgreen: [154, 205, 50, 1]
  , rebeccapurple: [102, 51, 153, 1]
};

},{}],63:[function(require,module,exports){

/*!
 * Stylus - errors
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Initialize a new `ParseError` with the given `msg`.
 *
 * @param {String} msg
 * @api private
 */

class ParseError extends Error {
  constructor(msg) {
    super();
    this.name = 'ParseError';
    this.message = msg;
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, ParseError);
    }
  }
}

/**
 * Initialize a new `SyntaxError` with the given `msg`.
 *
 * @param {String} msg
 * @api private
 */

class SyntaxError extends Error {
  constructor(msg) {
    super();
    this.name = 'SyntaxError';
    this.message = msg;
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, ParseError);
    }
  }
}

/**
 * Expose constructors.
 */

exports.ParseError = ParseError;
exports.SyntaxError = SyntaxError;

},{}],64:[function(require,module,exports){
var nodes = require('../nodes')
  , convert = require('./convert-angle')
  , asin    = require('./asin');

/**
 * Return the arccosine of the given `value`.
 *
 * @param {Double} trigValue
 * @param {Unit} output 
 * @return {Unit}
 * @api public
 */
module.exports = function acos(trigValue, output) {
	var output = typeof output !== 'undefined' ? output : 'deg';
	var convertedValue = convert(Math.PI / 2, output) - asin(trigValue, output).val;
	var m = Math.pow(10, 9);
	convertedValue = Math.round(convertedValue * m) / m;
  return new nodes.Unit(convertedValue, output);
};

},{"../nodes":148,"./asin":68,"./convert-angle":77}],65:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Add property `name` with the given `expr`
 * to the mixin-able block.
 *
 * @param {String|Ident|Literal} name
 * @param {Expression} expr
 * @return {Property}
 * @api public
 */

(module.exports = function addProperty(name, expr){
  utils.assertType(name, 'expression', 'name');
  name = utils.unwrap(name).first;
  utils.assertString(name, 'name');
  utils.assertType(expr, 'expression', 'expr');
  var prop = new nodes.Property([name], expr);
  var block = this.closestBlock;

  var len = block.nodes.length
    , head = block.nodes.slice(0, block.index)
    , tail = block.nodes.slice(block.index++, len);
  head.push(prop);
  block.nodes = head.concat(tail);

  return prop;
}).raw = true;

},{"../nodes":148,"../utils":178}],66:[function(require,module,exports){
var utils = require('../utils');

/**
 * Adjust HSL `color` `prop` by `amount`.
 *
 * @param {RGBA|HSLA} color
 * @param {String} prop
 * @param {Unit} amount
 * @return {RGBA}
 * @api private
 */

function adjust(color, prop, amount){
  utils.assertColor(color, 'color');
  utils.assertString(prop, 'prop');
  utils.assertType(amount, 'unit', 'amount');
  var hsl = color.hsla.clone();
  prop = { hue: 'h', saturation: 's', lightness: 'l' }[prop.string];
  if (!prop) throw new Error('invalid adjustment property');
  var val = amount.val;
  if ('%' == amount.type){
    val = 'l' == prop && val > 0
      ? (100 - hsl[prop]) * val / 100
      : hsl[prop] * (val / 100);
  }
  hsl[prop] += val;
  return hsl.rgba;
};
adjust.params = ['color', 'prop', 'amount'];
module.exports = adjust;

},{"../utils":178}],67:[function(require,module,exports){
var nodes = require('../nodes')
  , rgba = require('./rgba');

/**
 * Return the alpha component of the given `color`,
 * or set the alpha component to the optional second `value` argument.
 *
 * Examples:
 *
 *    alpha(#fff)
 *    // => 1
 *
 *    alpha(rgba(0,0,0,0.3))
 *    // => 0.3
 *
 *    alpha(#fff, 0.5)
 *    // => rgba(255,255,255,0.5)
 *
 * @param {RGBA|HSLA} color
 * @param {Unit} [value]
 * @return {Unit|RGBA}
 * @api public
 */

function alpha(color, value){
  color = color.rgba;
  if (value) {
    return rgba(
      new nodes.Unit(color.r),
      new nodes.Unit(color.g),
      new nodes.Unit(color.b),
      value
    );
  }
  return new nodes.Unit(color.a, '');
};
alpha.params = ['color', 'value'];
module.exports = alpha;

},{"../nodes":148,"./rgba":110}],68:[function(require,module,exports){
var nodes = require('../nodes')
  , convert = require('./convert-angle');

/**
 * Return the arcsine of the given `value`.
 *
 * @param {Double} trigValue
 * @param {Unit} output 
 * @return {Unit}
 * @api public
 */

module.exports = function atan(trigValue, output) {
	var output = typeof output !== 'undefined' ? output : 'deg';
  var m = Math.pow(10, 9);
	var value = Math.asin(trigValue) ;
	var convertedValue = convert(value, output);
	convertedValue = Math.round(convertedValue * m) / m;
  return new nodes.Unit(convertedValue, output);
};

},{"../nodes":148,"./convert-angle":77}],69:[function(require,module,exports){
var nodes = require('../nodes')
  , convert = require('./convert-angle');

/**
 * Return the arctangent of the given `value`.
 *
 * @param {Double} trigValue
 * @param {Unit} output 
 * @return {Unit}
 * @api public
 */

module.exports = function atan(trigValue, output) {
	var output = typeof output !== 'undefined' ? output : 'deg';
	var value = Math.atan(trigValue) ;
	var m = Math.pow(10, 9);
	var convertedValue = convert(value, output);
	convertedValue = Math.round(convertedValue * m) / m;
  return new nodes.Unit(convertedValue, output);
};

},{"../nodes":148,"./convert-angle":77}],70:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Return a `Literal` `num` converted to the provided `base`, padded to `width`
 * with zeroes (default width is 2)
 *
 * @param {Number} num
 * @param {Number} base
 * @param {Number} width
 * @return {Literal}
 * @api public
 */

(module.exports = function(num, base, width) {
  utils.assertPresent(num, 'number');
  utils.assertPresent(base, 'base');
  num = utils.unwrap(num).nodes[0].val;
  base = utils.unwrap(base).nodes[0].val;
  width = (width && utils.unwrap(width).nodes[0].val) || 2;
  var result = Number(num).toString(base);
  while (result.length < width) {
    result = '0' + result;
  }
  return new nodes.Literal(result);
}).raw = true;

},{"../nodes":148,"../utils":178}],71:[function(require,module,exports){
var utils = require('../utils')
  , path = require('path');

/**
 * Return the basename of `path`.
 *
 * @param {String} path
 * @return {String}
 * @api public
 */

function basename(p, ext){
  utils.assertString(p, 'path');
  return path.basename(p.val, ext && ext.val);
};
basename.params = ['p', 'ext'];
module.exports = basename;

},{"../utils":178,"path":52}],72:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Blend the `top` color over the `bottom`
 *
 * Examples:
 *
 *     blend(rgba(#FFF, 0.5), #000)
 *     // => #808080
 * 
 *     blend(rgba(#FFDE00,.42), #19C261)
 *     // => #7ace38
 * 
 *     blend(rgba(lime, 0.5), rgba(red, 0.25))
 *     // => rgba(128,128,0,0.625)
 *
 * @param {RGBA|HSLA} top
 * @param {RGBA|HSLA} [bottom=#fff]
 * @return {RGBA}
 * @api public
 */

function blend(top, bottom){
  // TODO: different blend modes like overlay etc.
  utils.assertColor(top);
  top = top.rgba;
  bottom = bottom || new nodes.RGBA(255, 255, 255, 1);
  utils.assertColor(bottom);
  bottom = bottom.rgba;

  return new nodes.RGBA(
    top.r * top.a + bottom.r * (1 - top.a),
    top.g * top.a + bottom.g * (1 - top.a),
    top.b * top.a + bottom.b * (1 - top.a),
    top.a + bottom.a - top.a * bottom.a);
};
blend.params = ['top', 'bottom'];
module.exports = blend;

},{"../nodes":148,"../utils":178}],73:[function(require,module,exports){
var nodes = require('../nodes')
  , rgba = require('./rgba');

/**
 * Return the blue component of the given `color`,
 * or set the blue component to the optional second `value` argument.
 *
 * Examples:
 *
 *    blue(#00c)
 *    // => 204
 *
 *    blue(#000, 255)
 *    // => #00f
 *
 * @param {RGBA|HSLA} color
 * @param {Unit} [value]
 * @return {Unit|RGBA}
 * @api public
 */

function blue(color, value){
  color = color.rgba;
  if (value) {
    return rgba(
      new nodes.Unit(color.r),
      new nodes.Unit(color.g),
      value,
      new nodes.Unit(color.a)
    );
  }
  return new nodes.Unit(color.b, '');
};
blue.params = ['color', 'value'];
module.exports = blue;

},{"../nodes":148,"./rgba":110}],74:[function(require,module,exports){
var utils = require('../utils');

/**
 * Return a clone of the given `expr`.
 *
 * @param {Expression} expr
 * @return {Node}
 * @api public
 */

(module.exports = function clone(expr){
  utils.assertPresent(expr, 'expr');
  return expr.clone();
}).raw = true;

},{"../utils":178}],75:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Color component name map.
 */

var componentMap = {
    red: 'r'
  , green: 'g'
  , blue: 'b'
  , alpha: 'a'
  , hue: 'h'
  , saturation: 's'
  , lightness: 'l'
};

/**
 * Color component unit type map.
 */

var unitMap = {
    hue: 'deg'
  , saturation: '%'
  , lightness: '%'
};

/**
 * Color type map.
 */

var typeMap = {
    red: 'rgba'
  , blue: 'rgba'
  , green: 'rgba'
  , alpha: 'rgba'
  , hue: 'hsla'
  , saturation: 'hsla'
  , lightness: 'hsla'
};

/**
 * Return component `name` for the given `color`.
 *
 * @param {RGBA|HSLA} color
 * @param {String} name
 * @return {Unit}
 * @api public
 */

function component(color, name) {
  utils.assertColor(color, 'color');
  utils.assertString(name, 'name');
  var name = name.string
    , unit = unitMap[name]
    , type = typeMap[name]
    , name = componentMap[name];
  if (!name) throw new Error('invalid color component "' + name + '"');
  return new nodes.Unit(color[type][name], unit);
};
component.params = ['color', 'name'];
module.exports = component;

},{"../nodes":148,"../utils":178}],76:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes')
  , blend = require('./blend')
  , luminosity = require('./luminosity');

/**
 * Returns the contrast ratio object between `top` and `bottom` colors,
 * based on http://leaverou.github.io/contrast-ratio/
 * and https://github.com/LeaVerou/contrast-ratio/blob/gh-pages/color.js#L108
 *
 * Examples:
 *
 *     contrast(#000, #fff).ratio
 *     => 21
 *
 *     contrast(#000, rgba(#FFF, 0.5))
 *     => { "ratio": "13.15;", "error": "7.85", "min": "5.3", "max": "21" }
 *
 * @param {RGBA|HSLA} top
 * @param {RGBA|HSLA} [bottom=#fff]
 * @return {Object}
 * @api public
 */

function contrast(top, bottom){
  if ('rgba' != top.nodeName && 'hsla' != top.nodeName) {
    return new nodes.Literal('contrast(' + (top.isNull ? '' : top.toString()) + ')');
  }
  var result = new nodes.Object();
  top = top.rgba;
  bottom = bottom || new nodes.RGBA(255, 255, 255, 1);
  utils.assertColor(bottom);
  bottom = bottom.rgba;
  function contrast(top, bottom) {
    if (1 > top.a) {
      top = blend(top, bottom);
    }
    var l1 = luminosity(bottom).val + 0.05
      , l2 = luminosity(top).val + 0.05
      , ratio = l1 / l2;

    if (l2 > l1) {
      ratio = 1 / ratio;
    }
    return Math.round(ratio * 10) / 10;
  }

  if (1 <= bottom.a) {
    var resultRatio = new nodes.Unit(contrast(top, bottom));
    result.set('ratio', resultRatio);
    result.set('error', new nodes.Unit(0));
    result.set('min', resultRatio);
    result.set('max', resultRatio);
  } else {
    var onBlack = contrast(top, blend(bottom, new nodes.RGBA(0, 0, 0, 1)))
      , onWhite = contrast(top, blend(bottom, new nodes.RGBA(255, 255, 255, 1)))
      , max = Math.max(onBlack, onWhite);
    function processChannel(topChannel, bottomChannel) {
      return Math.min(Math.max(0, (topChannel - bottomChannel * bottom.a) / (1 - bottom.a)), 255);
    }
    var closest = new nodes.RGBA(
      processChannel(top.r, bottom.r),
      processChannel(top.g, bottom.g),
      processChannel(top.b, bottom.b),
      1
    );
    var min = contrast(top, blend(bottom, closest));

    result.set('ratio', new nodes.Unit(Math.round((min + max) * 50) / 100));
    result.set('error', new nodes.Unit(Math.round((max - min) * 50) / 100));
    result.set('min', new nodes.Unit(min));
    result.set('max', new nodes.Unit(max));
  }
  return result;
}
contrast.params = ['top', 'bottom'];
module.exports = contrast;

},{"../nodes":148,"../utils":178,"./blend":72,"./luminosity":93}],77:[function(require,module,exports){

/**
 * Convert given value's base into the parameter unitName
 *
 * @param {Double} value
 * @param {String} unitName
 * @return {Double}
 * @api private
 */

module.exports = function convertAngle(value, unitName) {
	var factors = {
		"rad" : 1,
		"deg" : 180 / Math.PI,
		"turn": 0.5 / Math.PI,
		"grad": 200 / Math.PI
	}
	return value * factors[unitName];
}

},{}],78:[function(require,module,exports){
var utils = require('../utils');

/**
 * Like `unquote` but tries to convert
 * the given `str` to a Stylus node.
 *
 * @param {String} str
 * @return {Node}
 * @api public
 */

function convert(str){
  utils.assertString(str, 'str');
  return utils.parseString(str.string);
};
convert.params = ['str'];
module.exports = convert;

},{"../utils":178}],79:[function(require,module,exports){
var nodes = require('../nodes');

/**
 * Returns the @media string for the current block
 *
 * @return {String}
 * @api public
 */

module.exports = function currentMedia(){
  var self = this;
  return new nodes.String(lookForMedia(this.closestBlock.node) || '');

  function lookForMedia(node){
    if ('media' == node.nodeName) {
      node.val = self.visit(node.val);
      return node.toString();
    } else if (node.block.parent.node) {
      return lookForMedia(node.block.parent.node);
    }
  }
};

},{"../nodes":148}],80:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Set a variable `name` on current scope.
 *
 * @param {String} name
 * @param {Expression} expr
 * @param {Boolean} [global]
 * @api public
 */

function define(name, expr, global){
  utils.assertType(name, 'string', 'name');
  expr = utils.unwrap(expr);
  var scope = this.currentScope;
  if (global && global.toBoolean().isTrue) {
    scope = this.global.scope;
  }
  var node = new nodes.Ident(name.val, expr);
  scope.add(node);
  return nodes.null;
};
define.params = ['name', 'expr', 'global'];
module.exports = define;

},{"../nodes":148,"../utils":178}],81:[function(require,module,exports){
var utils = require('../utils')
  , path = require('path');

/**
 * Return the dirname of `path`.
 *
 * @param {String} path
 * @return {String}
 * @api public
 */

function dirname(p){
  utils.assertString(p, 'path');
  return path.dirname(p.val).replace(/\\/g, '/');
};
dirname.params = ['p'];
module.exports = dirname;

},{"../utils":178,"path":52}],82:[function(require,module,exports){
var utils = require('../utils');

/**
 * Throw an error with the given `msg`.
 *
 * @param {String} msg
 * @api public
 */

function error(msg){
  utils.assertType(msg, 'string', 'msg');
  var err = new Error(msg.val);
  err.fromStylus = true;
  throw err;
};
error.params = ['msg'];
module.exports = error;

},{"../utils":178}],83:[function(require,module,exports){
var utils = require('../utils')
  , path = require('path');

/**
 * Return the extname of `path`.
 *
 * @param {String} path
 * @return {String}
 * @api public
 */

function extname(p){
  utils.assertString(p, 'path');
  return path.extname(p.val);
};
extname.params = ['p'];
module.exports = extname;

},{"../utils":178,"path":52}],84:[function(require,module,exports){
var nodes = require('../nodes')
  , rgba = require('./rgba');

/**
 * Return the green component of the given `color`,
 * or set the green component to the optional second `value` argument.
 *
 * Examples:
 *
 *    green(#0c0)
 *    // => 204
 *
 *    green(#000, 255)
 *    // => #0f0
 *
 * @param {RGBA|HSLA} color
 * @param {Unit} [value]
 * @return {Unit|RGBA}
 * @api public
 */

function green(color, value){
  color = color.rgba;
  if (value) {
    return rgba(
      new nodes.Unit(color.r),
      value,
      new nodes.Unit(color.b),
      new nodes.Unit(color.a)
    );
  }
  return new nodes.Unit(color.g, '');
};
green.params = ['color', 'value'];
module.exports = green;

},{"../nodes":148,"./rgba":110}],85:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes')
  , hsla = require('./hsla');

/**
 * Convert the given `color` to an `HSLA` node,
 * or h,s,l component values.
 *
 * Examples:
 *
 *    hsl(10, 50, 30)
 *    // => HSLA
 *
 *    hsl(#ffcc00)
 *    // => HSLA
 *
 * @param {Unit|HSLA|RGBA} hue
 * @param {Unit} saturation
 * @param {Unit} lightness
 * @return {HSLA}
 * @api public
 */

function hsl(hue, saturation, lightness){
  if (1 == arguments.length) {
    utils.assertColor(hue, 'color');
    return hue.hsla;
  } else {
    return hsla(
        hue
      , saturation
      , lightness
      , new nodes.Unit(1));
  }
};
hsl.params = ['hue', 'saturation', 'lightness'];
module.exports = hsl;

},{"../nodes":148,"../utils":178,"./hsla":86}],86:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Convert the given `color` to an `HSLA` node,
 * or h,s,l,a component values.
 *
 * Examples:
 *
 *    hsla(10deg, 50%, 30%, 0.5)
 *    // => HSLA
 *
 *    hsla(#ffcc00)
 *    // => HSLA
 *
 * @param {RGBA|HSLA|Unit} hue
 * @param {Unit} saturation
 * @param {Unit} lightness
 * @param {Unit} alpha
 * @return {HSLA}
 * @api public
 */

function hsla(hue, saturation, lightness, alpha){
  switch (arguments.length) {
    case 1:
      utils.assertColor(hue);
      return hue.hsla;
    case 2:
      utils.assertColor(hue);
      var color = hue.hsla;
      utils.assertType(saturation, 'unit', 'alpha');
      var alpha = saturation.clone();
      if ('%' == alpha.type) alpha.val /= 100;
      return new nodes.HSLA(
          color.h
        , color.s
        , color.l
        , alpha.val);
    default:
      utils.assertType(hue, 'unit', 'hue');
      utils.assertType(saturation, 'unit', 'saturation');
      utils.assertType(lightness, 'unit', 'lightness');
      utils.assertType(alpha, 'unit', 'alpha');
      var alpha = alpha.clone();
      if (alpha && '%' == alpha.type) alpha.val /= 100;
      return new nodes.HSLA(
          hue.val
        , saturation.val
        , lightness.val
        , alpha.val);
  }
};
hsla.params = ['hue', 'saturation', 'lightness', 'alpha'];
module.exports = hsla;

},{"../nodes":148,"../utils":178}],87:[function(require,module,exports){
var nodes = require('../nodes')
  , hsla = require('./hsla')
  , component = require('./component');

/**
 * Return the hue component of the given `color`,
 * or set the hue component to the optional second `value` argument.
 *
 * Examples:
 *
 *    hue(#00c)
 *    // => 240deg
 *
 *    hue(#00c, 90deg)
 *    // => #6c0
 *
 * @param {RGBA|HSLA} color
 * @param {Unit} [value]
 * @return {Unit|RGBA}
 * @api public
 */

function hue(color, value){
  if (value) {
    var hslaColor = color.hsla;
    return hsla(
      value,
      new nodes.Unit(hslaColor.s),
      new nodes.Unit(hslaColor.l),
      new nodes.Unit(hslaColor.a)
    )
  }
  return component(color, new nodes.String('hue'));
};
hue.params = ['color', 'value'];
module.exports = hue;

},{"../nodes":148,"./component":75,"./hsla":86}],88:[function(require,module,exports){

/*!
 * Stylus - Evaluator - built-in functions
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

exports['add-property'] = require('./add-property');
exports.adjust = require('./adjust');
exports.alpha = require('./alpha');
exports['base-convert'] = require('./base-convert');
exports.basename = require('./basename');
exports.blend = require('./blend');
exports.blue = require('./blue');
exports.clone = require('./clone');
exports.component = require('./component');
exports.contrast = require('./contrast');
exports.convert = require('./convert');
exports['current-media'] = require('./current-media');
exports.define = require('./define');
exports.dirname = require('./dirname');
exports.error = require('./error');
exports.extname = require('./extname');
exports.green = require('./green');
exports.hsl = require('./hsl');
exports.hsla = require('./hsla');
exports.hue = require('./hue');
exports.length = require('./length');
exports.lightness = require('./lightness');
exports['list-separator'] = require('./list-separator');
exports.lookup = require('./lookup');
exports.luminosity = require('./luminosity');
exports.match = require('./match');
exports.math = require('./math');
exports.merge = exports.extend = require('./merge');
exports.operate = require('./operate');
exports['opposite-position'] = require('./opposite-position');
exports.p = require('./p');
exports.pathjoin = require('./pathjoin');
exports.pop = require('./pop');
exports.push = exports.append = require('./push');
exports.range = require('./range');
exports.red = require('./red');
exports.remove = require('./remove');
exports.replace = require('./replace');
exports.rgb = require('./rgb');
exports.atan = require('./atan');
exports.asin = require('./asin');
exports.acos = require('./acos');
exports.rgba = require('./rgba');
exports.s = require('./s');
exports.saturation = require('./saturation');
exports['selector-exists'] = require('./selector-exists');
exports.selector = require('./selector');
exports.selectors = require('./selectors');
exports.shift = require('./shift');
exports.split = require('./split');
exports.substr = require('./substr');
exports.slice = require('./slice');
exports.tan = require('./tan');
exports.trace = require('./trace');
exports.transparentify = require('./transparentify');
exports.type = exports.typeof = exports['type-of'] = require('./type');
exports.unit = require('./unit');
exports.unquote = require('./unquote');
exports.unshift = exports.prepend = require('./unshift');
exports.warn = require('./warn');
exports['-math-prop'] = require('./math-prop');
exports['-prefix-classes'] = require('./prefix-classes');

},{"./acos":64,"./add-property":65,"./adjust":66,"./alpha":67,"./asin":68,"./atan":69,"./base-convert":70,"./basename":71,"./blend":72,"./blue":73,"./clone":74,"./component":75,"./contrast":76,"./convert":78,"./current-media":79,"./define":80,"./dirname":81,"./error":82,"./extname":83,"./green":84,"./hsl":85,"./hsla":86,"./hue":87,"./length":89,"./lightness":90,"./list-separator":91,"./lookup":92,"./luminosity":93,"./match":94,"./math":96,"./math-prop":95,"./merge":97,"./operate":98,"./opposite-position":99,"./p":100,"./pathjoin":101,"./pop":102,"./prefix-classes":103,"./push":104,"./range":105,"./red":106,"./remove":107,"./replace":108,"./rgb":109,"./rgba":110,"./s":111,"./saturation":112,"./selector":114,"./selector-exists":113,"./selectors":115,"./shift":116,"./slice":117,"./split":118,"./substr":119,"./tan":120,"./trace":121,"./transparentify":122,"./type":123,"./unit":124,"./unquote":125,"./unshift":126,"./warn":127}],89:[function(require,module,exports){
var utils = require('../utils');

/**
 * Return length of the given `expr`.
 *
 * @param {Expression} expr
 * @return {Unit}
 * @api public
 */

(module.exports = function length(expr){
  if (expr) {
    if (expr.nodes) {
      var nodes = utils.unwrap(expr).nodes;
      if (1 == nodes.length && 'object' == nodes[0].nodeName) {
        return nodes[0].length;
      } else if (1 == nodes.length && 'string' == nodes[0].nodeName) {
        return nodes[0].val.length;
      } else {
        return nodes.length;
      }
    } else {
      return 1;
    }
  }
  return 0;
}).raw = true;

},{"../utils":178}],90:[function(require,module,exports){
var nodes = require('../nodes')
  , hsla = require('./hsla')
  , component = require('./component');

/**
 * Return the lightness component of the given `color`,
 * or set the lightness component to the optional second `value` argument.
 *
 * Examples:
 *
 *    lightness(#00c)
 *    // => 100%
 *
 *    lightness(#00c, 80%)
 *    // => #99f
 *
 * @param {RGBA|HSLA} color
 * @param {Unit} [value]
 * @return {Unit|RGBA}
 * @api public
 */

function lightness(color, value){
  if (value) {
    var hslaColor = color.hsla;
    return hsla(
      new nodes.Unit(hslaColor.h),
      new nodes.Unit(hslaColor.s),
      value,
      new nodes.Unit(hslaColor.a)
    )
  }
  return component(color, new nodes.String('lightness'));
};
lightness.params = ['color', 'value'];
module.exports = lightness;

},{"../nodes":148,"./component":75,"./hsla":86}],91:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Return the separator of the given `list`.
 *
 * Examples:
 *
 *    list1 = a b c
 *    list-separator(list1)
 *    // => ' '
 *
 *    list2 = a, b, c
 *    list-separator(list2)
 *    // => ','
 *
 * @param {Experssion} list
 * @return {String}
 * @api public
 */

(module.exports = function listSeparator(list){
  list = utils.unwrap(list);
  return new nodes.String(list.isList ? ',' : ' ');
}).raw = true;

},{"../nodes":148,"../utils":178}],92:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Lookup variable `name` or return Null.
 *
 * @param {String} name
 * @return {Mixed}
 * @api public
 */

function lookup(name){
  utils.assertType(name, 'string', 'name');
  var node = this.lookup(name.val);
  if (!node) return nodes.null;
  return this.visit(node);
}
lookup.params = ['name'];
module.exports = lookup;

},{"../nodes":148,"../utils":178}],93:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Returns the relative luminance of the given `color`,
 * see http://www.w3.org/TR/WCAG20/#relativeluminancedef
 *
 * Examples:
 *
 *     luminosity(white)
 *     // => 1
 * 
 *     luminosity(#000)
 *     // => 0
 * 
 *     luminosity(red)
 *     // => 0.2126
 *
 * @param {RGBA|HSLA} color
 * @return {Unit}
 * @api public
 */

function luminosity(color){
  utils.assertColor(color);
  color = color.rgba;
  function processChannel(channel) {
    channel = channel / 255;
    return (0.03928 > channel)
      ? channel / 12.92
      : Math.pow(((channel + 0.055) / 1.055), 2.4);
  }
  return new nodes.Unit(
    0.2126 * processChannel(color.r)
    + 0.7152 * processChannel(color.g)
    + 0.0722 * processChannel(color.b)
  );
};
luminosity.params = ['color'];
module.exports = luminosity;

},{"../nodes":148,"../utils":178}],94:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

var VALID_FLAGS = 'igm';

/**
 * retrieves the matches when matching a `val`(string)
 * against a `pattern`(regular expression).
 *
 * Examples:
 *   $regex = '^(height|width)?([<>=]{1,})(.*)'
 *
 *   match($regex,'height>=sm')
 * 	 // => ('height>=sm' 'height' '>=' 'sm')
 * 	 // => also truthy
 *
 *   match($regex, 'lorem ipsum')
 *   // => null
 *
 * @param {String} pattern
 * @param {String|Ident} val
 * @param {String|Ident} [flags='']
 * @return {String|Null}
 * @api public
 */

function match(pattern, val, flags){
  utils.assertType(pattern, 'string', 'pattern');
  utils.assertString(val, 'val');
  var re = new RegExp(pattern.val, validateFlags(flags) ? flags.string : '');
  return val.string.match(re);
}
match.params = ['pattern', 'val', 'flags'];
module.exports = match;

function validateFlags(flags) {
  flags = flags && flags.string;

  if (flags) {
    return flags.split('').every(function(flag) {
      return ~VALID_FLAGS.indexOf(flag);
    });
  }
  return false;
}

},{"../nodes":148,"../utils":178}],95:[function(require,module,exports){
var nodes = require('../nodes');

/**
 * Get Math `prop`.
 *
 * @param {String} prop
 * @return {Unit}
 * @api private
 */

function math(prop){
  return new nodes.Unit(Math[prop.string]);
}
math.params = ['prop'];
module.exports = math;

},{"../nodes":148}],96:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Apply Math `fn` to `n`.
 *
 * @param {Unit} n
 * @param {String} fn
 * @return {Unit}
 * @api private
 */

function math(n, fn){
  utils.assertType(n, 'unit', 'n');
  utils.assertString(fn, 'fn');
  return new nodes.Unit(Math[fn.string](n.val), n.type);
}
math.params = ['n', 'fn'];
module.exports = math;

},{"../nodes":148,"../utils":178}],97:[function(require,module,exports){
var utils = require('../utils');

/**
 * Merge the object `dest` with the given args.
 *
 * @param {Object} dest
 * @param {Object} ...
 * @return {Object} dest
 * @api public
 */

(module.exports = function merge(dest){
  utils.assertPresent(dest, 'dest');
  dest = utils.unwrap(dest).first;
  utils.assertType(dest, 'object', 'dest');

  var last = utils.unwrap(arguments[arguments.length - 1]).first
    , deep = (true === last.val);

  for (var i = 1, len = arguments.length - deep; i < len; ++i) {
    utils.merge(dest.vals, utils.unwrap(arguments[i]).first.vals, deep);
  }
  return dest;
}).raw = true;

},{"../utils":178}],98:[function(require,module,exports){
var utils = require('../utils');

/**
 * Perform `op` on the `left` and `right` operands.
 *
 * @param {String} op
 * @param {Node} left
 * @param {Node} right
 * @return {Node}
 * @api public
 */

function operate(op, left, right){
  utils.assertType(op, 'string', 'op');
  utils.assertPresent(left, 'left');
  utils.assertPresent(right, 'right');
  return left.operate(op.val, right);
}
operate.params = ['op', 'left', 'right'];
module.exports = operate;

},{"../utils":178}],99:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Return the opposites of the given `positions`.
 *
 * Examples:
 *
 *    opposite-position(top left)
 *    // => bottom right
 *
 * @param {Expression} positions
 * @return {Expression}
 * @api public
 */

(module.exports = function oppositePosition(positions){
  var expr = [];
  utils.unwrap(positions).nodes.forEach(function(pos, i){
    utils.assertString(pos, 'position ' + i);
    pos = (function(){ switch (pos.string) {
      case 'top': return 'bottom';
      case 'bottom': return 'top';
      case 'left': return 'right';
      case 'right': return 'left';
      case 'center': return 'center';
      default: throw new Error('invalid position ' + pos);
    }})();
    expr.push(new nodes.Literal(pos));
  });
  return expr;
}).raw = true;

},{"../nodes":148,"../utils":178}],100:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Inspect the given `expr`.
 *
 * @param {Expression} expr
 * @api public
 */

(module.exports = function p(){
  [].slice.call(arguments).forEach(function(expr){
    expr = utils.unwrap(expr);
    if (!expr.nodes.length) return;
    console.log('\u001b[90minspect:\u001b[0m %s', expr.toString().replace(/^\(|\)$/g, ''));
  })
  return nodes.null;
}).raw = true;

},{"../nodes":148,"../utils":178}],101:[function(require,module,exports){
var path = require('path');

/**
 * Peform a path join.
 *
 * @param {String} path
 * @return {String}
 * @api public
 */

(module.exports = function pathjoin(){
  var paths = [].slice.call(arguments).map(function(path){
    return path.first.string;
  });
  return path.join.apply(null, paths).replace(/\\/g, '/');
}).raw = true;

},{"path":52}],102:[function(require,module,exports){
var utils = require('../utils');

/**
 * Pop a value from `expr`.
 *
 * @param {Expression} expr
 * @return {Node}
 * @api public
 */

(module.exports = function pop(expr) {
  expr = utils.unwrap(expr);
  return expr.nodes.pop();
}).raw = true;

},{"../utils":178}],103:[function(require,module,exports){
var utils = require('../utils');

/**
 * Prefix css classes in a block
 *
 * @param {String} prefix
 * @param {Block} block
 * @return {Block}
 * @api private
 */

function prefixClasses(prefix, block){
  utils.assertString(prefix, 'prefix');
  utils.assertType(block, 'block', 'block');

  var _prefix = this.prefix;

  this.options.prefix = this.prefix = prefix.string;
  block = this.visit(block);
  this.options.prefix = this.prefix = _prefix;
  return block;
}
prefixClasses.params = ['prefix', 'block'];
module.exports = prefixClasses;

},{"../utils":178}],104:[function(require,module,exports){
var utils = require('../utils');

/**
 * Push the given args to `expr`.
 *
 * @param {Expression} expr
 * @param {Node} ...
 * @return {Unit}
 * @api public
 */

(module.exports = function(expr){
  expr = utils.unwrap(expr);
  for (var i = 1, len = arguments.length; i < len; ++i) {
    expr.nodes.push(utils.unwrap(arguments[i]).clone());
  }
  return expr.nodes.length;
}).raw = true;

},{"../utils":178}],105:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Returns a list of units from `start` to `stop`
 * by `step`. If `step` argument is omitted,
 * it defaults to 1.
 *
 * @param {Unit} start
 * @param {Unit} stop
 * @param {Unit} [step]
 * @return {Expression}
 * @api public
 */

function range(start, stop, step){
  utils.assertType(start, 'unit', 'start');
  utils.assertType(stop, 'unit', 'stop');
  if (step) {
    utils.assertType(step, 'unit', 'step');
    if (0 == step.val) {
      throw new Error('ArgumentError: "step" argument must not be zero');
    }
  } else {
    step = new nodes.Unit(1);
  }
  var list = new nodes.Expression;
  for (var i = start.val; i <= stop.val; i += step.val) {
    list.push(new nodes.Unit(i, start.type));
  }
  return list;
}
range.params = ['start', 'stop', 'step'];
module.exports = range;

},{"../nodes":148,"../utils":178}],106:[function(require,module,exports){
var nodes = require('../nodes')
  , rgba = require('./rgba');

/**
 * Return the red component of the given `color`,
 * or set the red component to the optional second `value` argument.
 *
 * Examples:
 *
 *    red(#c00)
 *    // => 204
 *
 *    red(#000, 255)
 *    // => #f00
 *
 * @param {RGBA|HSLA} color
 * @param {Unit} [value]
 * @return {Unit|RGBA}
 * @api public
 */

function red(color, value){
  color = color.rgba;
  if (value) {
    return rgba(
      value,
      new nodes.Unit(color.g),
      new nodes.Unit(color.b),
      new nodes.Unit(color.a)
    );
  }
  return new nodes.Unit(color.r, '');
}
red.params = ['color', 'value'];
module.exports = red;

},{"../nodes":148,"./rgba":110}],107:[function(require,module,exports){
var utils = require('../utils');

/**
 * Remove the given `key` from the `object`.
 *
 * @param {Object} object
 * @param {String} key
 * @return {Object}
 * @api public
 */

function remove(object, key){
  utils.assertType(object, 'object', 'object');
  utils.assertString(key, 'key');
  delete object.vals[key.string];
  return object;
}
remove.params = ['object', 'key'];
module.exports = remove;

},{"../utils":178}],108:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Returns string with all matches of `pattern` replaced by `replacement` in given `val`
 *
 * @param {String} pattern
 * @param {String} replacement
 * @param {String|Ident} val
 * @return {String|Ident}
 * @api public
 */

function replace(pattern, replacement, val){
  utils.assertString(pattern, 'pattern');
  utils.assertString(replacement, 'replacement');
  utils.assertString(val, 'val');
  pattern = new RegExp(pattern.string, 'g');
  var res = val.string.replace(pattern, replacement.string);
  return val instanceof nodes.Ident
    ? new nodes.Ident(res)
    : new nodes.String(res);
}
replace.params = ['pattern', 'replacement', 'val'];
module.exports = replace;

},{"../nodes":148,"../utils":178}],109:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes')
  , rgba = require('./rgba');

/**
 * Return a `RGBA` from the r,g,b channels.
 *
 * Examples:
 *
 *    rgb(255,204,0)
 *    // => #ffcc00
 *
 *    rgb(#fff)
 *    // => #fff
 *
 * @param {Unit|RGBA|HSLA} red
 * @param {Unit} green
 * @param {Unit} blue
 * @return {RGBA}
 * @api public
 */

function rgb(red, green, blue){
  switch (arguments.length) {
    case 1:
      utils.assertColor(red);
      var color = red.rgba;
      return new nodes.RGBA(
          color.r
        , color.g
        , color.b
        , 1);
    default:
      return rgba(
          red
        , green
        , blue
        , new nodes.Unit(1));
  }
}
rgb.params = ['red', 'green', 'blue'];
module.exports = rgb;

},{"../nodes":148,"../utils":178,"./rgba":110}],110:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Return a `RGBA` from the r,g,b,a channels.
 *
 * Examples:
 *
 *    rgba(255,0,0,0.5)
 *    // => rgba(255,0,0,0.5)
 *
 *    rgba(255,0,0,1)
 *    // => #ff0000
 *
 *    rgba(#ffcc00, 50%)
 *    // rgba(255,204,0,0.5)
 *
 * @param {Unit|RGBA|HSLA} red
 * @param {Unit} green
 * @param {Unit} blue
 * @param {Unit} alpha
 * @return {RGBA}
 * @api public
 */

function rgba(red, green, blue, alpha){
  switch (arguments.length) {
    case 1:
      utils.assertColor(red);
      return red.rgba;
    case 2:
      utils.assertColor(red);
      var color = red.rgba;
      utils.assertType(green, 'unit', 'alpha');
      alpha = green.clone();
      if ('%' == alpha.type) alpha.val /= 100;
      return new nodes.RGBA(
          color.r
        , color.g
        , color.b
        , alpha.val);
    default:
      utils.assertType(red, 'unit', 'red');
      utils.assertType(green, 'unit', 'green');
      utils.assertType(blue, 'unit', 'blue');
      utils.assertType(alpha, 'unit', 'alpha');
      var r = '%' == red.type ? Math.round(red.val * 2.55) : red.val
        , g = '%' == green.type ? Math.round(green.val * 2.55) : green.val
        , b = '%' == blue.type ? Math.round(blue.val * 2.55) : blue.val;

      alpha = alpha.clone();
      if (alpha && '%' == alpha.type) alpha.val /= 100;
      return new nodes.RGBA(
          r
        , g
        , b
        , alpha.val);
  }
}
rgba.params = ['red', 'green', 'blue', 'alpha'];
module.exports = rgba;

},{"../nodes":148,"../utils":178}],111:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes')
  , Compiler = require('../visitor/compiler');

/**
 * Return a `Literal` with the given `fmt`, and
 * variable number of arguments.
 *
 * @param {String} fmt
 * @param {Node} ...
 * @return {Literal}
 * @api public
 */

(module.exports = function s(fmt){
  fmt = utils.unwrap(fmt).nodes[0];
  utils.assertString(fmt);
  var self = this
    , str = fmt.string
    , args = arguments
    , i = 1;

  // format
  str = str.replace(/%(s|d)/g, function(_, specifier){
    var arg = args[i++] || nodes.null;
    switch (specifier) {
      case 's':
        return new Compiler(arg, self.options).compile();
      case 'd':
        arg = utils.unwrap(arg).first;
        if ('unit' != arg.nodeName) throw new Error('%d requires a unit');
        return arg.val;
    }
  });

  return new nodes.Literal(str);
}).raw = true;

},{"../nodes":148,"../utils":178,"../visitor/compiler":179}],112:[function(require,module,exports){
var nodes = require('../nodes')
  , hsla = require('./hsla')
  , component = require('./component');

/**
 * Return the saturation component of the given `color`,
 * or set the saturation component to the optional second `value` argument.
 *
 * Examples:
 *
 *    saturation(#00c)
 *    // => 100%
 *
 *    saturation(#00c, 50%)
 *    // => #339
 *
 * @param {RGBA|HSLA} color
 * @param {Unit} [value]
 * @return {Unit|RGBA}
 * @api public
 */

function saturation(color, value){
  if (value) {
    var hslaColor = color.hsla;
    return hsla(
      new nodes.Unit(hslaColor.h),
      value,
      new nodes.Unit(hslaColor.l),
      new nodes.Unit(hslaColor.a)
    )
  }
  return component(color, new nodes.String('saturation'));
}
saturation.params = ['color', 'value'];
module.exports = saturation;

},{"../nodes":148,"./component":75,"./hsla":86}],113:[function(require,module,exports){
var utils = require('../utils');

/**
 * Returns true if the given selector exists.
 *
 * @param {String} sel
 * @return {Boolean}
 * @api public
 */

function selectorExists(sel) {
  utils.assertString(sel, 'selector');

  if (!this.__selectorsMap__) {
    var Normalizer = require('../visitor/normalizer')
      , visitor = new Normalizer(this.root.clone());
    visitor.visit(visitor.root);

    this.__selectorsMap__ = visitor.map;
  }

  return sel.string in this.__selectorsMap__;
}
selectorExists.params = ['sel'];
module.exports = selectorExists;

},{"../utils":178,"../visitor/normalizer":183}],114:[function(require,module,exports){
var utils = require('../utils');

/**
 * Return the current selector or compile
 * selector from a string or a list.
 *
 * @param {String|Expression}
 * @return {String}
 * @api public
 */

(module.exports = function selector(){
  var stack = this.selectorStack
    , args = [].slice.call(arguments);

  if (1 == args.length) {
    var expr = utils.unwrap(args[0])
      , len = expr.nodes.length;

    // selector('.a')
    if (1 == len) {
      utils.assertString(expr.first, 'selector');
      var SelectorParser = require('../selector-parser')
        , val = expr.first.string
        , parsed = new SelectorParser(val).parse().val;

      if (parsed == val) return val;

      stack.push(parse(val));
    } else if (len > 1) {
      // selector-list = '.a', '.b', '.c'
      // selector(selector-list)
      if (expr.isList) {
        pushToStack(expr.nodes, stack);
      // selector('.a' '.b' '.c')
      } else {
        stack.push(parse(expr.nodes.map(function(node){
          utils.assertString(node, 'selector');
          return node.string;
        }).join(' ')));
      }
    }
  // selector('.a', '.b', '.c')
  } else if (args.length > 1) {
    pushToStack(args, stack);
  }

  return stack.length ? utils.compileSelectors(stack).join(',') : '&';
}).raw = true;

function pushToStack(selectors, stack) {
  selectors.forEach(function(sel) {
    sel = sel.first;
    utils.assertString(sel, 'selector');
    stack.push(parse(sel.string));
  });
}

function parse(selector) {
  var Parser = new require('../parser')
    , parser = new Parser(selector)
    , nodes;
  parser.state.push('selector-parts');
  nodes = parser.selector();
  nodes.forEach(function(node) {
    node.val = node.segments.map(function(seg){
      return seg.toString();
    }).join('');
  });
  return nodes;
}

},{"../selector-parser":172,"../utils":178}],115:[function(require,module,exports){
var nodes = require('../nodes')
  , Parser = require('../selector-parser');

/**
 * Return a list with raw selectors parts
 * of the current group.
 *
 * For example:
 *
 *    .a, .b
 *      .c
 *        .d
 *          test: selectors() // => '.a,.b', '& .c', '& .d'
 *
 * @return {Expression}
 * @api public
 */

module.exports = function selectors(){
  var stack = this.selectorStack
    , expr = new nodes.Expression(true);

  if (stack.length) {
    for (var i = 0; i < stack.length; i++) {
      var group = stack[i]
        , nested;

      if (group.length > 1) {
        expr.push(new nodes.String(group.map(function(selector) {
          nested = new Parser(selector.val).parse().nested;
          return (nested && i ? '& ' : '') + selector.val;
        }).join(',')))
      } else {
        var selector = group[0].val
        nested = new Parser(selector).parse().nested;
        expr.push(new nodes.String((nested && i ? '& ' : '') + selector));
      }
    }
  } else {
    expr.push(new nodes.String('&'));
  }
  return expr;
};

},{"../nodes":148,"../selector-parser":172}],116:[function(require,module,exports){
var utils = require('../utils');

/**
 * Shift an element from `expr`.
 *
 * @param {Expression} expr
 * @return {Node}
 * @api public
 */

 (module.exports = function(expr){
   expr = utils.unwrap(expr);
   return expr.nodes.shift();
 }).raw = true;


},{"../utils":178}],117:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * This is a helper function for the slice method
 *
 * @param {String|Ident} vals
 * @param {Unit} start [0]
 * @param {Unit} end [vals.length]
 * @return {String|Literal|Null}
 * @api public
*/
(module.exports = function slice(val, start, end) {
  start = start && start.nodes[0].val;
  end = end && end.nodes[0].val;

  val = utils.unwrap(val).nodes;

  if (val.length > 1) {
    return utils.coerce(val.slice(start, end), true);
  }

  var result = val[0].string.slice(start, end);

  return val[0] instanceof nodes.Ident
    ? new nodes.Ident(result)
    : new nodes.String(result);
}).raw = true;

},{"../nodes":148,"../utils":178}],118:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Splits the given `val` by `delim`
 *
 * @param {String} delim
 * @param {String|Ident} val
 * @return {Expression}
 * @api public
 */

function split(delim, val){
  utils.assertString(delim, 'delimiter');
  utils.assertString(val, 'val');
  var splitted = val.string.split(delim.string);
  var expr = new nodes.Expression();
  var ItemNode = val instanceof nodes.Ident
    ? nodes.Ident
    : nodes.String;
  for (var i = 0, len = splitted.length; i < len; ++i) {
    expr.nodes.push(new ItemNode(splitted[i]));
  }
  return expr;
}
split.params = ['delim', 'val'];
module.exports = split;

},{"../nodes":148,"../utils":178}],119:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Returns substring of the given `val`.
 *
 * @param {String|Ident} val
 * @param {Number} start
 * @param {Number} [length]
 * @return {String|Ident}
 * @api public
 */

function substr(val, start, length){
  utils.assertString(val, 'val');
  utils.assertType(start, 'unit', 'start');
  length = length && length.val;
  var res = val.string.substr(start.val, length);
  return val instanceof nodes.Ident
      ? new nodes.Ident(res)
      : new nodes.String(res);
}
substr.params = ['val', 'start', 'length'];
module.exports = substr;

},{"../nodes":148,"../utils":178}],120:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Return the tangent of the given `angle`.
 *
 * @param {Unit} angle
 * @return {Unit}
 * @api public
 */

function tan(angle) {
  utils.assertType(angle, 'unit', 'angle');

  var radians = angle.val;

  if (angle.type === 'deg') {
    radians *= Math.PI / 180;
  }

  var m = Math.pow(10, 9);

  var sin = Math.round(Math.sin(radians) * m) / m
    , cos = Math.round(Math.cos(radians) * m) / m
    , tan = Math.round(m * sin / cos ) / m;

  return new nodes.Unit(tan, '');
}
tan.params = ['angle'];
module.exports = tan;

},{"../nodes":148,"../utils":178}],121:[function(require,module,exports){
var nodes = require('../nodes');

/**
 * Output stack trace.
 *
 * @api public
 */

module.exports = function trace(){
  console.log(this.stack);
  return nodes.null;
};

},{"../nodes":148}],122:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Returns the transparent version of the given `top` color,
 * as if it was blend over the given `bottom` color.
 *
 * Examples:
 *
 *     transparentify(#808080)
 *     => rgba(0,0,0,0.5)
 *
 *     transparentify(#414141, #000)
 *     => rgba(255,255,255,0.25)
 *
 *     transparentify(#91974C, #F34949, 0.5)
 *     => rgba(47,229,79,0.5)
 *
 * @param {RGBA|HSLA} top
 * @param {RGBA|HSLA} [bottom=#fff]
 * @param {Unit} [alpha]
 * @return {RGBA}
 * @api public
 */

function transparentify(top, bottom, alpha){
  utils.assertColor(top);
  top = top.rgba;
  // Handle default arguments
  bottom = bottom || new nodes.RGBA(255, 255, 255, 1);
  if (!alpha && bottom && !bottom.rgba) {
    alpha = bottom;
    bottom = new nodes.RGBA(255, 255, 255, 1);
  }
  utils.assertColor(bottom);
  bottom = bottom.rgba;
  var bestAlpha = ['r', 'g', 'b'].map(function(channel){
    return (top[channel] - bottom[channel]) / ((0 < (top[channel] - bottom[channel]) ? 255 : 0) - bottom[channel]);
  }).sort(function(a, b){return b - a;})[0];
  if (alpha) {
    utils.assertType(alpha, 'unit', 'alpha');
    if ('%' == alpha.type) {
      bestAlpha = alpha.val / 100;
    } else if (!alpha.type) {
      bestAlpha = alpha = alpha.val;
    }
  }
  bestAlpha = Math.max(Math.min(bestAlpha, 1), 0);
  // Calculate the resulting color
  function processChannel(channel) {
    if (0 == bestAlpha) {
      return bottom[channel]
    } else {
      return bottom[channel] + (top[channel] - bottom[channel]) / bestAlpha
    }
  }
  return new nodes.RGBA(
    processChannel('r'),
    processChannel('g'),
    processChannel('b'),
    Math.round(bestAlpha * 100) / 100
  );
}
transparentify.params = ['top', 'bottom', 'alpha'];
module.exports = transparentify;

},{"../nodes":148,"../utils":178}],123:[function(require,module,exports){
var utils = require('../utils');

/**
 * Return type of `node`.
 *
 * Examples:
 * 
 *    type(12)
 *    // => 'unit'
 *
 *    type(#fff)
 *    // => 'color'
 *
 *    type(type)
 *    // => 'function'
 *
 *    type(unbound)
 *    typeof(unbound)
 *    type-of(unbound)
 *    // => 'ident'
 *
 * @param {Node} node
 * @return {String}
 * @api public
 */

function type(node){
  utils.assertPresent(node, 'expression');
  return node.nodeName;
}
type.params = ['node'];
module.exports = type;

},{"../utils":178}],124:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Assign `type` to the given `unit` or return `unit`'s type.
 *
 * @param {Unit} unit
 * @param {String|Ident} type
 * @return {Unit}
 * @api public
 */

function unit(unit, type){
  utils.assertType(unit, 'unit', 'unit');

  // Assign
  if (type) {
    utils.assertString(type, 'type');
    return new nodes.Unit(unit.val, type.string);
  } else {
    return unit.type || '';
  }
}
unit.params = ['unit', 'type'];
module.exports = unit;

},{"../nodes":148,"../utils":178}],125:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Unquote the given `string`.
 *
 * Examples:
 *
 *    unquote("sans-serif")
 *    // => sans-serif
 *
 *    unquote(sans-serif)
 *    // => sans-serif
 *
 * @param {String|Ident} string
 * @return {Literal}
 * @api public
 */

function unquote(string){
  utils.assertString(string, 'string');
  return new nodes.Literal(string.string);
}
unquote.params = ['string'];
module.exports = unquote;

},{"../nodes":148,"../utils":178}],126:[function(require,module,exports){
var utils = require('../utils');

/**
 * Unshift the given args to `expr`.
 *
 * @param {Expression} expr
 * @param {Node} ...
 * @return {Unit}
 * @api public
 */

(module.exports = function(expr){
  expr = utils.unwrap(expr);
  for (var i = 1, len = arguments.length; i < len; ++i) {
    expr.nodes.unshift(utils.unwrap(arguments[i]));
  }
  return expr.nodes.length;
}).raw = true;

},{"../utils":178}],127:[function(require,module,exports){
var utils = require('../utils')
  , nodes = require('../nodes');

/**
 * Warn with the given `msg` prefixed by "Warning: ".
 *
 * @param {String} msg
 * @api public
 */

function warn(msg){
  utils.assertType(msg, 'string', 'msg');
  console.warn('Warning: %s', msg.val);
  return nodes.null;
}
warn.params = ['msg'];
module.exports = warn;

},{"../nodes":148,"../utils":178}],128:[function(require,module,exports){

/*!
 * Stylus - Lexer
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Token = require('./token')
  , nodes = require('./nodes')
  , errors = require('./errors');

/**
 * Operator aliases.
 */

var alias = {
  'and': '&&'
  , 'or': '||'
  , 'is': '=='
  , 'isnt': '!='
  , 'is not': '!='
  , ':=': '?='
};

exports = module.exports = class Lexer {
  /**
   * Initialize a new `Lexer` with the given `str` and `options`.
   *
   * @param {String} str
   * @param {Object} options
   * @api private
   */

  constructor(str, options) {
    options = options || {};
    this.stash = [];
    this.indentStack = [];
    this.indentRe = null;
    this.lineno = 1;
    this.column = 1;

    // HACK!
    function comment(str, val, offset, s) {
      var inComment = s.lastIndexOf('/*', offset) > s.lastIndexOf('*/', offset)
        , commentIdx = s.lastIndexOf('//', offset)
        , i = s.lastIndexOf('\n', offset)
        , double = 0
        , single = 0;

      if (~commentIdx && commentIdx > i) {
        while (i != offset) {
          if ("'" == s[i]) single ? single-- : single++;
          if ('"' == s[i]) double ? double-- : double++;

          if ('/' == s[i] && '/' == s[i + 1]) {
            inComment = !single && !double;
            break;
          }
          ++i;
        }
      }

      return inComment
        ? str
        : ((val === ',' && /^[,\t\n]+$/.test(str)) ? str.replace(/\n/, '\r') : val + '\r');
    };

    // Remove UTF-8 BOM.
    if ('\uFEFF' == str.charAt(0)) str = str.slice(1);

    this.str = str
      .replace(/\s+$/, '\n')
      .replace(/\r\n?/g, '\n')
      .replace(/\\ *\n/g, '\r')
      .replace(/([,(:](?!\/\/[^ ])) *(?:\/\/[^\n]*|\/\*.*?\*\/)?\n\s*/g, comment)
      .replace(/\s*\n[ \t]*([,)])/g, comment);
  };

  /**
     * Custom inspect.
     */

  inspect() {
    var tok
      , tmp = this.str
      , buf = [];
    while ('eos' != (tok = this.next()).type) {
      buf.push(tok.inspect());
    }
    this.str = tmp;
    return buf.concat(tok.inspect()).join('\n');
  }

  /**
   * Lookahead `n` tokens.
   *
   * @param {Number} n
   * @return {Object}
   * @api private
   */

  lookahead(n) {
    var fetch = n - this.stash.length;
    while (fetch-- > 0) this.stash.push(this.advance());
    return this.stash[--n];
  }

  /**
   * Consume the given `len`.
   *
   * @param {Number|Array} len
   * @api private
   */

  skip(len) {
    var chunk = len[0];
    len = chunk ? chunk.length : len;
    this.str = this.str.substr(len);
    if (chunk) {
      this.move(chunk);
    } else {
      this.column += len;
    }
  }

  /**
   * Move current line and column position.
   *
   * @param {String} str
   * @api private
   */

  move(str) {
    var lines = str.match(/\n/g)
      , idx = str.lastIndexOf('\n');

    if (lines) this.lineno += lines.length;
    this.column = ~idx
      ? str.length - idx
      : this.column + str.length;
  }

  /**
   * Fetch next token including those stashed by peek.
   *
   * @return {Token}
   * @api private
   */

  next() {
    var tok = this.stashed() || this.advance();
    this.prev = tok;
    return tok;
  }

  /**
   * Check if the current token is a part of selector.
   *
   * @return {Boolean}
   * @api private
   */

  isPartOfSelector() {
    var tok = this.stash[this.stash.length - 1] || this.prev;
    switch (tok && tok.type) {
      // #for
      case 'color':
        return 2 == tok.val.raw.length;
      // .or
      case '.':
      // [is]
      case '[':
        return true;
    }
    return false;
  }

  /**
   * Fetch next token.
   *
   * @return {Token}
   * @api private
   */

  advance() {
    var column = this.column
      , line = this.lineno
      , tok = this.eos()
        || this.null()
        || this.sep()
        || this.keyword()
        || this.urlchars()
        || this.comment()
        || this.newline()
        || this.escaped()
        || this.important()
        || this.literal()
        || this.anonFunc()
        || this.atrule()
        || this.function()
        || this.brace()
        || this.paren()
        || this.color()
        || this.string()
        || this.unit()
        || this.namedop()
        || this.boolean()
        || this.unicode()
        || this.ident()
        || this.op()
        || (function () {
          var token = this.eol();

          if (token) {
            column = token.column;
            line = token.lineno;
          }

          return token;
        }).call(this)
        || this.space()
        || this.selector();

    tok.lineno = line;
    tok.column = column;

    return tok;
  }

  /**
   * Lookahead a single token.
   *
   * @return {Token}
   * @api private
   */

  peek() {
    return this.lookahead(1);
  }

  /**
   * Return the next possibly stashed token.
   *
   * @return {Token}
   * @api private
   */

  stashed() {
    return this.stash.shift();
  }

  /**
   * EOS | trailing outdents.
   */

  eos() {
    if (this.str.length) return;
    if (this.indentStack.length) {
      this.indentStack.shift();
      return new Token('outdent');
    } else {
      return new Token('eos');
    }
  }

  /**
   * url char
   */

  urlchars() {
    var captures;
    if (!this.isURL) return;
    if (captures = /^[\/:@.;?&=*!,<>#%0-9]+/.exec(this.str)) {
      this.skip(captures);
      return new Token('literal', new nodes.Literal(captures[0]));
    }
  }

  /**
   * ';' [ \t]*
   */

  sep() {
    var captures;
    if (captures = /^;[ \t]*/.exec(this.str)) {
      this.skip(captures);
      return new Token(';');
    }
  }

  /**
   * '\r'
   */

  eol() {
    if ('\r' == this.str[0]) {
      ++this.lineno;
      this.skip(1);

      this.column = 1;
      while (this.space());

      return this.advance();
    }
  }

  /**
   * ' '+
   */

  space() {
    var captures;
    if (captures = /^([ \t]+)/.exec(this.str)) {
      this.skip(captures);
      return new Token('space');
    }
  }

  /**
   * '\\' . ' '*
   */

  escaped() {
    var captures;
    if (captures = /^\\(.)[ \t]*/.exec(this.str)) {
      var c = captures[1];
      this.skip(captures);
      return new Token('ident', new nodes.Literal(c));
    }
  }

  /**
   * '@css' ' '* '{' .* '}' ' '*
   */

  literal() {
    // HACK attack !!!
    var captures;
    if (captures = /^@css[ \t]*\{/.exec(this.str)) {
      this.skip(captures);
      var c
        , braces = 1
        , css = ''
        , node;
      while (c = this.str[0]) {
        this.str = this.str.substr(1);
        switch (c) {
          case '{': ++braces; break;
          case '}': --braces; break;
          case '\n':
          case '\r':
            ++this.lineno;
            break;
        }
        css += c;
        if (!braces) break;
      }
      css = css.replace(/\s*}$/, '');
      node = new nodes.Literal(css);
      node.css = true;
      return new Token('literal', node);
    }
  }

  /**
   * '!important' ' '*
   */

  important() {
    var captures;
    if (captures = /^!important[ \t]*/.exec(this.str)) {
      this.skip(captures);
      return new Token('ident', new nodes.Literal('!important'));
    }
  }

  /**
   * '{' | '}'
   */

  brace() {
    var captures;
    if (captures = /^([{}])/.exec(this.str)) {
      this.skip(1);
      var brace = captures[1];
      return new Token(brace, brace);
    }
  }

  /**
   * '(' | ')' ' '*
   */

  paren() {
    var captures;
    if (captures = /^([()])([ \t]*)/.exec(this.str)) {
      var paren = captures[1];
      this.skip(captures);
      if (')' == paren) this.isURL = false;
      var tok = new Token(paren, paren);
      tok.space = captures[2];
      return tok;
    }
  }

  /**
   * 'null'
   */

  null() {
    var captures
      , tok;
    if (captures = /^(null)\b[ \t]*/.exec(this.str)) {
      this.skip(captures);
      if (this.isPartOfSelector()) {
        tok = new Token('ident', new nodes.Ident(captures[0]));
      } else {
        tok = new Token('null', nodes.null);
      }
      return tok;
    }
  }

  /**
   *   'if'
   * | 'else'
   * | 'unless'
   * | 'return'
   * | 'for'
   * | 'in'
   */

  keyword() {
    var captures
      , tok;
    if (captures = /^(return|if|else|unless|for|in)\b(?!-)[ \t]*/.exec(this.str)) {
      var keyword = captures[1];
      this.skip(captures);
      if (this.isPartOfSelector()) {
        tok = new Token('ident', new nodes.Ident(captures[0]));
      } else {
        tok = new Token(keyword, keyword);
      }
      return tok;
    }
  }

  /**
   *   'not'
   * | 'and'
   * | 'or'
   * | 'is'
   * | 'is not'
   * | 'isnt'
   * | 'is a'
   * | 'is defined'
   */

  namedop() {
    var captures
      , tok;
    if (captures = /^(not|and|or|is a|is defined|isnt|is not|is)(?!-)\b([ \t]*)/.exec(this.str)) {
      var op = captures[1];
      this.skip(captures);
      if (this.isPartOfSelector()) {
        tok = new Token('ident', new nodes.Ident(captures[0]));
      } else {
        op = alias[op] || op;
        tok = new Token(op, op);
      }
      tok.space = captures[2];
      return tok;
    }
  }

  /**
   *   ','
   * | '+'
   * | '+='
   * | '-'
   * | '-='
   * | '*'
   * | '*='
   * | '/'
   * | '/='
   * | '%'
   * | '%='
   * | '**'
   * | '!'
   * | '&'
   * | '&&'
   * | '||'
   * | '>'
   * | '>='
   * | '<'
   * | '<='
   * | '='
   * | '=='
   * | '!='
   * | '!'
   * | '~'
   * | '?='
   * | ':='
   * | '?'
   * | ':'
   * | '['
   * | ']'
   * | '.'
   * | '..'
   * | '...'
   */

  op() {
    var captures;
    if (captures = /^([.]{1,3}|&&|\|\||[!<>=?:]=|\*\*|[-+*\/%]=?|[,=?:!~<>&\[\]])([ \t]*)/.exec(this.str)) {
      var op = captures[1];
      this.skip(captures);
      op = alias[op] || op;
      var tok = new Token(op, op);
      tok.space = captures[2];
      this.isURL = false;
      return tok;
    }
  }

  /**
   * '@('
   */

  anonFunc() {
    var tok;
    if ('@' == this.str[0] && '(' == this.str[1]) {
      this.skip(2);
      tok = new Token('function', new nodes.Ident('anonymous'));
      tok.anonymous = true;
      return tok;
    }
  }

  /**
   * '@' (-(\w+)-)?[a-zA-Z0-9-_]+
   */

  atrule() {
    var captures;
    if (captures = /^@(?!apply)(?:-(\w+)-)?([a-zA-Z0-9-_]+)[ \t]*/.exec(this.str)) {
      this.skip(captures);
      var vendor = captures[1]
        , type = captures[2]
        , tok;
      switch (type) {
        case 'require':
        case 'import':
        case 'charset':
        case 'namespace':
        case 'media':
        case 'scope':
        case 'supports':
          return new Token(type);
        case 'document':
          return new Token('-moz-document');
        case 'block':
          return new Token('atblock');
        case 'extend':
        case 'extends':
          return new Token('extend');
        case 'keyframes':
          return new Token(type, vendor);
        default:
          return new Token('atrule', (vendor ? '-' + vendor + '-' + type : type));
      }
    }
  }

  /**
   * '//' *
   */

  comment() {
    // Single line
    if ('/' == this.str[0] && '/' == this.str[1]) {
      var end = this.str.indexOf('\n');
      if (-1 == end) end = this.str.length;
      this.skip(end);
      return this.advance();
    }

    // Multi-line
    if ('/' == this.str[0] && '*' == this.str[1]) {
      var end = this.str.indexOf('*/');
      if (-1 == end) end = this.str.length;
      var str = this.str.substr(0, end + 2)
        , lines = str.split(/\n|\r/).length - 1
        , suppress = true
        , inline = false;
      this.lineno += lines;
      this.skip(end + 2);
      // output
      if ('!' == str[2]) {
        str = str.replace('*!', '*');
        suppress = false;
      }
      if (this.prev && ';' == this.prev.type) inline = true;
      return new Token('comment', new nodes.Comment(str, suppress, inline));
    }
  }

  /**
   * 'true' | 'false'
   */

  boolean() {
    var captures;
    if (captures = /^(true|false)\b([ \t]*)/.exec(this.str)) {
      var val = new nodes.Boolean('true' == captures[1]);
      this.skip(captures);
      var tok = new Token('boolean', val);
      tok.space = captures[2];
      return tok;
    }
  }

  /**
   * 'U+' [0-9A-Fa-f?]{1,6}(?:-[0-9A-Fa-f]{1,6})?
   */

  unicode() {
    var captures;
    if (captures = /^u\+[0-9a-f?]{1,6}(?:-[0-9a-f]{1,6})?/i.exec(this.str)) {
      this.skip(captures);
      return new Token('literal', new nodes.Literal(captures[0]));
    }
  }

  /**
   * -*[_a-zA-Z$] [-\w\d$]* '('
   */

  function() {
    var captures;
    if (captures = /^(-*[_a-zA-Z$][-\w\d$]*)\(([ \t]*)/.exec(this.str)) {
      var name = captures[1];
      this.skip(captures);
      this.isURL = 'url' == name;
      var tok = new Token('function', new nodes.Ident(name));
      tok.space = captures[2];
      return tok;
    }
  }

  /**
   * -*[_a-zA-Z$] [-\w\d$]*
   */

  ident() {
    var captures;
    if (captures = /^-*([_a-zA-Z$]|@apply)[-\w\d$]*/.exec(this.str)) {
      this.skip(captures);
      return new Token('ident', new nodes.Ident(captures[0]));
    }
  }

  /**
   * '\n' ' '+
   */

  newline() {
    var captures, re;

    // we have established the indentation regexp
    if (this.indentRe) {
      captures = this.indentRe.exec(this.str);
      // figure out if we are using tabs or spaces
    } else {
      // try tabs
      re = /^\n([\t]*)[ \t]*/;
      captures = re.exec(this.str);

      // nope, try spaces
      if (captures && !captures[1].length) {
        re = /^\n([ \t]*)/;
        captures = re.exec(this.str);
      }

      // established
      if (captures && captures[1].length) this.indentRe = re;
    }


    if (captures) {
      var tok
        , indents = captures[1].length;

      this.skip(captures);
      if (this.str[0] === ' ' || this.str[0] === '\t') {
        throw new errors.SyntaxError('Invalid indentation. You can use tabs or spaces to indent, but not both.');
      }

      // Blank line
      if ('\n' == this.str[0]) return this.advance();

      // Outdent
      if (this.indentStack.length && indents < this.indentStack[0]) {
        while (this.indentStack.length && this.indentStack[0] > indents) {
          this.stash.push(new Token('outdent'));
          this.indentStack.shift();
        }
        tok = this.stash.pop();
        // Indent
      } else if (indents && indents != this.indentStack[0]) {
        this.indentStack.unshift(indents);
        tok = new Token('indent');
        // Newline
      } else {
        tok = new Token('newline');
      }

      return tok;
    }
  }

  /**
   * '-'? (digit+ | digit* '.' digit+) unit
   */

  unit() {
    var captures;
    if (captures = /^(-)?(\d+\.\d+|\d+|\.\d+)(%|[a-zA-Z]+)?[ \t]*/.exec(this.str)) {
      this.skip(captures);
      var n = parseFloat(captures[2]);
      if ('-' == captures[1]) n = -n;
      var node = new nodes.Unit(n, captures[3]);
      node.raw = captures[0];
      return new Token('unit', node);
    }
  }

  /**
   * '"' [^"]+ '"' | "'"" [^']+ "'"
   */

  string() {
    var captures;
    if (captures = /^("[^"]*"|'[^']*')[ \t]*/.exec(this.str)) {
      var str = captures[1]
        , quote = captures[0][0];
      this.skip(captures);
      str = str.slice(1, -1).replace(/\\n/g, '\n');
      return new Token('string', new nodes.String(str, quote));
    }
  }

  /**
   * #rrggbbaa | #rrggbb | #rgba | #rgb | #nn | #n
   */

  color() {
    return this.rrggbbaa()
      || this.rrggbb()
      || this.rgba()
      || this.rgb()
      || this.nn()
      || this.n()
  }

  /**
   * #n
   */

  n() {
    var captures;
    if (captures = /^#([a-fA-F0-9]{1})[ \t]*/.exec(this.str)) {
      this.skip(captures);
      var n = parseInt(captures[1] + captures[1], 16)
        , color = new nodes.RGBA(n, n, n, 1);
      color.raw = captures[0];
      return new Token('color', color);
    }
  }

  /**
   * #nn
   */

  nn() {
    var captures;
    if (captures = /^#([a-fA-F0-9]{2})[ \t]*/.exec(this.str)) {
      this.skip(captures);
      var n = parseInt(captures[1], 16)
        , color = new nodes.RGBA(n, n, n, 1);
      color.raw = captures[0];
      return new Token('color', color);
    }
  }

  /**
   * #rgb
   */

  rgb() {
    var captures;
    if (captures = /^#([a-fA-F0-9]{3})[ \t]*/.exec(this.str)) {
      this.skip(captures);
      var rgb = captures[1]
        , r = parseInt(rgb[0] + rgb[0], 16)
        , g = parseInt(rgb[1] + rgb[1], 16)
        , b = parseInt(rgb[2] + rgb[2], 16)
        , color = new nodes.RGBA(r, g, b, 1);
      color.raw = captures[0];
      return new Token('color', color);
    }
  }

  /**
   * #rgba
   */

  rgba() {
    var captures;
    if (captures = /^#([a-fA-F0-9]{4})[ \t]*/.exec(this.str)) {
      this.skip(captures);
      var rgb = captures[1]
        , r = parseInt(rgb[0] + rgb[0], 16)
        , g = parseInt(rgb[1] + rgb[1], 16)
        , b = parseInt(rgb[2] + rgb[2], 16)
        , a = parseInt(rgb[3] + rgb[3], 16)
        , color = new nodes.RGBA(r, g, b, a / 255);
      color.raw = captures[0];
      return new Token('color', color);
    }
  }

  /**
   * #rrggbb
   */

  rrggbb() {
    var captures;
    if (captures = /^#([a-fA-F0-9]{6})[ \t]*/.exec(this.str)) {
      this.skip(captures);
      var rgb = captures[1]
        , r = parseInt(rgb.substr(0, 2), 16)
        , g = parseInt(rgb.substr(2, 2), 16)
        , b = parseInt(rgb.substr(4, 2), 16)
        , color = new nodes.RGBA(r, g, b, 1);
      color.raw = captures[0];
      return new Token('color', color);
    }
  }

  /**
   * #rrggbbaa
   */

  rrggbbaa() {
    var captures;
    if (captures = /^#([a-fA-F0-9]{8})[ \t]*/.exec(this.str)) {
      this.skip(captures);
      var rgb = captures[1]
        , r = parseInt(rgb.substr(0, 2), 16)
        , g = parseInt(rgb.substr(2, 2), 16)
        , b = parseInt(rgb.substr(4, 2), 16)
        , a = parseInt(rgb.substr(6, 2), 16)
        , color = new nodes.RGBA(r, g, b, a / 255);
      color.raw = captures[0];
      return new Token('color', color);
    }
  }

  /**
   * ^|[^\n,;]+
   */

  selector() {
    var captures;
    if (captures = /^\^|.*?(?=\/\/(?![^\[]*\])|[,\n{])/.exec(this.str)) {
      var selector = captures[0];
      this.skip(captures);
      return new Token('selector', selector);
    }
  }
};

},{"./errors":63,"./nodes":148,"./token":176}],129:[function(require,module,exports){

/*!
 * Stylus - Arguments
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var nodes = require('../nodes');

module.exports = class Arguments extends nodes.Expression {
  /**
   * Initialize a new `Arguments`.
   *
   * @api public
   */

  constructor() {
    super();
    this.map = {};
  }

  /**
   * Initialize an `Arguments` object with the nodes
   * from the given `expr`.
   *
   * @param {Expression} expr
   * @return {Arguments}
   * @api public
   */

  static fromExpression(expr) {
    var args = new Arguments
      , len = expr.nodes.length;
    args.lineno = expr.lineno;
    args.column = expr.column;
    args.isList = expr.isList;
    for (var i = 0; i < len; ++i) {
      args.push(expr.nodes[i]);
    }
    return args;
  };

  /**
   * Return a clone of this node.
   *
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = super.clone(parent);
    clone.map = {};
    for (var key in this.map) {
      clone.map[key] = this.map[key].clone(parent, clone);
    }
    clone.isList = this.isList;
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Arguments',
      map: this.map,
      isList: this.isList,
      preserve: this.preserve,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename,
      nodes: this.nodes
    };
  };

};




},{"../nodes":148}],130:[function(require,module,exports){
/*!
 * Stylus - @block
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Atblock extends Node {
  /**
   * Initialize a new `@block` node.
   *
   * @api public
   */

  constructor() {
    super();
  }

  /**
   * Return `block` nodes.
   */

  get nodes() {
    return this.block.nodes;
  }

  /**
   * Return a clone of this node.
   *
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Atblock;
    clone.block = this.block.clone(parent, clone);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return @block.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return '@block';
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Atblock',
      block: this.block,
      lineno: this.lineno,
      column: this.column,
      fileno: this.fileno
    };
  };
};

},{"./node":154}],131:[function(require,module,exports){
/*!
 * Stylus - at-rule
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Atrule extends Node {
  /**
   * Initialize a new at-rule node.
   *
   * @param {String} type
   * @api public
   */

  constructor(type) {
    super()
    this.type = type;
  }

  /**
   * Check if at-rule's block has only properties.
   *
   * @return {Boolean}
   * @api public
   */

  get hasOnlyProperties() {
    if (!this.block) return false;

    var nodes = this.block.nodes;
    for (var i = 0, len = nodes.length; i < len; ++i) {
      var nodeName = nodes[i].nodeName;
      switch (nodes[i].nodeName) {
        case 'property':
        case 'expression':
        case 'comment':
          continue;
        default:
          return false;
      }
    }
    return true;
  }

  /**
   * Return a clone of this node.
   *
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Atrule(this.type);
    if (this.block) clone.block = this.block.clone(parent, clone);
    clone.segments = this.segments.map(function (node) { return node.clone(parent, clone); });
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    var json = {
      __type: 'Atrule',
      type: this.type,
      segments: this.segments,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
    if (this.block) json.block = this.block;
    return json;
  };

  /**
   * Return @<type>.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return '@' + this.type;
  };

  /**
   * Check if the at-rule's block has output nodes.
   *
   * @return {Boolean}
   * @api public
   */

  get hasOutput() {
    return !!this.block && hasOutput(this.block);
  };
};

function hasOutput(block) {
  var nodes = block.nodes;

  // only placeholder selectors
  if (nodes.every(function (node) {
    return 'group' == node.nodeName && node.hasOnlyPlaceholders;
  })) return false;

  // something visible
  return nodes.some(function (node) {
    switch (node.nodeName) {
      case 'property':
      case 'literal':
      case 'import':
        return true;
      case 'block':
        return hasOutput(node);
      default:
        if (node.block) return hasOutput(node.block);
    }
  });
}

},{"./node":154}],132:[function(require,module,exports){

/*!
 * Stylus - BinOp
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class BinOp extends Node {
  /**
   * Initialize a new `BinOp` with `op`, `left` and `right`.
   *
   * @param {String} op
   * @param {Node} left
   * @param {Node} right
   * @api public
   */

  constructor(op, left, right) {
    super();
    this.op = op;
    this.left = left;
    this.right = right;
  }

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new BinOp(this.op);
    clone.left = this.left.clone(parent, clone);
    clone.right = this.right && this.right.clone(parent, clone);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    if (this.val) clone.val = this.val.clone(parent, clone);
    return clone;
  };

  /**
   * Return <left> <op> <right>
   *
   * @return {String}
   * @api public
   */
  toString() {
    return this.left.toString() + ' ' + this.op + ' ' + this.right.toString();
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    var json = {
      __type: 'BinOp',
      left: this.left,
      right: this.right,
      op: this.op,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
    if (this.val) json.val = this.val;
    return json;
  };

};

},{"./node":154}],133:[function(require,module,exports){

/*!
 * Stylus - Block
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Block extends Node {
  /**
   * Initialize a new `Block` node with `parent` Block.
   *
   * @param {Block} parent
   * @api public
   */

  constructor(parent, node) {
    super();
    this.nodes = [];
    this.parent = parent;
    this.node = node;
    this.scope = true;
  }

  /**
   * Check if this block has properties..
   *
   * @return {Boolean}
   * @api public
   */

  get hasProperties() {
    for (var i = 0, len = this.nodes.length; i < len; ++i) {
      if ('property' == this.nodes[i].nodeName) {
        return true;
      }
    }
  };

  /**
   * Check if this block has @media nodes.
   *
   * @return {Boolean}
   * @api public
   */

  get hasMedia() {
    for (var i = 0, len = this.nodes.length; i < len; ++i) {
      var nodeName = this.nodes[i].nodeName;
      if ('media' == nodeName) {
        return true;
      }
    }
    return false;
  };

  /**
   * Check if this block is empty.
   *
   * @return {Boolean}
   * @api public
   */

  get isEmpty() {
    return !this.nodes.length || this.nodes.every(function (n) { return n.nodeName == 'comment' });
  };

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent, node) {
    parent = parent || this.parent;
    var clone = new Block(parent, node || this.node);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    clone.scope = this.scope;
    this.nodes.forEach(function (node) {
      clone.push(node.clone(clone, clone));
    });
    return clone;
  };

  /**
   * Push a `node` to this block.
   *
   * @param {Node} node
   * @api public
   */

  push(node) {
    this.nodes.push(node);
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Block',
      // parent: this.parent,
      // node: this.node,
      scope: this.scope,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename,
      nodes: this.nodes
    };
  };

};

},{"./node":154}],134:[function(require,module,exports){

/*!
 * Stylus - Boolean
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node')
  , nodes = require('./');

module.exports = class Boolean extends Node {
  /**
   * Initialize a new `Boolean` node with the given `val`.
   *
   * @param {Boolean} val
   * @api public
   */

  constructor(val) {
    super();
    if (this.nodeName) {
      this.val = !!val;
    } else {
      return new Boolean(val);
    }
  }

  /**
   * Return `this` node.
   *
   * @return {Boolean}
   * @api public
   */

  toBoolean() {
    return this;
  };

  /**
   * Return `true` if this node represents `true`.
   *
   * @return {Boolean}
   * @api public
   */

  get isTrue() {
    return this.val;
  };

  /**
   * Return `true` if this node represents `false`.
   *
   * @return {Boolean}
   * @api public
   */

  get isFalse() {
    return !this.val;
  };

  /**
   * Negate the value.
   *
   * @return {Boolean}
   * @api public
   */

  negate() {
    return new Boolean(!this.val);
  };

  /**
   * Return 'Boolean'.
   *
   * @return {String}
   * @api public
   */

  inspect() {
    return '[Boolean ' + this.val + ']';
  };

  /**
   * Return 'true' or 'false'.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return this.val
      ? 'true'
      : 'false';
  };

  /**
   * Return a JSON representaiton of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Boolean',
      val: this.val
    };
  };
};

},{"./":148,"./node":154}],135:[function(require,module,exports){

/*!
 * Stylus - Call
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Call extends Node {
  /**
   * Initialize a new `Call` with `name` and `args`.
   *
   * @param {String} name
   * @param {Expression} args
   * @api public
   */

  constructor(name, args) {
    super();
    this.name = name;
    this.args = args;
  }

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Call(this.name);
    clone.args = this.args.clone(parent, clone);
    if (this.block) clone.block = this.block.clone(parent, clone);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return <name>(param1, param2, ...).
   *
   * @return {String}
   * @api public
   */

  toString() {
    var args = this.args.nodes.map(function (node) {
      var str = node.toString();
      return str.slice(1, str.length - 1);
    }).join(', ');

    return this.name + '(' + args + ')';
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    var json = {
      __type: 'Call',
      name: this.name,
      args: this.args,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
    if (this.block) json.block = this.block;
    return json;
  };
};

},{"./node":154}],136:[function(require,module,exports){

/*!
 * Stylus - Charset
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Charset extends Node {
  /**
   * Initialize a new `Charset` with the given `val`
   *
   * @param {String} val
   * @api public
   */

  constructor(val) {
    super();
    this.val = val;
  }

  /**
   * Return @charset "val".
   *
   * @return {String}
   * @api public
   */

  toString() {
    return '@charset ' + this.val;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Charset',
      val: this.val,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

};

},{"./node":154}],137:[function(require,module,exports){

/*!
 * Stylus - Comment
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Comment extends Node {
  /**
   * Initialize a new `Comment` with the given `str`.
   *
   * @param {String} str
   * @param {Boolean} suppress
   * @param {Boolean} inline
   * @api public
   */

  constructor(str, suppress, inline) {
    super();
    this.str = str;
    this.suppress = suppress;
    this.inline = inline;
  }

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Comment',
      str: this.str,
      suppress: this.suppress,
      inline: this.inline,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

  /**
   * Return comment.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return this.str;
  };

};

},{"./node":154}],138:[function(require,module,exports){

/*!
 * Stylus - Each
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node')
  , nodes = require('./');

module.exports = class Each extends Node {
  /**
   * Initialize a new `Each` node with the given `val` name,
   * `key` name, `expr`, and `block`.
   *
   * @param {String} val
   * @param {String} key
   * @param {Expression} expr
   * @param {Block} block
   * @api public
   */

  constructor(val, key, expr, block) {
    super();
    this.val = val;
    this.key = key;
    this.expr = expr;
    this.block = block;
  }

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Each(this.val, this.key);
    clone.expr = this.expr.clone(parent, clone);
    clone.block = this.block.clone(parent, clone);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Each',
      val: this.val,
      key: this.key,
      expr: this.expr,
      block: this.block,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

}

},{"./":148,"./node":154}],139:[function(require,module,exports){

/*!
 * Stylus - Expression
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node')
  , nodes = require('../nodes')
  , utils = require('../utils');

module.exports = class Expression extends Node {
  /**
   * Initialize a new `Expression`.
   *
   * @param {Boolean} isList
   * @api public
   */

  constructor(isList) {
    super();
    this.nodes = [];
    this.isList = isList;
  }

  /**
   * Check if the variable has a value.
   *
   * @return {Boolean}
   * @api public
   */

  get isEmpty() {
    return !this.nodes.length;
  };

  /**
   * Return the first node in this expression.
   *
   * @return {Node}
   * @api public
   */

  get first() {
    return this.nodes[0]
      ? this.nodes[0].first
      : nodes.null;
  };

  /**
   * Hash all the nodes in order.
   *
   * @return {String}
   * @api public
   */

  get hash() {
    return this.nodes.map(function (node) {
      return node.hash;
    }).join('::');
  };

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new this.constructor(this.isList);
    clone.preserve = this.preserve;
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    clone.nodes = this.nodes.map(function (node) {
      return node.clone(parent, clone);
    });
    return clone;
  };

  /**
   * Push the given `node`.
   *
   * @param {Node} node
   * @api public
   */

  push(node) {
    this.nodes.push(node);
  };

  /**
   * Operate on `right` with the given `op`.
   *
   * @param {String} op
   * @param {Node} right
   * @return {Node}
   * @api public
   */

  operate(op, right, val) {
    switch (op) {
      case '[]=':
        var self = this
          , range = utils.unwrap(right).nodes
          , val = utils.unwrap(val)
          , len
          , node;
        range.forEach(function (unit) {
          len = self.nodes.length;
          if ('unit' == unit.nodeName) {
            var i = unit.val < 0 ? len + unit.val : unit.val
              , n = i;
            while (i-- > len) self.nodes[i] = nodes.null;
            self.nodes[n] = val;
          } else if (unit.string) {
            node = self.nodes[0];
            if (node && 'object' == node.nodeName) node.set(unit.string, val.clone());
          }
        });
        return val;
      case '[]':
        var expr = new nodes.Expression
          , vals = utils.unwrap(this).nodes
          , range = utils.unwrap(right).nodes
          , node;
        range.forEach(function (unit) {
          if ('unit' == unit.nodeName) {
            node = vals[unit.val < 0 ? vals.length + unit.val : unit.val];
          } else if ('object' == vals[0].nodeName) {
            node = vals[0].get(unit.string);
          }
          if (node) expr.push(node);
        });
        return expr.isEmpty
          ? nodes.null
          : utils.unwrap(expr);
      case '||':
        return this.toBoolean().isTrue
          ? this
          : right;
      case 'in':
        return super.operate(op, right);
      case '!=':
        return this.operate('==', right, val).negate();
      case '==':
        var len = this.nodes.length
          , right = right.toExpression()
          , a
          , b;
        if (len != right.nodes.length) return nodes.false;
        for (var i = 0; i < len; ++i) {
          a = this.nodes[i];
          b = right.nodes[i];
          if (a.operate(op, b).isTrue) continue;
          return nodes.false;
        }
        return nodes.true;
        break;
      default:
        return this.first.operate(op, right, val);
    }
  };

  /**
   * Expressions with length > 1 are truthy,
   * otherwise the first value's toBoolean()
   * method is invoked.
   *
   * @return {Boolean}
   * @api public
   */

  toBoolean() {
    if (this.nodes.length > 1) return nodes.true;
    return this.first.toBoolean();
  };

  /**
   * Return "<a> <b> <c>" or "<a>, <b>, <c>" if
   * the expression represents a list.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return '(' + this.nodes.map(function (node) {
      return node.toString();
    }).join(this.isList ? ', ' : ' ') + ')';
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Expression',
      isList: this.isList,
      preserve: this.preserve,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename,
      nodes: this.nodes
    };
  };
};

},{"../nodes":148,"../utils":178,"./node":154}],140:[function(require,module,exports){

/*!
 * Stylus - Extend
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Extend extends Node {
  /**
   * Initialize a new `Extend` with the given `selectors` array.
   *
   * @param {Array} selectors array of the selectors
   * @api public
   */

  constructor(selectors) {
    super();
    this.selectors = selectors;
  }

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone() {
    return new Extend(this.selectors);
  };

  /**
   * Return `@extend selectors`.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return '@extend ' + this.selectors.join(', ');
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Extend',
      selectors: this.selectors,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

};
},{"./node":154}],141:[function(require,module,exports){

/*!
 * Stylus - Feature
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Feature extends Node {
  /**
   * Initialize a new `Feature` with the given `segs`.
   *
   * @param {Array} segs
   * @api public
   */

  constructor(segs) {
    super();
    this.segments = segs;
    this.expr = null;
  }

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Feature;
    clone.segments = this.segments.map(function (node) { return node.clone(parent, clone); });
    if (this.expr) clone.expr = this.expr.clone(parent, clone);
    if (this.name) clone.name = this.name;
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return "<ident>" or "(<ident>: <expr>)"
   *
   * @return {String}
   * @api public
   */

  toString() {
    if (this.expr) {
      return '(' + this.segments.join('') + ': ' + this.expr.toString() + ')';
    } else {
      return this.segments.join('');
    }
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    var json = {
      __type: 'Feature',
      segments: this.segments,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
    if (this.expr) json.expr = this.expr;
    if (this.name) json.name = this.name;
    return json;
  };
};

},{"./node":154}],142:[function(require,module,exports){

/*!
 * Stylus - Function
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Function extends Node {
  /**
   * Initialize a new `Function` with `name`, `params`, and `body`.
   *
   * @param {String} name
   * @param {Params|Function} params
   * @param {Block} body
   * @api public
   */

  constructor(name, params, body) {
    super();
    this.name = name;
    this.params = params;
    this.block = body;
    if ('function' == typeof params) this.fn = params;
  }

  /**
   * Check function arity.
   *
   * @return {Boolean}
   * @api public
   */

  get arity() {
    return this.params.length;
  };

  /**
   * Return hash.
   *
   * @return {String}
   * @api public
   */

  get hash() {
    return 'function ' + this.name;
  };

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    if (this.fn) {
      var clone = new Function(
        this.name
        , this.fn);
    } else {
      var clone = new Function(this.name);
      clone.params = this.params.clone(parent, clone);
      clone.block = this.block.clone(parent, clone);
    }
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return <name>(param1, param2, ...).
   *
   * @return {String}
   * @api public
   */

  toString() {
    if (this.fn) {
      return this.name
        + '('
        + this.fn.toString()
          .match(/^function *\w*\((.*?)\)/)
          .slice(1)
          .join(', ')
        + ')';
    } else {
      return this.name
        + '('
        + this.params.nodes.join(', ')
        + ')';
    }
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    var json = {
      __type: 'Function',
      name: this.name,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
    if (this.fn) {
      json.fn = this.fn;
    } else {
      json.params = this.params;
      json.block = this.block;
    }
    return json;
  };

};

},{"./node":154}],143:[function(require,module,exports){

/*!
 * Stylus - Group
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Group extends Node {
  /**
   * Initialize a new `Group`.
   *
   * @api public
   */

  constructor() {
    super();
    this.nodes = [];
    this.extends = [];
  }

  /**
   * Push the given `selector` node.
   *
   * @param {Selector} selector
   * @api public
   */

  push(selector) {
    this.nodes.push(selector);
  };

  /**
   * Return this set's `Block`.
   */

  get block() {
    return this.nodes[0].block;
  };

  /**
   * Assign `block` to each selector in this set.
   *
   * @param {Block} block
   * @api public
   */

  set block(block) {
    for (var i = 0, len = this.nodes.length; i < len; ++i) {
      this.nodes[i].block = block;
    }
  };

  /**
   * Check if this set has only placeholders.
   *
   * @return {Boolean}
   * @api public
   */

  get hasOnlyPlaceholders() {
    return this.nodes.every(function (selector) { return selector.isPlaceholder; });
  };

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Group;
    clone.lineno = this.lineno;
    clone.column = this.column;
    this.nodes.forEach(function (node) {
      clone.push(node.clone(parent, clone));
    });
    clone.filename = this.filename;
    clone.block = this.block.clone(parent, clone);
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Group',
      nodes: this.nodes,
      block: this.block,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };
};

},{"./node":154}],144:[function(require,module,exports){

/*!
 * Stylus - HSLA
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node')
  , nodes = require('./');

/**
 * Initialize a new `HSLA` with the given h,s,l,a component values.
 *
 * @param {Number} h
 * @param {Number} s
 * @param {Number} l
 * @param {Number} a
 * @api public
 */

exports = module.exports = class HSLA extends Node {
  constructor(h, s, l, a) {
    super();
    this.h = clampDegrees(h);
    this.s = clampPercentage(s);
    this.l = clampPercentage(l);
    this.a = clampAlpha(a);
    this.hsla = this;
  }

  /**
   * Return hsla(n,n,n,n).
   *
   * @return {String}
   * @api public
   */

  toString() {
    return 'hsla('
      + this.h + ','
      + this.s.toFixed(0) + '%,'
      + this.l.toFixed(0) + '%,'
      + this.a + ')';
  };

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new HSLA(
      this.h
      , this.s
      , this.l
      , this.a);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'HSLA',
      h: this.h,
      s: this.s,
      l: this.l,
      a: this.a,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

  /**
   * Return rgba `RGBA` representation.
   *
   * @return {RGBA}
   * @api public
   */

  get rgba() {
    return nodes.RGBA.fromHSLA(this);
  };

  /**
   * Return hash.
   *
   * @return {String}
   * @api public
   */

  get hash() {
    return this.rgba.toString();
  };

  /**
   * Add h,s,l to the current component values.
   *
   * @param {Number} h
   * @param {Number} s
   * @param {Number} l
   * @return {HSLA} new node
   * @api public
   */

  add(h, s, l) {
    return new HSLA(
      this.h + h
      , this.s + s
      , this.l + l
      , this.a);
  };

  /**
   * Subtract h,s,l from the current component values.
   *
   * @param {Number} h
   * @param {Number} s
   * @param {Number} l
   * @return {HSLA} new node
   * @api public
   */

  sub(h, s, l) {
    return this.add(-h, -s, -l);
  };

  /**
   * Operate on `right` with the given `op`.
   *
   * @param {String} op
   * @param {Node} right
   * @return {Node}
   * @api public
   */

  operate(op, right) {
    switch (op) {
      case '==':
      case '!=':
      case '<=':
      case '>=':
      case '<':
      case '>':
      case 'is a':
      case '||':
      case '&&':
        return this.rgba.operate(op, right);
      default:
        return this.rgba.operate(op, right).hsla;
    }
  };


  /**
   * Adjust lightness by `percent`.
   *
   * @param {Number} percent
   * @return {HSLA} for chaining
   * @api public
   */

  adjustLightness(percent) {
    this.l = clampPercentage(this.l + this.l * (percent / 100));
    return this;
  };

  /**
   * Adjust hue by `deg`.
   *
   * @param {Number} deg
   * @return {HSLA} for chaining
   * @api public
   */

  adjustHue(deg) {
    this.h = clampDegrees(this.h + deg);
    return this;
  };


  /**
   * Return `HSLA` representation of the given `color`.
   *
   * @param {RGBA} color
   * @return {HSLA}
   * @api public
   */

  static fromRGBA(rgba) {
    var r = rgba.r / 255
      , g = rgba.g / 255
      , b = rgba.b / 255
      , a = rgba.a;

    var min = Math.min(r, g, b)
      , max = Math.max(r, g, b)
      , l = (max + min) / 2
      , d = max - min
      , h, s;

    switch (max) {
      case min: h = 0; break;
      case r: h = 60 * (g - b) / d; break;
      case g: h = 60 * (b - r) / d + 120; break;
      case b: h = 60 * (r - g) / d + 240; break;
    }

    if (max == min) {
      s = 0;
    } else if (l < .5) {
      s = d / (2 * l);
    } else {
      s = d / (2 - 2 * l);
    }

    h %= 360;
    s *= 100;
    l *= 100;

    return new HSLA(h, s, l, a);
  };
};

/**
 * Clamp degree `n` >= 0 and <= 360.
 *
 * @param {Number} n
 * @return {Number}
 * @api private
 */

function clampDegrees(n) {
  n = n % 360;
  return n >= 0 ? n : 360 + n;
}

/**
 * Clamp percentage `n` >= 0 and <= 100.
 *
 * @param {Number} n
 * @return {Number}
 * @api private
 */

function clampPercentage(n) {
  return Math.max(0, Math.min(n, 100));
}

/**
 * Clamp alpha `n` >= 0 and <= 1.
 *
 * @param {Number} n
 * @return {Number}
 * @api private
 */

function clampAlpha(n) {
  return Math.max(0, Math.min(n, 1));
}

},{"./":148,"./node":154}],145:[function(require,module,exports){

/*!
 * Stylus - Ident
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node')
  , nodes = require('./');

module.exports = class Ident extends Node {
  /**
   * Initialize a new `Ident` by `name` with the given `val` node.
   *
   * @param {String} name
   * @param {Node} val
   * @api public
   */

  constructor(name, val, mixin) {
    super();
    this.name = name;
    this.string = name;
    this.val = val || nodes.null;
    this.mixin = !!mixin;
  }

  /**
   * Check if the variable has a value.
   *
   * @return {Boolean}
   * @api public
   */

  get isEmpty() {
    return undefined == this.val;
  };

  /**
   * Return hash.
   *
   * @return {String}
   * @api public
   */

  get hash() {
    return this.name;
  };

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Ident(this.name);
    clone.val = this.val.clone(parent, clone);
    clone.mixin = this.mixin;
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    clone.property = this.property;
    clone.rest = this.rest;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Ident',
      name: this.name,
      val: this.val,
      mixin: this.mixin,
      property: this.property,
      rest: this.rest,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

  /**
   * Return <name>.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return this.name;
  };

  /**
   * Coerce `other` to an ident.
   *
   * @param {Node} other
   * @return {String}
   * @api public
   */

  coerce(other) {
    switch (other.nodeName) {
      case 'ident':
      case 'string':
      case 'literal':
        return new Ident(other.string);
      case 'unit':
        return new Ident(other.toString());
      default:
        return super.coerce(other);
    }
  };

  /**
   * Operate on `right` with the given `op`.
   *
   * @param {String} op
   * @param {Node} right
   * @return {Node}
   * @api public
   */

  operate(op, right) {
    var val = right.first;
    switch (op) {
      case '-':
        if ('unit' == val.nodeName) {
          var expr = new nodes.Expression;
          val = val.clone();
          val.val = -val.val;
          expr.push(this);
          expr.push(val);
          return expr;
        }
      case '+':
        return new nodes.Ident(this.string + this.coerce(val).string);
    }
    return super.operate(op, right);
  };
};

},{"./":148,"./node":154}],146:[function(require,module,exports){

/*!
 * Stylus - If
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class If extends Node {
  /**
   * Initialize a new `If` with the given `cond`.
   *
   * @param {Expression} cond
   * @param {Boolean|Block} negate, block
   * @api public
   */

  constructor(cond, negate) {
    super();
    this.cond = cond;
    this.elses = [];
    if (negate && negate.nodeName) {
      this.block = negate;
    } else {
      this.negate = negate;
    }
  }

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new If();
    clone.cond = this.cond.clone(parent, clone);
    clone.block = this.block.clone(parent, clone);
    clone.elses = this.elses.map(function (node) { return node.clone(parent, clone); });
    clone.negate = this.negate;
    clone.postfix = this.postfix;
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'If',
      cond: this.cond,
      block: this.block,
      elses: this.elses,
      negate: this.negate,
      postfix: this.postfix,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };
};

},{"./node":154}],147:[function(require,module,exports){

/*!
 * Stylus - Import
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Import extends Node {
  /**
   * Initialize a new `Import` with the given `expr`.
   *
   * @param {Expression} expr
   * @api public
   */

  constructor(expr, once) {
    super();
    this.path = expr;
    this.once = once || false;
  }

  /**
   * Return a clone of this node.
   *
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Import();
    clone.path = this.path.nodeName ? this.path.clone(parent, clone) : this.path;
    clone.once = this.once;
    clone.mtime = this.mtime;
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Import',
      path: this.path,
      once: this.once,
      mtime: this.mtime,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

};

},{"./node":154}],148:[function(require,module,exports){

/*!
 * Stylus - nodes
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

exports.lineno = null;
exports.column = null;
exports.filename = null;

/**
 * Constructors
 */

exports.Node = require('./node');
exports.Root = require('./root');
exports.Null = require('./null');
exports.Each = require('./each');
exports.If = require('./if');
exports.Call = require('./call');
exports.UnaryOp = require('./unaryop');
exports.BinOp = require('./binop');
exports.Ternary = require('./ternary');
exports.Block = require('./block');
exports.Unit = require('./unit');
exports.String = require('./string');
exports.HSLA = require('./hsla');
exports.RGBA = require('./rgba');
exports.Ident = require('./ident');
exports.Group = require('./group');
exports.Literal = require('./literal');
exports.Boolean = require('./boolean');
exports.Return = require('./return');
exports.Media = require('./media');
exports.QueryList = require('./query-list');
exports.Query = require('./query');
exports.Feature = require('./feature');
exports.Params = require('./params');
exports.Comment = require('./comment');
exports.Keyframes = require('./keyframes');
exports.Member = require('./member');
exports.Charset = require('./charset');
exports.Namespace = require('./namespace');
exports.Import = require('./import');
exports.Extend = require('./extend');
exports.Object = require('./object');
exports.Function = require('./function');
exports.Property = require('./property');
exports.Selector = require('./selector');
exports.Expression = require('./expression');
exports.Arguments = require('./arguments');
exports.Atblock = require('./atblock');
exports.Atrule = require('./atrule');
exports.Supports = require('./supports');

/**
 * Singletons.
 */

exports.true = new exports.Boolean(true);
exports.false = new exports.Boolean(false);
exports.null = new exports.Null;

},{"./arguments":129,"./atblock":130,"./atrule":131,"./binop":132,"./block":133,"./boolean":134,"./call":135,"./charset":136,"./comment":137,"./each":138,"./expression":139,"./extend":140,"./feature":141,"./function":142,"./group":143,"./hsla":144,"./ident":145,"./if":146,"./import":147,"./keyframes":149,"./literal":150,"./media":151,"./member":152,"./namespace":153,"./node":154,"./null":155,"./object":156,"./params":157,"./property":158,"./query":160,"./query-list":159,"./return":161,"./rgba":162,"./root":163,"./selector":164,"./string":165,"./supports":166,"./ternary":167,"./unaryop":168,"./unit":169}],149:[function(require,module,exports){

/*!
 * Stylus - Keyframes
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Atrule = require('./atrule');

module.exports = class Keyframes extends Atrule {
  /**
   * Initialize a new `Keyframes` with the given `segs`,
   * and optional vendor `prefix`.
   *
   * @param {Array} segs
   * @param {String} prefix
   * @api public
   */

  constructor(segs, prefix) {
    super('keyframes')
    this.segments = segs;
    this.prefix = prefix || 'official';
  }

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Keyframes;
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    clone.segments = this.segments.map(function (node) { return node.clone(parent, clone); });
    clone.prefix = this.prefix;
    clone.block = this.block.clone(parent, clone);
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Keyframes',
      segments: this.segments,
      prefix: this.prefix,
      block: this.block,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

  /**
   * Return `@keyframes name`.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return '@keyframes ' + this.segments.join('');
  };

};
},{"./atrule":131}],150:[function(require,module,exports){

/*!
 * Stylus - Literal
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node')
  , nodes = require('./');

module.exports = class Literal extends Node {
  /**
   * Initialize a new `Literal` with the given `str`.
   *
   * @param {String} str
   * @api public
   */

  constructor(str) {
    super();
    this.val = str;
    this.string = str;
    this.prefixed = false;
  }

  /**
   * Return hash.
   *
   * @return {String}
   * @api public
   */

  get hash() {
    return this.val;
  };

  /**
   * Return literal value.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return this.val.toString();
  };

  /**
   * Coerce `other` to a literal.
   *
   * @param {Node} other
   * @return {String}
   * @api public
   */

  coerce(other) {
    switch (other.nodeName) {
      case 'ident':
      case 'string':
      case 'literal':
        return new Literal(other.string);
      default:
        return super.coerce(other);
    }
  };

  /**
   * Operate on `right` with the given `op`.
   *
   * @param {String} op
   * @param {Node} right
   * @return {Node}
   * @api public
   */

  operate(op, right) {
    var val = right.first;
    switch (op) {
      case '+':
        return new nodes.Literal(this.string + this.coerce(val).string);
      default:
        return super.operate(op, right);
    }
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Literal',
      val: this.val,
      string: this.string,
      prefixed: this.prefixed,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

};

},{"./":148,"./node":154}],151:[function(require,module,exports){

/*!
 * Stylus - Media
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Atrule = require('./atrule');

module.exports = class Media extends Atrule {
  /**
   * Initialize a new `Media` with the given `val`
   *
   * @param {String} val
   * @api public
   */

  constructor(val) {
    super('media');
    this.val = val;
  }

  /**
   * Clone this node.
   *
   * @return {Media}
   * @api public
   */

  clone(parent) {
    var clone = new Media;
    clone.val = this.val.clone(parent, clone);
    clone.block = this.block.clone(parent, clone);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Media',
      val: this.val,
      block: this.block,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

  /**
   * Return @media "val".
   *
   * @return {String}
   * @api public
   */

  toString() {
    return '@media ' + this.val;
  };
};

},{"./atrule":131}],152:[function(require,module,exports){

/*!
 * Stylus - Member
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Member extends Node {
  /**
   * Initialize a new `Member` with `left` and `right`.
   *
   * @param {Node} left
   * @param {Node} right
   * @api public
   */

  constructor(left, right) {
    super();
    this.left = left;
    this.right = right;
  }

  /**
   * Return a clone of this node.
   *
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Member;
    clone.left = this.left.clone(parent, clone);
    clone.right = this.right.clone(parent, clone);
    if (this.val) clone.val = this.val.clone(parent, clone);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    var json = {
      __type: 'Member',
      left: this.left,
      right: this.right,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
    if (this.val) json.val = this.val;
    return json;
  };

  /**
   * Return a string representation of this node.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return this.left.toString()
      + '.' + this.right.toString();
  };
};

},{"./node":154}],153:[function(require,module,exports){
/*!
 * Stylus - Namespace
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Namespace extends Node {
  /**
   * Initialize a new `Namespace` with the given `val` and `prefix`
   *
   * @param {String|Call} val
   * @param {String} [prefix]
   * @api public
   */

  constructor(val, prefix) {
    super();
    this.val = val;
    this.prefix = prefix;
  }

  /**
   * Return @namespace "val".
   *
   * @return {String}
   * @api public
   */

  toString() {
    return '@namespace ' + (this.prefix ? this.prefix + ' ' : '') + this.val;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Namespace',
      val: this.val,
      prefix: this.prefix,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };
};

},{"./node":154}],154:[function(require,module,exports){

/*!
 * Stylus - Node
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Evaluator = require('../visitor/evaluator')
  , utils = require('../utils')
  , nodes = require('./');

class CoercionError extends Error {
  /**
   * Initialize a new `CoercionError` with the given `msg`.
   *
   * @param {String} msg
   * @api private
   */

  constructor(msg) {
    super();
    this.name = 'CoercionError'
    this.message = msg
    if (Error.captureStackTrace) {
      Error.captureStackTrace(this, CoercionError);
    }
  }
}



module.exports = class Node {
  /**
   * Node constructor.
   *
   * @api public
   */

  constructor() {
    this.lineno = nodes.lineno || 1;
    this.column = nodes.column || 1;
    this.filename = nodes.filename;
  }

  /**
   * Return this node.
   *
   * @return {Node}
   * @api public
   */

  get first() {
    return this;
  }

  /**
   * Return hash.
   *
   * @return {String}
   * @api public
   */

  get hash() {
    return this.val;
  }

  /**
   * Return node name.
   *
   * @return {String}
   * @api public
   */

  get nodeName() {
    return this.constructor.name.toLowerCase();
  }

  /**
   * Return this node.
   * 
   * @return {Node}
   * @api public
   */

  clone() {
    return this;
  }

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  }

  /**
   * Nodes by default evaluate to themselves.
   *
   * @return {Node}
   * @api public
   */

  eval() {
    return new Evaluator(this).evaluate();
  }

  /**
   * Return true.
   *
   * @return {Boolean}
   * @api public
   */

  toBoolean() {
    return nodes.true;
  }

  /**
   * Return the expression, or wrap this node in an expression.
   *
   * @return {Expression}
   * @api public
   */

  toExpression() {
    if ('expression' == this.nodeName) return this;
    var expr = new nodes.Expression;
    expr.push(this);
    return expr;
  }

  /**
   * Return false if `op` is generally not coerced.
   *
   * @param {String} op
   * @return {Boolean}
   * @api private
   */

  shouldCoerce(op) {
    switch (op) {
      case 'is a':
      case 'in':
      case '||':
      case '&&':
        return false;
      default:
        return true;
    }
  }

  /**
   * Operate on `right` with the given `op`.
   *
   * @param {String} op
   * @param {Node} right
   * @return {Node}
   * @api public
   */

  operate(op, right) {
    switch (op) {
      case 'is a':
        if ('string' == right.first.nodeName) {
          return new nodes.Boolean(this.nodeName == right.val);
        } else {
          throw new Error('"is a" expects a string, got ' + right.toString());
        }
      case '==':
        return new nodes.Boolean(this.hash == right.hash);
      case '!=':
        return new nodes.Boolean(this.hash != right.hash);
      case '>=':
        return new nodes.Boolean(this.hash >= right.hash);
      case '<=':
        return new nodes.Boolean(this.hash <= right.hash);
      case '>':
        return new nodes.Boolean(this.hash > right.hash);
      case '<':
        return new nodes.Boolean(this.hash < right.hash);
      case '||':
        return this.toBoolean().isTrue
          ? this
          : right;
      case 'in':
        var vals = utils.unwrap(right).nodes
          , len = vals && vals.length
          , hash = this.hash;
        if (!vals) throw new Error('"in" given invalid right-hand operand, expecting an expression');

        // 'prop' in obj
        if (1 == len && 'object' == vals[0].nodeName) {
          return new nodes.Boolean(vals[0].has(this.hash));
        }

        for (var i = 0; i < len; ++i) {
          if (hash == vals[i].hash) {
            return nodes.true;
          }
        }
        return nodes.false;
      case '&&':
        var a = this.toBoolean()
          , b = right.toBoolean();
        return a.isTrue && b.isTrue
          ? right
          : a.isFalse
            ? this
            : right;
      default:
        if ('[]' == op) {
          var msg = 'cannot perform '
            + this
            + '[' + right + ']';
        } else {
          var msg = 'cannot perform'
            + ' ' + this
            + ' ' + op
            + ' ' + right;
        }
        throw new Error(msg);
    }
  }

  /**
   * Default coercion throws.
   *
   * @param {Node} other
   * @return {Node}
   * @api public
   */

  coerce(other) {
    if (other.nodeName == this.nodeName) return other;
    throw new CoercionError('cannot coerce ' + other + ' to ' + this.nodeName);
  }
};


},{"../utils":178,"../visitor/evaluator":181,"./":148}],155:[function(require,module,exports){

/*!
 * Stylus - Null
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node')
  , nodes = require('./');

/**
 * Initialize a new `Null` node.
 *
 * @api public
 */

module.exports = class Null extends Node {
  /**
 * Return 'Null'.
 *
 * @return {String}
 * @api public
 */

  toString() {
    return 'null';
  };

  inspect() {
    return 'null';
  }

  /**
  * Return false.
  *
  * @return {Boolean}
  * @api public
  */

  toBoolean() {
    return nodes.false;
  };

  /**
  * Check if the node is a null node.
  *
  * @return {Boolean}
  * @api public
  */

  get isNull() {
    return true;
  };

  /**
  * Return hash.
  *
  * @return {String}
  * @api public
  */

  get hash() {
    return null;
  };

  /**
  * Return a JSON representation of this node.
  *
  * @return {Object}
  * @api public
  */

  toJSON() {
    return {
      __type: 'Null',
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };
};

},{"./":148,"./node":154}],156:[function(require,module,exports){

/*!
 * Stylus - Object
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node')
  , nodes = require('./')
  , nativeObj = {}.constructor;

module.exports = class Object extends Node {
  /**
   * Initialize a new `Object`.
   *
   * @api public
   */

  constructor() {
    super();
    this.vals = {};
    this.keys = {};
  }

  /**
   * Set `key` to `val`.
   *
   * @param {String} key
   * @param {Node} val
   * @return {Object} for chaining
   * @api public
   */

  setValue(key, val) {
    this.vals[key] = val;
    return this;
  };

  /**
   * Alias for `setValue` for compatible API
   */

  get set() {
    return this.setValue;
  }

  /**
   * Set `key` to `val`.
   *
   * @param {String} key
   * @param {Node} val
   * @return {Object} for chaining
   * @api public
   */

  setKey(key, val) {
    this.keys[key] = val;
    return this;
  };

  /**
   * Return length.
   *
   * @return {Number}
   * @api public
   */

  get length() {
    return nativeObj.keys(this.vals).length;
  };

  /**
   * Get `key`.
   *
   * @param {String} key
   * @return {Node}
   * @api public
   */

  get(key) {
    return this.vals[key] || nodes.null;
  };

  /**
   * Has `key`?
   *
   * @param {String} key
   * @return {Boolean}
   * @api public
   */

  has(key) {
    return key in this.vals;
  };

  /**
   * Operate on `right` with the given `op`.
   *
   * @param {String} op
   * @param {Node} right
   * @return {Node}
   * @api public
   */

  operate(op, right) {
    switch (op) {
      case '.':
      case '[]':
        return this.get(right.hash);
      case '==':
        var vals = this.vals
          , a
          , b;
        if ('object' != right.nodeName || this.length != right.length)
          return nodes.false;
        for (var key in vals) {
          a = vals[key];
          b = right.vals[key];
          if (a.operate(op, b).isFalse)
            return nodes.false;
        }
        return nodes.true;
      case '!=':
        return this.operate('==', right).negate();
      default:
        return super.operate(op, right);
    }
  };

  /**
   * Return Boolean based on the length of this object.
   *
   * @return {Boolean}
   * @api public
   */

  toBoolean() {
    return new nodes.Boolean(this.length);
  };

  /**
   * Convert object to string with properties.
   *
   * @return {String}
   * @api private
   */

  toBlock() {
    var str = '{'
      , key
      , val;

    for (key in this.vals) {
      val = this.get(key);
      if ('object' == val.first.nodeName) {
        str += key + ' ' + val.first.toBlock();
      } else {
        switch (key) {
          case '@charset':
            str += key + ' ' + val.first.toString() + ';';
            break;
          default:
            str += key + ':' + toString(val) + ';';
        }
      }
    }

    str += '}';

    return str;

    function toString(node) {
      if (node.nodes) {
        return node.nodes.map(toString).join(node.isList ? ',' : ' ');
      } else if ('literal' == node.nodeName && ',' == node.val) {
        return '\\,';
      }
      return node.toString();
    }
  };

  /**
   * Return a clone of this node.
   *
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Object;
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;

    var key;
    for (key in this.vals) {
      clone.vals[key] = this.vals[key].clone(parent, clone);
    }

    for (key in this.keys) {
      clone.keys[key] = this.keys[key].clone(parent, clone);
    }

    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Object',
      vals: this.vals,
      keys: this.keys,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

  /**
   * Return "{ <prop>: <val> }"
   *
   * @return {String}
   * @api public
   */

  toString() {
    var obj = {};
    for (var prop in this.vals) {
      obj[prop] = this.vals[prop].toString();
    }
    return JSON.stringify(obj);
  };

};

},{"./":148,"./node":154}],157:[function(require,module,exports){

/*!
 * Stylus - Params
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Params extends Node {
  /**
   * Initialize a new `Params` with `name`, `params`, and `body`.
   *
   * @param {String} name
   * @param {Params} params
   * @param {Expression} body
   * @api public
   */

  constructor() {
    super();
    this.nodes = [];
  }

  /**
   * Check function arity.
   *
   * @return {Boolean}
   * @api public
   */

  get length() {
    return this.nodes.length;
  };

  /**
   * Push the given `node`.
   *
   * @param {Node} node
   * @api public
   */

  push(node) {
    this.nodes.push(node);
  };

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Params;
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    this.nodes.forEach(function (node) {
      clone.push(node.clone(parent, clone));
    });
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Params',
      nodes: this.nodes,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };
};

},{"./node":154}],158:[function(require,module,exports){

/*!
 * Stylus - Property
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Property extends Node {
  /**
   * Initialize a new `Property` with the given `segs` and optional `expr`.
   *
   * @param {Array} segs
   * @param {Expression} expr
   * @api public
   */

  constructor(segs, expr) {
    super();
    this.segments = segs;
    this.expr = expr;
  }

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Property(this.segments);
    clone.name = this.name;
    if (this.literal) clone.literal = this.literal;
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    clone.segments = this.segments.map(function (node) { return node.clone(parent, clone); });
    if (this.expr) clone.expr = this.expr.clone(parent, clone);
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    var json = {
      __type: 'Property',
      segments: this.segments,
      name: this.name,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
    if (this.expr) json.expr = this.expr;
    if (this.literal) json.literal = this.literal;
    return json;
  };

  /**
   * Return string representation of this node.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return 'property(' + this.segments.join('') + ', ' + this.expr + ')';
  };

  /**
   * Operate on the property expression.
   *
   * @param {String} op
   * @param {Node} right
   * @return {Node}
   * @api public
   */

  operate(op, right, val) {
    return this.expr.operate(op, right, val);
  };
};

},{"./node":154}],159:[function(require,module,exports){

/*!
 * Stylus - QueryList
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class QueryList extends Node {
  /**
   * Initialize a new `QueryList`.
   *
   * @api public
   */

  constructor() {
    super();
    this.nodes = [];
  }

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new QueryList;
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    for (var i = 0; i < this.nodes.length; ++i) {
      clone.push(this.nodes[i].clone(parent, clone));
    }
    return clone;
  };

  /**
   * Push the given `node`.
   *
   * @param {Node} node
   * @api public
   */

  push(node) {
    this.nodes.push(node);
  };

  /**
   * Merges this query list with the `other`.
   *
   * @param {QueryList} other
   * @return {QueryList}
   * @api private
   */

  merge(other) {
    var list = new QueryList
      , merged;
    this.nodes.forEach(function (query) {
      for (var i = 0, len = other.nodes.length; i < len; ++i) {
        merged = query.merge(other.nodes[i]);
        if (merged) list.push(merged);
      }
    });
    return list;
  };

  /**
   * Return "<a>, <b>, <c>"
   *
   * @return {String}
   * @api public
   */

  toString() {
    return '(' + this.nodes.map(function (node) {
      return node.toString();
    }).join(', ') + ')';
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'QueryList',
      nodes: this.nodes,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

};

},{"./node":154}],160:[function(require,module,exports){

/*!
 * Stylus - Query
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Query extends Node {
  /**
   * Initialize a new `Query`.
   *
   * @api public
   */

  constructor() {
    super();
    this.nodes = [];
    this.type = '';
    this.predicate = '';
  }

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Query;
    clone.predicate = this.predicate;
    clone.type = this.type;
    for (var i = 0, len = this.nodes.length; i < len; ++i) {
      clone.push(this.nodes[i].clone(parent, clone));
    }
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Push the given `feature`.
   *
   * @param {Feature} feature
   * @api public
   */

  push(feature) {
    this.nodes.push(feature);
  };

  /**
   * Return resolved type of this query.
   *
   * @return {String}
   * @api private
   */

  get resolvedType() {
    if (this.type) {
      return this.type.nodeName
        ? this.type.string
        : this.type;
    }
  };

  /**
   * Return resolved predicate of this query.
   *
   * @return {String}
   * @api private
   */

  get resolvedPredicate() {
    if (this.predicate) {
      return this.predicate.nodeName
        ? this.predicate.string
        : this.predicate;
    }
  };

  /**
   * Merges this query with the `other`.
   *
   * @param {Query} other
   * @return {Query}
   * @api private
   */

  merge(other) {
    var query = new Query
      , p1 = this.resolvedPredicate
      , p2 = other.resolvedPredicate
      , t1 = this.resolvedType
      , t2 = other.resolvedType
      , type, pred;

    // Stolen from Sass :D
    t1 = t1 || t2;
    t2 = t2 || t1;
    if (('not' == p1) ^ ('not' == p2)) {
      if (t1 == t2) return;
      type = ('not' == p1) ? t2 : t1;
      pred = ('not' == p1) ? p2 : p1;
    } else if (('not' == p1) && ('not' == p2)) {
      if (t1 != t2) return;
      type = t1;
      pred = 'not';
    } else if (t1 != t2) {
      return;
    } else {
      type = t1;
      pred = p1 || p2;
    }
    query.predicate = pred;
    query.type = type;
    query.nodes = this.nodes.concat(other.nodes);
    return query;
  };

  /**
   * Return "<a> and <b> and <c>"
   *
   * @return {String}
   * @api public
   */

  toString() {
    var pred = this.predicate ? this.predicate + ' ' : ''
      , type = this.type || ''
      , len = this.nodes.length
      , str = pred + type;
    if (len) {
      str += (type && ' and ') + this.nodes.map(function (expr) {
        return expr.toString();
      }).join(' and ');
    }
    return str;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Query',
      predicate: this.predicate,
      type: this.type,
      nodes: this.nodes,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };
};

},{"./node":154}],161:[function(require,module,exports){

/*!
 * Stylus - Return
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node')
  , nodes = require('./');

/**
 * Initialize a new `Return` node with the given `expr`.
 *
 * @param {Expression} expr
 * @api public
 */

module.exports = class Return extends Node {
  constructor(expr) {
    super();
    this.expr = expr || nodes.null;
  };

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Return();
    clone.expr = this.expr.clone(parent, clone);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Return',
      expr: this.expr,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };
};

},{"./":148,"./node":154}],162:[function(require,module,exports){

/*!
 * Stylus - RGBA
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node')
  , HSLA = require('./hsla')
  , functions = require('../functions')
  , adjust = functions.adjust
  , nodes = require('./');

exports = module.exports = class RGBA extends Node {
  /**
   * Initialize a new `RGBA` with the given r,g,b,a component values.
   *
   * @param {Number} r
   * @param {Number} g
   * @param {Number} b
   * @param {Number} a
   * @api public
   */

  constructor(r, g, b, a) {
    super();
    this.r = clamp(r);
    this.g = clamp(g);
    this.b = clamp(b);
    this.a = clampAlpha(a);
    this.name = '';
    this.rgba = this;
  }

  /**
   * Return an `RGBA` without clamping values.
   * 
   * @param {Number} r
   * @param {Number} g
   * @param {Number} b
   * @param {Number} a
   * @return {RGBA}
   * @api public
   */

  static withoutClamping(r, g, b, a) {
    var rgba = new RGBA(0, 0, 0, 0);
    rgba.r = r;
    rgba.g = g;
    rgba.b = b;
    rgba.a = a;
    return rgba;
  };

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone() {
    var clone = new RGBA(
      this.r
      , this.g
      , this.b
      , this.a);
    clone.raw = this.raw;
    clone.name = this.name;
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'RGBA',
      r: this.r,
      g: this.g,
      b: this.b,
      a: this.a,
      raw: this.raw,
      name: this.name,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

  /**
   * Return true.
   *
   * @return {Boolean}
   * @api public
   */

  toBoolean() {
    return nodes.true;
  };

  /**
   * Return `HSLA` representation.
   *
   * @return {HSLA}
   * @api public
   */

  get hsla() {
    return HSLA.fromRGBA(this);
  };

  /**
   * Return hash.
   *
   * @return {String}
   * @api public
   */

  get hash() {
    return this.toString();
  };

  /**
   * Add r,g,b,a to the current component values.
   *
   * @param {Number} r
   * @param {Number} g
   * @param {Number} b
   * @param {Number} a
   * @return {RGBA} new node
   * @api public
   */

  add(r, g, b, a) {
    return new RGBA(
      this.r + r
      , this.g + g
      , this.b + b
      , this.a + a);
  };

  /**
   * Subtract r,g,b,a from the current component values.
   *
   * @param {Number} r
   * @param {Number} g
   * @param {Number} b
   * @param {Number} a
   * @return {RGBA} new node
   * @api public
   */

  sub(r, g, b, a) {
    return new RGBA(
      this.r - r
      , this.g - g
      , this.b - b
      , a == 1 ? this.a : this.a - a);
  };

  /**
   * Multiply rgb components by `n`.
   *
   * @param {String} n
   * @return {RGBA} new node
   * @api public
   */

  multiply(n) {
    return new RGBA(
      this.r * n
      , this.g * n
      , this.b * n
      , this.a);
  };

  /**
   * Divide rgb components by `n`.
   *
   * @param {String} n
   * @return {RGBA} new node
   * @api public
   */

  divide(n) {
    return new RGBA(
      this.r / n
      , this.g / n
      , this.b / n
      , this.a);
  };

  /**
   * Operate on `right` with the given `op`.
   *
   * @param {String} op
   * @param {Node} right
   * @return {Node}
   * @api public
   */

  operate(op, right) {
    if ('in' != op) right = right.first

    switch (op) {
      case 'is a':
        if ('string' == right.nodeName && 'color' == right.string) {
          return nodes.true;
        }
        break;
      case '+':
        switch (right.nodeName) {
          case 'unit':
            var n = right.val;
            switch (right.type) {
              case '%': return adjust(this, new nodes.String('lightness'), right);
              case 'deg': return this.hsla.adjustHue(n).rgba;
              default: return this.add(n, n, n, 0);
            }
          case 'rgba':
            return this.add(right.r, right.g, right.b, right.a);
          case 'hsla':
            return this.hsla.add(right.h, right.s, right.l);
        }
        break;
      case '-':
        switch (right.nodeName) {
          case 'unit':
            var n = right.val;
            switch (right.type) {
              case '%': return adjust(this, new nodes.String('lightness'), new nodes.Unit(-n, '%'));
              case 'deg': return this.hsla.adjustHue(-n).rgba;
              default: return this.sub(n, n, n, 0);
            }
          case 'rgba':
            return this.sub(right.r, right.g, right.b, right.a);
          case 'hsla':
            return this.hsla.sub(right.h, right.s, right.l);
        }
        break;
      case '*':
        switch (right.nodeName) {
          case 'unit':
            return this.multiply(right.val);
        }
        break;
      case '/':
        switch (right.nodeName) {
          case 'unit':
            return this.divide(right.val);
        }
        break;
    }
    return super.operate(op, right);
  };

  /**
   * Return #nnnnnn, #nnn, or rgba(n,n,n,n) string representation of the color.
   *
   * @return {String}
   * @api public
   */

  toString() {
    function pad(n) {
      return n < 16
        ? '0' + n.toString(16)
        : n.toString(16);
    }

    // special case for transparent named color
    if ('transparent' == this.name)
      return this.name;

    if (1 == this.a) {
      var r = pad(this.r)
        , g = pad(this.g)
        , b = pad(this.b);

      // Compress
      if (r[0] == r[1] && g[0] == g[1] && b[0] == b[1]) {
        return '#' + r[0] + g[0] + b[0];
      } else {
        return '#' + r + g + b;
      }
    } else {
      return 'rgba('
        + this.r + ','
        + this.g + ','
        + this.b + ','
        + (+this.a.toFixed(3)) + ')';
    }
  };

  /**
  * Return a `RGBA` from the given `hsla`.
  *
  * @param {HSLA} hsla
  * @return {RGBA}
  * @api public
  */

  static fromHSLA(hsla) {
    var h = hsla.h / 360
      , s = hsla.s / 100
      , l = hsla.l / 100
      , a = hsla.a;

    var m2 = l <= .5 ? l * (s + 1) : l + s - l * s
      , m1 = l * 2 - m2;

    var r = hue(h + 1 / 3) * 0xff
      , g = hue(h) * 0xff
      , b = hue(h - 1 / 3) * 0xff;

    function hue(h) {
      if (h < 0) ++h;
      if (h > 1) --h;
      if (h * 6 < 1) return m1 + (m2 - m1) * h * 6;
      if (h * 2 < 1) return m2;
      if (h * 3 < 2) return m1 + (m2 - m1) * (2 / 3 - h) * 6;
      return m1;
    }


    return new RGBA(r, g, b, a);
  };
};

/**
 * Clamp `n` >= 0 and <= 255.
 *
 * @param {Number} n
 * @return {Number}
 * @api private
 */

function clamp(n) {
  return Math.max(0, Math.min(n.toFixed(0), 255));
}

/**
 * Clamp alpha `n` >= 0 and <= 1.
 *
 * @param {Number} n
 * @return {Number}
 * @api private
 */

function clampAlpha(n) {
  return Math.max(0, Math.min(n, 1));
}

},{"../functions":88,"./":148,"./hsla":144,"./node":154}],163:[function(require,module,exports){

/*!
 * Stylus - Root
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Root extends Node {
  /**
   * Initialize a new `Root` node.
   *
   * @api public
   */

  constructor() {
    super();
    this.nodes = [];
  }

  /**
   * Push a `node` to this block.
   *
   * @param {Node} node
   * @api public
   */

  push(node) {
    this.nodes.push(node);
  };

  /**
   * Unshift a `node` to this block.
   *
   * @param {Node} node
   * @api public
   */

  unshift(node) {
    this.nodes.unshift(node);
  };

  /**
   * Return a clone of this node.
   *
   * @return {Node}
   * @api public
   */

  clone() {
    var clone = new Root();
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    this.nodes.forEach(function (node) {
      clone.push(node.clone(clone, clone));
    });
    return clone;
  };

  /**
   * Return "root".
   *
   * @return {String}
   * @api public
   */

  toString() {
    return '[Root]';
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Root',
      nodes: this.nodes,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

};

},{"./node":154}],164:[function(require,module,exports){

/*!
 * Stylus - Selector
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Block = require('./block')
  , Node = require('./node');

module.exports = class Selector extends Node {
  /**
   * Initialize a new `Selector` with the given `segs`.
   *
   * @param {Array} segs
   * @api public
   */

  constructor(segs) {
    super();
    this.inherits = true;
    this.segments = segs;
    this.optional = false;
  }

  /**
   * Return the selector string.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return this.segments.join('') + (this.optional ? ' !optional' : '');
  };

  /**
   * Check if this is placeholder selector.
   *
   * @return {Boolean}
   * @api public
   */

  get isPlaceholder() {
    return this.val && ~this.val.substr(0, 2).indexOf('$');
  };

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Selector;
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    clone.inherits = this.inherits;
    clone.val = this.val;
    clone.segments = this.segments.map(function (node) { return node.clone(parent, clone); });
    clone.optional = this.optional;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Selector',
      inherits: this.inherits,
      segments: this.segments,
      optional: this.optional,
      val: this.val,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

};

},{"./block":133,"./node":154}],165:[function(require,module,exports){
/*!
 * Stylus - String
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node')
  , sprintf = require('../functions').s
  , utils = require('../utils')
  , nodes = require('./');

module.exports = class String extends Node {
  /**
   * Initialize a new `String` with the given `val`.
   *
   * @param {String} val
   * @param {String} quote
   * @api public
   */

  constructor(val, quote) {
    super();
    this.val = val;
    this.string = val;
    this.prefixed = false;
    if (typeof quote !== 'string') {
      this.quote = "'";
    } else {
      this.quote = quote;
    }
  }

  /**
   * Return quoted string.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return this.quote + this.val + this.quote;
  };

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone() {
    var clone = new String(this.val, this.quote);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'String',
      val: this.val,
      quote: this.quote,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

  /**
   * Return Boolean based on the length of this string.
   *
   * @return {Boolean}
   * @api public
   */

  toBoolean() {
    return new nodes.Boolean(this.val.length);
  };

  /**
   * Coerce `other` to a string.
   *
   * @param {Node} other
   * @return {String}
   * @api public
   */

  coerce(other) {
    switch (other.nodeName) {
      case 'string':
        return other;
      case 'expression':
        return new String(other.nodes.map(function (node) {
          return this.coerce(node).val;
        }, this).join(' '));
      default:
        return new String(other.toString());
    }
  };

  /**
   * Operate on `right` with the given `op`.
   *
   * @param {String} op
   * @param {Node} right
   * @return {Node}
   * @api public
   */

  operate(op, right) {
    switch (op) {
      case '%':
        var expr = new nodes.Expression;
        expr.push(this);

        // constructargs
        var args = 'expression' == right.nodeName
          ? utils.unwrap(right).nodes
          : [right];

        // apply
        return sprintf.apply(null, [expr].concat(args));
      case '+':
        var expr = new nodes.Expression;
        expr.push(new String(this.val + this.coerce(right).val));
        return expr;
      default:
        return super.operate(op, right);
    }
  };

};

},{"../functions":88,"../utils":178,"./":148,"./node":154}],166:[function(require,module,exports){
/*!
 * Stylus - supports
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Atrule = require('./atrule');

module.exports = class Supports extends Atrule {
  /**
   * Initialize a new supports node.
   *
   * @param {Expression} condition
   * @api public
   */

  constructor(condition) {
    super('supports');
    this.condition = condition;
  }

  /**
   * Return a clone of this node.
   *
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Supports;
    clone.condition = this.condition.clone(parent, clone);
    clone.block = this.block.clone(parent, clone);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Supports',
      condition: this.condition,
      block: this.block,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

  /**
   * Return @supports
   *
   * @return {String}
   * @api public
   */

  toString() {
    return '@supports ' + this.condition;
  };
};

},{"./atrule":131}],167:[function(require,module,exports){

/*!
 * Stylus - Ternary
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class Ternary extends Node {
  /**
   * Initialize a new `Ternary` with `cond`, `trueExpr` and `falseExpr`.
   *
   * @param {Expression} cond
   * @param {Expression} trueExpr
   * @param {Expression} falseExpr
   * @api public
   */

  constructor(cond, trueExpr, falseExpr) {
    super();
    this.cond = cond;
    this.trueExpr = trueExpr;
    this.falseExpr = falseExpr;
  }

  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new Ternary();
    clone.cond = this.cond.clone(parent, clone);
    clone.trueExpr = this.trueExpr.clone(parent, clone);
    clone.falseExpr = this.falseExpr.clone(parent, clone);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Ternary',
      cond: this.cond,
      trueExpr: this.trueExpr,
      falseExpr: this.falseExpr,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };
};

},{"./node":154}],168:[function(require,module,exports){

/*!
 * Stylus - UnaryOp
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node');

module.exports = class UnaryOp extends Node {
  /**
   * Initialize a new `UnaryOp` with `op`, and `expr`.
   *
   * @param {String} op
   * @param {Node} expr
   * @api public
   */

  constructor(op, expr) {
    super();
    this.op = op;
    this.expr = expr;
  }


  /**
   * Return a clone of this node.
   * 
   * @return {Node}
   * @api public
   */

  clone(parent) {
    var clone = new UnaryOp(this.op);
    clone.expr = this.expr.clone(parent, clone);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'UnaryOp',
      op: this.op,
      expr: this.expr,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

};

},{"./node":154}],169:[function(require,module,exports){

/*!
 * Stylus - Unit
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Node = require('./node')
  , nodes = require('./');

/**
 * Unit conversion table.
 */

var FACTOR_TABLE = {
  'mm': { val: 1, label: 'mm' },
  'cm': { val: 10, label: 'mm' },
  'in': { val: 25.4, label: 'mm' },
  'pt': { val: 25.4 / 72, label: 'mm' },
  'ms': { val: 1, label: 'ms' },
  's': { val: 1000, label: 'ms' },
  'Hz': { val: 1, label: 'Hz' },
  'kHz': { val: 1000, label: 'Hz' }
};

module.exports = class Unit extends Node {
  /**
   * Initialize a new `Unit` with the given `val` and unit `type`
   * such as "px", "pt", "in", etc.
   *
   * @param {String} val
   * @param {String} type
   * @api public
   */

  constructor(val, type) {
    super();
    this.val = val;
    this.type = type;
  }

  /**
   * Return Boolean based on the unit value.
   *
   * @return {Boolean}
   * @api public
   */

  toBoolean() {
    return new nodes.Boolean(this.type
      ? true
      : this.val);
  };

  /**
   * Return unit string.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return this.val + (this.type || '');
  };

  /**
   * Return a clone of this node.
   *
   * @return {Node}
   * @api public
   */

  clone() {
    var clone = new Unit(this.val, this.type);
    clone.lineno = this.lineno;
    clone.column = this.column;
    clone.filename = this.filename;
    return clone;
  };

  /**
   * Return a JSON representation of this node.
   *
   * @return {Object}
   * @api public
   */

  toJSON() {
    return {
      __type: 'Unit',
      val: this.val,
      type: this.type,
      lineno: this.lineno,
      column: this.column,
      filename: this.filename
    };
  };

  /**
   * Operate on `right` with the given `op`.
   *
   * @param {String} op
   * @param {Node} right
   * @return {Node}
   * @api public
   */

  operate(op, right) {
    var type = this.type || right.first.type;

    // swap color
    if ('rgba' == right.nodeName || 'hsla' == right.nodeName) {
      return right.operate(op, this);
    }

    // operate
    if (this.shouldCoerce(op)) {
      right = right.first;
      // percentages
      if ('%' != this.type && ('-' == op || '+' == op) && '%' == right.type) {
        right = new Unit(this.val * (right.val / 100), '%');
      } else {
        right = this.coerce(right);
      }

      switch (op) {
        case '-':
          return new Unit(this.val - right.val, type);
        case '+':
          // keyframes interpolation
          type = type || (right.type == '%' && right.type);
          return new Unit(this.val + right.val, type);
        case '/':
          return new Unit(this.val / right.val, type);
        case '*':
          return new Unit(this.val * right.val, type);
        case '%':
          return new Unit(this.val % right.val, type);
        case '**':
          return new Unit(Math.pow(this.val, right.val), type);
        case '..':
        case '...':
          var start = this.val
            , end = right.val
            , expr = new nodes.Expression
            , inclusive = '..' == op;
          if (start < end) {
            do {
              expr.push(new nodes.Unit(start));
            } while (inclusive ? ++start <= end : ++start < end);
          } else {
            do {
              expr.push(new nodes.Unit(start));
            } while (inclusive ? --start >= end : --start > end);
          }
          return expr;
      }
    }

    return super.operate(op, right);
  };

  /**
   * Coerce `other` unit to the same type as `this` unit.
   *
   * Supports:
   *
   *    mm -> cm | in
   *    cm -> mm | in
   *    in -> mm | cm
   *
   *    ms -> s
   *    s  -> ms
   *
   *    Hz  -> kHz
   *    kHz -> Hz
   *
   * @param {Unit} other
   * @return {Unit}
   * @api public
   */

  coerce(other) {
    if ('unit' == other.nodeName) {
      var a = this
        , b = other
        , factorA = FACTOR_TABLE[a.type]
        , factorB = FACTOR_TABLE[b.type];

      if (factorA && factorB && (factorA.label == factorB.label)) {
        var bVal = b.val * (factorB.val / factorA.val);
        return new nodes.Unit(bVal, a.type);
      } else {
        return new nodes.Unit(b.val, a.type);
      }
    } else if ('string' == other.nodeName) {
      // keyframes interpolation
      if ('%' == other.val) return new nodes.Unit(0, '%');
      var val = parseFloat(other.val);
      if (isNaN(val)) super.coerce(other);
      return new nodes.Unit(val);
    } else {
      return super.coerce(other);
    }
  };
};

},{"./":148,"./node":154}],170:[function(require,module,exports){
/*!
 * Stylus - Parser
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Lexer = require('./lexer')
  , nodes = require('./nodes')
  , Token = require('./token')
  , units = require('./units')
  , errors = require('./errors')
  , cache = require('./cache');

// debuggers

var debug = {
  lexer: require('debug')('stylus:lexer')
  , selector: require('debug')('stylus:parser:selector')
};

/**
 * Selector composite tokens.
 */

var selectorTokens = [
  'ident'
  , 'string'
  , 'selector'
  , 'function'
  , 'comment'
  , 'boolean'
  , 'space'
  , 'color'
  , 'unit'
  , 'for'
  , 'in'
  , '['
  , ']'
  , '('
  , ')'
  , '+'
  , '-'
  , '*'
  , '*='
  , '<'
  , '>'
  , '='
  , ':'
  , '&'
  , '&&'
  , '~'
  , '{'
  , '}'
  , '.'
  , '..'
  , '/'
];

/**
 * CSS pseudo-classes and pseudo-elements.
 * See http://dev.w3.org/csswg/selectors4/
 */

var pseudoSelectors = [
  // https://www.w3.org/TR/selectors-4/#logical-combination
  // Logical Combinations
  'is'
  , 'has'
  , 'where'
  , 'not'

  // Linguistic Pseudo-classes
  , 'dir'
  , 'lang'

  // Location Pseudo-classes
  , 'any-link'
  , 'link'
  , 'visited'
  , 'local-link'
  , 'target'
  , 'scope'

  // User Action Pseudo-classes
  , 'hover'
  , 'active'
  , 'focus'
  , 'drop'

  // Time-dimensional Pseudo-classes
  , 'current'
  , 'past'
  , 'future'

  // The Input Pseudo-classes
  , 'enabled'
  , 'disabled'
  , 'read-only'
  , 'read-write'
  , 'placeholder-shown'
  , 'checked'
  , 'indeterminate'
  , 'valid'
  , 'invalid'
  , 'in-range'
  , 'out-of-range'
  , 'required'
  , 'optional'
  , 'user-error'

  // Tree-Structural pseudo-classes
  , 'root'
  , 'empty'
  , 'blank'
  , 'nth-child'
  , 'nth-last-child'
  , 'first-child'
  , 'last-child'
  , 'only-child'
  , 'nth-of-type'
  , 'nth-last-of-type'
  , 'first-of-type'
  , 'last-of-type'
  , 'only-of-type'
  , 'nth-match'
  , 'nth-last-match'

  // Grid-Structural Selectors
  , 'nth-column'
  , 'nth-last-column'

  // Pseudo-elements
  , 'first-line'
  , 'first-letter'
  , 'before'
  , 'after'

  // Non-standard
  , 'selection'
];

module.exports = class Parser {
  /**
   * Initialize a new `Parser` with the given `str` and `options`.
   *
   * @param {String} str
   * @param {Object} options
   * @api private
   */

  constructor(str, options) {
    var self = this;
    options = options || {};
    Parser.cache = Parser.cache || Parser.getCache(options);
    this.hash = Parser.cache.key(str, options);
    this.lexer = {};
    if (!Parser.cache.has(this.hash)) {
      this.lexer = new Lexer(str, options);
    }
    this.prefix = options.prefix || '';
    this.root = options.root || new nodes.Root;
    this.state = ['root'];
    this.stash = [];
    this.parens = 0;
    this.css = 0;
    this.state.pop = function () {
      self.prevState = [].pop.call(this);
    };
  };

  /**
   * Get cache instance.
   *
   * @param {Object} options
   * @return {Object}
   * @api private
   */

  static getCache(options) {
    return false === options.cache
      ? cache(false)
      : cache(options.cache || 'memory', options);
  };


  /**
   * Return current state.
   *
   * @return {String}
   * @api private
   */

  currentState() {
    return this.state[this.state.length - 1];
  }

  /**
   * Return previous state.
   *
   * @return {String}
   * @api private
   */

  previousState() {
    return this.state[this.state.length - 2];
  }

  /**
   * Parse the input, then return the root node.
   *
   * @return {Node}
   * @api private
   */

  parse() {
    var block = this.parent = this.root;
    if (Parser.cache.has(this.hash)) {
      block = Parser.cache.get(this.hash);
      // normalize cached imports
      if ('block' == block.nodeName) block.constructor = nodes.Root;
    } else {
      while ('eos' != this.peek().type) {
        this.skipWhitespace();
        if ('eos' == this.peek().type) break;
        var stmt = this.statement();
        this.accept(';');
        if (!stmt) this.error('unexpected token {peek}, not allowed at the root level');
        block.push(stmt);
      }
      Parser.cache.set(this.hash, block);
    }
    return block;
  }

  /**
   * Throw an `Error` with the given `msg`.
   *
   * @param {String} msg
   * @api private
   */

  error(msg) {
    var type = this.peek().type
      , val = undefined == this.peek().val
        ? ''
        : ' ' + this.peek().toString();
    if (val.trim() == type.trim()) val = '';
    throw new errors.ParseError(msg.replace('{peek}', '"' + type + val + '"'));
  }

  /**
   * Accept the given token `type`, and return it,
   * otherwise return `undefined`.
   *
   * @param {String} type
   * @return {Token}
   * @api private
   */

  accept(type) {
    if (type == this.peek().type) {
      return this.next();
    }
  }

  /**
   * Expect token `type` and return it, throw otherwise.
   *
   * @param {String} type
   * @return {Token}
   * @api private
   */

  expect(type) {
    if (type != this.peek().type) {
      this.error('expected "' + type + '", got {peek}');
    }
    return this.next();
  }

  /**
   * Get the next token.
   *
   * @return {Token}
   * @api private
   */

  next() {
    var tok = this.stash.length
      ? this.stash.pop()
      : this.lexer.next()
      , line = tok.lineno
      , column = tok.column || 1;

    if (tok.val && tok.val.nodeName) {
      tok.val.lineno = line;
      tok.val.column = column;
    }
    nodes.lineno = line;
    nodes.column = column;
    debug.lexer('%s %s', tok.type, tok.val || '');
    return tok;
  }

  /**
   * Peek with lookahead(1).
   *
   * @return {Token}
   * @api private
   */

  peek() {
    return this.lexer.peek();
  }

  /**
   * Lookahead `n` tokens.
   *
   * @param {Number} n
   * @return {Token}
   * @api private
   */

  lookahead(n) {
    return this.lexer.lookahead(n);
  }

  /**
   * Check if the token at `n` is a valid selector token.
   *
   * @param {Number} n
   * @return {Boolean}
   * @api private
   */

  isSelectorToken(n) {
    var la = this.lookahead(n).type;
    switch (la) {
      case 'for':
        return this.bracketed;
      case '[':
        this.bracketed = true;
        return true;
      case ']':
        this.bracketed = false;
        return true;
      default:
        return ~selectorTokens.indexOf(la);
    }
  }

  /**
   * Check if the token at `n` is a pseudo selector.
   *
   * @param {Number} n
   * @return {Boolean}
   * @api private
   */

  isPseudoSelector(n) {
    var val = this.lookahead(n).val;
    return val && ~pseudoSelectors.indexOf(val.name);
  }

  /**
   * Check if the current line contains `type`.
   *
   * @param {String} type
   * @return {Boolean}
   * @api private
   */

  lineContains(type) {
    var i = 1
      , la;

    while (la = this.lookahead(i++)) {
      if (~['indent', 'outdent', 'newline', 'eos'].indexOf(la.type)) return;
      if (type == la.type) return true;
    }
  }

  /**
   * Valid selector tokens.
   */

  selectorToken() {
    if (this.isSelectorToken(1)) {
      if ('{' == this.peek().type) {
        // unclosed, must be a block
        if (!this.lineContains('}')) return;
        // check if ':' is within the braces.
        // though not required by Stylus, chances
        // are if someone is using {} they will
        // use CSS-style props, helping us with
        // the ambiguity in this case
        var i = 0
          , la;
        while (la = this.lookahead(++i)) {
          if ('}' == la.type) {
            // Check empty block.
            if (i == 2 || (i == 3 && this.lookahead(i - 1).type == 'space'))
              return;
            break;
          }
          if (':' == la.type) return;
        }
      }
      return this.next();
    }
  }

  /**
   * Skip the given `tokens`.
   *
   * @param {Array} tokens
   * @api private
   */

  skip(tokens) {
    while (~tokens.indexOf(this.peek().type))
      this.next();
  }

  /**
   * Consume whitespace.
   */

  skipWhitespace() {
    this.skip(['space', 'indent', 'outdent', 'newline']);
  }

  /**
   * Consume newlines.
   */

  skipNewlines() {
    while ('newline' == this.peek().type)
      this.next();
  }

  /**
   * Consume spaces.
   */

  skipSpaces() {
    while ('space' == this.peek().type)
      this.next();
  }

  /**
   * Consume spaces and comments.
   */

  skipSpacesAndComments() {
    while ('space' == this.peek().type
      || 'comment' == this.peek().type)
      this.next();
  }

  /**
   * Check if the following sequence of tokens
   * forms a function definition, ie trailing
   * `{` or indentation.
   */

  looksLikeFunctionDefinition(i) {
    return 'indent' == this.lookahead(i).type
      || '{' == this.lookahead(i).type;
  }

  /**
   * Check if the following sequence of tokens
   * forms a selector.
   *
   * @param {Boolean} [fromProperty]
   * @return {Boolean}
   * @api private
   */

  looksLikeSelector(fromProperty) {
    var i = 1
      , node
      , brace;

    // Real property
    if (fromProperty && ':' == this.lookahead(i + 1).type
      && (this.lookahead(i + 1).space || 'indent' == this.lookahead(i + 2).type))
      return false;

    // Assume selector when an ident is
    // followed by a selector
    while ('ident' == this.lookahead(i).type
      && ('newline' == this.lookahead(i + 1).type
        || ',' == this.lookahead(i + 1).type)) i += 2;

    while (this.isSelectorToken(i)
      || ',' == this.lookahead(i).type) {

      if ('selector' == this.lookahead(i).type)
        return true;

      if ('&' == this.lookahead(i + 1).type)
        return true;

      // Hash values inside properties
      if (
        i > 1 &&
        'ident' === this.lookahead(i - 1).type &&
        '.' === this.lookahead(i).type &&
        'ident' === this.lookahead(i + 1).type
      ) {
        while ((node = this.lookahead(i + 2))) {
          if ([
            'indent',
            'outdent',
            '{',
            ';',
            'eos',
            'selector',
            'media',
            'if',
            'atrule',
            ')',
            '}',
            'unit',
            '[',
            'for',
            'function'
          ].indexOf(node.type) !== -1) {
            if (node.type === '[') {
              while ((node = this.lookahead(i + 3)) && node.type !== ']') {
                if (~['.', 'unit'].indexOf(node.type)) {
                  return false;
                }
                i += 1
              }
            } else {
              if (this.isPseudoSelector(i + 2)) {
                return true;
              }

              if (node.type === ')' && this.lookahead(i + 3) && this.lookahead(i + 3).type === '}') {
                break;
              }

              return [
                'outdent',
                ';',
                'eos',
                'media',
                'if',
                'atrule',
                ')',
                '}',
                'unit',
                'for',
                'function'
              ].indexOf(node.type) === -1;
            }
          }

          i += 1
        }

        return true;
      }

      if ('.' == this.lookahead(i).type && 'ident' == this.lookahead(i + 1).type) {
        return true;
      }

      if ('*' == this.lookahead(i).type && 'newline' == this.lookahead(i + 1).type)
        return true;

      // Pseudo-elements
      if (':' == this.lookahead(i).type
        && ':' == this.lookahead(i + 1).type)
        return true;

      // #a after an ident and newline
      if ('color' == this.lookahead(i).type
        && 'newline' == this.lookahead(i - 1).type)
        return true;

      if (this.looksLikeAttributeSelector(i))
        return true;

      if (('=' == this.lookahead(i).type || 'function' == this.lookahead(i).type)
        && '{' == this.lookahead(i + 1).type)
        return false;

      // Hash values inside properties
      if (':' == this.lookahead(i).type
        && !this.isPseudoSelector(i + 1)
        && this.lineContains('.'))
        return false;

      // the ':' token within braces signifies
      // a selector. ex: "foo{bar:'baz'}"
      if ('{' == this.lookahead(i).type) brace = true;
      else if ('}' == this.lookahead(i).type) brace = false;
      if (brace && ':' == this.lookahead(i).type) return true;

      // '{' preceded by a space is considered a selector.
      // for example "foo{bar}{baz}" may be a property,
      // however "foo{bar} {baz}" is a selector
      if ('space' == this.lookahead(i).type
        && '{' == this.lookahead(i + 1).type)
        return true;

      // Assume pseudo selectors are NOT properties
      // as 'td:th-child(1)' may look like a property
      // and function call to the parser otherwise
      if (':' == this.lookahead(i++).type
        && !this.lookahead(i - 1).space
        && this.isPseudoSelector(i))
        return true;

      // Trailing space
      if ('space' == this.lookahead(i).type
        && 'newline' == this.lookahead(i + 1).type
        && '{' == this.lookahead(i + 2).type)
        return true;

      if (',' == this.lookahead(i).type
        && 'newline' == this.lookahead(i + 1).type)
        return true;
    }

    // Trailing comma
    if (',' == this.lookahead(i).type
      && 'newline' == this.lookahead(i + 1).type)
      return true;

    // Trailing brace
    if ('{' == this.lookahead(i).type
      && 'newline' == this.lookahead(i + 1).type)
      return true;

    // css-style mode, false on ; }
    if (this.css) {
      if (';' == this.lookahead(i).type ||
        '}' == this.lookahead(i - 1).type)
        return false;
    }

    // Trailing separators
    while (!~[
      'indent'
      , 'outdent'
      , 'newline'
      , 'for'
      , 'if'
      , ';'
      , '}'
      , 'eos'].indexOf(this.lookahead(i).type))
      ++i;

    if ('indent' == this.lookahead(i).type)
      return true;
  }

  /**
   * Check if the following sequence of tokens
   * forms an attribute selector.
   */

  looksLikeAttributeSelector(n) {
    var type = this.lookahead(n).type;
    if ('=' == type && this.bracketed) return true;
    return ('ident' == type || 'string' == type)
      && ']' == this.lookahead(n + 1).type
      && ('newline' == this.lookahead(n + 2).type || this.isSelectorToken(n + 2))
      && !this.lineContains(':')
      && !this.lineContains('=');
  }

  /**
   * Check if the following sequence of tokens
   * forms a keyframe block.
   */

  looksLikeKeyframe() {
    var i = 2
      , type;
    switch (this.lookahead(i).type) {
      case '{':
      case 'indent':
      case ',':
        return true;
      case 'newline':
        while ('unit' == this.lookahead(++i).type
          || 'newline' == this.lookahead(i).type);
        type = this.lookahead(i).type;
        return 'indent' == type || '{' == type;
    }
  }

  /**
   * Check if the current state supports selectors.
   */

  stateAllowsSelector() {
    switch (this.currentState()) {
      case 'root':
      case 'atblock':
      case 'selector':
      case 'conditional':
      case 'function':
      case 'atrule':
      case 'for':
        return true;
    }
  }

  /**
   * Try to assign @block to the node.
   *
   * @param {Expression} expr
   * @private
   */

  assignAtblock(expr) {
    try {
      expr.push(this.atblock(expr));
    } catch (err) {
      this.error('invalid right-hand side operand in assignment, got {peek}');
    }
  }

  /**
   *   statement
   * | statement 'if' expression
   * | statement 'unless' expression
   */

  statement() {
    var stmt = this.stmt()
      , state = this.prevState
      , block
      , op;

    // special-case statements since it
    // is not an expression. We could
    // implement postfix conditionals at
    // the expression level, however they
    // would then fail to enclose properties
    if (this.allowPostfix) {
      this.allowPostfix = false;
      state = 'expression';
    }

    switch (state) {
      case 'assignment':
      case 'expression':
      case 'function arguments':
        while (op =
          this.accept('if')
          || this.accept('unless')
          || this.accept('for')) {
          switch (op.type) {
            case 'if':
            case 'unless':
              stmt = new nodes.If(this.expression(), stmt);
              stmt.postfix = true;
              stmt.negate = 'unless' == op.type;
              this.accept(';');
              break;
            case 'for':
              var key
                , val = this.id().name;
              if (this.accept(',')) key = this.id().name;
              this.expect('in');
              var each = new nodes.Each(val, key, this.expression());
              block = new nodes.Block(this.parent, each);
              block.push(stmt);
              each.block = block;
              stmt = each;
          }
        }
    }

    return stmt;
  }

  /**
   *    ident
   *  | selector
   *  | literal
   *  | charset
   *  | namespace
   *  | import
   *  | require
   *  | media
   *  | atrule
   *  | scope
   *  | keyframes
   *  | mozdocument
   *  | for
   *  | if
   *  | unless
   *  | comment
   *  | expression
   *  | 'return' expression
   */

  stmt() {
    var tok = this.peek(), selector;
    switch (tok.type) {
      case 'keyframes':
        return this.keyframes();
      case '-moz-document':
        return this.mozdocument();
      case 'comment':
      case 'selector':
      case 'literal':
      case 'charset':
      case 'namespace':
      case 'import':
      case 'require':
      case 'extend':
      case 'media':
      case 'atrule':
      case 'ident':
      case 'scope':
      case 'supports':
      case 'unless':
      case 'function':
      case 'for':
      case 'if':
        return this[tok.type]();
      case 'return':
        return this.return();
      case '{':
        return this.property();
      default:
        // Contextual selectors
        if (this.stateAllowsSelector()) {
          switch (tok.type) {
            case 'color':
            case '~':
            case '>':
            case '<':
            case ':':
            case '&':
            case '&&':
            case '[':
            case '.':
            case '/':
              selector = this.selector();
              selector.column = tok.column;
              selector.lineno = tok.lineno;
              return selector;
            // relative reference
            case '..':
              if ('/' == this.lookahead(2).type)
                return this.selector();
            case '+':
              return 'function' == this.lookahead(2).type
                ? this.functionCall()
                : this.selector();
            case '*':
              return this.property();
            // keyframe blocks (10%, 20% { ... })
            case 'unit':
              if (this.looksLikeKeyframe()) {
                selector = this.selector();
                selector.column = tok.column;
                selector.lineno = tok.lineno;
                return selector;
              }
            case '-':
              if ('{' == this.lookahead(2).type)
                return this.property();
          }
        }

        // Expression fallback
        var expr = this.expression();
        if (expr.isEmpty) this.error('unexpected {peek}');
        return expr;
    }
  }

  /**
   * indent (!outdent)+ outdent
   */

  block(node, scope) {
    var delim
      , stmt
      , next
      , block = this.parent = new nodes.Block(this.parent, node);

    if (false === scope) block.scope = false;

    this.accept('newline');

    // css-style
    if (this.accept('{')) {
      this.css++;
      delim = '}';
      this.skipWhitespace();
    } else {
      delim = 'outdent';
      this.expect('indent');
    }

    while (delim != this.peek().type) {
      // css-style
      if (this.css) {
        if (this.accept('newline') || this.accept('indent')) continue;
        stmt = this.statement();
        this.accept(';');
        this.skipWhitespace();
      } else {
        if (this.accept('newline')) continue;
        // skip useless indents and comments
        next = this.lookahead(2).type;
        if ('indent' == this.peek().type
          && ~['outdent', 'newline', 'comment'].indexOf(next)) {
          this.skip(['indent', 'outdent']);
          continue;
        }
        if ('eos' == this.peek().type) return block;
        stmt = this.statement();
        this.accept(';');
      }
      if (!stmt) this.error('unexpected token {peek} in block');
      block.push(stmt);
    }

    // css-style
    if (this.css) {
      this.skipWhitespace();
      this.expect('}');
      this.skipSpaces();
      this.css--;
    } else {
      this.expect('outdent');
    }

    this.parent = block.parent;
    return block;
  }

  /**
   * comment space*
   */

  comment() {
    var node = this.next().val;
    this.skipSpaces();
    return node;
  }

  /**
   * for val (',' key) in expr
   */

  for() {
    this.expect('for');
    var key
      , val = this.id().name;
    if (this.accept(',')) key = this.id().name;
    this.expect('in');
    this.state.push('for');
    this.cond = true;
    var each = new nodes.Each(val, key, this.expression());
    this.cond = false;
    each.block = this.block(each, false);
    this.state.pop();
    return each;
  }

  /**
   * return expression
   */

  return() {
    this.expect('return');
    var expr = this.expression();
    return expr.isEmpty
      ? new nodes.Return
      : new nodes.Return(expr);
  }

  /**
   * unless expression block
   */

  unless() {
    this.expect('unless');
    this.state.push('conditional');
    this.cond = true;
    var node = new nodes.If(this.expression(), true);
    this.cond = false;
    node.block = this.block(node, false);
    this.state.pop();
    return node;
  }

  /**
   * if expression block (else block)?
   */

  if() {
    var token = this.expect('if');

    this.state.push('conditional');
    this.cond = true;
    var node = new nodes.If(this.expression())
      , cond
      , block
      , item;

    node.column = token.column;

    this.cond = false;
    node.block = this.block(node, false);
    this.skip(['newline', 'comment']);
    while (this.accept('else')) {
      token = this.accept('if');
      if (token) {
        this.cond = true;
        cond = this.expression();
        this.cond = false;
        block = this.block(node, false);
        item = new nodes.If(cond, block);

        item.column = token.column;

        node.elses.push(item);
      } else {
        node.elses.push(this.block(node, false));
        break;
      }
      this.skip(['newline', 'comment']);
    }
    this.state.pop();
    return node;
  }

  /**
   * @block
   *
   * @param {Expression} [node]
   */

  atblock(node) {
    if (!node) this.expect('atblock');
    node = new nodes.Atblock;
    this.state.push('atblock');
    node.block = this.block(node, false);
    this.state.pop();
    return node;
  }

  /**
   * atrule selector? block?
   */

  atrule() {
    var type = this.expect('atrule').val
      , node = new nodes.Atrule(type)
      , tok;
    this.skipSpacesAndComments();
    node.segments = this.selectorParts();
    this.skipSpacesAndComments();
    tok = this.peek().type;
    if ('indent' == tok || '{' == tok || ('newline' == tok
      && '{' == this.lookahead(2).type)) {
      this.state.push('atrule');
      node.block = this.block(node);
      this.state.pop();
    }
    return node;
  }

  /**
   * scope
   */

  scope() {
    this.expect('scope');
    var selector = this.selectorParts()
      .map(function (selector) { return selector.val; })
      .join('');
    this.selectorScope = selector.trim();
    return nodes.null;
  }

  /**
   * supports
   */

  supports() {
    this.expect('supports');
    var node = new nodes.Supports(this.supportsCondition());
    this.state.push('atrule');
    node.block = this.block(node);
    this.state.pop();
    return node;
  }

  /**
   *   supports negation
   * | supports op
   * | expression
   */

  supportsCondition() {
    var node = this.supportsNegation()
      || this.supportsOp();
    if (!node) {
      this.cond = true;
      node = this.expression();
      this.cond = false;
    }
    return node;
  }

  /**
   * 'not' supports feature
   */

  supportsNegation() {
    if (this.accept('not')) {
      var node = new nodes.Expression;
      node.push(new nodes.Literal('not'));
      node.push(this.supportsFeature());
      return node;
    }
  }

  /**
   * supports feature (('and' | 'or') supports feature)+
   */

  supportsOp() {
    var feature = this.supportsFeature()
      , op
      , expr;
    if (feature) {
      expr = new nodes.Expression;
      expr.push(feature);
      while (op = this.accept('&&') || this.accept('||')) {
        expr.push(new nodes.Literal('&&' == op.val ? 'and' : 'or'));
        expr.push(this.supportsFeature());
      }
      return expr;
    }
  }

  /**
   *   ('(' supports condition ')')
   * | feature
   */

  supportsFeature() {
    this.skipSpacesAndComments();
    if ('(' == this.peek().type) {
      var la = this.lookahead(2).type;

      if ('ident' == la || '{' == la) {
        return this.feature();
      } else {
        this.expect('(');
        var node = new nodes.Expression;
        node.push(new nodes.Literal('('));
        node.push(this.supportsCondition());
        this.expect(')')
        node.push(new nodes.Literal(')'));
        this.skipSpacesAndComments();
        return node;
      }
    }
  }

  /**
   * extend
   */

  extend() {
    var tok = this.expect('extend')
      , selectors = []
      , sel
      , node
      , arr;

    do {
      arr = this.selectorParts();

      if (!arr.length) continue;

      sel = new nodes.Selector(arr);
      selectors.push(sel);

      if ('!' !== this.peek().type) continue;

      tok = this.lookahead(2);
      if ('ident' !== tok.type || 'optional' !== tok.val.name) continue;

      this.skip(['!', 'ident']);
      sel.optional = true;
    } while (this.accept(','));

    node = new nodes.Extend(selectors);
    node.lineno = tok.lineno;
    node.column = tok.column;
    return node;
  }

  /**
   * media queries
   */

  media() {
    this.expect('media');
    this.state.push('atrule');
    var media = new nodes.Media(this.queries());
    media.block = this.block(media);
    this.state.pop();
    return media;
  }

  /**
   * query (',' query)*
   */

  queries() {
    var queries = new nodes.QueryList
      , skip = ['comment', 'newline', 'space'];

    do {
      this.skip(skip);
      queries.push(this.query());
      this.skip(skip);
    } while (this.accept(','));
    return queries;
  }

  /**
   *   expression
   * | (ident | 'not')? ident ('and' feature)*
   * | feature ('and' feature)*
   */

  query() {
    var query = new nodes.Query
      , expr
      , pred
      , id;

    // hash values support
    if ('ident' == this.peek().type
      && ('.' == this.lookahead(2).type
        || '[' == this.lookahead(2).type)) {
      this.cond = true;
      expr = this.expression();
      this.cond = false;
      query.push(new nodes.Feature(expr.nodes));
      return query;
    }

    if (pred = this.accept('ident') || this.accept('not')) {
      pred = new nodes.Literal(pred.val.string || pred.val);

      this.skipSpacesAndComments();
      if (id = this.accept('ident')) {
        query.type = id.val;
        query.predicate = pred;
      } else {
        query.type = pred;
      }
      this.skipSpacesAndComments();

      if (!this.accept('&&')) return query;
    }

    do {
      query.push(this.feature());
    } while (this.accept('&&'));

    return query;
  }

  /**
   * '(' ident ( ':'? expression )? ')'
   */

  feature() {
    this.skipSpacesAndComments();
    this.expect('(');
    this.skipSpacesAndComments();
    var node = new nodes.Feature(this.interpolate());
    this.skipSpacesAndComments();
    this.accept(':')
    this.skipSpacesAndComments();
    this.inProperty = true;
    node.expr = this.list();
    this.inProperty = false;
    this.skipSpacesAndComments();
    this.expect(')');
    this.skipSpacesAndComments();
    return node;
  }

  /**
   * @-moz-document call (',' call)* block
   */

  mozdocument() {
    this.expect('-moz-document');
    var mozdocument = new nodes.Atrule('-moz-document')
      , calls = [];
    do {
      this.skipSpacesAndComments();
      calls.push(this.functionCall());
      this.skipSpacesAndComments();
    } while (this.accept(','));
    mozdocument.segments = [new nodes.Literal(calls.join(', '))];
    this.state.push('atrule');
    mozdocument.block = this.block(mozdocument, false);
    this.state.pop();
    return mozdocument;
  }

  /**
   * import expression
   */

  import() {
    this.expect('import');
    this.allowPostfix = true;
    return new nodes.Import(this.expression(), false);
  }

  /**
   * require expression
   */

  require() {
    this.expect('require');
    this.allowPostfix = true;
    return new nodes.Import(this.expression(), true);
  }

  /**
   * charset string
   */

  charset() {
    this.expect('charset');
    var str = this.expect('string').val;
    this.allowPostfix = true;
    return new nodes.Charset(str);
  }

  /**
   * namespace ident? (string | url)
   */

  namespace() {
    var str
      , prefix;
    this.expect('namespace');

    this.skipSpacesAndComments();
    if (prefix = this.accept('ident')) {
      prefix = prefix.val;
    }
    this.skipSpacesAndComments();

    str = this.accept('string') || this.url();
    this.allowPostfix = true;
    return new nodes.Namespace(str, prefix);
  }

  /**
   * keyframes name block
   */

  keyframes() {
    var tok = this.expect('keyframes')
      , keyframes;

    this.skipSpacesAndComments();
    keyframes = new nodes.Keyframes(this.selectorParts(), tok.val);
    keyframes.column = tok.column;

    this.skipSpacesAndComments();

    // block
    this.state.push('atrule');
    keyframes.block = this.block(keyframes);
    this.state.pop();

    return keyframes;
  }

  /**
   * literal
   */

  literal() {
    return this.expect('literal').val;
  }

  /**
   * ident space?
   */

  id() {
    var tok = this.expect('ident');
    this.accept('space');
    return tok.val;
  }

  /**
   *   ident
   * | assignment
   * | property
   * | selector
   */

  ident() {
    var i = 2
      , la = this.lookahead(i).type;

    while ('space' == la) la = this.lookahead(++i).type;

    switch (la) {
      // Assignment
      case '=':
      case '?=':
      case '-=':
      case '+=':
      case '*=':
      case '/=':
      case '%=':
        return this.assignment();
      // Member
      case '.':
        if ('space' == this.lookahead(i - 1).type) return this.selector();
        if (this._ident == this.peek()) return this.id();
        while ('=' != this.lookahead(++i).type
          && !~['[', ',', 'newline', 'indent', 'eos'].indexOf(this.lookahead(i).type));
        if ('=' == this.lookahead(i).type) {
          this._ident = this.peek();
          return this.expression();
        } else if (this.looksLikeSelector() && this.stateAllowsSelector()) {
          return this.selector();
        }
      // Assignment []=
      case '[':
        if (this._ident == this.peek()) return this.id();
        while (']' != this.lookahead(i++).type
          && 'selector' != this.lookahead(i).type
          && 'eos' != this.lookahead(i).type);
        if ('=' == this.lookahead(i).type) {
          this._ident = this.peek();
          return this.expression();
        } else if (this.looksLikeSelector() && this.stateAllowsSelector()) {
          return this.selector();
        }
      // Operation
      case '-':
      case '+':
      case '/':
      case '*':
      case '%':
      case '**':
      case '&&':
      case '||':
      case '>':
      case '<':
      case '>=':
      case '<=':
      case '!=':
      case '==':
      case '?':
      case 'in':
      case 'is a':
      case 'is defined':
        // Prevent cyclic .ident, return literal
        if (this._ident == this.peek()) {
          return this.id();
        } else {
          this._ident = this.peek();
          switch (this.currentState()) {
            // unary op or selector in property / for
            case 'for':
            case 'selector':
              return this.property();
            // Part of a selector
            case 'root':
            case 'atblock':
            case 'atrule':
              return '[' == la
                ? this.subscript()
                : this.selector();
            case 'function':
            case 'conditional':
              return this.looksLikeSelector()
                ? this.selector()
                : this.expression();
            // Do not disrupt the ident when an operand
            default:
              return this.operand
                ? this.id()
                : this.expression();
          }
        }
      // Selector or property
      default:
        switch (this.currentState()) {
          case 'root':
            return this.selector();
          case 'for':
          case 'selector':
          case 'function':
          case 'conditional':
          case 'atblock':
          case 'atrule':
            return this.property();
          default:
            var id = this.id();
            if ('interpolation' == this.previousState()) id.mixin = true;
            return id;
        }
    }
  }

  /**
   * '*'? (ident | '{' expression '}')+
   */

  interpolate() {
    var node
      , segs = []
      , star;

    star = this.accept('*');
    if (star) segs.push(new nodes.Literal('*'));

    while (true) {
      if (this.accept('{')) {
        this.state.push('interpolation');
        segs.push(this.expression());
        this.expect('}');
        this.state.pop();
      } else if (node = this.accept('-')) {
        segs.push(new nodes.Literal('-'));
      } else if (node = this.accept('ident')) {
        segs.push(node.val);
      } else {
        break;
      }
    }
    if (!segs.length) this.expect('ident');
    return segs;
  }

  /**
   *   property ':'? expression
   * | ident
   */

  property() {
    if (this.looksLikeSelector(true)) return this.selector();

    // property
    var ident = this.interpolate()
      , prop = new nodes.Property(ident)
      , ret = prop;

    // optional ':'
    this.accept('space');
    if (this.accept(':')) this.accept('space');

    this.state.push('property');
    this.inProperty = true;
    prop.expr = this.list();
    if (prop.expr.isEmpty) ret = ident[0];
    this.inProperty = false;
    this.allowPostfix = true;
    this.state.pop();

    // optional ';'
    this.accept(';');

    return ret;
  }

  /**
   *   selector ',' selector
   * | selector newline selector
   * | selector block
   */

  selector() {
    var arr
      , group = new nodes.Group
      , scope = this.selectorScope
      , isRoot = 'root' == this.currentState()
      , selector;

    do {
      // Clobber newline after ,
      this.accept('newline');

      arr = this.selectorParts();

      // Push the selector
      if (isRoot && scope) arr.unshift(new nodes.Literal(scope + ' '));
      if (arr.length) {
        selector = new nodes.Selector(arr);
        selector.lineno = arr[0].lineno;
        selector.column = arr[0].column;
        group.push(selector);
      }
    } while (this.accept(',') || this.accept('newline'));

    if ('selector-parts' == this.currentState()) return group.nodes;

    this.state.push('selector');
    group.block = this.block(group);
    this.state.pop();

    return group;
  }

  selectorParts() {
    var tok
      , arr = [];

    // Selector candidates,
    // stitched together to
    // form a selector.
    while (tok = this.selectorToken()) {
      debug.selector('%s', tok);
      // Selector component
      switch (tok.type) {
        case '{':
          this.skipSpaces();
          var expr = this.expression();
          this.skipSpaces();
          this.expect('}');
          arr.push(expr);
          break;
        case this.prefix && '.':
          var literal = new nodes.Literal(tok.val + this.prefix);
          literal.prefixed = true;
          arr.push(literal);
          break;
        case 'comment':
          // ignore comments
          break;
        case 'color':
        case 'unit':
          arr.push(new nodes.Literal(tok.val.raw));
          break;
        case 'space':
          arr.push(new nodes.Literal(' '));
          break;
        case 'function':
          arr.push(new nodes.Literal(tok.val.name + '('));
          break;
        case 'ident':
          arr.push(new nodes.Literal(tok.val.name || tok.val.string));
          break;
        default:
          arr.push(new nodes.Literal(tok.val));
          if (tok.space) arr.push(new nodes.Literal(' '));
      }
    }

    return arr;
  }

  /**
   * ident ('=' | '?=') expression
   */

  assignment() {
    var
      op,
      node,
      ident = this.id(),
      name = ident.name;

    if (op =
      this.accept('=')
      || this.accept('?=')
      || this.accept('+=')
      || this.accept('-=')
      || this.accept('*=')
      || this.accept('/=')
      || this.accept('%=')) {
      this.state.push('assignment');
      var expr = this.list();
      // @block support
      if (expr.isEmpty) this.assignAtblock(expr);
      node = new nodes.Ident(name, expr);

      node.lineno = ident.lineno;
      node.column = ident.column;

      this.state.pop();

      switch (op.type) {
        case '?=':
          var defined = new nodes.BinOp('is defined', node)
            , lookup = new nodes.Expression;
          lookup.push(new nodes.Ident(name));
          node = new nodes.Ternary(defined, lookup, node);
          break;
        case '+=':
        case '-=':
        case '*=':
        case '/=':
        case '%=':
          node.val = new nodes.BinOp(op.type[0], new nodes.Ident(name), expr);
          break;
      }
    }

    return node;
  }

  /**
   *   definition
   * | call
   */

  function() {
    var parens = 1
      , i = 2
      , tok;

    // Lookahead and determine if we are dealing
    // with a function call or definition. Here
    // we pair parens to prevent false negatives
    out:
    while (tok = this.lookahead(i++)) {
      switch (tok.type) {
        case 'function':
        case '(':
          ++parens;
          break;
        case ')':
          if (!--parens) break out;
          break;
        case 'eos':
          this.error('failed to find closing paren ")"');
      }
    }

    // Definition or call
    switch (this.currentState()) {
      case 'expression':
        return this.functionCall();
      default:
        return this.looksLikeFunctionDefinition(i)
          ? this.functionDefinition()
          : this.expression();
    }
  }

  /**
   * url '(' (expression | urlchars)+ ')'
   */

  url() {
    this.expect('function');
    this.state.push('function arguments');
    var args = this.args();
    this.expect(')');
    this.state.pop();
    return new nodes.Call('url', args);
  }

  /**
   * '+'? ident '(' expression ')' block?
   */

  functionCall() {
    var withBlock = this.accept('+');
    if ('url' == this.peek().val.name) return this.url();

    var tok = this.expect('function').val;
    var name = tok.name;

    this.state.push('function arguments');
    this.parens++;
    var args = this.args();
    this.expect(')');
    this.parens--;
    this.state.pop();
    var call = new nodes.Call(name, args);

    call.column = tok.column;
    call.lineno = tok.lineno;

    if (withBlock) {
      this.state.push('function');
      call.block = this.block(call);
      this.state.pop();
    }
    return call;
  }

  /**
   * ident '(' params ')' block
   */

  functionDefinition() {
    var
      tok = this.expect('function'),
      name = tok.val.name;

    // params
    this.state.push('function params');
    this.skipWhitespace();
    var params = this.params();
    this.skipWhitespace();
    this.expect(')');
    this.state.pop();

    // Body
    this.state.push('function');
    var fn = new nodes.Function(name, params);

    fn.column = tok.column;
    fn.lineno = tok.lineno;

    fn.block = this.block(fn);
    this.state.pop();
    return new nodes.Ident(name, fn);
  }

  /**
   *   ident
   * | ident '...'
   * | ident '=' expression
   * | ident ',' ident
   */

  params() {
    var tok
      , node
      , params = new nodes.Params;
    while (tok = this.accept('ident')) {
      this.accept('space');
      params.push(node = tok.val);
      if (this.accept('...')) {
        node.rest = true;
      } else if (this.accept('=')) {
        node.val = this.expression();
      }
      this.skipWhitespace();
      this.accept(',');
      this.skipWhitespace();
    }
    return params;
  }

  /**
   * (ident ':')? expression (',' (ident ':')? expression)*
   */

  args() {
    var args = new nodes.Arguments
      , keyword;

    do {
      // keyword
      if ('ident' == this.peek().type && ':' == this.lookahead(2).type) {
        keyword = this.next().val.string;
        this.expect(':');
        args.map[keyword] = this.expression();
        // arg
      } else {
        args.push(this.expression());
      }
    } while (this.accept(','));

    return args;
  }

  /**
   * expression (',' expression)*
   */

  list() {
    var node = this.expression();

    while (this.accept(',')) {
      if (node.isList) {
        list.push(this.expression());
      } else {
        var list = new nodes.Expression(true);
        list.push(node);
        list.push(this.expression());
        node = list;
      }
    }
    return node;
  }

  /**
   * negation+
   */

  expression() {
    var node
      , expr = new nodes.Expression;
    this.state.push('expression');
    while (node = this.negation()) {
      if (!node) this.error('unexpected token {peek} in expression');
      expr.push(node);
    }
    this.state.pop();
    if (expr.nodes.length) {
      expr.lineno = expr.nodes[0].lineno;
      expr.column = expr.nodes[0].column;
    }
    return expr;
  }

  /**
   *   'not' ternary
   * | ternary
   */

  negation() {
    if (this.accept('not')) {
      return new nodes.UnaryOp('!', this.negation());
    }
    return this.ternary();
  }

  /**
   * logical ('?' expression ':' expression)?
   */

  ternary() {
    var node = this.logical();
    if (this.accept('?')) {
      var trueExpr = this.expression();
      this.expect(':');
      var falseExpr = this.expression();
      node = new nodes.Ternary(node, trueExpr, falseExpr);
    }
    return node;
  }

  /**
   * typecheck (('&&' | '||') typecheck)*
   */

  logical() {
    var op
      , node = this.typecheck();
    while (op = this.accept('&&') || this.accept('||')) {
      node = new nodes.BinOp(op.type, node, this.typecheck());
    }
    return node;
  }

  /**
   * equality ('is a' equality)*
   */

  typecheck() {
    var op
      , node = this.equality();
    while (op = this.accept('is a')) {
      this.operand = true;
      if (!node) this.error('illegal unary "' + op + '", missing left-hand operand');
      node = new nodes.BinOp(op.type, node, this.equality());
      this.operand = false;
    }
    return node;
  }

  /**
   * in (('==' | '!=') in)*
   */

  equality() {
    var op
      , node = this.in();
    while (op = this.accept('==') || this.accept('!=')) {
      this.operand = true;
      if (!node) this.error('illegal unary "' + op + '", missing left-hand operand');
      node = new nodes.BinOp(op.type, node, this.in());
      this.operand = false;
    }
    return node;
  }

  /**
   * relational ('in' relational)*
   */

  in() {
    var node = this.relational();
    while (this.accept('in')) {
      this.operand = true;
      if (!node) this.error('illegal unary "in", missing left-hand operand');
      node = new nodes.BinOp('in', node, this.relational());
      this.operand = false;
    }
    return node;
  }

  /**
   * range (('>=' | '<=' | '>' | '<') range)*
   */

  relational() {
    var op
      , node = this.range();
    while (op =
      this.accept('>=')
      || this.accept('<=')
      || this.accept('<')
      || this.accept('>')
    ) {
      this.operand = true;
      if (!node) this.error('illegal unary "' + op + '", missing left-hand operand');
      node = new nodes.BinOp(op.type, node, this.range());
      this.operand = false;
    }
    return node;
  }

  /**
   * additive (('..' | '...') additive)*
   */

  range() {
    var op
      , node = this.additive();
    if (op = this.accept('...') || this.accept('..')) {
      this.operand = true;
      if (!node) this.error('illegal unary "' + op + '", missing left-hand operand');
      node = new nodes.BinOp(op.val, node, this.additive());
      this.operand = false;
    }
    return node;
  }

  /**
   * multiplicative (('+' | '-') multiplicative)*
   */

  additive() {
    var op
      , node = this.multiplicative();
    while (op = this.accept('+') || this.accept('-')) {
      this.operand = true;
      node = new nodes.BinOp(op.type, node, this.multiplicative());
      this.operand = false;
    }
    return node;
  }

  /**
   * defined (('**' | '*' | '/' | '%') defined)*
   */

  multiplicative() {
    var op
      , node = this.defined();
    while (op =
      this.accept('**')
      || this.accept('*')
      || this.accept('/')
      || this.accept('%')) {
      this.operand = true;
      if ('/' == op && this.inProperty && !this.parens) {
        this.stash.push(new Token('literal', new nodes.Literal('/')));
        this.operand = false;
        return node;
      } else {
        if (!node) this.error('illegal unary "' + op + '", missing left-hand operand');
        node = new nodes.BinOp(op.type, node, this.defined());
        this.operand = false;
      }
    }
    return node;
  }

  /**
   *    unary 'is defined'
   *  | unary
   */

  defined() {
    var node = this.unary();
    if (this.accept('is defined')) {
      if (!node) this.error('illegal unary "is defined", missing left-hand operand');
      node = new nodes.BinOp('is defined', node);
    }
    return node;
  }

  /**
   *   ('!' | '~' | '+' | '-') unary
   * | subscript
   */

  unary() {
    var op
      , node;
    if (op =
      this.accept('!')
      || this.accept('~')
      || this.accept('+')
      || this.accept('-')) {
      this.operand = true;
      node = this.unary();
      if (!node) this.error('illegal unary "' + op + '"');
      node = new nodes.UnaryOp(op.type, node);
      this.operand = false;
      return node;
    }
    return this.subscript();
  }

  /**
   *   member ('[' expression ']')+ '='?
   * | member
   */

  subscript() {
    var node = this.member()
      , id;
    while (this.accept('[')) {
      node = new nodes.BinOp('[]', node, this.expression());
      this.expect(']');
    }
    // TODO: TernaryOp :)
    if (this.accept('=')) {
      node.op += '=';
      node.val = this.list();
      // @block support
      if (node.val.isEmpty) this.assignAtblock(node.val);
    }
    return node;
  }

  /**
   *   primary ('.' id)+ '='?
   * | primary
   */

  member() {
    var node = this.primary();
    if (node) {
      while (this.accept('.')) {
        var id = new nodes.Ident(this.expect('ident').val.string);
        node = new nodes.Member(node, id);
      }
      this.skipSpaces();
      if (this.accept('=')) {
        node.val = this.list();
        // @block support
        if (node.val.isEmpty) this.assignAtblock(node.val);
      }
    }
    return node;
  }

  /**
   *   '{' '}'
   * | '{' pair (ws pair)* '}'
   */

  object() {
    var obj = new nodes.Object
      , id, val, comma, hash;
    this.expect('{');
    this.skipWhitespace();

    while (!this.accept('}')) {
      if (this.accept('comment')
        || this.accept('newline')) continue;

      if (!comma) this.accept(',');
      id = this.accept('ident') || this.accept('string');

      if (!id) {
        this.error('expected "ident" or "string", got {peek}');
      }

      hash = id.val.hash;

      this.skipSpacesAndComments();
      this.expect(':');

      val = this.expression();

      obj.setValue(hash, val);
      obj.setKey(hash, id.val);

      comma = this.accept(',');
      this.skipWhitespace();
    }

    return obj;
  }

  /**
   *   unit
   * | null
   * | color
   * | string
   * | ident
   * | boolean
   * | literal
   * | object
   * | atblock
   * | atrule
   * | '(' expression ')' '%'?
   */

  primary() {
    var tok;
    this.skipSpaces();

    // Parenthesis
    if (this.accept('(')) {
      ++this.parens;
      var expr = this.expression()
        , paren = this.expect(')');
      --this.parens;
      if (this.accept('%')) expr.push(new nodes.Ident('%'));
      tok = this.peek();
      // (1 + 2)px, (1 + 2)em, etc.
      if (!paren.space
        && 'ident' == tok.type
        && ~units.indexOf(tok.val.string)) {
        expr.push(new nodes.Ident(tok.val.string));
        this.next();
      }
      return expr;
    }

    tok = this.peek();

    // Primitive
    switch (tok.type) {
      case 'null':
      case 'unit':
      case 'color':
      case 'string':
      case 'literal':
      case 'boolean':
      case 'comment':
        return this.next().val;
      case !this.cond && '{':
        return this.object();
      case 'atblock':
        return this.atblock();
      // property lookup
      case 'atrule':
        var id = new nodes.Ident(this.next().val);
        id.property = true;
        return id;
      case 'ident':
        return this.ident();
      case 'function':
        return tok.anonymous
          ? this.functionDefinition()
          : this.functionCall();
    }
  }
};

},{"./cache":60,"./errors":63,"./lexer":128,"./nodes":148,"./token":176,"./units":177,"debug":"debug"}],171:[function(require,module,exports){
(function (__dirname){(function (){

/*!
 * Stylus - Renderer
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Parser = require('./parser')
  , EventEmitter = require('events').EventEmitter
  , Evaluator = require('./visitor/evaluator')
  , Normalizer = require('./visitor/normalizer')
  , events = new EventEmitter
  , utils = require('./utils')
  , nodes = require('./nodes')
  , join = require('path').join;

class Renderer extends EventEmitter {
  /**
   * Initialize a new `Renderer` with the given `str` and `options`.
   *
   * @param {String} str
   * @param {Object} options
   * @api public
   */

  constructor(str, options) {
    super();
    options = options || {};
    options.globals = options.globals || {};
    options.functions = options.functions || {};
    options.use = options.use || [];
    options.use = Array.isArray(options.use) ? options.use : [options.use];
    options.imports = [join(__dirname, 'functions/index.styl')].concat(options.imports || []);
    options.paths = options.paths || [];
    options.filename = options.filename || 'stylus';
    options.Evaluator = options.Evaluator || Evaluator;
    this.options = options;
    this.str = str;
    this.events = events;
  }

  /**
   * Parse and evaluate AST, then callback `fn(err, css, js)`.
   *
   * @param {Function} fn
   * @api public
   */

  render(fn) {
    var parser = this.parser = new Parser(this.str, this.options);

    // use plugin(s)
    for (var i = 0, len = this.options.use.length; i < len; i++) {
      this.use(this.options.use[i]);
    }

    try {
      nodes.filename = this.options.filename;
      // parse
      var ast = parser.parse();

      // evaluate
      this.evaluator = new this.options.Evaluator(ast, this.options);
      this.nodes = nodes;
      this.evaluator.renderer = this;
      ast = this.evaluator.evaluate();

      // normalize
      var normalizer = new Normalizer(ast, this.options);
      ast = normalizer.normalize();

      // compile
      if (this.options.sourcemap) {
        throw new Error('unsupported_builtin: source maps are unavailable');
      }
      var compiler = new (require('./visitor/compiler'))(ast, this.options)
        , css = compiler.compile();
    } catch (err) {
      var options = {};
      options.input = err.input || this.str;
      options.filename = err.filename || this.options.filename;
      options.lineno = err.lineno || parser.lexer.lineno;
      options.column = err.column || parser.lexer.column;
      if (!fn) throw utils.formatException(err, options);
      return fn(utils.formatException(err, options));
    }

    // fire `end` event
    var listeners = this.listeners('end');
    if (fn) listeners.push(fn);
    for (var i = 0, len = listeners.length; i < len; i++) {
      var ret = listeners[i](null, css);
      if (ret) css = ret;
    }
    if (!fn) return css;
  }

  /**
   * Get dependencies of the compiled file.
   *
   * @param {String} [filename]
   * @return {Array}
   * @api public
   */

  deps(filename) {
    var opts = utils.merge({ cache: false }, this.options);
    if (filename) opts.filename = filename;

    var DepsResolver = require('./visitor/deps-resolver')
      , parser = new Parser(this.str, opts);

    try {
      nodes.filename = opts.filename;
      // parse
      var ast = parser.parse()
        , resolver = new DepsResolver(ast, opts);

      // resolve dependencies
      return resolver.resolve();
    } catch (err) {
      var options = {};
      options.input = err.input || this.str;
      options.filename = err.filename || opts.filename;
      options.lineno = err.lineno || parser.lexer.lineno;
      options.column = err.column || parser.lexer.column;
      throw utils.formatException(err, options);
    }
  };

  /**
   * Set option `key` to `val`.
   *
   * @param {String} key
   * @param {Mixed} val
   * @return {Renderer} for chaining
   * @api public
   */

  set(key, val) {
    this.options[key] = val;
    return this;
  };

  /**
   * Get option `key`.
   *
   * @param {String} key
   * @return {Mixed} val
   * @api public
   */

  get(key) {
    return this.options[key];
  };

  /**
   * Include the given `path` to the lookup paths array.
   *
   * @param {String} path
   * @return {Renderer} for chaining
   * @api public
   */

  include(path) {
    this.options.paths.push(path);
    return this;
  };

  /**
   * Use the given `fn`.
   *
   * This allows for plugins to alter the renderer in
   * any way they wish, exposing paths etc.
   *
   * @param {Function}
   * @return {Renderer} for chaining
   * @api public
   */

  use(fn) {
    fn.call(this, this);
    return this;
  };

  /**
   * Define function or global var with the given `name`. Optionally
   * the function may accept full expressions, by setting `raw`
   * to `true`.
   *
   * @param {String} name
   * @param {Function|Node} fn
   * @param {Boolean} [raw]
   * @return {Renderer} for chaining
   * @api public
   */

  define(name, fn, raw) {
    fn = utils.coerce(fn, raw);

    if (fn.nodeName) {
      this.options.globals[name] = fn;
      return this;
    }

    // function
    this.options.functions[name] = fn;
    if (undefined != raw) fn.raw = raw;
    return this;
  };

  /**
   * Import the given `file`.
   *
   * @param {String} file
   * @return {Renderer} for chaining
   * @api public
   */

  import(file) {
    this.options.imports.push(file);
    return this;
  };
};

/**
 * Expose `Renderer`.
 */

module.exports = Renderer;

/**
 * Expose events explicitly.
 */

module.exports.events = events;

}).call(this)}).call(this,"/../package-slim/lib")
},{"./nodes":148,"./parser":170,"./utils":178,"./visitor/compiler":179,"./visitor/deps-resolver":180,"./visitor/evaluator":181,"./visitor/normalizer":183,"events":22,"path":52}],172:[function(require,module,exports){
/*!
 * Stylus - Selector Parser
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

var COMBINATORS = ['>', '+', '~'];

module.exports = class SelectorParser {
  /**
   * Initialize a new `SelectorParser`
   * with the given `str` and selectors `stack`.
   *
   * @param {String} str
   * @param {Array} stack
   * @param {Array} parts
   * @api private
   */

  constructor(str, stack, parts) {
    this.str = str;
    this.stack = stack || [];
    this.parts = parts || [];
    this.pos = 0;
    this.level = 2;
    this.nested = true;
    this.ignore = false;
  }

  /**
   * Consume the given `len` and move current position.
   *
   * @param {Number} len
   * @api private
   */

  skip(len) {
    this.str = this.str.substr(len);
    this.pos += len;
  };

  /**
   * Consume spaces.
   */

  skipSpaces() {
    while (' ' == this.str[0]) this.skip(1);
  };

  /**
   * Fetch next token.
   *
   * @return {String}
   * @api private
   */

  advance() {
    return this.root()
      || this.relative()
      || this.initial()
      || this.escaped()
      || this.parent()
      || this.partial()
      || this.char();
  };

  /**
   * '/'
   */

  root() {
    if (!this.pos && '/' == this.str[0]
      && 'deep' != this.str.slice(1, 5)) {
      this.nested = false;
      this.skip(1);
    }
  };

  /**
   * '../'
   */

  relative(multi) {
    if ((!this.pos || multi) && '../' == this.str.slice(0, 3)) {
      this.nested = false;
      this.skip(3);
      while (this.relative(true)) this.level++;
      if (!this.raw) {
        var ret = this.stack[this.stack.length - this.level];
        if (ret) {
          return ret;
        } else {
          this.ignore = true;
        }
      }
    }
  };

  /**
   * '~/'
   */

  initial() {
    if (!this.pos && '~' == this.str[0] && '/' == this.str[1]) {
      this.nested = false;
      this.skip(2);
      return this.stack[0];
    }
  };

  /**
   * '\' ('&' | '^')
   */

  escaped() {
    if ('\\' == this.str[0]) {
      var char = this.str[1];
      if ('&' == char || '^' == char) {
        this.skip(2);
        return char;
      }
    }
  };

  /**
   * '&'
   */

  parent() {
    if ('&' == this.str[0]) {
      this.nested = false;

      if (!this.pos && (!this.stack.length || this.raw)) {
        var i = 0;
        while (' ' == this.str[++i]);
        if (~COMBINATORS.indexOf(this.str[i])) {
          this.skip(i + 1);
          return;
        }
      }

      this.skip(1);
      if (!this.raw)
        return this.stack[this.stack.length - 1];
    }
  };

  /**
   * '^[' range ']'
   */

  partial() {
    if ('^' == this.str[0] && '[' == this.str[1]) {
      this.skip(2);
      this.skipSpaces();
      var ret = this.range();
      this.skipSpaces();
      if (']' != this.str[0]) return '^[';
      this.nested = false;
      this.skip(1);
      if (ret) {
        return ret;
      } else {
        this.ignore = true;
      }
    }
  };

  /**
   * '-'? 0-9+
   */

  number() {
    var i = 0, ret = '';
    if ('-' == this.str[i])
      ret += this.str[i++];

    while (this.str.charCodeAt(i) >= 48
      && this.str.charCodeAt(i) <= 57)
      ret += this.str[i++];

    if (ret) {
      this.skip(i);
      return Number(ret);
    }
  };

  /**
   * number ('..' number)?
   */

  range() {
    var start = this.number()
      , ret;

    if ('..' == this.str.slice(0, 2)) {
      this.skip(2);
      var end = this.number()
        , len = this.parts.length;

      if (start < 0) start = len + start - 1;
      if (end < 0) end = len + end - 1;

      if (start > end) {
        var tmp = start;
        start = end;
        end = tmp;
      }

      if (end < len - 1) {
        ret = this.parts.slice(start, end + 1).map(function (part) {
          var selector = new SelectorParser(part, this.stack, this.parts);
          selector.raw = true;
          return selector.parse();
        }, this).map(function (selector) {
          return (selector.nested ? ' ' : '') + selector.val;
        }).join('').trim();
      }
    } else {
      ret = this.stack[
        start < 0 ? this.stack.length + start - 1 : start
      ];
    }

    if (ret) {
      return ret;
    } else {
      this.ignore = true;
    }
  };

  /**
   * .+
   */

  char() {
    var char = this.str[0];
    this.skip(1);
    return char;
  };

  /**
   * Parses the selector.
   *
   * @return {Object}
   * @api private
   */

  parse() {
    var val = '';
    while (this.str.length) {
      val += this.advance() || '';
      if (this.ignore) {
        val = '';
        break;
      }
    }
    return { val: val.trimRight(), nested: this.nested };
  };
};

},{}],173:[function(require,module,exports){

/*!
 * Stylus - stack - Frame
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Scope = require('./scope');

module.exports = class Frame {
  /**
   * Initialize a new `Frame` with the given `block`.
   *
   * @param {Block} block
   * @api private
   */

  constructor(block) {
    this._scope = false === block.scope
      ? null
      : new Scope;
    this.block = block;
  }

  /**
   * Return this frame's scope or the parent scope
   * for scope-less blocks.
   *
   * @return {Scope}
   * @api public
   */

  get scope() {
    return this._scope || this.parent.scope;
  };

  /**
   * Lookup the given local variable `name`.
   *
   * @param {String} name
   * @return {Node}
   * @api private
   */

  lookup(name) {
    return this.scope.lookup(name)
  };

  /**
   * Custom inspect.
   *
   * @return {String}
   * @api public
   */

  inspect() {
    return '[Frame '
      + (false === this.block.scope
        ? 'scope-less'
        : this.scope.inspect())
      + ']';
  };
};

},{"./scope":175}],174:[function(require,module,exports){

/*!
 * Stylus - Stack
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

module.exports = class Stack extends Array {
  /**
   * Initialize a new `Stack`.
   *
   * @api private
   */

  constructor() {
    super()
    Array.apply(this, arguments);
  }

  /**
   * Push the given `frame`.
   *
   * @param {Frame} frame
   * @api public
   */

  push(frame) {
    frame.stack = this;
    frame.parent = this.currentFrame;
    return [].push.apply(this, arguments);
  };

  /**
   * Return the current stack `Frame`.
   *
   * @return {Frame}
   * @api private
   */

  get currentFrame() {
    return this[this.length - 1];
  };

  /**
   * Lookup stack frame for the given `block`.
   *
   * @param {Block} block
   * @return {Frame}
   * @api private
   */

  getBlockFrame(block) {
    for (var i = 0; i < this.length; ++i) {
      if (block == this[i].block) {
        return this[i];
      }
    }
  };

  /**
   * Lookup the given local variable `name`, relative
   * to the lexical scope of the current frame's `Block`.
   *
   * When the result of a lookup is an identifier
   * a recursive lookup is performed, defaulting to
   * returning the identifier itself.
   *
   * @param {String} name
   * @return {Node}
   * @api private
   */

  lookup(name) {
    var block = this.currentFrame.block
      , val
      , ret;

    do {
      var frame = this.getBlockFrame(block);
      if (frame && (val = frame.lookup(name))) {
        return val;
      }
    } while (block = block.parent);
  };

  /**
   * Custom inspect.
   *
   * @return {String}
   * @api private
   */

  inspect() {
    return this.reverse().map(function (frame) {
      return frame.inspect();
    }).join('\n');
  };

  /**
   * Return stack string formatted as:
   *
   *   at <context> (<filename>:<lineno>:<column>)
   *
   * @return {String}
   * @api private
   */

  toString() {
    var block
      , node
      , buf = []
      , location
      , len = this.length;

    while (len--) {
      block = this[len].block;
      if (node = block.node) {
        location = '(' + node.filename + ':' + (node.lineno + 1) + ':' + node.column + ')';
        switch (node.nodeName) {
          case 'function':
            buf.push('    at ' + node.name + '() ' + location);
            break;
          case 'group':
            buf.push('    at "' + node.nodes[0].val + '" ' + location);
            break;
        }
      }
    }

    return buf.join('\n');
  };
};

},{}],175:[function(require,module,exports){

/*!
 * Stylus - stack - Scope
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

module.exports = class Scope {
  /**
   * Initialize a new `Scope`.
   *
   * @api private
   */

  constructor() {
    this.locals = {};
  }

  /**
   * Add `ident` node to the current scope.
   *
   * @param {Ident} ident
   * @api private
   */

  add(ident) {
    this.locals[ident.name] = ident.val;
  };

  /**
   * Lookup the given local variable `name`.
   *
   * @param {String} name
   * @return {Node}
   * @api private
   */

  lookup(name) {
    return this.locals.hasOwnProperty(name) ? this.locals[name] : undefined;
  };

  /**
   * Custom inspect.
   *
   * @return {String}
   * @api public
   */

  inspect() {
    var keys = Object.keys(this.locals).map(function (key) { return '@' + key; });
    return '[Scope'
      + (keys.length ? ' ' + keys.join(', ') : '')
      + ']';
  };
};

},{}],176:[function(require,module,exports){

/*!
 * Stylus - Token
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var inspect = require('util').inspect;

exports = module.exports = class Token {
  /**
   * Initialize a new `Token` with the given `type` and `val`.
   *
   * @param {String} type
   * @param {Mixed} val
   * @api private
   */

  constructor(type, val) {
    this.type = type;
    this.val = val;
  }

  /**
   * Custom inspect.
   *
   * @return {String}
   * @api public
   */

  inspect() {
    var val = ' ' + inspect(this.val);
    return '[Token:' + this.lineno + ':' + this.column + ' '
      + '\x1b[32m' + this.type + '\x1b[0m'
      + '\x1b[33m' + (this.val ? val : '') + '\x1b[0m'
      + ']';
  };

  /**
   * Return type or val.
   *
   * @return {String}
   * @api public
   */

  toString() {
    return (undefined === this.val
      ? this.type
      : this.val).toString();
  };
};

},{"util":58}],177:[function(require,module,exports){

/*!
 * Stylus - units
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

// units found in http://www.w3.org/TR/css3-values
// and in https://www.w3.org/TR/css-values-4

module.exports = [
    'em', 'ex', 'ch', 'rem' // relative lengths

  , 'vw', 'svw', 'lvw', 'dvw' // relative viewport-percentage lengths (including de-facto standard)
  , 'vh', 'svh', 'lvh', 'dvh'
  , 'vi', 'svi', 'lvi', 'dvi'
  , 'vb', 'svb', 'lvb', 'dvb'
  , 'vmin', 'svmin', 'lvmin', 'dvmin'
  , 'vmax', 'svmax', 'lvmax', 'dvmax'

  , 'cm', 'mm', 'in', 'pt', 'pc', 'px' // absolute lengths
  , 'deg', 'grad', 'rad', 'turn' // angles
  , 's', 'ms' // times
  , 'Hz', 'kHz' // frequencies
  , 'dpi', 'dpcm', 'dppx', 'x' // resolutions
  , '%' // percentage type
  , 'fr' // grid-layout (http://www.w3.org/TR/css3-grid-layout/)
];

},{}],178:[function(require,module,exports){
(function (__dirname){(function (){

/*!
 * Stylus - utils
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var nodes = require('./nodes')
  , basename = require('path').basename
  , relative = require('path').relative
  , join = require('path').join
  , isAbsolute = require('path').isAbsolute
  , glob = require('glob')
  , fs = require('fs');

/**
 * Check if `path` looks absolute.
 *
 * @param {String} path
 * @return {Boolean}
 * @api private
 */

exports.absolute = isAbsolute || function(path){
  // On Windows the path could start with a drive letter, i.e. a:\\ or two leading backslashes.
  // Also on Windows, the path may have been normalized to forward slashes, so check for this too.
  return path.substr(0, 2) == '\\\\' || '/' === path.charAt(0) || /^[a-z]:[\\\/]/i.test(path);
};

/**
 * Attempt to lookup `path` within `paths` from tail to head.
 * Optionally a path to `ignore` may be passed.
 *
 * @param {String} path
 * @param {String} paths
 * @param {String} ignore
 * @return {String}
 * @api private
 */

exports.lookup = function(path, paths, ignore){
  var lookup
    , i = paths.length;

  // Absolute
  if (exports.absolute(path)) {
    try {
      fs.statSync(path);
      return path;
    } catch (err) {
      // Ignore, continue on
      // to trying relative lookup.
      // Needed for url(/images/foo.png)
      // for example
    }
  }

  // Relative
  while (i--) {
    try {
      lookup = join(paths[i], path);
      if (ignore == lookup) continue;
      fs.statSync(lookup);
      return lookup;
    } catch (err) {
      // Ignore
    }
  }
};

/**
 * Like `utils.lookup` but uses `glob` to find files.
 *
 * @param {String} path
 * @param {String} paths
 * @param {String} ignore
 * @return {Array}
 * @api private
 */
exports.find = function(path, paths, ignore) {
  var lookup
    , found
    , i = paths.length;

  // Absolute
  if (exports.absolute(path)) {
    if ((found = glob.sync(path, {windowsPathsNoEscape: true, posix: true})).length) {
      return found.sort();
    }
  }

  // Relative
  while (i--) {
    lookup = join(paths[i], path);
    if (ignore == lookup) continue;
    if ((found = glob.sync(lookup, {windowsPathsNoEscape: true, posix: true})).length) {
      return found.sort();
    }
  }
};

/**
 * Lookup index file inside dir with given `name`.
 *
 * @param {String} name
 * @return {Array}
 * @api private
 */

exports.lookupIndex = function(name, paths, filename){
  // foo/index.styl
  var found = exports.find(join(name, 'index.styl'), paths, filename);
  if (!found) {
    // foo/foo.styl
    found = exports.find(join(name, basename(name).replace(/\.styl/i, '') + '.styl'), paths, filename);
  }
  if (!found && !~name.indexOf('node_modules')) {
    // node_modules/foo/.. or node_modules/foo.styl/..
    found = lookupPackage(join('node_modules', name));
  }
  return found;

  function lookupPackage(dir) {
    var pkg = exports.lookup(join(dir, 'package.json'), paths, filename);
    if (!pkg) {
      return /\.styl$/i.test(dir) ? exports.lookupIndex(dir, paths, filename) : lookupPackage(dir + '.styl');
    }
    var main = require(relative(__dirname, pkg)).main;
    if (main) {
      found = exports.find(join(dir, main), paths, filename);
    } else {
      found = exports.lookupIndex(dir, paths, filename);
    }
    return found;
  }
};

/**
 * Format the given `err` with the given `options`.
 *
 * Options:
 *
 *   - `filename`   context filename
 *   - `context`    context line count [8]
 *   - `lineno`     context line number
 *   - `column`     context column number
 *   - `input`        input string
 *
 * @param {Error} err
 * @param {Object} options
 * @return {Error}
 * @api private
 */

exports.formatException = function(err, options){
  var lineno = options.lineno
    , column = options.column
    , filename = options.filename
    , str = options.input
    , context = options.context || 8
    , context = context / 2
    , lines = ('\n' + str).split('\n')
    , start = Math.max(lineno - context, 1)
    , end = Math.min(lines.length, lineno + context)
    , pad = end.toString().length;

  var context = lines.slice(start, end).map(function(line, i){
    var curr = i + start;
    return '   '
      + Array(pad - curr.toString().length + 1).join(' ')
      + curr
      + '| '
      + line
      + (curr == lineno
        ? '\n' + Array(curr.toString().length + 5 + column).join('-') + '^'
        : '');
  }).join('\n');

  err.message = filename
    + ':' + lineno
    + ':' + column
    + '\n' + context
    + '\n\n' + err.message + '\n'
    + (err.stylusStack ? err.stylusStack + '\n' : '');

  // Don't show JS stack trace for Stylus errors
  if (err.fromStylus) err.stack = 'Error: ' + err.message;

  return err;
};

/**
 * Assert that `node` is of the given `type`, or throw.
 *
 * @param {Node} node
 * @param {Function} type
 * @param {String} param
 * @api public
 */

exports.assertType = function(node, type, param){
  exports.assertPresent(node, param);
  if (node.nodeName == type) return;
  var actual = node.nodeName
    , msg = 'expected '
      + (param ? '"' + param + '" to be a ' :  '')
      + type + ', but got '
      + actual + ':' + node;
  throw new Error('TypeError: ' + msg);
};

/**
 * Assert that `node` is a `String` or `Ident`.
 *
 * @param {Node} node
 * @param {String} param
 * @api public
 */

exports.assertString = function(node, param){
  exports.assertPresent(node, param);
  switch (node.nodeName) {
    case 'string':
    case 'ident':
    case 'literal':
      return;
    default:
      var actual = node.nodeName
        , msg = 'expected string, ident or literal, but got ' + actual + ':' + node;
      throw new Error('TypeError: ' + msg);
  }
};

/**
 * Assert that `node` is a `RGBA` or `HSLA`.
 *
 * @param {Node} node
 * @param {String} param
 * @api public
 */

exports.assertColor = function(node, param){
  exports.assertPresent(node, param);
  switch (node.nodeName) {
    case 'rgba':
    case 'hsla':
      return;
    default:
      var actual = node.nodeName
        , msg = 'expected rgba or hsla, but got ' + actual + ':' + node;
      throw new Error('TypeError: ' + msg);
  }
};

/**
 * Assert that param `name` is given, aka the `node` is passed.
 *
 * @param {Node} node
 * @param {String} name
 * @api public
 */

exports.assertPresent = function(node, name){
  if (node) return;
  if (name) throw new Error('"' + name + '" argument required');
  throw new Error('argument missing');
};

/**
 * Unwrap `expr`.
 *
 * Takes an expressions with length of 1
 * such as `((1 2 3))` and unwraps it to `(1 2 3)`.
 *
 * @param {Expression} expr
 * @return {Node}
 * @api public
 */

exports.unwrap = function(expr){
  // explicitly preserve the expression
  if (expr.preserve) return expr;
  if ('arguments' != expr.nodeName && 'expression' != expr.nodeName) return expr;
  if (1 != expr.nodes.length) return expr;
  if ('arguments' != expr.nodes[0].nodeName && 'expression' != expr.nodes[0].nodeName) return expr;
  return exports.unwrap(expr.nodes[0]);
};

/**
 * Coerce JavaScript values to their Stylus equivalents.
 *
 * @param {Mixed} val
 * @param {Boolean} [raw]
 * @return {Node}
 * @api public
 */

exports.coerce = function(val, raw){
  switch (typeof val) {
    case 'function':
      return val;
    case 'string':
      return new nodes.String(val);
    case 'boolean':
      return new nodes.Boolean(val);
    case 'number':
      return new nodes.Unit(val);
    default:
      if (null == val) return nodes.null;
      if (Array.isArray(val)) return exports.coerceArray(val, raw);
      if (val.nodeName) return val;
      return exports.coerceObject(val, raw);
  }
};

/**
 * Coerce a javascript `Array` to a Stylus `Expression`.
 *
 * @param {Array} val
 * @param {Boolean} [raw]
 * @return {Expression}
 * @api private
 */

exports.coerceArray = function(val, raw){
  var expr = new nodes.Expression;
  val.forEach(function(val){
    expr.push(exports.coerce(val, raw));
  });
  return expr;
};

/**
 * Coerce a javascript object to a Stylus `Expression` or `Object`.
 *
 * For example `{ foo: 'bar', bar: 'baz' }` would become
 * the expression `(foo 'bar') (bar 'baz')`. If `raw` is true
 * given `obj` would become a Stylus hash object.
 *
 * @param {Object} obj
 * @param {Boolean} [raw]
 * @return {Expression|Object}
 * @api public
 */

exports.coerceObject = function(obj, raw){
  var node = raw ? new nodes.Object : new nodes.Expression
    , val;

  for (var key in obj) {
    val = exports.coerce(obj[key], raw);
    key = new nodes.Ident(key);
    if (raw) {
      node.set(key, val);
    } else {
      node.push(exports.coerceArray([key, val]));
    }
  }

  return node;
};

/**
 * Return param names for `fn`.
 *
 * @param {Function} fn
 * @return {Array}
 * @api private
 */

exports.params = function(fn){
  return fn
    .toString()
    .match(/\(([^)]*)\)/)[1].split(/ *, */);
};

/**
 * Merge object `b` with `a`.
 *
 * @param {Object} a
 * @param {Object} b
 * @param {Boolean} [deep]
 * @return {Object} a
 * @api private
 */
exports.merge = function(a, b, deep) {
  for (var k in b) {
    if (deep && a[k]) {
      var nodeA = exports.unwrap(a[k]).first
        , nodeB = exports.unwrap(b[k]).first;

      if ('object' == nodeA.nodeName && 'object' == nodeB.nodeName) {
        a[k].first.vals = exports.merge(nodeA.vals, nodeB.vals, deep);
      } else {
        a[k] = b[k];
      }
    } else {
      a[k] = b[k];
    }
  }
  return a;
};

/**
 * Returns an array with unique values.
 *
 * @param {Array} arr
 * @return {Array}
 * @api private
 */

exports.uniq = function(arr){
  var obj = {}
    , ret = [];

  for (var i = 0, len = arr.length; i < len; ++i) {
    if (arr[i] in obj) continue;

    obj[arr[i]] = true;
    ret.push(arr[i]);
  }
  return ret;
};

/**
 * Compile selector strings in `arr` from the bottom-up
 * to produce the selector combinations. For example
 * the following Stylus:
 *
 *    ul
 *      li
 *      p
 *        a
 *          color: red
 *
 * Would return:
 *
 *      [ 'ul li a', 'ul p a' ]
 *
 * @param {Array} arr
 * @param {Boolean} leaveHidden
 * @return {Array}
 * @api private
 */

exports.compileSelectors = function(arr, leaveHidden){
  var selectors = []
    , Parser = require('./selector-parser')
    , indent = (this.indent || '')
    , buf = [];

  function parse(selector, buf) {
    var parts = [selector.val]
      , str = new Parser(parts[0], parents, parts).parse().val
      , parents = [];

    if (buf.length) {
      for (var i = 0, len = buf.length; i < len; ++i) {
        parts.push(buf[i]);
        parents.push(str);
        var child = new Parser(buf[i], parents, parts).parse();

        if (child.nested) {
          str += ' ' + child.val;
        } else {
          str = child.val;
        }
      }
    }
    return str.trim();
  }

  function compile(arr, i) {
    if (i) {
      arr[i].forEach(function(selector){
        if (!leaveHidden && selector.isPlaceholder) return;
        if (selector.inherits) {
          buf.unshift(selector.val);
          compile(arr, i - 1);
          buf.shift();
        } else {
          selectors.push(indent + parse(selector, buf));
        }
      });
    } else {
      arr[0].forEach(function(selector){
        if (!leaveHidden && selector.isPlaceholder) return;
        var str = parse(selector, buf);
        if (str) selectors.push(indent + str);
      });
    }
  }

  compile(arr, arr.length - 1);

  // Return the list with unique selectors only
  return exports.uniq(selectors);
};

/**
 * Attempt to parse string.
 *
 * @param {String} str
 * @return {Node}
 * @api private
 */

exports.parseString = function(str){
  var Parser = require('./parser')
    , parser
    , ret;

  try {
    parser = new Parser(str);
    ret = parser.list();
  } catch (e) {
    ret = new nodes.Literal(str);
  }
  return ret;
};

}).call(this)}).call(this,"/../package-slim/lib")
},{"./nodes":148,"./parser":170,"./selector-parser":172,"fs":"fs","glob":"glob","path":52}],179:[function(require,module,exports){
/*!
 * Stylus - Compiler
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Visitor = require('./')
  , utils = require('../utils')
  , fs = require('fs');

module.exports = class Compiler extends Visitor {
  /**
   * Initialize a new `Compiler` with the given `root` Node
   * and the following `options`.
   *
   * Options:
   *
   *   - `compress`  Compress the CSS output (default: false)
   *
   * @param {Node} root
   * @api public
   */

  constructor(root, options) {
    super(root);
    options = options || {};
    this.compress = options.compress;
    this.firebug = options.firebug;
    this.linenos = options.linenos;
    this.spaces = options['indent spaces'] || 2;
    this.indents = 1;
    this.stack = [];
  }

  /**
   * Compile to css, and return a string of CSS.
   *
   * @return {String}
   * @api private
   */

  compile() {
    return this.visit(this.root);
  };

  /**
   * Output `str`
   *
   * @param {String} str
   * @param {Node} node
   * @return {String}
   * @api private
   */

  out(str, node) {
    return str;
  };

  /**
   * Return indentation string.
   *
   * @return {String}
   * @api private
   */

  get indent() {
    if (this.compress) return '';
    return new Array(this.indents).join(Array(this.spaces + 1).join(' '));
  };

  /**
   * Check if given `node` needs brackets.
   *
   * @param {Node} node
   * @return {Boolean}
   * @api private
   */

  needBrackets(node) {
    return 1 == this.indents
      || 'atrule' != node.nodeName
      || node.hasOnlyProperties;
  };

  /**
   * Visit Root.
   */

  visitRoot(block) {
    this.buf = '';
    for (var i = 0, len = block.nodes.length; i < len; ++i) {
      var node = block.nodes[i];
      if (this.linenos || this.firebug) this.debugInfo(node);
      var ret = this.visit(node);
      if (ret) this.buf += this.out(ret + '\n', node);
    }
    return this.buf;
  };

  /**
   * Visit Block.
   */

  visitBlock(block) {
    var node
      , separator = this.compress ? '' : '\n'
      , needBrackets
      , lastPropertyIndex;

    if (block.hasProperties && !block.lacksRenderedSelectors) {
      needBrackets = this.needBrackets(block.node);

      if (this.compress) {
        for (var i = block.nodes.length - 1; i >= 0; --i) {
          if (block.nodes[i].nodeName === 'property') {
            lastPropertyIndex = i;
            break;
          }
        }
      }
      if (needBrackets) {
        this.buf += this.out(this.compress ? '{' : ' {\n');
        ++this.indents;
      }
      for (var i = 0, len = block.nodes.length; i < len; ++i) {
        this.last = lastPropertyIndex === i;
        node = block.nodes[i];
        switch (node.nodeName) {
          case 'null':
          case 'expression':
          case 'function':
          case 'group':
          case 'block':
          case 'unit':
          case 'media':
          case 'keyframes':
          case 'atrule':
          case 'supports':
            continue;
          // inline comments
          case !this.compress && node.inline && 'comment':
            this.buf = this.buf.slice(0, -1);
            this.buf += this.out(' ' + this.visit(node) + '\n', node);
            break;
          case 'property':
            var ret = this.visit(node) + separator;
            this.buf += this.compress ? ret : this.out(ret, node);
            break;
          default:
            this.buf += this.out(this.visit(node) + separator, node);
        }
      }
      if (needBrackets) {
        --this.indents;
        this.buf += this.out(this.indent + '}' + separator);
      }
    }

    // Nesting
    for (var i = 0, len = block.nodes.length; i < len; ++i) {
      node = block.nodes[i];
      switch (node.nodeName) {
        case 'group':
        case 'block':
        case 'keyframes':
          if (this.linenos || this.firebug) this.debugInfo(node);
          this.visit(node);
          break;
        case 'media':
        case 'import':
        case 'atrule':
        case 'supports':
          this.visit(node);
          break;
        case 'comment':
          // only show unsuppressed comments
          if (!node.suppress) {
            this.buf += this.out(this.indent + this.visit(node) + '\n', node);
          }
          break;
        case 'charset':
        case 'literal':
        case 'namespace':
          this.buf += this.out(this.visit(node) + '\n', node);
          break;
      }
    }
  };

  /**
   * Visit Keyframes.
   */

  visitKeyframes(node) {
    if (!node.frames) return;

    var prefix = 'official' == node.prefix
      ? ''
      : '-' + node.prefix + '-';

    this.buf += this.out('@' + prefix + 'keyframes '
      + this.visit(node.val)
      + (this.compress ? '{' : ' {\n'), node);

    this.keyframe = true;
    ++this.indents;
    this.visit(node.block);
    --this.indents;
    this.keyframe = false;

    this.buf += this.out('}' + (this.compress ? '' : '\n'));
  };

  /**
   * Visit Media.
   */

  visitMedia(media) {
    var val = media.val;
    if (!media.hasOutput || !val.nodes.length) return;

    this.buf += this.out('@media ', media);
    this.visit(val);
    this.buf += this.out(this.compress ? '{' : ' {\n');
    ++this.indents;
    this.visit(media.block);
    --this.indents;
    this.buf += this.out('}' + (this.compress ? '' : '\n'));
  };

  /**
   * Visit QueryList.
   */

  visitQueryList(queries) {
    for (var i = 0, len = queries.nodes.length; i < len; ++i) {
      this.visit(queries.nodes[i]);
      if (len - 1 != i) this.buf += this.out(',' + (this.compress ? '' : ' '));
    }
  };

  /**
   * Visit Query.
   */

  visitQuery(node) {
    var len = node.nodes.length;
    if (node.predicate) this.buf += this.out(node.predicate + ' ');
    if (node.type) this.buf += this.out(node.type + (len ? ' and ' : ''));
    for (var i = 0; i < len; ++i) {
      this.buf += this.out(this.visit(node.nodes[i]));
      if (len - 1 != i) this.buf += this.out(' and ');
    }
  };

  /**
   * Visit Feature.
   */

  visitFeature(node) {
    if (!node.expr) {
      return node.name;
    } else if (node.expr.isEmpty) {
      return '(' + node.name + ')';
    } else {
      return '(' + node.name + ':' + (this.compress ? '' : ' ') + this.visit(node.expr) + ')';
    }
  };

  /**
   * Visit Import.
   */

  visitImport(imported) {
    this.buf += this.out('@import ' + this.visit(imported.path) + ';\n', imported);
  };

  /**
   * Visit Atrule.
   */

  visitAtrule(atrule) {
    var newline = this.compress ? '' : '\n';

    this.buf += this.out(this.indent + '@' + atrule.type, atrule);

    if (atrule.val) this.buf += this.out(' ' + atrule.val.trim());

    if (atrule.block) {
      if (atrule.block.isEmpty) {
        this.buf += this.out((this.compress ? '' : ' ') + '{}' + newline);
      } else if (atrule.hasOnlyProperties) {
        this.visit(atrule.block);
      } else {
        this.buf += this.out(this.compress ? '{' : ' {\n');
        ++this.indents;
        this.visit(atrule.block);
        --this.indents;
        this.buf += this.out(this.indent + '}' + newline);
      }
    } else {
      this.buf += this.out(';' + newline);
    }
  };

  /**
   * Visit Supports.
   */

  visitSupports(node) {
    if (!node.hasOutput) return;

    this.buf += this.out(this.indent + '@supports ', node);
    this.isCondition = true;
    this.buf += this.out(this.visit(node.condition));
    this.isCondition = false;
    this.buf += this.out(this.compress ? '{' : ' {\n');
    ++this.indents;
    this.visit(node.block);
    --this.indents;
    this.buf += this.out(this.indent + '}' + (this.compress ? '' : '\n'));
  }

  /**
   * Visit Comment.
   */

  visitComment(comment) {
    return this.compress
      ? comment.suppress
        ? ''
        : comment.str
      : comment.str;
  };

  /**
   * Visit Function.
   */

  visitFunction(fn) {
    return fn.name;
  };

  /**
   * Visit Charset.
   */

  visitCharset(charset) {
    return '@charset ' + this.visit(charset.val) + ';';
  };

  /**
   * Visit Namespace.
   */

  visitNamespace(namespace) {
    return '@namespace '
      + (namespace.prefix ? this.visit(namespace.prefix) + ' ' : '')
      + this.visit(namespace.val) + ';';
  };

  /**
   * Visit Literal.
   */

  visitLiteral(lit) {
    var val = lit.val;
    if (lit.css) val = val.replace(/^  /gm, '');
    return val;
  };

  /**
   * Visit Boolean.
   */

  visitBoolean(bool) {
    return bool.toString();
  };

  /**
   * Visit RGBA.
   */

  visitRGBA(rgba) {
    return rgba.toString();
  };

  /**
   * Visit HSLA.
   */

  visitHSLA(hsla) {
    return hsla.rgba.toString();
  };

  /**
   * Visit Unit.
   */

  visitUnit(unit) {
    var type = unit.type || ''
      , n = unit.val
      , float = n != (n | 0);

    // Compress
    if (this.compress) {
      // Always return '0' unless the unit is a percentage, time, degree or fraction
      if (!(['%', 's', 'ms', 'deg', 'fr'].includes(type)) && 0 == n) return '0';
      // Omit leading '0' on floats
      if (float && n < 1 && n > -1) {
        return n.toString().replace('0.', '.') + type;
      }
    }

    return (float ? parseFloat(n.toFixed(15)) : n).toString() + type;
  };

  /**
   * Visit Group.
   */

  visitGroup(group) {
    var stack = this.keyframe ? [] : this.stack
      , comma = this.compress ? ',' : ',\n';

    stack.push(group.nodes);

    // selectors
    if (group.block.hasProperties) {
      var selectors = utils.compileSelectors.call(this, stack)
        , len = selectors.length;

      if (len) {
        if (this.keyframe) comma = this.compress ? ',' : ', ';

        for (var i = 0; i < len; ++i) {
          var selector = selectors[i]
            , last = (i == len - 1);

          // keyframe blocks (10%, 20% { ... })
          if (this.keyframe) selector = i ? selector.trim() : selector;

          this.buf += this.out(selector + (last ? '' : comma), group.nodes[i]);
        }
      } else {
        group.block.lacksRenderedSelectors = true;
      }
    }

    // output block
    this.visit(group.block);
    stack.pop();
  };

  /**
   * Visit Ident.
   */

  visitIdent(ident) {
    return ident.name;
  };

  /**
   * Visit String.
   */

  visitString(string) {
    return this.isURL
      ? string.val
      : string.toString();
  };

  /**
   * Visit Null.
   */

  visitNull(node) {
    return '';
  };

  /**
   * Visit Call.
   */

  visitCall(call) {
    this.isURL = 'url' == call.name;
    var args = call.args.nodes.map(function (arg) {
      return this.visit(arg);
    }, this).join(this.compress ? ',' : ', ');
    if (this.isURL) args = '"' + args + '"';
    this.isURL = false;
    return call.name + '(' + args + ')';
  };

  /**
   * Visit Expression.
   */

  visitExpression(expr) {
    var buf = []
      , self = this
      , len = expr.nodes.length
      , nodes = expr.nodes.map(function (node) { return self.visit(node); });

    nodes.forEach(function (node, i) {
      var last = i == len - 1;
      buf.push(node);
      if ('/' == nodes[i + 1] || '/' == node) return;
      if (last) return;

      var space = self.isURL || (self.isCondition
        && (')' == nodes[i + 1] || '(' == node))
        ? '' : ' ';

      buf.push(expr.isList
        ? (self.compress ? ',' : ', ')
        : space);
    });

    return buf.join('');
  };

  /**
   * Visit Arguments.
   */

  get visitArguments() {
    return this.visitExpression;
  }

  /**
   * Visit Property.
   */

  visitProperty(prop) {
    var val = this.visit(prop.expr).trim()
      , name = (prop.name || prop.segments.join(''))
      , arr = [];

    if (name === '@apply') {
      arr.push(
        this.out(this.indent),
        this.out(name + ' ', prop),
        this.out(val, prop.expr),
        this.out(this.compress ? (this.last ? '' : ';') : ';')
      );
      return arr.join('');
    }
    arr.push(
      this.out(this.indent),
      this.out(name + (this.compress ? ':' : ': '), prop),
      this.out(val, prop.expr),
      this.out(this.compress ? (this.last ? '' : ';') : ';')
    );
    return arr.join('');
  };

  /**
   * Debug info.
   */

  debugInfo(node) {

    var path = node.filename == 'stdin' ? 'stdin' : fs.realpathSync(node.filename)
      , line = (node.nodes && node.nodes.length ? node.nodes[0].lineno : node.lineno) || 1;

    if (this.linenos) {
      this.buf += '\n/* ' + 'line ' + line + ' : ' + path + ' */\n';
    }

    if (this.firebug) {
      // debug info for firebug, the crazy formatting is needed
      path = 'file\\\:\\\/\\\/' + path.replace(/([.:/\\])/g, function (m) {
        return '\\' + (m === '\\' ? '\/' : m)
      });
      line = '\\00003' + line;
      this.buf += '\n@media -stylus-debug-info'
        + '{filename{font-family:' + path
        + '}line{font-family:' + line + '}}\n';
    }
  }

};

},{"../utils":178,"./":182,"fs":"fs"}],180:[function(require,module,exports){

/**
 * Module dependencies.
 */

var Visitor = require('./')
  , Parser = require('../parser')
  , nodes = require('../nodes')
  , utils = require('../utils')
  , dirname = require('path').dirname
  , fs = require('fs');

module.exports = class DepsResolver extends Visitor {
  /**
   * Initialize a new `DepsResolver` with the given `root` Node
   * and the `options`.
   *
   * @param {Node} root
   * @param {Object} options
   * @api private
   */

  constructor(root, options) {
    super(root)
    this.filename = options.filename;
    this.paths = options.paths || [];
    this.paths.push(dirname(options.filename || '.'));
    this.options = options;
    this.functions = {};
    this.deps = [];
  }


  visit(node) {
    switch (node.nodeName) {
      case 'root':
      case 'block':
      case 'expression':
        this.visitRoot(node);
        break;
      case 'group':
      case 'media':
      case 'atblock':
      case 'atrule':
      case 'keyframes':
      case 'each':
      case 'supports':
        this.visit(node.block);
        break;
      default:
        super.visit(node);
    }
  };

  /**
   * Visit Root.
   */

  visitRoot(block) {
    for (var i = 0, len = block.nodes.length; i < len; ++i) {
      this.visit(block.nodes[i]);
    }
  };

  /**
   * Visit Ident.
   */

  visitIdent(ident) {
    this.visit(ident.val);
  };

  /**
   * Visit If.
   */

  visitIf(node) {
    this.visit(node.block);
    this.visit(node.cond);
    for (var i = 0, len = node.elses.length; i < len; ++i) {
      this.visit(node.elses[i]);
    }
  };

  /**
   * Visit Function.
   */

  visitFunction(fn) {
    this.functions[fn.name] = fn.block;
  };

  /**
   * Visit Call.
   */

  visitCall(call) {
    if (call.name in this.functions) this.visit(this.functions[call.name]);
    if (call.block) this.visit(call.block);
  };

  /**
   * Visit Import.
   */

  visitImport(node) {
    // If it's a url() call, skip
    if (node.path.first.name === 'url') return;

    var path = !node.path.first.val.isNull && node.path.first.val || node.path.first.name
      , literal, found, oldPath;

    if (!path) return;

    literal = /\.css(?:"|$)/.test(path);

    // support optional .styl
    if (!literal && !/\.styl$/i.test(path)) {
      oldPath = path;
      path += '.styl';
    }

    // Lookup
    found = utils.find(path, this.paths, this.filename);

    // support optional index
    if (!found && oldPath) found = utils.lookupIndex(oldPath, this.paths, this.filename);

    if (!found) return;

    this.deps = this.deps.concat(found);

    if (literal) return;

    // nested imports
    for (var i = 0, len = found.length; i < len; ++i) {
      var file = found[i]
        , dir = dirname(file)
        , str = fs.readFileSync(file, 'utf-8')
        , block = new nodes.Block
        , parser = new Parser(str, utils.merge({ root: block }, this.options));

      if (!~this.paths.indexOf(dir)) this.paths.push(dir);

      try {
        block = parser.parse();
      } catch (err) {
        err.filename = file;
        err.lineno = parser.lexer.lineno;
        err.column = parser.lexer.column;
        err.input = str;
        throw err;
      }

      this.visit(block);
    }
  };

  /**
   * Get dependencies.
   */

  resolve() {
    this.visit(this.root);
    return utils.uniq(this.deps);
  };
};

},{"../nodes":148,"../parser":170,"../utils":178,"./":182,"fs":"fs","path":52}],181:[function(require,module,exports){

/*!
 * Stylus - Evaluator
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Visitor = require('./')
  , units = require('../units')
  , nodes = require('../nodes')
  , Stack = require('../stack')
  , Frame = require('../stack/frame')
  , utils = require('../utils')
  , bifs = require('../functions')
  , dirname = require('path').dirname
  , colors = require('../colors')
  , debug = require('debug')('stylus:evaluator');

/**
 * Import `file` and return Block node.
 *
 * @api private
 */
function importFile(node, file, literal) {
  var importStack = this.importStack
    , Parser = require('../parser')
    , stat;

  // Handling the `require`
  if (node.once) {
    if (this.requireHistory[file]) return nodes.null;
    this.requireHistory[file] = true;

    if (literal && !this.includeCSS) {
      return node;
    }
  }

  // Avoid overflows from importing the same file over again
  if (~importStack.indexOf(file))
    throw new Error('import loop has been found');

  var str = fs.readFileSync(file, 'utf8');

  // shortcut for empty files
  if (!str.trim()) return nodes.null;

  // Expose imports
  node.path = file;
  node.dirname = dirname(file);
  // Store the modified time
  stat = fs.statSync(file);
  node.mtime = stat.mtime;
  this.paths.push(node.dirname);

  if (this.options._imports) this.options._imports.push(node.clone());

  // Parse the file
  importStack.push(file);
  nodes.filename = file;

  if (literal) {
    literal = new nodes.Literal(str.replace(/\r\n?/g, '\n'));
    literal.lineno = literal.column = 1;
    if (!this.resolveURL) return literal;
  }

  // parse
  var block = new nodes.Block
    , parser = new Parser(str, utils.merge({ root: block }, this.options));

  try {
    block = parser.parse();
  } catch (err) {
    var line = parser.lexer.lineno
      , column = parser.lexer.column;

    if (literal && this.includeCSS && this.resolveURL) {
      this.warn('ParseError: ' + file + ':' + line + ':' + column + '. This file included as-is');
      return literal;
    } else {
      err.filename = file;
      err.lineno = line;
      err.column = column;
      err.input = str;
      throw err;
    }
  }

  // Evaluate imported "root"
  block = block.clone(this.currentBlock);
  block.parent = this.currentBlock;
  block.scope = false;
  var ret = this.visit(block);
  importStack.pop();
  if (!this.resolveURL || this.resolveURL.nocheck) this.paths.pop();

  return ret;
}

module.exports = class Evaluator extends Visitor {
  /**
   * Initialize a new `Evaluator` with the given `root` Node
   * and the following `options`.
   *
   * Options:
   *
   *   - `compress`  Compress the css output, defaults to false
   *   - `warn`  Warn the user of duplicate function definitions etc
   *
   * @param {Node} root
   * @api private
   */

  constructor(root, options) {
    super(root);
    options = options || {};
    var functions = this.functions = options.functions || {};
    this.stack = new Stack;
    this.imports = options.imports || [];
    this.globals = options.globals || {};
    this.paths = options.paths || [];
    this.prefix = options.prefix || '';
    this.filename = options.filename;
    this.includeCSS = options['include css'];
    this.resolveURL = functions.url
      && 'resolver' == functions.url.name
      && functions.url.options;
    this.paths.push(dirname(options.filename || '.'));
    this.stack.push(this.global = new Frame(root));
    this.warnings = options.warn;
    this.options = options;
    this.calling = []; // TODO: remove, use stack
    this.importStack = [];
    this.requireHistory = {};
    this.return = 0;
  }

  /**
   * Proxy visit to expose node line numbers.
   *
   * @param {Node} node
   * @return {Node}
   * @api private
   */

  visit(node) {
    try {
      return super.visit(node);
    } catch (err) {
      if (err.filename) throw err;
      err.lineno = node.lineno;
      err.column = node.column;
      err.filename = node.filename;
      err.stylusStack = this.stack.toString();
      try {
        err.input = this.str;
      } catch (err) {
        // ignore
      }
      throw err;
    }
  };

  /**
   * Perform evaluation setup:
   *
   *   - populate global scope
   *   - iterate imports
   *
   * @api private
   */

  setup() {
    var root = this.root;
    var imports = [];

    this.populateGlobalScope();
    this.imports.forEach(function (file) {
      var expr = new nodes.Expression;
      expr.push(new nodes.String(file));
      imports.push(new nodes.Import(expr));
    }, this);

    root.nodes = imports.concat(root.nodes);
  };

  /**
   * Populate the global scope with:
   *
   *   - css colors
   *   - user-defined globals
   *
   * @api private
   */

  populateGlobalScope() {
    var scope = this.global.scope;

    // colors
    Object.keys(colors).forEach(function (name) {
      var color = colors[name]
        , rgba = new nodes.RGBA(color[0], color[1], color[2], color[3])
        , node = new nodes.Ident(name, rgba);
      rgba.name = name;
      scope.add(node);
    });

    // Host-backed embedurl is intentionally not exposed in the offline artifact.

    // user-defined globals
    var globals = this.globals;
    Object.keys(globals).forEach(function (name) {
      var val = globals[name];
      if (!val.nodeName) val = new nodes.Literal(val);
      scope.add(new nodes.Ident(name, val));
    });
  };

  /**
   * Evaluate the tree.
   *
   * @return {Node}
   * @api private
   */

  evaluate() {
    debug('eval %s', this.filename);
    this.setup();
    return this.visit(this.root);
  };

  /**
   * Visit Group.
   */

  visitGroup(group) {
    group.nodes = group.nodes.map(function (selector) {
      selector.val = this.interpolate(selector);
      debug('ruleset %s', selector.val);
      return selector;
    }, this);

    group.block = this.visit(group.block);
    return group;
  };

  /**
   * Visit Return.
   */

  visitReturn(ret) {
    ret.expr = this.visit(ret.expr);
    throw ret;
  };

  /**
   * Visit Media.
   */

  visitMedia(media) {
    media.block = this.visit(media.block);
    media.val = this.visit(media.val);
    return media;
  };

  /**
   * Visit QueryList.
   */

  visitQueryList(queries) {
    var val, query;
    queries.nodes.forEach(this.visit, this);

    if (1 == queries.nodes.length) {
      query = queries.nodes[0];
      if (val = this.lookup(query.type)) {
        val = val.first.string;
        if (!val) return queries;
        var Parser = require('../parser')
          , parser = new Parser(val, this.options);
        queries = this.visit(parser.queries());
      }
    }
    return queries;
  };

  /**
   * Visit Query.
   */

  visitQuery(node) {
    node.predicate = this.visit(node.predicate);
    node.type = this.visit(node.type);
    node.nodes.forEach(this.visit, this);
    return node;
  };

  /**
   * Visit Feature.
   */

  visitFeature(node) {
    node.name = this.interpolate(node);
    if (node.expr) {
      this.return++;
      node.expr = this.visit(node.expr);
      this.return--;
    }
    return node;
  };

  /**
   * Visit Object.
   */

  visitObject(obj) {
    for (var key in obj.vals) {
      obj.vals[key] = this.visit(obj.vals[key]);
    }
    return obj;
  };

  /**
   * Visit Member.
   */

  visitMember(node) {
    var left = node.left
      , right = node.right
      , obj = this.visit(left).first;

    if ('object' != obj.nodeName) {
      throw new Error(left.toString() + ' has no property .' + right);
    }
    if (node.val) {
      this.return++;
      obj.set(right.name, this.visit(node.val));
      this.return--;
    }
    return obj.get(right.name);
  };

  /**
   * Visit Keyframes.
   */

  visitKeyframes(keyframes) {
    var val;
    if (keyframes.fabricated) return keyframes;
    keyframes.val = this.interpolate(keyframes).trim();
    if (val = this.lookup(keyframes.val)) {
      keyframes.val = val.first.string || val.first.name;
    }
    keyframes.block = this.visit(keyframes.block);

    if ('official' != keyframes.prefix) return keyframes;

    this.vendors.forEach(function (prefix) {
      // IE never had prefixes for keyframes
      if ('ms' == prefix) return;
      var node = keyframes.clone();
      node.val = keyframes.val;
      node.prefix = prefix;
      node.block = keyframes.block;
      node.fabricated = true;
      this.currentBlock.push(node);
    }, this);

    return nodes.null;
  };

  /**
   * Visit Function.
   */

  visitFunction(fn) {
    // check local
    var local = this.stack.currentFrame.scope.lookup(fn.name);
    if (local) this.warn('local ' + local.nodeName + ' "' + fn.name + '" previously defined in this scope');

    // user-defined
    var user = this.functions[fn.name];
    if (user) this.warn('user-defined function "' + fn.name + '" is already defined');

    // BIF
    var bif = bifs[fn.name];
    if (bif) this.warn('built-in function "' + fn.name + '" is already defined');

    return fn;
  };

  /**
   * Visit Each.
   */

  visitEach(each) {
    this.return++;
    var expr = utils.unwrap(this.visit(each.expr))
      , len = expr.nodes.length
      , val = new nodes.Ident(each.val)
      , key = new nodes.Ident(each.key || '__index__')
      , scope = this.currentScope
      , block = this.currentBlock
      , vals = []
      , self = this
      , body
      , obj;
    this.return--;

    each.block.scope = false;

    function visitBody(key, val) {
      scope.add(val);
      scope.add(key);
      body = self.visit(each.block.clone());
      vals = vals.concat(body.nodes);
    }

    // for prop in obj
    if (1 == len && 'object' == expr.nodes[0].nodeName) {
      obj = expr.nodes[0];
      for (var prop in obj.vals) {
        val.val = new nodes.String(prop);
        key.val = obj.get(prop);
        visitBody(key, val);
      }
    } else {
      for (var i = 0; i < len; ++i) {
        val.val = expr.nodes[i];
        key.val = new nodes.Unit(i);
        visitBody(key, val);
      }
    }

    this.mixin(vals, block);
    return vals[vals.length - 1] || nodes.null;
  };

  /**
   * Visit Call.
   */

  visitCall(call) {
    debug('call %s', call);
    var fn = this.lookup(call.name)
      , literal
      , ret;

    // url()
    this.ignoreColors = 'url' == call.name;

    // Variable function
    if (fn && 'expression' == fn.nodeName) {
      fn = fn.nodes[0];
    }

    // Not a function? try user-defined or built-ins
    if (fn && 'function' != fn.nodeName) {
      fn = this.lookupFunction(call.name);
    }

    // Undefined function? render literal CSS
    if (!fn || fn.nodeName != 'function') {
      debug('%s is undefined', call);
      // Special case for `calc`
      if ('calc' == this.unvendorize(call.name)) {
        literal = call.args.nodes && call.args.nodes[0];
        if (literal) ret = new nodes.Literal(call.name + literal);
      } else {
        ret = this.literalCall(call);
      }
      this.ignoreColors = false;
      return ret;
    }

    this.calling.push(call.name);

    // Massive stack
    if (this.calling.length > 200) {
      throw new RangeError('Maximum stylus call stack size exceeded');
    }

    // First node in expression
    if ('expression' == fn.nodeName) fn = fn.first;

    // Evaluate arguments
    this.return++;
    var args = this.visit(call.args);

    for (var key in args.map) {
      args.map[key] = this.visit(args.map[key].clone());
    }
    this.return--;

    // Built-in
    if (fn.fn) {
      debug('%s is built-in', call);
      ret = this.invokeBuiltin(fn.fn, args);
      // User-defined
    } else if ('function' == fn.nodeName) {
      debug('%s is user-defined', call);
      // Evaluate mixin block
      if (call.block) call.block = this.visit(call.block);
      ret = this.invokeFunction(fn, args, call.block);
    }

    this.calling.pop();
    this.ignoreColors = false;
    return ret;
  };

  /**
   * Visit Ident.
   */

  visitIdent(ident) {
    var prop;
    // Property lookup
    if (ident.property) {
      if (prop = this.lookupProperty(ident.name)) {
        return this.visit(prop.expr.clone());
      }
      return nodes.null;
      // Lookup
    } else if (ident.val.isNull) {
      var val = this.lookup(ident.name);
      // Object or Block mixin
      if (val && ident.mixin) this.mixinNode(val);
      return val ? this.visit(val) : ident;
      // Assign
    } else {
      this.return++;
      ident.val = this.visit(ident.val);
      this.return--;
      this.currentScope.add(ident);
      return ident.val;
    }
  };

  /**
   * Visit BinOp.
   */

  visitBinOp(binop) {
    // Special-case "is defined" pseudo binop
    if ('is defined' == binop.op) return this.isDefined(binop.left);

    this.return++;
    // Visit operands
    var op = binop.op
      , left = this.visit(binop.left)
      , right = ('||' == op || '&&' == op)
        ? binop.right : this.visit(binop.right);

    // HACK: ternary
    var val = binop.val
      ? this.visit(binop.val)
      : null;
    this.return--;

    // Operate
    try {
      return this.visit(left.operate(op, right, val));
    } catch (err) {
      // disregard coercion issues in equality
      // checks, and simply return false
      if ('CoercionError' == err.name) {
        switch (op) {
          case '==':
            return nodes.false;
          case '!=':
            return nodes.true;
        }
      }
      throw err;
    }
  };

  /**
   * Visit UnaryOp.
   */

  visitUnaryOp(unary) {
    var op = unary.op
      , node = this.visit(unary.expr);

    if ('!' != op) {
      node = node.first.clone();
      utils.assertType(node, 'unit');
    }

    switch (op) {
      case '-':
        node.val = -node.val;
        break;
      case '+':
        node.val = +node.val;
        break;
      case '~':
        node.val = ~node.val;
        break;
      case '!':
        return node.toBoolean().negate();
    }

    return node;
  };

  /**
   * Visit TernaryOp.
   */

  visitTernary(ternary) {
    var ok = this.visit(ternary.cond).toBoolean();
    return ok.isTrue
      ? this.visit(ternary.trueExpr)
      : this.visit(ternary.falseExpr);
  };

  /**
   * Visit Expression.
   */

  visitExpression(expr) {
    for (var i = 0, len = expr.nodes.length; i < len; ++i) {
      expr.nodes[i] = this.visit(expr.nodes[i]);
    }

    // support (n * 5)px etc
    if (this.castable(expr)) expr = this.cast(expr);

    return expr;
  };

  /**
   * Visit Arguments.
   */

  get visitArguments() {
    return this.visitExpression;
  }

  /**
   * Visit Property.
   */

  visitProperty(prop) {
    var name = this.interpolate(prop)
      , fn = this.lookup(name)
      , call = fn && 'function' == fn.first.nodeName
      , literal = ~this.calling.indexOf(name)
      , _prop = this.property;

    // Function of the same name
    if (call && !literal && !prop.literal) {
      var args = nodes.Arguments.fromExpression(utils.unwrap(prop.expr.clone()));
      prop.name = name;
      this.property = prop;
      this.return++;
      this.property.expr = this.visit(prop.expr);
      this.return--;
      var ret = this.visit(new nodes.Call(name, args));
      this.property = _prop;
      return ret;
      // Regular property
    } else {
      this.return++;
      prop.name = name;
      prop.literal = true;
      this.property = prop;
      prop.expr = this.visit(prop.expr);
      this.property = _prop;
      this.return--;
      return prop;
    }
  };

  /**
   * Visit Root.
   */

  visitRoot(block) {
    // normalize cached imports
    if (block != this.root) {
      block.constructor = nodes.Block;
      return this.visit(block);
    }

    for (var i = 0; i < block.nodes.length; ++i) {
      block.index = i;
      block.nodes[i] = this.visit(block.nodes[i]);
    }
    return block;
  };

  /**
   * Visit Block.
   */

  visitBlock(block) {
    this.stack.push(new Frame(block));
    for (block.index = 0; block.index < block.nodes.length; ++block.index) {
      try {
        block.nodes[block.index] = this.visit(block.nodes[block.index]);
      } catch (err) {
        if ('return' == err.nodeName) {
          if (this.return) {
            this.stack.pop();
            throw err;
          } else {
            block.nodes[block.index] = err;
            break;
          }
        } else {
          throw err;
        }
      }
    }
    this.stack.pop();
    return block;
  };

  /**
   * Visit Atblock.
   */

  visitAtblock(atblock) {
    atblock.block = this.visit(atblock.block);
    return atblock;
  };

  /**
   * Visit Atrule.
   */

  visitAtrule(atrule) {
    atrule.val = this.interpolate(atrule);
    if (atrule.block) atrule.block = this.visit(atrule.block);
    return atrule;
  };

  /**
   * Visit Supports.
   */

  visitSupports(node) {
    var condition = node.condition
      , val;

    this.return++;
    node.condition = this.visit(condition);
    this.return--;

    val = condition.first;
    if (1 == condition.nodes.length
      && 'string' == val.nodeName) {
      node.condition = val.string;
    }
    node.block = this.visit(node.block);
    return node;
  };

  /**
   * Visit If.
   */

  visitIf(node) {
    var ret
      , block = this.currentBlock
      , negate = node.negate;

    this.return++;
    var ok = this.visit(node.cond).first.toBoolean();
    this.return--;

    node.block.scope = node.block.hasMedia;

    // Evaluate body
    if (negate) {
      // unless
      if (ok.isFalse) {
        ret = this.visit(node.block);
      }
    } else {
      // if
      if (ok.isTrue) {
        ret = this.visit(node.block);
        // else
      } else if (node.elses.length) {
        var elses = node.elses
          , len = elses.length
          , cond;
        for (var i = 0; i < len; ++i) {
          // else if
          if (elses[i].cond) {
            elses[i].block.scope = elses[i].block.hasMedia;
            this.return++;
            cond = this.visit(elses[i].cond).first.toBoolean();
            this.return--;
            if (cond.isTrue) {
              ret = this.visit(elses[i].block);
              break;
            }
            // else
          } else {
            elses[i].scope = elses[i].hasMedia;
            ret = this.visit(elses[i]);
          }
        }
      }
    }

    // mixin conditional statements within
    // a selector group or at-rule
    if (ret && !node.postfix && block.node
      && ~['group'
        , 'atrule'
        , 'media'
        , 'supports'
        , 'keyframes'].indexOf(block.node.nodeName)) {
      this.mixin(ret.nodes, block);
      return nodes.null;
    }

    return ret || nodes.null;
  };

  /**
   * Visit Extend.
   */

  visitExtend(extend) {
    var block = this.currentBlock;
    if ('group' != block.node.nodeName) block = this.closestGroup;
    extend.selectors.forEach(function (selector) {
      block.node.extends.push({
        // Cloning the selector for when we are in a loop and don't want it to affect
        // the selector nodes and cause the values to be different to expected
        selector: this.interpolate(selector.clone()).trim(),
        optional: selector.optional,
        lineno: selector.lineno,
        column: selector.column
      });
    }, this);
    return nodes.null;
  };

  /**
   * Visit Import.
   */

  visitImport(imported) {
    this.return++;

    var path = this.visit(imported.path).first
      , nodeName = imported.once ? 'require' : 'import'
      , found
      , literal;

    this.return--;
    debug('import %s', path);

    // url() passed
    if ('url' == path.name) {
      if (imported.once) throw new Error('You cannot @require a url');

      return imported;
    }

    // Ensure string
    if (!path.string) throw new Error('@' + nodeName + ' string expected');

    var name = path = path.string;

    // Absolute URL or hash
    if (/(?:url\s*\(\s*)?['"]?(?:#|(?:https?:)?\/\/)/i.test(path)) {
      if (imported.once) throw new Error('You cannot @require a url');
      return imported;
    }

    // Literal
    if (/\.css(?:"|$)/.test(path)) {
      literal = true;
      if (!imported.once && !this.includeCSS) {
        return imported;
      }
    }

    // support optional .styl
    if (!literal && !/\.styl$/i.test(path)) path += '.styl';

    // Lookup
    found = utils.find(path, this.paths, this.filename);
    if (!found) {
      found = utils.lookupIndex(name, this.paths, this.filename);
    }

    // Throw if import failed
    if (!found) throw new Error('failed to locate @' + nodeName + ' file ' + path);

    var block = new nodes.Block;

    for (var i = 0, len = found.length; i < len; ++i) {
      block.push(importFile.call(this, imported, found[i], literal));
    }

    return block;
  };

  /**
   * Invoke `fn` with `args`.
   *
   * @param {Function} fn
   * @param {Array} args
   * @return {Node}
   * @api private
   */

  invokeFunction(fn, args, content) {
    var block = new nodes.Block(fn.block.parent);

    // Clone the function body
    // to prevent mutation of subsequent calls
    var body = fn.block.clone(block);

    // mixin block
    var mixinBlock = this.stack.currentFrame.block;

    // new block scope
    this.stack.push(new Frame(block));
    var scope = this.currentScope;

    // normalize arguments
    if ('arguments' != args.nodeName) {
      var expr = new nodes.Expression;
      expr.push(args);
      args = nodes.Arguments.fromExpression(expr);
    }

    // arguments local
    scope.add(new nodes.Ident('arguments', args));

    // mixin scope introspection
    scope.add(new nodes.Ident('mixin', this.return
      ? nodes.false
      : new nodes.String(mixinBlock.nodeName)));

    // current property
    if (this.property) {
      var prop = this.propertyExpression(this.property, fn.name);
      scope.add(new nodes.Ident('current-property', prop));
    } else {
      scope.add(new nodes.Ident('current-property', nodes.null));
    }

    // current call stack
    var expr = new nodes.Expression;
    for (var i = this.calling.length - 1; i--;) {
      expr.push(new nodes.Literal(this.calling[i]));
    };
    scope.add(new nodes.Ident('called-from', expr));

    // inject arguments as locals
    var i = 0
      , len = args.nodes.length;
    fn.params.nodes.forEach(function (node) {
      // rest param support
      if (node.rest) {
        node.val = new nodes.Expression;
        for (; i < len; ++i) node.val.push(args.nodes[i]);
        node.val.preserve = true;
        node.val.isList = args.isList;
        // argument default support
      } else {
        var arg = args.map[node.name] || args.nodes[i++];
        node = node.clone();
        if (arg) {
          arg.isEmpty ? args.nodes[i - 1] = this.visit(node) : node.val = arg;
        } else {
          args.push(node.val);
        }

        // required argument not satisfied
        if (node.val.isNull) {
          throw new Error('argument "' + node + '" required for ' + fn);
        }
      }

      scope.add(node);
    }, this);

    // mixin block
    if (content) scope.add(new nodes.Ident('block', content, true));

    // invoke
    return this.invoke(body, true, fn.filename);
  };

  /**
   * Invoke built-in `fn` with `args`.
   *
   * @param {Function} fn
   * @param {Array} args
   * @return {Node}
   * @api private
   */

  invokeBuiltin(fn, args) {
    // Map arguments to first node
    // providing a nicer js api for
    // BIFs. Functions may specify that
    // they wish to accept full expressions
    // via .raw
    if (fn.raw) {
      args = args.nodes;
    } else {
      if (!fn.params) {
        fn.params = utils.params(fn);
      }
      args = fn.params.reduce(function (ret, param) {
        var arg = args.map[param] || args.nodes.shift()
        if (arg) {
          arg = utils.unwrap(arg);
          var len = arg.nodes.length;
          if (len > 1) {
            for (var i = 0; i < len; ++i) {
              ret.push(utils.unwrap(arg.nodes[i].first));
            }
          } else {
            ret.push(arg.first);
          }
        }
        return ret;
      }, []);
    }

    // Invoke the BIF
    var body = utils.coerce(fn.apply(this, args));

    // Always wrapping allows js functions
    // to return several values with a single
    // Expression node
    var expr = new nodes.Expression;
    expr.push(body);
    body = expr;

    // Invoke
    return this.invoke(body);
  };

  /**
   * Invoke the given function `body`.
   *
   * @param {Block} body
   * @return {Node}
   * @api private
   */

  invoke(body, stack, filename) {
    var self = this
      , ret;

    if (filename) this.paths.push(dirname(filename));

    // Return
    if (this.return) {
      ret = this.eval(body.nodes);
      if (stack) this.stack.pop();
      // Mixin
    } else {
      body = this.visit(body);
      if (stack) this.stack.pop();
      this.mixin(body.nodes, this.currentBlock);
      ret = nodes.null;
    }

    if (filename) this.paths.pop();

    return ret;
  };

  /**
   * Mixin the given `nodes` to the given `block`.
   *
   * @param {Array} nodes
   * @param {Block} block
   * @api private
   */

  mixin(nodes, block) {
    if (!nodes.length) return;
    var len = block.nodes.length
      , head = block.nodes.slice(0, block.index)
      , tail = block.nodes.slice(block.index + 1, len);
    this._mixin(nodes, head, block);
    block.index = 0;
    block.nodes = head.concat(tail);
  };

  /**
   * Mixin the given `items` to the `dest` array.
   *
   * @param {Array} items
   * @param {Array} dest
   * @param {Block} block
   * @api private
   */

  _mixin(items, dest, block) {
    var node
      , len = items.length;
    for (var i = 0; i < len; ++i) {
      switch ((node = items[i]).nodeName) {
        case 'return':
          return;
        case 'block':
          this._mixin(node.nodes, dest, block);
          break;
        case 'media':
          // fix link to the parent block
          var parentNode = node.block.parent.node;
          if (parentNode && 'call' != parentNode.nodeName) {
            node.block.parent = block;
          }
        case 'property':
          var val = node.expr;
          // prevent `block` mixin recursion
          if (node.literal && 'block' == val.first.name) {
            val = utils.unwrap(val);
            val.nodes[0] = new nodes.Literal('block');
          }
        default:
          dest.push(node);
      }
    }
  };

  /**
   * Mixin the given `node` to the current block.
   *
   * @param {Node} node
   * @api private
   */

  mixinNode(node) {
    node = this.visit(node.first);
    switch (node.nodeName) {
      case 'object':
        this.mixinObject(node);
        return nodes.null;
      case 'block':
      case 'atblock':
        this.mixin(node.nodes, this.currentBlock);
        return nodes.null;
    }
  };

  /**
   * Mixin the given `object` to the current block.
   *
   * @param {Object} object
   * @api private
   */

  mixinObject(object) {
    var Parser = require('../parser')
      , root = this.root
      , str = '$block ' + object.toBlock()
      , parser = new Parser(str, utils.merge({ root: block }, this.options))
      , block;

    try {
      block = parser.parse();
    } catch (err) {
      err.filename = this.filename;
      err.lineno = parser.lexer.lineno;
      err.column = parser.lexer.column;
      err.input = str;
      throw err;
    }

    block.parent = root;
    block.scope = false;
    var ret = this.visit(block)
      , vals = ret.first.nodes;
    for (var i = 0, len = vals.length; i < len; ++i) {
      if (vals[i].block) {
        this.mixin(vals[i].block.nodes, this.currentBlock);
        break;
      }
    }
  };

  /**
   * Evaluate the given `vals`.
   *
   * @param {Array} vals
   * @return {Node}
   * @api private
   */

  eval(vals) {
    if (!vals) return nodes.null;
    var len = vals.length
      , node = nodes.null;

    try {
      for (var i = 0; i < len; ++i) {
        node = vals[i];
        switch (node.nodeName) {
          case 'if':
            if ('block' != node.block.nodeName) {
              node = this.visit(node);
              break;
            }
          case 'each':
          case 'block':
            node = this.visit(node);
            if (node.nodes) node = this.eval(node.nodes);
            break;
          default:
            node = this.visit(node);
        }
      }
    } catch (err) {
      if ('return' == err.nodeName) {
        return err.expr;
      } else {
        throw err;
      }
    }

    return node;
  };

  /**
   * Literal function `call`.
   *
   * @param {Call} call
   * @return {call}
   * @api private
   */

  literalCall(call) {
    call.args = this.visit(call.args);
    return call;
  };

  /**
   * Lookup property `name`.
   *
   * @param {String} name
   * @return {Property}
   * @api private
   */

  lookupProperty(name) {
    var i = this.stack.length
      , index = this.currentBlock.index
      , top = i
      , nodes
      , block
      , len
      , other;

    while (i--) {
      block = this.stack[i].block;
      if (!block.node) continue;
      switch (block.node.nodeName) {
        case 'group':
        case 'function':
        case 'if':
        case 'each':
        case 'atrule':
        case 'media':
        case 'atblock':
        case 'call':
          nodes = block.nodes;
          // scan siblings from the property index up
          if (i + 1 == top) {
            while (index--) {
              // ignore current property
              if (this.property == nodes[index]) continue;
              other = this.interpolate(nodes[index]);
              if (name == other) return nodes[index].clone();
            }
            // sequential lookup for non-siblings (for now)
          } else {
            len = nodes.length;
            while (len--) {
              if ('property' != nodes[len].nodeName
                || this.property == nodes[len]) continue;
              other = this.interpolate(nodes[len]);
              if (name == other) return nodes[len].clone();
            }
          }
          break;
      }
    }

    return nodes.null;
  };

  /**
   * Return the closest mixin-able `Block`.
   *
   * @return {Block}
   * @api private
   */

  get closestBlock() {
    var i = this.stack.length
      , block;
    while (i--) {
      block = this.stack[i].block;
      if (block.node) {
        switch (block.node.nodeName) {
          case 'group':
          case 'keyframes':
          case 'atrule':
          case 'atblock':
          case 'media':
          case 'call':
            return block;
        }
      }
    }
  };

  /**
   * Return the closest group block.
   *
   * @return {Block}
   * @api private
   */

  get closestGroup() {
    var i = this.stack.length
      , block;
    while (i--) {
      block = this.stack[i].block;
      if (block.node && 'group' == block.node.nodeName) {
        return block;
      }
    }
  };

  /**
   * Return the current selectors stack.
   *
   * @return {Array}
   * @api private
   */

  get selectorStack() {
    var block
      , stack = [];
    for (var i = 0, len = this.stack.length; i < len; ++i) {
      block = this.stack[i].block;
      if (block.node && 'group' == block.node.nodeName) {
        block.node.nodes.forEach(function (selector) {
          if (!selector.val) selector.val = this.interpolate(selector);
        }, this);
        stack.push(block.node.nodes);
      }
    }
    return stack;
  };

  /**
   * Lookup `name`, with support for JavaScript
   * functions, and BIFs.
   *
   * @param {String} name
   * @return {Node}
   * @api private
   */

  lookup(name) {
    var val;
    if (this.ignoreColors && name in colors) return;
    if (val = this.stack.lookup(name)) {
      return utils.unwrap(val);
    } else {
      return this.lookupFunction(name);
    }
  };

  /**
   * Map segments in `node` returning a string.
   *
   * @param {Node} node
   * @return {String}
   * @api private
   */

  interpolate(node) {
    var self = this
      , isSelector = ('selector' == node.nodeName);
    function toString(node) {
      switch (node.nodeName) {
        case 'function':
        case 'ident':
          return node.name;
        case 'literal':
        case 'string':
          if (self.prefix && !node.prefixed && !node.val.nodeName) {
            node.val = node.val.replace(/\.(?=[\w-])|^\.$/g, '.' + self.prefix);
            node.prefixed = true;
          }
          return node.val;
        case 'unit':
          // Interpolation inside keyframes
          return '%' == node.type ? node.val + '%' : node.val;
        case 'member':
          return toString(self.visit(node));
        case 'expression':
          // Prevent cyclic `selector()` calls.
          if (self.calling && ~self.calling.indexOf('selector') && self._selector) return self._selector;
          self.return++;
          var ret = toString(self.visit(node).first);
          self.return--;
          if (isSelector) self._selector = ret;
          return ret;
      }
    }

    if (node.segments) {
      return node.segments.map(toString).join('');
    } else {
      return toString(node);
    }
  };

  /**
   * Lookup JavaScript user-defined or built-in function.
   *
   * @param {String} name
   * @return {Function}
   * @api private
   */

  lookupFunction(name) {
    var fn = this.functions[name] || bifs[name];
    if (fn) return new nodes.Function(name, fn);
  };

  /**
   * Check if the given `node` is an ident, and if it is defined.
   *
   * @param {Node} node
   * @return {Boolean}
   * @api private
   */

  isDefined(node) {
    if ('ident' == node.nodeName) {
      return new nodes.Boolean(this.lookup(node.name));
    } else {
      throw new Error('invalid "is defined" check on non-variable ' + node);
    }
  };

  /**
   * Return `Expression` based on the given `prop`,
   * replacing cyclic calls to the given function `name`
   * with "__CALL__".
   *
   * @param {Property} prop
   * @param {String} name
   * @return {Expression}
   * @api private
   */

  propertyExpression(prop, name) {
    var expr = new nodes.Expression
      , val = prop.expr.clone();

    // name
    expr.push(new nodes.String(prop.name));

    // replace cyclic call with __CALL__
    function replace(node) {
      if ('call' == node.nodeName && name == node.name) {
        return new nodes.Literal('__CALL__');
      }

      if (node.nodes) node.nodes = node.nodes.map(replace);
      return node;
    }

    replace(val);
    expr.push(val);
    return expr;
  };

  /**
   * Cast `expr` to the trailing ident.
   *
   * @param {Expression} expr
   * @return {Unit}
   * @api private
   */

  cast(expr) {
    return new nodes.Unit(expr.first.val, expr.nodes[1].name);
  };

  /**
   * Check if `expr` is castable.
   *
   * @param {Expression} expr
   * @return {Boolean}
   * @api private
   */

  castable(expr) {
    return 2 == expr.nodes.length
      && 'unit' == expr.first.nodeName
      && ~units.indexOf(expr.nodes[1].name);
  };

  /**
   * Warn with the given `msg`.
   *
   * @param {String} msg
   * @api private
   */

  warn(msg) {
    if (!this.warnings) return;
    console.warn('\u001b[33mWarning:\u001b[0m ' + msg);
  };

  /**
   * Return the current `Block`.
   *
   * @return {Block}
   * @api private
   */

  get currentBlock() {
    return this.stack.currentFrame.block;
  };

  /**
   * Return an array of vendor names.
   *
   * @return {Array}
   * @api private
   */

  get vendors() {
    return this.lookup('vendors').nodes.map(function (node) {
      return node.string;
    });
  };

  /**
   * Return the property name without vendor prefix.
   *
   * @param {String} prop
   * @return {String}
   * @api public
   */

  unvendorize(prop) {
    for (var i = 0, len = this.vendors.length; i < len; i++) {
      if ('official' != this.vendors[i]) {
        var vendor = '-' + this.vendors[i] + '-';
        if (~prop.indexOf(vendor)) return prop.replace(vendor, '');
      }
    }
    return prop;
  };

  /**
   * Return the current frame `Scope`.
   *
   * @return {Scope}
   * @api private
   */

  get currentScope() {
    return this.stack.currentFrame.scope;
  };

  /**
   * Return the current `Frame`.
   *
   * @return {Frame}
   * @api private
   */

  get currentFrame() {
    return this.stack.currentFrame;
  };
};

},{"../colors":62,"../functions":88,"../nodes":148,"../parser":170,"../stack":174,"../stack/frame":173,"../units":177,"../utils":178,"./":182,"debug":"debug","path":52}],182:[function(require,module,exports){

/*!
 * Stylus - Visitor
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

module.exports = class Visitor {
  /**
   * Initialize a new `Visitor` with the given `root` Node.
   *
   * @param {Node} root
   * @api private
   */

  constructor(root) {
    this.root = root;
  }

  /**
   * Visit the given `node`.
   *
   * @param {Node|Array} node
   * @api public
   */

  visit(node, fn) {
    var method = 'visit' + node.constructor.name;
    if (this[method]) return this[method](node);
    return node;
  };
};

},{}],183:[function(require,module,exports){

/*!
 * Stylus - Normalizer
 * Copyright (c) Automattic <developer.wordpress.com>
 * MIT Licensed
 */

/**
 * Module dependencies.
 */

var Visitor = require('./')
  , nodes = require('../nodes')
  , utils = require('../utils');

module.exports = class Normalizer extends Visitor {
  /**
   * Initialize a new `Normalizer` with the given `root` Node.
   *
   * This visitor implements the first stage of the duel-stage
   * compiler, tasked with stripping the "garbage" from
   * the evaluated nodes, ditching null rules, resolving
   * ruleset selectors etc. This step performs the logic
   * necessary to facilitate the "@extend" functionality,
   * as these must be resolved _before_ buffering output.
   *
   * @param {Node} root
   * @api public
   */

  constructor(root, options) {
    super(root);
    options = options || {};
    this.hoist = options['hoist atrules'];
    this.stack = [];
    this.map = {};
    this.imports = [];
  }

  /**
   * Normalize the node tree.
   *
   * @return {Node}
   * @api private
   */

  normalize() {
    var ret = this.visit(this.root);

    if (this.hoist) {
      // hoist @import
      if (this.imports.length) ret.nodes = this.imports.concat(ret.nodes);

      // hoist @charset
      if (this.charset) ret.nodes = [this.charset].concat(ret.nodes);
    }

    return ret;
  };

  /**
   * Bubble up the given `node`.
   *
   * @param {Node} node
   * @api private
   */

  bubble(node) {
    var props = []
      , other = []
      , self = this;

    function filterProps(block) {
      block.nodes.forEach(function (node) {
        node = self.visit(node);

        switch (node.nodeName) {
          case 'property':
            props.push(node);
            break;
          case 'block':
            filterProps(node);
            break;
          default:
            other.push(node);
        }
      });
    }

    filterProps(node.block);

    if (props.length) {
      var selector = new nodes.Selector([new nodes.Literal('&')]);
      selector.lineno = node.lineno;
      selector.column = node.column;
      selector.filename = node.filename;
      selector.val = '&';

      var group = new nodes.Group;
      group.lineno = node.lineno;
      group.column = node.column;
      group.filename = node.filename;

      var block = new nodes.Block(node.block, group);
      block.lineno = node.lineno;
      block.column = node.column;
      block.filename = node.filename;

      props.forEach(function (prop) {
        block.push(prop);
      });

      group.push(selector);
      group.block = block;

      node.block.nodes = [];
      node.block.push(group);
      other.forEach(function (n) {
        node.block.push(n);
      });

      var group = this.closestGroup(node.block);
      if (group) node.group = group.clone();

      node.bubbled = true;
    }
  };

  /**
   * Return group closest to the given `block`.
   *
   * @param {Block} block
   * @return {Group}
   * @api private
   */

  closestGroup(block) {
    var parent = block.parent
      , node;
    while (parent && (node = parent.node)) {
      if ('group' == node.nodeName) return node;
      parent = node.block && node.block.parent;
    }
  };

  /**
   * Visit Root.
   */

  visitRoot(block) {
    var ret = new nodes.Root
      , node;

    for (var i = 0; i < block.nodes.length; ++i) {
      node = block.nodes[i];
      switch (node.nodeName) {
        case 'null':
        case 'expression':
        case 'function':
        case 'unit':
        case 'atblock':
          continue;
        default:
          this.rootIndex = i;
          ret.push(this.visit(node));
      }
    }

    return ret;
  };

  /**
   * Visit Property.
   */

  visitProperty(prop) {
    this.visit(prop.expr);
    return prop;
  };

  /**
   * Visit Expression.
   */

  visitExpression(expr) {
    expr.nodes = expr.nodes.map(function (node) {
      // returns `block` literal if mixin's block
      // is used as part of a property value
      if ('block' == node.nodeName) {
        var literal = new nodes.Literal('block');
        literal.lineno = expr.lineno;
        literal.column = expr.column;
        return literal;
      }
      return node;
    });
    return expr;
  };

  /**
   * Visit Block.
   */

  visitBlock(block) {
    var node;

    if (block.hasProperties) {
      for (var i = 0, len = block.nodes.length; i < len; ++i) {
        node = block.nodes[i];
        switch (node.nodeName) {
          case 'null':
          case 'expression':
          case 'function':
          case 'group':
          case 'unit':
          case 'atblock':
            continue;
          default:
            block.nodes[i] = this.visit(node);
        }
      }
    }

    // nesting
    for (var i = 0, len = block.nodes.length; i < len; ++i) {
      node = block.nodes[i];
      block.nodes[i] = this.visit(node);
    }

    return block;
  };

  /**
   * Visit Group.
   */

  visitGroup(group) {
    var stack = this.stack
      , map = this.map
      , parts;

    // normalize interpolated selectors with comma
    group.nodes.forEach(function (selector, i) {
      if (!~selector.val.indexOf(',')) return;
      if (~selector.val.indexOf('\\,')) {
        selector.val = selector.val.replace(/\\,/g, ',');
        return;
      }
      parts = selector.val.split(',');
      var root = '/' == selector.val.charAt(0)
        , part, s;
      for (var k = 0, len = parts.length; k < len; ++k) {
        part = parts[k].trim();
        if (root && k > 0 && !~part.indexOf('&')) {
          part = '/' + part;
        }
        s = new nodes.Selector([new nodes.Literal(part)]);
        s.val = part;
        s.block = group.block;
        group.nodes[i++] = s;
      }
    });
    stack.push(group.nodes);

    var selectors = utils.compileSelectors(stack, true);

    // map for extension lookup
    selectors.forEach(function (selector) {
      map[selector] = map[selector] || [];
      map[selector].push(group);
    });

    // extensions
    this.extend(group, selectors);

    stack.pop();
    return group;
  };

  /**
   * Visit Function.
   */

  visitFunction() {
    return nodes.null;
  };

  /**
   * Visit Media.
   */

  visitMedia(media) {
    var medias = []
      , group = this.closestGroup(media.block)
      , parent;

    function mergeQueries(block) {
      block.nodes.forEach(function (node, i) {
        switch (node.nodeName) {
          case 'media':
            node.val = media.val.merge(node.val);
            medias.push(node);
            block.nodes[i] = nodes.null;
            break;
          case 'block':
            mergeQueries(node);
            break;
          default:
            if (node.block && node.block.nodes)
              mergeQueries(node.block);
        }
      });
    }

    mergeQueries(media.block);
    this.bubble(media);

    if (medias.length) {
      medias.forEach(function (node) {
        if (group) {
          group.block.push(node);
        } else {
          this.root.nodes.splice(++this.rootIndex, 0, node);
        }
        node = this.visit(node);
        parent = node.block.parent;
        if (node.bubbled && (!group || 'group' == parent.node.nodeName)) {
          node.group.block = node.block.nodes[0].block;
          node.block.nodes[0] = node.group;
        }
      }, this);
    }
    return media;
  };

  /**
   * Visit Supports.
   */

  visitSupports(node) {
    this.bubble(node);
    return node;
  };

  /**
   * Visit Atrule.
   */

  visitAtrule(node) {
    if (node.block) node.block = this.visit(node.block);
    return node;
  };

  /**
   * Visit Keyframes.
   */

  visitKeyframes(node) {
    var frames = node.block.nodes.filter(function (frame) {
      return frame.block && frame.block.hasProperties;
    });
    node.frames = frames.length;
    return node;
  };

  /**
   * Visit Import.
   */

  visitImport(node) {
    this.imports.push(node);
    return this.hoist ? nodes.null : node;
  };

  /**
   * Visit Charset.
   */

  visitCharset(node) {
    this.charset = node;
    return this.hoist ? nodes.null : node;
  };

  /**
   * Apply `group` extensions.
   *
   * @param {Group} group
   * @param {Array} selectors
   * @api private
   */

  extend(group, selectors) {
    var map = this.map
      , self = this
      , parent = this.closestGroup(group.block);

    group.extends.forEach(function (extend) {
      var groups = map[extend.selector];
      if (!groups) {
        if (extend.optional) return;
        groups = self._checkForPrefixedGroups(extend.selector);
        if (!groups) {
          var err = new Error('Failed to @extend "' + extend.selector + '"');
          err.lineno = extend.lineno;
          err.column = extend.column;
          throw err;
        }
      }
      selectors.forEach(function (selector) {
        var node = new nodes.Selector;
        node.val = selector;
        node.inherits = false;
        groups.forEach(function (group) {
          // prevent recursive extend
          if (!parent || (parent != group)) self.extend(group, selectors);
          group.push(node);
        });
      });
    });

    group.block = this.visit(group.block);
  };

  _checkForPrefixedGroups(selector) {
    var prefix = [];
    var map = this.map;
    var result = null;
    for (var i = 0; i < this.stack.length; i++) {
      var stackElementArray = this.stack[i];
      var stackElement = stackElementArray[0];
      prefix.push(stackElement.val);
      var fullSelector = prefix.join(" ") + " " + selector;
      result = map[fullSelector];
      if (result)
        break;
    }
    return result;
  };
};

},{"../nodes":148,"../utils":178,"./":182}],184:[function(require,module,exports){
/* Offline Stylus 0.64.0 JSC entry point. */
var Renderer = require('../package-slim/lib/renderer');

function fail(code, message) {
  return { error: { code: code, message: String(message) } };
}

function compile(input) {
  try {
    if (!input || typeof input !== 'object' || Array.isArray(input)) {
      return fail('invalid_input', 'expected an object with a string source');
    }
    if (typeof input.source !== 'string') {
      return fail('invalid_source', 'source must be a string');
    }
    // This artifact is deliberately offline. Imports and host-backed built-ins are rejected.
    if (/(^|[\r\n])\s*@(?:import|require)\b/i.test(input.source)) {
      return fail('imports_rejected', 'Stylus imports are unavailable in the offline compiler');
    }
    if (/(?:^|[\s;(])(?:embedurl|image-size|json|use|url)\s*\(/i.test(input.source)) {
      return fail('unsupported_builtin', 'filesystem-backed Stylus built-ins are unavailable');
    }
    var variables = input.variables == null ? {} : input.variables;
    if (typeof variables !== 'object' || Array.isArray(variables)) {
      return fail('invalid_variables', 'variables must be an object');
    }
    var renderer = new Renderer(input.source, {
      filename: 'offline.styl',
      globals: variables,
      // Renderer adds a file import by default; disable it before rendering.
      imports: []
    });
    // Remove the default import inserted by Renderer. Core language constructs remain.
    renderer.options.imports = [];
    return { css: renderer.render() };
  } catch (error) {
    return fail('compile_error', error && error.message ? error.message : error);
  }
}

// JSContext's global object has globalThis on supported JavaScriptCore versions.
if (typeof globalThis !== 'undefined') globalThis.StylusCompile = compile;

},{"../package-slim/lib/renderer":171}],"debug":[function(require,module,exports){
module.exports = function () {
  return function () {};
};
module.exports.enable = function () {};
module.exports.disable = function () {};
module.exports.enabled = function () { return false; };

},{}],"fs":[function(require,module,exports){
function unsupported() { throw new Error('unsupported_builtin: filesystem access is unavailable'); }
module.exports = {
  readFileSync: unsupported, statSync: unsupported, openSync: unsupported,
  fstatSync: unsupported, closeSync: unsupported, readSync: unsupported,
  existsSync: function () { return false; }
};

},{}],"glob":[function(require,module,exports){
module.exports = { sync: function () { throw new Error('unsupported_builtin: filesystem globbing is unavailable'); } };

},{}]},{},[184])("glob")
});
