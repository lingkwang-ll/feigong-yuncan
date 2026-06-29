/**
 * 菜品数据规范检查（只读，不修改数据库）
 *
 * 检查商家菜品 category / mealTypes / extraPrice 是否符合套餐点餐要求。
 *
 * Usage:
 *   cd server
 *   npx ts-node --transpile-only scripts/check_dish_data_quality.ts
 *   # or
 *   powershell -ExecutionPolicy Bypass -File ./scripts/check_dish_data_quality.ps1
 */
import Database from 'better-sqlite3';
import fs from 'fs';
import path from 'path';

import { suggestDishCategory } from '../src/utils/dish-category-suggest.util';

const VALID_CATEGORIES = new Set([
  'meat',
  'vegetable',
  'extra',
  'staple',
  'soup',
  'drink',
]);

const CHINESE_CATEGORIES: Record<string, string> = {
  荤菜: 'meat',
  荤: 'meat',
  素菜: 'vegetable',
  素: 'vegetable',
  加菜: 'extra',
};

const VALID_MEAL_TYPES = new Set([
  'breakfast',
  'lunch',
  'dinner',
  'overtime',
]);

type IssueCode =
  | 'CATEGORY_EMPTY'
  | 'CATEGORY_INVALID'
  | 'CATEGORY_CHINESE'
  | 'MEAL_TYPES_MISSING'
  | 'MEAL_TYPE_INVALID'
  | 'EXTRA_NO_PRICE'
  | 'EXTRA_PRICE_MISMATCH';

interface DishIssue {
  code: IssueCode;
  message: string;
  suggestion: string;
  blocking: boolean;
}

interface DishRow {
  id: string;
  merchant_id: string;
  name: string;
  category: string | null;
  meal_type: string;
  meal_types_json: string | null;
  extra_price: number | null;
  is_available: number;
  is_sold_out: number;
}

interface MerchantRow {
  id: string;
  name: string;
}

interface MerchantReport {
  merchantId: string;
  merchantName: string;
  total: number;
  meatCount: number;
  vegetableCount: number;
  extraCount: number;
  categoryMissing: number;
  mealTypesMissing: number;
  issues: Array<{
    dishId: string;
    dishName: string;
    currentCategory: string;
    suggestedCategory: string | null;
    mealTypes: string;
    problems: DishIssue[];
  }>;
}

function openReadonlyDb(): Database.Database {
  const dbPath = path.resolve(process.cwd(), 'data', 'feigong-yuncan.db');
  return new Database(dbPath, { readonly: true, fileMustExist: true });
}

function parseMealTypesJson(raw: string | null): string[] {
  if (!raw || raw.trim() === '') return [];
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed.map(String).filter((s) => s.trim().length > 0);
  } catch {
    return [];
  }
}

function normalizeCategory(raw: string | null): string {
  return (raw ?? '').trim();
}

function effectiveMealTypes(row: DishRow): string[] {
  const fromJson = parseMealTypesJson(row.meal_types_json);
  const validFromJson = fromJson.filter((m) => VALID_MEAL_TYPES.has(m));
  if (validFromJson.length > 0) return [...new Set(validFromJson)];
  const mt = (row.meal_type ?? '').trim();
  if (VALID_MEAL_TYPES.has(mt)) return [mt];
  return [];
}

