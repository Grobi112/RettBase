import { db } from "./firebase-config.js";
import {
  collection,
  getDocs,
  addDoc,
  updateDoc,
  deleteDoc,
  doc
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

const userTable = document.getElementById("userTable");
const modal = document.getElementById("userModal");
const modalTitle = document.getElementById("modalTitle");
const nameInput = document.getElementById("userName");
const emailInput = document.getElementById("userEmail");
const passwordInput = document.getElementById("userPassword");
const roleSelect = document.getElementById("userRole");
const activeCheckbox = document.getElementById("userActive");
const saveBtn = document.getElementById("saveUser");
const closeModalBtn = document.getElementById("closeModal");
const addUserBtn = document.getElementById("addUserBtn");

let users = [];
let editUserId = null; // merkt sich, ob wir gerade bearbeiten

// 🔹 Benutzer laden
async function loadUsers() {
  users = [];
  const querySnapshot = await getDocs(collection(db, "users"));
  userTable.innerHTML = "";

  querySnapshot.forEach((docSnap) => {
    const data = docSnap.data();
    const tr = document.createElement("tr");
    tr.innerHTML = `
      <td>${data.name || "-"}</td>
      <td>${data.email || "-"}</td>
      <td>${data.role || "user"}</td>
      <td>${data.active ? "✅" : "❌"}</td>
      <td>
        <button class="edit-btn" data-id="${docSnap.id}">Bearbeiten</button>
        <button class="delete-btn" data-id="${docSnap.id}">Löschen</button>
      </td>
    `;
    userTable.appendChild(tr);
    users.push({ id: docSnap.id, ...data });
  });
}

// ✅ Funktioniert jetzt garantiert auch nach Reload
function attachRowEvents() {
  document.addEventListener("click", (e) => {
    const editBtn = e.target.closest(".edit-btn");
    const deleteBtn = e.target.closest(".delete-btn");

    if (editBtn) {
      const id = editBtn.dataset.id;
      const user = users.find((u) => u.id === id);
      if (user) openEditModal(user);
    }

    if (deleteBtn) {
      const id = deleteBtn.dataset.id;
      if (confirm("Benutzer wirklich löschen?")) {
        deleteDoc(doc(db, "users", id)).then(loadUsers);
      }
    }
  });
}

// 🔹 Neues Modal öffnen (für Neuen Benutzer)
addUserBtn.addEventListener("click", () => {
  editUserId = null;
  modalTitle.textContent = "Neuen Benutzer anlegen";
  nameInput.value = "";
  emailInput.value = "";
  passwordInput.value = "";
  roleSelect.value = "user";
  activeCheckbox.checked = true;
  modal.style.display = "block";
});

// 🔹 Modal für Bearbeitung öffnen
function openEditModal(user) {
  editUserId = user.id;
  modalTitle.textContent = "Benutzer bearbeiten";
  nameInput.value = user.name || "";
  emailInput.value = user.email || "";
  passwordInput.value = user.password || "";
  roleSelect.value = user.role || "user";
  activeCheckbox.checked = !!user.active;
  modal.style.display = "block";
}

// 🔹 Benutzer speichern oder aktualisieren
saveBtn.addEventListener("click", async () => {
  const userData = {
    name: nameInput.value.trim(),
    email: emailInput.value.trim(),
    password: passwordInput.value.trim(),
    role: roleSelect.value,
    active: activeCheckbox.checked,
    updatedAt: new Date()
  };

  if (!userData.name || !userData.email) {
    alert("Name und E-Mail sind Pflichtfelder.");
    return;
  }

  if (editUserId) {
    // 🔸 Bestehenden Benutzer aktualisieren
    const ref = doc(db, "users", editUserId);
    await updateDoc(ref, userData);
  } else {
    // 🔸 Neuen Benutzer anlegen
    userData.createdAt = new Date();
    await addDoc(collection(db, "users"), userData);
  }

  modal.style.display = "none";
  loadUsers();
});

// 🔹 Modal schließen
closeModalBtn.addEventListener("click", () => {
  modal.style.display = "none";
});

// 🔹 Initial laden
loadUsers();
attachRowEvents();
