<template>
  <div class="page-card">
    <div class="page-head">
      <h2 class="page-title">待补分类菜品</h2>
      <el-button link type="primary" @click="$router.push('/dishes')">返回菜品管理</el-button>
    </div>

    <p class="hint">
      以下菜品 category 为空，套餐点餐页无法正确分荤菜/素菜/加菜。请确认分类后保存；仅更新分类，不会修改价格、餐段与订单。
    </p>

    <div class="toolbar">
      <el-select
        v-model="merchantFilter"
        placeholder="筛选商家"
        clearable
        filterable
        style="width: 240px"
        @change="load"
      >
        <el-option
          v-for="m in merchantOptions"
          :key="m.id"
          :label="m.merchantName"
          :value="m.id"
        />
      </el-select>
      <el-checkbox v-model="onlyPending" @change="applyFilter">只看未处理</el-checkbox>
      <el-button type="primary" :disabled="batchItems.length === 0" @click="confirmBatchSave">
        批量保存（{{ batchItems.length }}）
      </el-button>
      <el-button @click="load">刷新</el-button>
    </div>

    <div v-loading="loading">
      <el-empty v-if="!loading && filteredGroups.length === 0" description="暂无待补分类菜品" />

      <div v-for="group in filteredGroups" :key="group.merchantId" class="merchant-block">
        <h3 class="merchant-title">
          {{ group.merchantName }}
          <span class="muted">（{{ group.dishes.length }} 道）</span>
        </h3>
        <el-table :data="group.dishes" stripe @selection-change="(rows) => onSelectChange(group.merchantId, rows)">
          <el-table-column type="selection" width="48" />
          <el-table-column label="图片" width="72">
            <template #default="{ row }">
              <el-image
                v-if="isUploadImageUrl(row.imageUrl)"
                :src="fullImageUrl(row.imageUrl)"
                fit="cover"
                class="thumb"
              />
              <span v-else class="muted">—</span>
            </template>
          </el-table-column>
          <el-table-column prop="dishName" label="菜名" min-width="140" />
          <el-table-column label="餐段" min-width="120">
            <template #default="{ row }">
              <span v-if="row.mealTypes?.length">
                {{ row.mealTypes.map((m) => mealLabel(m)).join('、') }}
              </span>
              <span v-else>{{ mealLabel(row.mealType) }}</span>
            </template>
          </el-table-column>
          <el-table-column label="价格" width="90">
            <template #default="{ row }">¥{{ row.price }}</template>
          </el-table-column>
          <el-table-column label="建议分类" min-width="160">
            <template #default="{ row }">
              <span v-if="row.suggestedCategory">{{ dishCategoryLabel(row.suggestedCategory) }}</span>
              <span v-else class="muted">—</span>
              <div v-if="row.reason" class="reason">{{ row.reason }}</div>
            </template>
          </el-table-column>
          <el-table-column label="选择分类" width="140">
            <template #default="{ row }">
              <el-select
                v-model="row._pickCategory"
                placeholder="选择"
                size="small"
                @change="syncPick(row)"
              >
                <el-option
                  v-for="c in categoryOptions"
                  :key="c.value"
                  :label="c.label"
                  :value="c.value"
                />
              </el-select>
            </template>
          </el-table-column>
          <el-table-column label="操作" width="100" fixed="right">
            <template #default="{ row }">
              <el-button
                link
                type="primary"
                :disabled="!row._pickCategory"
                @click="saveOne(row)"
              >
                保存
              </el-button>
            </template>
          </el-table-column>
        </el-table>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, ref } from 'vue';
import { ElMessage, ElMessageBox } from 'element-plus';
import {
  adminApi,
  DISH_CATEGORY_OPTIONS,
  dishCategoryLabel,
  fullImageUrl,
  isUploadImageUrl,
  mealLabel,
} from '../api/admin';

const loading = ref(false);
const groups = ref([]);
const merchantFilter = ref('');
const onlyPending = ref(true);
const merchants = ref([]);
const pickedByMerchant = ref({});
const categoryOptions = DISH_CATEGORY_OPTIONS;

