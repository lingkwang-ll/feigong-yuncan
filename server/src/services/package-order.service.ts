import { getDb } from '../db/database';
import {
  merchantToDto,
  parseJsonArray,
  parsePackageRules,
} from '../models/mappers';
import {
  DishRow,
  MealType,
  MerchantRow,
  PackageRow,
} from '../models/types';

const ALLOWED_MEALS: MealType[] = ['breakfast', 'lunch', 'dinner', 'overtime'];

export interface PackageOrderPackageItem {
  id: string;
  name: string;
  basePrice: number;
  meatCount: number;
  vegetableCount: number;
  mealTypes: MealType[];
  isEnabled: boolean;
  description: string;
}

export interface PackageOrderMeatVegDish {
  id: string;
  name: string;
  imageUrl: string;
  description: string;
}

export interface PackageOrderExtraDish {
  id: string;
  name: string;
  imageUrl: string;
  extraPrice: number;
}

export interface PackageOrderDataDto {
  merchant: ReturnType<typeof merchantToDto>;
  mealType: MealType;
  packages: PackageOrderPackageItem[];
  dishes: {
    meat: PackageOrderMeatVegDish[];
    vegetable: PackageOrderMeatVegDish[];
    extra: PackageOrderExtraDish[];
  };
}

function dishMatchesMeal(row: DishRow, mealType: MealType): boolean {
  const mealTypes = parseJsonArray<MealType>(row.meal_types_json).filter((m) =>
    ALLOWED_MEALS.includes(m),
  );
  if (mealTypes.length > 0) return mealTypes.includes(mealType);
  return row.meal_type === mealType;
}

function toMeatVegDish(row: DishRow): PackageOrderMeatVegDish {
  return {
    id: row.id,
    name: row.name,
    imageUrl: row.image_url ?? '',
    description: row.description ?? '',
  };
}

function toExtraDish(row: DishRow): PackageOrderExtraDish {
  return {
    id: row.id,
    name: row.name,
    imageUrl: row.image_url ?? '',
    extraPrice: typeof row.extra_price === 'number' ? row.extra_price : 0,
  };
}

function toPackageItem(row: PackageRow): PackageOrderPackageItem {
  const rules = parsePackageRules(row.rules_json);
  return {
    id: row.id,
    name: row.name,
    basePrice: typeof row.base_price === 'number' ? row.base_price : 0,
    meatCount: rules.meat ?? 0,
    vegetableCount: rules.vegetable ?? 0,
    mealTypes: parseJsonArray<MealType>(row.meal_types_json).filter((m) =>
      ALLOWED_MEALS.includes(m),
    ),
    isEnabled: !!row.is_enabled,
    description: row.description ?? '',
  };
}

export class PackageOrderService {
  getPackageOrderData(
    merchantId: string,
    mealType: MealType,
  ): PackageOrderDataDto | null {
    const db = getDb();
    const merchant = db
      .prepare<[string], MerchantRow>('SELECT * FROM merchants WHERE id = ?')
      .get(merchantId);
    if (!merchant) return null;

    const packageRows = db
      .prepare<[string, string], PackageRow>(
        `SELECT * FROM packages
          WHERE merchant_id = ?
            AND is_enabled = 1
            AND (meal_types_json = '[]' OR instr(meal_types_json, ?) > 0)
          ORDER BY base_price ASC, created_at DESC`,
      )
      .all(merchantId, mealType);

    const dishRows = db
      .prepare<[string], DishRow>(
        `SELECT * FROM dishes
          WHERE merchant_id = ?
            AND is_available = 1
            AND is_sold_out = 0
            AND category IN ('meat', 'vegetable', 'extra')
          ORDER BY sort_order ASC, created_at ASC`,
      )
      .all(merchantId);

    const meat: PackageOrderMeatVegDish[] = [];
    const vegetable: PackageOrderMeatVegDish[] = [];
    const extra: PackageOrderExtraDish[] = [];

    for (const row of dishRows) {
      if (!dishMatchesMeal(row, mealType)) continue;
      const cat = row.category;
      if (cat === 'meat') {
        meat.push(toMeatVegDish(row));
      } else if (cat === 'vegetable') {
        vegetable.push(toMeatVegDish(row));
      } else if (cat === 'extra') {
        const price =
          typeof row.extra_price === 'number' ? row.extra_price : 0;
        if (price > 0) extra.push(toExtraDish(row));
      }
    }

    return {
      merchant: merchantToDto(merchant),
      mealType,
      packages: packageRows.map(toPackageItem),
      dishes: { meat, vegetable, extra },
    };
  }
}

export const packageOrderService = new PackageOrderService();