function inspectDish(row: DishRow): DishIssue[] {
  const issues: DishIssue[] = [];
  const cat = normalizeCategory(row.category);
  const extraPrice = typeof row.extra_price === 'number' ? row.extra_price : 0;
  const mealTypes = effectiveMealTypes(row);

  if (!cat) {
    issues.push({
      code: 'CATEGORY_EMPTY',
      message: 'category 为空',
      suggestion: '请在商家端编辑菜品，选择荤菜/素菜/加菜',
      blocking: true,
    });
  } else if (CHINESE_CATEGORIES[cat]) {
    issues.push({
      code: 'CATEGORY_CHINESE',
      message: `category 为中文「${cat}」`,
      suggestion: `建议迁移为英文枚举 ${CHINESE_CATEGORIES[cat]}`,
      blocking: true,
    });
  } else if (!VALID_CATEGORIES.has(cat)) {
    issues.push({
      code: 'CATEGORY_INVALID',
      message: `category 非法值「${cat}」`,
      suggestion:
        '合法值：meat / vegetable / extra / staple / soup / drink',
      blocking: true,
    });
  }

  const rawMealType = (row.meal_type ?? '').trim();
  const jsonRaw = parseMealTypesJson(row.meal_types_json);
  const jsonInvalid = jsonRaw.filter((m) => !VALID_MEAL_TYPES.has(m));

  if (mealTypes.length === 0) {
    issues.push({
      code: 'MEAL_TYPES_MISSING',
      message: `无有效餐段（meal_type=${rawMealType || '<空>'}, meal_types_json=${row.meal_types_json ?? '[]'}）`,
      suggestion:
        '请在商家端为菜品勾选适用餐段（早餐/中餐/晚餐/加班餐）',
      blocking: true,
    });
  }

  if (rawMealType && !VALID_MEAL_TYPES.has(rawMealType) && mealTypes.length === 0) {
    issues.push({
      code: 'MEAL_TYPE_INVALID',
      message: `meal_type 非法值「${rawMealType}」`,
      suggestion: '合法餐段：breakfast / lunch / dinner / overtime',
      blocking: true,
    });
  }

  if (jsonInvalid.length > 0 && mealTypes.length === 0) {
    issues.push({
      code: 'MEAL_TYPE_INVALID',
      message: `meal_types_json 含非法值：${jsonInvalid.join(', ')}`,
      suggestion: '合法餐段：breakfast / lunch / dinner / overtime',
      blocking: true,
    });
  }

  if (cat === 'extra' && extraPrice <= 0) {
    issues.push({
      code: 'EXTRA_NO_PRICE',
      message: 'category=extra 但 extra_price <= 0',
      suggestion: '请填写加菜价格',
      blocking: true,
    });
  }

  if (extraPrice > 0 && cat !== 'extra') {
    issues.push({
      code: 'EXTRA_PRICE_MISMATCH',
      message: `extra_price=${extraPrice} 但 category=${cat || '<空>'}`,
      suggestion: '请确认是否应归为加菜（category=extra）',
      blocking: false,
    });
  }

  return issues;
}

function countCategory(cat: string): 'meat' | 'vegetable' | 'extra' | 'other' {
  if (cat === 'meat') return 'meat';
  if (cat === 'vegetable') return 'vegetable';
  if (cat === 'extra') return 'extra';
  return 'other';
}

