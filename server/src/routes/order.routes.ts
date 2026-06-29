import { Router } from 'express';
import { orderController } from '../controllers/order.controller';
import { requireAuth } from '../middleware/auth.middleware';

// /api/orders —— 全部需要登录
const orderRouter = Router();
orderRouter.post('/', requireAuth, orderController.create);
orderRouter.get('/my', requireAuth, orderController.listMy);
orderRouter.get('/overtime-eligibility', requireAuth, orderController.overtimeEligibility);
orderRouter.get('/company-pay-eligibility', requireAuth, orderController.companyPayEligibility);
orderRouter.put('/:orderId/status', requireAuth, orderController.updateStatus);

// /api/merchant/orders（挂接到 merchant 路由上）
const merchantOrderRouter = Router();
merchantOrderRouter.get('/orders', requireAuth, orderController.listMerchant);

export { merchantOrderRouter, orderRouter };
