import { nanoid } from 'nanoid';
import { getDb } from '../db/database';
import { nowIso } from '../models/mappers';
import { MerchantHygieneStatsDto } from '../models/types';

const GRADE_ORDER = ['S', 'A', 'B', 'C', 'D'] as const;

function gradeFromHygieneAvg(avg: number): string {
  if (avg >= 4.8) return 'S';
  if (avg >= 4.5) return 'A';
  if (avg >= 4.0) return 'B';
  if (avg >= 3.0) return 'C';
  return 'D';
}

function gradeLabel(grade: string): string {
  switch (grade) {
    case 'S':
      return '极优';
    case 'A':
      return '优秀';
    case 'B':
      return '良好';
    case 'C':
      return '需关注';
    case 'D':
      return '需整改';
    default:
      return '暂无足够评价';
  }
}

function downgradeGrade(current: string): string {
  const idx = GRADE_ORDER.indexOf(current as (typeof GRADE_ORDER)[number]);
  const base = idx >= 0 ? idx : GRADE_ORDER.length - 1;
  return GRADE_ORDER[Math.min(base + 1, GRADE_ORDER.length - 1)];
}

function hygieneRatingOf(row: {
  hygiene_rating?: number | null;
  rating: number;
}): number {
  const h = row.hygiene_rating;
  if (typeof h === 'number' && h >= 1 && h <= 5) return h;
  return row.rating;
}

export class MerchantCreditService {
  /** 计算卫生均分：近30天>=10条用30天，否则用全部；不足5条返回 null */
  computeHygieneAverage(merchantId: string): {
    hygieneAvg: number | null;
    hygieneAvg30d: number | null;
    count: number;
    count30d: number;
    overallAvg: number | null;
  } {
    const db = getDb();
    const all = db
      .prepare<[string], { hygiene_rating: number | null; rating: number }>(
        `SELECT hygiene_rating, rating FROM reviews WHERE merchant_id = ?`,
      )
      .all(merchantId);
    const recent30 = db
      .prepare<[string], { hygiene_rating: number | null; rating: number }>(
        `SELECT hygiene_rating, rating FROM reviews
         WHERE merchant_id = ?
           AND datetime(created_at) >= datetime('now', '-30 days')`,
      )
      .all(merchantId);

    const count = all.length;
    const count30d = recent30.length;
    const avgOf = (rows: { hygiene_rating: number | null; rating: number }[]) => {
      if (rows.length === 0) return null;
      const sum = rows.reduce((s, r) => s + hygieneRatingOf(r), 0);
      return Number((sum / rows.length).toFixed(2));
    };

    const hygieneAvg30d = avgOf(recent30);
    const hygieneAvg =
      count30d >= 10 ? hygieneAvg30d : count >= 5 ? avgOf(all) : null;

    const overallRow = db
      .prepare<[string], { avg: number | null }>(
        `SELECT AVG(COALESCE(overall_rating, rating)) AS avg FROM reviews WHERE merchant_id = ?`,
      )
      .get(merchantId);
    const overallAvg =
      count >= 5 && overallRow?.avg != null
        ? Number(Number(overallRow.avg).toFixed(2))
        : null;

    return {
      hygieneAvg,
      hygieneAvg30d,
      count,
      count30d,
      overallAvg,
    };
  }

  recalculateMerchantRating(merchantId: string): MerchantHygieneStatsDto {
    const db = getDb();
    const stats = this.computeHygieneAverage(merchantId);
    const { count, hygieneAvg, hygieneAvg30d, overallAvg } = stats;

    let grade = '—';
    let riskStatus: MerchantHygieneStatsDto['riskStatus'] = 'insufficient';
    let needsRemediation = false;

    if (hygieneAvg != null && count >= 5) {
      grade = gradeFromHygieneAvg(hygieneAvg);
      riskStatus = 'normal';
      needsRemediation = hygieneAvg < 3.0;
    }

    db.prepare(
      `UPDATE merchants SET
         rating = ?,
         hygiene_grade = ?,
         hygiene_score = ?,
         hygiene_review_count = ?,
         hygiene_score_30d = ?,
         hygiene_risk_status = ?,
         updated_at = ?
       WHERE id = ?`,
    ).run(
      overallAvg ?? 0,
      grade,
      hygieneAvg,
      count,
      hygieneAvg30d,
      riskStatus,
      nowIso(),
      merchantId,
    );

    return {
      hygieneGrade: grade,
      hygieneScore: hygieneAvg,
      hygieneScore30d: hygieneAvg30d,
      reviewCount: count,
      overallRating: count >= 5 ? overallAvg : null,
      riskStatus,
      needsRemediation,
      gradeLabel: gradeLabel(grade),
    };
  }

  private createRemediationNotice(
    merchantId: string,
    reason: string,
    hygieneAvg: number | null,
  ): void {
    const db = getDb();
    const id = `RN${nanoid(10)}`;
    const now = nowIso();
    db.prepare(
      `INSERT INTO merchant_remediation_notices
         (id, merchant_id, reason, hygiene_avg, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, 'open', ?, ?)`,
    ).run(id, merchantId, reason, hygieneAvg, now, now);
  }

