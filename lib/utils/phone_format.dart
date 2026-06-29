/// 中国大陆手机号格式校验（11 位）
bool isValidPhoneFormat(String phone) {
  final normalized = phone.replaceAll(RegExp(r'\s'), '');
  return RegExp(r'^1[3-9]\d{9}$').hasMatch(normalized);
}
