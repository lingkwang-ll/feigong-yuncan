<template>
  <div class="page-card">
    <h2 class="page-title">菜品管理</h2>

    <div class="toolbar">
      <el-select v-model="merchantId" placeholder="商家" clearable filterable @change="onMerchantChange" style="width: 220px">
        <el-option v-for="m in merchants" :key="m.id" :label="m.merchantName" :value="m.id" />
      </el-select>
      <el-button type="warning" plain @click="$router.push('/dishes/category-missing')">
        待补分类菜品
      </el-button>
    </div>

    <el-tabs v-model="activeTab" class="dish-tabs">
      <!-- ===== Tab 1: 菜品库 ===== -->
      <el-tab-pane label="菜品库" name="library">
        <div class="sub-toolbar">
          <el-select v-model="mealType" placeholder="餐段" clearable @change="loadDishes" style="width: 120px">
            <el-option v-for="m in mealOptions" :key="m.value" :label="m.label" :value="m.value" />
          </el-select>
          <el-select v-model="categoryFilter" placeholder="分类" clearable @change="loadDishes" style="width: 120px">
            <el-option v-for="c in categoryOptions" :key="c.value" :label="c.label" :value="c.value" />
          </el-select>
          <el-button type="primary" :disabled="!merchantId" @click="openCreate('')">新增菜品</el-button>
        </div>
        <el-table :data="filteredDishes" v-loading="loading" stripe>
          <el-table-column prop="name" label="菜品名称" min-width="140" />
          <el-table-column label="分类" width="90">
            <template #default="{ row }">{{ dishCategoryLabel(row.category) }}</template>
          </el-table-column>
          <el-table-column prop="mealType" label="餐段" width="90">
            <template #default="{ row }">{{ mealLabel(row.mealType) }}</template>
          </el-table-column>
          <el-table-column label="价格 / 加菜价" width="120">
            <template #default="{ row }">
              <span v-if="row.category === 'extra'">加菜：¥{{ row.extraPrice ?? 0 }}</span>
              <span v-else>¥{{ row.price ?? 0 }}</span>
            </template>
          </el-table-column>
          <el-table-column label="适用餐段" min-width="140">
            <template #default="{ row }">
              <span v-if="row.mealTypes && row.mealTypes.length">
                {{ row.mealTypes.map((m) => mealLabel(m)).join('、') }}
              </span>
              <span v-else class="muted">—</span>
            </template>
          </el-table-column>
          <el-table-column label="标签" width="160">
            <template #default="{ row }">{{ (row.tags || []).join('、') || '—' }}</template>
          </el-table-column>
          <el-table-column prop="sortOrder" label="排序" width="100">
            <template #default="{ row }">
              <el-input-number v-model="row.sortOrder" :min="0" size="small" @change="(v) => saveSort(row, v)" />
            </template>
          </el-table-column>
          <el-table-column label="上架" width="70">
            <template #default="{ row }">{{ row.isAvailable ? '是' : '否' }}</template>
          </el-table-column>
          <el-table-column label="售罄" width="70">
            <template #default="{ row }">{{ row.isSoldOut ? '是' : '否' }}</template>
          </el-table-column>
          <el-table-column label="操作" width="240" fixed="right">
            <template #default="{ row }">
              <el-button link type="primary" @click="openEdit(row)">编辑</el-button>
              <el-button link @click="toggleAvailable(row)">{{ row.isAvailable ? '下架' : '上架' }}</el-button>
              <el-button link type="warning" @click="toggleSoldOut(row)">{{ row.isSoldOut ? '取消售罄' : '售罄' }}</el-button>
            </template>
          </el-table-column>
        </el-table>
      </el-tab-pane>

      <!-- ===== Tab 2: 套餐管理 ===== -->
      <el-tab-pane label="套餐管理" name="packages">
        <div class="sub-toolbar">
          <el-button type="primary" :disabled="!merchantId" @click="openCreatePackage">新增套餐</el-button>
          <span class="hint">用于配置"一荤两素"、"两荤两素"等套餐规则与基础价。</span>
        </div>
        <el-table :data="packages" v-loading="pkgLoading" stripe>
          <el-table-column prop="name" label="套餐名称" min-width="160" />
          <el-table-column label="基础价" width="100">
            <template #default="{ row }">¥{{ row.basePrice }}</template>
          </el-table-column>
          <el-table-column label="适用餐段" min-width="140">
            <template #default="{ row }">
              <span v-if="row.mealTypes && row.mealTypes.length">
                {{ row.mealTypes.map((m) => mealLabel(m)).join('、') }}
              </span>
              <span v-else class="muted">全部餐段</span>
            </template>
          </el-table-column>
          <el-table-column label="规则" min-width="220">
            <template #default="{ row }">{{ formatRules(row.rules) }}</template>
          </el-table-column>
          <el-table-column label="允许加菜" width="100">
            <template #default="{ row }">{{ row.allowExtra ? '是' : '否' }}</template>
          </el-table-column>
          <el-table-column label="启用" width="80">
            <template #default="{ row }">{{ row.isEnabled ? '是' : '否' }}</template>
          </el-table-column>
          <el-table-column label="操作" width="240" fixed="right">
            <template #default="{ row }">
              <el-button link type="primary" @click="openEditPackage(row)">编辑</el-button>
              <el-button link @click="togglePackageEnabled(row)">{{ row.isEnabled ? '停用' : '启用' }}</el-button>
              <el-button link type="danger" @click="removePackage(row)">删除</el-button>
            </template>
          </el-table-column>
        </el-table>
      </el-tab-pane>

      <!-- ===== Tab 3: 加菜管理 ===== -->
      <el-tab-pane label="加菜管理" name="extras">
        <div class="sub-toolbar">
          <el-button type="primary" :disabled="!merchantId" @click="openCreate('extra')">新增加菜</el-button>
          <span class="hint">加菜在下单时按数量计价，例如鸡腿 6 元、鸡蛋 2 元、米饭加量 2 元等。</span>
        </div>
        <el-table :data="extraDishes" v-loading="loading" stripe>
          <el-table-column prop="name" label="加菜名称" min-width="140" />
          <el-table-column label="加菜价" width="100">
            <template #default="{ row }">¥{{ row.extraPrice ?? 0 }}</template>
          </el-table-column>
          <el-table-column label="适用餐段" min-width="140">
            <template #default="{ row }">
              <span v-if="row.mealTypes && row.mealTypes.length">
                {{ row.mealTypes.map((m) => mealLabel(m)).join('、') }}
              </span>
              <span v-else class="muted">—</span>
            </template>
          </el-table-column>
          <el-table-column label="上架" width="80">
            <template #default="{ row }">{{ row.isAvailable ? '是' : '否' }}</template>
          </el-table-column>
          <el-table-column label="操作" width="200" fixed="right">
            <template #default="{ row }">
              <el-button link type="primary" @click="openEdit(row)">编辑</el-button>
              <el-button link @click="toggleAvailable(row)">{{ row.isAvailable ? '下架' : '上架' }}</el-button>
            </template>
          </el-table-column>
        </el-table>
      </el-tab-pane>
    </el-tabs>

    <!-- ===== 菜品 新增/编辑 弹窗 ===== -->
    <el-dialog v-model="dialogVisible" :title="form.id ? '编辑菜品' : '新增菜品'" width="560px">
      <el-form label-width="100px">
        <el-form-item label="菜品名称">
          <el-input v-model="form.name" />
        </el-form-item>
        <el-form-item label="分类" required>
          <el-select v-model="form.category" placeholder="选择分类" style="width: 100%">
            <el-option v-for="c in categoryOptions" :key="c.value" :label="c.label" :value="c.value" />
          </el-select>
        </el-form-item>
        <el-form-item v-if="form.category === 'extra'" label="加菜价格" required>
          <el-input-number v-model="form.extraPrice" :min="0" :step="0.5" />
        </el-form-item>
        <el-form-item v-else label="菜品价格">
          <el-input-number v-model="form.price" :min="0" :step="0.5" />
          <span class="hint">套餐体系下普通菜品价格可填 0。</span>
        </el-form-item>
        <el-form-item label="主餐段">
          <el-select v-model="form.mealType" style="width: 100%">
            <el-option v-for="m in mealOptions" :key="m.value" :label="m.label" :value="m.value" />
          </el-select>
        </el-form-item>
        <el-form-item label="适用餐段">
          <el-checkbox-group v-model="form.mealTypes">
            <el-checkbox v-for="m in mealOptions" :key="m.value" :value="m.value">{{ m.label }}</el-checkbox>
          </el-checkbox-group>
          <div class="hint">未勾选时默认按主餐段处理。</div>
        </el-form-item>
        <el-form-item label="图片">
          <el-input v-model="form.image" placeholder="图片 URL" />
          <el-upload :show-file-list="false" :http-request="uploadImage" accept="image/*" class="upload-btn">
            <el-button size="small" type="primary" plain>上传图片</el-button>
          </el-upload>
        </el-form-item>
        <el-form-item label="标签">
          <el-input v-model="form.tagsText" placeholder="多个标签用逗号分隔" />
        </el-form-item>
        <el-form-item label="排序">
          <el-input-number v-model="form.sortOrder" :min="0" />
        </el-form-item>
        <el-form-item label="菜品描述">
          <el-input v-model="form.description" type="textarea" :rows="3" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="dialogVisible = false">取消</el-button>
        <el-button type="primary" @click="save">保存</el-button>
      </template>
    </el-dialog>

    <!-- ===== 套餐 新增/编辑 弹窗 ===== -->
    <el-dialog v-model="pkgDialogVisible" :title="pkgForm.id ? '编辑套餐' : '新增套餐'" width="640px">
      <el-form label-width="120px">
        <el-form-item label="套餐名称" required>
          <el-input v-model="pkgForm.name" placeholder="例如：一荤两素套餐" />
        </el-form-item>
        <el-form-item label="基础价格" required>
          <el-input-number v-model="pkgForm.basePrice" :min="0" :step="0.5" />
          <span class="hint">员工选择该套餐时的基础金额，加菜在此基础上额外加价。</span>
        </el-form-item>
        <el-form-item label="适用餐段">
          <el-checkbox-group v-model="pkgForm.mealTypes">
            <el-checkbox v-for="m in mealOptions" :key="m.value" :value="m.value">{{ m.label }}</el-checkbox>
          </el-checkbox-group>
          <div class="hint">未勾选则全部餐段可用。</div>
        </el-form-item>
        <el-form-item label="套餐规则" required>
          <div class="rule-grid">
            <div class="rule-cell">
              <span class="rule-label">荤菜</span>
              <el-input-number v-model="pkgForm.rules.meat" :min="0" :max="20" size="small" />
            </div>
            <div class="rule-cell">
              <span class="rule-label">素菜</span>
              <el-input-number v-model="pkgForm.rules.vegetable" :min="0" :max="20" size="small" />
            </div>
            <div class="rule-cell">
              <span class="rule-label">主食</span>
              <el-input-number v-model="pkgForm.rules.staple" :min="0" :max="20" size="small" />
            </div>
            <div class="rule-cell">
              <span class="rule-label">汤品</span>
              <el-input-number v-model="pkgForm.rules.soup" :min="0" :max="20" size="small" />
            </div>
            <div class="rule-cell">
              <span class="rule-label">饮品</span>
              <el-input-number v-model="pkgForm.rules.drink" :min="0" :max="20" size="small" />
            </div>
          </div>
          <div class="hint">至少配置一项数量大于 0。</div>
        </el-form-item>
        <el-form-item label="允许加菜">
          <el-switch v-model="pkgForm.allowExtra" />
          <span class="hint">关闭后该套餐不允许员工再加菜。</span>
        </el-form-item>
        <el-form-item label="启用">
          <el-switch v-model="pkgForm.isEnabled" />
        </el-form-item>
        <el-form-item label="套餐说明">
          <el-input v-model="pkgForm.description" type="textarea" :rows="3" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="pkgDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="savePackage">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup>
