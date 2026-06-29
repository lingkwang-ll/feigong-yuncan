import '../models/order_model.dart';

bool canTrackDelivery(Order order) {
  return order.status == OrderStatus.accepted ||
      order.status == OrderStatus.delivering ||
      order.status == OrderStatus.completed;
}

String settlementStatusLabel(String status) {
  switch (status) {
    case 'not_paid':
      return '未支付';
    case 'paid_to_platform':
      return '平台已收款，待履约';
    case 'in_service':
      return '履约中';
    case 'completed_pending_settlement':
      return '已完成，待结算';
    case 'settlement_pending':
      return '结算等待中';
    case 'settled':
      return '已结算给商家';
    case 'refund_pending':
      return '退款处理中';
    case 'refunded':
      return '已退款';
    case 'settlement_blocked':
      return '结算冻结';
    default:
      return status;
  }
}

String paymentChannelLabel(String channel) {
  switch (channel) {
    case 'wechat_pay':
      return '微信支付';
    case 'alipay':
      return '支付宝';
    case 'manual_qr':
      return '付款截图';
    case 'company_pay':
      return '企业代付';
    case 'mixed_pay':
      return '混合支付';
    default:
      return channel;
  }
}

String manualPayChannelLabel(String? channel) {
  switch (channel) {
    case 'wechat':
      return '微信截图';
    case 'alipay':
      return '支付宝截图';
    default:
      return '付款截图';
  }
}

bool orderHasSettlementInfo(Order order) {
  return order.settlementStatus != 'not_paid' ||
      order.paymentChannel != 'manual_qr';
}
