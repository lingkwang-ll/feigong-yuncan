import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import {
  ALL_CONVERSATION_MESSAGE_TYPES,
  ConversationMessageRow,
  ConversationMessageType,
  ConversationRow,
  ConversationSenderType,
  OrderRow,
  OrderStatus,
  UserRow,
} from '../models/types';
import { resolveAdminScope } from '../utils/company-scope.util';

export interface ConversationAccessContext {
  conv: ConversationRow;
  /** 当前调用者在该会话中扮演的角色 */
  role: 'employee' | 'merchant' | 'admin';
}

export interface SendMessageInput {
  conversationId: string;
  user: UserRow;
  role: 'employee' | 'merchant' | 'admin';
  messageType: ConversationMessageType;
  /** 文字 / emoji 内容（system 内部使用） */
  content?: string;
  imageUrl?: string;
  metadata?: Record<string, unknown>;
}

/**
 * 订单沟通会话与消息服务。
 *
 * 业务约束：
 * - 每个 order 一个会话（UNIQUE(order_id)），首次访问自动创建。
 * - sender_id 一律由路由层用 req.user 注入，service 不再信任前端。
 * - 系统消息：订单创建、付款截图上传、商家接单、完成、取消都会写入。
 * - 计算未读：自己发的消息不计入自己的未读；
 *             收到的消息累加到对方的未读计数；
 *             markRead 清零并把对方所有未读消息的 read_at 写上。
 */
export class ConversationService {
  // ---------- 查询 ----------

  getById(id: string): ConversationRow | undefined {
    return getDb()
      .prepare<[string], ConversationRow>(
        'SELECT * FROM conversations WHERE id = ?',
      )
      .get(id);
  }

  getByOrderId(orderId: string): ConversationRow | undefined {
    return getDb()
      .prepare<[string], ConversationRow>(
        'SELECT * FROM conversations WHERE order_id = ?',
      )
      .get(orderId);
  }

  listByMerchant(merchantId: string): ConversationRow[] {
    return getDb()
      .prepare<[string], ConversationRow>(
        `SELECT * FROM conversations
           WHERE merchant_id = ?
           ORDER BY merchant_unread_count DESC, COALESCE(last_message_at, created_at) DESC`,
      )
      .all(merchantId);
  }

  listByEmployee(employeeId: string): ConversationRow[] {
    return getDb()
      .prepare<[string], ConversationRow>(
        `SELECT * FROM conversations
           WHERE employee_id = ?
           ORDER BY employee_unread_count DESC, COALESCE(last_message_at, created_at) DESC`,
      )
      .all(employeeId);
  }

  messages(
    conversationId: string,
    opts?: { limit?: number; afterId?: string },
  ): ConversationMessageRow[] {
    const limit = Math.min(Math.max(opts?.limit ?? 200, 1), 500);
    return getDb()
      .prepare<[string, number], ConversationMessageRow>(
        `SELECT * FROM conversation_messages
           WHERE conversation_id = ?
           ORDER BY created_at ASC, id ASC
           LIMIT ?`,
      )
      .all(conversationId, limit);
  }

  // ---------- 创建 ----------

  /**
   * 为订单获取会话；不存在则按订单数据创建，并写入一条"订单已提交"的系统消息。
   * 注意：会自动校验调用者是否可访问该订单（依赖路由层先校验 order）。
   */
  getOrCreateForOrder(order: OrderRow): ConversationRow {
    const existing = this.getByOrderId(order.id);
    if (existing) {
      if (!existing.employee_id && order.user_id) {
        return this.ensureEmployeeId(existing, order.user_id);
      }
      return existing;
    }
    const now = nowIso();
    const id = `conv_${nanoid(10)}`;
    getDb()
      .prepare(
        `INSERT INTO conversations
           (id, type, order_id, merchant_id, employee_id,
            last_message_text, last_message_at,
            employee_unread_count, merchant_unread_count,
            status, created_at, updated_at)
         VALUES (?, 'order', ?, ?, ?, ?, ?, 0, 0, 'open', ?, ?)`,
      )
      .run(
        id,
        order.id,
        order.merchant_id,
        order.user_id ?? null,
        '订单已提交',
        now,
        now,
        now,
      );

    const created = this.getById(id);
    if (!created) {
      throw new Error('CONVERSATION_CREATE_FAILED');
    }

    // 入会话即写入一条系统消息，便于双方进入聊天页就能看到上下文。
    this.appendSystemMessage(created, '订单已提交，请耐心等待商家接单');
    return this.getById(id) ?? created;
  }

  /** 订单状态变化的系统消息（幂等：仅生成消息，不依赖前端） */
  appendStatusSystemMessage(order: OrderRow): void {
    const text = systemTextForStatus(order.status);
    if (!text) return;
    const conv = this.getByOrderId(order.id);
    if (!conv) return;
    this.appendSystemMessage(conv, text);
  }

