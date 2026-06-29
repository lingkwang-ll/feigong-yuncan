import jwt, { SignOptions } from 'jsonwebtoken';
import { UserRow } from '../models/types';

function getSecret(): string {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw new Error('JWT_SECRET 未配置');
  }
  return secret;
}

export function signUserToken(user: UserRow): string {
  const options: SignOptions = {
    expiresIn: (process.env.JWT_EXPIRES_IN || '7d') as SignOptions['expiresIn'],
  };
  return jwt.sign(
    {
      sub: user.id,
      phone: user.phone,
      role: user.role,
      companyId: user.company_id ?? null,
    },
    getSecret(),
    options,
  );
}

export function verifyUserToken(token: string): jwt.JwtPayload | null {
  try {
    const payload = jwt.verify(token, getSecret());
    if (typeof payload === 'string') return null;
    return payload;
  } catch {
    return null;
  }
}
