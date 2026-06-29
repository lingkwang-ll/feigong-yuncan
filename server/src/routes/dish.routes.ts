import { Router } from 'express';
import { dishController } from '../controllers/dish.controller';
import { requireAuth } from '../middleware/auth.middleware';

// 查询某商家菜品挂在 /api/merchants/:merchantId/dishes（通过 mergeParams）
const merchantDishRouter = Router({ mergeParams: true });
merchantDishRouter.get('/', dishController.listByMerchant);

// 菜品 CRUD 挂在 /api/dishes，全部需要登录 + 归属校验
const dishRouter = Router();
dishRouter.post('/', requireAuth, dishController.create);
dishRouter.put('/:dishId', requireAuth, dishController.update);
dishRouter.put('/:dishId/available', requireAuth, dishController.setAvailable);
dishRouter.put('/:dishId/sold-out', requireAuth, dishController.setSoldOut);
dishRouter.delete('/:dishId', requireAuth, dishController.remove);

export { dishRouter, merchantDishRouter };
