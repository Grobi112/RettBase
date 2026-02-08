// =========================================================
// BLOCK 0 – FIREBASE INITIALISIERUNG (MUSS GANZ OBEN STEHEN)
// =========================================================

import { initializeApp } 
    from "https://www.gstatic.com/firebasejs/11.0.1/firebase-app.js";

import { 
  getFirestore,
  doc,
  getDoc,
  collection,
  getDocs,
  addDoc,
  deleteDoc,
  updateDoc,
  onSnapshot,
  serverTimestamp,
  setDoc
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

import { 
  getAuth, 
  onAuthStateChanged 
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-auth.js";

import {
  getStorage,
  ref,
  uploadBytes
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-storage.js";

// =========================================================
// FIREBASE CONFIG
// =========================================================

const firebaseConfig = {
  apiKey: "AIzaSyB_PRdGdU_f18VeK1rBUqStc6pXVu3tU04",
  authDomain: "reinoldus-f4dc3.firebaseapp.com",
  projectId: "reinoldus-f4dc3",
  storageBucket: "reinoldus-f4dc3.firebasestorage.app",
  messagingSenderId: "518113038751",
  appId: "1:518113038751:web:04cdccdfb7b43ea0c06daa",
  measurementId: "G-CCGFYRWEH1"
};

// =========================================================
// INITIALISIEREN
// =========================================================

const app = initializeApp(firebaseConfig);
const db = getFirestore(app);
const auth = getAuth(app);
const storage = getStorage(app);

// =========================================================
// GLOBAL STATE
// =========================================================

let receivedUID = null;
let isAdmin = false;
let currentWache = "RW_Holzwickede";
let personalList = [];


// =========================================================
// BLOCK 2 – Personal laden, speichern, Excel-Import (A3)
// =========================================================


// =========================================================
// PERSONAL LADEN (A3-Struktur)
// =========================================================
async function loadPersonal() {
  try {
    const ref = collection(db, "whiteboardStaff");
    const snap = await getDocs(ref);

    personalList = [];
    snap.forEach(docSnap => {
      personalList.push({ id: docSnap.id, ...docSnap.data() });
    });

    // alphabetisch sortieren
    personalList.sort((a, b) => a.lastname.localeCompare(b.lastname));

    console.log("Personal (A3) geladen:", personalList);

  } catch (err) {
    console.error("Fehler beim Laden des Personals:", err);
  }
}


// =========================================================
// PERSONAL DROPDOWN OPTIONEN GENERIEREN
// =========================================================
function getPersonalDropdownOptions(selectedValue = "") {
  let html = `<option value="">— auswählen —</option>`;

  personalList.forEach(p => {
    const label = `${p.lastname}, ${p.firstname} (${p.qualification || "?"})`;
    html += `<option value="${label}" ${selectedValue === label ? "selected" : ""}>${label}</option>`;
  });

  return html;
}


// =========================================================
// EXCEL-IMPORT BUTTON
// =========================================================
const excelInput = document.getElementById("excelInput");
const uploadExcelBtn = document.getElementById("uploadExcelBtn");

if (uploadExcelBtn) {
  uploadExcelBtn.addEventListener("click", async () => {
    if (!isAdmin) {
      alert("Keine Berechtigung!");
      return;
    }

    const file = excelInput.files[0];
    if (!file) {
      alert("Bitte Excel-Datei auswählen!");
      return;
    }

    await handleExcelUpload(file);
  });
}


// =========================================================
// EXCEL DATEI EINLESEN UND NACH FIRESTORE ÜBERTRAGEN
// =========================================================
async function handleExcelUpload(file) {
  try {
    const buffer = await file.arrayBuffer();
    const workbook = XLSX.read(buffer);
    const sheet = workbook.Sheets[workbook.SheetNames[0]];
    const rows = XLSX.utils.sheet_to_json(sheet);

    // alte Personal-Daten löschen
    const old = await getDocs(collection(db, "whiteboardStaff"));
    for (const docSnap of old.docs) {
      await deleteDoc(doc(db, "whiteboardStaff", docSnap.id));
    }

    // neue Daten importieren
    for (const row of rows) {
      await addDoc(collection(db, "whiteboardStaff"), {
        firstname: row["Vorname"] || "",
        lastname: row["Name"] || "",
        qualification: row["Qualifikation"] || "",
        phone: row["Telefonnummer"] || "",
        driver_license: row["Führerschein"] || "",
        hosp: row["Hosp"] === "Ja",
        specialskills: row["Besonderheiten"]
          ? row["Besonderheiten"].split(",").map(s => s.trim())
          : [],
        created: serverTimestamp()
      });
    }

    alert("Personal erfolgreich importiert!");
    await loadPersonal();

  } catch (err) {
    console.error("Excel-Import Fehler:", err);
    alert("Fehler beim Importieren. Siehe Konsole.");
  }
}


// =========================================================
// DRAG & DROP EXCEL IMPORT
// =========================================================
document.addEventListener("dragover", e => {
  e.preventDefault();
});

document.addEventListener("drop", e => {
  e.preventDefault();

  if (!isAdmin) return;

  const file = e.dataTransfer.files[0];
  if (!file) return;

  if (!file.name.endsWith(".xlsx")) {
    alert("Bitte eine gültige .xlsx-Datei ziehen!");
    return;
  }

  handleExcelUpload(file);
});
// =========================================================
// BLOCK 3 – Personal-Dropdown + Suche + Freie Eingabe
// =========================================================


// =========================================================
// Suchbares Dropdown FÜR ALLE PERSONAL-FELDER
// =========================================================
// Wird später in shiftRendering verwendet
function createPersonalSelectElement(defaultValue = "") {
  const wrapper = document.createElement("div");
  wrapper.className = "personalWrapper";

  // Input + Dropdown
  wrapper.innerHTML = `
    <input class="personalSearchInput" type="text" placeholder="Suchen..." autocomplete="off"/>
    <div class="personalDropdown"></div>
  `;

  const input = wrapper.querySelector(".personalSearchInput");
  const dropdown = wrapper.querySelector(".personalDropdown");

  // Farbstatus (weiß/gelb)
  wrapper.dataset.color = "white";
  wrapper.style.background = "white";

  // Wenn ein Wert existiert → voreintragen
  input.value = defaultValue || "";

  // Dropdown-Generierung
  function updateDropdown() {
    const query = input.value.toLowerCase();
    dropdown.innerHTML = "";

    const filtered = personalList.filter(p => {
      const label = `${p.lastname}, ${p.firstname} (${p.qualification})`;
      return label.toLowerCase().includes(query);
    });

    // Treffer anzeigen
    filtered.forEach(p => {
      const label = `${p.lastname}, ${p.firstname} (${p.qualification})`;
      const item = document.createElement("div");
      item.className = "dropdownItem";
      item.textContent = label;

      item.onclick = () => {
        input.value = label;
        dropdown.style.display = "none";
        triggerPersonalChange(wrapper);
      };

      dropdown.appendChild(item);
    });

    // Falls keine Treffer → freie Eingabe
    if (filtered.length === 0) {
      const free = document.createElement("div");
      free.className = "dropdownItem freeItem";
      free.textContent = `➕ Extern hinzufügen: "${input.value}"`;

      free.onclick = () => {
        // freie Eingabe übernehmen
        triggerPersonalChange(wrapper);
        dropdown.style.display = "none";
      };

      dropdown.appendChild(free);
    }

    dropdown.style.display = "block";
  }

  // INPUT-EVENT
  input.addEventListener("input", updateDropdown);
  input.addEventListener("focus", updateDropdown);

  // Klick außerhalb schließt Menü
  document.addEventListener("click", (e) => {
    if (!wrapper.contains(e.target)) {
      dropdown.style.display = "none";
    }
  });

  return wrapper;
}


// =========================================================
// PERSONAL-FARBWECHSEL (Rechtsklick oder LongPress)
// =========================================================
function enablePersonalColorLogic(wrapper) {
  // Rechtsklick verhindern
  wrapper.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    toggleColor(wrapper);
  });

  // LongPress (Mobil)
  let pressTimer = null;
  wrapper.addEventListener("touchstart", () => {
    pressTimer = setTimeout(() => toggleColor(wrapper), 600);
  });
  wrapper.addEventListener("touchend", () => clearTimeout(pressTimer));
  wrapper.addEventListener("touchmove", () => clearTimeout(pressTimer));
}


// =========================================================
// Farbwechsel-Logik (weiß ↔ gelb)
// =========================================================
function toggleColor(wrapper) {
  if (wrapper.dataset.color === "white") {
    wrapper.dataset.color = "yellow";
    wrapper.style.background = "#fff7a7";
  } else {
    wrapper.dataset.color = "white";
    wrapper.style.background = "white";
  }

  // Speichern bei Bedarf
  if (wrapper.dataset.onchange) {
    wrapper.dataset.onchange(wrapper);
  }
}


// =========================================================
// PERSONAL-WERT ÄNDERN UND ZURÜCKGEBEN
// =========================================================
function triggerPersonalChange(wrapper) {
  const input = wrapper.querySelector(".personalSearchInput");
  const value = input.value.trim();

  // falls keine onchange-Funktion → egal
  if (wrapper.dataset.onchange) {
    wrapper.dataset.onchange(value, wrapper.dataset.color);
  }
}
// =========================================================
// BLOCK 4 – Tage laden, Tage anlegen, Tage löschen (S3)
// =========================================================


// =========================================================
// TAGE LADEN (Realtime)
// =========================================================
async function loadDays() {
  const area = document.getElementById("daysArea");
  if (!area) return;

  area.innerHTML = `<div class="loading">Lade Tage…</div>`;

  const ref = collection(db, "whiteboard", currentWache, "tage");

  // Realtime Listener
  onSnapshot(ref, (snap) => {
    area.innerHTML = "";

    if (snap.empty) {
      area.innerHTML = `<div class="noDays">Noch keine Tage angelegt.</div>`;
      return;
    }

    snap.forEach(docSnap => {
      renderDay(docSnap.id, docSnap.data());
    });
  });
}


// =========================================================
// TAG ERSTELLEN
// =========================================================
const addDayBtn = document.getElementById("addDayBtn");

if (addDayBtn) {
  addDayBtn.addEventListener("click", async () => {
    let d = prompt("Datum eingeben (YYYY-MM-DD):");

    if (!d) return;
    if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) {
      alert("Ungültiges Format. Beispiel: 2025-11-24");
      return;
    }

    const dayRef = doc(db, "whiteboard", currentWache, "tage", d);

    await setDoc(dayRef, {
      datum: d,
      created: serverTimestamp()
    });

    console.log("Tag erstellt:", d);
  });
}


