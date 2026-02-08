// menue.js
// Menü-Verwaltung mit Drag & Drop

import { db } from "../../firebase-config.js";
import { getAllModules } from "../../modules.js";
import {
  collection,
  doc,
  getDoc,
  setDoc,
  updateDoc,
  query,
  where,
  getDocs,
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";

// ---------------------------------------------------------
// Globale Zustände
// ---------------------------------------------------------

let userAuthData = null; // { uid, companyId, role, ... }
let availableModules = []; // Verfügbare Module
let menuStructure = []; // Aktuelle Menüstruktur

// ---------------------------------------------------------
// DOM-Elemente
// ---------------------------------------------------------

const backBtn = document.getElementById("backBtn");
const saveMenuBtn = document.getElementById("saveMenuBtn");
const createMenuItemBtn = document.getElementById("createMenuItemBtn");
const availableItems = document.getElementById("availableItems");
const menuStructureDiv = document.getElementById("menuStructure");
const createMenuItemModal = document.getElementById("createMenuItemModal");
const createMenuItemForm = document.getElementById("createMenuItemForm");
const closeCreateModalBtn = document.getElementById("closeCreateModalBtn");
const cancelCreateMenuItemBtn = document.getElementById("cancelCreateMenuItemBtn");
const createMenuItemMessage = document.getElementById("createMenuItemMessage");
const editMenuItemModal = document.getElementById("editMenuItemModal");
const editMenuItemForm = document.getElementById("editMenuItemForm");
const closeEditModalBtn = document.getElementById("closeEditModalBtn");
const cancelEditMenuItemBtn = document.getElementById("cancelEditMenuItemBtn");
const editMenuItemMessage = document.getElementById("editMenuItemMessage");
let draggedElement = null;
let dragOverElement = null;

// ---------------------------------------------------------
// Initialisierung
// ---------------------------------------------------------

window.addEventListener("DOMContentLoaded", () => {
  // Warte auf Auth-Daten vom Parent (Dashboard)
  waitForAuthData()
    .then((data) => {
      userAuthData = data;
      console.log(`✅ Menü-Verwaltung - Auth-Daten empfangen: Role ${data.role}, Company ${data.companyId}`);
      initializeMenuEditor();
    })
    .catch((err) => {
      console.error("Menü-Verwaltung konnte Auth-Daten nicht empfangen:", err);
    });
});

// ---------------------------------------------------------
// Auth-Handshake
// ---------------------------------------------------------

function waitForAuthData() {
  return new Promise((resolve) => {
    // Sende "Ready" Signal an Parent
    if (window.parent && window.parent !== window) {
      window.parent.postMessage({ type: "IFRAME_READY" }, "*");
    }

    // Warte auf AUTH_DATA Nachricht vom Parent
    const messageHandler = (event) => {
      if (event.data && event.data.type === "AUTH_DATA") {
        window.removeEventListener("message", messageHandler);
        resolve(event.data.data);
      }
    };

    window.addEventListener("message", messageHandler);
  });
}

// ---------------------------------------------------------
// Hauptfunktionen
// ---------------------------------------------------------

async function initializeMenuEditor() {
  if (!userAuthData || !userAuthData.companyId) {
    console.error("Keine Auth-Daten verfügbar");
    return;
  }

  // 🔥 PRÜFE: Nur Superadmin darf die globale Menüstruktur bearbeiten
  if (userAuthData.role !== 'superadmin') {
    console.error("Nur Superadmin darf die globale Menüstruktur bearbeiten");
    if (menuStructureDiv) {
      menuStructureDiv.innerHTML = '<p style="color: #ef4444; padding: 20px;">Sie benötigen Superadmin-Rechte, um die globale Menüstruktur zu bearbeiten.</p>';
    }
    if (saveMenuBtn) {
      saveMenuBtn.disabled = true;
      saveMenuBtn.style.opacity = '0.5';
    }
    if (createMenuItemBtn) {
      createMenuItemBtn.disabled = true;
      createMenuItemBtn.style.opacity = '0.5';
    }
    return;
  }

  // Back-Button Event Listener
  if (backBtn) {
    backBtn.addEventListener("click", () => {
      if (window.parent && window.parent !== window) {
        window.parent.postMessage({ type: "NAVIGATE_TO_HOME" }, "*");
      }
    });
  }

  // Save Button Event Listener
  if (saveMenuBtn) {
    saveMenuBtn.addEventListener("click", () => {
      saveMenuStructure();
    });
  }

  // Create Menu Item Button
  if (createMenuItemBtn) {
    createMenuItemBtn.addEventListener("click", () => {
      openCreateMenuItemModal();
    });
  }

  // Close Modal Buttons
  if (closeCreateModalBtn) {
    closeCreateModalBtn.addEventListener("click", () => {
      closeCreateMenuItemModal();
    });
  }

  if (cancelCreateMenuItemBtn) {
    cancelCreateMenuItemBtn.addEventListener("click", () => {
      closeCreateMenuItemModal();
    });
  }

  // Create Menu Item Form
  if (createMenuItemForm) {
    createMenuItemForm.addEventListener("submit", (e) => {
      e.preventDefault();
      createCustomMenuItem();
    });
  }

  // Edit Menu Item Modal Event Listener
  if (closeEditModalBtn) {
    closeEditModalBtn.addEventListener("click", () => {
      closeEditMenuItemModal();
    });
  }

  if (cancelEditMenuItemBtn) {
    cancelEditMenuItemBtn.addEventListener("click", () => {
      closeEditMenuItemModal();
    });
  }

  // Edit Menu Item Form
  if (editMenuItemForm) {
    editMenuItemForm.addEventListener("submit", (e) => {
      e.preventDefault();
      saveEditedMenuItem();
    });
  }

  // Event Listener für Menüstruktur-Container (nur einmal)
  if (menuStructureDiv) {
    menuStructureDiv.addEventListener("dragover", handleMenuStructureDragOver);
    menuStructureDiv.addEventListener("drop", handleMenuStructureDrop);
    menuStructureDiv.addEventListener("dragleave", (e) => {
      if (!menuStructureDiv.contains(e.relatedTarget)) {
        menuStructureDiv.classList.remove("drag-over");
      }
    });
  }

  // Lade Module und Menüstruktur
  await loadModules();
  await loadMenuStructure();
  renderAvailableItems();
  renderMenuStructure();
}

// ---------------------------------------------------------
// Module und Menü laden
// ---------------------------------------------------------

async function loadModules() {
  try {
    const modules = await getAllModules();
    availableModules = Object.values(modules).filter(m => m.active !== false);
    availableModules.sort((a, b) => (a.order || 999) - (b.order || 999));
    console.log("📦 Module geladen:", availableModules.length);
  } catch (error) {
    console.error("Fehler beim Laden der Module:", error);
    availableModules = [];
  }
}

async function loadMenuStructure() {
  // 🔥 GLOBAL: Lade Menüstruktur aus globalem Pfad (nicht firmenspezifisch)
  try {
    const menuRef = doc(db, "settings", "globalMenu");
    const menuSnap = await getDoc(menuRef);
    
    if (menuSnap.exists()) {
      const data = menuSnap.data();
      menuStructure = data.items || [];
      console.log("📋 Globale Menüstruktur geladen:", menuStructure.length, "Items");
    } else {
      // Erstelle Standard-Menüstruktur basierend auf verfügbaren Modulen
      menuStructure = availableModules.map(module => ({
        id: module.id,
        label: module.label,
        url: module.url,
        type: 'module',
        level: 0,
        order: module.order || 999
      }));
      console.log("📋 Neue Standard-Menüstruktur erstellt (wird beim Speichern global gespeichert)");
    }
  } catch (error) {
    console.error("Fehler beim Laden der globalen Menüstruktur:", error);
    menuStructure = [];
  }
}

async function saveMenuStructure() {
  // 🔥 PRÜFE: Nur Superadmin darf speichern
  if (!userAuthData || userAuthData.role !== 'superadmin') {
    alert("Nur Superadmin darf die globale Menüstruktur speichern.");
    return;
  }

  try {
    saveMenuBtn.disabled = true;
    saveMenuBtn.textContent = "Speichere...";

    // 🔥 GLOBAL: Speichere Menüstruktur in globalem Pfad (für alle Firmen)
    const menuRef = doc(db, "settings", "globalMenu");
    await setDoc(menuRef, {
      items: menuStructure,
      updatedAt: new Date(),
      updatedBy: userAuthData.uid,
      isGlobal: true // Flag für Klarheit
    }, { merge: true });

    console.log("✅ Globale Menüstruktur gespeichert (gilt für alle Firmen)");
    
    // 🔥 NEU: Sende Nachricht an Parent (Dashboard), dass globale Menüstruktur aktualisiert wurde
    if (window.parent && window.parent !== window) {
      window.parent.postMessage({ 
        type: 'MENU_UPDATED',
        isGlobal: true // Signalisiert, dass es global ist
      }, '*');
      console.log("📤 Nachricht an Dashboard gesendet: MENU_UPDATED (global)");
    }
    
    alert("Globale Menüstruktur erfolgreich gespeichert! Die Änderungen gelten für alle Firmen.");
    
    saveMenuBtn.disabled = false;
    saveMenuBtn.textContent = "Menü speichern";
  } catch (error) {
    console.error("Fehler beim Speichern der globalen Menüstruktur:", error);
    alert("Fehler beim Speichern der Menüstruktur: " + error.message);
    
    saveMenuBtn.disabled = false;
    saveMenuBtn.textContent = "Menü speichern";
  }
}

// ---------------------------------------------------------
// Rendering
// ---------------------------------------------------------

function renderAvailableItems() {
  if (!availableItems) return;

  // Filtere bereits im Menü enthaltene Module (nur Module, nicht benutzerdefinierte Items)
  const usedModuleIds = new Set(menuStructure.filter(item => item.type === 'module').map(item => item.id));
  const unusedModules = availableModules.filter(m => !usedModuleIds.has(m.id));

  availableItems.innerHTML = "";

  if (unusedModules.length === 0) {
    availableItems.innerHTML = '<p style="color: #94a3b8; font-style: italic;">Alle Module sind bereits im Menü</p>';
    return;
  }

  unusedModules.forEach(module => {
    const item = createMenuItemElement(module, false);
    item.draggable = true;
    item.dataset.moduleId = module.id;
    item.dataset.fromAvailable = "true";
    item.dataset.itemType = "module";
    item.addEventListener("dragstart", handleDragStartFromAvailable);
    availableItems.appendChild(item);
  });
}

function renderMenuStructure() {
  if (!menuStructureDiv) return;

  menuStructureDiv.innerHTML = "";

  if (menuStructure.length === 0) {
    return; // Leerer Zustand wird über CSS ::before angezeigt
  }

  // Sortiere nach order
  const sortedItems = [...menuStructure].sort((a, b) => (a.order || 0) - (b.order || 0));

  sortedItems.forEach((item, displayIndex) => {
    // Finde den tatsächlichen Index im ursprünglichen Array
    const actualIndex = menuStructure.indexOf(item);
    const itemElement = createMenuItemElement(item, true, actualIndex);
    menuStructureDiv.appendChild(itemElement);
  });
}

function createMenuItemElement(item, isInMenu = false, index = 0) {
  const div = document.createElement("div");
  const itemType = item.type || 'module';
  const isCustom = itemType === 'custom';
  const canHaveChildren = isCustom && !item.url; // Benutzerdefinierte Items ohne URL können Kinder haben
  
  div.className = `menu-item ${isInMenu ? `level-${item.level || 0}` : ""} ${isCustom ? 'custom-item' : 'module-item'} ${canHaveChildren ? 'can-drop' : ''}`;
  div.draggable = true;
  div.dataset.itemId = item.id;
  div.dataset.index = index;
  div.dataset.itemType = itemType;
  
  // Für Kompatibilität: auch moduleId setzen
  if (itemType === 'module') {
    div.dataset.moduleId = item.id;
  }

  if (isInMenu) {
    div.addEventListener("dragstart", handleDragStart);
    div.addEventListener("dragover", handleDragOver);
    div.addEventListener("drop", handleDrop);
    div.addEventListener("dragend", handleDragEnd);
  }

  // Icon für benutzerdefinierte Items
  const iconSvg = isCustom 
    ? `<svg class="menu-item-icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M3 9l9-7 9 7v11a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"></path>
        <polyline points="9 22 9 12 15 12 15 22"></polyline>
      </svg>`
    : `<svg class="menu-item-icon" width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <line x1="3" y1="12" x2="21" y2="12"></line>
        <line x1="3" y1="6" x2="21" y2="6"></line>
        <line x1="3" y1="18" x2="21" y2="18"></line>
      </svg>`;

  // Zeige Rollen-Badge für Container mit Rollen
  const rolesBadge = (isCustom && isInMenu && item.roles && Array.isArray(item.roles) && item.roles.length > 0) 
    ? `<span class="menu-item-badge roles-badge" title="Rollen: ${item.roles.join(', ')}">${item.roles.length} Rolle(n)</span>` 
    : '';
  
  div.innerHTML = `
    ${iconSvg}
    <span class="menu-item-label">${item.label || item.id}</span>
    ${isCustom ? '<span class="menu-item-badge">Benutzerdefiniert</span>' : ''}
    ${rolesBadge}
    ${isInMenu ? `
      <div class="menu-item-actions">
        <button class="menu-item-action indent" title="Als Untermenü einrücken" data-action="indent" ${(item.level || 0) >= 1 ? 'disabled style="opacity: 0.5; cursor: not-allowed;"' : ''}>
          →
        </button>
        <button class="menu-item-action outdent" title="Ausrücken" data-action="outdent" ${(item.level || 0) === 0 ? 'disabled style="opacity: 0.5; cursor: not-allowed;"' : ''}>
          ←
        </button>
        <button class="menu-item-action delete" title="Entfernen" data-action="delete">
          ✕
        </button>
      </div>
    ` : ""}
  `;

  // Event Listener für Aktionen (mit korrektem Index)
  if (isInMenu) {
    const indentBtn = div.querySelector('[data-action="indent"]');
    const outdentBtn = div.querySelector('[data-action="outdent"]');
    const deleteBtn = div.querySelector('[data-action="delete"]');

    if (indentBtn) {
      indentBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        const currentIndex = parseInt(div.dataset.index);
        indentMenuItem(currentIndex);
      });
    }

    if (outdentBtn) {
      outdentBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        const currentIndex = parseInt(div.dataset.index);
        outdentMenuItem(currentIndex);
      });
    }

    if (deleteBtn) {
      deleteBtn.addEventListener("click", (e) => {
        e.stopPropagation();
        const currentIndex = parseInt(div.dataset.index);
        deleteMenuItem(currentIndex);
      });
    }

    // Click-Listener auf den Menüpunkt selbst (öffnet Edit-Modal)
    // Verhindere, dass Drag & Drop den Click abfängt
    div.addEventListener("click", (e) => {
      // Ignoriere Clicks auf Action-Buttons und Icons
      if (e.target.closest('.menu-item-actions') || e.target.closest('.menu-item-icon')) {
        return;
      }
      // Ignoriere wenn gerade gedraggt wird
      if (div.classList.contains('dragging')) {
        return;
      }
      e.stopPropagation();
      const currentIndex = parseInt(div.dataset.index);
      openEditMenuItemModal(currentIndex);
    });
  }

  return div;
}

