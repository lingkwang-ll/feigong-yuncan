<template>
  <div class="page-card support-page">
    <div class="page-head">
      <h2 class="page-title">客服消息</h2>
      <el-button type="primary" @click="loadList">刷新</el-button>
    </div>

    <el-table :data="rows" stripe v-loading="loading" @row-click="openChat">
      <el-table-column label="来源" width="90">
        <template #default="{ row }">
          {{ row.userRole === 'merchant' ? '商家' : '员工' }}
        </template>
      </el-table-column>
      <el-table-column prop="userName" label="姓名" width="120" />
      <el-table-column prop="userPhone" label="手机号" width="130" />
      <el-table-column prop="merchantName" label="所属商家" min-width="140">
        <template #default="{ row }">{{ row.merchantName || '—' }}</template>
      </el-table-column>
      <el-table-column prop="lastMessageText" label="最新消息" min-width="180" show-overflow-tooltip />
      <el-table-column label="未读" width="80">
        <template #default="{ row }">
          <el-badge v-if="row.adminUnreadCount > 0" :value="row.adminUnreadCount" />
          <span v-else>—</span>
        </template>
      </el-table-column>
      <el-table-column label="状态" width="100">
        <template #default="{ row }">{{ statusLabel(row.status) }}</template>
      </el-table-column>
      <el-table-column label="更新时间" width="170">
        <template #default="{ row }">{{ formatTime(row.lastMessageAt || row.updatedAt) }}</template>
      </el-table-column>
      <el-table-column label="操作" width="180" fixed="right">
        <template #default="{ row }">
          <el-button link type="primary" @click.stop="openChat(row)">查看</el-button>
          <el-button
            v-if="row.status !== 'resolved'"
            link
            type="success"
            @click.stop="markResolved(row)"
          >
            标记已解决
          </el-button>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog
      v-model="chatVisible"
      :title="chatTitle"
      width="720px"
      destroy-on-close
      @closed="stopPoll"
    >
      <div v-if="activeConv" class="chat-meta">
        <span>{{ activeConv.userRole === 'merchant' ? '商家' : '员工' }}</span>
        <span>{{ activeConv.userName }}</span>
        <span>{{ activeConv.userPhone }}</span>
        <span v-if="activeConv.merchantName">商家：{{ activeConv.merchantName }}</span>
        <el-tag size="small">{{ statusLabel(activeConv.status) }}</el-tag>
      </div>

      <div ref="msgBox" class="chat-messages" v-loading="msgLoading">
        <div v-if="!messages.length" class="empty-hint">暂无消息</div>
        <div
          v-for="msg in messages"
          :key="msg.id"
          class="msg-row"
          :class="{ mine: msg.senderType === 'admin' }"
        >
          <div class="bubble">
            <img
              v-if="msg.messageType === 'image' && msg.imageUrl"
              :src="fullImageUrl(msg.imageUrl)"
              class="msg-image"
              alt="图片"
            />
            <span
              v-else
              :class="{ emoji: msg.messageType === 'emoji' }"
            >{{ msg.content }}</span>
          </div>
          <div class="time">{{ formatTime(msg.createdAt) }}</div>
        </div>
      </div>

      <div class="chat-input">
        <el-button @click="pickEmoji">😀</el-button>
        <el-upload
          :show-file-list="false"
          accept="image/*"
          :http-request="uploadImage"
        >
          <el-button>图片</el-button>
        </el-upload>
        <el-input
          v-model="replyText"
          placeholder="回复用户…"
          @keyup.enter="sendReply"
        />
        <el-button type="primary" :loading="sending" @click="sendReply">发送</el-button>
      </div>
    </el-dialog>
  </div>
</template>

<script setup>
import { computed, nextTick, onMounted, onUnmounted, ref } from 'vue';
import { ElMessage } from 'element-plus';
import { adminApi, fullImageUrl } from '../api/admin';

const loading = ref(false);
const rows = ref([]);
const chatVisible = ref(false);
const activeConv = ref(null);
const messages = ref([]);
const msgLoading = ref(false);
const replyText = ref('');
const sending = ref(false);
const msgBox = ref(null);
let pollTimer = null;

const chatTitle = computed(() =>
  activeConv.value ? `客服会话 · ${activeConv.value.userName || ''}` : '客服会话',
);

