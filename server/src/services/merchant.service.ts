import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { MealType, MerchantRow } from '../models/types';
import {
  deriveMealOrderDeadlinesFromOpeningHours,
  normalizeMealOpeningHours,
  validateMealOpeningHours,
} from '../utils/meal-opening-hours.util';
import { DEFAULT_COMPANY_ID } from '../utils/company-scope.util';

export class MerchantService {
  /** 员工端：仅返回已审核、已启用、营业中的同企业商家 */
  listForCompany(companyId?: string | null): MerchantRow[] {
    const cid = companyId ?? DEFAULT_COMPANY_ID;
    return getDb()
      .prepare<[string], MerchantRow>(
        `SELECT * FROM merchants
         WHERE company_id = ?
           AND onboarding_status = 'approved'
           AND is_enabled = 1
         ORDER BY distance ASC, id ASC`,
      )
      .all(cid);
  }

  listAll(): MerchantRow[] {
    return getDb()
      .prepare<[], MerchantRow>(
        'SELECT * FROM merchants ORDER BY distance ASC, id ASC',
      )
      .all();
  }

  getById(id: string): MerchantRow | undefined {
    return getDb()
      .prepare<[string], MerchantRow>('SELECT * FROM merchants WHERE id = ?')
      .get(id);
  }

  getByUserId(userId: string): MerchantRow | undefined {
    return getDb()
      .prepare<[string], MerchantRow>(
        'SELECT * FROM merchants WHERE user_id = ?',
      )
      .get(userId);
  }

  updatePaymentQrCode(id: string, url: string): MerchantRow {
    return this.patch(id, { payment_qr_code_url: url });
  }

  updateChannelPaymentQr(
    id: string,
    channel: 'wechat' | 'alipay',
    url: string,
  ): MerchantRow {
    const patch: Record<string, unknown> = {};
    if (channel === 'wechat') {
      patch.wechat_payment_qr_url = url;
      patch.wechat_payment_qr_urls_json = JSON.stringify([url]);
      const row = this.getById(id);
      if (
        row &&
        (!row.payment_qr_code_url ||
          row.payment_qr_code_url === 'qr' ||
          !row.payment_qr_code_url.trim())
      ) {
        patch.payment_qr_code_url = url;
      }
    } else {
      patch.alipay_payment_qr_url = url;
      patch.alipay_payment_qr_urls_json = JSON.stringify([url]);
    }
    return this.patch(id, patch);
  }

  updateLogo(id: string, url: string): MerchantRow {
    return this.patch(id, { logo_url: url });
  }

  updateProfile(
    id: string,
    input: {
      name?: string;
      logo?: string;
      contactName?: string;
      contactPhone?: string;
      address?: string;
      description?: string;
    },
  ): MerchantRow {
    const patch: Record<string, unknown> = {};
    if (input.name != null) patch.name = input.name.trim();
    if (input.logo != null) patch.logo_url = input.logo.trim();
    if (input.contactName != null) patch.contact_name = input.contactName.trim();
    if (input.contactPhone != null) {
      patch.contact_phone = input.contactPhone.trim();
      patch.phone = input.contactPhone.trim();
    }
    if (input.address != null) patch.address = input.address.trim();
    if (input.description != null) patch.description = input.description.trim();
    return this.patch(id, patch);
  }

  updateDeliverySettings(
    id: string,
    input: {
      deliveryModes?: string[];
      deliveryFee?: number;
      deliveryScope?: string;
      estimatedDeliveryTime?: string;
    },
  ): MerchantRow {
    const patch: Record<string, unknown> = {};
    if (input.deliveryModes != null) {
      patch.delivery_modes_json = JSON.stringify(input.deliveryModes);
    }
    if (input.deliveryFee != null) patch.delivery_fee = input.deliveryFee;
    if (input.deliveryScope != null) {
      patch.delivery_scope = input.deliveryScope.trim();
    }
    if (input.estimatedDeliveryTime != null) {
      patch.estimated_delivery_time = input.estimatedDeliveryTime.trim();
    }
    return this.patch(id, patch);
  }

  updateBusinessHours(
    id: string,
    input: {
      supportedMealTypes?: MealType[];
      mealOpeningHours?: Record<
        string,
        { enabled?: boolean; start?: string; end?: string; hours?: string }
      >;
    },
  ): MerchantRow {
    const patch: Record<string, unknown> = {};
    if (input.supportedMealTypes != null) {
      patch.supported_meal_types_json = JSON.stringify(input.supportedMealTypes);
    }
    if (input.mealOpeningHours != null) {
      validateMealOpeningHours(input.mealOpeningHours);
      const normalized = normalizeMealOpeningHours(input.mealOpeningHours);
      patch.meal_opening_hours_json = JSON.stringify(normalized);
      patch.meal_order_deadlines_json = JSON.stringify(
        deriveMealOrderDeadlinesFromOpeningHours(normalized),
      );
    }
    return this.patch(id, patch);
  }

  update(
    id: string,
    patch: Partial<
      Pick<
        MerchantRow,
        | 'name'
        | 'logo_url'
        | 'address'
        | 'distance_text'
        | 'distance'
        | 'rating'
        | 'month_sold'
        | 'hygiene_grade'
        | 'is_open'
        | 'payment_qr_code_url'
        | 'delivery_fee'
      >
    >,
  ): MerchantRow {
    return this.patch(id, patch as Record<string, unknown>);
  }

  private patch(id: string, patch: Record<string, unknown>): MerchantRow {
    const db = getDb();
    const fields: string[] = [];
    const values: unknown[] = [];
    for (const [k, v] of Object.entries(patch)) {
      if (v === undefined) continue;
      fields.push(`${k} = ?`);
      values.push(v);
    }
    if (fields.length === 0) return this.getById(id)!;
    fields.push('updated_at = ?');
    values.push(nowIso());
    values.push(id);
    db.prepare(`UPDATE merchants SET ${fields.join(', ')} WHERE id = ?`).run(
      ...(values as never[]),
    );
    return this.getById(id)!;
  }
}

export const merchantService = new MerchantService();
