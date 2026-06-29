import { Request, Response } from 'express';
import {
  BadRequest,
  Forbidden,
  NotFound,
  Unauthorized,
} from '../middleware/error.middleware';
import { reviewToDto } from '../models/mappers';
import { reviewService } from '../services/review.service';
import { resolveAdminScope } from '../utils/company-scope.util';

export const reviewController = {
  create(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const b = req.body ?? {};
    const orderId = typeof b.orderId === 'string' ? b.orderId : '';
    if (!orderId) throw BadRequest('缺少 orderId');

    const rating = Number(b.rating);
    const overallRating =
      b.overallRating != null ? Number(b.overallRating) : rating;
    const tasteRating =
      b.tasteRating != null ? Number(b.tasteRating) : undefined;
    const hygieneRating =
      b.hygieneRating != null ? Number(b.hygieneRating) : undefined;
    const serviceRating =
      b.serviceRating != null ? Number(b.serviceRating) : undefined;
    const deliveryRating =
      b.deliveryRating != null ? Number(b.deliveryRating) : undefined;
    const content = typeof b.content === 'string' ? b.content : '';
    const images = Array.isArray(b.images)
      ? b.images.filter((u: unknown): u is string => typeof u === 'string')
      : [];
    const isAnonymous = b.isAnonymous === true;

    try {
      const row = reviewService.create({
        orderId,
        userId: req.user.id,
        rating: overallRating,
        overallRating,
        tasteRating,
        hygieneRating,
        serviceRating,
        deliveryRating,
        content,
        images,
        isAnonymous,
      });
      const display = reviewService.resolveDisplayName(row, 'employee');
      res.json({
        data: reviewToDto(row, reviewService.imagesOf(row), {
          displayUserName: display.displayUserName,
          departmentName: display.departmentName,
        }),
      });
    } catch (e) {
      const msg = (e as Error).message;
      if (msg === 'REVIEW_DISABLED') {
        throw BadRequest('评价功能未开启', 'REVIEW_DISABLED');
      }
      if (msg === 'INVALID_RATING') {
        throw BadRequest('评分须为 1~5 星', 'INVALID_RATING');
      }
      if (msg === 'INVALID_HYGIENE_RATING') {
        throw BadRequest('卫生评分须为 1~5 星', 'INVALID_HYGIENE_RATING');
      }
      if (msg === 'INVALID_IMAGE_COUNT') {
        throw BadRequest('最多上传9张图片', 'INVALID_IMAGE_COUNT');
      }
      if (msg === 'INVALID_IMAGE_URL') {
        throw BadRequest('图片地址无效', 'INVALID_IMAGE_URL');
      }
      if (msg === 'ORDER_NOT_FOUND') throw NotFound('订单不存在');
      if (msg === 'ORDER_NOT_COMPLETED') {
        throw BadRequest('订单完成后才可评价', 'ORDER_NOT_COMPLETED');
      }
      if (msg === 'REVIEW_ALREADY_EXISTS') {
        throw BadRequest('该订单已评价', 'REVIEW_ALREADY_EXISTS');
      }
      if (msg === 'FORBIDDEN') throw Forbidden('无权评价该订单');
      throw e;
    }
  },

  getByOrder(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const orderId = req.params.orderId;
    const row = reviewService.getByOrderId(orderId);
    if (!row) {
      res.json({ data: null });
      return;
    }
    const viewer =
      req.user.role === 'merchant'
        ? 'merchant'
        : req.user.role === 'admin'
          ? 'admin'
          : 'employee';
    const display = reviewService.resolveDisplayName(row, viewer);
    res.json({
      data: reviewToDto(row, reviewService.imagesOf(row), {
        displayUserName: display.displayUserName,
        departmentName: display.departmentName,
      }),
    });
  },

  listByMerchant(req: Request, res: Response) {
    if (!req.user) throw Unauthorized();
    const merchantId = req.params.merchantId;
    const scope = resolveAdminScope(req.user);

    if (scope.isMerchant) {
      if (!scope.merchantId || scope.merchantId !== merchantId) {
        throw Forbidden('无权查看该商家评价');
      }
    } else if (req.user.role === 'employee') {
      // 员工可查看商家公开评价
    } else if (!scope.isPlatformAdmin && !scope.isCompanyAdmin) {
      throw Forbidden('无权查看商家评价');
    }

    const rows = reviewService.listByMerchant(merchantId);
    res.json({
      data: rows.map((r) => {
        const display = reviewService.resolveDisplayName(
          r,
          scope.isMerchant ? 'merchant' : 'admin',
        );
        return reviewToDto(r, reviewService.imagesOf(r), {
          displayUserName: display.displayUserName,
          departmentName: display.departmentName,
        });
      }),
    });
  },
};
