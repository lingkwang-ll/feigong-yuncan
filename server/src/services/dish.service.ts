import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { normalizeDishCategory, nowIso } from '../models/mappers';
import { DishCategory, DishRow, DISH_LISTING_MEAL_TYPES, MealType } from '../models/types';
import { systemConfigService } from './system-config.service';

function sanitizeDishMealTypes(arr?: MealType[]): MealType[] {
  return (arr ?? []).filter((m) => DISH_LISTING_MEAL_TYPES.includes(m));
}

function assertDishListingMealType(mealType: MealType): void {
  if (!DISH_LISTING_MEAL_TYPES.includes(mealType)) {
    throw new Error('DISH_OVERTIME_NOT_ALLOWED');
  }
}

export class DishService {
  listByMerchant(
    merchantId: string,
    mealType?: MealType,
    opts?: { hideSoldOut?: boolean },
  ): DishRow[] {
    const hideSoldOut =
      opts?.hideSoldOut ??
      !systemConfigService.getAppSettings().showSoldOutDishes;
    const db = getDb();
    const soldOutClause = hideSoldOut ? ' AND is_sold_out = 0' : '';
    if (mealType) {
      return db
        .prepare<[string, string, string], DishRow>(
          `SELECT * FROM dishes
            WHERE merchant_id = ?
              AND (meal_type = ?
                OR meal_types_json = '[]'
                OR instr(meal_types_json, ?) > 0)${soldOutClause}
            ORDER BY sort_order ASC, created_at ASC`,
        )
        .all(merchantId, mealType, mealType);
    }
    return db
      .prepare<[string], DishRow>(
        `SELECT * FROM dishes WHERE merchant_id = ?${soldOutClause} ORDER BY meal_type ASC, sort_order ASC, created_at ASC`,
      )
      .all(merchantId);
  }

  getById(id: string): DishRow | undefined {
    return getDb()
      .prepare<[string], DishRow>('SELECT * FROM dishes WHERE id = ?')
      .get(id);
  }

  create(input: {
    id?: string;
    merchantId: string;
    name: string;
    image?: string;
    description?: string;
    price: number;
    mealType: MealType;
    tags?: string[];
    isAvailable?: boolean;
    sortOrder?: number;
    // 套餐体系扩展（可选）：未传时不影响旧调用
    category?: DishCategory | string;
    extraPrice?: number;
    mealTypes?: MealType[];
  }): DishRow {
    assertDishListingMealType(input.mealType);
    const db = getDb();
    const id = input.id ?? `d_${nanoid(8)}`;
    const now = nowIso();
    const category = normalizeDishCategory(input.category);
    // 加菜分类必须填价格
    if (category === 'extra') {
      if (input.extraPrice == null || !(input.extraPrice >= 0)) {
        throw new Error('EXTRA_PRICE_REQUIRED');
      }
    }
    const extraPrice =
      typeof input.extraPrice === 'number' && input.extraPrice >= 0
        ? input.extraPrice
        : 0;
    const mealTypes = sanitizeDishMealTypes(input.mealTypes);
    db.prepare(
      `INSERT INTO dishes
         (id, merchant_id, name, image_url, description, price, meal_type,
          tags_json, is_available, is_sold_out, sort_order,
          category, extra_price, meal_types_json,
          created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      id,
      input.merchantId,
      input.name,
      input.image ?? 'dish',
      input.description ?? '',
      input.price,
      input.mealType,
      JSON.stringify(input.tags ?? []),
      input.isAvailable === false ? 0 : 1,
      0,
      input.sortOrder ?? 0,
      category,
      extraPrice,
      JSON.stringify(mealTypes),
      now,
      now,
    );
    return this.getById(id)!;
  }

  update(
    id: string,
    patch: {
      name?: string;
      image?: string;
      description?: string;
      price?: number;
      mealType?: MealType;
      tags?: string[];
      isAvailable?: boolean;
      isSoldOut?: boolean;
      sortOrder?: number;
      category?: DishCategory | string;
      extraPrice?: number;
      mealTypes?: MealType[];
    },
  ): DishRow {
    const existing = this.getById(id);
    if (!existing) throw new Error('NOT_FOUND');
    const db = getDb();
    const fields: string[] = [];
    const values: unknown[] = [];

    if (patch.name !== undefined) {
      fields.push('name = ?');
      values.push(patch.name);
    }
    if (patch.image !== undefined) {
      fields.push('image_url = ?');
      values.push(patch.image);
    }
    if (patch.description !== undefined) {
      fields.push('description = ?');
      values.push(patch.description);
    }
    if (patch.price !== undefined) {
      fields.push('price = ?');
      values.push(patch.price);
    }
    if (patch.mealType !== undefined) {
      assertDishListingMealType(patch.mealType);
      fields.push('meal_type = ?');
      values.push(patch.mealType);
    }
    if (patch.tags !== undefined) {
      fields.push('tags_json = ?');
      values.push(JSON.stringify(patch.tags));
    }
    if (patch.isAvailable !== undefined) {
      fields.push('is_available = ?');
      values.push(patch.isAvailable ? 1 : 0);
    }
    if (patch.isSoldOut !== undefined) {
      fields.push('is_sold_out = ?');
      values.push(patch.isSoldOut ? 1 : 0);
    }
    if (patch.sortOrder !== undefined) {
      fields.push('sort_order = ?');
      values.push(patch.sortOrder);
    }
    if (patch.category !== undefined) {
      const cat = normalizeDishCategory(patch.category);
      // 切换到 extra 时，必须传或已存在 extra_price > 0
      if (cat === 'extra') {
        const ep =
          patch.extraPrice !== undefined ? patch.extraPrice : existing.extra_price;
        if (!(ep > 0)) throw new Error('EXTRA_PRICE_REQUIRED');
      }
      fields.push('category = ?');
      values.push(cat);
    }
    if (patch.extraPrice !== undefined) {
      if (!(patch.extraPrice >= 0)) throw new Error('INVALID_EXTRA_PRICE');
      fields.push('extra_price = ?');
      values.push(patch.extraPrice);
    }
    if (patch.mealTypes !== undefined) {
      const mts = sanitizeDishMealTypes(patch.mealTypes);
      fields.push('meal_types_json = ?');
      values.push(JSON.stringify(mts));
    }

    if (fields.length === 0) return existing;

    fields.push('updated_at = ?');
    values.push(nowIso());
    values.push(id);

    db.prepare(`UPDATE dishes SET ${fields.join(', ')} WHERE id = ?`).run(
      ...(values as never[]),
    );
    return this.getById(id)!;
  }

  setAvailable(id: string, isAvailable: boolean): DishRow {
    return this.update(id, { isAvailable });
  }

  setSoldOut(id: string, isSoldOut: boolean): DishRow {
    return this.update(id, { isSoldOut });
  }

  setSortOrder(id: string, sortOrder: number): DishRow {
    const existing = this.getById(id);
    if (!existing) throw new Error('NOT_FOUND');
    getDb()
      .prepare('UPDATE dishes SET sort_order = ?, updated_at = ? WHERE id = ?')
      .run(sortOrder, nowIso(), id);
    return this.getById(id)!;
  }

  delete(id: string): void {
    const existing = this.getById(id);
    if (!existing) throw new Error('NOT_FOUND');
    getDb().prepare('DELETE FROM dishes WHERE id = ?').run(id);
  }
}

export const dishService = new DishService();
