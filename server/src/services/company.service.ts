import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { companyToDto, nowIso } from '../models/mappers';
import { CompanyRow, UserRow } from '../models/types';
import { DEFAULT_COMPANY_ID } from '../utils/company-scope.util';
import { defaultPasswordHash } from '../utils/password.util';

export interface CreateCompanyInput {
  companyName: string;
  adminPhone: string;
  adminName?: string;
}

export class CompanyService {
  listForUser(user: UserRow): CompanyRow[] {
    const db = getDb();
    if (user.role === 'admin') {
      return db
        .prepare<[], CompanyRow>(
          'SELECT * FROM companies ORDER BY created_at DESC',
        )
        .all();
    }
    const cid = user.company_id ?? DEFAULT_COMPANY_ID;
    const row = db
      .prepare<[string], CompanyRow>('SELECT * FROM companies WHERE id = ?')
      .get(cid);
    return row ? [row] : [];
  }

  getById(id: string): CompanyRow | undefined {
    return getDb()
      .prepare<[string], CompanyRow>('SELECT * FROM companies WHERE id = ?')
      .get(id);
  }

  /** 企业入驻：创建企业 + 企业管理员账号 */
  create(input: CreateCompanyInput): {
    company: ReturnType<typeof companyToDto>;
    adminUser: UserRow;
  } {
    const db = getDb();
    const now = nowIso();
    const companyId = `comp_${nanoid(8)}`;
    const adminName = input.adminName?.trim() || `${input.companyName}管理员`;

    let admin = db
      .prepare<[string], UserRow>('SELECT * FROM users WHERE phone = ?')
      .get(input.adminPhone.trim());

    const tx = db.transaction(() => {
      if (!admin) {
        const adminId = `u_${nanoid(8)}`;
        const pwdHash = defaultPasswordHash();
        db.prepare(
          `INSERT INTO users
             (id, name, nickname, phone, role, status, company_id, password_hash, password_updated_at, created_at, updated_at)
           VALUES (?, ?, ?, ?, 'company_admin', 'active', ?, ?, ?, ?, ?)`,
        ).run(
          adminId,
          adminName,
          adminName,
          input.adminPhone.trim(),
          companyId,
          pwdHash,
          now,
          now,
          now,
        );
        admin = db
          .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
          .get(adminId)!;
      } else {
        db.prepare(
          `UPDATE users SET role = 'company_admin', company_id = ?, status = 'active', updated_at = ? WHERE id = ?`,
        ).run(companyId, now, admin!.id);
        admin = db
          .prepare<[string], UserRow>('SELECT * FROM users WHERE id = ?')
          .get(admin!.id)!;
      }

      db.prepare(
        `INSERT INTO companies (id, company_name, admin_user_id, status, created_at, updated_at)
         VALUES (?, ?, ?, 'active', ?, ?)`,
      ).run(companyId, input.companyName.trim(), admin!.id, now, now);
    });
    tx();

    const company = this.getById(companyId)!;
    return {
      company: companyToDto(company),
      adminUser: admin!,
    };
  }

  updateStatus(id: string, status: 'active' | 'disabled'): CompanyRow {
    const db = getDb();
    db.prepare(
      'UPDATE companies SET status = ?, updated_at = ? WHERE id = ?',
    ).run(status, nowIso(), id);
    return this.getById(id)!;
  }

  update(
    id: string,
    patch: { companyName?: string; status?: 'active' | 'disabled' },
  ): CompanyRow {
    const db = getDb();
    const fields: string[] = [];
    const vals: unknown[] = [];
    if (patch.companyName) {
      fields.push('company_name = ?');
      vals.push(patch.companyName.trim());
    }
    if (patch.status) {
      fields.push('status = ?');
      vals.push(patch.status);
    }
    if (fields.length === 0) return this.getById(id)!;
    fields.push('updated_at = ?');
    vals.push(nowIso(), id);
    db.prepare(`UPDATE companies SET ${fields.join(', ')} WHERE id = ?`).run(
      ...(vals as never[]),
    );
    return this.getById(id)!;
  }

  getWithContact(id: string) {
    const company = this.getById(id);
    if (!company) return undefined;
    const admin = company.admin_user_id
      ? getDb()
          .prepare<[string], UserRow>(
            'SELECT name, phone FROM users WHERE id = ?',
          )
          .get(company.admin_user_id)
      : undefined;
    return {
      ...company,
      contactName: admin?.name ?? '—',
      contactPhone: admin?.phone ?? '—',
    };
  }
}

export const companyService = new CompanyService();
