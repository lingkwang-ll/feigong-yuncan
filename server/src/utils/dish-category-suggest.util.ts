import { DishCategory } from '../models/types';

const MEAT_HINTS = ['鸡', '鸭', '鱼', '肉', '牛', '羊', '排骨', '虾', '蛋'];
const VEG_HINTS = ['青菜', '白菜', '土豆', '茄子', '豆腐', '韭黄', '素'];

export interface CategorySuggestion {
  suggestedCategory: DishCategory | null;
  reason: string | null;
}

/**
 * 根据菜品名称与加菜价给出分类建议（仅提示，不自动落库）。
 */
export function suggestDishCategory(
  name: string,
  extraPrice = 0,
): CategorySuggestion {
  if (extraPrice > 0) {
    return {
      suggestedCategory: 'extra',
      reason: 'extraPrice > 0，建议归为加菜',
    };
  }
  const n = (name ?? '').trim();
  if (!n) {
    return { suggestedCategory: null, reason: '菜名为空，无法自动建议' };
  }
  if (MEAT_HINTS.some((h) => n.includes(h))) {
    return {
      suggestedCategory: 'meat',
      reason: `菜名含荤菜关键词（${MEAT_HINTS.filter((h) => n.includes(h)).join('、')}）`,
    };
  }
  if (VEG_HINTS.some((h) => n.includes(h))) {
    return {
      suggestedCategory: 'vegetable',
      reason: `菜名含素菜关键词（${VEG_HINTS.filter((h) => n.includes(h)).join('、')}）`,
    };
  }
  return { suggestedCategory: null, reason: '无法根据名称判断，请手动选择分类' };
}
