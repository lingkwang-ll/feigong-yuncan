import { MealSummaryDto, MealLabelGroupDto } from './meal-summary.service';

function escapeCsv(v: string): string {
  if (v.includes(',') || v.includes('"') || v.includes('\n')) {
    return `"${v.replace(/"/g, '""')}"`;
  }
  return v;
}

function escapeHtml(raw: string): string {
  return raw
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export type LabelFontScale = 'small' | 'standard' | 'large';

export interface LabelPrintOptions {
  widthMm?: number;
  heightMm?: number;
  fontScale?: LabelFontScale;
  showPackage?: boolean;
  showMeat?: boolean;
  showVegetable?: boolean;
  showExtra?: boolean;
  showRemark?: boolean;
}

const FONT_SCALE_FACTOR: Record<LabelFontScale, number> = {
  small: 0.85,
  standard: 1.0,
  large: 1.15,
};

function dishJoin(
  items: { name: string; quantity: number }[],
  compact: boolean,
): string {
  return items
    .map((d) => {
      if (d.quantity <= 1) return d.name;
      return compact ? `${d.name}x${d.quantity}` : `${d.name} x${d.quantity}`;
    })
    .join('、');
}

export function formatLabelPrintLines(
  g: MealLabelGroupDto,
  opts: LabelPrintOptions & { widthMm: number; heightMm: number },
): string[] {
  const compact = opts.widthMm <= 45 || opts.heightMm <= 35;
  const lines: string[] = [];

  if (compact) {
    lines.push(`${g.labelCode} ${g.employeeName}`);
  } else {
    lines.push(g.labelCode);
    lines.push(g.employeeName);
  }

  if (opts.showPackage !== false && g.packages.length > 0) {
    const text = dishJoin(g.packages, compact);
    lines.push(compact ? text : `套餐：${text}`);
  }
  if (opts.showMeat !== false && g.meats.length > 0) {
    const text = dishJoin(g.meats, compact);
    lines.push(compact ? `荤：${text}` : `荤菜：${text}`);
  }
  if (opts.showVegetable !== false && g.vegetables.length > 0) {
    const text = dishJoin(g.vegetables, compact);
    lines.push(compact ? `素：${text}` : `素菜：${text}`);
  }
  if (opts.showExtra !== false && g.extras.length > 0) {
    const text = dishJoin(g.extras, compact);
    const suffix = g.extrasFollowOrder ? '（随单）' : '';
    lines.push(compact ? `加：${text}${suffix}` : `加菜：${text}${suffix}`);
  }
  if (opts.showRemark !== false && (g.remark ?? '').trim()) {
    lines.push(`备注：${g.remark.trim()}`);
  }

  return lines;
}

function labelPrintCss(opts: Required<
  Pick<LabelPrintOptions, 'widthMm' | 'heightMm' | 'fontScale'>
>): string {
  const { widthMm: w, heightMm: h, fontScale } = opts;
  const scale = FONT_SCALE_FACTOR[fontScale];
  const compact = w <= 45 || h <= 35;
  const codePx = ((compact ? 10 : 12) * scale).toFixed(1);
  const namePx = ((compact ? 10 : 13) * scale).toFixed(1);
  const linePx = ((compact ? 8 : 10) * scale).toFixed(1);
  const pad = compact ? '2mm' : '3mm';

  return `
@page { size: ${w}mm ${h}mm; margin: 0; }
html, body { margin: 0; padding: 0; background: #fff; }
.label-page {
  width: ${w}mm; height: ${h}mm; box-sizing: border-box; padding: ${pad};
  page-break-after: always; break-after: page; overflow: hidden; background: #fff;
  font-family: "Microsoft YaHei", "PingFang SC", sans-serif; color: #111;
}
.label-page:last-child { page-break-after: auto; break-after: auto; }
.label-header { display: flex; align-items: baseline; gap: 2mm; margin-bottom: 1mm; }
.label-code { font-size: ${codePx}px; font-weight: 700; color: #FF7A00; flex-shrink: 0; }
.label-name { font-size: ${namePx}px; font-weight: 700; line-height: 1.2;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.label-line { font-size: ${linePx}px; line-height: 1.25;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
@media print { html, body { margin: 0; padding: 0; background: #fff; } }
`;
}

function labelPageHtml(
  g: MealLabelGroupDto,
  opts: LabelPrintOptions & { widthMm: number; heightMm: number },
): string {
  const lines = formatLabelPrintLines(g, opts);
  const compact = opts.widthMm <= 45 || opts.heightMm <= 35;
  const parts: string[] = ['<div class="label-page">'];

  if (compact) {
    const header = lines[0] ?? g.labelCode;
    const rest = lines.slice(1);
    const headerParts = header.split(' ');
    const code = headerParts[0] ?? g.labelCode;
    const name = headerParts.slice(1).join(' ') || g.employeeName;
    parts.push('<div class="label-header">');
    parts.push(`<span class="label-code">${escapeHtml(code)}</span>`);
    parts.push(`<span class="label-name">${escapeHtml(name)}</span>`);
    parts.push('</div>');
    for (const line of rest) {
      parts.push(`<div class="label-line">${escapeHtml(line)}</div>`);
    }
  } else {
    if (lines[0]) parts.push(`<div class="label-code">${escapeHtml(lines[0])}</div>`);
    if (lines[1]) parts.push(`<div class="label-name">${escapeHtml(lines[1])}</div>`);
    for (const line of lines.slice(2)) {
      parts.push(`<div class="label-line">${escapeHtml(line)}</div>`);
    }
  }

  parts.push('</div>');
  return parts.join('');
}

export function mealSummaryToCsv(summary: MealSummaryDto): string {
  const lines: string[] = [];
  lines.push('section,key,value');
  lines.push(`summary,date,${summary.date}`);
  lines.push(`summary,meal,${summary.mealLabel}`);
  lines.push(`summary,merchant,${summary.merchantName}`);
  lines.push(`summary,totalPeople,${summary.totalPeople}`);
  lines.push(`summary,totalPortions,${summary.totalPortions}`);
  lines.push(`summary,totalAmount,${summary.totalAmount}`);
  lines.push(`summary,collector,${escapeCsv(summary.collectorName)}`);
  lines.push(`summary,phone,${summary.collectorPhone}`);
  lines.push(`summary,address,${escapeCsv(summary.collectorAddress)}`);
  lines.push(`summary,status,${summary.batchStatus ?? summary.phase}`);
  lines.push('');
  lines.push('dishSummary,dishName,quantity,subtotal');
  for (const d of summary.dishSummary) {
    lines.push(`dish,${escapeCsv(d.dishName)},${d.quantity},${d.subtotal}`);
  }
  lines.push('');
  lines.push('employee,labelCode,name,department,detail,remark,amount');
  for (const e of summary.employeeDetails) {
    const detail = formatLabelPrintLines(e, {
      widthMm: 60,
      heightMm: 40,
    }).join(' | ');
    lines.push(
      `line,${e.labelCode},${escapeCsv(e.employeeName)},${escapeCsv(e.department)},${escapeCsv(detail)},${escapeCsv(e.remark || '无')},${e.amount}`,
    );
  }
  return lines.join('\n');
}

export function employeesToCsv(
  rows: {
    name: string;
    phone: string;
    departmentName: string;
  }[],
): string {
  const lines = ['姓名,手机号,部门'];
  for (const r of rows) {
    lines.push(
      [escapeCsv(r.name), r.phone, escapeCsv(r.departmentName)].join(','),
    );
  }
  return lines.join('\n');
}

export function labelsToHtml(
  groups: MealLabelGroupDto[],
  opts?: LabelPrintOptions & { fontSizePt?: number },
): string {
  const widthMm = opts?.widthMm ?? 60;
  const heightMm = opts?.heightMm ?? 40;
  const fontScale = opts?.fontScale ?? 'standard';
  const resolved: LabelPrintOptions & { widthMm: number; heightMm: number } = {
    widthMm,
    heightMm,
    fontScale,
    showPackage: opts?.showPackage,
    showMeat: opts?.showMeat,
    showVegetable: opts?.showVegetable,
    showExtra: opts?.showExtra,
    showRemark: opts?.showRemark,
  };

  const pages = groups.map((g) => labelPageHtml(g, resolved)).join('');
  const css = labelPrintCss({ widthMm, heightMm, fontScale });
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><style>${css}</style></head><body>${pages}</body></html>`;
}

/** 供 admin-web 预览网格使用的屏幕 CSS（非打印） */
export function labelPreviewCss(widthMm: number): string {
  return `
  .label-card { border: 1px solid #ddd; border-radius: 6px; padding: 10px 12px;
    width: 220px; background: #fafafa; box-sizing: border-box; }
  .code { font-weight: 700; color: #2d8f47; margin-bottom: 4px; }
  .line { font-size: 13px; line-height: 1.45; }
  .remark { font-size: 12px; color: #666; margin-top: 6px; }
  .print-only { display: none; }
  @media print {
    .preview-grid { display: none !important; }
    .print-only { display: block !important; }
  }
`;
}

export function labelsToPrintHtml(
  groups: MealLabelGroupDto[],
  opts?: LabelPrintOptions,
): string {
  return labelsToHtml(groups, opts);
}
