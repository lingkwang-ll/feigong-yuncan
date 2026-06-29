import {
  OnlinePaymentEnabledDto,
  DEFAULT_ONLINE_PAYMENT_ENABLED,
} from '../models/types';
import {
  isProductionEnv,
  validateAlipayEnv,
  validateWechatPayEnv,
} from '../utils/payment-config.util';
import { systemConfigService } from './system-config.service';
import type { PaymentChannelInput } from './payment.service';

export interface PublicPaymentConfigDto {
  onlinePaymentEnabled: OnlinePaymentEnabledDto;
  /** 开关 + 商户配置均就绪，客户端可展示并发起真实支付 */
  wechatAvailable: boolean;
  alipayAvailable: boolean;
  manualQrAvailable: boolean;
  wechatConfigured: boolean;
  alipayConfigured: boolean;
  hints: {
    wechat: string;
    alipay: string;
    manualQr: string;
  };
}

const HINT_NOT_ENABLED = '暂未开通，请使用付款截图';
const HINT_MANUAL_QR = '上传付款截图，商家确认后订单生效';

export class PaymentConfigService {
  getSwitches(): OnlinePaymentEnabledDto {
    const settings = systemConfigService.getAppSettings();
    return {
      ...DEFAULT_ONLINE_PAYMENT_ENABLED,
      ...settings.onlinePaymentEnabled,
    };
  }

  isWechatEnvConfigured(): boolean {
    return validateWechatPayEnv().ok;
  }

  isAlipayEnvConfigured(): boolean {
    return validateAlipayEnv().ok;
  }

  /** 开关开启且 env 配置齐全 */
  isWechatPayReady(): boolean {
    const sw = this.getSwitches();
    return sw.wechat && this.isWechatEnvConfigured();
  }

  isAlipayPayReady(): boolean {
    const sw = this.getSwitches();
    return sw.alipay && this.isAlipayEnvConfigured();
  }

  isManualQrEnabled(): boolean {
    return this.getSwitches().manualQr;
  }

  /**
   * 是否允许创建该渠道支付单。
   * 开发环境允许 wechat/alipay + mock-paid E2E；生产环境严格校验开关与配置。
   */
  isCreateAllowed(channel: PaymentChannelInput): boolean {
    const sw = this.getSwitches();
    if (channel === 'manual_qr') return sw.manualQr;
    if (channel === 'wechat_pay') {
      if (!isProductionEnv()) return true;
      return this.isWechatPayReady();
    }
    if (channel === 'alipay') {
      if (!isProductionEnv()) return true;
      return this.isAlipayPayReady();
    }
    return false;
  }

  /** 生产环境禁止返回 mock 参数 */
  shouldUseMockPayParams(channel: 'wechat_pay' | 'alipay'): boolean {
    if (isProductionEnv()) return false;
    if (channel === 'wechat_pay' && this.isWechatPayReady()) return false;
    if (channel === 'alipay' && this.isAlipayPayReady()) return false;
    return true;
  }

  getPublicConfig(): PublicPaymentConfigDto {
    const sw = this.getSwitches();
    const wechatConfigured = this.isWechatEnvConfigured();
    const alipayConfigured = this.isAlipayEnvConfigured();
    return {
      onlinePaymentEnabled: sw,
      wechatAvailable: this.isWechatPayReady(),
      alipayAvailable: this.isAlipayPayReady(),
      manualQrAvailable: sw.manualQr,
      wechatConfigured,
      alipayConfigured,
      hints: {
        wechat: sw.wechat && wechatConfigured
          ? '微信支付'
          : HINT_NOT_ENABLED,
        alipay: sw.alipay && alipayConfigured
          ? '支付宝'
          : HINT_NOT_ENABLED,
        manualQr: sw.manualQr ? HINT_MANUAL_QR : HINT_NOT_ENABLED,
      },
    };
  }

  /** 启动时打印支付配置摘要（不输出密钥内容） */
  logStartupChecks(): void {
    const sw = this.getSwitches();
    const wechat = validateWechatPayEnv();
    const alipay = validateAlipayEnv();
    const prod = isProductionEnv();

    // eslint-disable-next-line no-console
    console.log('[payment-config] NODE_ENV=%s', process.env.NODE_ENV || 'development');
    // eslint-disable-next-line no-console
    console.log(
      '[payment-config] switches: manualQr=%s wechat=%s alipay=%s',
      sw.manualQr,
      sw.wechat,
      sw.alipay,
    );

    if (sw.wechat) {
      const msg = wechat.ok
        ? '微信支付 env 配置齐全'
        : `微信支付已开启但配置缺失: ${wechat.missing.join(', ')}`;
      if (!wechat.ok && prod) console.error('[payment-config] ERROR:', msg);
      else if (!wechat.ok) console.warn('[payment-config] WARN:', msg);
      else console.log('[payment-config]', msg);
    }

    if (sw.alipay) {
      const msg = alipay.ok
        ? '支付宝 env 配置齐全'
        : `支付宝已开启但配置缺失: ${alipay.missing.join(', ')}`;
      if (!alipay.ok && prod) console.error('[payment-config] ERROR:', msg);
      else if (!alipay.ok) console.warn('[payment-config] WARN:', msg);
      else console.log('[payment-config]', msg);
    }

    if (prod) {
      // eslint-disable-next-line no-console
      console.log('[payment-config] 生产环境 mock-paid 已禁用');
    }
  }
}

export const paymentConfigService = new PaymentConfigService();
