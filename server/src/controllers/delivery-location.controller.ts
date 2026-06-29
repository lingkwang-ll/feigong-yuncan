import { Request, Response } from 'express';
import { BadRequest, Unauthorized } from '../middleware/error.middleware';
import { deliveryLocationToDto } from '../models/mappers';
import { ALL_MEAL_TYPES, MealType } from '../models/types';
import { deliveryLocationService } from '../services/delivery-location.service';
import { assertMerchantAccess } from '../utils/company-scope.util';

function parseMealType(v: unknown): MealType {
  if (typeof v === 'string' && ALL_MEAL_TYPES.includes(v as MealType)) {
    return v as MealType;
  }
  throw BadRequest('mealType 非法');
}

function parseCoord(v: unknown, field: string): number {
  const n = Number(v);
  if (!Number.isFinite(n)) throw BadRequest(`${field} 非法`);
  return n;
}

export const deliveryLocationController = {
  update(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const b = req.body ?? {};
    const date = b.date as string;
    const mealType = parseMealType(b.mealType);
    const merchantId = b.merchantId as string;
    if (!date) throw BadRequest('缺少 date');
    if (!merchantId) throw BadRequest('缺少 merchantId');

    try {
      assertMerchantAccess(req.user, merchantId);
    } catch {
      throw Unauthorized('无权更新该商家配送位置');
    }

    const row = deliveryLocationService.update({
      date,
      mealType,
      merchantId,
      latitude: parseCoord(b.latitude, 'latitude'),
      longitude: parseCoord(b.longitude, 'longitude'),
      addressText:
        typeof b.addressText === 'string' ? b.addressText : undefined,
      status:
        b.status === 'delivering' || b.status === 'stopped'
          ? b.status
          : 'delivering',
      companyId: req.user.company_id ?? undefined,
    });
    res.json({ data: deliveryLocationToDto(row) });
  },

  getCurrent(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const date = (req.query.date as string) || '';
    const mealType = parseMealType(req.query.mealType);
    const merchantId = req.query.merchantId as string;
    if (!date) throw BadRequest('缺少 date');
    if (!merchantId) throw BadRequest('缺少 merchantId');

    try {
      assertMerchantAccess(req.user, merchantId);
    } catch {
      // 员工端只读：允许同企业员工查看
      if (req.user.role !== 'employee') {
        throw Unauthorized('无权查看该配送位置');
      }
    }

    const row = deliveryLocationService.getCurrent(date, mealType, merchantId);
    res.json({ data: row ? deliveryLocationToDto(row) : null });
  },
};

export const adminDeliveryLocationController = {
  getCurrent(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const date = (req.query.date as string) || '';
    const mealType = parseMealType(req.query.mealType);
    const merchantId = req.query.merchantId as string;
    if (!date) throw BadRequest('缺少 date');
    if (!merchantId) throw BadRequest('缺少 merchantId');

    try {
      assertMerchantAccess(req.user, merchantId);
    } catch {
      throw Unauthorized('无权查看该配送位置');
    }

    const row = deliveryLocationService.getCurrent(date, mealType, merchantId);
    res.json({ data: row ? deliveryLocationToDto(row) : null });
  },
};
