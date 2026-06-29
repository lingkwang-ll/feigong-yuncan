<template>
  <div class="page-card">
    <h2 class="page-title">工作台</h2>
    <div class="toolbar">
      <el-date-picker v-model="date" type="date" value-format="YYYY-MM-DD" @change="load" />
      <el-button type="primary" @click="load">刷新</el-button>
    </div>

    <el-row :gutter="16" class="stats-row" v-loading="loading">
      <el-col :span="6"><div class="stat-card"><div class="label">今日订餐人数</div><div class="value">{{ stats.orderPeople }}</div></div></el-col>
      <el-col :span="6"><div class="stat-card"><div class="label">今日订餐份数</div><div class="value">{{ stats.orderPortions }}</div></div></el-col>
      <el-col :span="6"><div class="stat-card"><div class="label">今日订餐金额</div><div class="value accent">¥{{ stats.orderAmount }}</div></div></el-col>
      <el-col :span="6"><div class="stat-card"><div class="label">统一取餐人</div><div class="value small">{{ stats.collectorName }}</div></div></el-col>
    </el-row>

    <el-row :gutter="16" class="stats-row">
      <el-col :span="6"><div class="stat-card"><div class="label">待处理汇总</div><div class="value">{{ stats.pendingBatches }}</div></div></el-col>
      <el-col :span="6"><div class="stat-card"><div class="label">已完成汇总</div><div class="value">{{ stats.completedBatches }}</div></div></el-col>
    </el-row>

    <h3 class="section-title">餐段统计</h3>
    <el-table :data="mealRows" stripe>
      <el-table-column prop="label" label="餐段" width="120" />
      <el-table-column prop="people" label="人数" width="100" />
      <el-table-column prop="portions" label="份数" width="100" />
      <el-table-column prop="amount" label="金额" />
    </el-table>

    <h3 class="section-title">快捷入口</h3>
    <div class="quick-links">
      <el-button type="primary" @click="$router.push('/meal-summary')">今日订餐汇总</el-button>
      <el-button type="warning" @click="$router.push('/labels')">打印餐盒标签</el-button>
      <el-button @click="$router.push('/meal-summary')">导出订餐表</el-button>
      <el-button @click="$router.push('/dishes')">菜品管理</el-button>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue';
import { ElMessage } from 'element-plus';
import { adminApi, MEAL_OPTIONS, todayStr } from '../api/admin';

const date = ref(todayStr());
const loading = ref(false);
const stats = ref({
  orderPeople: 0,
  orderPortions: 0,
  orderAmount: 0,
  pendingBatches: 0,
  completedBatches: 0,
  collectorName: '—',
  mealStats: {},
});

const mealRows = computed(() =>
  MEAL_OPTIONS.map((m) => ({
    label: m.label,
    people: stats.value.mealStats?.[m.value]?.people ?? 0,
    portions: stats.value.mealStats?.[m.value]?.portions ?? 0,
    amount: `¥${stats.value.mealStats?.[m.value]?.amount ?? 0}`,
  })),
);

async function load() {
  loading.value = true;
  try {
    const res = await adminApi.getDashboard(date.value);
    stats.value = res.data;
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    loading.value = false;
  }
}

onMounted(load);
</script>

<style scoped>
.toolbar { display: flex; gap: 12px; margin-bottom: 20px; }
.stats-row { margin-bottom: 16px; }
.stat-card {
  background: #f9faf8; border-radius: 10px; padding: 16px; border: 1px solid #eef2eb;
}
.stat-card .label { color: #888; font-size: 13px; margin-bottom: 8px; }
.stat-card .value { font-size: 28px; font-weight: 700; color: var(--fy-primary); }
.stat-card .value.accent { color: var(--fy-accent); }
.stat-card .value.small { font-size: 18px; }
.section-title { margin: 24px 0 12px; font-size: 16px; }
.quick-links { display: flex; gap: 12px; flex-wrap: wrap; }
</style>
