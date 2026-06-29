import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { UserRow } from '../models/types';

export interface AdminOperationLogInput {
  operator?: UserRow | null;
  action: string;
  targetType?: string;
  targetId?: string;
  detail?: unknown;
  ip?: string;
}

export class AdminOperationLogService {
  write(input: AdminOperationLogInput): void {
    const db = getDb();
    db.prepare(
      `INSERT INTO admin_operation_logs
         (id, operator_user_id, operator_role, action, target_type, target_id, detail_json, ip_address, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      `aol_${nanoid(10)}`,
      input.operator?.id ?? null,
      input.operator?.role ?? null,
      input.action,
      input.targetType ?? null,
      input.targetId ?? null,
      input.detail != null ? JSON.stringify(input.detail) : null,
      input.ip ?? null,
      nowIso(),
    );
  }
}

export const adminOperationLogService = new AdminOperationLogService();
