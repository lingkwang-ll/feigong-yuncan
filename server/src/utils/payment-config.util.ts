import fs from 'fs';
import path from 'path';

export interface PaymentConfigValidation {
  ok: boolean;
  missing: string[];
}

const WECHAT_ENV_KEYS = [
  'WECHAT_PAY_APPID',
  'WECHAT_PAY_MCH_ID',
  'WECHAT_PAY_API_V3_KEY',
  'WECHAT_PAY_PRIVATE_KEY_PATH',
  'WECHAT_PAY_CERT_SERIAL_NO',
  'WECHAT_PAY_NOTIFY_URL',
] as const;

const ALIPAY_ENV_KEYS = [
  'ALIPAY_APP_ID',
  'ALIPAY_PRIVATE_KEY_PATH',
  'ALIPAY_PUBLIC_KEY_PATH',
  'ALIPAY_NOTIFY_URL',
  'ALIPAY_GATEWAY',
] as const;

function envMissing(keys: readonly string[]): string[] {
  return keys.filter((k) => !process.env[k]?.trim());
}

function keyFileMissing(envKey: string): string | null {
  const raw = process.env[envKey]?.trim();
  if (!raw) return null;
  const abs = path.isAbsolute(raw) ? raw : path.resolve(process.cwd(), raw);
  if (!fs.existsSync(abs)) {
    return `${envKey} (file not found: ${abs})`;
  }
  return null;
}

/** 微信支付商户配置完整性（不含业务开关） */
export function validateWechatPayEnv(): PaymentConfigValidation {
  const missing = envMissing(WECHAT_ENV_KEYS);
  const keyMissing = keyFileMissing('WECHAT_PAY_PRIVATE_KEY_PATH');
  if (keyMissing) missing.push(keyMissing);
  return { ok: missing.length === 0, missing };
}

/** 支付宝商户配置完整性（不含业务开关） */
export function validateAlipayEnv(): PaymentConfigValidation {
  const missing = envMissing(ALIPAY_ENV_KEYS);
  const privMissing = keyFileMissing('ALIPAY_PRIVATE_KEY_PATH');
  const pubMissing = keyFileMissing('ALIPAY_PUBLIC_KEY_PATH');
  if (privMissing) missing.push(privMissing);
  if (pubMissing) missing.push(pubMissing);
  return { ok: missing.length === 0, missing };
}

export function isProductionEnv(): boolean {
  return process.env.NODE_ENV === 'production';
}
