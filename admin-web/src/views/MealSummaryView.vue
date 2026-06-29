<template>
  <div class="page-card">
    <h2 class="page-title">订餐汇总</h2>
    <div class="toolbar">
      <el-date-picker v-model="date" type="date" value-format="YYYY-MM-DD" @change="load" />
      <el-select v-model="mealType" placeholder="餐段" style="width: 120px" @change="load">
        <el-option v-for="m in mealOptions" :key="m.value" :label="m.label" :value="m.value" />
      </el-select>
      <el-select v-model="merchantId" placeholder="商家" filterable style="width: 180px" @change="load">
        <el-option v-for="m in merchants" :key="m.id" :label="m.merchantName" :value="m.id" />
      </el-select>
      <el-select v-model="status" placeholder="状态" clearable style="width: 120px" @change="load">
        <el-option label="待处理" value="pending" />
        <el-option label="已完成" value="completed" />
      </el-select>
      <el-button type="primary" @click="load">查询</el-button>
      <el-button @click="exportCsv">导出 CSV</el-button>
      <el-button type="warning" @click="goLabels">打印标签</el-button>
      <el-button
        v-if="summary && summary.batchStatus === 'pending'"
        type="success"
        @click="confirmSummary"
      >确认汇总</el-button>
    </div>

    <template v-if="summary">
      <el-row :gutter="16" class="summary-cards">
        <el-col :span="4"><div class="stat"><div class="k">总人数</div><div class="v">{{ summary.totalPeople }}</div></div></el-col>
        <el-col :span="4"><div class="stat"><div class="k">总份数</div><div class="v">{{ summary.totalPortions }}</div></div></el-col>
        <el-col :span="4"><div class="stat"><div class="k">总金额</div><div class="v accent">¥{{ summary.totalAmount }}</div></div></el-col>
        <el-col :span="4"><div class="stat"><div class="k">取餐人</div><div class="v small">{{ summary.collectorName }}</div></div></el-col>
        <el-col :span="4"><div class="stat"><div class="k">联系电话</div><div class="v small">{{ summary.collectorPhone }}</div></div></el-col>
        <el-col :span="4"><div class="stat"><div class="k">取餐地点</div><div class="v small">{{ summary.collectorAddress }}</div></div></el-col>
      </el-row>
      <div class="status-bar">
        当前状态：
        <el-tag :type="summary.batchStatus === 'confirmed' ? 'success' : 'warning'">
          {{ summary.batchStatus === 'confirmed' ? '已完成' : '待处理' }}
        </el-tag>
        <span class="meta">{{ summary.date }} · {{ summary.mealLabel }} · {{ summary.merchantName }}</span>
      </div>

      <div class="delivery-card" v-loading="deliveryLoading">
        <div class="delivery-card-head">
          <h3>配送位置</h3>
          <el-button v-if="deliveryLocation" size="small" @click="showMapHint">查看地图</el-button>
        </div>
        <template v-if="deliveryLocation && deliveryLocation.latitude">
          <p><span class="label">商家当前位置</span>{{ deliveryLocation.addressText || '—' }}</p>
          <p><span class="label">坐标</span>{{ deliveryLocation.latitude }}, {{ deliveryLocation.longitude }}</p>
          <p><span class="label">更新时间</span>{{ formatTime(deliveryLocation.updatedAt) }}</p>
          <p><span class="label">状态</span>{{ deliveryLocation.status === 'delivering' ? '配送中' : deliveryLocation.status }}</p>
        </template>
        <template v-else>
          <p class="empty-hint">商家暂未开启实时位置</p>
        </template>
        <p v-if="summary.collectorAddress" class="pickup-line">
          <span class="label">统一取餐点</span>{{ summary.collectorAddress }}
        </p>
      </div>

      <h3>菜品汇总</h3>
      <el-table :data="summary.dishSummary" stripe class="section">
        <el-table-column prop="dishName" label="菜品名称" />
        <el-table-column prop="quantity" label="数量" width="100" />
        <el-table-column prop="subtotal" label="小计金额" width="120" />
      </el-table>

      <h3>员工明细（一人一行）</h3>
      <el-table :data="summary.employeeDetails" stripe v-loading="loading">
        <el-table-column prop="labelCode" label="标签编号" width="100" />
        <el-table-column prop="employeeName" label="员工姓名" width="100" />
        <el-table-column label="菜品列表">
          <template #default="{ row }">{{ formatItems(row.items) }}</template>
        </el-table-column>
        <el-table-column prop="remark" label="备注" width="160">
          <template #default="{ row }">{{ row.remark || '无' }}</template>
        </el-table-column>
        <el-table-column prop="amount" label="金额" width="80" />
      </el-table>
    </template>
    <el-empty v-else-if="!loading" description="请选择日期、餐段和商家后查询" />
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { ElMessage } from 'element-plus';
import { adminApi, MEAL_OPTIONS, todayStr } from '../api/admin';

