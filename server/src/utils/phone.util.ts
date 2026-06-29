export function normalizePhone(phone: string): string {
  return phone.replace(/\s/g, '');
}

export function isValidPhone(phone: string): boolean {
  return /^1[3-9]\d{9}$/.test(normalizePhone(phone));
}
