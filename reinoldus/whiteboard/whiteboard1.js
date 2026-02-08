// === TAG ANLEGEN ===
addDayBtn.addEventListener("click", async () => {
  const datum = prompt("Datum eingeben (YYYY-MM-DD)");
  if (!datum) return;

  const ref = doc(db, "whiteboard", currentWache, "tage", datum);
  await setDoc(ref, { datum, created: serverTimestamp() }, { merge: true });
});

// === TAG RENDERN ===
function renderDay(datum, data) {
  const box = document.createElement("div");
  box.className = "day-container";
  box.dataset.datum = datum;

  box.innerHTML = `
    <div class="day-header">
      <div class="day-date">${datum}</div>
      <button class="delete-day">×</button>
    </div>
    <div class="schichten"></div>
    <button class="add-shift-btn">+ Schicht hinzufügen</button>
  `;

  // Tag löschen
  box.querySelector(".delete-day").addEventListener("click", async () => {
    if (confirm("Tag löschen?")) {
      const ref = doc(db, "whiteboard", currentWache, "tage", datum);
      await deleteDoc(ref);
    }
  });

  // Schicht hinzufügen
  box.querySelector(".add-shift-btn").addEventListener("click", () => addShift(datum));

  // Schichten laden
  loadShifts(datum, box.querySelector(".schichten"));

  daysArea.appendChild(box);
}

// === SCHICHTEN LADEN ===
function loadShifts(datum, container) {
  const col = collection(db, "whiteboard", currentWache, "tage", datum, "schichten");
  onSnapshot(col, (snap) => {
    container.innerHTML = "";
    snap.forEach((d) => renderShift(datum, d.id, d.data(), container));
  });
}

// === SCHICHT RENDERN ===
function renderShift(datum, id, data, container) {
  const card = document.createElement("div");
  card.className = "cell personal-cell";
  card.dataset.id = id;

  card.style.background = computeStatusColor(data);

  card.innerHTML = `
    <h4>Schicht</h4>
    <select class="schicht-select"></select>

    <h4>Personal</h4>
    <select class="personal1"></select>
    <select class="personal2"></select>

    <button class="del-shift">Schicht löschen</button>
  `;

  const schichtSel = card.querySelector(".schicht-select");
  const p1Sel = card.querySelector(".personal1");
  const p2Sel = card.querySelector(".personal2");

  // Dropdowns befüllen
  populateShiftDropdown(schichtSel, data.schicht);
  populatePersonalDropdown(p1Sel, data.personal1);
  populatePersonalDropdown(p2Sel, data.personal2);

  // Schicht speichern
  schichtSel.addEventListener("change", () => saveShift(datum, id, { schicht: schichtSel.value }));
  p1Sel.addEventListener("change", () => saveShift(datum, id, { personal1: p1Sel.value }));
  p2Sel.addEventListener("change", () => saveShift(datum, id, { personal2: p2Sel.value }));

  // Schicht löschen
  card.querySelector(".del-shift").addEventListener("click", async () => {
    if (!confirm("Schicht löschen?")) return;
    const ref = doc(db, "whiteboard", currentWache, "tage", datum, "schichten", id);
    await deleteDoc(ref);
  });

  // Farbwechsel (gelb/weiß)
  p1Sel.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    toggleColor(datum, id, "personal1Color", data.personal1Color);
  });
  p2Sel.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    toggleColor(datum, id, "personal2Color", data.personal2Color);
  });

  container.appendChild(card);
}

// === SCHICHT SPEICHERN ===
async function saveShift(datum, id, partial) {
  const ref = doc(db, "whiteboard", currentWache, "tage", datum, "schichten", id);
  await updateDoc(ref, { ...partial, updated: serverTimestamp() });
}

// === FARBLOGIK ===
function computeStatusColor(data) {
  if (!data.personal1 || !data.personal2) return "#ffd4d4"; // ROT
  return "#d4ffd7"; // GRÜN
}

