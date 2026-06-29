import cors from 'cors';
import express from 'express';
import path from 'path';
import { getDb } from './db/database';
import { loadUser } from './middleware/auth.middleware';
import {
  errorHandler,
  notFoundHandler,
} from './middleware/error.middleware';
import authRoutes from './routes/auth.routes';
import { dishRouter, merchantDishRouter } from './routes/dish.routes';
import {
  merchantRouter,
  nearbyRouter,
} from './routes/merchant.routes';
import { merchantOrderRouter, orderRouter } from './routes/order.routes';
import {
  merchantPackageRouter,
  packageOrderDataRouter,
  packageRouter,
} from './routes/package.routes';
import {
  conversationRouter,
  merchantConversationRouter,
} from './routes/conversation.routes';
import uploadRoutes, { ensureUploadSubdirs } from './routes/upload.routes';
import reviewRoutes from './routes/review.routes';
import paymentRoutes from './routes/payment.routes';
import adminRoutes from './routes/admin.routes';
import merchantOnboardingRoutes from './routes/merchant-onboarding.routes';
import supportRoutes from './routes/support.routes';
import couponRoutes from './routes/coupon.routes';
import deliveryLocationRoutes, {
  adminDeliveryLocationRouter,
} from './routes/delivery-location.routes';
import { systemConfigService } from './services/system-config.service';
import { paymentConfigService } from './services/payment-config.service';

export function createApp(): express.Express {
  // 初始化数据库（创建表）
  getDb();

  const app = express();

  // CORS：默认放开（CORS_ORIGIN=*），支持逗号分隔的白名单
  // 例：CORS_ORIGIN=http://localhost:5757,http://192.168.0.10:5757
  const corsRaw = (process.env.CORS_ORIGIN || '*').trim();
  if (corsRaw === '*' || corsRaw === '') {
    app.use(cors());
  } else {
    const whitelist = corsRaw
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean);
    app.use(
      cors({
        origin: (origin, cb) => {
          // 服务端直连 / curl 等无 Origin 请求放行
          if (!origin) return cb(null, true);
          cb(null, whitelist.includes(origin));
        },
      }),
    );
  }

  app.use(express.json({ limit: '10mb' }));
  app.use(express.urlencoded({ extended: true }));

  // 静态暴露 uploads（启动时确保子目录存在）
  const uploadDir = path.resolve(
    process.cwd(),
    process.env.UPLOAD_DIR || './uploads',
  );
  ensureUploadSubdirs(uploadDir);
  app.use('/uploads', express.static(uploadDir));

  app.use(loadUser);

  // 健康检查
  app.get('/api/health', (_req, res) => {
    res.json({ data: { ok: true, ts: new Date().toISOString() } });
  });

  /** 运行时配置（只读，供客户端/验收读取；业务强制以服务端校验为准） */
  app.get('/api/config/runtime', (_req, res) => {
    const full = systemConfigService.getFullConfig();
    const payment = paymentConfigService.getPublicConfig();
    res.json({
      data: {
        mealDeadlines: full.mealDeadlines,
        appSettings: {
          allowCancelOrder: full.appSettings.allowCancelOrder,
          enableReview: full.appSettings.enableReview,
          requirePaymentScreenshot: full.appSettings.requirePaymentScreenshot,
          showSoldOutDishes: full.appSettings.showSoldOutDishes,
          onlinePaymentEnabled: payment.onlinePaymentEnabled,
        },
        payment,
        updatedAt: full.updatedAt,
      },
    });
  });

  // 业务路由
  app.use('/api/auth', authRoutes);
  app.use('/api/merchants', nearbyRouter);
  app.use('/api/merchants/:merchantId/dishes', merchantDishRouter);
  app.use('/api/merchants/:merchantId/packages', merchantPackageRouter);
  app.use(
    '/api/merchants/:merchantId/package-order-data',
    packageOrderDataRouter,
  );
  app.use('/api/merchant', merchantRouter);
  app.use('/api/merchant', merchantOrderRouter);
  app.use('/api/dishes', dishRouter);
  app.use('/api/packages', packageRouter);
  app.use('/api/orders', orderRouter);
  app.use('/api/reviews', reviewRoutes);
  app.use('/api/payments', paymentRoutes);
  app.use('/api/conversations', conversationRouter);
  app.use('/api/merchant/conversations', merchantConversationRouter);
  app.use('/api/support', supportRoutes);
  app.use('/api/coupons', couponRoutes);
  app.use('/api/uploads', uploadRoutes);
  app.use('/api/delivery-location', deliveryLocationRoutes);
  app.use('/api/merchant-onboarding', merchantOnboardingRoutes);
  app.use('/api/admin', adminRoutes);
  app.use('/api/admin/delivery-location', adminDeliveryLocationRouter);

  // 404 + error
  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}
