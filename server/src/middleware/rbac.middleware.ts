import { NextFunction, Request, Response } from 'express';
import { ADMIN_ROLES, ALL_ROLES, BACKOFFICE_ROLES } from '../constants/roles';
import { Unauthorized } from './error.middleware';
import { UserRole } from '../models/types';

export function requireAuth(req: Request, _res: Response, next: NextFunction) {
  if (!req.user) {
    return next(Unauthorized());
  }
  next();
}

export function requireRoles(...roles: UserRole[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user) return next(Unauthorized());
    if (!roles.includes(req.user.role)) {
      return next(Unauthorized('无权访问该资源'));
    }
    next();
  };
}

/** 平台、企业或商家后台 */
export function requireBackofficeAccess(
  req: Request,
  _res: Response,
  next: NextFunction,
) {
  if (!req.user) return next(Unauthorized());
  if (!BACKOFFICE_ROLES.includes(req.user.role)) {
    return next(Unauthorized('需要后台访问权限'));
  }
  next();
}

/** 平台或企业后台管理员 */
export function requireAdminAccess(
  req: Request,
  _res: Response,
  next: NextFunction,
) {
  if (!req.user) return next(Unauthorized());
  if (!ADMIN_ROLES.includes(req.user.role)) {
    return next(Unauthorized('需要管理员权限'));
  }
  next();
}

export function requireValidRole(req: Request, _res: Response, next: NextFunction) {
  if (!req.user) return next();
  if (!ALL_ROLES.includes(req.user.role)) {
    return next(Unauthorized('无效角色'));
  }
  next();
}