// === FARBTOGGLE ===
async function toggleColor(datum, id, field, current) {
  const next = current === "yellow" ? "white" : "yellow";
  saveShift(datum, id, { [field]: next });
}
function populateShiftDropdown(selectEl, currentValue = "") {
  selectEl.innerHTML = "";

  // 1) Freie Eingabe
  const freeOpt = document.createElement("option");
  freeOpt.value = "__custom__";
  freeOpt.textContent = "➕ Eigene Schicht hinzufügen…";
  selectEl.appendChild(freeOpt);

  // 2) Feste Schichten der Wache
  if (fixedSchichten[currentWache]) {
    fixedSchichten[currentWache].forEach(s => {
      const opt = document.createElement("option");
      opt.value = s;
      opt.textContent = s;
      selectEl.appendChild(opt);
    });
  }

  // 3) Custom-Schichten live nachladen
  loadCustomShifts(selectEl, currentValue);

  // Auswahl wiederherstellen
  selectEl.value = currentValue || "";

  // Freie Eingabe
  selectEl.addEventListener("change", async () => {
    if (selectEl.value === "__custom__") {
      const newName = prompt("Eigene Schicht eingeben:");
      if (!newName) {
        selectEl.value = currentValue;
        return;
      }
      await saveCustomShift(newName);
    }
  });
}

// Custom Schichten laden
function loadCustomShifts(selectEl, currentValue) {
  const col = collection(db, "whiteboard", currentWache, "customSchichten");
  onSnapshot(col, (snap) => {
    snap.forEach((docSnap) => {
      const name = docSnap.data().name;
      const opt = document.createElement("option");
      opt.value = name;
      opt.textContent = name;
      selectEl.appendChild(opt);
    });

    if (currentValue) selectEl.value = currentValue;
  });
}

// Custom Schicht speichern
async function saveCustomShift(name) {
  const col = collection(db, "whiteboard", currentWache, "customSchichten");
  await addDoc(col, { name, created: serverTimestamp() });
}
function populatePersonalDropdown(selectEl, currentValue = "") {
  selectEl.innerHTML = "";

  // Suchfeld
  const searchOpt = document.createElement("option");
  searchOpt.disabled = true;
  searchOpt.textContent = "🔍 Name eingeben…";
  selectEl.appendChild(searchOpt);

  // Personal-Liste einfügen
  personalList
    .sort((a, b) => a.vollname.localeCompare(b.vollname, "de"))
    .forEach(p => {
      const opt = document.createElement("option");
      opt.value = p.vollname;
      opt.textContent = p.vollname;
      selectEl.appendChild(opt);
    });

  // Setzen
  if (currentValue) selectEl.value = currentValue;

  // Suche
  selectEl.addEventListener("click", () => filterPersonal(selectEl));
  selectEl.addEventListener("keyup", () => filterPersonal(selectEl));
}

function filterPersonal(selectEl) {
  const term = prompt("Name suchen:")?.toLowerCase();
  if (!term) return;

  Array.from(selectEl.options).forEach((opt, i) => {
    if (i === 0) return;
    opt.hidden = !opt.textContent.toLowerCase().includes(term);
  });

  selectEl.options[0].textContent = "🔍 " + term;
}

// Personal neu rendern, wenn Excel neu geladen wurde
function renderAllDropdowns() {
  document.querySelectorAll(".personal1, .personal2").forEach(sel => {
    const oldValue = sel.value;
    populatePersonalDropdown(sel, oldValue);
  });
}
// =========================================================
//  BLOCK 4: TAGE-LISTE + SNAPSHOT + OVD-MODUS BASIS
// =========================================================

function loadDays() {
  if (currentWache === "OVD") {
    loadOVDDays();
    return;
  }

  const col = collection(db, "whiteboard", currentWache, "tage");
  const q = query(col, orderBy("datum"));

  onSnapshot(q, (snap) => {
    daysArea.innerHTML = "";
    snap.forEach((docSnap) => {
      renderDay(docSnap.id, docSnap.data());
    });
  });
}

