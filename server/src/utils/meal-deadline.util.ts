import { getDb } from '../db/database';
import { MealType } from '../models/types';
import { systemConfigService } from '../services/system-config.service';
import {
  isMealEnabledInOpeningHours,
  isOrderWindowClosed,
  parseMealOpeningHoursJson,
  resolveEndTimeFromOpeningHours,
  resolveMealOrderWindow,
} from './meal-opening-hours.util';

function parseHm(value: string): number | null {
  const m = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h < 0 || h > 23 || min < 0 || min > 59) return null;
  return h * 60 + min;
}

function loadMerchantHours(merchantId: string): {
  opening: ReturnType<typeof parseMealOpeningHoursJson>;
  deadlinesJson: string | null;
} | null {
  try {
    const row = getDb()
      .prepare<
        [string],
        {
          meal_opening_hours_json: string | null;
          meal_order_deadlines_json: string | null;
        }
      >(
        'SELECT meal_opening_hours_json, meal_order_deadlines_json FROM merchants WHERE id = ?',
      )
      .get(merchantId);
    if (!row) return null;
    return {
      opening: parseMealOpeningHoursJson(row.meal_opening_hours_json),
      deadlinesJson: row.meal_order_deadlines_json,
    };
  } catch {
    return null;
  }
}

/**
 * 取某商家在指定餐段的订餐截止时间（展示用 HH:mm）。
 */
export function resolveMerchantDeadline(
  mealType: MealType,
  merchantId?: string | null,
): string | undefined {
  const global = systemConfigService.getMealDeadlines().mealDeadlines;
  if (!merchantId) return global[mealType];

  const loaded = loadMerchantHours(merchantId);
  if (loaded) {
    const fromHours = resolveEndTimeFromOpeningHours(mealType, loaded.opening);
    if (fromHours) return fromHours;

    if (loaded.deadlinesJson) {
      try {
        const parsed = JSON.parse(loaded.deadlinesJson) as Partial<
          Record<MealType, string>
        >;
        const v = parsed?.[mealType];
        if (typeof v === 'string' && v.trim().length > 0) {
          return v.trim();
        }
      } catch {
        // ignore
      }
    }
  }
  return global[mealType];
}

/** 餐段是否未开放（营业时间里 enabled=false） */
export function isMealNotOpen(
  mealType: MealType,
  merchantId?: string | null,
): boolean {
  if (!merchantId) return false;
  const loaded = loadMerchantHours(merchantId);
  if (!loaded) return false;
  const entry = loaded.opening[mealType];
  if (!entry) return false;
  return !isMealEnabledInOpeningHours(mealType, loaded.opening);
}

/**
 * 当前时间是否已超过订餐截止 / 不在可下单窗口。
 * 跨天营业（如加班餐 23:00-03:00）截止为次日 end 时刻。
 */
export function isMealDeadlinePassed(
  mealType: MealType,
  merchantId?: string | null,
  now: Date = new Date(),
): boolean {
  if (isMealNotOpen(mealType, merchantId)) return true;

  const currentMin = now.getHours() * 60 + now.getMinutes();

  if (merchantId) {
    const loaded = loadMerchantHours(merchantId);
    if (loaded) {
      const window = resolveMealOrderWindow(mealType, loaded.opening);
      if (window) {
        return isOrderWindowClosed(window, currentMin);
      }
    }
  }

  const deadlineStr = resolveMerchantDeadline(mealType, merchantId);
  if (!deadlineStr) return false;
  const deadlineMin = parseHm(deadlineStr);
  if (deadlineMin == null) return false;
  return currentMin > deadlineMin;
}

export function assertMealTypesOrderable(
  mealTypes: MealType[],
  merchantId?: string | null,
  now: Date = new Date(),
): void {
  for (const mealType of mealTypes) {
    if (isMealDeadlinePassed(mealType, merchantId, now)) {
      throw new Error(`MEAL_DEADLINE_PASSED:${mealType}`);
    }
  }
}
