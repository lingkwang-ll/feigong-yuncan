import { Request, Response } from 'express';
import {
  BadRequest,
  Forbidden,
  NotFound,
  Unauthorized,
} from '../middleware/error.middleware';
import {
  conversationMessageToDto,
  conversationToDto,
} from '../models/mappers';
import { ConversationRow, OrderRow, UserRow } from '../models/types';
import { conversationService } from '../services/conversation.service';
import { orderService } from '../services/order.service';
import { merchantService } from '../services/merchant.service';
import { assertOrderAccess, resolveAdminScope } from '../utils/company-scope.util';
import { resolveMerchantDisplayName } from '../utils/display-text.util';
import { getDb } from '../db/database';

function ensureUser(req: Request): UserRow {
  if (!req.user) throw Unauthorized();
  return req.user;
}

function ensureOrder(orderId: string): OrderRow {
  const order = orderService.getById(orderId);
  if (!order) throw NotFound('订单不存在');
  return order;
}

function ensureConversation(id: string): ConversationRow {
  const conv = conversationService.getById(id);
  if (!conv) throw NotFound('会话不存在');
  return conv;
}

function ensureRoleAccess(
  user: UserRow,
  conv: ConversationRow,
): 'employee' | 'merchant' | 'admin' {
  try {
    return conversationService.resolveAccess(user, conv).role;
  } catch (e) {
    if ((e as Error).message === 'FORBIDDEN') throw Forbidden('无权访问该会话');
    throw e;
  }
}

/** 必须是员工 / 管理员才能走员工侧接口（merchant 走商家侧接口） */
function assertEmployeeSide(user: UserRow): void {
  const scope = resolveAdminScope(user);
  if (scope.isPlatformAdmin) return;
  if (user.role === 'employee') return;
  throw Forbidden('该接口仅员工/管理员可用');
}

/** 必须是商家或管理员才能走商家侧接口 */
function assertMerchantSide(user: UserRow): void {
  const scope = resolveAdminScope(user);
  if (scope.isPlatformAdmin) return;
  if (scope.isMerchant) return;
  throw Forbidden('该接口仅商家/管理员可用');
}

function withConversationContext(conv: ConversationRow) {
  const order = orderService.getById(conv.order_id);
  let employeeName: string | null = null;
  if (conv.employee_id) {
    const u = getDb()
      .prepare<[string], { name: string }>('SELECT name FROM users WHERE id = ?')
      .get(conv.employee_id);
    employeeName = u?.name ?? null;
  }
  const merchant = merchantService.getById(conv.merchant_id);
  const merchantName = resolveMerchantDisplayName(
    order?.merchant_name,
    merchant?.name,
  );
  return conversationToDto(conv, {
    orderNo: order?.order_no ?? null,
    orderStatus: order?.status ?? null,
    employeeName,
    merchantName,
  });
}

function withSyncedContext(conv: ConversationRow) {
  return withConversationContext(conversationService.syncUnreadCounts(conv));
}

