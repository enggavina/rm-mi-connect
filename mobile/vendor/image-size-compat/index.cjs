'use strict';

const fs = require('node:fs');
const modern = require('image-size-modern');

// Metro 0.83 calls its v1 image-size dependency with a filename in getAssetData,
// while getAssetSize supplies a Buffer. image-size 2 removes filename support.
// Keep the patched parser and adapt only the obsolete synchronous I/O contract.
function imageSize(input) {
  return modern.imageSize(typeof input === 'string' ? fs.readFileSync(input) : input);
}

module.exports = imageSize;
module.exports.default = imageSize;
module.exports.imageSize = imageSize;
module.exports.disableTypes = modern.disableTypes;
module.exports.types = modern.types;