  /** 顾客上传付款截图后写入系统消息 */
  appendPaymentScreenshotSystemMessage(order: OrderRow): void {
    const conv = this.getByOrderId(order.id);
    if (!conv) return;
    this.appendSystemMessage(conv, '顾客已上传付款截图');
  }

  // ---------- 发送 ----------

  sendMessage(input: SendMessageInput): ConversationMessageRow {
    if (!ALL_CONVERSATION_MESSAGE_TYPES.includes(input.messageType)) {
      throw new Error('INVALID_MESSAGE_TYPE');
    }
    if (input.role !== 'employee' && input.role !== 'merchant') {
      // service 层只支持 employee/merchant；admin 系统消息走 appendSystemMessage
      throw new Error('INVALID_SENDER_ROLE');
    }

    const conv = this.getById(input.conversationId);
    if (!conv) throw new Error('CONVERSATION_NOT_FOUND');

    const senderType: ConversationSenderType =
      input.role === 'employee' ? 'employee' : 'merchant';

    let content: string | null = null;
    let imageUrl: string | null = null;

    if (input.messageType === 'image') {
      const url = (input.imageUrl ?? '').trim();
      if (!url) throw new Error('IMAGE_URL_REQUIRED');
      imageUrl = url;
      content = null;
    } else if (input.messageType === 'system') {
      throw new Error('SYSTEM_MESSAGE_NOT_ALLOWED');
    } else {
      const text = (input.content ?? '').trim();
      if (!text) throw new Error('CONTENT_REQUIRED');
      if (text.length > 2000) throw new Error('CONTENT_TOO_LONG');
      content = text;
    }

    const id = `cmsg_${nanoid(12)}`;
    const now = nowIso();
    const metaJson = JSON.stringify(input.metadata ?? {});

    const db = getDb();
    const tx = db.transaction(() => {
      db.prepare(
        `INSERT INTO conversation_messages
           (id, conversation_id, sender_type, sender_id,
            message_type, content, image_url, metadata_json,
            created_at, read_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)`,
      ).run(
        id,
        conv.id,
        senderType,
        input.user.id,
        input.messageType,
        content,
        imageUrl,
        metaJson,
        now,
      );

      // 维护未读：对方累加，自己保持不变；自己侧立刻置 0
      if (senderType === 'employee') {
        db.prepare(
          `UPDATE conversations
              SET last_message_text = ?, last_message_at = ?, updated_at = ?,
                  merchant_unread_count = merchant_unread_count + 1,
                  employee_unread_count = 0
            WHERE id = ?`,
        ).run(previewText(content, imageUrl, input.messageType), now, now, conv.id);
      } else {
        db.prepare(
          `UPDATE conversations
              SET last_message_text = ?, last_message_at = ?, updated_at = ?,
                  employee_unread_count = employee_unread_count + 1,
                  merchant_unread_count = 0
            WHERE id = ?`,
        ).run(previewText(content, imageUrl, input.messageType), now, now, conv.id);
      }
    });
    tx();

    const created = db
      .prepare<[string], ConversationMessageRow>(
        'SELECT * FROM conversation_messages WHERE id = ?',
      )
      .get(id);
    if (!created) throw new Error('MESSAGE_INSERT_FAILED');
    return created;
  }

  /** 系统消息（由服务端触发，例如订单状态变化） */
  appendSystemMessage(
    conv: ConversationRow,
    text: string,
    metadata?: Record<string, unknown>,
  ): ConversationMessageRow {
    const trimmed = (text || '').trim();
    if (!trimmed) throw new Error('CONTENT_REQUIRED');
    const id = `cmsg_${nanoid(12)}`;
    const now = nowIso();
    const metaJson = JSON.stringify(metadata ?? {});

    const db = getDb();
    const tx = db.transaction(() => {
      db.prepare(
        `INSERT INTO conversation_messages
           (id, conversation_id, sender_type, sender_id,
            message_type, content, image_url, metadata_json,
            created_at, read_at)
         VALUES (?, ?, 'system', NULL, 'system', ?, NULL, ?, ?, NULL)`,
      ).run(id, conv.id, trimmed, metaJson, now);

      db.prepare(
        `UPDATE conversations
            SET last_message_text = ?, last_message_at = ?, updated_at = ?
          WHERE id = ?`,
      ).run(`[系统] ${trimmed}`, now, now, conv.id);
    });
    tx();

    const created = db
      .prepare<[string], ConversationMessageRow>(
        'SELECT * FROM conversation_messages WHERE id = ?',
      )
      .get(id);
    if (!created) throw new Error('MESSAGE_INSERT_FAILED');
    return created;
  }

