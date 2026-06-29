import { Request, Response } from 'express';
import {
  BadRequest,
  Forbidden,
  NotFound,
  Unauthorized,
} from '../middleware/error.middleware';
import { dishToDto, normalizeDishCategory } from '../models/mappers';
import {
  ALL_DISH_CATEGORIES,
  DISH_LISTING_MEAL_TYPES,
  DishCategory,
  MealType,
  UserRow,
} from '../models/types';
import { dishService } from '../services/dish.service';
import {
  assertMerchantAccess,
  getMerchantIdByDishId,
  resolveAdminScope,
} from '../utils/company-scope.util';

function parseDishMealType(v: unknown): MealType | undefined {
  if (typeof v !== 'string') return undefined;
  return DISH_LISTING_MEAL_TYPES.includes(v as MealType)
    ? (v as MealType)
    : undefined;
}

function parseDishMealTypesArr(v: unknown): MealType[] | undefined {
  if (v === undefined) return undefined;
  if (!Array.isArray(v)) return undefined;
  const out: MealType[] = [];
  for (const m of v) {
    const mt = parseDishMealType(m);
    if (mt && !out.includes(mt)) out.push(mt);
  }
  return out;
}

function parseCategory(v: unknown): DishCategory | undefined {
  if (v === undefined) return undefined;
  if (typeof v !== 'string') return undefined;
  const norm = normalizeDishCategory(v);
  return ALL_DISH_CATEGORIES.includes(norm) || norm === ''
    ? norm
    : undefined;
}

/**
 * 菜品写操作鉴权
 *
 * - 商家：仅能操作自己绑定的 merchantId 下的菜品（即使前端传入也必须一致）
 * - 平台 / 企业管理员：可操作其权限范围内的菜品
 * - 员工：禁止
 */
