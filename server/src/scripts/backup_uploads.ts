/**
 * backup_uploads.ts — 复制 uploads 目录到 server/backups/uploads-{timestamp}/
 *
 * 用法：npm run backup:uploads
 */
import 'dotenv/config';
import fs from 'fs';
import path from 'path';

function pad(n: number) {
  return n.toString().padStart(2, '0');
}

function timestamp(d = new Date()) {
  return (
    d.getFullYear().toString() +
    pad(d.getMonth() + 1) +
    pad(d.getDate()) +
    '-' +
    pad(d.getHours()) +
    pad(d.getMinutes()) +
    pad(d.getSeconds())
  );
}

function copyDir(src: string, dest: string) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const from = path.join(src, entry.name);
    const to = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDir(from, to);
    } else if (entry.isFile()) {
      fs.copyFileSync(from, to);
    }
  }
}

function main() {
  const uploadDir = path.resolve(
    process.cwd(),
    process.env.UPLOAD_DIR || './uploads',
  );
  if (!fs.existsSync(uploadDir)) {
    console.error(`[backup_uploads] uploads dir not found: ${uploadDir}`);
    process.exit(1);
  }

  const backupRoot = path.resolve(process.cwd(), './backups');
  if (!fs.existsSync(backupRoot)) fs.mkdirSync(backupRoot, { recursive: true });

  const target = path.join(backupRoot, `uploads-${timestamp()}`);
  copyDir(uploadDir, target);

  let fileCount = 0;
  const walk = (dir: string) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(p);
      else fileCount++;
    }
  };
  walk(target);

  console.log('[backup_uploads] ok ✅');
  console.log(`  source : ${uploadDir}`);
  console.log(`  target : ${target}`);
  console.log(`  files  : ${fileCount}`);
}

main();