const STATUS_MAP = {
  open: '待处理',
  pending: '处理中',
  resolved: '已解决',
  closed: '已关闭',
};

function statusLabel(s) {
  return STATUS_MAP[s] || s || '—';
}

function formatTime(v) {
  if (!v) return '—';
  const d = new Date(v);
  if (Number.isNaN(d.getTime())) return v;
  return d.toLocaleString('zh-CN', { hour12: false });
}

async function loadList() {
  loading.value = true;
  try {
    const res = await adminApi.listSupportConversations();
    rows.value = res.data || [];
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    loading.value = false;
  }
}

async function openChat(row) {
  activeConv.value = row;
  chatVisible.value = true;
  await loadMessages();
  startPoll();
}

async function loadMessages() {
  if (!activeConv.value) return;
  msgLoading.value = true;
  try {
    const res = await adminApi.listSupportMessages(activeConv.value.id);
    messages.value = res.data || [];
    await adminApi.markSupportRead(activeConv.value.id);
    activeConv.value = {
      ...activeConv.value,
      adminUnreadCount: 0,
    };
    await loadList();
    await nextTick();
    if (msgBox.value) {
      msgBox.value.scrollTop = msgBox.value.scrollHeight;
    }
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    msgLoading.value = false;
  }
}

function startPoll() {
  stopPoll();
  pollTimer = setInterval(loadMessages, 5000);
}

function stopPoll() {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

async function sendReply() {
  const text = replyText.value.trim();
  if (!text || !activeConv.value) return;
  sending.value = true;
  try {
    await adminApi.sendSupportMessage(activeConv.value.id, {
      messageType: 'text',
      content: text,
    });
    replyText.value = '';
    await loadMessages();
  } catch (e) {
    ElMessage.error(e.message || '发送失败');
  } finally {
    sending.value = false;
  }
}

async function pickEmoji() {
  const emoji = '🙂';
  if (!activeConv.value) return;
  sending.value = true;
  try {
    await adminApi.sendSupportMessage(activeConv.value.id, {
      messageType: 'emoji',
      content: emoji,
    });
    await loadMessages();
  } catch (e) {
    ElMessage.error(e.message);
  } finally {
    sending.value = false;
  }
}

async function uploadImage({ file }) {
  if (!activeConv.value) return;
  sending.value = true;
  try {
    await adminApi.uploadSupportImage(file, activeConv.value.id);
    await loadMessages();
  } catch (e) {
    ElMessage.error(e.message || '图片上传失败');
  } finally {
    sending.value = false;
  }
}

async function markResolved(row) {
  try {
    await adminApi.updateSupportStatus(row.id, 'resolved');
    ElMessage.success('已标记为已解决');
    await loadList();
    if (activeConv.value?.id === row.id) {
      activeConv.value = { ...activeConv.value, status: 'resolved' };
    }
  } catch (e) {
    ElMessage.error(e.message);
  }
}

onMounted(loadList);
onUnmounted(stopPoll);
</script>

<style scoped>
.page-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 16px;
}
.chat-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 12px;
  margin-bottom: 12px;
  font-size: 13px;
  color: #666;
}
.chat-messages {
  height: 360px;
  overflow-y: auto;
  background: #f7f8fa;
  border-radius: 8px;
  padding: 12px;
  margin-bottom: 12px;
}
.empty-hint {
  text-align: center;
  color: #999;
  padding: 40px 0;
}
.msg-row {
  margin-bottom: 12px;
  max-width: 75%;
}
.msg-row.mine {
  margin-left: auto;
  text-align: right;
}
.bubble {
  display: inline-block;
  padding: 8px 12px;
  border-radius: 12px;
  background: #fff;
  border: 1px solid #eee;
  text-align: left;
}
.msg-row.mine .bubble {
  background: #16a34a;
  color: #fff;
  border-color: #16a34a;
}
.bubble .emoji {
  font-size: 24px;
}
.msg-image {
  max-width: 200px;
  border-radius: 8px;
}
.time {
  font-size: 11px;
  color: #999;
  margin-top: 4px;
}
.chat-input {
  display: flex;
  gap: 8px;
  align-items: center;
}
</style>
