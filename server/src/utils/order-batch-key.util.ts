/** 企业订餐汇总单维度 key：date + mealType + merchantId */
export function buildOrderBatchKey(
  date: string,
  mealType: string,
  merchantId: string,
): string {
  return `${date}_${mealType}_${merchantId}`;
}
