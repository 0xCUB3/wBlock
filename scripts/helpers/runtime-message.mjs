// Model runtime.sendMessage without treating a listener's return value as its reply.
export function runtimeMessageListener(listener) {
  return (request, sender) => new Promise(resolve => {
    if (listener(request, sender, resolve) !== true) {
      throw new Error("Runtime listener must keep its asynchronous response channel open");
    }
  });
}
