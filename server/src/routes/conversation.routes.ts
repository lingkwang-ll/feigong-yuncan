import { Router } from 'express';
import { conversationController } from '../controllers/conversation.controller';
import { uploadController } from '../controllers/upload.controller';
import { requireAuth } from '../middleware/auth.middleware';
import { buildUploader, singleFileUpload } from './upload.routes';

const chatUploader = buildUploader('chats');

/**
 * 员工 / 平台管理员侧会话接口
 * /api/conversations/*
 */
const conversationRouter = Router();

conversationRouter.get(
  '/',
  requireAuth,
  conversationController.employeeList,
);
conversationRouter.get(
  '/order/:orderId',
  requireAuth,
  conversationController.getOrCreateByOrder,
);
conversationRouter.get(
  '/:conversationId/messages',
  requireAuth,
  conversationController.employeeListMessages,
);
conversationRouter.post(
  '/:conversationId/messages',
  requireAuth,
  conversationController.employeeSendMessage,
);
conversationRouter.post(
  '/:conversationId/read',
  requireAuth,
  conversationController.employeeMarkRead,
);
conversationRouter.post(
  '/:conversationId/images',
  requireAuth,
  singleFileUpload(chatUploader, uploadController.conversationImage),
);

/**
 * 商家 / 平台管理员侧会话接口
 * /api/merchant/conversations/*
 */
const merchantConversationRouter = Router();

merchantConversationRouter.get(
  '/order/:orderId',
  requireAuth,
  conversationController.merchantGetOrCreateByOrder,
);
merchantConversationRouter.get(
  '/',
  requireAuth,
  conversationController.merchantList,
);
merchantConversationRouter.get(
  '/:conversationId/messages',
  requireAuth,
  conversationController.merchantListMessages,
);
merchantConversationRouter.post(
  '/:conversationId/messages',
  requireAuth,
  conversationController.merchantSendMessage,
);
merchantConversationRouter.post(
  '/:conversationId/read',
  requireAuth,
  conversationController.merchantMarkRead,
);
merchantConversationRouter.post(
  '/:conversationId/images',
  requireAuth,
  singleFileUpload(chatUploader, uploadController.conversationImage),
);

export { conversationRouter, merchantConversationRouter };
