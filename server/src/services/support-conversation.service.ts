import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import {
  ALL_SUPPORT_MESSAGE_TYPES,
  SupportConversationRow,
  SupportConversationStatus,
  SupportMessageRow,
  SupportMessageType,
  SupportUserRole,
  UserRow,
} from '../models/types';
import { isAdminRole } from '../constants/roles';

function previewText(
  content: string | null,
  imageUrl: string | null,
  messageType: SupportMessageType,
): string {
  if (messageType === 'image' || imageUrl) return '[图片]';
  if (messageType === 'emoji') return content ?? '[表情]';
  const t = (content ?? '').trim();
  return t.length > 80 ? `${t.slice(0, 80)}…` : t;
}

export class SupportConversationService {
  getById(id: string): SupportConversationRow | undefined {
    return getDb()
      .prepare<[string], SupportConversationRow>(
        'SELECT * FROM support_conversations WHERE id = ?',
      )
      .get(id);
  }

  getByUser(userId: string, userRole: SupportUserRole): SupportConversationRow | undefined {
    return getDb()
      .prepare<[string, string], SupportConversationRow>(
        'SELECT * FROM support_conversations WHERE user_id = ? AND user_role = ?',
      )
      .get(userId, userRole);
  }

  resolveMerchantIdForUser(user: UserRow): string | null {
    if (user.role !== 'merchant') return null;
    const row = getDb()
      .prepare<[string], { id: string }>(
        'SELECT id FROM merchants WHERE user_id = ? LIMIT 1',
      )
      .get(user.id);
    return row?.id ?? null;
  }

  getOrCreateForUser(user: UserRow): SupportConversationRow {
    if (user.role !== 'employee' && user.role !== 'merchant') {
      throw new Error('INVALID_USER_ROLE');
    }
    const userRole: SupportUserRole = user.role;
    const existing = this.getByUser(user.id, userRole);
    if (existing) return existing;

    const now = nowIso();
    const id = `sup_${nanoid(10)}`;
    const merchantId =
      userRole === 'merchant' ? this.resolveMerchantIdForUser(user) : null;

    getDb()
      .prepare(
        `INSERT INTO support_conversations
           (id, user_id, user_role, merchant_id, title, status,
            last_message_text, last_message_at,
            user_unread_count, admin_unread_count,
            created_at, updated_at)
         VALUES (?, ?, ?, ?, '平台客服', 'open', NULL, NULL, 0, 0, ?, ?)`,
      )
      .run(id, user.id, userRole, merchantId, now, now);

    const created = this.getById(id);
    if (!created) throw new Error('SUPPORT_CONVERSATION_CREATE_FAILED');
    return created;
  }

  listForAdmin(): SupportConversationRow[] {
    return getDb()
      .prepare<[], SupportConversationRow>(
        `SELECT * FROM support_conversations
           ORDER BY admin_unread_count DESC,
                    COALESCE(last_message_at, created_at) DESC`,
      )
      .all();
  }

  adminUnreadTotal(): number {
    const row = getDb()
      .prepare<[], { total: number }>(
        `SELECT COALESCE(SUM(admin_unread_count), 0) AS total
           FROM support_conversations`,
      )
      .get();
    return row?.total ?? 0;
  }

  userUnreadTotal(userId: string, userRole: SupportUserRole): number {
    const conv = this.getByUser(userId, userRole);
    return conv?.user_unread_count ?? 0;
  }

  messages(conversationId: string, limit = 200): SupportMessageRow[] {
    const capped = Math.min(Math.max(limit, 1), 500);
    return getDb()
      .prepare<[string, number], SupportMessageRow>(
        `SELECT * FROM support_messages
           WHERE conversation_id = ?
           ORDER BY created_at ASC, id ASC
           LIMIT ?`,
      )
      .all(conversationId, capped);
  }

  sendUserMessage(input: {
    conversationId: string;
    user: UserRow;
    messageType: SupportMessageType;
    content?: string;
    imageUrl?: string;
  }): SupportMessageRow {
    if (!ALL_SUPPORT_MESSAGE_TYPES.includes(input.messageType)) {
      throw new Error('INVALID_MESSAGE_TYPE');
    }
    if (input.user.role !== 'employee' && input.user.role !== 'merchant') {
      throw new Error('INVALID_USER_ROLE');
    }
    const conv = this.getById(input.conversationId);
    if (!conv) throw new Error('CONVERSATION_NOT_FOUND');
    if (conv.user_id !== input.user.id) throw new Error('FORBIDDEN');

    const { content, imageUrl } = this.normalizePayload(
      input.messageType,
      input.content,
      input.imageUrl,
    );

    const id = `smsg_${nanoid(12)}`;
    const now = nowIso();
    const db = getDb();
    const tx = db.transaction(() => {
      db.prepare(
        `INSERT INTO support_messages
           (id, conversation_id, sender_type, sender_id,
            message_type, content, image_url, created_at, read_at)
         VALUES (?, ?, 'user', ?, ?, ?, ?, ?, NULL)`,
      ).run(
        id,
        conv.id,
        input.user.id,
        input.messageType,
        content,
        imageUrl,
        now,
      );

      const reopenStatus =
        conv.status === 'resolved' || conv.status === 'closed' ? 'open' : conv.status;

      db.prepare(
        `UPDATE support_conversations
            SET last_message_text = ?, last_message_at = ?, updated_at = ?,
                admin_unread_count = admin_unread_count + 1,
                user_unread_count = 0,
                status = ?
          WHERE id = ?`,
      ).run(
        previewText(content, imageUrl, input.messageType),
        now,
        now,
        reopenStatus,
        conv.id,
      );
    });
    tx();

    return db
      .prepare<[string], SupportMessageRow>(
        'SELECT * FROM support_messages WHERE id = ?',
      )
      .get(id)!;
  }