  applyReviewImpact(merchantId: string, latestHygieneRating: number): void {
    const stats = this.recalculateMerchantRating(merchantId);
    const db = getDb();
    const { hygieneScore, reviewCount } = stats;

    if (hygieneScore != null && hygieneScore < 3.0) {
      this.createRemediationNotice(
        merchantId,
        `卫生评分 ${hygieneScore} 低于 3.0，需整改`,
        hygieneScore,
      );
      db.prepare(
        `UPDATE merchants SET hygiene_risk_status = 'remediation', updated_at = ? WHERE id = ?`,
      ).run(nowIso(), merchantId);
    }

    const recentHygiene = db
      .prepare(
        `SELECT COALESCE(hygiene_rating, rating) AS h FROM reviews
         WHERE merchant_id = ? ORDER BY created_at DESC LIMIT 3`,
      )
      .all(merchantId) as { h: number }[];
    const consecutiveLowHygiene =
      recentHygiene.length >= 3 && recentHygiene.every((r) => r.h <= 2);
    if (consecutiveLowHygiene) {
      const merchant = db
        .prepare<[string], { hygiene_grade: string }>(
          'SELECT hygiene_grade FROM merchants WHERE id = ?',
        )
        .get(merchantId);
      const downgraded = downgradeGrade(merchant?.hygiene_grade ?? 'C');
      db.prepare(
        `UPDATE merchants SET hygiene_grade = ?, hygiene_risk_status = 'remediation', updated_at = ? WHERE id = ?`,
      ).run(downgraded, nowIso(), merchantId);
      this.createRemediationNotice(
        merchantId,
        '连续 3 条卫生评分 ≤2，卫生风险升级',
        hygieneScore,
      );
    }

    if (
      hygieneScore != null &&
      hygieneScore < 2.5 &&
      reviewCount >= 5
    ) {
      db.prepare(
        `UPDATE merchants SET is_open = 0, hygiene_risk_status = 'suspended', updated_at = ? WHERE id = ?`,
      ).run(nowIso(), merchantId);
      this.createRemediationNotice(
        merchantId,
        `卫生评分 ${hygieneScore} < 2.5 且评价数 ≥5，已暂停接单`,
        hygieneScore,
      );
    }

    if (latestHygieneRating <= 2 && hygieneScore != null && hygieneScore < 3.5) {
      console.warn(
        `[merchant-credit] 商家 ${merchantId} 收到低卫生评价 ${latestHygieneRating}`,
      );
    }
  }

  getHygieneStats(merchantId: string): MerchantHygieneStatsDto {
    const db = getDb();
    const m = db
      .prepare<
        [string],
        {
          rating: number;
          hygiene_grade: string;
          hygiene_score: number | null;
          hygiene_review_count: number;
          hygiene_score_30d: number | null;
          hygiene_risk_status: string;
        }
      >(
        `SELECT rating, hygiene_grade, hygiene_score, hygiene_review_count,
                hygiene_score_30d, hygiene_risk_status
         FROM merchants WHERE id = ?`,
      )
      .get(merchantId);
    if (!m) {
      return {
        hygieneGrade: '—',
        hygieneScore: null,
        hygieneScore30d: null,
        reviewCount: 0,
        overallRating: null,
        riskStatus: 'insufficient',
        needsRemediation: false,
        gradeLabel: '暂无足够评价',
      };
    }
    const hygieneAvg = m.hygiene_score;
    const reviewCount = m.hygiene_review_count ?? 0;
    const needsRemediation =
      hygieneAvg != null ? hygieneAvg < 3.0 : false;
    const insufficient = reviewCount < 5;
    return {
      hygieneGrade: insufficient ? '—' : (m.hygiene_grade ?? '—'),
      hygieneScore: insufficient ? null : m.hygiene_score,
      hygieneScore30d: m.hygiene_score_30d,
      reviewCount,
      overallRating:
        insufficient || m.rating == null ? null : Number(m.rating),
      riskStatus:
        (m.hygiene_risk_status as MerchantHygieneStatsDto['riskStatus']) ??
        'normal',
      needsRemediation,
      gradeLabel: insufficient
        ? '暂无足够评价'
        : gradeLabel(m.hygiene_grade ?? '—'),
    };
  }

  listRemediationNotices(merchantId: string, limit = 20) {
    return getDb()
      .prepare(
        `SELECT * FROM merchant_remediation_notices
         WHERE merchant_id = ? ORDER BY created_at DESC LIMIT ?`,
      )
      .all(merchantId, limit);
  }

  listLowHygieneReviews(merchantId: string, limit = 10) {
    return getDb()
      .prepare(
        `SELECT * FROM reviews
         WHERE merchant_id = ? AND COALESCE(hygiene_rating, rating) <= 3
         ORDER BY created_at DESC LIMIT ?`,
      )
      .all(merchantId, limit);
  }
}

export const merchantCreditService = new MerchantCreditService();