function runCheck(): { reports: MerchantReport[]; overallPass: boolean } {
  const db = openReadonlyDb();
  try {
    const merchants = db
      .prepare('SELECT id, name FROM merchants ORDER BY name ASC')
      .all() as MerchantRow[];

    const dishes = db
      .prepare(
        `SELECT id, merchant_id, name, category, meal_type, meal_types_json,
                extra_price, is_available, is_sold_out
         FROM dishes
         ORDER BY merchant_id, name`,
      )
      .all() as DishRow[];

    const byMerchant = new Map<string, DishRow[]>();
    for (const d of dishes) {
      const list = byMerchant.get(d.merchant_id) ?? [];
      list.push(d);
      byMerchant.set(d.merchant_id, list);
    }

    const reports: MerchantReport[] = [];

    for (const m of merchants) {
      const merchantDishes = byMerchant.get(m.id) ?? [];
      const report: MerchantReport = {
        merchantId: m.id,
        merchantName: m.name,
        total: merchantDishes.length,
        meatCount: 0,
        vegetableCount: 0,
        extraCount: 0,
        categoryMissing: 0,
        mealTypesMissing: 0,
        issues: [],
      };

      for (const d of merchantDishes) {
        const cat = normalizeCategory(d.category);
        const mealTypes = effectiveMealTypes(d);

        if (!cat) report.categoryMissing++;
        if (mealTypes.length === 0) report.mealTypesMissing++;

        const bucket = countCategory(cat);
        if (bucket === 'meat') report.meatCount++;
        else if (bucket === 'vegetable') report.vegetableCount++;
        else if (bucket === 'extra') report.extraCount++;

        const problems = inspectDish(d);
        if (problems.length > 0) {
          const suggestion = suggestDishCategory(
            d.name,
            typeof d.extra_price === 'number' ? d.extra_price : 0,
          );
          report.issues.push({
            dishId: d.id,
            dishName: d.name,
            currentCategory: cat || '',
            suggestedCategory: suggestion.suggestedCategory,
            mealTypes: mealTypes.join(',') || d.meal_type,
            problems,
          });
        }
      }

      reports.push(report);
    }

    // 孤儿菜品（商家不存在）
    for (const [merchantId, merchantDishes] of byMerchant) {
      if (merchants.some((m) => m.id === merchantId)) continue;
      const report: MerchantReport = {
        merchantId,
        merchantName: `<未知商家 ${merchantId}>`,
        total: merchantDishes.length,
        meatCount: 0,
        vegetableCount: 0,
        extraCount: 0,
        categoryMissing: 0,
        mealTypesMissing: 0,
        issues: [],
      };
      for (const d of merchantDishes) {
        const cat = normalizeCategory(d.category);
        const mealTypes = effectiveMealTypes(d);
        if (!cat) report.categoryMissing++;
        if (mealTypes.length === 0) report.mealTypesMissing++;
        const problems = inspectDish(d);
        if (problems.length > 0) {
          const suggestion = suggestDishCategory(
            d.name,
            typeof d.extra_price === 'number' ? d.extra_price : 0,
          );
          report.issues.push({
            dishId: d.id,
            dishName: d.name,
            currentCategory: cat || '',
            suggestedCategory: suggestion.suggestedCategory,
            mealTypes: mealTypes.join(',') || d.meal_type,
            problems,
          });
        }
      }
      reports.push(report);
    }

    const hasBlocking = reports.some((r) =>
      r.issues.some((i) => i.problems.some((p) => p.blocking)),
    );

    return { reports, overallPass: !hasBlocking };
  } finally {
    db.close();
  }
}

function printReport(reports: MerchantReport[], overallPass: boolean): void {
  console.log('============================================================');
  console.log(' 非攻云餐 · 菜品数据规范检查（只读）');
  console.log('============================================================');
  console.log('');

  let totalDishes = 0;
  let totalIssues = 0;
  let totalBlocking = 0;
  let merchantsWithIssues = 0;

  for (const r of reports) {
    totalDishes += r.total;
    const issueCount = r.issues.length;
    if (issueCount > 0) merchantsWithIssues++;
    for (const item of r.issues) {
      totalIssues += item.problems.length;
      totalBlocking += item.problems.filter((p) => p.blocking).length;
    }

    console.log('------------------------------------------------------------');
    console.log(`商家：${r.merchantName} (${r.merchantId})`);
    console.log(`  菜品总数：${r.total}`);
    console.log(`  荤菜(meat)：${r.meatCount}`);
    console.log(`  素菜(vegetable)：${r.vegetableCount}`);
    console.log(`  加菜(extra)：${r.extraCount}`);
    console.log(`  category 缺失：${r.categoryMissing}`);
    console.log(`  mealTypes 缺失：${r.mealTypesMissing}`);

    if (r.issues.length === 0) {
      console.log('  异常菜品：无');
    } else {
      console.log(`  异常菜品：${r.issues.length} 道`);
      for (const item of r.issues) {
        console.log(`    - [${item.dishId}] ${item.dishName}`);
        for (const p of item.problems) {
          const tag = p.blocking ? '阻断' : '警告';
          console.log(`        [${tag}] ${p.message}`);
          console.log(`              建议：${p.suggestion}`);
        }
      }
    }
    console.log('');
  }

  console.log('============================================================');
  console.log(' 汇总');
  console.log('============================================================');
  console.log(`  商家数：${reports.length}`);
  console.log(`  菜品总数：${totalDishes}`);
  console.log(`  有问题商家数：${merchantsWithIssues}`);
  console.log(`  异常条目数：${totalIssues}（阻断 ${totalBlocking}，警告 ${totalIssues - totalBlocking}）`);
  console.log('');

  const blockingMerchants = reports.filter((r) =>
    r.issues.some((i) => i.problems.some((p) => p.blocking)),
  );

  if (blockingMerchants.length > 0) {
    console.log('  会影响套餐点餐的阻断数据：是');
    console.log('  阻断商家：');
    for (const r of blockingMerchants) {
      const blockingDishes = r.issues.filter((i) =>
        i.problems.some((p) => p.blocking),
      ).length;
      console.log(`    - ${r.merchantName}（${blockingDishes} 道菜品）`);
    }
  } else {
    console.log('  会影响套餐点餐的阻断数据：否');
  }

  console.log('');
  console.log(
    `  总体是否通过：${overallPass ? '通过' : '未通过（存在阻断项）'}`,
  );
  console.log('============================================================');
}

