import bcrypt from 'bcryptjs';

export const DEFAULT_PASSWORD = '123456';
const SALT_ROUNDS = 10;

export function hashPassword(plain: string): string {
  return bcrypt.hashSync(plain, SALT_ROUNDS);
}

export function verifyPassword(
  plain: string,
  hash: string | null | undefined,
): boolean {
  if (!hash) return false;
  return bcrypt.compareSync(plain, hash);
}

export function assertNewPasswordValid(password: string): void {
  if (!password || password.length < 6) {
    throw new Error('PASSWORD_TOO_SHORT');
  }
}

export function defaultPasswordHash(): string {
  return hashPassword(DEFAULT_PASSWORD);
}