async function loadOVDDays() {
  daysArea.innerHTML = "";

  const wachList = [
    "RW_Holzwickede",
    "Froendenberg",
    "Koenigsborn",
    "Menden",
    "KTW"
  ];

  let allRedShifts = [];

  for (const w of wachList) {
    const tageCol = collection(db, "whiteboard", w, "tage");
    const tageSnap = await getDocs(tageCol);

    for (const t of tageSnap.docs) {
      const datum = t.id;
      const schCol = collection(db, "whiteboard", w, "tage", datum, "schichten");
      const schSnap = await getDocs(schCol);

      schSnap.forEach((s) => {
        const data = s.data();
        if (!data.personal1 || !data.personal2) {
          allRedShifts.push({
            wache: w,
            datum,
            id: s.id,
            ...data
          });
        }
      });
    }
  }

  allRedShifts.sort((a, b) => b.datum.localeCompare(a.datum));

  allRedShifts.forEach((r) => renderOVDShift(r));
}

function renderOVDShift(data) {
  const card = document.createElement("div");
  card.className = "cell personal-cell";
  card.style.background = "#ffd4d4";

  card.innerHTML = `
    <h4>${data.wache} – ${data.datum}</h4>
    <div><b>Schicht:</b> ${data.schicht || "(leer)"}</div>
    <div><b>Personal 1:</b> ${data.personal1 || "(leer)"}</div>
    <div><b>Personal 2:</b> ${data.personal2 || "(leer)"}</div>
  `;

  daysArea.appendChild(card);
}

loadDays();
// =========================================================
//  BLOCK 5: OVD SCHICHTEN EDITIERBAR + LÖSCHBAR
// =========================================================

function renderOVDShift(data) {
  const card = document.createElement("div");
  card.className = "cell personal-cell";

  // Rot da OVD nur rote Schichten anzeigt
  card.style.background = "#ffd4d4";

  card.innerHTML = `
    <h4>${data.wache} – ${data.datum}</h4>

    <label>Schicht:</label>
    <select class="ovd-schicht"></select>

    <label>Personal 1:</label>
    <select class="ovd-p1"></select>

    <label>Personal 2:</label>
    <select class="ovd-p2"></select>

    <button class="ovd-del">Schicht löschen</button>
  `;

  const schSel = card.querySelector(".ovd-schicht");
  const p1Sel  = card.querySelector(".ovd-p1");
  const p2Sel  = card.querySelector(".ovd-p2");

  // Schichtdropdown
  populateShiftDropdown(schSel, data.schicht);

  // Personal
  populatePersonalDropdown(p1Sel, data.personal1);
  populatePersonalDropdown(p2Sel, data.personal2);

  // Änderungen speichern
  schSel.addEventListener("change", () => {
    saveOVDShift(data, { schicht: schSel.value });
  });
  p1Sel.addEventListener("change", () => {
    saveOVDShift(data, { personal1: p1Sel.value });
  });
  p2Sel.addEventListener("change", () => {
    saveOVDShift(data, { personal2: p2Sel.value });
  });

  // Farbwechsel p1
  p1Sel.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    const next = data.personal1Color === "yellow" ? "white" : "yellow";
    saveOVDShift(data, { personal1Color: next });
  });

  // Farbwechsel p2
  p2Sel.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    const next = data.personal2Color === "yellow" ? "white" : "yellow";
    saveOVDShift(data, { personal2Color: next });
  });

  // Löschen
  card.querySelector(".ovd-del").addEventListener("click", async () => {
    if (!confirm("Schicht aus der Wache löschen?")) return;

    const ref = doc(
      db,
      "whiteboard",
      data.wache,
      "tage",
      data.datum,
      "schichten",
      data.id
    );
    await deleteDoc(ref);
  });

  daysArea.appendChild(card);
}

