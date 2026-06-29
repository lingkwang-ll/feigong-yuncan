import { Router, RequestHandler } from 'express';
import fs from 'fs';
import multer from 'multer';
import path from 'path';
import { uploadController } from '../controllers/upload.controller';
import { requireAuth } from '../middleware/auth.middleware';
import { BadRequest } from '../middleware/error.middleware';
import {
  ALLOWED_IMAGE_EXTENSIONS,
  randomUploadFilename,
  validateUploadedFileOnDisk,
} from '../utils/upload-security.util';

export const UPLOAD_DIR = path.resolve(
  process.cwd(),
  process.env.UPLOAD_DIR || './uploads',
);

export const UPLOAD_SUBDIRS = [
  'qrcodes',
  'licenses',
  'stores',
  'payments',
  'dishes',
  'merchants',
  'chats',
  'reviews',
  'avatars',
  'supports',
] as const;

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

const ALLOWED_MIME = new Set(['image/jpeg', 'image/png', 'image/webp']);

function normalizeExt(originalName: string): string {
  const ext = path.extname(originalName || '').toLowerCase();
  return ext || '.jpg';
}

export function ensureUploadSubdirs(baseDir = UPLOAD_DIR): void {
  if (!fs.existsSync(baseDir)) {
    fs.mkdirSync(baseDir, { recursive: true });
  }
  for (const sub of UPLOAD_SUBDIRS) {
    const target = path.join(baseDir, sub);
    if (!fs.existsSync(target)) {
      fs.mkdirSync(target, { recursive: true });
    }
  }
}

export function buildUploader(subdir: string) {
  const target = path.join(UPLOAD_DIR, subdir);
  ensureUploadSubdirs(UPLOAD_DIR);
  const storage = multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, target),
    filename: (_req, file, cb) => {
      let ext = normalizeExt(file.originalname);
      if (ext === '.jpeg') ext = '.jpg';
      if (!ALLOWED_IMAGE_EXTENSIONS.has(ext)) ext = '.jpg';
      cb(null, randomUploadFilename(ext));
    },
  });
  return multer({
    storage,
    limits: { fileSize: 10 * 1024 * 1024 },
    fileFilter: (_req, file, cb) => {
      const ext = normalizeExt(file.originalname);
      if (BLOCKED_EXTENSIONS.has(ext)) {
        cb(new Error('禁止上传该类型文件'));
        return;
      }
      if (!ALLOWED_IMAGE_EXTENSIONS.has(ext) && ext !== '.jpeg') {
        cb(new Error('仅支持 jpg / png / jpeg / webp 图片'));
        return;
      }
      if (!ALLOWED_MIME.has((file.mimetype || '').toLowerCase())) {
        const ext = normalizeExt(file.originalname);
        // Flutter / 部分客户端未设置 Content-Type，默认为 application/octet-stream
        if (
          (file.mimetype || '').toLowerCase() === 'application/octet-stream' &&
          ALLOWED_IMAGE_EXTENSIONS.has(ext)
        ) {
          cb(null, true);
          return;
        }
        cb(new Error('文件 MIME 类型不允许，仅支持 jpg / png / webp'));
        return;
      }
      cb(null, true);
    },
  });
}

const paymentUploader = buildUploader('payments');
const dishUploader = buildUploader('dishes');
const qrUploader = buildUploader('qrcodes');
const licenseUploader = buildUploader('licenses');
const storePhotoUploader = buildUploader('stores');
const merchantLogoUploader = buildUploader('merchants');
const reviewImageUploader = buildUploader('reviews');
const employeeAvatarUploader = buildUploader('avatars');
const supportImageUploader = buildUploader('supports');

export function singleFileUpload(
  uploader: multer.Multer,
  handler: RequestHandler,
): RequestHandler {
  return (req, res, next) => {
    uploader.single('file')(req, res, (err: unknown) => {
      if (err) {
        const msg =
          err instanceof multer.MulterError && err.code === 'LIMIT_FILE_SIZE'
            ? '文件过大，最大 10MB'
            : err instanceof Error
              ? err.message
              : '上传失败';
        return next(BadRequest(msg, 'UPLOAD_FAILED'));
      }
      if (req.file) {
        try {
          validateUploadedFileOnDisk(
            req.file.path,
            req.file.originalname,
            req.file.mimetype,
          );
        } catch (e) {
          try {
            fs.unlinkSync(req.file.path);
          } catch {
            // ignore
          }
          return next(e);
        }
      }
      return handler(req, res, next);
    });
  };
}

const router = Router();

// 所有上传接口必须登录；按场景在控制器里再做角色/归属校验
router.post(
  '/payment-screenshot',
  requireAuth,
  singleFileUpload(paymentUploader, uploadController.paymentScreenshot),
);
router.post(
  '/dish-image',
  requireAuth,
  singleFileUpload(dishUploader, uploadController.dishImage),
);
router.post(
  '/merchant-qr-code',
  requireAuth,
  singleFileUpload(qrUploader, uploadController.merchantQrCode),
);
router.post(
  '/merchant-license',
  requireAuth,
  singleFileUpload(licenseUploader, uploadController.merchantLicense),
);
router.post(
  '/store-photo',
  requireAuth,
  singleFileUpload(storePhotoUploader, uploadController.storePhoto),
);
router.post(
  '/merchant-logo',
  requireAuth,
  singleFileUpload(merchantLogoUploader, uploadController.merchantLogo),
);
router.post(
  '/review-images',
  requireAuth,
  singleFileUpload(reviewImageUploader, uploadController.reviewImage),
);
router.post(
  '/employee-avatar',
  requireAuth,
  singleFileUpload(employeeAvatarUploader, uploadController.employeeAvatar),
);
router.post(
  '/support-image',
  requireAuth,
  singleFileUpload(supportImageUploader, uploadController.supportImage),
);

export default router;
