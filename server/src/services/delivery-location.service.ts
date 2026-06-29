import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import {
  DeliveryLocationRow,
  DeliveryLocationStatus,
  MealType,
} from '../models/types';
import { DEFAULT_COMPANY_ID } from '../utils/company-scope.util';
import { buildOrderBatchKey } from '../utils/order-batch-key.util';

export interface UpdateDeliveryLocationInput {
  date: string;
  mealType: MealType;
  merchantId: string;
  latitude: number;
  longitude: number;
  addressText?: string;
  status?: DeliveryLocationStatus;
  companyId?: string;
}

export class DeliveryLocationService {
  update(input: UpdateDeliveryLocationInput): DeliveryLocationRow {
    const db = getDb();
    const orderBatchKey = buildOrderBatchKey(
      input.date,
      input.mealType,
      input.merchantId,
    );
    const now = nowIso();
    const status = input.status ?? 'delivering';
    const companyId =
      input.companyId ??
      db
        .prepare<[string], { company_id: string | null }>(
          'SELECT company_id FROM merchants WHERE id = ?',
        )
        .get(input.merchantId)?.company_id ??
      DEFAULT_COMPANY_ID;

    const existing = db
      .prepare<[string], DeliveryLocationRow>(
        'SELECT * FROM delivery_locations WHERE order_batch_key = ?',
      )
      .get(orderBatchKey);

    if (existing) {
      db.prepare(
        `UPDATE delivery_locations
         SET latitude = ?, longitude = ?, address_text = ?, status = ?, updated_at = ?
         WHERE order_batch_key = ?`,
      ).run(
        input.latitude,
        input.longitude,
        input.addressText ?? existing.address_text,
        status,
        now,
        orderBatchKey,
      );
      return db
        .prepare<[string], DeliveryLocationRow>(
          'SELECT * FROM delivery_locations WHERE order_batch_key = ?',
        )
        .get(orderBatchKey)!;
    }

    const id = `dl_${nanoid(10)}`;
    db.prepare(
      `INSERT INTO delivery_locations
         (id, company_id, merchant_id, order_batch_key, date, meal_type,
          latitude, longitude, address_text, status, updated_at, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      id,
      companyId,
      input.merchantId,
      orderBatchKey,
      input.date,
      input.mealType,
      input.latitude,
      input.longitude,
      input.addressText ?? null,
      status,
      now,
      now,
    );

    return db
      .prepare<[string], DeliveryLocationRow>(
        'SELECT * FROM delivery_locations WHERE id = ?',
      )
      .get(id)!;
  }

  getCurrent(
    date: string,
    mealType: MealType,
    merchantId: string,
  ): DeliveryLocationRow | undefined {
    const orderBatchKey = buildOrderBatchKey(date, mealType, merchantId);
    return getDb()
      .prepare<[string], DeliveryLocationRow>(
        'SELECT * FROM delivery_locations WHERE order_batch_key = ?',
      )
      .get(orderBatchKey);
  }
}

export const deliveryLocationService = new DeliveryLocationService();