const route = useRoute();
const router = useRouter();
const mealOptions = MEAL_OPTIONS;
const date = ref(route.query.date || todayStr());
const mealType = ref(route.query.mealType || 'lunch');
const merchantId = ref(route.query.merchantId || '');
const status = ref('');
const merchants = ref([]);
const summary = ref(null);
const loading = ref(false);
const deliveryLocation = ref(null);
const deliveryLoading = ref(false);

function formatItems(items) {
  return (items || []).map((i) => `${i.dishName}×${i.quantity}`).join('、');
}

async function loadMerchants() {
  const res = await adminApi.listMerchants('approved');
  merchants.value = res.data;
  if (!merchantId.value && merchants.value.length) {
    merchantId.value = merchants.value[0].id;
  }
}

async function load() {
  if (!merchantId.value || !mealType.value) return;
  loading.value = true;
  try {
    const res = await adminApi.getMealSummary({
      date: date.value,
      mealType: mealType.value,
      merchantId: merchantId.value,
      status: status.value || undefined,
    });
    summary.value = res.data;
    await loadDeliveryLocation();
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    loading.value = false;
  }
}

async function loadDeliveryLocation() {
  if (!merchantId.value || !mealType.value || !date.value) return;
  deliveryLoading.value = true;
  try {
    const res = await adminApi.getDeliveryLocation({
      date: date.value,
      mealType: mealType.value,
      merchantId: merchantId.value,
    });
    deliveryLocation.value = res.data;
  } catch {
    deliveryLocation.value = null;
  } finally {
    deliveryLoading.value = false;
  }
}

function formatTime(iso) {
  if (!iso) return '—';
  return String(iso).replace('T', ' ').slice(0, 19);
}

function showMapHint() {
  const loc = deliveryLocation.value;
  if (!loc?.latitude) return;
  ElMessage.info(`商家位置：${loc.addressText || ''} (${loc.latitude}, ${loc.longitude})`);
}

async function exportCsv() {
  if (!merchantId.value || !mealType.value) {
    ElMessage.warning('请先选择日期、餐段和商家');
    return;
  }
  try {
    await adminApi.exportMealSummary({
      date: date.value,
      mealType: mealType.value,
      merchantId: merchantId.value,
      status: status.value || undefined,
    });
    ElMessage.success('导出成功');
  } catch (e) {
    ElMessage.error(e.message);
  }
}

async function confirmSummary() {
  try {
    const res = await adminApi.confirmMealSummary({
      date: date.value,
      mealType: mealType.value,
      merchantId: merchantId.value,
    });
    summary.value = res.data;
    ElMessage.success('汇总已确认');
  } catch (e) {
    ElMessage.error(e.message);
  }
}

function goLabels() {
  router.push({
    path: '/labels',
    query: { date: date.value, mealType: mealType.value, merchantId: merchantId.value },
  });
}

onMounted(async () => {
  await loadMerchants();
  load();
});
</script>

<style scoped>
.toolbar { display: flex; gap: 12px; margin-bottom: 20px; flex-wrap: wrap; }
.summary-cards { margin-bottom: 12px; }
.status-bar { margin-bottom: 20px; display: flex; align-items: center; gap: 12px; }
.status-bar .meta { color: #888; font-size: 13px; }
.stat { background: #f9faf8; border-radius: 8px; padding: 12px; border: 1px solid #eef2eb; }
.stat .k { color: #888; font-size: 12px; }
.stat .v { font-size: 20px; font-weight: 700; color: var(--fy-primary); margin-top: 4px; }
.stat .v.accent { color: var(--fy-accent); }
.stat .v.small { font-size: 14px; font-weight: 600; }
.section { margin-bottom: 24px; }
h3 { margin: 16px 0 8px; font-size: 15px; }
.delivery-card {
  background: #fff;
  border: 1px solid #eef2eb;
  border-radius: 10px;
  padding: 14px 16px;
  margin-bottom: 20px;
}
.delivery-card-head { display: flex; align-items: center; justify-content: space-between; margin-bottom: 8px; }
.delivery-card-head h3 { margin: 0; }
.delivery-card p { margin: 6px 0; font-size: 13px; color: #444; }
.delivery-card .label { color: #888; margin-right: 8px; }
.delivery-card .empty-hint { color: #999; font-size: 13px; }
.delivery-card .pickup-line { margin-top: 10px; padding-top: 10px; border-top: 1px dashed #eef2eb; }
</style>
