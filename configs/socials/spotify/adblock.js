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
  const blocked = (url) => typeof url === "string" && BLOCK.some((re) => re.test(url));
  const empty = () =>
    new Response("{}", { status: 200, headers: { "content-type": "application/json" } });

  const origFetch = window.fetch;
  window.fetch = function (resource, init) {
    const url = resource instanceof Request ? resource.url : resource;
    return blocked(url) ? Promise.resolve(empty()) : origFetch.apply(this, arguments);
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
    setTimeout(() => {
      if (typeof this.onreadystatechange === "function") this.onreadystatechange();
      if (typeof this.onload === "function") this.onload();
    }, 0);
  };
})();
