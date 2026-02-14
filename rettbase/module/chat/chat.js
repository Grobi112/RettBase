// chat.js – RettBase Chat-Modul
// 1:1-Chat, Gruppen-Chat, Bilder und Dateien versenden

import { auth, db, storage } from "../../firebase-config.js";
import {
  collection,
  doc,
  getDoc,
  getDocs,
  setDoc,
  addDoc,
  updateDoc,
  deleteDoc,
  query,
  where,
  orderBy,
  onSnapshot,
  serverTimestamp,
  limit,
  arrayUnion,
  writeBatch,
  increment,
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";
import { ref, uploadBytes, getDownloadURL } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-storage.js";

let userAuthData = null;
let allMitarbeiter = [];
let allChats = [];
/** Map E-Mail → Firebase Auth UID (aus users-Collection) für korrekte Chat-Zuordnung */
let usersEmailToUid = {};
let currentChatId = null;
let messagesUnsubscribe = null;
let chatsPollInterval = null;
let pendingAttachments = [];
const MAX_FILE_SIZE = 10 * 1024 * 1024;
const IMAGE_TYPES = ['image/jpeg', 'image/png', 'image/gif', 'image/webp'];
const MIN_VOICE_DURATION = 0.5;
let mediaRecorder = null;
let recordChunks = [];
let recordStartTime = 0;
let recordCooldownUntil = 0;

const backBtn = document.getElementById("backBtn");
const newChatBtn = document.getElementById("newChatBtn");
const newGroupBtn = document.getElementById("newGroupBtn");
const chatSearch = document.getElementById("chatSearch");
const chatList = document.getElementById("chatList");
const chatListEmpty = document.getElementById("chatListEmpty");
const noChatSelected = document.getElementById("noChatSelected");
const chatActive = document.getElementById("chatActive");
const chatTitle = document.getElementById("chatTitle");
const chatSubtitle = document.getElementById("chatSubtitle");
const messagesList = document.getElementById("messagesList");
const messageInput = document.getElementById("messageInput");
const sendBtn = document.getElementById("sendBtn");
const attachBtn = document.getElementById("attachBtn");
const recordBtn = document.getElementById("recordBtn");
const micPermissionModal = document.getElementById("micPermissionModal");
const micPermissionBody = document.getElementById("micPermissionBody");
const micPermissionAllow = document.getElementById("micPermissionAllow");
const micPermissionCancel = document.getElementById("micPermissionCancel");
const micPermissionNewTab = document.getElementById("micPermissionNewTab");
const closeMicPermissionModal = document.getElementById("closeMicPermissionModal");
const fileInput = document.getElementById("fileInput");
const attachmentPreview = document.getElementById("attachmentPreview");
const selectUserModal = document.getElementById("selectUserModal");
const closeSelectUserModal = document.getElementById("closeSelectUserModal");
const userSearch = document.getElementById("userSearch");
const userList = document.getElementById("userList");
const createGroupModal = document.getElementById("createGroupModal");
const closeCreateGroupModal = document.getElementById("closeCreateGroupModal");
const groupName = document.getElementById("groupName");
const groupMemberSearch = document.getElementById("groupMemberSearch");
const groupMemberList = document.getElementById("groupMemberList");
const selectedMembers = document.getElementById("selectedMembers");
const cancelCreateGroup = document.getElementById("cancelCreateGroup");
const confirmCreateGroup = document.getElementById("confirmCreateGroup");
const chatBackToList = document.getElementById("chatBackToList");
const chatListPanel = document.getElementById("chatListPanel");
const chatViewPanel = document.getElementById("chatViewPanel");

window.addEventListener("DOMContentLoaded", () => {
  waitForAuthData().then((data) => {
    userAuthData = data;
    if (!userAuthData?.companyId && window === window.top) {
      window.location.href = window.location.origin + "/dashboard.html";
      return;
    }
    initializeChat();
  }).catch((err) => console.error("Chat: Auth fehlgeschlagen", err));
});

function waitForAuthData() {
  return new Promise((resolve) => {
    if (window === window.top) {
      const stored = localStorage.getItem("rettbase_chat_auth");
      if (stored) {
        try {
          const data = JSON.parse(stored);
          localStorage.removeItem("rettbase_chat_auth");
          resolve(data);
          return;
        } catch (e) {}
      }
      resolve(null);
      return;
    }
    // Im iframe (z.B. Flutter Web nach auth-callback): postMessage ODER Firebase-Auth-Fallback
    window.parent.postMessage({ type: "IFRAME_READY" }, "*");
    const handler = (e) => {
      if (e.data && e.data.type === "AUTH_DATA") {
        window.removeEventListener("message", handler);
        clearTimeout(fallbackTimer);
        resolve(e.data.data || e.data);
      }
    };
    window.addEventListener("message", handler);
    // Fallback: Nach auth-callback ist Firebase Auth schon angemeldet (Flutter Web iframe)
    const AUTH_FALLBACK_MS = 1500;
    const fallbackTimer = setTimeout(async () => {
      const user = auth?.currentUser;
      if (user) {
        const host = typeof location !== "undefined" ? location.hostname : "";
        const m = host.match(/([^.]+)\.rettbase\.de$/);
        const companyId = m && !["www", "login"].includes(m[1]) ? m[1] : "";
        if (companyId) {
          window.removeEventListener("message", handler);
          const data = {
            uid: user.uid,
            email: user.email || "",
            companyId,
            role: "user"
          };
          resolve(data);
          return;
        }
      }
      // Kein User oder keine companyId – weiter auf AUTH_DATA warten (Dashboard sendet es)
    }, AUTH_FALLBACK_MS);
  });
}

function getCompanyId() {
  const host = typeof location !== "undefined" ? location.hostname : "";
  const m = host.match(/([^.]+)\.rettbase\.de$/);
  if (m && !["www", "login"].includes(m[1])) return m[1];
  return userAuthData?.companyId || "";
}
function getUserId() { return userAuthData?.uid || ""; }

function getSenderName() {
  const m = userAuthData?.mitarbeiterData || userAuthData;
  if (m?.vorname || m?.nachname) return `${m.vorname || ""} ${m.nachname || ""}`.trim();
  return userAuthData?.email || "Unbekannt";
}

async function loadCurrentUserMitarbeiterData() {
  const companyId = getCompanyId(), uid = getUserId();
  if (!companyId || !uid) return;
  try {
    const q = query(collection(db, "kunden", companyId, "mitarbeiter"), where("uid", "==", uid));
    const snap = await getDocs(q);
    if (!snap.empty) userAuthData.mitarbeiterData = snap.docs[0].data();
    else {
      const directSnap = await getDoc(doc(db, "kunden", companyId, "mitarbeiter", uid));
      if (directSnap.exists()) userAuthData.mitarbeiterData = directSnap.data();
    }
  } catch (e) { console.warn("Mitarbeiterdaten:", e); }
}

function getDirectChatId(u1, u2) { const a = [u1, u2].sort(); return `direct_${a[0]}_${a[1]}`; }

/** Prüft ob Name ein "Extern"-Platzhalter ist (z.B. "Extern", "Extern 1", "Extern 2") */
function isExternPlaceholder(name) {
  if (!name || typeof name !== "string") return false;
  return /^Extern(\s+\d+)?$/i.test(name.trim());
}
function escapeHtml(s) { const d = document.createElement("div"); d.textContent = s || ""; return d.innerHTML; }
function getInitials(n) { return (n || "").split(" ").map(p => p[0]).join("").toUpperCase().slice(0, 2) || "?"; }
function formatTime(t) {
  if (!t) return "";
  const d = t.toDate ? t.toDate() : new Date(t);
  const now = new Date();
  if (now - d < 86400000) return d.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });
  if (now - d < 604800000) return d.toLocaleDateString("de-DE", { weekday: "short" });
  return d.toLocaleDateString("de-DE", { day: "2-digit", month: "2-digit" });
}