import { computed, onMounted, reactive, ref } from 'vue';
import { useRoute } from 'vue-router';
import { ElMessage, ElMessageBox } from 'element-plus';
import {
  adminApi,
  DISH_CATEGORY_OPTIONS,
  MEAL_OPTIONS,
  dishCategoryLabel,
  mealLabel,
} from '../api/admin';

const route = useRoute();
const mealOptions = MEAL_OPTIONS;
const categoryOptions = DISH_CATEGORY_OPTIONS;

const merchants = ref([]);
const merchantId = ref(route.query.merchantId || '');
const activeTab = ref('library');

// ----- 菜品库 -----
const list = ref([]);
const loading = ref(false);
const mealType = ref('');
const categoryFilter = ref('');
const dialogVisible = ref(false);
const form = reactive(emptyDishForm());

const filteredDishes = computed(() => {
  let r = list.value;
  if (categoryFilter.value) {
    r = r.filter((d) => d.category === categoryFilter.value);
  } else {
    // 默认菜品库不展示 extra（加菜在另一个 tab）
    r = r.filter((d) => d.category !== 'extra');
  }
  return r;
});

const extraDishes = computed(() => list.value.filter((d) => d.category === 'extra'));

// ----- 套餐 -----
const packages = ref([]);
const pkgLoading = ref(false);
const pkgDialogVisible = ref(false);
const pkgForm = reactive(emptyPackageForm());

