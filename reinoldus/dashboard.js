// ====================================================================================
//  WHITEBOARD.JS – FINAL VERSION (MIT FIREBASE AUTH IM IFRAME + ADMIN FIX)
// ====================================================================================

// ------------------------------------------------------------------------------------
//  FIREBASE INITIALISIEREN
// ------------------------------------------------------------------------------------
import { initializeApp } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-app.js";
import {
  getFirestore,
  collection,
  doc,
  setDoc,
  getDocs,
  addDoc,
  deleteDoc,
  updateDoc,
  onSnapshot,
  query,
  orderBy,
  serverTimestamp,
  getDoc as fsGetDoc
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

import {
  getAuth,
  onAuthStateChanged
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js";

// Deine Firebase Config
const firebaseConfig = {
  apiKey: "AIzaSyB_PRdGdU_f18VeKlrBUqStc6pXVu3tU04",
  authDomain: "reinoldus-f4dc3.firebaseapp.com",
  projectId: "reinoldus-f4dc3",
  storageBucket: "reinoldus-f4dc3.firebasestorage.app",
  messagingSenderId: "518113038751",
  appId: "1:518113038751:web:04cdccdfb7b43ea0c06daa",
  measurementId: "G-CCGFYRWEH1"
};

// Init
const app = initializeApp(firebaseConfig);
const db = getFirestore(app);
const auth = getAuth(app);

// ------------------------------------------------------------------------------------
//  GLOBAL STATE
// ------------------------------------------------------------------------------------
let currentWache = "RW_Holzwickede";
let personalList = [];
let isAdmin = false;
let currentUID = null;

// ------------------------------------------------------------------------------------
//  FIREBASE AUTH IM IFRAME – DAMIT ADMIN ERKANNT WIRD
// ------------------------------------------------------------------------------------
onAuthStateChanged(auth, async (user) => {
  if (user) {
    console.log("Whiteboard: Eingeloggt als:", user.uid);
    currentUID = user.uid;
    localStorage.setItem("uid", user.uid);
    startWhiteboard();
  } else {
    console.warn("Whiteboard: kein Benutzer eingeloggt");
    currentUID = null;
    localStorage.removeItem("uid");
  }
});

// ------------------------------------------------------------------------------------
//  ADMIN CHECK
// ------------------------------------------------------------------------------------
async function checkAdmin() {
  if (!currentUID) {
    console.warn("Admin Check ohne UID → Abbruch");
    hideExcelUpload();
    return;
  }

  const userDoc = await fsGetDoc(doc(db, "users", currentUID));
  if (!userDoc.exists()) {
    console.warn("Admin Check: Benutzer nicht in Firestore gefunden.");
    hideExcelUpload();
    return;
  }

  if (userDoc.data().role === "admin") {
    console.log("ADMIN erkannt");
    isAdmin = true;
    showExcelUpload();
  } else {
    isAdmin = false;
    hideExcelUpload();
  }
}

function showExcelUpload() {
  document.getElementById("excelArea").style.display = "flex";
}

function hideExcelUpload() {
  document.getElementById("excelArea").style.display = "none";
}

// ------------------------------------------------------------------------------------
//  PERSONAL LADEN
// ------------------------------------------------------------------------------------
function loadPersonal() {
  onSnapshot(collection(db, "personal"), (snap) => {
    personalList = snap.docs.map((d) => d.data());
    personalList.sort((a, b) => a.name.localeCompare(b.name, "de"));
  });
}

function populatePersonalDropdown(sel, value = "") {
  sel.innerHTML = `<option value="">— auswählen —</option>`;
  personalList.forEach((p) => {
    const label = `${p.name}, ${p.vorname} (${p.qualifikation})`;
    const opt = document.createElement("option");
    opt.value = label;
    opt.textContent = label;
    sel.appendChild(opt);
  });
  if (value) sel.value = value;
}

// ------------------------------------------------------------------------------------
//  SCHICHTEN DROPDOWN
// ------------------------------------------------------------------------------------
function populateShiftDropdown(sel, val = "") {
  const shifts = ["Frei", "RH1", "RH1T", "RH1N", "RH2", "RH2T", "RH2N"];
  sel.innerHTML = shifts.map((s) => `<option value="${s}">${s}</option>`).join("");
  if (val) sel.value = val;
}

// ------------------------------------------------------------------------------------
//  EXCEL IMPORT (XLSX kommt aus HTML <script>-Tag!)
// ------------------------------------------------------------------------------------
async function handleExcelUpload(file) {
  const data = await file.arrayBuffer();
  const workbook = XLSX.read(data);
  const sheet = workbook.Sheets[workbook.SheetNames[0]];
  const rows = XLSX.utils.sheet_to_json(sheet);

  const old = await getDocs(collection(db, "personal"));
  for (const d of old.docs) {
    await deleteDoc(doc(db, "personal", d.id));
  }

  for (const r of rows) {
    await addDoc(collection(db, "personal"), {
      vorname: r["Vorname"] || "",
      name: r["Name"] || "",
      qualifikation: r["Qualifikation"] || "",
      fuehrerschein: r["Führerschein"] || "",
      vertrag: r["Vertrag"] || "",
      telefonnummer: r["Telefonnummer"] || ""
    });
  }

  alert("Personal-Liste erfolgreich aktualisiert!");
}

// ------------------------------------------------------------------------------------
//  POPUP FÜR PERSONAL-INFOS
// ------------------------------------------------------------------------------------
function attachEmployeeInfo(sel) {
  sel.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    if (!isAdmin) return;
    if (!sel.value) return;

    const [nachname, rest] = sel.value.split(", ");
    const vorname = rest.split(" (")[0];

    const p = personalList.find((x) => x.name === nachname && x.vorname === vorname);
    if (!p) return;

    const pop = document.getElementById("employeeInfoPopup");
    pop.innerHTML = `
      <h3>${p.name}, ${p.vorname}</h3>
      <p><b>Qualifikation:</b> ${p.qualifikation}</p>
      <p><b>Führerschein:</b> ${p.fuehrerschein}</p>
      <p><b>Vertrag:</b> ${p.vertrag}</p>
      <p><b>Telefon:</b> ${p.telefonnummer}</p>
      <button onclick="document.getElementById('employeeInfoPopup').style.display='none'">
        Schließen
      </button>
    `;
    pop.style.display = "block";
  });
}