// =========================================================
// TAG RENDERN
// =========================================================
function renderDay(datum, data) {
  const area = document.getElementById("daysArea");
  if (!area) return;

  // Tages-Container
  const wrap = document.createElement("div");
  wrap.className = "dayWrap";

  wrap.innerHTML = `
    <div class="dayHeader">
      <div class="dayDate">${datum}</div>
      <button class="delDayBtn">×</button>
    </div>
    <div class="shiftContainer" id="shifts-${datum}"></div>
    <button class="addShiftBtn">+ Schicht hinzufügen</button>
  `;

  // Löschen
  wrap.querySelector(".delDayBtn").onclick = () => {
    if (!confirm(`${datum} wirklich löschen?`)) return;

    deleteDoc(doc(db, "whiteboard", currentWache, "tage", datum));
  };

  // Schicht hinzufügen
  wrap.querySelector(".addShiftBtn").onclick = () => {
    createShift(datum);
  };

  area.appendChild(wrap);

  // Schichten für diesen Tag laden
  loadShifts(datum);
}
// =========================================================
// BLOCK 5 – SCHICHTSYSTEM (S3: wache → tage → schichten)
// =========================================================


// =========================================================
// SCHICHTEN LADEN (Realtime)
// =========================================================
function loadShifts(datum) {
  const ref = collection(db, "whiteboard", currentWache, "tage", datum, "schichten");

  onSnapshot(ref, (snap) => {
    const area = document.getElementById(`shifts-${datum}`);
    if (!area) return;

    area.innerHTML = ""; // leeren

    snap.forEach(docSnap => {
      renderShift(datum, docSnap.id, docSnap.data(), area);
    });
  });
}


