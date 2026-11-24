(function noMusicVideos() {
  // the "Music videos" switch is a server product-state flag; an override turns it off locally
  const RETRY_MS = 300;
  const RETRY_COUNT_MAX = 100;
  let tries = 0;
  const off = () => {
    const api = Spicetify?.Platform?.ProductStateAPI?.productStateApi;
    if (!api) {
      if (++tries >= RETRY_COUNT_MAX) {
        console.error("no-music-videos: ProductStateAPI never appeared, giving up");
        return;
      }
      return setTimeout(off, RETRY_MS);
    }
    api.putOverridesValues({ pairs: { "music-video-disabled": "1" } });
  };
  off();
})();