// ------------------------------------------------------------------------------------
//  TAGE + SCHICHTEN – LIVE UPDATE
// ------------------------------------------------------------------------------------
function loadDays() {
  const area = document.getElementById("daysArea");
  area.innerHTML = "";

  if (currentWache === "OVD") {
    loadOVD();
    return;
  }

  const q = query(
    collection(db, "whiteboard", currentWache, "tage"),
    orderBy("datum")
  );

  onSnapshot(q, (snap) => {
    area.innerHTML = "";
    snap.forEach((docSnap) => renderDay(docSnap.id));
  });
}

async function addDay() {
  const datum = prompt("Datum (YYYY-MM-DD)");
  if (!datum) return;

  await setDoc(doc(db, "whiteboard", currentWache, "tage", datum), {
    datum,
    created: serverTimestamp(),
  });
}

async function deleteDay(datum) {
  await deleteDoc(doc(db, "whiteboard", currentWache, "tage", datum));
}

function renderDay(datum) {
  const area = document.getElementById("daysArea");

  const card = document.createElement("div");
  card.className = "day-container";

  card.innerHTML = `
    <div class="day-header">
      <div class="day-date">${datum}</div>
      <button class="delete-day">×</button>
    </div>
    <div id="shifts-${datum}"></div>
    <button class="add-shift-btn">+ Schicht</button>
  `;

  card.querySelector(".delete-day").onclick = () => deleteDay(datum);
  card.querySelector(".add-shift-btn").onclick = () => createShift(datum);

  area.appendChild(card);

  loadShifts(datum);
}

function loadShifts(datum) {
  const ref = collection(
    db,
    "whiteboard",
    currentWache,
    "tage",
    datum,
    "schichten"
  );

  onSnapshot(ref, (snap) => {
    const container = document.getElementById("shifts-" + datum);
    container.innerHTML = "";

    snap.forEach((s) => {
      renderShift(datum, s.id, s.data(), container);
    });
  });
}