async function initializeChat() {
  if (!userAuthData?.companyId) return;
  await loadCurrentUserMitarbeiterData();
  await loadMitarbeiter();
  setupEventListeners();
  subscribeToChats();
  updateMobileLayout();
  window.addEventListener("resize", updateMobileLayout);
  backBtn?.addEventListener("click", () => {
    if (isMobileView() && currentChatId) {
      backToChatList();
    } else {
      if (window.parent?.document.getElementById("contentFrame")) window.parent.postMessage({ type: "NAVIGATE_TO_HOME" }, "*");
      else window.location.href = "/home.html";
    }
  });
}

async function loadMitarbeiter() {
  const companyId = getCompanyId();
  if (!companyId) return;
  try {
    // Users laden: E-Mail → UID für korrekte Chat-Zuordnung (Empfänger muss seine UID in participants haben)
    usersEmailToUid = {};
    const usersSnap = await getDocs(collection(db, "kunden", companyId, "users"));
    usersSnap.forEach((u) => {
      const em = (u.data().email || "").toLowerCase().trim();
      if (em) usersEmailToUid[em] = u.id;
    });

    const snap = await getDocs(collection(db, "kunden", companyId, "mitarbeiter"));
    allMitarbeiter = [];
    snap.forEach((docSnap) => {
      const d = docSnap.data();
      if (d.active === false) return;
      let uid = usersEmailToUid[(d.email || d.eMail || "").toLowerCase().trim()] || d.uid || docSnap.id;
      if (uid && uid !== getUserId()) {
        const vorname = d.vorname || "", nachname = d.nachname || "";
        const name = [vorname, nachname].filter(Boolean).join(" ") || d.name || d.email || d.eMail || "Unbekannt";
        if (isExternPlaceholder(vorname) || isExternPlaceholder(nachname) || isExternPlaceholder(name) || isExternPlaceholder(d.name)) return;
        allMitarbeiter.push({ uid, docId: docSnap.id, vorname, nachname, name, email: d.email || d.eMail || "" });
      }
    });
  } catch (e) { console.error("Mitarbeiter laden:", e); }
}

function setupEventListeners() {
  newChatBtn?.addEventListener("click", () => { selectUserModal.classList.add("show"); userSearch.value = ""; renderUserList(""); });
  newGroupBtn?.addEventListener("click", () => { createGroupModal.classList.add("show"); groupName.value = ""; groupMemberSearch.value = ""; selectedGroupMembers = []; renderGroupMemberList(""); renderSelectedMembers(); });
  closeSelectUserModal?.addEventListener("click", () => selectUserModal.classList.remove("show"));
  closeCreateGroupModal?.addEventListener("click", () => createGroupModal.classList.remove("show"));
  cancelCreateGroup?.addEventListener("click", () => createGroupModal.classList.remove("show"));
  chatSearch?.addEventListener("input", (e) => filterChatList(e.target.value));
  messageInput?.addEventListener("keydown", (e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); sendMessage(); } });
  messageInput?.addEventListener("input", () => { sendBtn.disabled = !messageInput.value.trim() && pendingAttachments.length === 0; });
  sendBtn?.addEventListener("click", sendMessage);
  attachBtn?.addEventListener("click", () => fileInput?.click());
  fileInput?.addEventListener("change", handleFileSelect);
  setupVoiceRecording();
  confirmCreateGroup?.addEventListener("click", createGroup);
  userSearch?.addEventListener("input", (e) => renderUserList(e.target.value));
  groupMemberSearch?.addEventListener("input", (e) => renderGroupMemberList(e.target.value));
  selectUserModal?.addEventListener("click", (e) => { if (e.target === selectUserModal) selectUserModal.classList.remove("show"); });
  createGroupModal?.addEventListener("click", (e) => { if (e.target === createGroupModal) createGroupModal.classList.remove("show"); });
  chatBackToList?.addEventListener("click", () => backToChatList());
  document.addEventListener("click", (e) => {
    const menu = document.getElementById("msgContextMenu");
    if (menu?.classList.contains("show") && !e.target.closest("#msgContextMenu")) hideMessageContextMenu();
  });
}

