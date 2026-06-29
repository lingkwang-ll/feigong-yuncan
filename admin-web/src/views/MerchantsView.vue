<template>
  <div class="page-card">
    <h2 class="page-title">商家管理</h2>

    <el-tabs v-model="activeTab" @tab-change="onTabChange">
      <el-tab-pane label="入驻审核" name="pending" />
      <el-tab-pane label="已入驻商家" name="approved" />
    </el-tabs>

    <div class="toolbar">
      <el-button
        v-if="!auth.isMerchant && activeTab === 'approved'"
        type="primary"
        @click="openCreate"
      >新增商家</el-button>
      <el-select
        v-if="activeTab === 'pending'"
        v-model="statusFilter"
        placeholder="审核状态"
        clearable
        @change="load"
        style="width: 140px"
      >
        <el-option label="待审核" value="pending" />
        <el-option label="已拒绝" value="rejected" />
      </el-select>
    </div>

    <el-table :data="list" v-loading="loading" stripe>
      <el-table-column prop="merchantName" label="商家名称" min-width="120" />
      <el-table-column prop="contactName" label="联系人" width="100" />
      <el-table-column prop="contactPhone" label="联系电话" width="130">
        <template #default="{ row }">{{ row.contactPhone || row.phone }}</template>
      </el-table-column>
      <el-table-column prop="address" label="地址" min-width="140" show-overflow-tooltip />
      <el-table-column v-if="activeTab === 'pending'" label="支持餐段" width="160">
        <template #default="{ row }">{{ formatMeals(row.supportedMealTypes) }}</template>
      </el-table-column>
      <el-table-column v-if="activeTab === 'pending'" prop="status" label="审核状态" width="100">
        <template #default="{ row }">
          <el-tag :type="statusTag(row.status)">{{ statusLabel(row.status) }}</el-tag>
        </template>
      </el-table-column>
      <el-table-column v-if="activeTab === 'pending'" prop="createdAt" label="提交时间" width="170" />
      <el-table-column v-if="activeTab === 'approved'" label="营业状态" width="100">
        <template #default="{ row }">{{ row.isOpen ? '营业中' : '休息中' }}</template>
      </el-table-column>
      <el-table-column v-if="activeTab === 'approved'" label="启用" width="80">
        <template #default="{ row }">{{ row.isEnabled ? '是' : '否' }}</template>
      </el-table-column>
      <el-table-column v-if="activeTab === 'approved'" label="支持餐段" width="160">
        <template #default="{ row }">{{ formatMeals(row.supportedMealTypes) }}</template>
      </el-table-column>
      <el-table-column prop="companyId" label="所属企业" width="120" />
      <el-table-column label="操作" :width="activeTab === 'pending' ? 260 : 360" fixed="right">
        <template #default="{ row }">
          <template v-if="activeTab === 'pending'">
            <el-button link type="primary" @click="openDetail(row)">查看详情</el-button>
            <template v-if="row.status === 'pending' && !auth.isMerchant">
              <el-button link type="success" @click="review(row, 'approved')">通过</el-button>
              <el-button link type="danger" @click="openReject(row)">驳回</el-button>
            </template>
          </template>
          <template v-else>
            <el-button v-if="!auth.isMerchant" link @click="openEdit(row)">编辑</el-button>
            <el-button link @click="toggleEnabled(row)">{{ row.isEnabled ? '停用' : '启用' }}</el-button>
            <el-button link @click="toggleOpen(row)">{{ row.isOpen ? '休息' : '营业' }}</el-button>
            <el-button link type="primary" @click="editQr(row)">收款码</el-button>
            <el-button link @click="$router.push({ path: '/dishes', query: { merchantId: row.id } })">菜品</el-button>
            <el-button link @click="goSummary(row)">汇总</el-button>
            <el-button v-if="!auth.isMerchant" link type="primary" @click="openHygiene(row)">卫生评分</el-button>
            <el-button v-if="!auth.isMerchant" link @click="resetMerchantPassword(row)">重置密码</el-button>
          </template>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="formVisible" :title="form.id ? '编辑商家' : '新增商家'" width="520px">
      <el-form label-width="100px">
        <el-form-item v-if="auth.isPlatformAdmin" label="所属企业">
          <el-select v-model="form.companyId" filterable style="width: 100%">
            <el-option v-for="c in companies" :key="c.id" :label="c.name" :value="c.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="商家名称"><el-input v-model="form.merchantName" /></el-form-item>
        <el-form-item label="地址"><el-input v-model="form.address" /></el-form-item>
        <el-form-item label="联系电话"><el-input v-model="form.phone" /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="formVisible = false">取消</el-button>
        <el-button type="primary" @click="saveMerchant">保存</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="qrVisible" title="收款码" width="460px">
      <div v-if="qrForm.paymentQr && isImageUrl(qrForm.paymentQr)" class="qr-preview">
        <el-image
          :src="fullImageUrl(qrForm.paymentQr)"
          :preview-src-list="[fullImageUrl(qrForm.paymentQr)]"
          fit="contain"
          preview-teleported
          class="qr-thumb"
        />
      </div>
      <div v-else-if="qrForm.paymentQr" class="qr-preview">{{ qrForm.paymentQr }}</div>
      <el-input v-model="qrForm.paymentQr" placeholder="收款码 URL" class="qr-input" />
      <el-upload :show-file-list="false" :http-request="uploadQr" accept="image/*">
        <el-button type="primary" plain>上传图片</el-button>
      </el-upload>
      <template #footer>
        <el-button @click="qrVisible = false">取消</el-button>
        <el-button type="primary" @click="saveQr">保存</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="detailVisible" title="入驻详情" width="780px">
      <div v-if="detail" class="detail-grid">
        <h4>基础信息</h4>
        <p>店铺显示名称：{{ orDash(detail.storeDisplayName || detail.shortName || detail.merchantName) }}</p>
        <p>联系人：{{ orDash(detail.contactName) }}</p>
        <p>联系电话：{{ orDash(detail.contactPhone || detail.phone) }}</p>
        <p>客服电话：{{ orDash(detail.customerServicePhone) }}</p>
        <p>店铺地址：{{ orDash(detail.address) }}</p>

        <h4>经营信息</h4>
        <p>支持餐段：{{ formatMeals(detail.supportedMealTypes) }}</p>
        <p>配送方式：{{ formatDeliveryModes(detail.deliveryModes) }}</p>
        <p>营业日：{{ formatBusinessDays(detail.businessDays) }}</p>
        <p>营业时间：{{ formatHoursRange(detail.businessHoursStart, detail.businessHoursEnd) }}</p>
        <p>早餐截止时间：{{ orDash(deadlineOf(detail, 'breakfast')) }}</p>
        <p>中餐截止时间：{{ orDash(deadlineOf(detail, 'lunch')) }}</p>
        <p>晚餐截止时间：{{ orDash(deadlineOf(detail, 'dinner')) }}</p>
        <p>加班餐截止时间：{{ orDash(deadlineOf(detail, 'overtime')) }}</p>

        <h4>收款信息</h4>
        <p>收款方式：{{ formatPaymentMethods(resolvePaymentMethods(detail)) }}</p>
        <p>收款人姓名：{{ orDash(detail.paymentReceiverName) }}</p>
        <QualificationImageList
          v-if="hasPaymentMethod(detail, 'wechat')"
          label="微信收款码"
          :urls="detail.wechatPaymentQrUrls"
          :fallback="detail.paymentQrCodeUrl || detail.paymentQr"
        />
        <QualificationImageList
          v-if="hasPaymentMethod(detail, 'alipay')"
          label="支付宝收款码"
          :urls="detail.alipayPaymentQrUrls"
        />

        <h4>资质信息</h4>
        <QualificationImageList
          label="营业执照"
          :urls="detail.businessLicenseUrls"
          :fallback="detail.businessLicenseUrl"
        />
        <QualificationImageList
          label="食品经营许可证"
          :urls="detail.foodLicenseUrls"
          :fallback="detail.foodLicenseUrl"
        />
        <QualificationImageList
          label="后厨/操作间照片"
          :urls="detail.kitchenPhotoUrls"
          :fallback="detail.kitchenPhotoUrl"
        />
        <QualificationImageList
          label="健康证"
          :urls="detail.healthCertificateUrls"
          :fallback="detail.healthCertificateUrl"
        />
        <QualificationImageList
          label="门店照片"
          :urls="detail.storePhotoUrls"
          :fallback="detail.storePhotoUrl"
        />
        <p>备注：{{ orDash(detail.remark) }}</p>
        <p v-if="detail.rejectReason" class="reject-note">上次驳回原因：{{ detail.rejectReason }}</p>
      </div>
      <template #footer>
        <el-button @click="detailVisible = false">关闭</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="rejectVisible" title="驳回入驻申请" width="480px">
      <el-input
        v-model="rejectReason"
        type="textarea"
        :rows="4"
        placeholder="请填写驳回原因（必填）"
      />
      <template #footer>
        <el-button @click="rejectVisible = false">取消</el-button>
        <el-button type="danger" @click="confirmReject">确认驳回</el-button>
      </template>
    </el-dialog>

    <el-dialog v-model="hygieneVisible" title="商家卫生与评价" width="720px">
      <div v-if="hygieneLoading" v-loading="true" style="min-height: 120px" />
      <div v-else-if="hygieneData">
        <el-descriptions :column="2" border size="small">
          <el-descriptions-item label="卫生等级">{{ hygieneData.stats?.hygieneGrade || '—' }}</el-descriptions-item>
          <el-descriptions-item label="卫生评分">{{ hygieneData.stats?.hygieneScore ?? '—' }}</el-descriptions-item>
          <el-descriptions-item label="平均评分">{{ hygieneData.stats?.overallRating ?? '—' }}</el-descriptions-item>
          <el-descriptions-item label="评价数量">{{ hygieneData.stats?.reviewCount ?? 0 }}</el-descriptions-item>
          <el-descriptions-item label="最近30天">{{ hygieneData.stats?.hygieneScore30d ?? '—' }}</el-descriptions-item>
          <el-descriptions-item label="风险状态">{{ hygieneData.stats?.riskStatus || 'normal' }}</el-descriptions-item>
        </el-descriptions>
        <h4 style="margin-top: 16px">最近差评（卫生≤3）</h4>
        <el-table :data="hygieneData.lowReviews || []" size="small" max-height="200">
          <el-table-column prop="rating" label="总评" width="60" />
          <el-table-column prop="hygieneRating" label="卫生" width="60" />
          <el-table-column prop="content" label="内容" min-width="160" show-overflow-tooltip />
          <el-table-column prop="createdAt" label="时间" width="160" />
        </el-table>
        <h4 style="margin-top: 16px">整改提醒记录</h4>
        <el-table :data="hygieneData.remediationNotices || []" size="small" max-height="160">
          <el-table-column prop="reason" label="原因" min-width="180" show-overflow-tooltip />
          <el-table-column prop="status" label="状态" width="90" />
          <el-table-column prop="createdAt" label="时间" width="160" />
        </el-table>
      </div>
      <template #footer>
        <el-button @click="hygieneVisible = false">关闭</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { onMounted, reactive, ref } from 'vue';
