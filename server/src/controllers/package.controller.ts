import { Request, Response } from 'express';
import {
  BadRequest,
  Forbidden,
  NotFound,
  Unauthorized,
} from '../middleware/error.middleware';
import { packageToDto } from '../models/mappers';
import {
  DISH_LISTING_MEAL_TYPES,
  MealType,
  PackageRules,
  UserRow,
} from '../models/types';
import { getDb } from '../db/database';
import { packageService } from '../services/package.service';
import { packageOrderService } from '../services/package-order.service';
import {
  assertMerchantAccess,
  resolveAdminScope,
} from '../utils/company-scope.util';

function parsePackageMealType(v: unknown): MealType | undefined {
  if (typeof v !== 'string') return undefined;
  return DISH_LISTING_MEAL_TYPES.includes(v as MealType)
    ? (v as MealType)
    : undefined;
}

function parsePackageMealTypes(v: unknown): MealType[] | undefined {
  if (v === undefined) return undefined;
  if (!Array.isArray(v)) return undefined;
  const out: MealType[] = [];
  for (const m of v) {
    const mt = parsePackageMealType(m);
    if (mt && !out.includes(mt)) out.push(mt);
  }
  return out;
}

function parseRules(v: unknown): PackageRules | undefined {
  if (v === undefined) return undefined;
  if (!v || typeof v !== 'object') throw BadRequest('rules 必须是对象');
  const out: PackageRules = {};
  for (const cat of ['meat', 'vegetable', 'staple', 'soup', 'drink'] as const) {
    const n = (v as Record<string, unknown>)[cat];
    if (n !== undefined && n !== null && n !== '') {
      const num = Number(n);
      if (!Number.isFinite(num) || num < 0) {
        throw BadRequest(`rules.${cat} 非法`);
      }
      if (num > 0) out[cat] = Math.floor(num);
    }
  }
  return out;
}

/** 商家维护场景：只能管自己的；admin/company_admin 须传 merchantId 且校验 */
function resolveOwnedMerchantIdForCreate(
  user: UserRow,
  requestedMerchantId: string | undefined,
): string {
  const scope = resolveAdminScope(user);
  if (scope.isMerchant) {
    if (!scope.merchantId) throw Forbidden('当前账号未绑定商家');
    if (requestedMerchantId && requestedMerchantId !== scope.merchantId) {
      throw Forbidden('无权为其它商家创建套餐');
    }
    return scope.merchantId;
  }
  if (scope.isPlatformAdmin || scope.isCompanyAdmin) {
    if (!requestedMerchantId) throw BadRequest('缺少 merchantId');
    try {
      assertMerchantAccess(user, requestedMerchantId);
    } catch (e) {
      if ((e as Error).message === 'FORBIDDEN') throw Forbidden('无权操作该商家');
      throw e;
    }
    return requestedMerchantId;
  }
  throw Forbidden('当前角色无权管理套餐');
}

function assertOwnsPackage(user: UserRow, packageId: string): void {
  const row = getDb()
    .prepare<[string], { merchant_id: string }>(
      'SELECT merchant_id FROM packages WHERE id = ?',
    )
    .get(packageId);
  if (!row) throw NotFound('套餐不存在');
  const scope = resolveAdminScope(user);
  if (scope.isMerchant) {
    if (!scope.merchantId) throw Forbidden('当前账号未绑定商家');
    if (scope.merchantId !== row.merchant_id) throw Forbidden('无权操作其它商家的套餐');
    return;
  }
  if (scope.isPlatformAdmin || scope.isCompanyAdmin) {
    try {
      assertMerchantAccess(user, row.merchant_id);
    } catch (e) {
      if ((e as Error).message === 'FORBIDDEN') throw Forbidden('无权操作该商家');
      throw e;
    }
    return;
  }
  throw Forbidden('当前角色无权管理套餐');
}