function isMobileView() { return window.innerWidth <= 768; }

function updateMobileLayout() {
  if (!isMobileView()) {
    chatListPanel?.classList.remove("hidden-mobile");
    chatViewPanel?.classList.remove("visible-mobile");
    noChatSelected?.classList.remove("hidden-mobile");
    chatActive?.classList.remove("hidden-mobile");
    chatBackToList?.style.setProperty("display", "none");
    return;
  }
  chatBackToList?.style.setProperty("display", currentChatId ? "flex" : "none");
  if (currentChatId) {
    chatListPanel?.classList.add("hidden-mobile");
    chatViewPanel?.classList.add("visible-mobile");
  } else {
    chatListPanel?.classList.remove("hidden-mobile");
    chatViewPanel?.classList.remove("visible-mobile");
  }
}

function backToChatList() {
  if (!currentChatId) return;
  if (messagesUnsubscribe) { messagesUnsubscribe(); messagesUnsubscribe = null; }
  currentChatId = null;
  noChatSelected.style.display = "flex";
  chatActive.style.display = "none";
  renderChatList();
  updateMobileLayout();
}

function subscribeToChats() {
  if (chatsPollInterval) { clearInterval(chatsPollInterval); chatsPollInterval = null; }
  const companyId = getCompanyId(), userId = getUserId();
  if (!companyId || !userId) return;
  const chatsRef = collection(db, "kunden", companyId, "chats");
  const q = query(chatsRef, where("participants", "array-contains", userId));
  const applySnapshot = (snapshot) => {
    allChats = [];
    if (snapshot.forEach) {
      snapshot.forEach((docSnap) => allChats.push({ id: docSnap.id, ...docSnap.data() }));
    } else if (snapshot.docs) {
      snapshot.docs.forEach((d) => allChats.push({ id: d.id, ...d.data() }));
    }
    allChats = allChats.filter((c) => !(c.deletedBy || []).includes(userId));
    allChats.sort((a, b) => (b.lastMessageAt?.toMillis?.() || 0) - (a.lastMessageAt?.toMillis?.() || 0));
    renderChatList();
  };
  const pollFallback = () => {
    getDocs(q).then(applySnapshot);
  };
  const unsub = onSnapshot(q, applySnapshot, (err) => {
    console.warn("Chat-Listener Fehler, nutze Polling-Fallback:", err?.code, err?.message);
    pollFallback();
    chatsPollInterval = setInterval(pollFallback, 2000);
  });
}

function getChatDisplayName(chat) {
  if (chat.name) return chat.name;
  const others = (chat.participantNames || []).filter(p => p.uid !== getUserId());
  return others.map(p => p.name).join(", ") || "Chat";
}

function setupSwipeToDelete(wrapper) {
  const slider = wrapper.querySelector(".chat-item-slider");
  const item = wrapper.querySelector(".chat-item");
  let startX = 0, startY = 0, currentX = 0, isDragging = false, didSwipe = false;
  const deleteWidth = window.innerWidth <= 768 ? 60 : 70;
  const SWIPE_THRESHOLD = Math.min(deleteWidth, 60);

  const onStart = (x, y) => {
    startX = x;
    startY = y || 0;
    currentX = x;
    isDragging = true;
    didSwipe = false;
  };
  const onMove = (x, y) => {
    if (!isDragging) return;
    currentX = x;
    const diffX = startX - currentX;
    const diffY = Math.abs((y || 0) - startY);
    if (diffX > 0 && diffX > diffY) {
      slider.style.transform = `translateX(-${Math.min(diffX, deleteWidth)}px)`;
    }
  };
  const onEnd = () => {
    if (!isDragging) return;
    isDragging = false;
    const diff = startX - currentX;
    if (diff > SWIPE_THRESHOLD) {
      wrapper.classList.add("swiped");
      slider.style.transform = "";
      didSwipe = true;
    } else {
      wrapper.classList.remove("swiped");
      slider.style.transform = "";
    }
  };

  const handleMouseMove = (e) => onMove(e.clientX, e.clientY);
  const handleMouseUp = () => { onEnd(); document.removeEventListener("mousemove", handleMouseMove); document.removeEventListener("mouseup", handleMouseUp); };

  item.addEventListener("touchstart", (e) => onStart(e.touches[0].clientX, e.touches[0].clientY), { passive: true });
  item.addEventListener("touchmove", (e) => {
    const dx = Math.abs(e.touches[0].clientX - startX);
    const dy = Math.abs(e.touches[0].clientY - startY);
    if (isDragging && dx > 5 && dx > dy) e.preventDefault();
    onMove(e.touches[0].clientX, e.touches[0].clientY);
  }, { passive: false });
  item.addEventListener("touchend", onEnd, { passive: true });

  item.addEventListener("mousedown", (e) => {
    if (e.button === 0) { onStart(e.clientX, e.clientY); document.addEventListener("mousemove", handleMouseMove); document.addEventListener("mouseup", handleMouseUp); }
  });

  wrapper._didSwipe = () => didSwipe;
  wrapper._clearDidSwipe = () => { didSwipe = false; };
}

async function deleteChat(chatId, wrapperEl) {
  if (!confirm("Chat aus deiner Liste entfernen? (Für den anderen sichtbar, bis er ebenfalls löscht)")) return;
  const companyId = getCompanyId(), userId = getUserId();
  if (!companyId || !userId) return;
  try {
    const chatRef = doc(db, "kunden", companyId, "chats", chatId);
    await updateDoc(chatRef, { deletedBy: arrayUnion(userId) });
    const chatSnap = await getDoc(chatRef);
    if (!chatSnap.exists()) return;
    const chatData = chatSnap.data();
    const participants = chatData.participants || [];
    const deletedBy = chatData.deletedBy || [];
    const allDeleted = participants.every((p) => deletedBy.includes(p));
    if (allDeleted) {
      const messagesRef = collection(db, "kunden", companyId, "chats", chatId, "messages");
      const snap = await getDocs(messagesRef);
      for (const d of snap.docs) await deleteDoc(d.ref);
      await deleteDoc(chatRef);
    }

    if (currentChatId === chatId) {
      currentChatId = null;
      if (messagesUnsubscribe) { messagesUnsubscribe(); messagesUnsubscribe = null; }
      noChatSelected.style.display = "flex";
      chatActive.style.display = "none";
      updateMobileLayout();
    }
    if (wrapperEl) wrapperEl.remove();
    allChats = allChats.filter(c => c.id !== chatId);
    renderChatList();
  } catch (e) {
    console.error("Chat löschen:", e);
    alert("Chat konnte nicht gelöscht werden.");
  }
}

