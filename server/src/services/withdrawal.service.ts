import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { MerchantWithdrawalRow } from '../models/types';
import { settlementService } from './settlement.service';

export class WithdrawalService {
  create(params: {
    merchantId: string;
    amount: number;
    accountName: string;
    accountType: string;
    accountNo: string;
  }): MerchantWithdrawalRow {
    const amount = Number(params.amount);
    if (!Number.isFinite(amount) || amount <= 0) {
      throw new Error('INVALID_AMOUNT');
    }

    const wallet = settlementService.getMerchantWalletSummary(params.merchantId);
    if (amount > wallet.withdrawableAmount + 0.001) {
      throw new Error('AMOUNT_EXCEEDS_WITHDRAWABLE');
    }

    const accountName = (params.accountName ?? '').trim();
    const accountType = (params.accountType ?? '').trim();
    const accountNo = (params.accountNo ?? '').trim();
    if (!accountName || !accountType || !accountNo) {
      throw new Error('ACCOUNT_REQUIRED');
    }

    const db = getDb();
    const now = nowIso();
    const id = `WD${nanoid(10)}`;
    db.prepare(
      `INSERT INTO merchant_withdrawals
         (id, merchant_id, amount, status, account_name, account_type, account_no,
          remark, created_at, updated_at, reviewed_at)
       VALUES (?, ?, ?, 'pending', ?, ?, ?, NULL, ?, ?, NULL)`,
    ).run(
      id,
      params.merchantId,
      Number(amount.toFixed(2)),
      accountName,
      accountType,
      accountNo,
      now,
      now,
    );

    return db
      .prepare<[string], MerchantWithdrawalRow>(
        'SELECT * FROM merchant_withdrawals WHERE id = ?',
      )
      .get(id)!;
  }

  listByMerchant(merchantId: string): MerchantWithdrawalRow[] {
    const db = getDb();
    return db
      .prepare<[string], MerchantWithdrawalRow>(
        `SELECT * FROM merchant_withdrawals
         WHERE merchant_id = ?
         ORDER BY datetime(created_at) DESC`,
      )
      .all(merchantId);
  }
}

export const withdrawalService = new WithdrawalService();