// =========================================================
// SCHICHT ANLEGEN
// =========================================================
async function createShift(datum) {
  const shiftsRef = collection(db, "whiteboard", currentWache, "tage", datum, "schichten");

  await addDoc(shiftsRef, {
    schicht: "",
    personal1: "",
    personal1Color: "white",
    personal2: "",
    personal2Color: "white",
    created: serverTimestamp()
  });
}


// =========================================================
// SCHICHTEN PRO WACHE
// =========================================================
const shiftsPerWache = {
  RW_Holzwickede: ["RH1", "RH1T", "RH1N", "RH2", "RH2T", "RH2N"],
  Froendenberg: ["RF1", "RF2"],
  Koenigsborn: ["RK1", "RK2"],
  Menden: ["RM1", "RM2"],
  KTW: ["KTW1", "KTW2"],
  OVD: ["OVD"]
};


// =========================================================
// SCHICHT-DROPDOWN
// =========================================================
function buildShiftDropdown(selected = "") {
  const select = document.createElement("select");
  select.className = "shiftSelect";

  const list = shiftsPerWache[currentWache] || [];

  list.forEach(s => {
    const opt = document.createElement("option");
    opt.value = s;
    opt.textContent = s;
    if (s === selected) opt.selected = true;
    select.appendChild(opt);
  });

  return select;
}