function filterChatList(filter) {
  const f = (filter || "").toLowerCase();
  const items = allChats.filter(c => (c.name || getChatDisplayName(c)).toLowerCase().includes(f));
  renderChatList(items);
}

function renderChatList(items) {
  items = items !== undefined ? items : allChats;
  const filter = chatSearch?.value?.toLowerCase() || "";
  if (filter) items = items.filter(c => (c.name || getChatDisplayName(c)).toLowerCase().includes(filter));
  chatListEmpty.style.display = items.length === 0 ? "block" : "none";
  chatList.querySelectorAll(".chat-item-wrapper").forEach(el => el.remove());
  const userId = getUserId();
  items.forEach(chat => {
    const name = chat.name || getChatDisplayName(chat);
    let unread = Math.max(0, (chat.unreadCount || {})[userId] || 0);
    if (unread === 0) {
      const lastFrom = chat.lastMessageFrom;
      const lastAt = chat.lastMessageAt?.toMillis?.() || 0;
      const lastRead = (chat.lastReadAt || {})[userId];
      const lastReadMs = lastRead?.toMillis?.() || 0;
      if (lastFrom && lastFrom !== userId && lastAt > lastReadMs) unread = 1;
    }
    const hasUnread = unread > 0;
    const wrapper = document.createElement("div");
    wrapper.className = "chat-item-wrapper" + (hasUnread ? " has-unread" : "");
    wrapper.dataset.chatId = chat.id;
    const unreadBadge = hasUnread ? `<span class="chat-item-unread-badge">${unread > 99 ? "99+" : unread}</span>` : "";
    wrapper.innerHTML = `<div class="chat-item-slider">
      <div class="chat-item ${chat.id === currentChatId ? " active" : ""}">
        <div class="chat-item-avatar ${chat.type === "group" ? "group" : ""}">${getInitials(name)}</div>
        <div class="chat-item-content"><div class="chat-item-name-row"><span class="chat-item-name">${escapeHtml(name)}</span>${unreadBadge}</div><div class="chat-item-preview">${escapeHtml(chat.lastMessageText || "Keine Nachrichten")}</div></div>
        <div class="chat-item-time">${formatTime(chat.lastMessageAt)}</div>
      </div>
      <button type="button" class="chat-item-delete" title="Chat löschen"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path><line x1="10" y1="11" x2="10" y2="17"></line><line x1="14" y1="11" x2="14" y2="17"></line></svg></button>
    </div>`;
    const itemEl = wrapper.querySelector(".chat-item");
    const deleteBtn = wrapper.querySelector(".chat-item-delete");
    itemEl.addEventListener("click", (e) => {
      if (wrapper.classList.contains("swiped")) {
        if (wrapper._didSwipe && wrapper._didSwipe()) {
          wrapper._clearDidSwipe && wrapper._clearDidSwipe();
          return;
        }
        wrapper.classList.remove("swiped");
        wrapper.querySelector(".chat-item-slider").style.transform = "";
      } else {
        selectChat(chat.id);
      }
    });
    deleteBtn.addEventListener("click", (e) => { e.stopPropagation(); deleteChat(chat.id, wrapper); });
    setupSwipeToDelete(wrapper);
    chatList.appendChild(wrapper);
  });
}

function selectChat(chatId) {
  if (messagesUnsubscribe) { messagesUnsubscribe(); messagesUnsubscribe = null; }
  currentChatId = chatId;
  noChatSelected.style.display = "none";
  chatActive.style.display = "flex";
  const chat = allChats.find(c => c.id === chatId);
  chatTitle.textContent = chat?.name || getChatDisplayName(chat || { id: chatId });
  chatSubtitle.textContent = chat?.type === "group" ? `${(chat.participants || []).length} Mitglieder` : "";
  renderChatList();
  loadMessages(chatId);
  messageInput.focus();
  updateMobileLayout();
  sendBtn.disabled = true;
}

function loadMessages(chatId) {
  const companyId = getCompanyId(), userId = getUserId(), messagesRef = collection(db, "kunden", companyId, "chats", chatId, "messages");
  const chat = allChats.find(c => c.id === chatId);
  const q = query(messagesRef, orderBy("createdAt", "asc"), limit(100));
  const chatRef = doc(db, "kunden", getCompanyId(), "chats", chatId);
  updateDoc(chatRef, { [`lastReadAt.${userId}`]: serverTimestamp(), [`unreadCount.${userId}`]: 0 }).catch(() => {});
  messagesUnsubscribe = onSnapshot(q, async (snapshot) => {
    const toMark = [];
    snapshot.forEach(d => {
      const data = d.data();
      if (data.from !== userId && !(data.deletedBy || []).includes(userId)) {
        const readBy = data.readBy || [];
        if (!readBy.includes(userId)) toMark.push(d.ref);
      }
    });
    messagesList.innerHTML = "";
    snapshot.forEach(d => {
      const data = d.data();
      if ((data.deletedBy || []).includes(userId)) return;
      appendMessage({ id: d.id, ...data }, chat);
    });
    document.getElementById("scrollAnchor")?.scrollIntoView({ behavior: "smooth" });
    if (toMark.length > 0) {
      const batch = writeBatch(db);
      toMark.slice(0, 50).forEach(ref => batch.update(ref, { readBy: arrayUnion(userId) }));
      try { await batch.commit(); } catch (e) { console.warn("Mark read:", e); }
    }
  });
}

