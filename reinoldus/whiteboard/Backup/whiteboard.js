import { initializeApp } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-app.js";
import {
  getFirestore, doc, setDoc, getDoc, updateDoc, onSnapshot,
  arrayUnion, arrayRemove, deleteField
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// === Firebase Setup ===
const firebaseConfig = {
  apiKey: "AIzaSyB_PRdGdU_f18VeKlrBUqStc6pXVu3tU04",
  authDomain: "reinoldus-f4dc3.firebaseapp.com",
  projectId: "reinoldus-f4dc3",
  storageBucket: "reinoldus-f4dc3.firebasestorage.app",
  messagingSenderId: "518113038751",
  appId: "1:518113038751:web:04cdccdfb7b43ea0c06daa",
  measurementId: "G-CCGFYRWEH1"
};
const app = initializeApp(firebaseConfig);
const db = getFirestore(app);
const boardRef = doc(db, "whiteboard", "global");

// === Rolle/Email aus Dashboard ===
const currentUserRole = localStorage.getItem("role") || "user";
const currentUserEmail = localStorage.getItem("userEmail") || "anonymous";

// === DOM ===
const schichtInput = document.getElementById("schichtInput");
const personalInput = document.getElementById("personalInput");
const addSchichtBtn = document.getElementById("addSchicht");
const addPersonalBtn = document.getElementById("addPersonal");
const ablageSchichten = document.getElementById("ablageSchichten");
const ablagePersonal = document.getElementById("ablagePersonal");
const rowsArea = document.getElementById("rowsArea");
const addRowBtn = document.getElementById("addRow");

// === State ===
let schichten = [];
let personal = [];
let rowsOrder = [];
let rows = {};

// === Init Firestore (mit rows/rowsOrder) ===
async function initFirestore() {
  const snap = await getDoc(boardRef);
  if (!snap.exists()) {
    const firstRowId = crypto.randomUUID().replace(/-/g, "_");
    await setDoc(boardRef, {
      schichten: [],
      personal: [],
      titel: "Datum / Bereich",
      rowsOrder: [firstRowId],
      rows: {
        [firstRowId]: {
          title: "Datum / Bereich",
          assignments: { schicht: [], personal: [] }
        }
      }
    });
  } else {
    const data = snap.data();
    if (!data.rowsOrder || !data.rows) {
      const migratedRowId = crypto.randomUUID().replace(/-/g, "_");
      await updateDoc(boardRef, {
        rowsOrder: arrayUnion(migratedRowId),
        [`rows.${migratedRowId}`]: {
          title: data.titel || "Datum / Bereich",
          assignments: { schicht: [], personal: [] }
        }
      });
    }
  }
}
await initFirestore();

// === Clips (unverändert) ===
function makeClipEl({ id, text, type, fromAssignment = false, rowId = null }) {
  const div = document.createElement("div");
  div.className = "clip";
  div.draggable = true;
  div.dataset.type = type;
  div.dataset.id = id;
  div.dataset.fromAssignment = fromAssignment ? "true" : "false";
  if (rowId) div.dataset.rowId = rowId;
  div.textContent = text;

  const delBtn = document.createElement("button");
  delBtn.textContent = "×";
  delBtn.addEventListener("click", async (e) => {
    e.stopPropagation();
    if (!["user", "admin"].includes(currentUserRole)) { alert("Keine Berechtigung."); return; }

    if (fromAssignment && rowId) {
      await updateDoc(boardRef, {
        [`rows.${rowId}.assignments.${type}`]: arrayRemove({ id, text })
      });
    } else {
      const field = (type === "schicht" || type === "schichten") ? "schichten" : "personal";
      await updateDoc(boardRef, { [field]: arrayRemove({ id, text }) });
    }
  });
  div.appendChild(delBtn);

  div.addEventListener("dragstart", (e) => {
    div.classList.add("dragging");
    e.dataTransfer.setData("text/plain", JSON.stringify({
      id, text, type, fromAssignment, rowId
    }));
  });
  div.addEventListener("dragend", () => div.classList.remove("dragging"));
  return div;
}

function renderClips(container, items, type, fromAssignment = false, rowId = null) {
  container.innerHTML = "";
  items.slice().sort((a,b)=>a.text.localeCompare(b.text,"de",{sensitivity:"base"}))
    .forEach(clip => container.appendChild(
      makeClipEl({ id: clip.id, text: clip.text, type, fromAssignment, rowId })
    ));
}

// === Ablagen hinzufügen (unverändert) ===
async function addClip(type, text, inputField) {
  if (!["user","admin"].includes(currentUserRole)) { alert("Keine Berechtigung."); return; }
  const value = text.trim(); if (!value) return;
  inputField.value = ""; inputField.focus();
  const clip = { id: crypto.randomUUID(), text: value };
  const field = (type === "schicht" || type === "schichten") ? "schichten" : "personal";
  await updateDoc(boardRef, { [field]: arrayUnion(clip) });
}
addSchichtBtn.addEventListener("click", () => addClip("schichten", schichtInput.value, schichtInput));
addPersonalBtn.addEventListener("click", () => addClip("personal", personalInput.value, personalInput));
schichtInput.addEventListener("keydown", e => { if (e.key === "Enter") addClip("schichten", schichtInput.value, schichtInput); });
personalInput.addEventListener("keydown", e => { if (e.key === "Enter") addClip("personal", personalInput.value, personalInput); });

// === Row DOM (JETZT mit Löschen-Button „×“) ===
function createRowDOM(rowId, rowData) {
  const wrapper = document.createElement("div");
  wrapper.className = "main-column";
  wrapper.dataset.rowId = rowId;

  const titleWrap = document.createElement("div");
  titleWrap.className = "title-wrapper";

  const titleDiv = document.createElement("div");
  titleDiv.className = "grid-title";
  titleDiv.contentEditable = "true";
  titleDiv.textContent = rowData.title || "Datum / Bereich";
  titleDiv.addEventListener("keydown", (e) => {
    if (e.key === "Enter") { e.preventDefault(); titleDiv.blur(); }
  });
  titleDiv.addEventListener("blur", async () => {
    const newT = (titleDiv.textContent || "").trim() || "Datum / Bereich";
    await updateDoc(boardRef, { [`rows.${rowId}.title`]: newT });
  });

  const pencil = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  pencil.setAttribute("xmlns", "http://www.w3.org/2000/svg");
  pencil.setAttribute("class", "edit-icon");
  pencil.setAttribute("fill", "none");
  pencil.setAttribute("viewBox", "0 0 24 24");
  pencil.setAttribute("stroke-width", "2");
  pencil.innerHTML = '<path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z"/>';
  pencil.addEventListener("click", () => titleDiv.focus());

  // --- NEU: Löschen-Button „×“ ---
  const deleteBtn = document.createElement("button");
  deleteBtn.textContent = "×";
  deleteBtn.title = "Zeile löschen";
  deleteBtn.style.background = "none";
  deleteBtn.style.border = "1px solid #f3d6d6";
  deleteBtn.style.borderRadius = "8px";
  deleteBtn.style.padding = "2px 8px";
  deleteBtn.style.marginLeft = "8px";
  deleteBtn.style.cursor = "pointer";
  deleteBtn.style.color = "#b91c1c";
  deleteBtn.addEventListener("click", async () => {
    if (!["user","admin"].includes(currentUserRole)) { alert("Keine Berechtigung."); return; }
    if (!confirm("Diese Zeile wirklich löschen?")) return;

    // rowsOrder lokal aktualisieren und rows.{rowId} entfernen
    const newOrder = rowsOrder.filter(id => id !== rowId);
    await updateDoc(boardRef, {
      rowsOrder: newOrder,
      [`rows.${rowId}`]: deleteField()
    });
  });

  titleWrap.appendChild(titleDiv);
  titleWrap.appendChild(pencil);
  titleWrap.appendChild(deleteBtn);

  const gridRow = document.createElement("div");
  gridRow.className = "grid-row";

  const cellSchicht = document.createElement("div");
  cellSchicht.className = "grid-cell";
  cellSchicht.setAttribute("data-type", "schicht");
  cellSchicht.setAttribute("data-row-id", rowId);
  cellSchicht.innerHTML = `<h4 contenteditable="true">Schicht</h4><div class="dropzone"></div>`;

  const cellPersonal = document.createElement("div");
  cellPersonal.className = "grid-cell";
  cellPersonal.setAttribute("data-type", "personal");
  cellPersonal.setAttribute("data-row-id", rowId);
  cellPersonal.innerHTML = `<h4 contenteditable="true">Personal</h4><div class="dropzone"></div>`;

  gridRow.appendChild(cellSchicht);
  gridRow.appendChild(cellPersonal);

  wrapper.appendChild(titleWrap);
  wrapper.appendChild(gridRow);
  return wrapper;
}

// === Render aller Zeilen ===
function renderRows() {
  rowsArea.innerHTML = "";
  rowsOrder.forEach(rowId => {
    const rowData = rows[rowId];
    if (!rowData) return;
    const rowDom = createRowDOM(rowId, rowData);
    rowsArea.appendChild(rowDom);

    const dropSchicht = rowDom.querySelector('.grid-cell[data-type="schicht"] .dropzone');
    const dropPersonal = rowDom.querySelector('.grid-cell[data-type="personal"] .dropzone');
    renderClips(dropSchicht, rowData.assignments?.schicht || [], "schicht", true, rowId);
    renderClips(dropPersonal, rowData.assignments?.personal || [], "personal", true, rowId);
  });
  setupDropzones();
}

// === Zeile hinzufügen (unverändert) ===
addRowBtn.addEventListener("click", async () => {
  if (!["user","admin"].includes(currentUserRole)) { alert("Keine Berechtigung."); return; }
  const rowId = crypto.randomUUID().replace(/-/g, "_");
  await updateDoc(boardRef, {
    rowsOrder: arrayUnion(rowId),
    [`rows.${rowId}`]: {
      title: "Datum / Bereich",
      assignments: { schicht: [], personal: [] }
    }
  });
});

// === Drop-System (mit Zeilen) ===
function setupDropzones() {
  document.querySelectorAll(".dropzone").forEach((zone) => {
    zone.addEventListener("dragover", (e) => {
      e.preventDefault();
      zone.classList.add("drag-over");
    });
    zone.addEventListener("dragleave", () => zone.classList.remove("drag-over"));
    zone.addEventListener("drop", async (e) => {
      e.preventDefault();
      zone.classList.remove("drag-over");

      const data = e.dataTransfer.getData("text/plain");
      if (!data) return;

      const { id, text, type, fromAssignment, rowId: sourceRowId } = JSON.parse(data);

      const isTopZone = zone.id === "ablageSchichten" || zone.id === "ablagePersonal";
      const parentCell = zone.closest(".grid-cell");
      const isBottomZone = !!parentCell;
      const targetType = parentCell ? parentCell.getAttribute("data-type") : null;
      const targetRowId = parentCell ? parentCell.getAttribute("data-row-id") : null;

      const clipObj = { id, text };

      // Oben -> Unten (in bestimmte Zeile)
      if (!fromAssignment && isBottomZone && targetRowId && targetType) {
        const removeField = (type === "schicht" || type === "schichten") ? "schichten" : "personal";
        await updateDoc(boardRef, {
          [removeField]: arrayRemove(clipObj),
          [`rows.${targetRowId}.assignments.${targetType}`]: arrayUnion(clipObj),
        });
        return;
      }

      // Unten -> Oben
      if (fromAssignment && isTopZone && sourceRowId) {
        const addField = (type === "schicht" || type === "schichten") ? "schichten" : "personal";
        await updateDoc(boardRef, {
          [`rows.${sourceRowId}.assignments.${type}`]: arrayRemove(clipObj),
          [addField]: arrayUnion(clipObj),
        });
        return;
      }

      // Unten -> Unten (Zeile -> andere Zeile)
      if (fromAssignment && isBottomZone && targetRowId && targetType) {
        if (!sourceRowId) return;
        await updateDoc(boardRef, {
          [`rows.${sourceRowId}.assignments.${type}`]: arrayRemove(clipObj),
          [`rows.${targetRowId}.assignments.${targetType}`]: arrayUnion(clipObj),
        });
        return;
      }

      // Fallback visuell
      const dragged = document.querySelector(".clip.dragging");
      if (dragged) zone.appendChild(dragged);
    });
  });
}

// === Snapshot Sync ===
onSnapshot(boardRef, (snap) => {
  if (!snap.exists()) return;
  const data = snap.data();
  schichten = data.schichten || [];
  personal  = data.personal || [];
  rowsOrder = data.rowsOrder || [];
  rows      = data.rows || {};

  renderClips(ablageSchichten, schichten, "schichten", false, null);
  renderClips(ablagePersonal, personal, "personal", false, null);
  renderRows();
});
