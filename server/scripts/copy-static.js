'use strict';

const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const src = path.join(root, 'src', 'db', 'schema.sql');
const destDir = path.join(root, 'dist', 'db');
const dest = path.join(destDir, 'schema.sql');

if (!fs.existsSync(src)) {
  console.error('[copy-static] missing source:', src);
  process.exit(1);
}

fs.mkdirSync(destDir, { recursive: true });
fs.copyFileSync(src, dest);
console.log('[copy-static] copied schema.sql -> dist/db/schema.sql');