// Speichern im OVD-Modus (zurück in die jeweilige Wache)
async function saveOVDShift(orig, partial) {
  const ref = doc(
    db,
    "whiteboard",
    orig.wache,
    "tage",
    orig.datum,
    "schichten",
    orig.id
  );

  await updateDoc(ref, {
    ...partial,
    updated: serverTimestamp()
  });
}
// =========================================================
//  BLOCK 6: LONG-TOUCH FÜR PERSONAL-FARBWECHSEL (MOBILE)
// =========================================================

function enableLongTouchColorToggle(selectEl, callback) {
  let touchTimer = null;

  selectEl.addEventListener("touchstart", (e) => {
    touchTimer = setTimeout(() => {
      callback();
    }, 600); // 600ms gedrückt halten = long touch
  });

  selectEl.addEventListener("touchend", () => {
    clearTimeout(touchTimer);
  });

  selectEl.addEventListener("touchmove", () => {
    clearTimeout(touchTimer);
  });
}

// === Für normale Schichten ===
function attachMobileColorToggle(datum, id, p1Sel, p2Sel, data) {
  enableLongTouchColorToggle(p1Sel, () => {
    const next = data.personal1Color === "yellow" ? "white" : "yellow";
    saveShift(datum, id, { personal1Color: next });
  });

  enableLongTouchColorToggle(p2Sel, () => {
    const next = data.personal2Color === "yellow" ? "white" : "yellow";
    saveShift(datum, id, { personal2Color: next });
  });
}

// === Für OVD-Schichten ===
function attachMobileColorToggleOVD(orig, p1Sel, p2Sel, data) {
  enableLongTouchColorToggle(p1Sel, () => {
    const next = data.personal1Color === "yellow" ? "white" : "yellow";
    saveOVDShift(orig, { personal1Color: next });
  });

  enableLongTouchColorToggle(p2Sel, () => {
    const next = data.personal2Color === "yellow" ? "white" : "yellow";
    saveOVDShift(orig, { personal2Color: next });
  });
}
function renderOVDShift(data) {
  const card = document.createElement("div");
  card.className = "cell personal-cell";
  card.style.background = "#ffd4d4";

  card.innerHTML = `
    <h4>${data.wache} – ${data.datum}</h4>

    <label>Schicht:</label>
    <select class="ovd-schicht"></select>

    <label>Personal 1:</label>
    <select class="ovd-p1"></select>

    <label>Personal 2:</label>
    <select class="ovd-p2"></select>

    <button class="ovd-del">Schicht löschen</button>
  `;

  const schSel = card.querySelector(".ovd-schicht");
  const p1Sel  = card.querySelector(".ovd-p1");
  const p2Sel  = card.querySelector(".ovd-p2");

  populateShiftDropdown(schSel, data.schicht);
  populatePersonalDropdown(p1Sel, data.personal1);
  populatePersonalDropdown(p2Sel, data.personal2);

  schSel.addEventListener("change", () => saveOVDShift(data, { schicht: schSel.value }));
  p1Sel.addEventListener("change", () => saveOVDShift(data, { personal1: p1Sel.value }));
  p2Sel.addEventListener("change", () => saveOVDShift(data, { personal2: p2Sel.value }));

  p1Sel.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    const next = data.personal1Color === "yellow" ? "white" : "yellow";
    saveOVDShift(data, { personal1Color: next });
  });

  p2Sel.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    const next = data.personal2Color === "yellow" ? "white" : "yellow";
    saveOVDShift(data, { personal2Color: next });
  });

  attachMobileColorToggleOVD(data, p1Sel, p2Sel, data);

  refreshUI();

  card.querySelector(".ovd-del").addEventListener("click", async () => {
    if (!confirm("Schicht aus der Wache löschen?")) return;

    const ref = doc(
      db,
      "whiteboard",
      data.wache,
      "tage",
      data.datum,
      "schichten",
      data.id
    );
    await deleteDoc(ref);
  });

  daysArea.appendChild(card);
}
// =========================================================
//  BLOCK 8: VALIDIERUNG, FEHLERABFANGEN, DUPLIKAT-SCHUTZ
// =========================================================