// =========================================================
// SCHICHT RENDERN
// =========================================================
function renderShift(datum, id, data, container) {
  const isComplete = data.personal1 && data.personal2;
  const bgColor = isComplete ? "#d4ffd4" : "#ffd4d4";

  const row = document.createElement("div");
  row.className = "shiftRow";
  row.style.background = bgColor;

  // -------------------------------------------------------
  // Elemente erstellen
  // -------------------------------------------------------
  const shiftSelect = buildShiftDropdown(data.schicht);

  // Personal 1 Wrapper (Suchfeld, Farbe, externe Eingabe)
  const p1Wrapper = createPersonalSelectElement(data.personal1);
  p1Wrapper.style.background = data.personal1Color === "yellow" ? "#fff7a7" : "white";
  p1Wrapper.dataset.color = data.personal1Color || "white";

  // Personal 2 Wrapper
  const p2Wrapper = createPersonalSelectElement(data.personal2);
  p2Wrapper.style.background = data.personal2Color === "yellow" ? "#fff7a7" : "white";
  p2Wrapper.dataset.color = data.personal2Color || "white";

  // Löschen
  const delBtn = document.createElement("button");
  delBtn.className = "delShiftBtn";
  delBtn.textContent = "×";


  // -------------------------------------------------------
  // Wrapper in Row einsetzen
  // -------------------------------------------------------
  row.appendChild(shiftSelect);
  row.appendChild(p1Wrapper);
  row.appendChild(p2Wrapper);
  row.appendChild(delBtn);


  // -------------------------------------------------------
  // LOGIK: PERSONAL-FARBWECHSEL aktivieren
  // -------------------------------------------------------
  enablePersonalColorLogic(p1Wrapper);
  enablePersonalColorLogic(p2Wrapper);


  // -------------------------------------------------------
  // EVENTS: Änderung von Schicht
  // -------------------------------------------------------
  shiftSelect.addEventListener("change", async () => {
    await updateDoc(doc(db, "whiteboard", currentWache, "tage", datum, "schichten", id), {
      schicht: shiftSelect.value
    });
  });


  // -------------------------------------------------------
  // EVENTS: Personal1 ändern (Name + Farbe)
  // -------------------------------------------------------
  p1Wrapper.dataset.onchange = async (value, color) => {
    await updateDoc(doc(db, "whiteboard", currentWache, "tage", datum, "schichten", id), {
      personal1: value,
      personal1Color: color
    });
  };


  // -------------------------------------------------------
  // EVENTS: Personal2 ändern
  // -------------------------------------------------------
  p2Wrapper.dataset.onchange = async (value, color) => {
    await updateDoc(doc(db, "whiteboard", currentWache, "tage", datum, "schichten", id), {
      personal2: value,
      personal2Color: color
    });
  };


  // -------------------------------------------------------
  // LOGIK: Hintergrund rot/grün aktualisieren
  // -------------------------------------------------------
  function updateRowColor() {
    const filled = p1Wrapper.querySelector(".personalSearchInput").value.trim() &&
                   p2Wrapper.querySelector(".personalSearchInput").value.trim();
    row.style.background = filled ? "#d4ffd4" : "#ffd4d4";
  }

  p1Wrapper.addEventListener("input", updateRowColor);
  p2Wrapper.addEventListener("input", updateRowColor);


  // -------------------------------------------------------
  // LÖSCHEN
  // -------------------------------------------------------
  delBtn.addEventListener("click", async () => {
    if (!confirm("Schicht wirklich löschen?")) return;

    await deleteDoc(doc(db, "whiteboard", currentWache, "tage", datum, "schichten", id));
  });


  // -------------------------------------------------------
  // Row anhängen
  // -------------------------------------------------------
  container.appendChild(row);
}
// =========================================================
// BLOCK 6 – OVD-MODUS
// =========================================================
//
// Ziel: Alle Wachen → Alle Tage → Alle Schichten
//       Filter: personal1 == "" ODER personal2 == ""
//
// Ausgabe: In #ovdArea
// =========================================================


// Wachenliste für OVD-Suche
const OVD_WACHEN = [
  "RW_Holzwickede",
  "Froendenberg",
  "Koenigsborn",
  "Menden",
  "KTW"
];


// =========================================================
// OVD STARTEN
// =========================================================
async function loadOVD() {

  const area = document.getElementById("ovdArea");
  if (!area) return;

  area.innerHTML = `<div class="loading">OVD-Daten werden geladen…</div>`;

  area.innerHTML = ""; // leeren für Neuladen

  // Für jede Wache live abhören
  OVD_WACHEN.forEach(wache => {
    loadOvdForWache(wache);
  });
}