function getRecipientIds(chat) {
  if (!chat) return [];
  return (chat.participants || []).filter(uid => uid !== getUserId());
}

function getStatusChecks(msg, chat) {
  if (msg.from !== getUserId()) return "";
  const recipients = getRecipientIds(chat);
  if (recipients.length === 0) return "";
  const readBy = msg.readBy || [];
  const anyRead = recipients.some(r => readBy.includes(r));
  if (anyRead) return `<span class="msg-checks msg-checks-read" title="Gelesen">✓</span>`;
  return `<span class="msg-checks msg-checks-sent" title="Gesendet">✓</span>`;
}

function appendMessage(msg, chat) {
  const div = document.createElement("div");
  const isSent = msg.from === getUserId();
  div.className = `message ${isSent ? "sent" : "received"}`;
  div.dataset.messageId = msg.id;
  div.dataset.chatId = currentChatId;
  let attHtml = "";
  if (msg.attachments?.length) {
    attHtml = msg.attachments.map(att => {
      if (IMAGE_TYPES.includes(att.type)) return `<div class="message-attachment"><img src="${escapeHtml(att.url)}" alt="${escapeHtml(att.name)}" onclick="window.open('${escapeHtml(att.url)}')"></div>`;
      if ((att.type || "").startsWith("audio/")) {
        const dur = att.duration != null ? `${Math.floor(att.duration / 60)}:${String(att.duration % 60).padStart(2, "0")}` : "";
        const bars = [40, 72, 48, 88, 55, 95, 42, 68, 52, 82, 58, 78, 45, 85, 50, 90, 38, 75];
        const barHtml = bars.map(h => `<span class="voice-bar" style="height:${h}%"></span>`).join("");
        return `<div class="message-attachment voice-message"><audio src="${escapeHtml(att.url)}" preload="metadata"></audio><button type="button" class="voice-play-btn" aria-label="Abspielen"><svg class="icon-play" width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"></polygon></svg><svg class="icon-pause" width="18" height="18" viewBox="0 0 24 24" fill="currentColor" style="display:none"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg></button><div class="voice-waveform-wrap"><div class="voice-waveform voice-waveform-bg">${barHtml}</div><div class="voice-waveform voice-waveform-fill"><div class="voice-waveform-inner">${barHtml}</div></div></div><span class="voice-duration">${escapeHtml(dur)}</span></div>`;
      }
      return `<div class="message-attachment"><a href="${escapeHtml(att.url)}" target="_blank">📎 ${escapeHtml(att.name)}</a></div>`;
    }).join("");
  }
  const time = msg.createdAt?.toDate?.() ? msg.createdAt.toDate().toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" }) : "";
  const checks = getStatusChecks(msg, chat);
  div.innerHTML = `<div class="message-bubble">${msg.text ? `<div class="message-text">${escapeHtml(msg.text)}</div>` : ""}${attHtml ? `<div class="message-attachments">${attHtml}</div>` : ""}<div class="message-meta"><span class="message-sender">${escapeHtml(isSent ? "Du" : (msg.senderName || "Unbekannt"))}</span>${time ? ` ${time}` : ""}${checks}</div></div>`;
  messagesList.appendChild(div);
  div.querySelectorAll(".voice-play-btn").forEach((btn) => {
    const wrap = btn.closest(".voice-message");
    const audio = wrap?.querySelector("audio");
    const progressEl = wrap?.querySelector(".voice-waveform-fill");
    const iconPlay = btn?.querySelector(".icon-play");
    const iconPause = btn?.querySelector(".icon-pause");
    if (!audio) return;
    const updateProgress = () => {
      if (!progressEl || !audio.duration || isNaN(audio.duration)) return;
      const pct = Math.min(100, (audio.currentTime / audio.duration) * 100);
      progressEl.style.width = pct + "%";
      const inner = progressEl.querySelector(".voice-waveform-inner");
      if (inner && pct > 0) inner.style.width = (100 / pct) * 100 + "%";
    };
    const setPlaying = (v) => {
      btn.classList.toggle("playing", v);
      if (iconPlay) iconPlay.style.display = v ? "none" : "block";
      if (iconPause) iconPause.style.display = v ? "block" : "none";
    };
    btn.addEventListener("click", (e) => {
      if (wrap.closest(".message")?.dataset.longPress) {
        delete wrap.closest(".message").dataset.longPress;
        return;
      }
      if (audio.paused) {
        document.querySelectorAll(".voice-message audio").forEach(a => { if (a !== audio) a.pause(); });
        audio.play();
        setPlaying(true);
      } else {
        audio.pause();
        setPlaying(false);
      }
    });
    audio.addEventListener("timeupdate", updateProgress);
    audio.addEventListener("ended", () => {
      setPlaying(false);
      if (progressEl) { progressEl.style.width = "0"; const i = progressEl.querySelector(".voice-waveform-inner"); if (i) i.style.width = ""; }
    });
    audio.addEventListener("loadedmetadata", () => {
      if (progressEl && audio.paused) { progressEl.style.width = "0"; const i = progressEl.querySelector(".voice-waveform-inner"); if (i) i.style.width = ""; }
    });
  });
  setupMessageContextMenu(div, msg, chat);
}