function resolveOwnedMerchantIdForCreate(
  user: UserRow,
  requestedMerchantId: string | undefined,
): string {
  const scope = resolveAdminScope(user);

  if (scope.isMerchant) {
    if (!scope.merchantId) throw Forbidden('当前账号未绑定商家');
    if (requestedMerchantId && requestedMerchantId !== scope.merchantId) {
      throw Forbidden('无权为其它商家新增菜品');
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

  throw Forbidden('当前角色无权管理菜品');
}

function assertOwnsDish(user: UserRow, dishId: string): void {
  let merchantId: string;
  try {
    merchantId = getMerchantIdByDishId(dishId);
  } catch (e) {
    if ((e as Error).message === 'NOT_FOUND') throw NotFound('菜品不存在');
    throw e;
  }

  const scope = resolveAdminScope(user);
  if (scope.isMerchant) {
    if (!scope.merchantId) throw Forbidden('当前账号未绑定商家');
    if (scope.merchantId !== merchantId) throw Forbidden('无权操作其它商家的菜品');
    return;
  }
  if (scope.isPlatformAdmin || scope.isCompanyAdmin) {
    try {
      assertMerchantAccess(user, merchantId);
    } catch (e) {
      if ((e as Error).message === 'FORBIDDEN') throw Forbidden('无权操作该商家');
      throw e;
    }
    return;
  }
  throw Forbidden('当前角色无权管理菜品');
}

export const dishController = {
  listByMerchant(req: Request, res: Response) {
    const merchantId = req.params.merchantId;
    if (!merchantId) throw BadRequest('缺少 merchantId');
    const rawMeal = req.query.mealType;
    const mealType =
      rawMeal != null && String(rawMeal) !== ''
        ? parseDishMealType(rawMeal)
        : undefined;
    if (rawMeal != null && String(rawMeal) !== '' && !mealType) {
      res.json({ data: [] });
      return;
    }
    const list = dishService
      .listByMerchant(merchantId, mealType, { hideSoldOut: true })
      .map(dishToDto);
    res.json({ data: list });
  },

  create(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const body = req.body ?? {};
    const name = body.name;
    const mealType = parseDishMealType(body.mealType);
    if (!name || typeof name !== 'string') throw BadRequest('name 不能为空');
    if (!mealType) throw BadRequest('mealType 非法');

    const category = parseCategory(body.category);
    // 普通菜品在套餐体系下可不单独设价；加菜必须填 extraPrice
    let price = Number(body.price);
    if (!Number.isFinite(price) || price < 0) price = 0;
    const extraPrice =
      body.extraPrice !== undefined ? Number(body.extraPrice) : undefined;
    if (category === 'extra') {
      if (!Number.isFinite(extraPrice as number) || (extraPrice as number) <= 0) {
        throw BadRequest('加菜分类必须填写加菜价格 extraPrice');
      }
    }

    const merchantId = resolveOwnedMerchantIdForCreate(req.user, body.merchantId);

    try {
      const dish = dishService.create({
        merchantId,
        name,
        image: typeof body.image === 'string' ? body.image : undefined,
        description:
          typeof body.description === 'string' ? body.description : '',
        price,
        mealType,
        tags: Array.isArray(body.tags) ? body.tags.map(String) : [],
        isAvailable:
          typeof body.isAvailable === 'boolean' ? body.isAvailable : true,
        category,
        extraPrice,
        mealTypes: parseDishMealTypesArr(body.mealTypes),
      });
      res.json({ data: dishToDto(dish) });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'EXTRA_PRICE_REQUIRED')
        throw BadRequest('加菜分类必须填写加菜价格 extraPrice');
      if (msg === 'DISH_OVERTIME_NOT_ALLOWED')
        throw BadRequest('菜品不支持加班餐餐段', 'DISH_OVERTIME_NOT_ALLOWED');
      throw e;
    }
  },

  update(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const dishId = req.params.dishId;
    if (!dishId) throw BadRequest('缺少 dishId');
    assertOwnsDish(req.user, dishId);

    const body = req.body ?? {};
    const mealType =
      body.mealType !== undefined ? parseDishMealType(body.mealType) : undefined;
    if (body.mealType !== undefined && !mealType) {
      throw BadRequest('mealType 非法');
    }
    try {
      const dish = dishService.update(dishId, {
        name: typeof body.name === 'string' ? body.name : undefined,
        image: typeof body.image === 'string' ? body.image : undefined,
        description:
          typeof body.description === 'string' ? body.description : undefined,
        price:
          body.price !== undefined ? Number(body.price) : undefined,
        mealType,
        tags: Array.isArray(body.tags) ? body.tags.map(String) : undefined,
        isAvailable:
          typeof body.isAvailable === 'boolean'
            ? body.isAvailable
            : undefined,
        category: parseCategory(body.category),
        extraPrice:
          body.extraPrice !== undefined ? Number(body.extraPrice) : undefined,
        mealTypes: parseDishMealTypesArr(body.mealTypes),
      });
      res.json({ data: dishToDto(dish) });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'NOT_FOUND') throw NotFound('菜品不存在');
      if (msg === 'EXTRA_PRICE_REQUIRED')
        throw BadRequest('切换为加菜分类必须填写加菜价格 extraPrice');
      if (msg === 'INVALID_EXTRA_PRICE')
        throw BadRequest('extraPrice 非法');
      if (msg === 'DISH_OVERTIME_NOT_ALLOWED')
        throw BadRequest('菜品不支持加班餐餐段', 'DISH_OVERTIME_NOT_ALLOWED');
      throw e;
    }
  },

  setAvailable(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const dishId = req.params.dishId;
    const { isAvailable } = req.body ?? {};
    if (!dishId) throw BadRequest('缺少 dishId');
    if (typeof isAvailable !== 'boolean')
      throw BadRequest('isAvailable 必须是 boolean');
    assertOwnsDish(req.user, dishId);
    try {
      const dish = dishService.setAvailable(dishId, isAvailable);
      res.json({ data: dishToDto(dish) });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('菜品不存在');
      throw e;
    }
  },

  setSoldOut(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const dishId = req.params.dishId;
    const { isSoldOut } = req.body ?? {};
    if (!dishId) throw BadRequest('缺少 dishId');
    if (typeof isSoldOut !== 'boolean')
      throw BadRequest('isSoldOut 必须是 boolean');
    assertOwnsDish(req.user, dishId);
    try {
      const dish = dishService.setSoldOut(dishId, isSoldOut);
      res.json({ data: dishToDto(dish) });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('菜品不存在');
      throw e;
    }
  },

  remove(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const dishId = req.params.dishId;
    if (!dishId) throw BadRequest('缺少 dishId');
    assertOwnsDish(req.user, dishId);
    try {
      dishService.delete(dishId);
      res.json({ data: { ok: true } });
    } catch (e) {
      if ((e as Error).message === 'NOT_FOUND') throw NotFound('菜品不存在');
      throw e;
    }
  },
};
