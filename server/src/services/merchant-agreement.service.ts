import { createHash } from 'crypto';
import { nanoid } from 'nanoid';
import {
  assertMerchantAgreementVersion,
  buildMerchantAgreementSnapshot,
  MERCHANT_AGREEMENT_VERSION,
} from '../constants/merchant-agreement.constants';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';

export interface MerchantAgreementRow {
  id: string;
  merchant_id: string;
  agreement_version: string;
  agreement_content_snapshot: string;
  ip_address: string | null;
  user_agent: string | null;
  signed_at: string;
  signature_hash: string;
}

export interface MerchantAgreementDto {
  id: string;
  merchantId: string;
  merchantName: string;
  agreementVersion: string;
  agreementContentSnapshot: string;
  ipAddress: string | null;
  userAgent: string | null;
  signedAt: string;
  signatureHash: string;
}

export interface RecordMerchantAgreementInput {
  merchantId: string;
  agreementVersion: string;
  ipAddress?: string | null;
  userAgent?: string | null;
  clientTime?: string | null;
}

function buildSignatureHash(
  merchantId: string,
  signedAt: string,
  version: string,
): string {
  return createHash('sha256')
    .update(`${merchantId}|${signedAt}|${version}`)
    .digest('hex');
}

function rowToDto(
  row: MerchantAgreementRow,
  merchantName: string,
): MerchantAgreementDto {
  return {
    id: row.id,
    merchantId: row.merchant_id,
    merchantName,
    agreementVersion: row.agreement_version,
    agreementContentSnapshot: row.agreement_content_snapshot,
    ipAddress: row.ip_address,
    userAgent: row.user_agent,
    signedAt: row.signed_at,
    signatureHash: row.signature_hash,
  };
}

export const merchantAgreementService = {
  /** 仅新增签署记录，不可修改或删除历史记录 */
  recordSign(input: RecordMerchantAgreementInput): MerchantAgreementDto {
    const version = input.agreementVersion.trim();
    assertMerchantAgreementVersion(version);

    const db = getDb();
    const merchant = db
      .prepare<[string], { id: string; name: string }>(
        'SELECT id, name FROM merchants WHERE id = ?',
      )
      .get(input.merchantId);
    if (!merchant) throw new Error('MERCHANT_NOT_FOUND');

    const signedAt = input.clientTime?.trim() || nowIso();
    const snapshot = buildMerchantAgreementSnapshot(version);
    const signatureHash = buildSignatureHash(
      input.merchantId,
      signedAt,
      version,
    );
    const id = `ma_${nanoid(10)}`;

    db.prepare(
      `INSERT INTO merchant_agreements
         (id, merchant_id, agreement_version, agreement_content_snapshot,
          ip_address, user_agent, signed_at, signature_hash)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      id,
      input.merchantId,
      version,
      snapshot,
      input.ipAddress?.trim() || null,
      input.userAgent?.trim() || null,
      signedAt,
      signatureHash,
    );

    return rowToDto(
      {
        id,
        merchant_id: input.merchantId,
        agreement_version: version,
        agreement_content_snapshot: snapshot,
        ip_address: input.ipAddress?.trim() || null,
        user_agent: input.userAgent?.trim() || null,
        signed_at: signedAt,
        signature_hash: signatureHash,
      },
      merchant.name,
    );
  },

  /** 服务端触发场景（营业/收款）使用当前版本写入 */
  recordSignWithCurrentVersion(
    merchantId: string,
    ctx: { ipAddress?: string | null; userAgent?: string | null },
  ): MerchantAgreementDto | null {
    try {
      return this.recordSign({
        merchantId,
        agreementVersion: MERCHANT_AGREEMENT_VERSION,
        ipAddress: ctx.ipAddress,
        userAgent: ctx.userAgent,
      });
    } catch {
      return null;
    }
  },

  listForAdmin(filters?: {
    merchantId?: string;
    limit?: number;
    offset?: number;
  }): MerchantAgreementDto[] {
    const db = getDb();
    const limit = Math.min(Math.max(filters?.limit ?? 200, 1), 500);
    const offset = Math.max(filters?.offset ?? 0, 0);
    const merchantId = filters?.merchantId?.trim();

    let sql = `
      SELECT ma.*, m.name AS merchant_name
      FROM merchant_agreements ma
      JOIN merchants m ON m.id = ma.merchant_id
    `;
    const params: unknown[] = [];
    if (merchantId) {
      sql += ' WHERE ma.merchant_id = ?';
      params.push(merchantId);
    }
    sql += ' ORDER BY ma.signed_at DESC LIMIT ? OFFSET ?';
    params.push(limit, offset);

    const rows = db
      .prepare(sql)
      .all(...params) as (MerchantAgreementRow & { merchant_name: string })[];

    return rows.map((r) => rowToDto(r, r.merchant_name));
  },

  toCsv(rows: MerchantAgreementDto[]): string {
    const header = [
      'id',
      'merchantId',
      'merchantName',
      'agreementVersion',
      'signedAt',
      'ipAddress',
      'userAgent',
      'signatureHash',
      'agreementContentSnapshot',
    ];
    const escape = (v: string | null | undefined) => {
      const s = v ?? '';
      if (/[",\n\r]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
      return s;
    };
    const lines = [header.join(',')];
    for (const r of rows) {
      lines.push(
        [
          r.id,
          r.merchantId,
          r.merchantName,
          r.agreementVersion,
          r.signedAt,
          r.ipAddress,
          r.userAgent,
          r.signatureHash,
          r.agreementContentSnapshot,
        ]
          .map((c) => escape(String(c ?? '')))
          .join(','),
      );
    }
    return lines.join('\n');
  },
};