// =========================================================
// OVD – PRO WACHE HÖREN
// =========================================================
function loadOvdForWache(wache) {

  const tageRef = collection(db, "whiteboard", wache, "tage");

  onSnapshot(tageRef, (tageSnap) => {

    tageSnap.forEach(tagDoc => {
      const datum = tagDoc.id;

      const schichtenRef = collection(
        db, "whiteboard", wache, "tage", datum, "schichten"
      );

      // Schichten auswerten
      onSnapshot(schichtenRef, (schichtSnap) => {
        schichtSnap.forEach(schichtDoc => {
          const data = schichtDoc.data();

          // Nur unvollständige Schichten rot anzeigen
          const isRed = !data.personal1 || !data.personal2;

          if (isRed) {
            renderOVDEntry(wache, datum, schichtDoc.id, data);
          } else {
            // Falls Schicht repariert → entfernen
            removeOVDEntry(wache, datum, schichtDoc.id);
          }
        });
      });
    });
  });
}


// =========================================================
// OVD-EINTRAG RENDERN
// =========================================================
function renderOVDEntry(wache, datum, schichtId, data) {

  const area = document.getElementById("ovdArea");
  if (!area) return;

  const entryId = `ovd-${wache}-${datum}-${schichtId}`;
  let entry = document.getElementById(entryId);

  if (!entry) {
    entry = document.createElement("div");
    entry.id = entryId;
    entry.className = "ovdEntry";

    area.appendChild(entry);
  }

  entry.innerHTML = `
    <div class="ovdHeader">
      <strong>${wache}</strong> — ${datum}
    </div>
    <div class="ovdRow">
      <div class="ovdSchicht">${data.schicht || "—"}</div>
      <div class="ovdPersons">
        <div class="ovdP">1: ${data.personal1 || "<span class='missing'>Leer</span>"}</div>
        <div class="ovdP">2: ${data.personal2 || "<span class='missing'>Leer</span>"}</div>
      </div>
      <button class="ovdJumpBtn">Springen</button>
    </div>
  `;

  entry.querySelector(".ovdJumpBtn").onclick = () => {
    scrollToShift(wache, datum, schichtId);
  };
}


// =========================================================
// OVD-EINTRAG ENTFERNEN
// =========================================================
function removeOVDEntry(wache, datum, schichtId) {
  const id = `ovd-${wache}-${datum}-${schichtId}`;
  const el = document.getElementById(id);
  if (el) el.remove();
}


// =========================================================
// SPRINGEN ZUR SCHICHT (Scrollen)
// =========================================================
function scrollToShift(wache, datum, schichtId) {

  // Wache wechseln, falls nötig
  if (currentWache !== wache) {
    currentWache = wache;
    document.getElementById("wacheSelector").value = wache;
    loadDays();
  }

  // 300ms warten wegen onSnapshot-Render
  setTimeout(() => {
    const el = document.querySelector(`#shifts-${datum} .shiftRow`);

    if (el) {
      el.scrollIntoView({ behavior: "smooth", block: "center" });
      el.style.outline = "3px solid red";

      setTimeout(() => el.style.outline = "none", 2000);
    }
  }, 300);
}
// =========================================================
// BLOCK 7 – Mitarbeiter-Info (Popup)
// =========================================================


// =========================================================
// POPUP ELEMENT ERSTELLEN
// =========================================================
let infoPopup = null;

function createInfoPopup() {
  infoPopup = document.createElement("div");
  infoPopup.id = "infoPopup";
  infoPopup.style.position = "fixed";
  infoPopup.style.zIndex = "99999";
  infoPopup.style.background = "white";
  infoPopup.style.border = "2px solid #333";
  infoPopup.style.borderRadius = "8px";
  infoPopup.style.padding = "10px";
  infoPopup.style.boxShadow = "0 0 15px rgba(0,0,0,0.3)";
  infoPopup.style.display = "none";
  infoPopup.style.maxWidth = "260px";
  infoPopup.style.fontSize = "14px";
  infoPopup.style.color = "#111";

  document.body.appendChild(infoPopup);
}

createInfoPopup();


// =========================================================
// POPUP SCHLIESSEN
// =========================================================
function closeInfoPopup() {
  if (infoPopup) {
    infoPopup.style.display = "none";
  }
}

document.addEventListener("click", (e) => {
  if (infoPopup && !infoPopup.contains(e.target)) {
    closeInfoPopup();
  }
});


