import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso, parsePackageRules } from '../models/mappers';
import {
  DISH_LISTING_MEAL_TYPES,
  MealType,
  PackageRow,
  PackageRules,
} from '../models/types';

const ALLOWED_MEALS: MealType[] = [...DISH_LISTING_MEAL_TYPES];

export interface PackageInput {
  merchantId: string;
  name: string;
  description?: string;
  basePrice: number;
  mealTypes?: MealType[];
  rules?: PackageRules;
  allowExtra?: boolean;
  extraDishIds?: string[];
  isEnabled?: boolean;
}

function normalizeMealTypes(input?: MealType[]): MealType[] {
  if (!input || !Array.isArray(input)) return [];
  const seen = new Set<string>();
  const out: MealType[] = [];
  for (const m of input) {
    if (ALLOWED_MEALS.includes(m) && !seen.has(m)) {
      seen.add(m);
      out.push(m);
    }
  }
  return out;
}

function normalizeRules(input?: PackageRules): PackageRules {
  if (!input || typeof input !== 'object') return {};
  // 复用 mapper 的校验逻辑（要求正整数）；
  // 业务简化：新建/更新套餐时只保留 meat 和 vegetable，避免再依赖 staple/soup/drink。
  const parsed = parsePackageRules(JSON.stringify(input));
  const out: PackageRules = {};
  if ((parsed.meat ?? 0) > 0) out.meat = parsed.meat;
  if ((parsed.vegetable ?? 0) > 0) out.vegetable = parsed.vegetable;
  return out;
}

function normalizeStringArray(input?: string[]): string[] {
  if (!input || !Array.isArray(input)) return [];
  const seen = new Set<string>();
  const out: string[] = [];
  for (const s of input) {
    if (typeof s !== 'string') continue;
    const t = s.trim();
    if (!t || seen.has(t)) continue;
    seen.add(t);
    out.push(t);
  }
  return out;
}

export class PackageService {
  listByMerchant(merchantId: string, opts?: { mealType?: MealType }): PackageRow[] {
    const db = getDb();
    if (opts?.mealType) {
      return db
        .prepare<[string, string], PackageRow>(
          `SELECT * FROM packages
            WHERE merchant_id = ?
              AND is_enabled = 1
              AND (meal_types_json = '[]' OR instr(meal_types_json, ?) > 0)
            ORDER BY base_price ASC, created_at DESC`,
        )
        .all(merchantId, opts.mealType);
    }
    return db
      .prepare<[string], PackageRow>(
        `SELECT * FROM packages WHERE merchant_id = ? ORDER BY is_enabled DESC, base_price ASC, created_at DESC`,
      )
      .all(merchantId);
  }

  /** 商家维护页（含未启用） */
  listAllByMerchant(merchantId: string): PackageRow[] {
    return getDb()
      .prepare<[string], PackageRow>(
        `SELECT * FROM packages WHERE merchant_id = ? ORDER BY created_at DESC`,
      )
      .all(merchantId);
  }

  getById(id: string): PackageRow | undefined {
    return getDb()
      .prepare<[string], PackageRow>('SELECT * FROM packages WHERE id = ?')
      .get(id);
  }

  create(input: PackageInput): PackageRow {
    if (!input.merchantId) throw new Error('INVALID_MERCHANT');
    if (!input.name?.trim()) throw new Error('INVALID_NAME');
    if (!(input.basePrice >= 0)) throw new Error('INVALID_PRICE');
    const id = `pkg_${nanoid(8)}`;
    const now = nowIso();
    const mealTypes = normalizeMealTypes(input.mealTypes);
    const rules = normalizeRules(input.rules);
    if ((rules.meat ?? 0) + (rules.vegetable ?? 0) === 0) {
      // 至少要选 1 个荤菜或素菜，否则套餐没有意义
      throw new Error('EMPTY_RULES');
    }
    // allow_extra 字段保留兼容，新建套餐默认置 1，加菜是否展示由前端基于商家是否有 extra 菜品决定
    const allowExtra = input.allowExtra !== false ? 1 : 0;
    const extraDishIds = normalizeStringArray(input.extraDishIds);
    const isEnabled = input.isEnabled !== false ? 1 : 0;
    getDb()
      .prepare(
        `INSERT INTO packages
           (id, merchant_id, name, description, base_price,
            meal_types_json, rules_json, allow_extra, extra_dish_ids_json,
            is_enabled, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      )
      .run(
        id,
        input.merchantId,
        input.name.trim(),
        input.description?.trim() ?? '',
        input.basePrice,
        JSON.stringify(mealTypes),
        JSON.stringify(rules),
        allowExtra,
        JSON.stringify(extraDishIds),
        isEnabled,
        now,
        now,
      );
    return this.getById(id)!;
  }

  update(id: string, patch: Partial<PackageInput>): PackageRow {
    const existing = this.getById(id);
    if (!existing) throw new Error('NOT_FOUND');
    const fields: string[] = [];
    const values: unknown[] = [];

    if (patch.name !== undefined) {
      if (!patch.name.trim()) throw new Error('INVALID_NAME');
      fields.push('name = ?');
      values.push(patch.name.trim());
    }
    if (patch.description !== undefined) {
      fields.push('description = ?');
      values.push(patch.description.trim());
    }
    if (patch.basePrice !== undefined) {
      if (!(patch.basePrice >= 0)) throw new Error('INVALID_PRICE');
      fields.push('base_price = ?');
      values.push(patch.basePrice);
    }
    if (patch.mealTypes !== undefined) {
      fields.push('meal_types_json = ?');
      values.push(JSON.stringify(normalizeMealTypes(patch.mealTypes)));
    }
    if (patch.rules !== undefined) {
      const rules = normalizeRules(patch.rules);
      if ((rules.meat ?? 0) + (rules.vegetable ?? 0) === 0) {
        throw new Error('EMPTY_RULES');
      }
      fields.push('rules_json = ?');
      values.push(JSON.stringify(rules));
    }
    if (patch.allowExtra !== undefined) {
      fields.push('allow_extra = ?');
      values.push(patch.allowExtra ? 1 : 0);
    }
    if (patch.extraDishIds !== undefined) {
      fields.push('extra_dish_ids_json = ?');
      values.push(JSON.stringify(normalizeStringArray(patch.extraDishIds)));
    }
    if (patch.isEnabled !== undefined) {
      fields.push('is_enabled = ?');
      values.push(patch.isEnabled ? 1 : 0);
    }

    if (fields.length === 0) return existing;

    fields.push('updated_at = ?');
    values.push(nowIso());
    values.push(id);

    getDb()
      .prepare(`UPDATE packages SET ${fields.join(', ')} WHERE id = ?`)
      .run(...(values as never[]));
    return this.getById(id)!;
  }

  setEnabled(id: string, isEnabled: boolean): PackageRow {
    return this.update(id, { isEnabled });
  }

  delete(id: string): void {
    const existing = this.getById(id);
    if (!existing) throw new Error('NOT_FOUND');
    getDb().prepare('DELETE FROM packages WHERE id = ?').run(id);
  }
}

export const packageService = new PackageService();
