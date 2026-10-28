// Preloaded into every Node process (NODE_OPTIONS, set in home/shell.nix).
//
// Node's listen(port) with no host binds the dual-stack wildcard [::]. WSL's
// Consomme localhost relay only forwards IPv4 listeners to Windows. For a [::]
// listener it opens IPv6-only relay ports that accept connections and never
// forward them, and the guest itself refuses 127.0.0.1 for it
// (microsoft/WSL#41860, #41836, #41117). A Windows browser then gets
// ERR_CONNECTION_REFUSED or a hang from dev servers such as
// https://app-local.dev.bookcreator.com:3000.
//
// So listen(port) binds the IPv4 wildcard instead, which is the IPv4 half of
// what Node would have bound anyway. A host passed explicitly is left alone.
// Set NODE_LISTEN_DUALSTACK=1 to get stock Node behavior back.
'use strict';

const net = require('net');

if (!process.env.NODE_LISTEN_DUALSTACK && !net.Server.prototype.listen.__ipv4Default) {
  const listen = net.Server.prototype.listen;

  const patched = function (...args) {
    const first = args[0];
    if (first === undefined || typeof first === 'function' || typeof first === 'number' || (typeof first === 'string' && /^\d+$/.test(first))) {
      // listen([port[, host[, backlog]]][, callback])
      if (first === undefined || typeof first === 'function') args.unshift(0);
      if (args[1] == null || args[1] === '') args[1] = '0.0.0.0';
      else if (typeof args[1] !== 'string') args.splice(1, 0, '0.0.0.0');
    } else if (
      first && typeof first === 'object' &&
      (typeof first.port === 'number' || typeof first.port === 'string') &&
      !first.host && !first.path && first.fd === undefined && !first.handle && !first.ipv6Only
    ) {
      args[0] = { ...first, host: '0.0.0.0' };
    }
    return listen.apply(this, args);
  };
  patched.__ipv4Default = true;
  net.Server.prototype.listen = patched;
}