// =========================================================
// INFO POPUP BEFÜLLEN + POSITIONIEREN
// =========================================================
function showInfoPopup(personLabel, x, y) {
  if (!personLabel) return;

  // Person in der A3-Liste suchen
  const person = personalList.find(p => {
    const label = `${p.lastname}, ${p.firstname} (${p.qualification})`;
    return label === personLabel;
  });

  if (!person) return;

  // Popup-Inhalt
  infoPopup.innerHTML = `
    <div style="font-weight:bold; margin-bottom:6px; font-size:15px;">
      ${person.firstname} ${person.lastname}
    </div>

    <div><strong>Qualifikation:</strong> ${person.qualification || "-"}</div>
    <div><strong>Telefon:</strong> ${person.phone || "-"}</div>
    <div><strong>Führerschein:</strong> ${person.driver_license || "-"}</div>
    <div><strong>Hosp:</strong> ${person.hosp ? "Ja" : "Nein"}</div>

    ${
      person.specialskills && person.specialskills.length > 0
        ? `<div><strong>Besonderheiten:</strong><br>${person.specialskills.join("<br>")}</div>`
        : ""
    }
  `;

  infoPopup.style.left = x + "px";
  infoPopup.style.top = y + "px";
  infoPopup.style.display = "block";
}


// =========================================================
// PERSONALFELDER MIT POPUP VERKNÜPFEN
// =========================================================
function attachInfoPopupToWrapper(wrapper) {
  const input = wrapper.querySelector(".personalSearchInput");

  if (!input) return;

  // Rechtsklick → Popup anzeigen
  input.addEventListener("contextmenu", (e) => {
    e.preventDefault();

    const value = input.value.trim();
    if (!value) return;

    showInfoPopup(value, e.clientX, e.clientY);
  });

  // LongPress mobil
  let pressTimer = null;

  input.addEventListener("touchstart", (e) => {
    pressTimer = setTimeout(() => {
      const t = e.touches[0];
      const value = input.value.trim();
      if (value) {
        showInfoPopup(value, t.clientX, t.clientY);
      }
    }, 600);
  });

  input.addEventListener("touchend", () => clearTimeout(pressTimer));
  input.addEventListener("touchmove", () => clearTimeout(pressTimer));
}
// =========================================================
// BLOCK 8 – Finaler Glue für alle Event-Bindings
// =========================================================


// =========================================================
// PERSONAL-FELDER NACH JEDEM RENDER FINDEN & BINDEN
// =========================================================
function bindAllPersonalWrappers() {
  const wrappers = document.querySelectorAll(".personalWrapper");

  wrappers.forEach(wrapper => {
    // Info-Popup verbinden
    attachInfoPopupToWrapper(wrapper);

    // Farbwechsel (weiß/gelb)
    enablePersonalColorLogic(wrapper);
  });

  console.log("Personal-Wrapper neu gebunden:", wrappers.length);
}


// =========================================================
// SHIFT-ROW BINDING (nach jedem Render neuer Schichtzeile)
// =========================================================
function bindShiftRowEvents() {
  const rows = document.querySelectorAll(".shiftRow");

  rows.forEach(row => {
    // bereits gebunden? → überspringen
    if (row.dataset.bound === "1") return;

    row.dataset.bound = "1";

    // Personal-Felder binden
    const wrappers = row.querySelectorAll(".personalWrapper");
    wrappers.forEach(wrapper => {
      attachInfoPopupToWrapper(wrapper);
      enablePersonalColorLogic(wrapper);
    });
  });
}


// =========================================================
// WACHE SELECTOR – FINALER FIX
// =========================================================
const wacheSelector = document.getElementById("wacheSelector");

if (wacheSelector) {
  wacheSelector.addEventListener("change", () => {
    currentWache = wacheSelector.value;
    console.log("Wache gewechselt auf:", currentWache);
    loadDays();
  });
}


// =========================================================
// INITIAL START, NACHDEM UID EMPFANGEN WURDE
// =========================================================
async function startWhiteboardIfReady() {
  if (!receivedUID) {
    console.warn("Whiteboard wartet auf UID…");
    setTimeout(startWhiteboardIfReady, 300);
    return;
  }

  console.log("Whiteboard startet mit UID:", receivedUID);

  await loadUserRole(receivedUID);
  await loadPersonal();
  await loadDays();
}

startWhiteboardIfReady();


// =========================================================
// NACH JEDEM DOM-UPDATE EVENTS RE-BINDEN
// =========================================================
// MutationObserver → überwacht #daysArea
// und bindet automatisch alle neuen Shift/Feld-Elemente

const daysArea = document.getElementById("daysArea");

if (daysArea) {
  const observer = new MutationObserver(() => {
    bindAllPersonalWrappers();
    bindShiftRowEvents();
  });

  observer.observe(daysArea, { childList: true, subtree: true });
}
// =========================================================
// BLOCK 10 – UX FEINSCHLIFF & PERFORMANCE
// =========================================================