const merchantOptions = computed(() => {
  const fromGroups = groups.value.map((g) => ({
    id: g.merchantId,
    merchantName: g.merchantName,
  }));
  const map = new Map();
  for (const m of [...merchants.value, ...fromGroups]) {
    if (m?.id) map.set(m.id, m);
  }
  return Array.from(map.values());
});

const filteredGroups = computed(() => {
  if (!onlyPending.value) return groups.value;
  return groups.value.filter((g) => g.dishes.length > 0);
});

const batchItems = computed(() => {
  const items = [];
  for (const g of groups.value) {
    for (const d of g.dishes) {
      if (d._pickCategory) {
        items.push({ dishId: d.dishId, category: d._pickCategory, dishName: d.dishName });
      }
    }
  }
  return items;
});

function decorateGroups(raw) {
  return (raw || []).map((g) => ({
    ...g,
    dishes: (g.dishes || []).map((d) => ({
      ...d,
      _pickCategory: d.suggestedCategory || '',
    })),
  }));
}

async function loadMerchants() {
  try {
    const res = await adminApi.listMerchants('approved');
    merchants.value = res.data || [];
  } catch {
  merchants.value = [];
  }
}

async function load() {
  loading.value = true;
  try {
    const res = await adminApi.listCategoryMissingDishes(merchantFilter.value || undefined);
    groups.value = decorateGroups(res.data);
    pickedByMerchant.value = {};
  } catch (e) {
    ElMessage.error(e.message || '加载失败');
  } finally {
    loading.value = false;
  }
}

function applyFilter() {
  // filteredGroups is computed; reload if merchant filter changed externally
}

function syncPick(row) {
  // selection tracking uses _pickCategory on row
}

function onSelectChange(merchantId, rows) {
  pickedByMerchant.value[merchantId] = rows;
  for (const row of rows) {
    if (!row._pickCategory && row.suggestedCategory) {
      row._pickCategory = row.suggestedCategory;
    }
  }
}

async function saveOne(row) {
  if (!row._pickCategory) {
    ElMessage.warning('请先选择分类');
    return;
  }
  try {
    await ElMessageBox.confirm(
      `确认将「${row.dishName}」分类更新为「${dishCategoryLabel(row._pickCategory)}」？该操作不会修改价格、餐段和订单。`,
      '确认保存',
      { type: 'warning' },
    );
    await adminApi.patchDishCategory(row.dishId, row._pickCategory);
    ElMessage.success('已保存');
    await load();
  } catch (e) {
    if (e !== 'cancel') ElMessage.error(e.message || '保存失败');
  }
}

async function confirmBatchSave() {
  const items = batchItems.value;
  if (!items.length) return;
  try {
    await ElMessageBox.confirm(
      `确认将 ${items.length} 道菜品分类更新为所选分类？该操作不会修改价格、餐段和订单。`,
      '批量保存确认',
      { type: 'warning' },
    );
    await adminApi.patchDishCategoryBatch(
      items.map(({ dishId, category }) => ({ dishId, category })),
    );
    ElMessage.success(`已更新 ${items.length} 道菜品`);
    await load();
  } catch (e) {
    if (e !== 'cancel') ElMessage.error(e.message || '批量保存失败');
  }
}

onMounted(async () => {
  await loadMerchants();
  await load();
});
</script>

<style scoped>
.page-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 8px;
}
.hint {
  color: #666;
  font-size: 13px;
  margin-bottom: 16px;
  line-height: 1.5;
}
.toolbar {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 16px;
  flex-wrap: wrap;
}
.merchant-block {
  margin-bottom: 28px;
}
.merchant-title {
  font-size: 15px;
  margin: 0 0 10px;
  font-weight: 600;
}
.muted {
  color: #999;
  font-size: 12px;
}
.reason {
  font-size: 12px;
  color: #888;
  margin-top: 4px;
}
.thumb {
  width: 48px;
  height: 48px;
  border-radius: 6px;
}
</style>