function setupMessageContextMenu(msgEl, msg, chat) {
  const isSent = msg.from === getUserId();
  if (!isSent) return;
  const readBy = msg.readBy || [];
  const recipients = getRecipientIds(chat);
  const isRead = recipients.some(r => readBy.includes(r));
  const canDeleteForBoth = !isRead;

  let longPressTimer = null;
  const showMenu = (x, y, fromTouch) => {
    if (fromTouch) msgEl.dataset.longPress = "1";
    hideMessageContextMenu();
    const menu = document.getElementById("msgContextMenu");
    if (!menu) return;
    menu.innerHTML = "";
    const optMe = document.createElement("button");
    optMe.type = "button";
    optMe.className = "msg-context-option";
    optMe.textContent = "Für mich löschen";
    optMe.onclick = () => { hideMessageContextMenu(); deleteMessageForMe(msg.id); };
    menu.appendChild(optMe);
    if (canDeleteForBoth) {
      const optBoth = document.createElement("button");
      optBoth.type = "button";
      optBoth.className = "msg-context-option";
      optBoth.textContent = "Für alle löschen";
      optBoth.onclick = () => { hideMessageContextMenu(); deleteMessageForBoth(msg.id); };
      menu.appendChild(optBoth);
    }
    menu.style.left = `${Math.min(x, window.innerWidth - 180)}px`;
    menu.style.top = `${Math.min(y, window.innerHeight - 120)}px`;
    menu.classList.add("show");
  };

  const bubble = msgEl.querySelector(".message-bubble");
  if (!bubble) return;

  bubble.addEventListener("contextmenu", (e) => { e.preventDefault(); showMenu(e.clientX, e.clientY); });

  const opts = { passive: true, capture: true };
  msgEl.addEventListener("touchstart", (e) => {
    longPressTimer = setTimeout(() => {
      longPressTimer = null;
      const rect = msgEl.getBoundingClientRect();
      showMenu(rect.left + rect.width / 2, rect.top + rect.height / 2, true);
    }, 450);
  }, opts);
  msgEl.addEventListener("touchend", () => {
    if (longPressTimer) { clearTimeout(longPressTimer); longPressTimer = null; }
  }, opts);
  msgEl.addEventListener("touchcancel", () => {
    if (longPressTimer) { clearTimeout(longPressTimer); longPressTimer = null; }
  }, opts);
}

function hideMessageContextMenu() {
  document.getElementById("msgContextMenu")?.classList.remove("show");
}

function deleteMessageForMe(messageId) {
  const companyId = getCompanyId(), userId = getUserId();
  if (!companyId || !currentChatId) return;
  const msgRef = doc(db, "kunden", companyId, "chats", currentChatId, "messages", messageId);
  updateDoc(msgRef, { deletedBy: arrayUnion(userId) }).catch(e => { console.error(e); alert("Nachricht konnte nicht gelöscht werden."); });
}

async function deleteMessageForBoth(messageId) {
  const companyId = getCompanyId();
  if (!companyId || !currentChatId) return;
  if (!confirm("Nachricht für alle löschen? Dies kann nicht rückgängig gemacht werden.")) return;
  const msgRef = doc(db, "kunden", companyId, "chats", currentChatId, "messages", messageId);
  await deleteDoc(msgRef);
}

async function sendMessage() {
  const text = messageInput?.value?.trim() || "";
  const hasAtt = pendingAttachments.length > 0;
  if (!text && !hasAtt) return;
  if (!currentChatId) return;
  sendBtn.disabled = true;
  try {
    let attachments = [];
    if (hasAtt) {
      const companyId = getCompanyId(), ts = Date.now();
      for (let i = 0; i < pendingAttachments.length; i++) {
        const file = pendingAttachments[i];
        const path = `kunden/${companyId}/chat-attachments/${currentChatId}/${ts}_${i}_${file.name.replace(/[^a-zA-Z0-9.-]/g, "_")}`;
        await uploadBytes(ref(storage, path), file);
        const url = await getDownloadURL(ref(storage, path));
        const att = { url, name: file.name, type: file.type, size: file.size };
        if (file.duration != null) att.duration = file.duration;
        attachments.push(att);
      }
      pendingAttachments = [];
      renderAttachmentPreview();
    }
    const messagesRef = collection(db, "kunden", getCompanyId(), "chats", currentChatId, "messages");
    await addDoc(messagesRef, { from: getUserId(), senderName: getSenderName(), text: text || null, attachments: attachments.length ? attachments : null, createdAt: serverTimestamp() });
    const lastPreview = text || (attachments.length ? (attachments.some(a => (a.type || "").startsWith("audio/")) ? "🎤 Sprachnachricht" : "📎 Datei") : "");
    const chatRef = doc(db, "kunden", getCompanyId(), "chats", currentChatId);
    await setDoc(chatRef, { lastMessageText: lastPreview, lastMessageAt: serverTimestamp(), lastMessageFrom: getUserId() }, { merge: true });
    const senderId = getUserId();
    let chat = allChats.find((c) => c.id === currentChatId);
    if (!chat?.participants?.length) {
      const chatSnap = await getDoc(chatRef);
      chat = chatSnap.exists() ? chatSnap.data() : null;
    }
    const participants = (chat?.participants || []);
    if (participants.length > 0) {
      const incUpdates = {};
      participants.forEach((pid) => {
        if (pid && pid !== senderId) incUpdates[`unreadCount.${pid}`] = increment(1);
      });
      if (Object.keys(incUpdates).length > 0) {
        try {
          await updateDoc(chatRef, incUpdates);
        } catch (incErr) {
          console.warn("UnreadCount-Update:", incErr);
        }
      }
    }
    messageInput.value = "";
  } catch (e) {
    console.error("Senden fehlgeschlagen:", e?.code || e?.message, e);
    let msg = "Nachricht konnte nicht gesendet werden.";
    const code = (e?.code || "").toString();
    if (code === "storage/unauthorized" || code.includes("storage")) {
      msg = "Storage-Berechtigung fehlt. Bitte 'firebase deploy --only storage' ausführen, um die Regeln zu aktualisieren.";
    } else if (code === "permission-denied" || e?.message?.includes("permission")) {
      msg = "Keine Berechtigung zum Senden. Bitte auf der gleichen Firma anmelden (z.B. reinoldus.rettbase.de).";
    }
    alert(msg);
  }
  sendBtn.disabled = !messageInput?.value?.trim() && pendingAttachments.length === 0;
}

const VIDEO_MIME_PREFIX = "video/";
const VIDEO_EXTENSIONS = /\.(mp4|webm|ogg|mov|avi|mkv|wmv|flv|m4v|3gp)$/i;

