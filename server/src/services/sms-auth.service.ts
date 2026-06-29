import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { SmsCodeRow, UserRow } from '../models/types';
import { assertEmployeeAppLogin } from '../utils/employee-auth.util';
import { isValidPhone, normalizePhone } from '../utils/phone.util';
import { merchantOnboardingService } from './merchant-onboarding.service';
import { signUserToken } from './jwt.service';
import {
  isMockSmsProvider,
  MOCK_SMS_CODE,
  smsService,
} from './sms.service';

const ALIYUN_SEND_INTERVAL_SEC = Number(
  process.env.SMS_SEND_INTERVAL_SEC ?? 60,
);
const ALIYUN_DAILY_LIMIT = Number(process.env.SMS_DAILY_LIMIT ?? 10);
const CODE_TTL_MIN = 5;

function generateCode(): string {
  if (isMockSmsProvider()) {
    return MOCK_SMS_CODE;
  }
  return String(Math.floor(100000 + Math.random() * 900000));
}

function getSendIntervalSec(): number {
  if (isMockSmsProvider()) {
    const raw = process.env.SMS_MOCK_SEND_INTERVAL_SEC;
    if (raw === undefined || raw === '') return 0;
    const n = Number(raw);
    return Number.isFinite(n) && n >= 0 ? n : 0;
  }
  return ALIYUN_SEND_INTERVAL_SEC;
}

function getDailyLimit(): number | null {
  if (isMockSmsProvider()) {
    return null;
  }
  return ALIYUN_DAILY_LIMIT;
}

export class SmsAuthService {
  sendCode(phone: string, scene: string, ip?: string | null): void {
    const normalized = normalizePhone(phone);
    if (!isValidPhone(normalized)) {
      throw new Error('INVALID_PHONE');
    }
    if (!scene || typeof scene !== 'string') {
      throw new Error('INVALID_SCENE');
    }

    const db = getDb();
    const now = Date.now();
    const sendIntervalSec = getSendIntervalSec();
    const dailyLimit = getDailyLimit();

    if (sendIntervalSec > 0) {
      const last = db
        .prepare<[string], SmsCodeRow>(
          `SELECT * FROM sms_codes WHERE phone = ? ORDER BY created_at DESC LIMIT 1`,
        )
        .get(normalized);
      if (last) {
        const lastAt = Date.parse(last.created_at);
        if (
          Number.isFinite(lastAt) &&
          now - lastAt < sendIntervalSec * 1000
        ) {
          throw new Error('SEND_TOO_FREQUENT');
        }
      }
    }

    if (dailyLimit !== null) {
      const todayCount = db
        .prepare<[string], { c: number }>(
          `SELECT COUNT(1) AS c FROM sms_codes
           WHERE phone = ? AND date(created_at) = date('now', 'localtime')`,
        )
        .get(normalized);
      if ((todayCount?.c ?? 0) >= dailyLimit) {
        throw new Error('DAILY_LIMIT_EXCEEDED');
      }
    }

    const code = generateCode();
    const expiresAt = new Date(now + CODE_TTL_MIN * 60 * 1000).toISOString();
    const createdAt = nowIso();

    db.prepare(
      `INSERT INTO sms_codes (phone, code, scene, expires_at, ip, created_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).run(normalized, code, scene, expiresAt, ip ?? null, createdAt);

    void smsService.sendVerificationCode(normalized, code);
  }

  loginWithCode(
    phone: string,
    code: string,
    role?: import('../models/types').UserRole,
  ): { token: string; user: UserRow } {
    const normalized = normalizePhone(phone);
    if (!isValidPhone(normalized)) {
      throw new Error('INVALID_PHONE');
    }
    if (!/^\d{6}$/.test(code)) {
      throw new Error('INVALID_CODE');
    }

    const db = getDb();
    const mockBypass =
      isMockSmsProvider() && code === MOCK_SMS_CODE;

    if (!mockBypass) {
      const row = db
        .prepare<[string], SmsCodeRow>(
          `SELECT * FROM sms_codes
           WHERE phone = ? AND used_at IS NULL
           ORDER BY created_at DESC LIMIT 1`,
        )
        .get(normalized);

      if (!row) throw new Error('CODE_NOT_FOUND');
      if (Date.parse(row.expires_at) < Date.now()) {
        throw new Error('CODE_EXPIRED');
      }
      if (row.code !== code) throw new Error('CODE_MISMATCH');

      db.prepare(`UPDATE sms_codes SET used_at = ? WHERE id = ?`).run(
        nowIso(),
        row.id,
      );
    } else {
      const row = db
        .prepare<[string, string], SmsCodeRow>(
          `SELECT * FROM sms_codes
           WHERE phone = ? AND used_at IS NULL AND code = ?
           ORDER BY created_at DESC LIMIT 1`,
        )
        .get(normalized, MOCK_SMS_CODE);
      if (row) {
        db.prepare(`UPDATE sms_codes SET used_at = ? WHERE id = ?`).run(
          nowIso(),
          row.id,
        );
      }
    }

    let user = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE phone = ?')
      .get(normalized);

    if (role === 'merchant') {
      if (!user) {
        throw new Error('MERCHANT_NOT_FOUND');
      }
      if ((user.status ?? 'active') !== 'active') {
        throw new Error('USER_DISABLED');
      }
      const merchant = merchantOnboardingService.assertMerchantCanLogin(normalized);
      merchantOnboardingService.linkMerchantUser(merchant, user);
      user = db
        .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
        .get(user.id)!;
      const token = signUserToken(user);
      return { token, user };
    }

    if (role === 'employee') {
      user = assertEmployeeAppLogin(user);
      const token = signUserToken(user);
      return { token, user };
    }

    // 未指定 role（如后台 admin 登录）：仅校验已存在且未禁用，不自动建号
    if (!user) {
      throw new Error('USER_NOT_FOUND');
    }
    if ((user.status ?? 'active') !== 'active') {
      throw new Error('USER_DISABLED');
    }
    const token = signUserToken(user);
    return { token, user };
  }
}

export const smsAuthService = new SmsAuthService();
