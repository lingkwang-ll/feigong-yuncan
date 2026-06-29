import { ALL_MEAL_TYPES, MealType } from '../models/types';

export interface MealOpeningHoursEntry {
  enabled?: boolean;
  start?: string;
  end?: string;
  hours?: string;
}

function parseHm(value: string): number | null {
  const m = /^(\d{1,2}):(\d{2})$/.exec(value.trim());
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h < 0 || h > 23 || min < 0 || min > 59) return null;
  return h * 60 + min;
}

export interface MealOrderWindow {
  startMin: number;
  endMin: number;
  crossDay: boolean;
}

/** 营业时段是否跨天（start > end，如 23:00-03:00） */
export function isCrossDayEntry(entry: MealOpeningHoursEntry): boolean {
  const norm = normalizeOpeningHoursEntry(entry);
  const startMin = parseHm(norm.start ?? '');
  const endMin = parseHm(norm.end ?? '');
  if (startMin == null || endMin == null) return false;
  return endMin <= startMin;
}

/** 从营业时间解析订餐窗口；无有效 start/end 返回 null */
export function resolveMealOrderWindow(
  mealType: MealType,
  opening: Record<string, MealOpeningHoursEntry>,
): MealOrderWindow | null {
  const entry = opening[mealType];
  if (!entry) return null;
  const norm = normalizeOpeningHoursEntry(entry);
  if (!norm.enabled) return null;
  const startMin = parseHm(norm.start ?? '');
  const endMin = parseHm(norm.end ?? '');
  if (startMin == null || endMin == null) return null;
  return {
    startMin,
    endMin,
    crossDay: endMin <= startMin,
  };
}

/**
 * 当前时刻是否已过订餐截止 / 不在可下单窗口内。
 * - 同日：currentMin > endMin 为已过；
 * - 跨天：23:00-03:00 表示截止次日 endMin；仅 start 之后或 end 之前可下单。
 */
export function isOrderWindowClosed(
  window: MealOrderWindow,
  currentMin: number,
): boolean {
  if (window.crossDay) {
    if (currentMin >= window.startMin) return false;
    if (currentMin <= window.endMin) return false;
    return true;
  }
  return currentMin > window.endMin;
}

function parseHoursRange(hours: string): { start?: string; end?: string } {
  const m = /^(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})$/.exec(hours.trim());
  if (!m) return {};
  return { start: m[1], end: m[2] };
}

/** 归一化单餐段营业时间：补齐 start/end，并同步 hours 字符串 */
export function normalizeOpeningHoursEntry(
  raw: MealOpeningHoursEntry,
): MealOpeningHoursEntry {
  let start = (raw.start ?? '').trim();
  let end = (raw.end ?? '').trim();
  if ((!start || !end) && raw.hours) {
    const parsed = parseHoursRange(raw.hours);
    if (!start) start = parsed.start ?? '';
    if (!end) end = parsed.end ?? '';
  }
  const hours =
    start && end ? `${start}-${end}` : (raw.hours ?? '').trim();
  return {
    enabled: raw.enabled ?? true,
    start,
    end,
    hours,
  };
}

export function normalizeMealOpeningHours(
  raw: Record<string, MealOpeningHoursEntry>,
): Record<string, MealOpeningHoursEntry> {
  const out: Record<string, MealOpeningHoursEntry> = {};
  for (const [key, val] of Object.entries(raw)) {
    if (!val || typeof val !== 'object') continue;
    out[key] = normalizeOpeningHoursEntry(val);
  }
  return out;
}

/** 从营业时间结束时间生成 mealOrderDeadlines（仅 enabled 且 end 合法） */
export function deriveMealOrderDeadlinesFromOpeningHours(
  opening: Record<string, MealOpeningHoursEntry>,
): Partial<Record<MealType, string>> {
  const out: Partial<Record<MealType, string>> = {};
  for (const mt of ALL_MEAL_TYPES) {
    const entry = opening[mt];
    if (!entry || !entry.enabled) continue;
    const norm = normalizeOpeningHoursEntry(entry);
    const end = norm.end?.trim();
    if (end && parseHm(end) != null) {
      out[mt] = end;
    }
  }
  return out;
}

/**
 * 校验营业时间。
 * - 早餐/中餐/晚餐：结束须晚于开始（不支持跨天）；
 * - 加班餐：允许跨天（start > end，如 23:00-03:00）；
 * - start === end 一律非法。
 */
export function validateMealOpeningHours(
  raw: Record<string, MealOpeningHoursEntry>,
): void {
  const opening = normalizeMealOpeningHours(raw);
  for (const [key, entry] of Object.entries(opening)) {
    if (!entry.enabled) continue;
    const start = entry.start?.trim() ?? '';
    const end = entry.end?.trim() ?? '';
    if (!start || !end) continue;
    const startMin = parseHm(start);
    const endMin = parseHm(end);
    if (startMin == null || endMin == null) {
      throw new Error('INVALID_BUSINESS_HOURS');
    }
    if (startMin === endMin) {
      throw new Error('INVALID_BUSINESS_HOURS');
    }
    const allowCrossDay = key === 'overtime';
    if (!allowCrossDay && endMin <= startMin) {
      throw new Error('BUSINESS_HOURS_END_BEFORE_START');
    }
  }
}

/** 从 meal_opening_hours_json 字符串解析 */
export function parseMealOpeningHoursJson(
  raw: string | null | undefined,
): Record<string, MealOpeningHoursEntry> {
  if (!raw) return {};
  try {
    const parsed = JSON.parse(raw) as Record<string, MealOpeningHoursEntry>;
    if (!parsed || typeof parsed !== 'object') return {};
    return normalizeMealOpeningHours(parsed);
  } catch {
    return {};
  }
}

/** 取某餐段营业结束时间（HH:mm）；未启用或无配置返回 undefined */
export function resolveEndTimeFromOpeningHours(
  mealType: MealType,
  opening: Record<string, MealOpeningHoursEntry>,
): string | undefined {
  const entry = opening[mealType];
  if (!entry) return undefined;
  const norm = normalizeOpeningHoursEntry(entry);
  if (!norm.enabled) return undefined;
  const end = norm.end?.trim();
  if (!end || parseHm(end) == null) return undefined;
  return end;
}

/** 餐段是否对外营业（enabled） */
export function isMealEnabledInOpeningHours(
  mealType: MealType,
  opening: Record<string, MealOpeningHoursEntry>,
): boolean {
  const entry = opening[mealType];
  if (!entry) return true; // 旧数据无配置时默认可用
  return normalizeOpeningHoursEntry(entry).enabled ?? true;
}
