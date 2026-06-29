/** 展示用文本兜底：避免 `????`、空值等进入前端 UI */

export function isCorruptDisplayText(value?: string | null): boolean {
  const t = (value ?? '').trim();
  if (!t) return true;
  if (/^(null|undefined)$/i.test(t)) return true;
  if (/^[\?？]+$/.test(t)) return true;
  if (t.includes('???')) return true;
  if (/^[\?？]+/.test(t) && t.toUpperCase().includes('E2E')) return true;
  return false;
}

export function resolveMerchantDisplayName(
  orderSnapshot?: string | null,
  merchantFromDb?: string | null,
): string {
  const fromDb = (merchantFromDb ?? '').trim();
  if (fromDb && !isCorruptDisplayText(fromDb)) return fromDb;
  const snap = (orderSnapshot ?? '').trim();
  if (snap && !isCorruptDisplayText(snap)) return snap;
  return '未知商家';
}

export function resolveDishDisplayName(
  snapshot?: string | null,
  dishFromDb?: string | null,
): string {
  const fromDb = (dishFromDb ?? '').trim();
  if (fromDb && !isCorruptDisplayText(fromDb)) return fromDb;
  const snap = (snapshot ?? '').trim();
  if (snap && !isCorruptDisplayText(snap)) return snap;
  return '菜品信息缺失';
}

export function resolvePackageDisplayName(value?: string | null): string {
  const t = (value ?? '').trim();
  if (t && !isCorruptDisplayText(t)) return t;
  return '套餐信息缺失';
}

export interface OrderDisplayLookup {
  merchantNameFromDb?: string | null;
  dishNameById?: Map<string, string>;
}

export function buildOrderItemsSummary(
  order: {
    package_id?: string | null;
    package_name?: string | null;
    selected_items_json?: string | null;
    extra_items_json?: string | null;
  },
  items: { dish_id?: string | null; dish_name: string; quantity: number }[],
  lookup: OrderDisplayLookup,
): string {
  const dishName = (dishId?: string | null, snap?: string) =>
    resolveDishDisplayName(
      snap,
      dishId ? lookup.dishNameById?.get(dishId) : undefined,
    );

  if (order.package_id) {
    const parts: string[] = [resolvePackageDisplayName(order.package_name)];
    try {
      const selected = JSON.parse(order.selected_items_json ?? '[]');
      if (Array.isArray(selected)) {
        for (const row of selected) {
          if (!row || typeof row !== 'object') continue;
          const o = row as Record<string, unknown>;
          parts.push(`${dishName(String(o.dishId ?? ''), String(o.name ?? ''))} x1`);
        }
      }
    } catch {
      /* ignore */
    }
    try {
      const extras = JSON.parse(order.extra_items_json ?? '[]');
      if (Array.isArray(extras)) {
        for (const row of extras) {
          if (!row || typeof row !== 'object') continue;
          const o = row as Record<string, unknown>;
          const qty = typeof o.quantity === 'number' ? o.quantity : 0;
          if (qty > 0) {
            parts.push(
              `${dishName(String(o.dishId ?? ''), String(o.name ?? ''))} x${qty}`,
            );
          }
        }
      }
    } catch {
      /* ignore */
    }
    return parts.join('、');
  }

  return items
    .map((i) => `${dishName(i.dish_id, i.dish_name)} x${i.quantity}`)
    .join('、');
}
