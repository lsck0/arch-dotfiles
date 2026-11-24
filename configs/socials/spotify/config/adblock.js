(function adblock() {
  const BLOCK = [
    /\/ads\//,
    /\/ad-logic\//,
    /gabo-receiver-service/,
    /\/sponsored\//,
    /spclient\.wg\.spotify\.com\/.*\/ads/,
    /pixel(-static)?\.spotify\.com/,
    /\/collect(\?|$)/,
    /googleads|doubleclick|google-analytics/,
  ];
  const blocked = (resource) => {
    const url = String(resource && resource.url ? resource.url : resource);
    return BLOCK.some((re) => re.test(url));
  };
  const empty = () =>
    new Response("{}", { status: 200, headers: { "content-type": "application/json" } });

  const origFetch = window.fetch;
  window.fetch = function (resource, init) {
    return blocked(resource) ? Promise.resolve(empty()) : origFetch.apply(this, arguments);
  };

  const origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__blocked = blocked(url);
    return origOpen.apply(this, arguments);
  };
  const origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function () {
    if (!this.__blocked) return origSend.apply(this, arguments);
    Object.defineProperty(this, "readyState", { value: 4, configurable: true });
    Object.defineProperty(this, "status", { value: 200, configurable: true });
    Object.defineProperty(this, "responseText", { value: "{}", configurable: true });
    Object.defineProperty(this, "response", { value: "{}", configurable: true });
    setTimeout(() => {
      this.dispatchEvent(new Event("readystatechange"));
      this.dispatchEvent(new Event("load"));
      this.dispatchEvent(new Event("loadend"));
    }, 0);
  };
})();
