import { NextFunction, Request, Response } from 'express';
import { getDb } from '../db/database';
import { Unauthorized } from './error.middleware';
import { UserRow } from '../models/types';
import { verifyUserToken } from '../services/jwt.service';

/**
 * 鉴权中间件
 *
 * 优先级：
 * 1. Authorization: Bearer <JWT>
 * 2. X-User-Id / query userId / body userId（兼容旧客户端）
 */
declare module 'express-serve-static-core' {
  interface Request {
    user?: UserRow;
  }
}

function loadUserById(userId: string): UserRow | undefined {
  return getDb()
    .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
    .get(userId);
}

export function loadUser(req: Request, _res: Response, next: NextFunction) {
  const authHeader = req.header('Authorization');
  if (authHeader?.startsWith('Bearer ')) {
    const token = authHeader.slice('Bearer '.length).trim();
    const payload = verifyUserToken(token);
    const userId = payload?.sub;
    if (typeof userId === 'string' && userId) {
      const row = loadUserById(userId);
      if (row) {
        req.user = row;
        return next();
      }
    }
  }

  const userId =
    (req.header('X-User-Id') as string | undefined) ||
    (req.query.userId as string | undefined) ||
    (req.body && typeof req.body === 'object'
      ? (req.body.userId as string | undefined)
      : undefined);

  if (userId) {
    const row = loadUserById(userId);
    if (row) req.user = row;
  }
  next();
}

/** 必须已登录（Bearer Token 或 X-User-Id） */
export function requireAuth(req: Request, _res: Response, next: NextFunction) {
  if (!req.user) {
    return next(Unauthorized());
  }
  next();
}
