(function noMusicVideos() {
  // the "Music videos" switch is a server product-state flag; an override turns it off locally
  const off = () => {
    const api = Spicetify?.Platform?.ProductStateAPI?.productStateApi;
    if (!api) return setTimeout(off, 300);
    api.putOverridesValues({ pairs: { "music-video-disabled": "1" } });
  };
  off();
})();