export const conversationController = {
  // ---------- 员工侧 ----------

  /** GET /api/conversations/order/:orderId */
  getOrCreateByOrder(req: Request, res: Response) {
    const user = ensureUser(req);
    assertEmployeeSide(user);
    const orderId = req.params.orderId;
    let order = ensureOrder(orderId);
    if (user.role === 'employee' && !order.user_id) {
      orderService.claimEmployeeOrder(order.id, user.id);
      order = ensureOrder(orderId);
    }
    try {
      assertOrderAccess(user, order);
    } catch (e) {
      if ((e as Error).message === 'FORBIDDEN')
        throw Forbidden('无权访问该订单');
      throw e;
    }
    const conv = conversationService.getOrCreateForOrder(order);
    res.json({ data: withSyncedContext(conv) });
  },

  /** GET /api/conversations — 员工会话列表 */
  employeeList(req: Request, res: Response) {
    const user = ensureUser(req);
    assertEmployeeSide(user);
    if (user.role !== 'employee') {
      res.json({ data: [] });
      return;
    }
    const list = conversationService
      .listByEmployee(user.id)
      .map((c) => withSyncedContext(c));
    res.json({ data: list });
  },

  /** GET /api/conversations/:conversationId/messages */
  employeeListMessages(req: Request, res: Response) {
    const user = ensureUser(req);
    assertEmployeeSide(user);
    const conv = ensureConversation(req.params.conversationId);
    ensureRoleAccess(user, conv);
    const list = conversationService
      .messages(conv.id)
      .map(conversationMessageToDto);
    res.json({ data: list });
  },

  /** POST /api/conversations/:conversationId/messages */
  employeeSendMessage(req: Request, res: Response) {
    const user = ensureUser(req);
    assertEmployeeSide(user);
    const conv = ensureConversation(req.params.conversationId);
    const role = ensureRoleAccess(user, conv);
    if (role !== 'employee') {
      throw Forbidden('请通过商家接口发送消息');
    }
    const b = req.body ?? {};
    sendOrThrow({
      conversationId: conv.id,
      user,
      role,
      messageType: b.messageType,
      content: b.content,
      imageUrl: b.imageUrl,
      metadata: b.metadata,
      res,
    });
  },

  /** POST /api/conversations/:conversationId/read */
  employeeMarkRead(req: Request, res: Response) {
    const user = ensureUser(req);
    assertEmployeeSide(user);
    const conv = ensureConversation(req.params.conversationId);
    const role = ensureRoleAccess(user, conv);
    if (role !== 'employee') {
      throw Forbidden('请通过商家接口标记已读');
    }
    const updated = conversationService.markRead(conv.id, 'employee');
    res.json({ data: withSyncedContext(updated) });
  },

  // ---------- 商家侧 ----------

  /** GET /api/merchant/conversations/order/:orderId */
  merchantGetOrCreateByOrder(req: Request, res: Response) {
    const user = ensureUser(req);
    assertMerchantSide(user);
    const orderId = req.params.orderId;
    const order = ensureOrder(orderId);
    try {
      assertOrderAccess(user, order);
    } catch (e) {
      if ((e as Error).message === 'FORBIDDEN')
        throw Forbidden('无权访问该订单');
      throw e;
    }
    const conv = conversationService.getOrCreateForOrder(order);
    res.json({ data: withSyncedContext(conv) });
  },

  /** GET /api/merchant/conversations */
  merchantList(req: Request, res: Response) {
    const user = ensureUser(req);
    assertMerchantSide(user);
    const scope = resolveAdminScope(user);
    if (!scope.merchantId && !scope.isPlatformAdmin) {
      throw Forbidden('当前账号未绑定商家');
    }
    if (scope.isPlatformAdmin && req.query.merchantId) {
      const merchantId = String(req.query.merchantId);
      const list = conversationService
      .listByMerchant(merchantId)
      .map((c) => withSyncedContext(c));
      res.json({ data: list });
      return;
    }
    if (!scope.merchantId) {
      // platform admin without merchantId param -> return empty (admin 视图请走 admin 路由，后续接入)
      res.json({ data: [] });
      return;
    }
    const list = conversationService
      .listByMerchant(scope.merchantId)
      .map((c) => withSyncedContext(c));
    res.json({ data: list });
  },

  /** GET /api/merchant/conversations/:conversationId/messages */
  merchantListMessages(req: Request, res: Response) {
    const user = ensureUser(req);
    assertMerchantSide(user);
    const conv = ensureConversation(req.params.conversationId);
    ensureRoleAccess(user, conv);
    const list = conversationService
      .messages(conv.id)
      .map(conversationMessageToDto);
    res.json({ data: list });
  },

  /** POST /api/merchant/conversations/:conversationId/messages */
  merchantSendMessage(req: Request, res: Response) {
    const user = ensureUser(req);
    assertMerchantSide(user);
    const conv = ensureConversation(req.params.conversationId);
    const role = ensureRoleAccess(user, conv);
    if (role !== 'merchant') {
      throw Forbidden('请通过员工接口发送消息');
    }
    const b = req.body ?? {};
    sendOrThrow({
      conversationId: conv.id,
      user,
      role,
      messageType: b.messageType,
      content: b.content,
      imageUrl: b.imageUrl,
      metadata: b.metadata,
      res,
    });
  },

  /** POST /api/merchant/conversations/:conversationId/read */
  merchantMarkRead(req: Request, res: Response) {
    const user = ensureUser(req);
    assertMerchantSide(user);
    const conv = ensureConversation(req.params.conversationId);
    const role = ensureRoleAccess(user, conv);
    if (role !== 'merchant') {
      throw Forbidden('请通过员工接口标记已读');
    }
    const updated = conversationService.markRead(conv.id, 'merchant');
    res.json({ data: withSyncedContext(updated) });
  },
};

function sendOrThrow(args: {
  conversationId: string;
  user: UserRow;
  role: 'employee' | 'merchant' | 'admin';
  messageType: unknown;
  content: unknown;
  imageUrl: unknown;
  metadata: unknown;
  res: Response;
}) {
  if (args.role === 'admin') {
    throw Forbidden('管理员不能直接发送会话消息');
  }
  const type = String(args.messageType ?? 'text');
  if (type !== 'text' && type !== 'image' && type !== 'emoji') {
    throw BadRequest('messageType 非法', 'INVALID_MESSAGE_TYPE');
  }
  try {
    const msg = conversationService.sendMessage({
      conversationId: args.conversationId,
      user: args.user,
      role: args.role,
      messageType: type,
      content: typeof args.content === 'string' ? args.content : undefined,
      imageUrl: typeof args.imageUrl === 'string' ? args.imageUrl : undefined,
      metadata:
        args.metadata && typeof args.metadata === 'object'
          ? (args.metadata as Record<string, unknown>)
          : undefined,
    });
    args.res.json({ data: conversationMessageToDto(msg) });
  } catch (e) {
    const code = (e as Error).message;
    if (code === 'CONVERSATION_NOT_FOUND') throw NotFound('会话不存在');
    if (code === 'CONTENT_REQUIRED')
      throw BadRequest('消息内容不能为空', 'CONTENT_REQUIRED');
    if (code === 'CONTENT_TOO_LONG')
      throw BadRequest('消息内容过长', 'CONTENT_TOO_LONG');
    if (code === 'IMAGE_URL_REQUIRED')
      throw BadRequest('图片消息缺少 imageUrl', 'IMAGE_URL_REQUIRED');
    if (code === 'INVALID_MESSAGE_TYPE')
      throw BadRequest('messageType 非法', 'INVALID_MESSAGE_TYPE');
    if (code === 'SYSTEM_MESSAGE_NOT_ALLOWED')
      throw Forbidden('系统消息不能由用户发送');
    throw e;
  }
}
