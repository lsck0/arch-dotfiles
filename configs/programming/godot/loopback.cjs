// preloaded into godot-mcp's node (NODE_OPTIONS): a listen() without a host binds every interface, so one without a
// host binds loopback instead. the bridge already pins its websocket (6505) and proxy http (6506) there, but the
// map_project visualizer (http and websocket from 6510 up, live script edits, no auth) and its port probe do not
'use strict';
const net = require('node:net');

const LOOPBACK = '127.0.0.1';
const listen = net.Server.prototype.listen;

net.Server.prototype.listen = function (...args) {
    const first = args[0];
    if (first === undefined || typeof first === 'function') {
        args.unshift(0, LOOPBACK);
    } else if (typeof first === 'number' || (typeof first === 'string' && /^\d+$/.test(first))) {
        if (typeof args[1] !== 'string') args.splice(1, 0, LOOPBACK);
    } else if (first && typeof first === 'object' && first.path === undefined && first.host === undefined
        && first.fd === undefined && first._handle === undefined) {
        args[0] = { ...first, host: LOOPBACK };
    }
    return listen.apply(this, args);
};
