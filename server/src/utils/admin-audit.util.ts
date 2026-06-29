import { Request } from 'express';
import { adminOperationLogService } from '../services/admin-operation-log.service';

export function auditAdminOperation(
  req: Request,
  action: string,
  opts?: {
    targetType?: string;
    targetId?: string;
    detail?: unknown;
  },
): void {
  try {
    adminOperationLogService.write({
      operator: req.user ?? null,
      action,
      targetType: opts?.targetType,
      targetId: opts?.targetId,
      detail: opts?.detail,
      ip: req.ip,
    });
  } catch (e) {
    console.warn('[audit] failed to write admin operation log', e);
  }
}