function isVideoFile(file) {
  if (file.type && file.type.startsWith(VIDEO_MIME_PREFIX)) return true;
  if (file.type && file.type.startsWith("audio/")) return false; // Sprachnachrichten (audio/webm, audio/mp4) erlauben
  return VIDEO_EXTENSIONS.test(file.name);
}

function handleFileSelect(e) {
  Array.from(e.target.files || []).forEach(file => {
    const isVideo = isVideoFile(file);
    if (isVideo) {
      alert(`Videodateien sind nicht erlaubt. "${file.name}" wurde nicht hinzugefügt.`);
      return;
    }
    if (file.size <= MAX_FILE_SIZE) pendingAttachments.push(file);
    else alert(`"${file.name}" zu groß. Max. 10 MB.`);
  });
  e.target.value = "";
  renderAttachmentPreview();
  sendBtn.disabled = false;
}

async function setupVoiceRecording() {
  if (!recordBtn) return;
  const updateRecordUI = (recording) => {
    const icon = recordBtn?.querySelector(".record-icon");
    const stopIcon = recordBtn?.querySelector(".stop-icon");
    recordBtn?.classList.toggle("recording", recording);
    if (icon) icon.style.display = recording ? "none" : "block";
    if (stopIcon) stopIcon.style.display = recording ? "block" : "none";
  };
  const doStartRecording = async (stream) => {
    const mimeType = MediaRecorder.isTypeSupported("audio/webm;codecs=opus") ? "audio/webm;codecs=opus" : MediaRecorder.isTypeSupported("audio/webm") ? "audio/webm" : "audio/mp4";
    mediaRecorder = new MediaRecorder(stream);
    recordChunks = [];
    recordStartTime = Date.now();
    mediaRecorder.ondataavailable = (e) => { if (e.data.size) recordChunks.push(e.data); };
    mediaRecorder.onstop = () => {
      stream.getTracks().forEach(t => t.stop());
      recordCooldownUntil = Date.now() + 400;
      const duration = (Date.now() - recordStartTime) / 1000;
      if (duration < MIN_VOICE_DURATION) return;
      const blob = new Blob(recordChunks, { type: mimeType });
      if (blob.size > MAX_FILE_SIZE) { alert("Sprachnachricht zu groß. Max. 10 MB."); return; }
      const ext = mimeType.includes("webm") ? "webm" : "mp4";
      const file = new File([blob], `Sprachnachricht_${Date.now()}.${ext}`, { type: mimeType });
      file.duration = Math.round(duration);
      pendingAttachments.push(file);
      renderAttachmentPreview();
      sendBtn.disabled = false;
    };
    mediaRecorder.start();
    updateRecordUI(true);
  };
  const requestMicAndRecord = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      micPermissionModal?.classList.remove("show");
      await doStartRecording(stream);
    } catch (e) {
      console.error("Mikrofon:", e);
      const isSystem = (e?.message || "").includes("by system");
      if (micPermissionBody) {
        micPermissionBody.innerHTML = isSystem
          ? '<p class="mic-permission-text">Mikrofon wird blockiert.</p><p class="mic-permission-hint">Prüfe: Adressleiste → Schloss-Symbol → Mikrofon, oder Systemeinstellungen → Datenschutz → Mikrofon. Alternativ: „In neuem Tab öffnen“ – dort funktioniert das Mikrofon oft.</p>'
          : '<p class="mic-permission-text">Für Sprachnachrichten wird Mikrofon-Zugriff benötigt. Browser fragt dich – wähle Erlauben oder Blockieren.</p>';
      }
      if (micPermissionAllow) micPermissionAllow.textContent = "Erneut versuchen";
      if (micPermissionNewTab && window.parent !== window) micPermissionNewTab.style.display = "inline-block";
      micPermissionModal?.classList.add("show");
    }
  };
  const toggleRecording = async () => {
    if (mediaRecorder && mediaRecorder.state === "recording") {
      mediaRecorder.stop();
      mediaRecorder = null;
      updateRecordUI(false);
      return;
    }
    if (Date.now() < recordCooldownUntil) return;
    if (!currentChatId) { alert("Bitte wähle zuerst einen Chat aus."); return; }
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      await doStartRecording(stream);
    } catch (e) {
      console.error("Mikrofon:", e);
      if (e?.name === "NotAllowedError" || e?.message?.includes("Permission denied")) {
        const isSystem = (e?.message || "").includes("by system");
        if (micPermissionBody) {
          micPermissionBody.innerHTML = isSystem
            ? '<p class="mic-permission-text">Mikrofon wird blockiert.</p><p class="mic-permission-hint">Prüfe: Adressleiste → Schloss-Symbol → Mikrofon, oder Systemeinstellungen → Datenschutz → Mikrofon. Alternativ: „In neuem Tab öffnen“ – dort funktioniert das Mikrofon oft.</p>'
            : '<p class="mic-permission-text">Für Sprachnachrichten wird Mikrofon-Zugriff benötigt. Browser fragt dich – wähle Erlauben oder Blockieren.</p>';
        }
        if (micPermissionAllow) micPermissionAllow.textContent = "Erneut versuchen";
        if (micPermissionNewTab && window.parent !== window) micPermissionNewTab.style.display = "inline-block";
        micPermissionModal?.classList.add("show");
      } else {
        alert("Mikrofon ist nicht verfügbar.");
      }
    }
  };
  closeMicPermissionModal?.addEventListener("click", () => { micPermissionModal?.classList.remove("show"); if (micPermissionNewTab) micPermissionNewTab.style.display = "none"; });
  micPermissionCancel?.addEventListener("click", () => { micPermissionModal?.classList.remove("show"); if (micPermissionNewTab) micPermissionNewTab.style.display = "none"; });
  micPermissionAllow?.addEventListener("click", () => requestMicAndRecord());
  micPermissionNewTab?.addEventListener("click", () => {
    micPermissionModal?.classList.remove("show");
    if (micPermissionNewTab) micPermissionNewTab.style.display = "none";
    if (window.parent && window.parent !== window) window.parent.postMessage({ type: "OPEN_CHAT_IN_NEW_TAB" }, "*");
  });
  micPermissionModal?.addEventListener("click", (e) => { if (e.target === micPermissionModal) micPermissionModal.classList.remove("show"); });
  recordBtn.addEventListener("click", (e) => { e.preventDefault(); toggleRecording(); });
}