export const packageController = {
  /** 公开：员工套餐点餐聚合数据 */
  packageOrderData(req: Request, res: Response) {
    const merchantId = req.params.merchantId;
    if (!merchantId) throw BadRequest('缺少 merchantId');
    const mealType = parsePackageMealType(req.query.mealType);
    if (!mealType) throw BadRequest('mealType 非法或缺失');
    const data = packageOrderService.getPackageOrderData(merchantId, mealType);
    if (!data) throw NotFound('商家不存在');
    res.json({ data });
  },

  /** 公开：员工选套餐场景（GET /api/merchants/:merchantId/packages?mealType=lunch） */
  listByMerchant(req: Request, res: Response) {
    const merchantId = req.params.merchantId;
    if (!merchantId) throw BadRequest('缺少 merchantId');
    const rawMeal = req.query.mealType;
    const mealType =
      rawMeal != null && String(rawMeal) !== ''
        ? parsePackageMealType(rawMeal)
        : undefined;
    if (rawMeal != null && String(rawMeal) !== '' && !mealType) {
      res.json({ data: [] });
      return;
    }
    const list = packageService
      .listByMerchant(merchantId, { mealType })
      .map(packageToDto);
    res.json({ data: list });
  },

  /** 商家维护：返回包括 disabled 的全部 */
  listAllByMerchant(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const merchantId = resolveOwnedMerchantIdForCreate(
      req.user,
      req.query.merchantId as string | undefined,
    );
    const list = packageService.listAllByMerchant(merchantId).map(packageToDto);
    res.json({ data: list });
  },

  create(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const body = req.body ?? {};
    const name = body.name;
    const basePrice = Number(body.basePrice);
    if (!name || typeof name !== 'string') throw BadRequest('name 不能为空');
    if (!Number.isFinite(basePrice) || basePrice < 0) {
      throw BadRequest('basePrice 非法');
    }
    const merchantId = resolveOwnedMerchantIdForCreate(req.user, body.merchantId);

    try {
      const row = packageService.create({
        merchantId,
        name,
        description:
          typeof body.description === 'string' ? body.description : '',
        basePrice,
        mealTypes: parsePackageMealTypes(body.mealTypes),
        rules: parseRules(body.rules),
        allowExtra:
          typeof body.allowExtra === 'boolean' ? body.allowExtra : undefined,
        extraDishIds: Array.isArray(body.extraDishIds)
          ? body.extraDishIds.map(String)
          : undefined,
        isEnabled:
          typeof body.isEnabled === 'boolean' ? body.isEnabled : undefined,
      });
      res.json({ data: packageToDto(row) });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'INVALID_NAME') throw BadRequest('name 非法');
      if (msg === 'INVALID_PRICE') throw BadRequest('basePrice 非法');
      if (msg === 'EMPTY_RULES')
        throw BadRequest('套餐规则不能为空，至少配置一项荤/素/主食/汤/饮品');
      throw e;
    }
  },

  update(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const packageId = req.params.packageId;
    if (!packageId) throw BadRequest('缺少 packageId');
    assertOwnsPackage(req.user, packageId);
    const body = req.body ?? {};
    try {
      const row = packageService.update(packageId, {
        merchantId: undefined as unknown as string, // 不允许跨商家修改
        name: typeof body.name === 'string' ? body.name : undefined,
        description:
          typeof body.description === 'string' ? body.description : undefined,
        basePrice:
          body.basePrice !== undefined ? Number(body.basePrice) : undefined,
        mealTypes: parsePackageMealTypes(body.mealTypes),
        rules: parseRules(body.rules),
        allowExtra:
          typeof body.allowExtra === 'boolean' ? body.allowExtra : undefined,
        extraDishIds: Array.isArray(body.extraDishIds)
          ? body.extraDishIds.map(String)
          : undefined,
        isEnabled:
          typeof body.isEnabled === 'boolean' ? body.isEnabled : undefined,
      });
      res.json({ data: packageToDto(row) });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'NOT_FOUND') throw NotFound('套餐不存在');
      if (msg === 'INVALID_NAME') throw BadRequest('name 非法');
      if (msg === 'INVALID_PRICE') throw BadRequest('basePrice 非法');
      if (msg === 'EMPTY_RULES') throw BadRequest('套餐规则不能为空');
      throw e;
    }
  },

  setEnabled(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const packageId = req.params.packageId;
    if (!packageId) throw BadRequest('缺少 packageId');
    const { isEnabled } = req.body ?? {};
    if (typeof isEnabled !== 'boolean') throw BadRequest('isEnabled 必须是 boolean');
    assertOwnsPackage(req.user, packageId);
    try {
      const row = packageService.setEnabled(packageId, isEnabled);
      res.json({ data: packageToDto(row) });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('套餐不存在');
      throw e;
    }
  },

  remove(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const packageId = req.params.packageId;
    if (!packageId) throw BadRequest('缺少 packageId');
    assertOwnsPackage(req.user, packageId);
    try {
      packageService.delete(packageId);
      res.json({ data: { ok: true } });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('套餐不存在');
      throw e;
    }
  },
};
