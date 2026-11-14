(function () {
  'use strict';
  const encode = JSON.stringify.bind(JSON);
  const pending = new Map();
  let calls = [], serial = 0, done = false, value = null, error = null;
  const api = Object.freeze({
    request(method, args = {}) {
      if (++serial > 24) return Promise.reject(new Error('host call limit'));
      return new Promise((resolve, reject) => {
        pending.set(serial, {resolve, reject});
        calls.push({id: serial, method, args});
      });
    }
  });
  return {
    start(event) {
      if (typeof globalThis.myunePlugin !== 'function') throw new Error('myunePlugin handler required');
      Promise.resolve().then(() => globalThis.myunePlugin(event, api)).then(
        result => { value = result ?? null; done = true; },
        failure => { error = String(failure).slice(0, 1000); done = true; }
      );
    },
    accept(responses) {
      for (const response of responses) {
        const target = pending.get(response.id);
        if (!target) throw new Error('unknown response');
        pending.delete(response.id);
        if (response.error != null) target.reject(new Error(response.error));
        else target.resolve(response.value);
      }
    },
    take() {
      const result = encode({done, value, error, calls});
      calls = [];
      return result;
    }
  };
})()