function emptyDishForm() {
  return {
    id: '',
    merchantId: '',
    name: '',
    category: '',
    price: 0,
    extraPrice: 0,
    mealType: 'lunch',
    mealTypes: [],
    image: 'dish',
    description: '',
    tagsText: '',
    sortOrder: 0,
  };
}

function emptyPackageForm() {
  return {
    id: '',
    name: '',
    description: '',
    basePrice: 0,
    mealTypes: [],
    rules: { meat: 0, vegetable: 0, staple: 0, soup: 0, drink: 0 },
    allowExtra: true,
    isEnabled: true,
  };
}

async function loadMerchants() {
  const res = await adminApi.listMerchants('approved');
  merchants.value = res.data;
  if (!merchantId.value && merchants.value.length > 0) {
    merchantId.value = merchants.value[0].id;
  }
}

async function loadDishes() {
  if (!merchantId.value) {
    list.value = [];
    return;
  }
  loading.value = true;
  try {
    const res = await adminApi.listDishes({
      merchantId: merchantId.value,
      mealType: mealType.value || undefined,
    });
    list.value = res.data;
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    loading.value = false;
  }
}

async function loadPackages() {
  if (!merchantId.value) {
    packages.value = [];
    return;
  }
  pkgLoading.value = true;
  try {
    const res = await adminApi.listPackages(merchantId.value);
    packages.value = res.data;
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    pkgLoading.value = false;
  }
}

