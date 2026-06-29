import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso, parseJsonArray } from '../models/mappers';
import { ReviewListFilter, ReviewRow } from '../models/types';
import { resolveEmployeeContext } from '../utils/employee-context.util';
import { merchantCreditService } from './merchant-credit.service';
import { orderService } from './order.service';
import { systemConfigService } from './system-config.service';

export interface CreateReviewInput {
  orderId: string;
  userId: string;
  /** @deprecated 使用 overallRating */
  rating?: number;
  overallRating?: number;
  tasteRating?: number;
  hygieneRating?: number;
  serviceRating?: number;
  deliveryRating?: number;
  content?: string;
  images?: string[];
  isAnonymous?: boolean;
}

export interface ReviewListRow extends ReviewRow {
  order_no?: string | null;
  employee_name?: string | null;
  department_name?: string | null;
}

function parseRating(v: unknown): number | null {
  if (v == null || v === '') return null;
  const n = Math.floor(Number(v));
  if (!Number.isFinite(n) || n < 1 || n > 5) return null;
  return n;
}

function clampOptionalRating(v: unknown, fallback: number): number {
  const parsed = parseRating(v);
  return parsed ?? fallback;
}

function isValidReviewImageUrl(url: string): boolean {
  const u = url.trim();
  if (!u) return false;
  const lower = u.toLowerCase();
  if (
    lower.startsWith('local://') ||
    lower.startsWith('blob:') ||
    lower.startsWith('file://')
  ) {
    return false;
  }
  return (
    lower.startsWith('http://') ||
    lower.startsWith('https://') ||
    lower.startsWith('/uploads/')
  );
}

export class ReviewService {
  getByOrderId(orderId: string): ReviewRow | undefined {
    return getDb()
      .prepare<[string], ReviewRow>('SELECT * FROM reviews WHERE order_id = ?')
      .get(orderId);
  }

  listByMerchant(merchantId: string, limit = 50): ReviewRow[] {
    return getDb()
      .prepare<[string, number], ReviewRow>(
        `SELECT * FROM reviews WHERE merchant_id = ? ORDER BY created_at DESC LIMIT ?`,
      )
      .all(merchantId, limit);
  }

  listForMerchant(
    merchantId: string,
    options?: { filter?: ReviewListFilter; limit?: number },
  ): ReviewListRow[] {
    const filter = options?.filter ?? 'all';
    const limit = options?.limit ?? 100;
    let sql = `
      SELECT r.*, o.order_no, ep.employee_name, ep.department_name
      FROM reviews r
      LEFT JOIN orders o ON o.id = r.order_id
      LEFT JOIN employee_profiles ep ON ep.user_id = r.user_id
      WHERE r.merchant_id = ?
    `;
    const params: unknown[] = [merchantId];

    if (filter === 'good') {
      sql += ' AND COALESCE(r.overall_rating, r.rating) >= 4';
    } else if (filter === 'medium') {
      sql += ' AND COALESCE(r.overall_rating, r.rating) = 3';
    } else if (filter === 'bad') {
      sql += ' AND COALESCE(r.overall_rating, r.rating) <= 2';
    } else if (filter === 'with_images') {
      sql += " AND r.images_json IS NOT NULL AND r.images_json NOT IN ('[]', '')";
    }

    sql += ' ORDER BY r.created_at DESC LIMIT ?';
    params.push(limit);

    return getDb()
      .prepare(sql)
      .all(...params) as ReviewListRow[];
  }

  resolveDisplayName(
    row: ReviewRow | ReviewListRow,
    viewer: 'merchant' | 'employee' | 'admin',
  ): { displayUserName: string; departmentName: string } {
    const isAnonymous = !!row.is_anonymous;
    const listRow = row as ReviewListRow;
    const ctx = resolveEmployeeContext({ userId: row.user_id });
    const name =
      listRow.employee_name?.trim() ||
      ctx.employeeName ||
      '员工';
    const dept =
      listRow.department_name?.trim() ||
      ctx.departmentName ||
      '';

    if (isAnonymous && viewer === 'merchant') {
      return { displayUserName: '匿名用户', departmentName: '' };
    }
    if (isAnonymous && viewer === 'employee') {
      return { displayUserName: '匿名用户', departmentName: '' };
    }
    return { displayUserName: name, departmentName: dept };
  }

  create(input: CreateReviewInput): ReviewRow {
    const settings = systemConfigService.getAppSettings();
    if (!settings.enableReview) {
      throw new Error('REVIEW_DISABLED');
    }

    const overallParsed = parseRating(
      input.overallRating != null ? input.overallRating : input.rating,
    );
    if (overallParsed == null) throw new Error('INVALID_RATING');
    const overallRating = overallParsed;

    const hygieneParsed = parseRating(input.hygieneRating);
    if (input.hygieneRating != null) {
      if (hygieneParsed == null) throw new Error('INVALID_HYGIENE_RATING');
    }
    const hygieneRating = hygieneParsed ?? overallRating;

    const tasteRating = clampOptionalRating(input.tasteRating, overallRating);
    const serviceRating = clampOptionalRating(input.serviceRating, overallRating);
    const deliveryRating = clampOptionalRating(
      input.deliveryRating,
      overallRating,
    );

    const images = (input.images ?? []).filter(
      (u) => typeof u === 'string' && u.trim().length > 0,
    );
    if (images.length > 9) {
      throw new Error('INVALID_IMAGE_COUNT');
    }
    for (const url of images) {
      if (!isValidReviewImageUrl(url)) {
        throw new Error('INVALID_IMAGE_URL');
      }
    }

    const order = orderService.getById(input.orderId);
    if (!order) throw new Error('ORDER_NOT_FOUND');
    if (order.status !== 'completed') {
      throw new Error('ORDER_NOT_COMPLETED');
    }
    if (order.user_id !== input.userId) {
      throw new Error('FORBIDDEN');
    }

    const existing = this.getByOrderId(input.orderId);
    if (existing) throw new Error('REVIEW_ALREADY_EXISTS');

    const id = `R${nanoid(10)}`;
    const now = nowIso();
    const isAnonymous = input.isAnonymous === true ? 1 : 0;
    const db = getDb();
    db.prepare(
      `INSERT INTO reviews
         (id, order_id, merchant_id, user_id, rating, overall_rating,
          taste_rating, hygiene_rating, service_rating, delivery_rating,
          content, images_json, is_anonymous, created_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).run(
      id,
      input.orderId,
      order.merchant_id,
      input.userId,
      overallRating,
      overallRating,
      tasteRating,
      hygieneRating,
      serviceRating,
      deliveryRating,
      (input.content ?? '').trim(),
      JSON.stringify(images),
      isAnonymous,
      now,
    );

    const row = this.getByOrderId(input.orderId)!;
    merchantCreditService.applyReviewImpact(order.merchant_id, hygieneRating);
    return row;
  }

  imagesOf(row: ReviewRow): string[] {
    return parseJsonArray<string>(row.images_json);
  }
}

export const reviewService = new ReviewService();