// ---------------------------------------------------------
// Benutzerdefinierte Menüpunkte
// ---------------------------------------------------------

function openCreateMenuItemModal() {
  if (!createMenuItemModal) return;
  createMenuItemForm.reset();
  createMenuItemMessage.textContent = "";
  createMenuItemMessage.className = "form-message";
  
  // Setze alle Rollen-Checkboxen zurück
  const roleCheckboxes = document.querySelectorAll('input[name="roles"]');
  roleCheckboxes.forEach(cb => cb.checked = false);
  
  // Rollen-Checkboxen sind jetzt immer sichtbar
  const rolesGroup = document.getElementById("rolesSelectionGroup");
  if (rolesGroup) {
    rolesGroup.style.display = "block";
  }
  
  createMenuItemModal.style.display = "flex";
}

function closeCreateMenuItemModal() {
  if (!createMenuItemModal) return;
  createMenuItemModal.style.display = "none";
  createMenuItemForm.reset();
  // Setze alle Rollen-Checkboxen zurück
  const roleCheckboxes = document.querySelectorAll('input[name="roles"]');
  roleCheckboxes.forEach(cb => cb.checked = false);
  createMenuItemMessage.textContent = "";
  createMenuItemMessage.className = "form-message";
}

function createCustomMenuItem() {
  if (!createMenuItemForm) return;

  const labelInput = document.getElementById("customMenuItemLabel");
  const urlInput = document.getElementById("customMenuItemUrl");

  if (!labelInput || !labelInput.value.trim()) {
    createMenuItemMessage.textContent = "Bitte geben Sie eine Bezeichnung ein.";
    createMenuItemMessage.className = "form-message error";
    return;
  }

  const label = labelInput.value.trim();
  const url = urlInput.value.trim() || null;
  const isContainer = !url || url === "#";
  
  // Sammle ausgewählte Rollen
  const roleCheckboxes = document.querySelectorAll('input[name="roles"]:checked');
  const roles = Array.from(roleCheckboxes).map(cb => cb.value);
  
  // Prüfe Rollenauswahl für Container (muss mindestens eine Rolle haben)
  if (isContainer && roles.length === 0) {
    createMenuItemMessage.textContent = "Bitte wählen Sie mindestens eine Rolle für Container-Menüpunkte aus.";
    createMenuItemMessage.className = "form-message error";
    return;
  }
  
  const itemId = `custom_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  // Erstelle neuen Menüpunkt
  const newItem = {
    id: itemId,
    label: label,
    url: url,
    type: 'custom',
    level: 0,
    order: menuStructure.length
  };
  
  // Füge Rollen hinzu, wenn welche ausgewählt wurden (für Container obligatorisch, für Items mit URL optional)
  if (roles.length > 0) {
    newItem.roles = roles;
  }

  menuStructure.push(newItem);
  updateMenuOrder();
  renderMenuStructure();
  renderAvailableItems();

  createMenuItemMessage.textContent = "Menüpunkt erfolgreich erstellt!";
  createMenuItemMessage.className = "form-message success";

  setTimeout(() => {
    closeCreateMenuItemModal();
  }, 1000);
}

// ---------------------------------------------------------
// Bearbeiten von Menüpunkten
// ---------------------------------------------------------

function openEditMenuItemModal(index) {
  if (!editMenuItemModal || !editMenuItemForm || index < 0 || index >= menuStructure.length) {
    return;
  }

  const item = menuStructure[index];
  if (!item) {
    return;
  }

  // Fülle Formular mit aktuellen Werten
  const labelInput = document.getElementById("editMenuItemLabel");
  const urlInput = document.getElementById("editMenuItemUrl");
  const indexInput = document.getElementById("editMenuItemIndex");

  if (labelInput) labelInput.value = item.label || '';
  if (urlInput) urlInput.value = item.url || '';
  if (indexInput) indexInput.value = index;

  // Setze Rollen-Checkboxen
  const roleCheckboxes = document.querySelectorAll('input[name="editRoles"]');
  roleCheckboxes.forEach(cb => {
    cb.checked = item.roles && Array.isArray(item.roles) && item.roles.includes(cb.value);
  });

  // Setze Nachricht zurück
  if (editMenuItemMessage) {
    editMenuItemMessage.textContent = "";
    editMenuItemMessage.className = "form-message";
  }

  editMenuItemModal.style.display = "flex";
}

function closeEditMenuItemModal() {
  if (!editMenuItemModal) return;
  editMenuItemModal.style.display = "none";
  editMenuItemForm.reset();
  // Setze alle Rollen-Checkboxen zurück
  const roleCheckboxes = document.querySelectorAll('input[name="editRoles"]');
  roleCheckboxes.forEach(cb => cb.checked = false);
  if (editMenuItemMessage) {
    editMenuItemMessage.textContent = "";
    editMenuItemMessage.className = "form-message";
  }
}

function saveEditedMenuItem() {
  if (!editMenuItemForm) return;

  const indexInput = document.getElementById("editMenuItemIndex");
  const labelInput = document.getElementById("editMenuItemLabel");
  const urlInput = document.getElementById("editMenuItemUrl");

  if (!indexInput || !labelInput || !labelInput.value.trim()) {
    if (editMenuItemMessage) {
      editMenuItemMessage.textContent = "Bitte geben Sie eine Bezeichnung ein.";
      editMenuItemMessage.className = "form-message error";
    }
    return;
  }

  const index = parseInt(indexInput.value);
  if (index < 0 || index >= menuStructure.length) {
    if (editMenuItemMessage) {
      editMenuItemMessage.textContent = "Ungültiger Menüpunkt-Index.";
      editMenuItemMessage.className = "form-message error";
    }
    return;
  }

  const item = menuStructure[index];
  if (!item) {
    if (editMenuItemMessage) {
      editMenuItemMessage.textContent = "Menüpunkt nicht gefunden.";
      editMenuItemMessage.className = "form-message error";
    }
    return;
  }

  const label = labelInput.value.trim();
  const url = urlInput.value.trim() || null;
  const isContainer = !url || url === "#";

  // Sammle ausgewählte Rollen
  const roleCheckboxes = document.querySelectorAll('input[name="editRoles"]:checked');
  const roles = Array.from(roleCheckboxes).map(cb => cb.value);

  // Prüfe Rollenauswahl für Container (muss mindestens eine Rolle haben)
  if (isContainer && roles.length === 0) {
    if (editMenuItemMessage) {
      editMenuItemMessage.textContent = "Bitte wählen Sie mindestens eine Rolle für Container-Menüpunkte aus.";
      editMenuItemMessage.className = "form-message error";
    }
    return;
  }

  // Aktualisiere Menüpunkt
  item.label = label;
  item.url = url;

  // Aktualisiere Rollen
  if (roles.length > 0) {
    item.roles = roles;
  } else {
    // Entferne Rollen, wenn keine ausgewählt wurden (nur für Items mit URL erlaubt)
    delete item.roles;
  }

  // Aktualisiere Anzeige
  renderMenuStructure();
  renderAvailableItems();

  if (editMenuItemMessage) {
    editMenuItemMessage.textContent = "Menüpunkt erfolgreich aktualisiert!";
    editMenuItemMessage.className = "form-message success";
  }

  setTimeout(() => {
    closeEditMenuItemModal();
  }, 1000);
}

// ---------------------------------------------------------
// Drag & Drop
// ---------------------------------------------------------

function handleDragStartFromAvailable(e) {
  draggedElement = this;
  this.classList.add("dragging");
  e.dataTransfer.effectAllowed = "copy";
  e.dataTransfer.setData("text/plain", this.dataset.moduleId);
  e.dataTransfer.setData("fromAvailable", "true");
  e.dataTransfer.setData("itemType", this.dataset.itemType || "module");
}

function handleDragStart(e) {
  draggedElement = this;
  this.classList.add("dragging");
  e.dataTransfer.effectAllowed = "move";
  e.dataTransfer.setData("text/plain", this.dataset.index);
  e.dataTransfer.setData("fromAvailable", "false");
  e.dataTransfer.setData("itemType", this.dataset.itemType || "module");
  e.dataTransfer.setData("itemId", this.dataset.itemId);
}

function handleDragOver(e) {
  if (e.preventDefault) {
    e.preventDefault();
  }
  
  const fromAvailable = e.dataTransfer.getData("fromAvailable") === "true";
  e.dataTransfer.dropEffect = fromAvailable ? "copy" : "move";

  if (draggedElement && this !== draggedElement) {
    dragOverElement = this;
    this.classList.add("drag-over");
  }
  return false;
}

function handleMenuStructureDragOver(e) {
  if (e.preventDefault) {
    e.preventDefault();
  }
  e.dataTransfer.dropEffect = "move";
  menuStructureDiv.classList.add("drag-over");
  return false;
}

function handleMenuStructureDrop(e) {
  if (e.stopPropagation) {
    e.stopPropagation();
  }
  
  const fromAvailable = e.dataTransfer.getData("fromAvailable") === "true";
  menuStructureDiv.classList.remove("drag-over");
  
  if (fromAvailable) {
    // Neues Item von "Verfügbare Items" hinzufügen
    const moduleId = e.dataTransfer.getData("text/plain");
    const module = availableModules.find(m => m.id === moduleId);
    
    if (module) {
      menuStructure.push({
        id: module.id,
        label: module.label,
        url: module.url,
        level: 0,
        order: menuStructure.length
      });
      
      updateMenuOrder();
      renderMenuStructure();
      renderAvailableItems();
    }
  }
  
  return false;
}

function handleDrop(e) {
  if (e.stopPropagation) {
    e.stopPropagation();
  }

  const fromAvailable = e.dataTransfer.getData("fromAvailable") === "true";
  const dropIndex = parseInt(this.dataset.index);
  
  if (dropIndex < 0 || dropIndex >= menuStructure.length) {
    this.classList.remove("drag-over");
    return false;
  }
  
  const dropTarget = menuStructure[dropIndex];
  const dropTargetType = dropTarget.type || 'module';
  const dropTargetId = dropTarget.id;
  
  // Prüfe ob Drop-Ziel ein benutzerdefiniertes Item ohne URL ist (kann Kinder haben)
  const canDropInto = dropTargetType === 'custom' && !dropTarget.url;
  
  if (fromAvailable) {
    // Neues Item von "Verfügbare Items" einfügen
    const moduleId = e.dataTransfer.getData("text/plain");
    const module = availableModules.find(m => m.id === moduleId);
    
    if (module) {
      if (canDropInto) {
        // Als Untermenü in benutzerdefiniertes Item einfügen
        const newItem = {
          id: module.id,
          label: module.label,
          url: module.url,
          type: 'module',
          level: 1,
          parentId: dropTargetId,
          order: menuStructure.length
        };
        
        // Finde die Position nach dem Parent-Item
        let insertIndex = dropIndex + 1;
        // Finde das nächste Item auf Level 0 oder das Ende
        while (insertIndex < menuStructure.length && menuStructure[insertIndex].level > 0) {
          insertIndex++;
        }
        menuStructure.splice(insertIndex, 0, newItem);
      } else {
        // Normale Einfügung direkt nach dem Drop-Target
        menuStructure.splice(dropIndex + 1, 0, {
          id: module.id,
          label: module.label,
          url: module.url,
          type: 'module',
          level: dropTarget.level || 0,
          order: dropIndex + 1
        });
      }
      
      updateMenuOrder();
      renderMenuStructure();
      renderAvailableItems();
    }
  } else if (draggedElement !== this) {
    // Bestehendes Item verschieben
    const draggedIndex = parseInt(draggedElement.dataset.index);
    
    if (draggedIndex < 0 || draggedIndex >= menuStructure.length) {
      this.classList.remove("drag-over");
      return false;
    }
    
    if (canDropInto) {
      // Als Untermenü in benutzerdefiniertes Item verschieben
      const item = menuStructure[draggedIndex];
      menuStructure.splice(draggedIndex, 1);
      
      // Anpassen des Index, falls durch das Entfernen verschoben
      const adjustedDropIndex = dropIndex > draggedIndex ? dropIndex - 1 : dropIndex;
      
      item.level = 1;
      item.parentId = dropTargetId;
      
      // Finde die Position nach dem Parent-Item
      let insertIndex = adjustedDropIndex + 1;
      while (insertIndex < menuStructure.length && menuStructure[insertIndex].level > 0) {
        insertIndex++;
      }
      menuStructure.splice(insertIndex, 0, item);
    } else {
      // Normale Verschiebung
      const item = menuStructure[draggedIndex];
      const oldLevel = item.level || 0;
      
      // Behalte Level, wenn es auf gleichem Level bleibt
      const targetLevel = dropTarget.level || 0;
      item.level = targetLevel;
      item.parentId = dropTarget.parentId || null;
      
      menuStructure.splice(draggedIndex, 1);
      // Anpassen des Index, falls durch das Entfernen verschoben
      const adjustedDropIndex = dropIndex > draggedIndex ? dropIndex - 1 : dropIndex;
      menuStructure.splice(adjustedDropIndex + 1, 0, item);
    }
    
    // Aktualisiere order-Werte
    updateMenuOrder();
    
    renderMenuStructure();
    renderAvailableItems();
  }

  this.classList.remove("drag-over");
  return false;
}

function handleDragEnd(e) {
  this.classList.remove("dragging");
  
  // Entferne drag-over Klasse von allen Elementen
  document.querySelectorAll(".menu-item").forEach(item => {
    item.classList.remove("drag-over");
  });
  
  draggedElement = null;
  dragOverElement = null;
}

// ---------------------------------------------------------
// Menü-Manipulation
// ---------------------------------------------------------

function indentMenuItem(index) {
  if (index === 0) return; // Erste Item kann nicht eingerückt werden
  
  const item = menuStructure[index];
  const prevItem = menuStructure[index - 1];
  const prevLevel = prevItem.level || 0;
  const currentLevel = item.level || 0;
  
  // Max. 1 Ebene tief (level 1)
  if (currentLevel < 1) {
    // Prüfe ob vorheriges Item ein Parent sein kann (Level 0)
    if (prevLevel === 0) {
      item.level = 1;
      updateMenuOrder();
      renderMenuStructure();
    }
  }
}

function outdentMenuItem(index) {
  const item = menuStructure[index];
  const currentLevel = item.level || 0;
  
  if (currentLevel > 0) {
    item.level = currentLevel - 1;
    updateMenuOrder();
    renderMenuStructure();
  }
}

function deleteMenuItem(index) {
  if (confirm("Möchten Sie diesen Menüpunkt wirklich entfernen?")) {
    menuStructure.splice(index, 1);
    updateMenuOrder();
    renderMenuStructure();
    renderAvailableItems();
  }
}

function updateMenuOrder() {
  menuStructure.forEach((item, index) => {
    item.order = index;
  });
}

// ---------------------------------------------------------
// Hilfsfunktionen
// ---------------------------------------------------------

function getCompanyId() {
  return userAuthData?.companyId || null;
}