import { useRouter } from 'vue-router';
import { ElMessage, ElMessageBox } from 'element-plus';
import { adminApi, fullImageUrl, isUploadImageUrl, MEAL_OPTIONS, todayStr } from '../api/admin';
import QualificationImageList from '../components/QualificationImageList.vue';
import { useAuthStore } from '../stores/auth';

const auth = useAuthStore();
const router = useRouter();
const activeTab = ref('pending');
const list = ref([]);
const companies = ref([]);
const loading = ref(false);
const statusFilter = ref('pending');
const formVisible = ref(false);
const qrVisible = ref(false);
const detailVisible = ref(false);
const rejectVisible = ref(false);
const detail = ref(null);
const rejectReason = ref('');
const rejectTarget = ref(null);
const hygieneVisible = ref(false);
const hygieneLoading = ref(false);
const hygieneData = ref(null);
const form = reactive({
  id: '', merchantName: '', address: '', phone: '', companyId: '',
});
const qrForm = reactive({ merchantId: '', paymentQr: '' });

function statusLabel(s) {
  return { pending: '待审核', approved: '已通过', rejected: '已拒绝' }[s] || s;
}
function statusTag(s) {
  return { pending: 'warning', approved: 'success', rejected: 'info' }[s] || '';
}
function formatMeals(types) {
  if (!types?.length) return '未填写';
  return types.map((t) => MEAL_OPTIONS.find((m) => m.value === t)?.label || t).join('、');
}

