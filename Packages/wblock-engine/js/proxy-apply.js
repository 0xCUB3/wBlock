// Shared across scriptlets in the same page so Function.prototype.toString is
// wrapped at most once and recursive page wrappers cannot blow the stack.
function proxyApplyFn(
    target = '',
    handler = '',
    options = {}
) {
    let context = globalThis;
    let prop = target;
    for (;;) {
        const pos = prop.indexOf('.');
        if ( pos === -1 ) { break; }
        context = context[prop.slice(0, pos)];
        if ( context instanceof Object === false ) { return; }
        prop = prop.slice(pos + 1);
    }
    const fn = context[prop];
    if ( typeof fn !== 'function' ) { return; }

    const stateKey = Symbol.for('wbe.proxyApply');
    let state = globalThis[stateKey];
    if ( state === undefined ) {
        const ctorContexts = [];
        const applyContexts = [];
        state = {
            CtorContext: class {
                constructor(...args) {
                    this.init(...args);
                }
                init(callFn, callArgs) {
                    this.callFn = callFn;
                    this.callArgs = callArgs;
                    return this;
                }
                reflect() {
                    const r = Reflect.construct(this.callFn, this.callArgs);
                    this.callFn = this.callArgs = this.private = undefined;
                    ctorContexts.push(this);
                    return r;
                }
                static factory(...args) {
                    return ctorContexts.length !== 0
                        ? ctorContexts.pop().init(...args)
                        : new state.CtorContext(...args);
                }
            },
            ApplyContext: class {
                constructor(...args) {
                    this.init(...args);
                }
                init(callFn, thisArg, callArgs) {
                    this.callFn = callFn;
                    this.thisArg = thisArg;
                    this.callArgs = callArgs;
                    return this;
                }
                reflect() {
                    const r = Reflect.apply(this.callFn, this.thisArg, this.callArgs);
                    this.callFn = this.thisArg = this.callArgs = this.private = undefined;
                    applyContexts.push(this);
                    return r;
                }
                static factory(...args) {
                    return applyContexts.length !== 0
                        ? applyContexts.pop().init(...args)
                        : new state.ApplyContext(...args);
                }
            },
            isCtor: new Map(),
            proxies: new WeakMap(),
            toStringInstalled: false,
            toStringDepth: 0,
            nativeToString: null,
        };
        try {
            Object.defineProperty(globalThis, stateKey, {
                value: state,
                configurable: true,
            });
        } catch {
            // Non-extensible globalThis: keep state local to this call chain.
        }
    }

    if ( state.toStringInstalled === false
        && (options.skipToString || proxyApplyFn.skipToString) !== true
    ) {
        state.toStringInstalled = true;
        const nativeToString = Function.prototype.toString;
        state.nativeToString = nativeToString;
        const proxiedToString = new Proxy(nativeToString, {
            apply(_target, thisArg, args) {
                if ( state.toStringDepth > 16 ) {
                    return 'function () { [native code] }';
                }
                let proxied = thisArg;
                let hops = 0;
                while ( hops < 64 ) {
                    const unwrapped = state.proxies.get(proxied);
                    if ( unwrapped === undefined || unwrapped === proxied ) { break; }
                    proxied = unwrapped;
                    hops += 1;
                }
                state.toStringDepth += 1;
                try {
                    return Reflect.apply(nativeToString, proxied, args);
                } finally {
                    state.toStringDepth -= 1;
                }
            }
        });
        state.proxies.set(proxiedToString, nativeToString);
        try {
            Function.prototype.toString = proxiedToString;
        } catch {
            // Frozen Function.prototype.toString: leave it untouched.
        }
    }

    if ( state.isCtor.has(target) === false ) {
        state.isCtor.set(target, fn.prototype?.constructor === fn);
    }
    const proxyDetails = {
        apply(targetFn, thisArg, args) {
            return handler(state.ApplyContext.factory(targetFn, thisArg, args));
        }
    };
    if ( state.isCtor.get(target) ) {
        proxyDetails.construct = function(targetFn, args) {
            return handler(state.CtorContext.factory(targetFn, args));
        };
    }
    const proxiedTarget = new Proxy(fn, proxyDetails);
    state.proxies.set(proxiedTarget, fn);
    context[prop] = proxiedTarget;
}
