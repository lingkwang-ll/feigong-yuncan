import { Router } from 'express';
import { packageController } from '../controllers/package.controller';
import { requireAuth } from '../middleware/auth.middleware';

// 查询某商家的可用套餐（员工选餐场景），公开接口（与 /merchants/:merchantId/dishes 一致）
const merchantPackageRouter = Router({ mergeParams: true });
merchantPackageRouter.get('/', packageController.listByMerchant);

const packageOrderDataRouter = Router({ mergeParams: true });
packageOrderDataRouter.get('/', packageController.packageOrderData);

// 套餐 CRUD 挂在 /api/packages，全部需要登录 + 归属校验
const packageRouter = Router();
packageRouter.get('/', requireAuth, packageController.listAllByMerchant);
packageRouter.post('/', requireAuth, packageController.create);
packageRouter.put('/:packageId', requireAuth, packageController.update);
packageRouter.put(
  '/:packageId/enabled',
  requireAuth,
  packageController.setEnabled,
);
packageRouter.delete('/:packageId', requireAuth, packageController.remove);

export { merchantPackageRouter, packageOrderDataRouter, packageRouter };
