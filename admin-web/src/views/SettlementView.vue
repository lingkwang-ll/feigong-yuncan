<template>
  <div class="page-card">
    <div class="toolbar">
      <h2>结算管理</h2>
      <el-select v-model="status" placeholder="状态" clearable style="width: 140px" @change="load">
        <el-option label="待结算" value="pending" />
        <el-option label="可结算" value="eligible" />
        <el-option label="已结算" value="settled" />
        <el-option label="冻结" value="blocked" />
      </el-select>
      <el-button type="primary" @click="runCheck">检查到期结算</el-button>
    </div>
    <el-table v-loading="loading" :data="rows" stripe>
      <el-table-column prop="settlement_no" label="结算单号" width="160" />
      <el-table-column prop="order_id" label="订单" width="120" />
      <el-table-column prop="merchant_id" label="商家" width="100" />
      <el-table-column prop="merchant_receivable_amount" label="商家应收" width="100" />
      <el-table-column prop="status" label="状态" width="100" />
      <el-table-column prop="settlement_eligible_at" label="可结算日" width="180" />
      <el-table-column label="操作" width="120">
        <template #default="{ row }">
          <el-button
            v-if="row.status === 'eligible'"
            size="small"
            type="success"
            @click="settle(row.id)"
          >结算</el-button>
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<script setup>
import { onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { adminApi } from '../api/admin'

const loading = ref(false)
const rows = ref([])
const status = ref('')

async function load() {
  loading.value = true
  try {
    const res = await adminApi.listSettlements(status.value || undefined)
    rows.value = res.data || []
  } catch (e) {
    ElMessage.error(e.message || '加载失败')
  } finally {
    loading.value = false
  }
}

async function runCheck() {
  try {
    const res = await adminApi.runSettlementCheck()
    ElMessage.success(`已标记 ${res.data.eligibleCount} 笔可结算`)
    await load()
  } catch (e) {
    ElMessage.error(e.message || '检查失败')
  }
}

async function settle(id) {
  try {
    await adminApi.settleOrder(id)
    ElMessage.success('结算成功')
    await load()
  } catch (e) {
    ElMessage.error(e.message || '结算失败')
  }
}

onMounted(load)
</script>

<style scoped>
.page-card { padding: 16px; }
.toolbar { display: flex; gap: 12px; align-items: center; margin-bottom: 16px; }
</style>