async function onMerchantChange() {
  await Promise.all([loadDishes(), loadPackages()]);
}

// ===== 菜品 =====
function openCreate(presetCategory) {
  Object.assign(form, emptyDishForm(), {
    merchantId: merchantId.value,
    category: presetCategory || '',
  });
  dialogVisible.value = true;
}

function openEdit(row) {
  Object.assign(form, {
    id: row.id,
    merchantId: row.merchantId,
    name: row.name,
    category: row.category || '',
    price: row.price ?? 0,
    extraPrice: row.extraPrice ?? 0,
    mealType: row.mealType,
    mealTypes: Array.isArray(row.mealTypes) ? [...row.mealTypes] : [],
    image: row.image || 'dish',
    description: row.description || '',
    tagsText: (row.tags || []).join(','),
    sortOrder: row.sortOrder ?? 0,
  });
  dialogVisible.value = true;
}

function parseTags(text) {
  return text.split(/[,，]/).map((s) => s.trim()).filter(Boolean);
}

async function save() {
  if (!form.name) {
    ElMessage.warning('请填写菜品名称');
    return;
  }
  if (!form.category) {
    ElMessage.warning('请选择菜品分类');
    return;
  }
  if (form.category === 'extra' && !(form.extraPrice > 0)) {
    ElMessage.warning('加菜分类必须填写加菜价格');
    return;
  }
  const payload = {
    merchantId: form.merchantId,
    name: form.name,
    price: form.category === 'extra' ? 0 : Number(form.price) || 0,
    extraPrice: form.category === 'extra' ? Number(form.extraPrice) || 0 : 0,
    mealType: form.mealType,
    mealTypes: form.mealTypes,
    image: form.image,
    description: form.description,
    tags: parseTags(form.tagsText),
    sortOrder: form.sortOrder,
    category: form.category,
  };
  try {
    if (form.id) {
      await adminApi.updateDish(form.id, payload);
    } else {
      await adminApi.createDish(payload);
    }
    ElMessage.success('保存成功');
    dialogVisible.value = false;
    loadDishes();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

async function uploadImage({ file }) {
  try {
    const res = await adminApi.uploadDishImage(file);
    form.image = res.data.url;
    ElMessage.success('上传成功');
  } catch (e) {
    ElMessage.error(e.message || '上传失败');
  }
}

async function toggleAvailable(row) {
  try {
    await adminApi.setDishAvailable(row.id, !row.isAvailable);
    loadDishes();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

async function toggleSoldOut(row) {
  try {
    await adminApi.setDishSoldOut(row.id, !row.isSoldOut);
    loadDishes();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

async function saveSort(row, sortOrder) {
  if (sortOrder == null) return;
  try {
    await adminApi.setDishSort(row.id, sortOrder);
  } catch (e) {
    ElMessage.error(e.message);
    loadDishes();
  }
}

// ===== 套餐 =====
function openCreatePackage() {
  Object.assign(pkgForm, emptyPackageForm());
  pkgDialogVisible.value = true;
}

function openEditPackage(row) {
  Object.assign(pkgForm, {
    id: row.id,
    name: row.name,
    description: row.description || '',
    basePrice: row.basePrice ?? 0,
    mealTypes: Array.isArray(row.mealTypes) ? [...row.mealTypes] : [],
    rules: {
      meat: row.rules?.meat ?? 0,
      vegetable: row.rules?.vegetable ?? 0,
      staple: row.rules?.staple ?? 0,
      soup: row.rules?.soup ?? 0,
      drink: row.rules?.drink ?? 0,
    },
    allowExtra: row.allowExtra !== false,
    isEnabled: row.isEnabled !== false,
  });
  pkgDialogVisible.value = true;
}

function formatRules(rules) {
  if (!rules) return '—';
  const parts = [];
  const map = { meat: '荤', vegetable: '素', staple: '主食', soup: '汤', drink: '饮品' };
  for (const k of ['meat', 'vegetable', 'staple', 'soup', 'drink']) {
    if (rules[k] > 0) parts.push(`${rules[k]}${map[k]}`);
  }
  return parts.length ? parts.join(' + ') : '—';
}

async function savePackage() {
  if (!merchantId.value) {
    ElMessage.warning('请先选择商家');
    return;
  }
  if (!pkgForm.name) {
    ElMessage.warning('请填写套餐名称');
    return;
  }
  if (!(pkgForm.basePrice >= 0)) {
    ElMessage.warning('基础价格非法');
    return;
  }
  const ruleSum =
    (pkgForm.rules.meat || 0) +
    (pkgForm.rules.vegetable || 0) +
    (pkgForm.rules.staple || 0) +
    (pkgForm.rules.soup || 0) +
    (pkgForm.rules.drink || 0);
  if (ruleSum <= 0) {
    ElMessage.warning('套餐规则至少配置一项数量大于 0');
    return;
  }
  const payload = {
    merchantId: merchantId.value,
    name: pkgForm.name,
    description: pkgForm.description,
    basePrice: Number(pkgForm.basePrice) || 0,
    mealTypes: pkgForm.mealTypes,
    rules: pkgForm.rules,
    allowExtra: pkgForm.allowExtra,
    isEnabled: pkgForm.isEnabled,
  };
  try {
    if (pkgForm.id) {
      await adminApi.updatePackage(pkgForm.id, payload);
    } else {
      await adminApi.createPackage(payload);
    }
    ElMessage.success('保存成功');
    pkgDialogVisible.value = false;
    loadPackages();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

async function togglePackageEnabled(row) {
  try {
    await adminApi.setPackageEnabled(row.id, !row.isEnabled);
    loadPackages();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

async function removePackage(row) {
  try {
    await ElMessageBox.confirm(`确认删除套餐"${row.name}"？该操作不可恢复。`, '提示', {
      confirmButtonText: '删除',
      cancelButtonText: '取消',
      type: 'warning',
    });
  } catch {
    return;
  }
  try {
    await adminApi.deletePackage(row.id);
    ElMessage.success('已删除');
    loadPackages();
  } catch (e) {
    ElMessage.error(e.message);
  }
}

onMounted(async () => {
  await loadMerchants();
  await Promise.all([loadDishes(), loadPackages()]);
});
</script>

<style scoped>
.toolbar { display: flex; gap: 12px; margin-bottom: 16px; flex-wrap: wrap; }
.sub-toolbar { display: flex; gap: 12px; margin-bottom: 12px; flex-wrap: wrap; align-items: center; }
.hint { color: #999; font-size: 12px; margin-left: 8px; }
.muted { color: #aaa; }
.upload-btn { margin-top: 8px; }
.dish-tabs { margin-top: 8px; }
.rule-grid {
  display: grid;
  grid-template-columns: repeat(5, minmax(0, 1fr));
  gap: 8px;
  width: 100%;
}
.rule-cell { display: flex; flex-direction: column; gap: 4px; }
.rule-label { font-size: 13px; color: #555; }
</style>
