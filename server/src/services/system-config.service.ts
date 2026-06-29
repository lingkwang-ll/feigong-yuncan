import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { ALL_MEAL_TYPES, AppSettingsDto, DEFAULT_ONLINE_PAYMENT_ENABLED, MealType, SystemConfigDto } from '../models/types';

const MEAL_KEY = 'meal_deadlines';
const APP_KEY = 'app_settings';

const DEFAULT_MEAL: Record<MealType, string> = {
  breakfast: '07:30',
  lunch: '09:30',
  dinner: '15:00',
  overtime: '17:30',
};

export const DEFAULT_APP_SETTINGS: AppSettingsDto = {
  allowCancelOrder: true,
  enableReview: true,
  enableMerchantAutoRefresh: false,
  requirePaymentScreenshot: true,
  allowMerchantReject: true,
  showSoldOutDishes: true,
  labelPrintWidthMm: 50,
  labelPrintFontSizePt: 12,
  companyPayDepartments: ['行政部', '生产部'],
  onlinePaymentEnabled: { ...DEFAULT_ONLINE_PAYMENT_ENABLED },
};

function readJson(key: string): Record<string, unknown> | null {
  const row = getDb()
    .prepare<[string], { value_json: string }>(
      'SELECT value_json FROM system_config WHERE key = ?',
    )
    .get(key);
  if (!row) return null;
  try {
    return JSON.parse(row.value_json) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function writeJson(key: string, value: unknown): string {
  const now = nowIso();
  getDb()
    .prepare(
      `INSERT INTO system_config (key, value_json, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json, updated_at = excluded.updated_at`,
    )
    .run(key, JSON.stringify(value), now);
  return now;
}

export class SystemConfigService {
  getMealDeadlines(): Pick<SystemConfigDto, 'mealDeadlines' | 'updatedAt'> {
    const parsed = readJson(MEAL_KEY);
    const mealDeadlines = { ...DEFAULT_MEAL };
    if (parsed) {
      for (const t of ALL_MEAL_TYPES) {
        if (typeof parsed[t] === 'string') mealDeadlines[t] = parsed[t];
      }
    }
    const row = getDb()
      .prepare<[string], { updated_at: string }>(
        'SELECT updated_at FROM system_config WHERE key = ?',
      )
      .get(MEAL_KEY);
    return { mealDeadlines, updatedAt: row?.updated_at ?? nowIso() };
  }

  updateMealDeadlines(deadlines: Partial<Record<MealType, string>>) {
    const current = this.getMealDeadlines();
    const next = { ...current.mealDeadlines, ...deadlines };
    const updatedAt = writeJson(MEAL_KEY, next);
    return { mealDeadlines: next, updatedAt };
  }

  getAppSettings(): AppSettingsDto {
    const parsed = readJson(APP_KEY);
    if (!parsed) return { ...DEFAULT_APP_SETTINGS };
    const rawOnline = parsed.onlinePaymentEnabled as Record<string, unknown> | undefined;
    const onlinePaymentEnabled = {
      ...DEFAULT_ONLINE_PAYMENT_ENABLED,
      ...(rawOnline && typeof rawOnline === 'object' ? rawOnline : {}),
    } as AppSettingsDto['onlinePaymentEnabled'];
    const merged = {
      ...DEFAULT_APP_SETTINGS,
      ...parsed,
      onlinePaymentEnabled,
    } as AppSettingsDto;
    if (!Array.isArray(merged.companyPayDepartments)) {
      merged.companyPayDepartments = DEFAULT_APP_SETTINGS.companyPayDepartments;
    }
    return merged;
  }

  updateAppSettings(patch: Partial<AppSettingsDto>): AppSettingsDto {
    const next = { ...this.getAppSettings(), ...patch };
    writeJson(APP_KEY, next);
    return next;
  }

  getFullConfig(): SystemConfigDto {
    const meal = this.getMealDeadlines();
    return {
      mealDeadlines: meal.mealDeadlines,
      appSettings: this.getAppSettings(),
      updatedAt: meal.updatedAt,
    };
  }

  updateFullConfig(input: {
    mealDeadlines?: Partial<Record<MealType, string>>;
    appSettings?: Partial<AppSettingsDto>;
  }): SystemConfigDto {
    if (input.mealDeadlines) this.updateMealDeadlines(input.mealDeadlines);
    if (input.appSettings) this.updateAppSettings(input.appSettings);
    return this.getFullConfig();
  }
}

export const systemConfigService = new SystemConfigService();