function writeMarkdownReport(
  reports: MerchantReport[],
  overallPass: boolean,
): string {
  const now = new Date().toISOString();
  const lines: string[] = [
    '# 菜品数据质量检查报告',
    '',
    `生成时间：${now}`,
    '',
    `**总体是否通过：** ${overallPass ? '通过' : '未通过（存在阻断项）'}`,
    '',
    '## 异常明细',
    '',
    '| 商家 | 菜品名称 | 当前 category | 建议 category | mealTypes | 问题原因 | 修复建议 |',
    '| --- | --- | --- | --- | --- | --- | --- |',
  ];

  for (const r of reports) {
    for (const item of r.issues) {
      const reasons = item.problems.map((p) => p.message).join('；');
      const fixes = item.problems.map((p) => p.suggestion).join('；');
      const esc = (s: string) => s.replace(/\|/g, '\\|');
      lines.push(
        `| ${esc(r.merchantName)} | ${esc(item.dishName)} | ${esc(item.currentCategory || '空')} | ${esc(item.suggestedCategory || '—')} | ${esc(item.mealTypes)} | ${esc(reasons)} | ${esc(fixes)} |`,
      );
    }
  }

  lines.push('');
  lines.push('## 商家统计');
  lines.push('');
  lines.push('| 商家 | 菜品总数 | 荤菜 | 素菜 | 加菜 | category缺失 | mealTypes缺失 |');
  lines.push('| --- | --- | --- | --- | --- | --- | --- |');
  for (const r of reports) {
    lines.push(
      `| ${r.merchantName} | ${r.total} | ${r.meatCount} | ${r.vegetableCount} | ${r.extraCount} | ${r.categoryMissing} | ${r.mealTypesMissing} |`,
    );
  }

  return lines.join('\n');
}

function saveMarkdownReport(reports: MerchantReport[], overallPass: boolean): void {
  const reportDir = path.resolve(process.cwd(), 'reports');
  fs.mkdirSync(reportDir, { recursive: true });
  const reportPath = path.join(reportDir, 'dish-data-quality-report.md');
  const content = writeMarkdownReport(reports, overallPass);
  fs.writeFileSync(reportPath, content, 'utf8');
  console.log(`Markdown 报告已写入：${reportPath}`);
}

function main(): void {
  try {
    const { reports, overallPass } = runCheck();
    printReport(reports, overallPass);
    saveMarkdownReport(reports, overallPass);
    process.exitCode = overallPass ? 0 : 1;
  } catch (e) {
    console.error('[ERROR] 检查失败：', e);
    process.exitCode = 2;
  }
}

main();
