/** 上海时区日期 YYYY-MM-DD */
export function shanghaiDateString(d = new Date()): string {
  return d.toLocaleDateString('en-CA', { timeZone: 'Asia/Shanghai' });
}
