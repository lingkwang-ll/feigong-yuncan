import { Request, Response } from 'express';
import {
  BadRequest,
  Forbidden,
  NotFound,
  Unauthorized,
} from '../middleware/error.middleware';
import { UserRow } from '../models/types';
import { merchantAgreementService } from '../services/merchant-agreement.service';
import { resolveAdminScope } from '../utils/company-scope.util';
import { auditAdminOperation } from '../utils/admin-audit.util';

function ensureUser(req: Request): UserRow {
  if (!req.user) throw Unauthorized();
  return req.user;
}

function resolveOwnedMerchantId(req: Request, bodyMerchantId?: string): string {
  const user = ensureUser(req);
  const scope = resolveAdminScope(user);
  const requestedId = bodyMerchantId?.trim();

  if (scope.isMerchant) {
    if (!scope.merchantId) throw Forbidden('当前账号未绑定商家');
    if (requestedId && requestedId !== scope.merchantId) {
      throw Forbidden('无权操作其它商家');
    }
    return scope.merchantId;
  }

  if ((scope.isPlatformAdmin || scope.isCompanyAdmin) && requestedId) {
    return requestedId;
  }

  if (requestedId) return requestedId;
  throw BadRequest('缺少 merchantId');
}

function mapAgreementError(e: unknown): never {
  const code = (e as Error).message;
  switch (code) {
    case 'AGREEMENT_VERSION_MISMATCH':
      throw BadRequest('协议版本已更新，请刷新页面后重新同意', code);
    case 'MERCHANT_NOT_FOUND':
      throw NotFound('商家不存在');
    default:
      throw e;
  }
}

export const merchantAgreementController = {
  sign(req: Request, res: Response) {
    const body = req.body ?? {};
    const agreementVersion = String(body.agreementVersion ?? '').trim();
    if (!agreementVersion) throw BadRequest('agreementVersion 必填');

    const merchantId = resolveOwnedMerchantId(req, body.merchantId as string);
    const deviceInfo =
      typeof body.deviceInfo === 'string' ? body.deviceInfo.trim() : '';
    const clientTime =
      typeof body.clientTime === 'string' ? body.clientTime.trim() : undefined;

    try {
      const data = merchantAgreementService.recordSign({
        merchantId,
        agreementVersion,
        ipAddress: req.ip || req.socket.remoteAddress,
        userAgent: deviceInfo || req.get('user-agent') || undefined,
        clientTime,
      });
      res.json({ data });
    } catch (e) {
      mapAgreementError(e);
    }
  },
};

export const merchantAgreementAdminController = {
  list(req: Request, res: Response) {
    ensureUser(req);
    const merchantId = req.query.merchantId as string | undefined;
    const data = merchantAgreementService.listForAdmin({ merchantId });
    res.json({ data });
  },

  exportCsv(req: Request, res: Response) {
    ensureUser(req);
    const merchantId = req.query.merchantId as string | undefined;
    const rows = merchantAgreementService.listForAdmin({
      merchantId,
      limit: 5000,
    });
    auditAdminOperation(req, 'export.merchant_agreements', {
      detail: { count: rows.length, merchantId: merchantId ?? null },
    });
    const csv = merchantAgreementService.toCsv(rows);
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader(
      'Content-Disposition',
      'attachment; filename=merchant-agreements.csv',
    );
    res.send('\ufeff' + csv);
  },
};
