import path from 'path';

const PUBLIC_BASE_URL = process.env.PUBLIC_BASE_URL || '';

/**
 * 把 multer 写到 uploads/xxx/abc.png 这种磁盘文件路径
 * 转成对外可访问 URL：
 *   - 默认相对路径 /uploads/xxx/abc.png
 *   - 配置了 PUBLIC_BASE_URL 时，拼接为完整 URL
 */
export function toPublicUrl(diskPath: string): string {
  const uploadRoot = path.resolve(
    process.cwd(),
    process.env.UPLOAD_DIR || './uploads',
  );
  const abs = path.resolve(diskPath);
  let rel = path.relative(uploadRoot, abs).replace(/\\/g, '/');
  if (!rel.startsWith('uploads/')) rel = 'uploads/' + rel;
  const publicPath = '/' + rel;
  if (PUBLIC_BASE_URL) {
    return PUBLIC_BASE_URL.replace(/\/$/, '') + publicPath;
  }
  return publicPath;
}