// =========================================================
// DEBOUNCE (für Farblogik und Dropdown)
// =========================================================
function debounce(func, delay = 120) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => func(...args), delay);
  };
}


// =========================================================
// STABILERE FARBLOGIK (ROT/GRÜN)
// =========================================================
function updateShiftColor(row) {
  const inputs = row.querySelectorAll(".personalSearchInput");

  if (inputs.length < 2) return;

  const p1 = inputs[0].value.trim();
  const p2 = inputs[1].value.trim();

  const complete = p1 !== "" && p2 !== "";

  if (complete) {
    row.classList.add("complete");
    row.classList.remove("incomplete");
  } else {
    row.classList.add("incomplete");
    row.classList.remove("complete");
  }
}

const debouncedUpdateColor = debounce(updateShiftColor, 100);


// =========================================================
// INPUT-OPTIMIERUNG FÜR PERSONAL-SUCHFELD
// =========================================================
document.addEventListener("input", (e) => {
  if (!e.target.classList.contains("personalSearchInput")) return;

  const row = e.target.closest(".shiftRow");
  if (!row) return;

  debouncedUpdateColor(row);
});


// =========================================================
// DROPDOWN VERHALTEN VERBESSERN
// =========================================================
document.addEventListener("click", (e) => {
  const dropdowns = document.querySelectorAll(".personalDropdown");

  dropdowns.forEach(dd => {
    if (!dd.contains(e.target) && !dd.previousElementSibling.contains(e.target)) {
      dd.style.display = "none";
    }
  });
});


// =========================================================
// NEUE SCHICHT AUTO-SCROLL
// =========================================================
function autoScrollToNewShift(datum) {
  setTimeout(() => {
    const area = document.getElementById(`shifts-${datum}`);
    if (!area) return;

    const rows = area.querySelectorAll(".shiftRow");
    if (rows.length === 0) return;

    const last = rows[rows.length - 1];
    last.scrollIntoView({ behavior: "smooth", block: "center" });
  }, 250);
}