const EMPTY_PLACEHOLDER = '未填写';
const DELIVERY_MODE_LABELS = { delivery: '配送', selfPickup: '自取' };
const WEEKDAY_LABELS = {
  mon: '周一',
  tue: '周二',
  wed: '周三',
  thu: '周四',
  fri: '周五',
  sat: '周六',
  sun: '周日',
};
const PAYMENT_METHOD_LABELS = {
  wechat: '微信',
  alipay: '支付宝',
  // 历史数据可能仍有 bankTransfer，保留映射避免在详情页显示英文枚举值
  bankTransfer: '对公转账',
};

function orDash(v) {
  if (v == null) return EMPTY_PLACEHOLDER;
  const s = String(v).trim();
  return s ? s : EMPTY_PLACEHOLDER;
}

function formatDeliveryModes(modes) {
  if (!modes?.length) return EMPTY_PLACEHOLDER;
  return modes.map((m) => DELIVERY_MODE_LABELS[m] || m).join('、');
}

function formatBusinessDays(days) {
  if (!days?.length) return EMPTY_PLACEHOLDER;
  return days.map((d) => WEEKDAY_LABELS[d] || d).join('、');
}

function formatHoursRange(start, end) {
  if (!start && !end) return EMPTY_PLACEHOLDER;
  if (!start || !end) return orDash(start || end);
  return `${start} - ${end}`;
}