  /** 统计某一侧未读：仅对方主动发送的 text / image / emoji */
  countUnreadMessages(
    conversationId: string,
    forRole: 'employee' | 'merchant',
  ): number {
    const opponentSender = forRole === 'employee' ? 'merchant' : 'employee';
    const row = getDb()
      .prepare<[string, string], { c: number }>(
        `SELECT COUNT(*) AS c FROM conversation_messages
           WHERE conversation_id = ?
             AND read_at IS NULL
             AND sender_type = ?
             AND message_type IN ('text', 'image', 'emoji')`,
      )
      .get(conversationId, opponentSender);
    return row?.c ?? 0;
  }

  /** 按消息表重算未读计数（修正历史脏数据） */
  syncUnreadCounts(conv: ConversationRow): ConversationRow {
    const employeeUnread = this.countUnreadMessages(conv.id, 'employee');
    const merchantUnread = this.countUnreadMessages(conv.id, 'merchant');
    const now = nowIso();
    getDb()
      .prepare(
        `UPDATE conversations
            SET employee_unread_count = ?, merchant_unread_count = ?, updated_at = ?
          WHERE id = ?`,
      )
      .run(employeeUnread, merchantUnread, now, conv.id);
    return this.getById(conv.id)!;
  }

  /** 标记某一侧已读：仅标记对方用户消息，并重算未读 */
  markRead(conversationId: string, role: 'employee' | 'merchant'): ConversationRow {
    const conv = this.getById(conversationId);
    if (!conv) throw new Error('CONVERSATION_NOT_FOUND');
    const db = getDb();
    const now = nowIso();
    const opponentSender = role === 'employee' ? 'merchant' : 'employee';
    db.prepare(
      `UPDATE conversation_messages
          SET read_at = ?
        WHERE conversation_id = ?
          AND read_at IS NULL
          AND sender_type = ?
          AND message_type IN ('text', 'image', 'emoji')`,
    ).run(now, conversationId, opponentSender);
    return this.syncUnreadCounts(this.getById(conversationId)!);
  }

  // ---------- 权限 ----------

  /**
   * 判定当前用户对会话的访问角色。
   * - employee：必须是 conv.employee_id 本人
   * - merchant：必须绑定到 conv.merchant_id
   * - admin：放行（平台管理员）
   * - company_admin：暂不开放（返回 FORBIDDEN）
   * 其它情况抛 FORBIDDEN。
   */
  resolveAccess(
    user: UserRow,
    conv: ConversationRow,
  ): ConversationAccessContext {
    const scope = resolveAdminScope(user);
    if (scope.isPlatformAdmin) {
      return { conv, role: 'admin' };
    }
    if (user.role === 'employee') {
      if (conv.employee_id === user.id) {
        return { conv, role: 'employee' };
      }
      const orderUserId = this.orderUserId(conv.order_id);
      if (orderUserId && orderUserId === user.id) {
        const patched = this.ensureEmployeeId(conv, user.id);
        return { conv: patched, role: 'employee' };
      }
      throw new Error('FORBIDDEN');
    }
    if (scope.isMerchant) {
      if (scope.merchantId && scope.merchantId === conv.merchant_id) {
        return { conv, role: 'merchant' };
      }
      throw new Error('FORBIDDEN');
    }
    throw new Error('FORBIDDEN');
  }

  /** 历史会话可能缺少 employee_id，按订单归属回填 */
  private ensureEmployeeId(
    conv: ConversationRow,
    employeeId: string,
  ): ConversationRow {
    if (conv.employee_id === employeeId) return conv;
    if (!conv.employee_id) {
      const now = nowIso();
      getDb()
        .prepare(
          'UPDATE conversations SET employee_id = ?, updated_at = ? WHERE id = ?',
        )
        .run(employeeId, now, conv.id);
      return this.getById(conv.id) ?? { ...conv, employee_id: employeeId };
    }
    return conv;
  }

  private orderUserId(orderId: string): string | null {
    const row = getDb()
      .prepare<[string], { user_id: string | null }>(
        'SELECT user_id FROM orders WHERE id = ?',
      )
      .get(orderId);
    return row?.user_id ?? null;
  }
}

export const conversationService = new ConversationService();

// =============================================================
// 工具
// =============================================================

function previewText(
  content: string | null,
  imageUrl: string | null,
  type: ConversationMessageType,
): string {
  if (type === 'image' || imageUrl) return '[图片]';
  if (type === 'system') return content ? `[系统] ${content}` : '[系统消息]';
  return (content ?? '').slice(0, 80);
}

function systemTextForStatus(status: OrderStatus): string | null {
  switch (status) {
    case 'pendingMerchantConfirm':
      return null; // 创建订单时已写入"订单已提交"，状态本身不再额外写
    case 'pendingPayment':
      return null;
    case 'paymentSubmitted':
      return '顾客已上传付款截图，等待商家确认';
    case 'accepted':
      return '商家已接单';
    case 'delivering':
      return '订单正在配送中';
    case 'completed':
      return '订单已完成';
    case 'cancelled':
      return '订单已取消';
    default:
      return null;
  }
}