function renderAttachmentPreview() {
  attachmentPreview.innerHTML = "";
  attachmentPreview.style.display = pendingAttachments.length ? "flex" : "none";
  pendingAttachments.forEach((file, i) => {
    const div = document.createElement("div");
    div.className = "attachment-preview-item";
    const isVoice = (file.type || "").startsWith("audio/");
    if (IMAGE_TYPES.includes(file.type)) { const img = document.createElement("img"); img.src = URL.createObjectURL(file); div.appendChild(img); }
    else if (isVoice) div.innerHTML = `<span class="file-info voice-preview">🎤 Sprachnachricht ${file.duration ? `(${Math.floor(file.duration / 60)}:${String(file.duration % 60).padStart(2, "0")})` : ""}</span>`;
    else div.innerHTML = `<span class="file-info">📎 ${escapeHtml(file.name)}</span>`;
    const btn = document.createElement("button"); btn.type = "button"; btn.className = "remove-attachment"; btn.textContent = "×";
    btn.onclick = () => { pendingAttachments.splice(i, 1); renderAttachmentPreview(); sendBtn.disabled = !messageInput?.value?.trim() && pendingAttachments.length === 0; };
    div.appendChild(btn);
    attachmentPreview.appendChild(div);
  });
}

function renderUserList(filter) {
  const f = (filter || "").toLowerCase();
  userList.innerHTML = "";
  const filtered = allMitarbeiter.filter(m => !f || m.name.toLowerCase().includes(f) || (m.email && m.email.toLowerCase().includes(f)));
  filtered.forEach(m => {
    const displayName = [m.vorname, m.nachname].filter(Boolean).join(" ") || m.name;
    const div = document.createElement("div");
    div.className = "user-list-item";
    div.innerHTML = `<div class="user-list-avatar">${getInitials(displayName)}</div><div class="user-list-name">${escapeHtml(displayName)}</div>`;
    div.onclick = () => startDirectChat(m);
    userList.appendChild(div);
  });
}

async function startDirectChat(mitarbeiter) {
  selectUserModal.classList.remove("show");
  const companyId = getCompanyId(), userId = getUserId();
  let recipientUid = mitarbeiter.uid;
  if (!recipientUid && mitarbeiter.email) {
    recipientUid = usersEmailToUid[(mitarbeiter.email || "").toLowerCase().trim()];
  }
  if (!recipientUid) {
    console.warn("Chat: Keine UID für Empfänger gefunden – Mitarbeiter hat möglicherweise keinen Login.", mitarbeiter);
    alert("Dieser Mitarbeiter hat keinen Benutzerzugang. Chat kann nicht gestartet werden.");
    return;
  }
  const chatId = getDirectChatId(userId, recipientUid);
  const chatRef = doc(db, "kunden", companyId, "chats", chatId);
  if (!(await getDoc(chatRef)).exists()) {
    await setDoc(chatRef, { type: "direct", participants: [userId, recipientUid], participantNames: [{ uid: userId, name: getSenderName() }, { uid: recipientUid, name: mitarbeiter.name }], lastMessageAt: serverTimestamp(), lastMessageText: "", createdAt: serverTimestamp() });
  }
  selectChat(chatId);
}

let selectedGroupMembers = [];

function renderGroupMemberList(filter) {
  const f = (filter || "").toLowerCase();
  const userId = getUserId();
  groupMemberList.innerHTML = "";
  allMitarbeiter.filter(m => m.uid !== userId && (!f || m.name.toLowerCase().includes(f) || (m.email && m.email.toLowerCase().includes(f)))).forEach(m => {
    const displayName = [m.vorname, m.nachname].filter(Boolean).join(" ") || m.name;
    const isSel = selectedGroupMembers.some(s => s.uid === m.uid);
    const div = document.createElement("div");
    div.className = "user-list-item" + (isSel ? " selected" : "");
    div.innerHTML = `<div class="user-list-avatar">${getInitials(displayName)}</div><div class="user-list-name">${escapeHtml(displayName)}</div>`;
    div.onclick = () => toggleGroupMember(m);
    groupMemberList.appendChild(div);
  });
}

function toggleGroupMember(m) {
  const idx = selectedGroupMembers.findIndex(s => s.uid === m.uid);
  if (idx >= 0) selectedGroupMembers.splice(idx, 1); else selectedGroupMembers.push(m);
  renderGroupMemberList(groupMemberSearch?.value || "");
  renderSelectedMembers();
}

function renderSelectedMembers() {
  selectedMembers.innerHTML = "";
  selectedGroupMembers.forEach(m => {
    const tag = document.createElement("span");
    tag.className = "selected-member-tag";
    tag.innerHTML = `${escapeHtml(m.name)} <button type="button" class="remove">&times;</button>`;
    tag.querySelector(".remove").onclick = (e) => { e.stopPropagation(); toggleGroupMember(m); };
    selectedMembers.appendChild(tag);
  });
}

async function createGroup() {
  const name = groupName?.value?.trim();
  if (!name) { alert("Bitte Gruppenname eingeben."); return; }
  if (selectedGroupMembers.length === 0) { alert("Bitte mindestens einen Teilnehmer auswählen."); return; }
  const companyId = getCompanyId(), userId = getUserId();
  const participants = [userId, ...selectedGroupMembers.map(m => m.uid)];
  const participantNames = [{ uid: userId, name: getSenderName() }, ...selectedGroupMembers.map(m => ({ uid: m.uid, name: m.name }))];
  const docRef = await addDoc(collection(db, "kunden", companyId, "chats"), { type: "group", name, participants, participantNames, createdBy: userId, lastMessageAt: serverTimestamp(), lastMessageText: "", createdAt: serverTimestamp() });
  createGroupModal.classList.remove("show");
  selectChat(docRef.id);
}