function formatPaymentMethods(methods) {
  if (!methods || !methods.length) return EMPTY_PLACEHOLDER;
  return methods.map((m) => PAYMENT_METHOD_LABELS[m] || m).join('、');
}

/**
 * 解析收款方式：优先用 paymentMethods 数组；为空则兜底拆分老的 paymentMethod 字符串。
 * 这样历史商家（只有 paymentMethod='wechat'）也能在新版后台看到收款方式。
 */
function resolvePaymentMethods(d) {
  if (!d) return [];
  if (Array.isArray(d.paymentMethods) && d.paymentMethods.length) {
    return d.paymentMethods;
  }
  const legacy = (d.paymentMethod || '').trim();
  if (!legacy) return [];
  return legacy.split(/[,，;；\s]+/).map((s) => s.trim()).filter(Boolean);
}

function hasPaymentMethod(d, key) {
  return resolvePaymentMethods(d).includes(key);
}

function deadlineOf(detail, mealType) {
  const map = detail?.mealOrderDeadlines;
  if (!map || typeof map !== 'object') return '';
  return map[mealType] || '';
}

function isImageUrl(url) {
  return isUploadImageUrl(url);
}

function onTabChange() {
  statusFilter.value = activeTab.value === 'pending' ? 'pending' : 'approved';
  load();
}

async function loadCompanies() {
  if (!auth.isPlatformAdmin) return;
  const res = await adminApi.listCompanies();
  companies.value = res.data;
}

async function load() {
  loading.value = true;
  try {
    const status = activeTab.value === 'pending'
      ? (statusFilter.value || 'pending')
      : 'approved';
    const res = await adminApi.listMerchants(status);
    list.value = activeTab.value === 'pending'
      ? res.data.filter((m) => m.status === 'pending' || m.status === 'rejected')
      : res.data.filter((m) => m.status === 'approved');
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    loading.value = false;
  }
}

async function openDetail(row) {
  try {
    const res = await adminApi.getMerchantOnboardingDetail(row.id);
    detail.value = res.data;
    detailVisible.value = true;
  } catch (e) {
    ElMessage.error(e.message);
  }
}

function openCreate() {
  Object.assign(form, {
    id: '', merchantName: '', address: '', phone: '',
    companyId: companies.value[0]?.id || auth.user?.companyId || '',
  });
  formVisible.value = true;
}