  sendAdminMessage(input: {
    conversationId: string;
    admin: UserRow;
    messageType: SupportMessageType;
    content?: string;
    imageUrl?: string;
  }): SupportMessageRow {
    if (!isAdminRole(input.admin.role)) {
      throw new Error('FORBIDDEN');
    }
    if (!ALL_SUPPORT_MESSAGE_TYPES.includes(input.messageType)) {
      throw new Error('INVALID_MESSAGE_TYPE');
    }
    const conv = this.getById(input.conversationId);
    if (!conv) throw new Error('CONVERSATION_NOT_FOUND');

    const { content, imageUrl } = this.normalizePayload(
      input.messageType,
      input.content,
      input.imageUrl,
    );

    const id = `smsg_${nanoid(12)}`;
    const now = nowIso();
    const db = getDb();
    const tx = db.transaction(() => {
      db.prepare(
        `INSERT INTO support_messages
           (id, conversation_id, sender_type, sender_id,
            message_type, content, image_url, created_at, read_at)
         VALUES (?, ?, 'admin', ?, ?, ?, ?, ?, NULL)`,
      ).run(
        id,
        conv.id,
        input.admin.id,
        input.messageType,
        content,
        imageUrl,
        now,
      );

      const nextStatus: SupportConversationStatus =
        conv.status === 'open' ? 'pending' : conv.status;

      db.prepare(
        `UPDATE support_conversations
            SET last_message_text = ?, last_message_at = ?, updated_at = ?,
                user_unread_count = user_unread_count + 1,
                admin_unread_count = 0,
                status = ?
          WHERE id = ?`,
      ).run(
        previewText(content, imageUrl, input.messageType),
        now,
        now,
        nextStatus,
        conv.id,
      );
    });
    tx();

    return db
      .prepare<[string], SupportMessageRow>(
        'SELECT * FROM support_messages WHERE id = ?',
      )
      .get(id)!;
  }

  markUserRead(conversationId: string, user: UserRow): SupportConversationRow {
    const conv = this.getById(conversationId);
    if (!conv) throw new Error('CONVERSATION_NOT_FOUND');
    if (conv.user_id !== user.id) throw new Error('FORBIDDEN');

    const now = nowIso();
    const db = getDb();
    db.prepare(
      `UPDATE support_messages
          SET read_at = ?
        WHERE conversation_id = ?
          AND read_at IS NULL
          AND sender_type = 'admin'
          AND message_type IN ('text', 'image', 'emoji')`,
    ).run(now, conversationId);
    db.prepare(
      `UPDATE support_conversations
          SET user_unread_count = 0, updated_at = ?
        WHERE id = ?`,
    ).run(now, conversationId);
    return this.getById(conversationId)!;
  }

  markAdminRead(conversationId: string): SupportConversationRow {
    const conv = this.getById(conversationId);
    if (!conv) throw new Error('CONVERSATION_NOT_FOUND');

    const now = nowIso();
    const db = getDb();
    db.prepare(
      `UPDATE support_messages
          SET read_at = ?
        WHERE conversation_id = ?
          AND read_at IS NULL
          AND sender_type = 'user'
          AND message_type IN ('text', 'image', 'emoji')`,
    ).run(now, conversationId);
    db.prepare(
      `UPDATE support_conversations
          SET admin_unread_count = 0, updated_at = ?
        WHERE id = ?`,
    ).run(now, conversationId);
    return this.getById(conversationId)!;
  }

  updateStatus(
    conversationId: string,
    status: SupportConversationStatus,
  ): SupportConversationRow {
    const allowed: SupportConversationStatus[] = [
      'open',
      'pending',
      'resolved',
      'closed',
    ];
    if (!allowed.includes(status)) throw new Error('INVALID_STATUS');
    const conv = this.getById(conversationId);
    if (!conv) throw new Error('CONVERSATION_NOT_FOUND');
    const now = nowIso();
    getDb()
      .prepare(
        `UPDATE support_conversations SET status = ?, updated_at = ? WHERE id = ?`,
      )
      .run(status, now, conversationId);
    return this.getById(conversationId)!;
  }

  assertUserAccess(user: UserRow, conv: SupportConversationRow): void {
    if (conv.user_id !== user.id) throw new Error('FORBIDDEN');
    if (user.role !== conv.user_role) throw new Error('FORBIDDEN');
  }

  private normalizePayload(
    messageType: SupportMessageType,
    content?: string,
    imageUrl?: string,
  ): { content: string | null; imageUrl: string | null } {
    if (messageType === 'system') throw new Error('SYSTEM_MESSAGE_NOT_ALLOWED');
    if (messageType === 'image') {
      const url = (imageUrl ?? '').trim();
      if (!url) throw new Error('IMAGE_URL_REQUIRED');
      return { content: null, imageUrl: url };
    }
    const text = (content ?? '').trim();
    if (!text) throw new Error('CONTENT_REQUIRED');
    if (text.length > 2000) throw new Error('CONTENT_TOO_LONG');
    return { content: text, imageUrl: null };
  }
}

export const supportConversationService = new SupportConversationService();
