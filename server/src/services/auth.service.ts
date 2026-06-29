import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { UserRole, UserRow } from '../models/types';
import { assertEmployeeAppLogin } from '../utils/employee-auth.util';
import { merchantOnboardingService } from './merchant-onboarding.service';

export class AuthService {
  /**
   * 登录（兼容旧接口 / check_ready）
   */
  login(phone: string, _code: string, role: UserRole): UserRow {
    const db = getDb();
    const user = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE phone = ?')
      .get(phone);

    if (role === 'merchant') {
      if (!user) {
        throw new Error('MERCHANT_NOT_FOUND');
      }
      if ((user.status ?? 'active') !== 'active') {
        throw new Error('USER_DISABLED');
      }
      const merchant = merchantOnboardingService.assertMerchantCanLogin(phone);
      merchantOnboardingService.linkMerchantUser(merchant, user);
      return db
        .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
        .get(user.id)!;
    }

    if (role === 'employee') {
      return assertEmployeeAppLogin(user);
    }

    throw new Error('INVALID_ROLE');
  }

  /** 审核通过后确保商家与用户关联（不再自动创建已审核商家） */
  ensureMerchantForUser(user: UserRow): void {
    const db = getDb();
    const m = db
      .prepare<[string], { id: string }>(
        'SELECT id FROM merchants WHERE user_id = ?',
      )
      .get(user.id);
    if (m) return;
    const byPhone = merchantOnboardingService.assertMerchantCanLogin(user.phone);
    merchantOnboardingService.linkMerchantUser(byPhone, user);
  }

  getById(id: string): UserRow | undefined {
    const user = getDb()
      .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
      .get(id);
    if (!user) return undefined;
    if ((user.status ?? 'active') !== 'active') {
      throw new Error('USER_DISABLED');
    }
    return user;
  }

  updateAvatarUrl(userId: string, url: string): UserRow {
    const now = nowIso();
    const db = getDb();
    db.prepare(
      'UPDATE users SET avatar_url = ?, updated_at = ? WHERE id = ?',
    ).run(url.trim(), now, userId);
    const user = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
      .get(userId);
    if (!user) throw new Error('USER_NOT_FOUND');
    return user;
  }
}

export const authService = new AuthService();