function openEdit(row) {
  Object.assign(form, {
    id: row.id, merchantName: row.merchantName, address: row.address,
    phone: row.contactPhone || row.phone, companyId: row.companyId,
  });
  formVisible.value = true;
}

async function saveMerchant() {
  try {
    if (form.id) {
      await adminApi.updateMerchant(form.id, {
        merchantName: form.merchantName, address: form.address,
        phone: form.phone, companyId: form.companyId,
      });
    } else {
      await adminApi.createMerchant({
        merchantName: form.merchantName, address: form.address,
        phone: form.phone, companyId: form.companyId,
      });
    }
    ElMessage.success('保存成功');
    formVisible.value = false;
    load();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

async function review(row, status) {
  try {
    await adminApi.reviewMerchant(row.id, status);
    ElMessage.success('已审核');
    load();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

function openReject(row) {
  rejectTarget.value = row;
  rejectReason.value = '';
  rejectVisible.value = true;
}

async function confirmReject() {
  if (!rejectReason.value.trim()) {
    ElMessage.warning('请填写驳回原因');
    return;
  }
  try {
    await adminApi.reviewMerchant(rejectTarget.value.id, 'rejected', rejectReason.value.trim());
    ElMessage.success('已驳回');
    rejectVisible.value = false;
    load();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

async function toggleEnabled(row) {
  try {
    await adminApi.setMerchantEnabled(row.id, !row.isEnabled);
    ElMessage.success('已更新');
    load();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

async function toggleOpen(row) {
  try {
    await adminApi.setMerchantOpen(row.id, !row.isOpen);
    ElMessage.success('已更新');
    load();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

async function resetMerchantPassword(row) {
  const userId = row.userId;
  if (!userId) {
    ElMessage.warning('该商家暂无登录账号，请先审核通过');
    return;
  }
  try {
    await ElMessageBox.confirm(
      '是否将该商家登录密码重置为 123456？',
      '重置密码',
      { type: 'warning' },
    );
    await adminApi.resetUserPassword(userId);
    ElMessage.success('密码已重置为 123456');
  } catch (e) {
    if (e !== 'cancel') ElMessage.error(e.message || '操作失败');
  }
}

function editQr(row) {
  qrForm.merchantId = row.id;
  qrForm.paymentQr = row.paymentQr || '';
  qrVisible.value = true;
}

async function uploadQr({ file }) {
  try {
    const res = await adminApi.uploadMerchantQr(file, qrForm.merchantId);
    qrForm.paymentQr = res.data.url;
    ElMessage.success('上传成功');
  } catch (e) {
    ElMessage.error(e.message || '上传失败');
  }
}

async function saveQr() {
  try {
    await adminApi.updateMerchantPaymentQr(qrForm.merchantId, qrForm.paymentQr);
    ElMessage.success('已保存');
    qrVisible.value = false;
    load();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

async function openHygiene(row) {
  hygieneVisible.value = true;
  hygieneLoading.value = true;
  hygieneData.value = null;
  try {
    const res = await adminApi.getMerchantHygiene(row.id);
    hygieneData.value = res.data;
  } catch (e) {
    ElMessage.error(e.message || '加载失败');
    hygieneVisible.value = false;
  } finally {
    hygieneLoading.value = false;
  }
}

function goSummary(row) {
  router.push({
    path: '/meal-summary',
    query: { merchantId: row.id, date: todayStr(), mealType: 'lunch' },
  });
}

onMounted(async () => {
  await loadCompanies();
  load();
});
</script>

<style scoped>
.toolbar { display: flex; gap: 12px; margin-bottom: 16px; flex-wrap: wrap; }
.qr-preview { margin-bottom: 12px; }
.qr-thumb { max-width: 200px; max-height: 200px; border: 1px solid #eee; border-radius: 8px; cursor: zoom-in; }
.qr-input { margin-bottom: 12px; }
.detail-grid h4 { margin: 16px 0 8px; color: #333; font-size: 14px; }
.detail-grid p { margin: 4px 0; color: #555; font-size: 13px; }
.detail-grid .reject-note {
  margin-top: 10px;
  padding: 8px 10px;
  background: #FFF3E8;
  color: #B95E00;
  border-radius: 6px;
  font-size: 13px;
}
</style>
