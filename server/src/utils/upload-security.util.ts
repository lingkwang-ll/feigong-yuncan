import { randomBytes } from 'crypto';
import fs from 'fs';
import path from 'path';
import { BadRequest } from '../middleware/error.middleware';

/** 允许的图片扩展名（小写，含点） */
export const ALLOWED_IMAGE_EXTENSIONS = new Set([
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
]);

/** 禁止的危险扩展名 */
const BLOCKED_EXTENSIONS = new Set([
  '.html',
  '.htm',
  '.js',
  '.mjs',
  '.exe',
  '.bat',
  '.cmd',
  '.sh',
  '.php',
  '.svg',
]);

const ALLOWED_MIME = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
]);

function normalizeExt(originalName: string): string {
  const ext = path.extname(originalName || '').toLowerCase();
  if (!ext) return '.jpg';
  return ext;
}

function detectImageExt(buffer: Buffer): string | null {
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return '.jpg';
  }
  if (
    buffer.length >= 8 &&
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47
  ) {
    return '.png';
  }
  if (
    buffer.length >= 12 &&
    buffer.toString('ascii', 0, 4) === 'RIFF' &&
    buffer.toString('ascii', 8, 12) === 'WEBP'
  ) {
    return '.webp';
  }
  return null;
}

export function assertAllowedUploadFile(
  originalName: string,
  mimetype: string,
  buffer: Buffer,
): string {
  const ext = normalizeExt(originalName);
  if (BLOCKED_EXTENSIONS.has(ext)) {
    throw BadRequest('禁止上传该类型文件', 'UPLOAD_TYPE_FORBIDDEN');
  }
  if (!ALLOWED_IMAGE_EXTENSIONS.has(ext)) {
    throw BadRequest('仅支持 jpg / png / jpeg / webp 图片', 'UPLOAD_TYPE_FORBIDDEN');
  }
  if (!ALLOWED_MIME.has(mimetype.toLowerCase())) {
    const mime = mimetype.toLowerCase();
    if (mime !== 'application/octet-stream') {
      throw BadRequest('文件 MIME 类型不允许', 'UPLOAD_TYPE_FORBIDDEN');
    }
    // octet-stream：后续 magic byte 校验兜底
  }
  const magicExt = detectImageExt(buffer);
  if (!magicExt) {
    throw BadRequest('文件内容不是有效图片', 'UPLOAD_TYPE_FORBIDDEN');
  }
  if (magicExt !== ext && !(ext === '.jpg' && magicExt === '.jpg')) {
    // jpeg 扩展名与 magic 一致即可；png/webp 必须匹配
    if (ext === '.jpeg' && magicExt === '.jpg') {
      return '.jpg';
    }
    if (magicExt !== ext) {
      throw BadRequest('文件扩展名与内容不匹配', 'UPLOAD_TYPE_FORBIDDEN');
    }
  }
  return ext === '.jpeg' ? '.jpg' : ext;
}

export function randomUploadFilename(ext: string): string {
  const safeExt = ALLOWED_IMAGE_EXTENSIONS.has(ext) ? ext : '.jpg';
  return `${randomBytes(16).toString('hex')}${safeExt}`;
}

export function validateUploadedFileOnDisk(filePath: string, originalName: string, mimetype: string): void {
  const buffer = fs.readFileSync(filePath);
  assertAllowedUploadFile(originalName, mimetype, buffer);
}
