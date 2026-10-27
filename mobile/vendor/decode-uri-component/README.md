This is the npm `decode-uri-component@0.5.1` implementation, with only
`export default function decodeUriComponent` changed to
`module.exports = function decodeUriComponent`.

Expo SDK54 depends on CommonJS query-string7, which calls require() as a function.
The upstream decoder0.5.1 fixes malformed-input exponential decoding but is ESM.
This export adaptation retains that fix without upgrading Expo or changing URL
parsing semantics. Upstream code and its MIT license are included verbatim except
for the export. Remove this adapter when upgrading to a compatible Expo Router.

Source: https://www.npmjs.com/package/decode-uri-component/v/0.5.1
Tarball SHA1: 7f66b25bf435df723f9af55713dcf860a1c297d2