// Validierung für Datum
function isValidDateString(str) {
  return /^\d{4}-\d{2}-\d{2}$/.test(str);
}

// Validierung für Schichtdopplung
async function shiftExists(datum, schichtName) {
  const col = collection(db, "whiteboard", currentWache, "tage", datum, "schichten");
  const snap = await getDocs(col);

  let exists = false;
  snap.forEach((d) => {
    const s = d.data();
    if (s.schicht === schichtName) exists = true;
  });

  return exists;
}

// WRAPPER für addShift mit Duplikat-Schutz
async function addShift(datum) {
  const schichtName = prompt("Schichtname eingeben (oder leer lassen für spätere Auswahl):");

  if (schichtName) {
    // prüfen ob schon vorhanden
    if (await shiftExists(datum, schichtName)) {
      alert("Diese Schicht existiert an diesem Tag bereits.");
      return;
    }
  }

  try {
    const col = collection(db, "whiteboard", currentWache, "tage", datum, "schichten");
    await addDoc(col, {
      schicht: schichtName || "",
      personal1: "",
      personal2: "",
      personal1Color: "white",
      personal2Color: "white",
      status: "rot",
      created: serverTimestamp(),
      updated: serverTimestamp()
    });

  } catch (err) {
    console.error("Fehler beim Anlegen der Schicht:", err);
    alert("Fehler beim Anlegen der Schicht. Details in der Konsole.");
  }
}

// WRAPPER für saveShift mit Validierung
async function saveShift(datum, id, partial) {
  if (partial.schicht) {
    if (await shiftExists(datum, partial.schicht)) {
      alert("Diese Schicht existiert an diesem Tag bereits.");
      return;
    }
  }

  const ref = doc(db, "whiteboard", currentWache, "tage", datum, "schichten", id);
  try {
    await updateDoc(ref, { ...partial, updated: serverTimestamp() });
  } catch (err) {
    console.error("Fehler beim Speichern:", err);
    alert("Fehler beim Speichern dieser Schicht.");
  }
}

// WRAPPER für saveOVDShift (Validierung & Fehlerhandling)
async function saveOVDShift(orig, partial) {
  const ref = doc(db, "whiteboard", orig.wache, "tage", orig.datum, "schichten", orig.id);

  // Duplikat-Prüfung für OVD-Änderungen
  if (partial.schicht) {
    const col = collection(db, "whiteboard", orig.wache, "tage", orig.datum, "schichten");
    const snap = await getDocs(col);

    let exists = false;
    snap.forEach((d) => {
      const s = d.data();
      if (s.schicht === partial.schicht && d.id !== orig.id) exists = true;
    });

    if (exists) {
      alert("Diese Schicht existiert an diesem Tag bereits.");
      return;
    }
  }

  try {
    await updateDoc(ref, { ...partial, updated: serverTimestamp() });
  } catch (err) {
    console.error("Fehler beim Speichern (OVD):", err);
    alert("Fehler beim Speichern dieser OVD-Schicht.");
  }
}

// Schutz beim Erstellen eines Tages
addDayBtn.addEventListener("click", async () => {
  const datum = prompt("Datum eingeben (YYYY-MM-DD)");
  if (!datum) return;

  if (!isValidDateString(datum)) {
    alert("Ungültiges Datumsformat. Beispiel: 2025-02-11");
    return;
  }

  const ref = doc(db, "whiteboard", currentWache, "tage", datum);
  try {
    await setDoc(ref, { datum, created: serverTimestamp() }, { merge: true });
  } catch (err) {
    console.error("Fehler beim Erstellen des Tages:", err);
    alert("Fehler beim Erstellen des Tages.");
  }
});
// =========================================================
//  BLOCK 9: PERFORMANCE OPTIMIERUNG
// =========================================================

// Cache für Tage
let cachedDays = {};

// Cache für Custom-Schichten
let cachedCustomShifts = {};

