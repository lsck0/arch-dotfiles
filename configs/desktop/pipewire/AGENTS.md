# desktop/pipewire

- `eq`: the AutoEq preset (`pro-x-2.txt`) as a filter chain on `eq_target`, its own client `pipewire-chain@eq.service`.
- `app-loopback.lua` (run by `app-loopback.service`, outside wireplumber): every app stream plays at its own level into
  `app.<key>`, whose `app.<key>.out` carries the system volume and route. The quickshell mixer drives the `.out` stream.
  On stop each loopback's level is handed to its streams and split again on start, keyed by app key, node name and
  media name; records unclaimed for two starts are dropped, loopbacks of apps unseen for 20 starts are removed. Later
  streams are only routed. While `dot.obs-listen` is set and OBS runs, all loopbacks are muted.
- Never name a loopback node like its app: OBS's application capture matches node.name.
- Native pipewire/wireplumber only, no easyeffects. No-op on WSL.
