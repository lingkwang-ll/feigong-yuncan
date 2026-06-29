export const MOCK_SMS_CODE = '123456';

export function isMockSmsProvider(): boolean {
  return (process.env.SMS_PROVIDER || 'mock').toLowerCase() === 'mock';
}

/**
 * 短信发送服务（mock / 阿里云）
 *
 * mock 模式：日志打印固定验证码，试运行不依赖真实短信
 * aliyun 模式：预留阿里云短信接入（需配置环境变量）
 */
export class SmsService {
  async sendVerificationCode(phone: string, code: string): Promise<void> {
    const provider = (process.env.SMS_PROVIDER || 'mock').toLowerCase();
    if (provider === 'mock') {
      this.sendMock(phone, code);
      return;
    }
    if (provider === 'aliyun') {
      await this.sendAliyun(phone, code);
      return;
    }
    throw new Error(`不支持的 SMS_PROVIDER: ${provider}`);
  }

  private sendMock(phone: string, code: string): void {
    console.log(`[SmsService][mock] phone=${phone} code=${code}`);
  }

  /** 预留阿里云短信接入 */
  private async sendAliyun(phone: string, code: string): Promise<void> {
    const accessKeyId = process.env.ALIYUN_SMS_ACCESS_KEY_ID;
    const accessKeySecret = process.env.ALIYUN_SMS_ACCESS_KEY_SECRET;
    const signName = process.env.ALIYUN_SMS_SIGN_NAME;
    const templateCode = process.env.ALIYUN_SMS_TEMPLATE_CODE;

    if (!accessKeyId || !accessKeySecret || !signName || !templateCode) {
      throw new Error('阿里云短信环境变量未完整配置');
    }

    // TODO: 接入 @alicloud/dysmsapi20170525
    // TemplateParam: JSON.stringify({ code })
    void phone;
    void code;
    void accessKeyId;
    void accessKeySecret;
    void signName;
    void templateCode;
    throw new Error('阿里云短信尚未接入，请使用 SMS_PROVIDER=mock');
  }
}

export const smsService = new SmsService();