// Personal Cache (Dropdownoptimierung)
let cachedPersonalHTML = "";

// Debounce für UI Refresh
let refreshTimer = null;
function debounceRefresh() {
  if (refreshTimer) clearTimeout(refreshTimer);
  refreshTimer = setTimeout(refreshUI, 80);
}

// Optimierter Custom-Schichten Loader
function loadCustomShifts(selectEl, currentValue) {

  // Wenn Schichten schon geladen → direkt HTML einfügen
  if (cachedCustomShifts[currentWache]) {
    cachedCustomShifts[currentWache].forEach(name => {
      const opt = document.createElement("option");
      opt.value = name;
      opt.textContent = name;
      selectEl.appendChild(opt);
    });
    if (currentValue) selectEl.value = currentValue;
    return;
  }

  const col = collection(db, "whiteboard", currentWache, "customSchichten");

  // Live Snapshot nur 1x pro Wache
  onSnapshot(col, (snap) => {
    cachedCustomShifts[currentWache] = snap.docs.map(d => d.data().name);

    // Dropdown befüllen wenn dieses select gerade existiert
    if (selectEl) {
      snap.forEach((docSnap) => {
        const name = docSnap.data().name;
        const opt = document.createElement("option");
        opt.value = name;
        opt.textContent = name;
        selectEl.appendChild(opt);
      });

      if (currentValue) selectEl.value = currentValue;
    }
  });
}

// Personal Dropdown Cache generieren
function buildPersonalDropdownCache() {
  let html = "";

  personalList
    .sort((a, b) => a.vollname.localeCompare(b.vollname, "de"))
    .forEach(p => {
      html += `<option value="${p.vollname}">${p.vollname}</option>`;
    });

  cachedPersonalHTML = html;
}

function populatePersonalDropdown(selectEl, currentValue = "") {
  // Suchfeld
  selectEl.innerHTML = `<option disabled>🔍 Name eingeben…</option>` + cachedPersonalHTML;

  if (currentValue) selectEl.value = currentValue;

  selectEl.addEventListener("click", () => filterPersonal(selectEl));
  selectEl.addEventListener("keyup", () => filterPersonal(selectEl));
}

// Listener wird nur einmal aufgerufen, Auslösung minimal halten
function loadDays() {
  if (currentWache === "OVD") {
    loadOVDDays();
    return;
  }

  const col = collection(db, "whiteboard", currentWache, "tage");
  const q = query(col, orderBy("datum"));

  onSnapshot(q, (snap) => {
    const newDays = {};
    snap.forEach((docSnap) => {
      newDays[docSnap.id] = docSnap.data();
    });

    // Falls sich nichts geändert hat → nicht neu rendern
    if (JSON.stringify(newDays) === JSON.stringify(cachedDays[currentWache])) {
      return;
    }

    cachedDays[currentWache] = newDays;

    daysArea.innerHTML = "";
    for (const datum of Object.keys(newDays)) {
      renderDay(datum, newDays[datum]);
    }

    debounceRefresh();
  });
}

// UI Refresh throtteln
function refreshUI() {
  enhanceAllDropdowns();
}
// =========================================================
//  BLOCK 10: FINAL CLEANUP & BUGFIXES
// =========================================================

// Listener Cleanup Cache
let activeListeners = [];

// Wrapper für onSnapshot mit automatischem Cleanup
function listen(ref, callback) {
  const unsub = onSnapshot(ref, callback);
  activeListeners.push(unsub);
  return unsub;
}

// Beim Wechsel der Wache alle Listener entfernen
function cleanupListeners() {
  activeListeners.forEach(unsub => {
    try { unsub(); } catch(e) {}
  });
  activeListeners = [];
}

// Sicherer Wache-Wechsel
wacheSelector.addEventListener("change", (e) => {
  cleanupListeners();
  localStorage.setItem("currentWache", e.target.value);
  location.reload();
});