// =========================================================
// NEUER TAG AUTO-SCROLL
// =========================================================
function autoScrollToDay(datum) {
  setTimeout(() => {
    const el = [...document.querySelectorAll(".dayWrap")]
      .find(d => d.querySelector(".dayDate")?.innerText === datum);

    if (el) {
      el.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  }, 300);
}


// =========================================================
// HOOK IN DIE SCHICHT-ERSTELLUNG
// (ersetzen NICHTS – wird zusätzlich ausgeführt)
// =========================================================
const _oldCreateShift = createShift;
createShift = async function (datum) {
  await _oldCreateShift(datum);
  autoScrollToNewShift(datum);
};


// =========================================================
// HOOK IN DIE TAGES-ERSTELLUNG
// =========================================================
const _oldAddDayBtnHandler = addDayBtn.onclick;

addDayBtn.onclick = async () => {
  const oldValue = await _oldAddDayBtnHandler();
  autoScrollToDay(oldValue);
  return oldValue;
};


// =========================================================
// MUTATION OBSERVER DROSSELN (Performance)
// =========================================================
let moTimer = null;

const optimizedObserver = new MutationObserver(() => {
  clearTimeout(moTimer);
  moTimer = setTimeout(() => {
    bindAllPersonalWrappers();
    bindShiftRowEvents();
  }, 80);
});

if (daysArea) {
  optimizedObserver.observe(daysArea, { childList: true, subtree: true });
}
// =========================================================
// BLOCK 12 – ERROR HANDLING & ROBUSTHEIT
// =========================================================


// ----------------------------
// 1) SAFE FIRESTORE SET
// ----------------------------
async function safeSetDoc(ref, data) {
  try {
    await setDoc(ref, data, { merge: true });
    return true;
  } catch (err) {
    console.error("❌ setDoc fehlgeschlagen:", err);
    showErrorBubble("Fehler beim Speichern. Netzwerkprobleme?");
    return false;
  }
}


// ----------------------------
// 2) SAFE FIRESTORE UPDATE
// ----------------------------
async function safeUpdateDoc(ref, data) {
  try {
    await updateDoc(ref, data);
    return true;
  } catch (err) {
    console.warn("⚠️ updateDoc fehlgeschlagen, versuche fallback:", err);

    try {
      await setDoc(ref, data, { merge: true });
      return true;

    } catch (err2) {
      console.error("❌ setDoc fallback fehlgeschlagen:", err2);
      showErrorBubble("Speicherung fehlgeschlagen!");
      return false;
    }
  }
}


// ----------------------------
// 3) SAFE FIRESTORE DELETE
// ----------------------------
async function safeDelete(ref) {
  try {
    await deleteDoc(ref);
    return true;
  } catch (err) {
    console.error("❌ deleteDoc fehlgeschlagen:", err);
    showErrorBubble("Konnte Eintrag nicht löschen.");
    return false;
  }
}


// ----------------------------
// 4) EINFACHES ERROR-BUBBLE
// ----------------------------
function showErrorBubble(text) {
  let bubble = document.createElement("div");
  
  bubble.className = "errorBubble";
  bubble.innerHTML = text;

  Object.assign(bubble.style, {
    position: "fixed",
    bottom: "25px",
    left: "50%",
    transform: "translateX(-50%)",
    background: "#ff5050",
    color: "white",
    padding: "12px 18px",
    borderRadius: "8px",
    fontSize: "15px",
    zIndex: "99999",
    boxShadow: "0 4px 10px rgba(0,0,0,0.2)"
  });

  document.body.appendChild(bubble);

  setTimeout(() => {
    bubble.style.opacity = "0";
    bubble.style.transition = "opacity 0.3s ease";
    setTimeout(() => bubble.remove(), 300);
  }, 2500);
}


// ----------------------------
// 5) RETRY MECHANISMUS
// ----------------------------
async function retry(operation, maxTry = 3, delay = 400) {
  for (let i = 1; i <= maxTry; i++) {
    try {
      return await operation();
    } catch (err) {
      console.warn(`Retry ${i}/${maxTry} wegen Fehler:`, err);
      if (i < maxTry) await new Promise(r => setTimeout(r, delay));
    }
  }
  showErrorBubble("Mehrere Versuche fehlgeschlagen.");
  return null;
}


// ----------------------------
// 6) SHIFT UPDATES SICHER MACHEN
// ----------------------------
async function updateShiftSafe(datum, shiftId, data) {
  const ref = doc(db, "whiteboard", currentWache, "tage", datum, "schichten", shiftId);

  return retry(() => safeUpdateDoc(ref, data), 3, 300);
}


// ----------------------------
// 7) ALLE INPUTS SANITIZEN
// ----------------------------
function sanitizeInput(str) {
  if (typeof str !== "string") return "";
  return str.replace(/[<>]/g, "").trim();
}


// ----------------------------
// 8) PERSONAL-EINGABEN SANITIZEN
// ----------------------------
function sanitizePersonalInput(wrapper) {
  const input = wrapper.querySelector(".personalSearchInput");
  if (!input) return;
  input.value = sanitizeInput(input.value);
}


// Hook in triggerPersonalChange:
const _oldTriggerPersonal = triggerPersonalChange;

triggerPersonalChange = function (wrapper) {
  sanitizePersonalInput(wrapper);
  _oldTriggerPersonal(wrapper);
};


// ----------------------------
// 9) DATUM VALIDIERUNG
// ----------------------------
function validateDateString(dateStr) {
  return /^\d{4}-\d{2}-\d{2}$/.test(dateStr);
}


// Patch für addDayBtn:
const _oldAddDayClick = addDayBtn.onclick;

addDayBtn.onclick = function () {
  let d = prompt("Datum (YYYY-MM-DD):");

  if (!d) return;
  if (!validateDateString(d)) {
    showErrorBubble("Ungültiges Datum!");
    return;
  }

  return _oldAddDayClick(d);
};


// ----------------------------
// 10) DUPLIKATE EVENT-BINDINGS VERHINDERN
// ----------------------------
const _oldBindPersonal = bindAllPersonalWrappers;

bindAllPersonalWrappers = function () {
  const alreadyBound = new WeakSet();

  const wrappers = document.querySelectorAll(".personalWrapper");

  wrappers.forEach(wrapper => {
    if (alreadyBound.has(wrapper)) return;
    alreadyBound.add(wrapper);

    enablePersonalColorLogic(wrapper);
    attachInfoPopupToWrapper(wrapper);
  });

  _oldBindPersonal();
};


// ----------------------------
// 11) OFFLINE / ONLINE HINWEIS
// ----------------------------
window.addEventListener("offline", () => {
  showErrorBubble("⚠️ Offline – Änderungen werden verzögert gespeichert!");
});

window.addEventListener("online", () => {
  showErrorBubble("🟢 Verbindung wiederhergestellt.");
});


// ----------------------------
// 12) FIRESTORE-DATA GUARD
// ----------------------------
function safeData(obj, field) {
  if (!obj) return "";
  if (!obj[field]) return "";
  return obj[field];
}
