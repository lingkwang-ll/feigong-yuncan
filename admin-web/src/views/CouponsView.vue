<template>
  <div class="page-card">
    <h2 class="page-title">优惠券管理</h2>

    <div class="toolbar">
      <el-input
        v-model="merchantFilter"
        placeholder="按商家 ID 筛选"
        clearable
        style="width: 220px"
        @keyup.enter="load"
      />
      <el-button type="primary" @click="load">查询</el-button>
      <el-button @click="resetFilter">重置</el-button>
    </div>

    <el-table :data="list" v-loading="loading" stripe>
      <el-table-column prop="name" label="优惠券名称" min-width="140" />
      <el-table-column prop="merchantId" label="商家 ID" width="140" />
      <el-table-column label="类型" width="100">
        <template #default="{ row }">{{ typeLabel(row.couponType) }}</template>
      </el-table-column>
      <el-table-column label="优惠" width="120">
        <template #default="{ row }">
          {{ row.couponType === 'threshold'
            ? `满${row.minOrderAmount}减${row.discountAmount}`
            : `减${row.discountAmount}` }}
        </template>
      </el-table-column>
      <el-table-column label="餐段" width="120">
        <template #default="{ row }">{{ formatMeals(row.mealTypes) }}</template>
      </el-table-column>
      <el-table-column label="领取/总量" width="110">
        <template #default="{ row }">{{ row.claimedCount }}/{{ row.totalQuantity }}</template>
      </el-table-column>
      <el-table-column prop="usedCount" label="已用" width="70" />
      <el-table-column label="有效期" min-width="180">
        <template #default="{ row }">
          {{ formatDate(row.startAt) }} ~ {{ formatDate(row.endAt) }}
        </template>
      </el-table-column>
      <el-table-column label="状态" width="90">
        <template #default="{ row }">
          <el-tag :type="row.status === 'enabled' ? 'success' : 'info'">
            {{ row.status === 'enabled' ? '启用' : '停用' }}
          </el-tag>
        </template>
      </el-table-column>
      <el-table-column label="操作" width="120" fixed="right">
        <template #default="{ row }">
          <el-button
            link
            :type="row.status === 'enabled' ? 'danger' : 'success'"
            @click="toggleStatus(row)"
          >
            {{ row.status === 'enabled' ? '停用' : '启用' }}
          </el-button>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue';
import { ElMessage } from 'element-plus';
import { adminApi } from '../api/admin';

const loading = ref(false);
const list = ref([]);
const merchantFilter = ref('');

function typeLabel(t) {
  if (t === 'threshold') return '满减券';
  if (t === 'newcomer') return '新人券';
  return '立减券';
}

function formatMeals(types) {
  if (!types?.length) return '—';
  const map = { breakfast: '早餐', lunch: '中餐', dinner: '晚餐' };
  return types.map((t) => map[t] || t).join('、');
}

function formatDate(v) {
  if (!v) return '—';
  return String(v).slice(0, 10);
}

async function load() {
  loading.value = true;
  try {
    const res = await adminApi.listCoupons({
      merchantId: merchantFilter.value || undefined,
    });
    list.value = res.data || [];
  } catch (e) {
    ElMessage.error(e.message || '加载失败');
  } finally {
    loading.value = false;
  }
}

function resetFilter() {
  merchantFilter.value = '';
  load();
}

async function toggleStatus(row) {
  const enabled = row.status !== 'enabled';
  try {
    await adminApi.setCouponStatus(row.id, enabled);
    ElMessage.success(enabled ? '已启用' : '已停用');
    await load();
  } catch (e) {
    ElMessage.error(e.message || '操作失败');
  }
}

onMounted(load);
</script>

<style scoped>
.toolbar {
  display: flex;
  gap: 12px;
  margin-bottom: 16px;
  flex-wrap: wrap;
}
</style>