// Dropdown-Doppeltevents verhindern
function removeDropdownHandlers() {
  document.querySelectorAll("select").forEach(sel => {
    const clone = sel.cloneNode(true);
    sel.parentNode.replaceChild(clone, sel);
  });
}

// UI Refresh stabilisieren
function refreshUI() {
  removeDropdownHandlers();
  enhanceAllDropdowns();
}

// Sicherstellen, dass Personal Cache regeneriert wird
onSnapshot(collection(db, "personal"), (snap) => {
  personalList = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  buildPersonalDropdownCache();
  renderAllDropdowns();
  debounceRefresh();
});

// Schutz gegen kaputte Daten in Schichten
function normalizeShiftData(data) {
  return {
    schicht: data.schicht || "",
    personal1: data.personal1 || "",
    personal2: data.personal2 || "",
    personal1Color: data.personal1Color || "white",
    personal2Color: data.personal2Color || "white"
  };
}

// Render Shift patchen
const _oldRenderShift = renderShift;
renderShift = function(datum, id, data, container) {
  data = normalizeShiftData(data);
  _oldRenderShift(datum, id, data, container);
};

function renderOVDShift(data) {
  const card = document.createElement("div");
  card.className = "cell personal-cell";
  card.style.background = "#ffd4d4";

  card.innerHTML = `
    <h4>${data.wache} – ${data.datum}</h4>

    <label>Schicht:</label>
    <select class="ovd-schicht"></select>

    <label>Personal 1:</label>
    <select class="ovd-p1"></select>

    <label>Personal 2:</label>
    <select class="ovd-p2"></select>

    <button class="ovd-del">Schicht löschen</button>
  `;

  const schSel = card.querySelector(".ovd-schicht");
  const p1Sel  = card.querySelector(".ovd-p1");
  const p2Sel  = card.querySelector(".ovd-p2");

  populateShiftDropdown(schSel, data.schicht);
  populatePersonalDropdown(p1Sel, data.personal1);
  populatePersonalDropdown(p2Sel, data.personal2);

  schSel.addEventListener("change", () =>
    saveOVDShift(data, { schicht: schSel.value })
  );
  p1Sel.addEventListener("change", () =>
    saveOVDShift(data, { personal1: p1Sel.value })
  );
  p2Sel.addEventListener("change", () =>
    saveOVDShift(data, { personal2: p2Sel.value })
  );

  p1Sel.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    const next = data.personal1Color === "yellow" ? "white" : "yellow";
    saveOVDShift(data, { personal1Color: next });
  });

  p2Sel.addEventListener("contextmenu", (e) => {
    e.preventDefault();
    const next = data.personal2Color === "yellow" ? "white" : "yellow";
    saveOVDShift(data, { personal2Color: next });
  });

  attachMobileColorToggleOVD(data, p1Sel, p2Sel, data);
  refreshUI();

  card.querySelector(".ovd-del").addEventListener("click", async () => {
    if (!confirm("Schicht aus der Wache löschen?")) return;
    const ref = doc(
      db,
      "whiteboard",
      data.wache,
      "tage",
      data.datum,
      "schichten",
      data.id
    );
    await deleteDoc(ref);
  });

  daysArea.appendChild(card);
}


// Entferne versehentliche Doppeltage
function removeDuplicateDays() {
  const days = {};
  daysArea.querySelectorAll(".day-container").forEach(box => {
    const d = box.dataset.datum;
    if (days[d]) box.remove();
    else days[d] = true;
  });
}

setInterval(removeDuplicateDays, 500);

// Sanity check für Custom-Schichten
async function cleanupCustomShifts() {
  const col = collection(db, "whiteboard", currentWache, "customSchichten");
  const snap = await getDocs(col);

  const names = new Set();
  for (const docSnap of snap.docs) {
    const n = (docSnap.data().name || "").trim();
    if (!n || names.has(n)) {
      deleteDoc(docSnap.ref);
    } else names.add(n);
  }
}

cleanupCustomShifts();

// Endgültiger UI Refresh
setTimeout(refreshUI, 300);