async function createShift(datum) {
  await addDoc(
    collection(db, "whiteboard", currentWache, "tage", datum, "schichten"),
    {
      schicht: "",
      personal1: "",
      personal2: "",
      created: serverTimestamp(),
    }
  );
}

async function saveShift(datum, id, obj) {
  await updateDoc(
    doc(db, "whiteboard", currentWache, "tage", datum, "schichten", id),
    obj
  );
}

function renderShift(datum, id, data, container) {
  const filled = data.personal1 && data.personal2;
  const bg = filled ? "#d4ffd4" : "#ffd4d4";

  const card = document.createElement("div");
  card.className = "cell";
  card.style.background = bg;

  card.innerHTML = `
    <select class="shift"></select>
    <select class="p1"></select>
    <select class="p2"></select>
    <button class="del-shift">×</button>
  `;

  const sch = card.querySelector(".shift");
  const p1 = card.querySelector(".p1");
  const p2 = card.querySelector(".p2");

  populateShiftDropdown(sch, data.schicht);
  populatePersonalDropdown(p1, data.personal1);
  populatePersonalDropdown(p2, data.personal2);

  attachEmployeeInfo(p1);
  attachEmployeeInfo(p2);

  sch.onchange = () => saveShift(datum, id, { schicht: sch.value });
  p1.onchange = () => saveShift(datum, id, { personal1: p1.value });
  p2.onchange = () => saveShift(datum, id, { personal2: p2.value });

  card.querySelector(".del-shift").onclick = () =>
    deleteDoc(doc(db, "whiteboard", currentWache, "tage", datum, "schichten", id));

  container.appendChild(card);
}

// ------------------------------------------------------------------------------------
//  OVD – ROTE SCHICHTEN
// ------------------------------------------------------------------------------------
async function loadOVD() {
  const area = document.getElementById("daysArea");
  area.innerHTML = "";

  const wachList = [
    "RW_Holzwickede",
    "Froendenberg",
    "Koenigsborn",
    "Menden",
    "KTW",
  ];

  let all = [];

  for (const w of wachList) {
    const tage = await getDocs(collection(db, "whiteboard", w, "tage"));
    for (const t of tage.docs) {
      const datum = t.id;

      const shifts = await getDocs(
        collection(db, "whiteboard", w, "tage", datum, "schichten")
      );

      shifts.forEach((s) => {
        const d = s.data();
        if (!d.personal1 || !d.personal2) {
          all.push({ wache: w, datum, id: s.id, ...d });
        }
      });
    }
  }

  all.sort((a, b) => b.datum.localeCompare(a.datum));
  all.forEach(renderOVDShift);
}

function renderOVDShift(data) {
  const area = document.getElementById("daysArea");

  const card = document.createElement("div");
  card.className = "cell ovd";

  card.innerHTML = `
    <h4>${data.wache} — ${data.datum}</h4>
    <div>Schicht: ${data.schicht || "(leer)"}</div>
    <div>Personal 1: ${data.personal1 || "(leer)"}</div>
    <div>Personal 2: ${data.personal2 || "(leer)"}</div>
  `;

  area.appendChild(card);
}

// ------------------------------------------------------------------------------------
//  EVENT LISTENER
// ------------------------------------------------------------------------------------
document.getElementById("wacheSelector").onchange = (e) => {
  currentWache = e.target.value;
  loadDays();
};

document.getElementById("addDayBtn").onclick = () => addDay();

document.getElementById("uploadExcelBtn").onclick = () => {
  if (!isAdmin) return alert("Keine Berechtigung!");
  const file = document.getElementById("excelInput").files[0];
  if (!file) return alert("Bitte Excel auswählen.");
  handleExcelUpload(file);
};

// ------------------------------------------------------------------------------------
//  START-FUNKTION → WENN AUTH ERKANNT
// ------------------------------------------------------------------------------------
function startWhiteboard() {
  if (!currentUID) return;

  console.log("Whiteboard gestartet für UID:", currentUID);

  checkAdmin();
  loadPersonal();
  loadDays();
}
