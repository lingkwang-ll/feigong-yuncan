import { createHash } from 'crypto';
import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { MealType } from '../models/types';
import { orderService } from './order.service';

export interface MealLabelPrintRow {
  id: string;
  merchant_id: string;
  order_id: string;
  label_code: string;
  meal_type: string;
  business_date: string;
  employee_name: string;
  department: string;
  package_name: string;
  label_hash: string;
  printed_at: string;
  print_count: number;
  created_at: string;
  updated_at: string;
}

export interface MealLabelPrintStatusDto {
  orderId: string;
  labelCode: string;
  printedAt: string;
  printCount: number;
}

export interface MarkMealLabelPrintedInput {
  orderId: string;
  labelCode: string;
  employeeName?: string;
  department?: string;
  packageName?: string;
}

function buildLabelHash(input: {
  merchantId: string;
  businessDate: string;
  mealType: string;
  orderId: string;
  labelCode: string;
}): string {
  const raw = [
    input.merchantId,
    input.businessDate,
    input.mealType,
    input.orderId,
    input.labelCode,
  ].join('|');
  return createHash('sha256').update(raw).digest('hex').slice(0, 32);
}

export class MealLabelPrintService {
  buildHash(
    merchantId: string,
    businessDate: string,
    mealType: MealType,
    orderId: string,
    labelCode: string,
  ): string {
    return buildLabelHash({
      merchantId,
      businessDate,
      mealType,
      orderId,
      labelCode,
    });
  }

  listStatus(
    merchantId: string,
    businessDate: string,
    mealType: MealType,
  ): MealLabelPrintStatusDto[] {
    const rows = getDb()
      .prepare<[string, string, string], MealLabelPrintRow>(
        `SELECT * FROM meal_label_prints
         WHERE merchant_id = ? AND business_date = ? AND meal_type = ?
         ORDER BY printed_at DESC`,
      )
      .all(merchantId, businessDate, mealType);
    return rows.map((r) => ({
      orderId: r.order_id,
      labelCode: r.label_code,
      printedAt: r.printed_at,
      printCount: r.print_count,
    }));
  }

  markPrinted(
    merchantId: string,
    businessDate: string,
    mealType: MealType,
    labels: MarkMealLabelPrintedInput[],
  ): { marked: number; updated: number } {
    if (labels.length === 0) return { marked: 0, updated: 0 };
    const db = getDb();
    const now = nowIso();
    let marked = 0;
    let updated = 0;

    const tx = db.transaction(() => {
      for (const label of labels) {
        const orderId = label.orderId?.trim();
        const labelCode = label.labelCode?.trim();
        if (!orderId || !labelCode) continue;

        const order = orderService.getById(orderId);
        if (!order) throw new Error('ORDER_NOT_FOUND');
        if (order.merchant_id !== merchantId) throw new Error('FORBIDDEN');

        const labelHash = buildLabelHash({
          merchantId,
          businessDate,
          mealType,
          orderId,
          labelCode,
        });

        const existing = db
          .prepare<[string], MealLabelPrintRow>(
            'SELECT * FROM meal_label_prints WHERE label_hash = ?',
          )
          .get(labelHash);

        if (existing) {
          db.prepare(
            `UPDATE meal_label_prints
             SET print_count = print_count + 1, printed_at = ?, updated_at = ?
             WHERE id = ?`,
          ).run(now, now, existing.id);
          updated++;
        } else {
          db.prepare(
            `INSERT INTO meal_label_prints
               (id, merchant_id, order_id, label_code, meal_type, business_date,
                employee_name, department, package_name, label_hash,
                printed_at, print_count, created_at, updated_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)`,
          ).run(
            `mlp_${nanoid(10)}`,
            merchantId,
            orderId,
            labelCode,
            mealType,
            businessDate,
            label.employeeName?.trim() ?? '',
            label.department?.trim() ?? '',
            label.packageName?.trim() ?? '',
            labelHash,
            now,
            now,
            now,
          );
          marked++;
        }
      }
    });
    tx();
    return { marked, updated };
  }
}

export const mealLabelPrintService = new MealLabelPrintService();
