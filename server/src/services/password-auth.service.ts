import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { UserRow } from '../models/types';
import { assertEmployeeAppLogin } from '../utils/employee-auth.util';
import { isValidPhone, normalizePhone } from '../utils/phone.util';
import {
  assertNewPasswordValid,
  DEFAULT_PASSWORD,
  hashPassword,
  verifyPassword,
} from '../utils/password.util';
import { merchantOnboardingService } from './merchant-onboarding.service';
import { signUserToken } from './jwt.service';

export { DEFAULT_PASSWORD } from '../utils/password.util';

export class PasswordAuthService {
  private assertPassword(user: UserRow, password: string): void {
    if (!verifyPassword(password, user.password_hash)) {
      throw new Error('PASSWORD_MISMATCH');
    }
  }

  loginApp(
    phone: string,
    password: string,
    role: 'employee' | 'merchant',
  ): { token: string; user: UserRow } {
    const normalized = normalizePhone(phone);
    if (!isValidPhone(normalized)) throw new Error('INVALID_PHONE');

    const db = getDb();
    let user = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE phone = ?')
      .get(normalized);

    if (role === 'merchant') {
      if (!user) throw new Error('MERCHANT_NOT_FOUND');
      if ((user.status ?? 'active') !== 'active') {
        throw new Error('USER_DISABLED');
      }
      this.assertPassword(user, password);
      const merchant = merchantOnboardingService.assertMerchantCanLogin(normalized);
      merchantOnboardingService.linkMerchantUser(merchant, user);
      user = db
        .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
        .get(user.id)!;
      return { token: signUserToken(user), user };
    }

    user = assertEmployeeAppLogin(user);
    this.assertPassword(user, password);
    return { token: signUserToken(user), user };
  }

  loginBackoffice(
    phone: string,
    password: string,
  ): { token: string; user: UserRow } {
    const normalized = normalizePhone(phone);
    if (!isValidPhone(normalized)) throw new Error('INVALID_PHONE');

    const user = getDb()
      .prepare<[string], UserRow>('SELECT * FROM users WHERE phone = ?')
      .get(normalized);
    if (!user) throw new Error('ACCOUNT_NOT_FOUND');
    if (user.role !== 'admin' && user.role !== 'company_admin') {
      throw new Error('NO_BACKOFFICE_ACCESS');
    }
    if ((user.status ?? 'active') !== 'active') {
      throw new Error('ACCOUNT_DISABLED');
    }
    this.assertPassword(user, password);
    return { token: signUserToken(user), user };
  }

  changePassword(
    userId: string,
    oldPassword: string,
    newPassword: string,
  ): void {
    assertNewPasswordValid(newPassword);
    const db = getDb();
    const user = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
      .get(userId);
    if (!user) throw new Error('NOT_FOUND');
    this.assertPassword(user, oldPassword);
    this.setPasswordHash(userId, newPassword);
  }

  setPasswordHash(userId: string, plain: string): void {
    const hash = hashPassword(plain);
    const now = nowIso();
    getDb()
      .prepare(
        `UPDATE users SET password_hash = ?, password_updated_at = ?, updated_at = ? WHERE id = ?`,
      )
      .run(hash, now, now, userId);
  }

  ensureUserHasPassword(userId: string, plain = DEFAULT_PASSWORD): void {
    const db = getDb();
    const user = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
      .get(userId);
    if (!user) return;
    if (user.password_hash) return;
    this.setPasswordHash(userId, plain);
  }
}

export const passwordAuthService = new PasswordAuthService();
