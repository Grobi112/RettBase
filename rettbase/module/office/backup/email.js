// email.js
// Interne E-Mail-Funktion für RettBase Office-Modul

import { db } from "../../firebase-config.js";
import {
  collection,
  doc,
  getDoc,
  getDocs,
  setDoc,
  addDoc,
  deleteDoc,
  updateDoc,
  query,
  where,
  orderBy,
  onSnapshot,
  serverTimestamp,
} from "https://www.gstatic.com/firebasejs/11.0.1/firebase-firestore.js";
import { getFunctions, httpsCallable } from "https://www.gstatic.com/firebasejs/11.0.1/firebase-functions.js";

// ---------------------------------------------------------
// Globale Zustände
// ---------------------------------------------------------

let userAuthData = null; // { uid, companyId, role, email, ... }
let allUsers = []; // Liste aller Benutzer der Firma
let allGroups = []; // Liste aller E-Mail-Gruppen
let allGroupMembers = []; // Alle Mitarbeiter für Gruppen (inkl. ohne interne E-Mail)
let currentEmailId = null; // ID der aktuell angezeigten E-Mail
let currentDraftId = null; // ID des aktuellen Entwurfs
let autoSaveTimer = null; // Timer für Auto-Save
let isSendingEmail = false; // Flagge: E-Mail wird gerade versendet (verhindert saveDraft())
let selectedGroupMembers = []; // Ausgewählte Mitglieder für Gruppenerstellung
let currentReplyType = "all"; // "all" oder "sender" für Antworten
let emailAttachments = []; // Anhänge für E-Mail

// ---------------------------------------------------------
// DOM-Elemente
// ---------------------------------------------------------

const backBtn = document.getElementById("backBtn");
const composeBtn = document.getElementById("composeBtn");
const composeModal = document.getElementById("composeModal");
const closeComposeModalBtn = document.getElementById("closeComposeModal");
const composeForm = document.getElementById("composeForm");
const recipientSelect = document.getElementById("recipientSelect");
const recipientInput = document.getElementById("recipientInput");
const selectPersonBtn = document.getElementById("selectPersonBtn");
const selectGroupBtn = document.getElementById("selectGroupBtn");
const selectEmailBtn = document.getElementById("selectEmailBtn");
const composeMessage = document.getElementById("composeMessage");
const cancelComposeBtn = document.getElementById("cancelComposeBtn");

// Mitarbeiter-Auswahl Modal
const selectMitarbeiterModal = document.getElementById("selectMitarbeiterModal");
const selectMitarbeiterForm = document.getElementById("selectMitarbeiterForm");
const cancelMitarbeiterBtn = document.getElementById("cancelMitarbeiterBtn");
const confirmMitarbeiterBtn = document.getElementById("confirmMitarbeiterBtn");
const mitarbeiterList = document.getElementById("mitarbeiterList");
const mitarbeiterSelect = document.getElementById("mitarbeiterSelect");
const mitarbeiterSearch = document.getElementById("mitarbeiterSearch");
let selectedMitarbeiter = []; // Array für ausgewählte Mitarbeiter

const inboxTab = document.getElementById("inboxTab");
const sentTab = document.getElementById("sentTab");
const draftsTab = document.getElementById("draftsTab");
const trashTab = document.getElementById("trashTab");
const inboxList = document.getElementById("inboxList");
const sentList = document.getElementById("sentList");
const draftsList = document.getElementById("draftsList");
const trashList = document.getElementById("trashList");
const tabBtns = document.querySelectorAll(".tab-btn");

const viewEmailModal = document.getElementById("viewEmailModal");
const closeViewEmailModalBtn = document.getElementById("closeViewEmailModal");
const viewEmailSubject = document.getElementById("viewEmailSubject");
const viewEmailFrom = document.getElementById("viewEmailFrom");
const viewEmailTo = document.getElementById("viewEmailTo");
const viewEmailDate = document.getElementById("viewEmailDate");
const viewEmailBody = document.getElementById("viewEmailBody");
const replyBtn = document.getElementById("replyBtn");
const deleteEmailBtn = document.getElementById("deleteEmailBtn");

// Gruppen-Menü
const emailMenuDropdown = document.getElementById("emailMenuDropdown");
const emailMenuBtn = document.getElementById("emailMenuBtn");
const emailDropdownMenu = document.getElementById("emailDropdownMenu");
const createGroupBtn = document.getElementById("createGroupBtn");

// Gruppenerstellung
const createGroupModal = document.getElementById("createGroupModal");
const closeCreateGroupModal = document.getElementById("closeCreateGroupModal");
const createGroupForm = document.getElementById("createGroupForm");
const groupName = document.getElementById("groupName");
const groupDescription = document.getElementById("groupDescription");
const groupMemberSearch = document.getElementById("groupMemberSearch");
const groupMembersList = document.getElementById("groupMembersList");
const selectedGroupMembersDiv = document.getElementById("selectedGroupMembers");
const cancelCreateGroupBtn = document.getElementById("cancelCreateGroupBtn");

// Gruppenauswahl
const selectGroupModal = document.getElementById("selectGroupModal");
const selectGroupForm = document.getElementById("selectGroupForm");
const groupSearch = document.getElementById("groupSearch");
const groupList = document.getElementById("groupList");
const confirmGroupBtn = document.getElementById("confirmGroupBtn");
const cancelGroupBtn = document.getElementById("cancelGroupBtn");

// Rich-Text-Editor (Quill)
let quillEditor = null; // Quill Editor Instanz
let emailBodyHidden = null; // Verstecktes Textarea für Form-Submit

// Antwort-Optionen (wird später initialisiert, da Elemente dynamisch sein können)
let replyOptions = null;
let replyTypeRadios = null;

// Wird später initialisiert, wenn DOM bereit ist
let deleteConfirmModal = null;
let confirmDeleteBtn = null;
let cancelDeleteBtn = null;
const permanentDeleteModal = document.getElementById("permanentDeleteModal");
const confirmPermanentDeleteBtn = document.getElementById("confirmPermanentDeleteBtn");
const cancelPermanentDeleteBtn = document.getElementById("cancelPermanentDeleteBtn");
let pendingDeleteEmailId = null;
let pendingDeleteEmailData = null;
let pendingSoftDeleteEmailId = null;
let pendingSoftDeleteEmailData = null;

// ---------------------------------------------------------
// Initialisierung
// ---------------------------------------------------------

window.addEventListener("DOMContentLoaded", () => {
  // Warte auf Auth-Daten vom Parent (Dashboard)
  waitForAuthData()
    .then((data) => {
      userAuthData = data;
      console.log(`✅ E-Mail-Modul - Auth-Daten empfangen: Role ${data.role}, Company ${data.companyId}`);
      initializeEmail();
    })
    .catch((err) => {
      console.error("E-Mail-Modul konnte Auth-Daten nicht empfangen:", err);
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

async function initializeEmail() {
  if (!userAuthData || !userAuthData.companyId) {
    console.error("Keine Auth-Daten verfügbar");
    return;
  }

  // Back-Button Event Listener - führt zurück zu Home
  if (backBtn) {
    backBtn.addEventListener("click", (e) => {
      e.preventDefault();
      console.log("🔙 Zurück-Button geklickt - navigiere zu Home");
      if (window.parent && window.parent !== window) {
        window.parent.postMessage({ type: "NAVIGATE_TO_HOME" }, "*");
      } else {
        // Fallback: Direkte Navigation zu Home
        window.location.href = "/home.html";
      }
    });
  }

  // Lade Benutzerliste
  await loadUsers();

  // Lade Gruppen
  await loadGroups();

  // Prüfe Rolle und zeige/verstecke Gruppen-Menü
  updateGroupMenuVisibility();

  // Event Listener
  setupEventListeners();

  // Empfänger-Suche wird nicht mehr benötigt (verwenden jetzt Modal)

  // Lade E-Mails
  await loadEmails();

  // Initialisiere Rich-Text-Editor
  initializeRichTextEditor();

  // Starte automatische Bereinigung gelöschter Nachrichten
  startAutoCleanup();
}

function setupEventListeners() {
  // Compose Modal
  composeBtn?.addEventListener("click", () => openComposeModal());
  closeComposeModalBtn?.addEventListener("click", () => closeComposeModal());
  cancelComposeBtn?.addEventListener("click", () => closeComposeModal());
  composeForm?.addEventListener("submit", handleComposeSubmit);

  // Empfänger-Auswahl
  selectPersonBtn?.addEventListener("click", () => openMitarbeiterModal());
  cancelMitarbeiterBtn?.addEventListener("click", () => closeMitarbeiterModal());
  confirmMitarbeiterBtn?.addEventListener("click", () => confirmMitarbeiterSelection());

  // Mitarbeiter-Suche
  mitarbeiterSearch?.addEventListener("input", (e) => {
    filterMitarbeiterList(e.target.value);
  });
  
  // Mitarbeiter-Select Change (für Desktop)
  mitarbeiterSelect?.addEventListener("change", (e) => {
    const selectedId = e.target.value;
    if (selectedId) {
      const user = allUsers.find(u => u.uid === selectedId);
      if (user && !selectedMitarbeiter.some(m => m.uid === user.uid)) {
        selectedMitarbeiter.push(user);
      }
    }
  });

  // Gruppen-Menü
  emailMenuBtn?.addEventListener("click", (e) => {
    e.stopPropagation();
    const isVisible = emailDropdownMenu?.style.display === "block";
    if (emailDropdownMenu) {
      emailDropdownMenu.style.display = isVisible ? "none" : "block";
    }
  });

  // Schließe Dropdown beim Klicken außerhalb
  document.addEventListener("click", (e) => {
    if (emailDropdownMenu && !emailMenuBtn?.contains(e.target) && !emailDropdownMenu.contains(e.target)) {
      emailDropdownMenu.style.display = "none";
    }
  });

  createGroupBtn?.addEventListener("click", () => {
    if (emailDropdownMenu) emailDropdownMenu.style.display = "none";
    openCreateGroupModal();
  });

  // Gruppenerstellung
  closeCreateGroupModal?.addEventListener("click", () => closeCreateGroupModalFunc());
  cancelCreateGroupBtn?.addEventListener("click", () => closeCreateGroupModalFunc());
  createGroupForm?.addEventListener("submit", handleCreateGroup);
  groupMemberSearch?.addEventListener("input", (e) => filterGroupMembers(e.target.value));

  // Gruppenauswahl
  selectGroupBtn?.addEventListener("click", () => openGroupSelectionModal());
  confirmGroupBtn?.addEventListener("click", () => confirmGroupSelection());
  cancelGroupBtn?.addEventListener("click", () => closeGroupSelectionModal());
  groupSearch?.addEventListener("input", (e) => filterGroupList(e.target.value));

  // Antwort-Optionen (initialisiere, wenn Elemente vorhanden sind)
  replyOptions = document.getElementById("replyOptions");
  replyTypeRadios = document.querySelectorAll('input[name="replyType"]');
  if (replyTypeRadios && replyTypeRadios.length > 0) {
    replyTypeRadios.forEach(radio => {
      radio.addEventListener("change", (e) => {
        currentReplyType = e.target.value;
      });
    });
  }

  // View Email Modal
  closeViewEmailModalBtn?.addEventListener("click", () => closeViewEmailModal());
  replyBtn?.addEventListener("click", () => handleReply());
  deleteEmailBtn?.addEventListener("click", () => handleDeleteEmail());

  // Initialisiere Delete Confirm Modal Elemente (falls noch nicht initialisiert)
  if (!deleteConfirmModal) {
    // Versuche verschiedene Methoden, um das Element zu finden
    deleteConfirmModal = document.getElementById("deleteConfirmModal");
    if (!deleteConfirmModal) {
      deleteConfirmModal = document.querySelector("#deleteConfirmModal");
    }
    if (!deleteConfirmModal) {
      deleteConfirmModal = document.querySelector('[id="deleteConfirmModal"]');
    }
    
    confirmDeleteBtn = document.getElementById("confirmDeleteBtn");
    if (!confirmDeleteBtn) {
      confirmDeleteBtn = document.querySelector("#confirmDeleteBtn");
    }
    
    cancelDeleteBtn = document.getElementById("cancelDeleteBtn");
    if (!cancelDeleteBtn) {
      cancelDeleteBtn = document.querySelector("#cancelDeleteBtn");
    }
    
    console.log(`🔍 Delete Confirm Modal initialisiert:`, {
      modal: !!deleteConfirmModal,
      modalElement: deleteConfirmModal,
      confirmBtn: !!confirmDeleteBtn,
      cancelBtn: !!cancelDeleteBtn,
      allModals: document.querySelectorAll('.modal-overlay'),
      allDeleteElements: document.querySelectorAll('[id*="delete"]')
    });
  }

  // Delete Confirm Modal (normale Löschung)
  confirmDeleteBtn?.addEventListener("click", () => handleConfirmDelete());
  cancelDeleteBtn?.addEventListener("click", () => closeDeleteConfirmModal());
  deleteConfirmModal?.addEventListener("click", (e) => {
    if (e.target === deleteConfirmModal) closeDeleteConfirmModal();
  });

  // Permanent Delete Modal
  confirmPermanentDeleteBtn?.addEventListener("click", () => handleConfirmPermanentDelete());
  cancelPermanentDeleteBtn?.addEventListener("click", () => closePermanentDeleteModal());
  permanentDeleteModal?.addEventListener("click", (e) => {
    if (e.target === permanentDeleteModal) closePermanentDeleteModal();
  });

  // Tabs
  tabBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      const tab = btn.dataset.tab;
      switchTab(tab);
    });
  });

  // Modal Overlay Click (schließen)
  composeModal?.addEventListener("click", (e) => {
    if (e.target === composeModal) closeComposeModal();
  });
  viewEmailModal?.addEventListener("click", (e) => {
    if (e.target === viewEmailModal) closeViewEmailModal();
  });
  selectMitarbeiterModal?.addEventListener("click", (e) => {
    if (e.target === selectMitarbeiterModal) closeMitarbeiterModal();
  });
  
  // Schließe Popup bei Escape
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && selectMitarbeiterModal && selectMitarbeiterModal.style.display !== "none") {
      closeMitarbeiterModal();
    }
  });
}

// ---------------------------------------------------------
// Rich-Text-Editor
// ---------------------------------------------------------

// Initialisiere Quill Font-Konfiguration (einmalig, außerhalb der Funktion)
let quillFontsInitialized = false;

function initializeQuillFonts() {
  if (quillFontsInitialized || typeof Quill === 'undefined') {
    return;
  }
  
  try {
    // Definiere Standard Windows-Schriftarten (in Kleinbuchstaben mit Bindestrichen, wie Quill sie erwartet)
    const Font = Quill.import('formats/font');
    const fontList = [
      'arial',
      'calibri',
      'cambria',
      'comic-sans-ms',
      'courier-new',
      'georgia',
      'impact',
      'lucida-console',
      'lucida-sans-unicode',
      'palatino-linotype',
      'tahoma',
      'times-new-roman',
      'trebuchet-ms',
      'verdana'
    ];
    
    Font.whitelist = fontList;
    Quill.register(Font, true);
    quillFontsInitialized = true;
    console.log("✅ Quill Fonts registriert:", fontList);
  } catch (error) {
    console.error("❌ Fehler beim Registrieren der Fonts:", error);
  }
}

// Initialisiere Quill Fonts beim Laden des Moduls (wenn Quill bereits geladen ist)
if (typeof Quill !== 'undefined') {
  initializeQuillFonts();
}

function initializeRichTextEditor() {
  const quillContainer = document.getElementById("quillEditorContainer");
  emailBodyHidden = document.getElementById("emailBodyHidden");
  
  if (!quillContainer) {
    console.warn("Quill Editor Container nicht gefunden");
    return;
  }
  
  // Prüfe ob Quill verfügbar ist
  if (typeof Quill === 'undefined') {
    console.error("Quill.js ist nicht geladen! Bitte CDN-Link überprüfen.");
    return;
  }
  
  // Initialisiere Fonts BEVOR der Editor erstellt wird
  initializeQuillFonts();
  
  // Initialisiere Quill Editor - ZERSTÖRE vorherige Instanz falls vorhanden
  if (quillEditor) {
    // Entferne alte Instanz
    const oldContainer = quillContainer;
    oldContainer.innerHTML = '';
    quillEditor = null;
  }
  
  // Quill 2.0.3 Konfiguration mit benutzerdefinierter Toolbar
  quillEditor = new Quill('#quillEditorContainer', {
    modules: {
      toolbar: {
        container: '#toolbar-container',
        handlers: {
          'bold': function() {
            // Custom Handler für Bold, um Font-Formatierung zu erhalten
            const range = quillEditor.getSelection(true);
            if (range) {
              // Hole aktuelle Formatierungen VOR dem Toggle
              const formats = range.length > 0 ? quillEditor.getFormat(range) : quillEditor.getFormat();
              const currentBold = !!formats.bold;
              const currentFont = formats.font;
              
              // Toggle Bold und stelle Font wieder her (beide zusammen anwenden)
              if (range.length > 0) {
                // Text ausgewählt - wende beide Formatierungen zusammen an
                quillEditor.formatText(range.index, range.length, 'bold', !currentBold, 'user');
                if (currentFont) {
                  quillEditor.formatText(range.index, range.length, 'font', currentFont, 'user');
                }
              } else {
                // Kein Text ausgewählt - setze Format für zukünftigen Text
                quillEditor.format('bold', !currentBold, 'user');
                if (currentFont) {
                  quillEditor.format('font', currentFont, 'user');
                }
              }
            }
          },
          'italic': function() {
            // Custom Handler für Italic, um Font-Formatierung zu erhalten
            const range = quillEditor.getSelection(true);
            if (range) {
              // Hole aktuelle Formatierungen VOR dem Toggle
              const formats = range.length > 0 ? quillEditor.getFormat(range) : quillEditor.getFormat();
              const currentItalic = !!formats.italic;
              const currentFont = formats.font;
              
              // Toggle Italic und stelle Font wieder her (beide zusammen anwenden)
              if (range.length > 0) {
                // Text ausgewählt - wende beide Formatierungen zusammen an
                quillEditor.formatText(range.index, range.length, 'italic', !currentItalic, 'user');
                if (currentFont) {
                  quillEditor.formatText(range.index, range.length, 'font', currentFont, 'user');
                }
              } else {
                // Kein Text ausgewählt - setze Format für zukünftigen Text
                quillEditor.format('italic', !currentItalic, 'user');
                if (currentFont) {
                  quillEditor.format('font', currentFont, 'user');
                }
              }
            }
          }
        }
      }
    },
    placeholder: 'Ihre Nachricht...',
    theme: 'snow'
  });
  
  // Setze Arial als Standard-Schriftart für den Editor
  if (quillEditor) {
    // Setze Standard-Schriftart im Editor-Container
    const editorElement = quillEditor.root;
    if (editorElement) {
      editorElement.style.fontFamily = 'Arial, sans-serif';
    }
    
    // Wenn Editor leer ist, setze Arial als Format für zukünftigen Text
    if (quillEditor.getLength() <= 1) {
      quillEditor.format('font', 'arial', 'user');
    }
  }
  
  // Synchronisiere Quill-Inhalt mit verstecktem Textarea
  quillEditor.on('text-change', () => {
    if (emailBodyHidden && quillEditor) {
      emailBodyHidden.value = quillEditor.root.innerHTML;
    }
  });
  
  console.log("✅ Quill Editor initialisiert");
  
  // Datei-Upload Handler (unabhängig vom Editor)
  const fileInput = document.getElementById("fileInput");
  const fileSelectBtn = document.getElementById("fileSelectBtn");
  const fileDropZone = document.getElementById("fileDropZone");
  
  if (fileSelectBtn && fileInput) {
    fileSelectBtn.addEventListener("click", () => {
      fileInput.click();
    });
  }
  
  if (fileInput) {
    fileInput.addEventListener("change", handleFileSelect);
  }
  
  if (fileDropZone) {
    fileDropZone.addEventListener("dragover", (e) => {
      e.preventDefault();
      fileDropZone.classList.add("dragover");
    });
    
    fileDropZone.addEventListener("dragleave", () => {
      fileDropZone.classList.remove("dragover");
    });
    
    fileDropZone.addEventListener("drop", (e) => {
      e.preventDefault();
      fileDropZone.classList.remove("dragover");
      const files = Array.from(e.dataTransfer.files);
      handleFiles(files);
    });
  }
}

// Führe Formatierungsbefehl aus (mit Schriftart-Erhaltung bei Bold)
function executeFormatCommand(command, value = null) {
  if (!emailBodyEditor) return;
  
  emailBodyEditor.focus();
  
  // Spezielle Behandlung für Bold-Befehl: Schriftart beibehalten
  if (command === "bold") {
    const selection = window.getSelection();
    if (selection.rangeCount > 0) {
      const range = selection.getRangeAt(0);
      
      // Wenn Text ausgewählt ist
      if (!range.collapsed) {
        // Speichere aktuelle Schriftart und Formatierung
        const container = range.commonAncestorContainer;
        
        // Finde das Element mit der Schriftart
        let fontElement = container.nodeType === Node.TEXT_NODE 
          ? container.parentElement 
          : container;
        
        // Suche nach dem nächsten Element mit font-family
        while (fontElement && fontElement !== emailBodyEditor) {
          const computedStyle = window.getComputedStyle(fontElement);
          const fontFamily = computedStyle.fontFamily;
          if (fontFamily && fontFamily !== 'inherit' && fontFamily !== 'initial') {
            break;
          }
          fontElement = fontElement.parentElement;
        }
        
        // Extrahiere Schriftart-Name (ohne Anführungszeichen)
        let currentFontFamily = null;
        if (fontElement && fontElement !== emailBodyEditor) {
          const computedStyle = window.getComputedStyle(fontElement);
          const fontFamily = computedStyle.fontFamily;
          // Entferne Anführungszeichen und extrahiere ersten Font-Namen
          const match = fontFamily.match(/(?:^|,)\s*["']?([^,"']+)["']?/);
          if (match) {
            currentFontFamily = match[1].trim();
          }
        }
        
        // Führe Bold-Befehl aus
        document.execCommand("bold", false, null);
        
        // Stelle Schriftart wieder her, falls vorhanden
        if (currentFontFamily && currentFontFamily !== 'Arial' && currentFontFamily !== 'sans-serif') {
          // Prüfe, ob der ausgewählte Text bereits bold ist
          const newSelection = window.getSelection();
          if (newSelection.rangeCount > 0) {
            const newRange = newSelection.getRangeAt(0);
            const boldElement = newRange.commonAncestorContainer.nodeType === Node.TEXT_NODE
              ? newRange.commonAncestorContainer.parentElement
              : newRange.commonAncestorContainer;
            
            // Wenn das Element ein <b> oder <strong> Tag ist, setze font-family darauf
            if (boldElement && (boldElement.tagName === 'B' || boldElement.tagName === 'STRONG')) {
              boldElement.style.fontFamily = currentFontFamily;
            } else {
              // Erstelle ein <span> Element mit der Schriftart
              const span = document.createElement("span");
              span.style.fontFamily = currentFontFamily;
              try {
                newRange.surroundContents(span);
              } catch (e) {
                // Falls surroundContents fehlschlägt, verwende insertNode
                span.appendChild(newRange.extractContents());
                newRange.insertNode(span);
              }
              newSelection.removeAllRanges();
              newSelection.addRange(newRange);
            }
          }
        }
      } else {
        // Kein Text ausgewählt - teile Text am Cursor auf
        const container = range.commonAncestorContainer;
        const offset = range.startOffset;
        
        if (container.nodeType === Node.TEXT_NODE) {
          const textNode = container;
          const textContent = textNode.textContent;
          const textBefore = textContent.substring(0, offset);
          const textAfter = textContent.substring(offset);
          
          const parentElement = textNode.parentElement;
          
          if (textAfter.length > 0) {
            // Text nach Cursor aufteilen
            textNode.textContent = textBefore;
            
            // Erstelle <b> für Text nach Cursor
            const boldElement = document.createElement("b");
            const afterTextNode = document.createTextNode(textAfter);
            boldElement.appendChild(afterTextNode);
            
            if (parentElement === emailBodyEditor) {
              emailBodyEditor.insertBefore(boldElement, textNode.nextSibling);
            } else {
              parentElement.parentElement.insertBefore(boldElement, parentElement.nextSibling);
            }
            
            // Setze Cursor in den neuen <b> Element
            const newRange = document.createRange();
            newRange.setStart(afterTextNode, 0);
            newRange.collapse(true);
            selection.removeAllRanges();
            selection.addRange(newRange);
          } else {
            // Kein Text nach Cursor - erstelle <b> für zukünftigen Text
            const boldElement = document.createElement("b");
            const emptyTextNode = document.createTextNode("");
            boldElement.appendChild(emptyTextNode);
            
            if (parentElement === emailBodyEditor) {
              emailBodyEditor.insertBefore(boldElement, textNode.nextSibling);
            } else {
              parentElement.parentElement.insertBefore(boldElement, parentElement.nextSibling);
            }
            
            const newRange = document.createRange();
            newRange.setStart(emptyTextNode, 0);
            newRange.collapse(true);
            selection.removeAllRanges();
            selection.addRange(newRange);
          }
        } else {
          // Cursor zwischen Elementen - verwende execCommand
          document.execCommand("bold", false, null);
        }
      }
    } else {
      // Fallback: Normale Bold-Ausführung
      document.execCommand("bold", false, null);
    }
  } else if (command === "fontName" && value) {
    // Schriftart ändern - wende direkt an
    console.log("🔧 executeFormatCommand: fontName =", value);
    emailBodyEditor.focus();
    
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0) {
      // Keine Auswahl - erstelle Range am Ende
      const range = document.createRange();
      range.selectNodeContents(emailBodyEditor);
      range.collapse(false);
      selection.removeAllRanges();
      selection.addRange(range);
    }
    
    if (selection.rangeCount > 0) {
      const range = selection.getRangeAt(0);
      
      // Wenn Text ausgewählt ist
      if (!range.collapsed) {
        // Prüfe, ob bereits eine Formatierung (Schriftgröße) vorhanden ist
        const container = range.commonAncestorContainer;
        let element = container.nodeType === Node.TEXT_NODE ? container.parentElement : container;
        let existingFontSize = null;
        while (element && element !== emailBodyEditor) {
          if (element.tagName === "SPAN") {
            const computedStyle = window.getComputedStyle(element);
            if (computedStyle.fontSize && computedStyle.fontSize !== 'inherit') {
              existingFontSize = computedStyle.fontSize;
              break;
            }
          }
          element = element.parentElement;
        }
        
        // Erstelle ein <span> Element mit der Schriftart
        const span = document.createElement("span");
        // Kombiniere Schriftart mit vorhandener Schriftgröße
        if (existingFontSize) {
          span.style.cssText = `font-family: ${value} !important; font-size: ${existingFontSize} !important; display: inline;`;
        } else {
          span.style.cssText = `font-family: ${value} !important; display: inline;`;
        }
        
        console.log("📝 Wende Schriftart auf ausgewählten Text an:", value, existingFontSize ? `(behalte Schriftgröße: ${existingFontSize})` : "");
        
        try {
          range.surroundContents(span);
          console.log("✅ Schriftart erfolgreich angewendet (surroundContents)");
          // Setze Cursor nach dem span
          const newRange = document.createRange();
          newRange.setStartAfter(span);
          newRange.collapse(true);
          selection.removeAllRanges();
          selection.addRange(newRange);
        } catch (e) {
          console.warn("surroundContents fehlgeschlagen, verwende extractContents:", e);
          // Falls surroundContents fehlschlägt, verwende extractContents
          const contents = range.extractContents();
          span.appendChild(contents);
          range.insertNode(span);
          console.log("✅ Schriftart erfolgreich angewendet (extractContents)");
          // Setze Cursor nach dem span
          const newRange = document.createRange();
          newRange.setStartAfter(span);
          newRange.collapse(true);
          selection.removeAllRanges();
          selection.addRange(newRange);
        }
      } else {
        // Kein Text ausgewählt - teile Text am Cursor auf, damit bereits geschriebener Text seine Formatierung behält
        const container = range.commonAncestorContainer;
        const offset = range.startOffset;
        
        console.log("📝 Kein Text ausgewählt, Container:", container.nodeType === Node.TEXT_NODE ? "TEXT_NODE" : container.tagName, "Offset:", offset);
        
        if (container.nodeType === Node.TEXT_NODE) {
          // Cursor ist in einem Text-Node - teile den Text am Cursor
          const textNode = container;
          const textContent = textNode.textContent;
          const textBefore = textContent.substring(0, offset);
          const textAfter = textContent.substring(offset);
          const parentElement = textNode.parentElement;
          
          // Prüfe, ob bereits eine Formatierung (Schriftgröße) vorhanden ist
          let existingFontSize = null;
          if (parentElement && parentElement !== emailBodyEditor && parentElement.tagName === "SPAN") {
            const computedStyle = window.getComputedStyle(parentElement);
            if (computedStyle.fontSize && computedStyle.fontSize !== 'inherit') {
              existingFontSize = computedStyle.fontSize;
            }
          }
          
          if (textAfter.length > 0) {
            // Es gibt Text nach dem Cursor - teile auf
            textNode.textContent = textBefore;
            
            // Erstelle neuen span für Text nach dem Cursor
            const newSpan = document.createElement("span");
            // Kombiniere Schriftart mit vorhandener Schriftgröße
            if (existingFontSize) {
              newSpan.style.cssText = `font-family: ${value} !important; font-size: ${existingFontSize} !important; display: inline;`;
            } else {
              newSpan.style.cssText = `font-family: ${value} !important; display: inline;`;
            }
            
            const afterTextNode = document.createTextNode(textAfter);
            newSpan.appendChild(afterTextNode);
            
            // Füge neuen span ein
            if (parentElement === emailBodyEditor) {
              emailBodyEditor.insertBefore(newSpan, textNode.nextSibling);
            } else {
              parentElement.parentElement.insertBefore(newSpan, parentElement.nextSibling);
            }
            
            // Setze Cursor NACH dem Text im neuen span (am Ende)
            const newRange = document.createRange();
            newRange.setStart(afterTextNode, afterTextNode.textContent.length);
            newRange.collapse(true);
            selection.removeAllRanges();
            selection.addRange(newRange);
            console.log("✅ Text am Cursor aufgeteilt - Cursor nach dem Text");
          } else {
            // Kein Text nach Cursor - erstelle neuen span für zukünftigen Text
            const newSpan = document.createElement("span");
            // Kombiniere Schriftart mit vorhandener Schriftgröße
            if (existingFontSize) {
              newSpan.style.cssText = `font-family: ${value} !important; font-size: ${existingFontSize} !important; display: inline;`;
            } else {
              newSpan.style.cssText = `font-family: ${value} !important; display: inline;`;
            }
            
            // Verwende Zero-width space, damit der span nicht leer ist und Text darin erstellt wird
            const zeroWidthNode = document.createTextNode("\u200B");
            newSpan.appendChild(zeroWidthNode);
            
            // Füge neuen span ein
            if (parentElement === emailBodyEditor) {
              emailBodyEditor.insertBefore(newSpan, textNode.nextSibling);
            } else {
              parentElement.parentElement.insertBefore(newSpan, parentElement.nextSibling);
            }
            
            // Setze Cursor nach dem Zero-width space (Position 1)
            const newRange = document.createRange();
            newRange.setStart(zeroWidthNode, 1);
            newRange.collapse(true);
            selection.removeAllRanges();
            selection.addRange(newRange);
            console.log("✅ Neuer Formatierungs-span erstellt mit Zero-width space - Cursor nach Zero-width space");
          }
        } else {
          // Cursor ist zwischen Elementen - prüfe vorhandene Formatierung
          let existingFontSize = null;
          const container = range.commonAncestorContainer;
          let element = container.nodeType === Node.TEXT_NODE ? container.parentElement : container;
          if (element && element !== emailBodyEditor && element.tagName === "SPAN") {
            const computedStyle = window.getComputedStyle(element);
            if (computedStyle.fontSize && computedStyle.fontSize !== 'inherit') {
              existingFontSize = computedStyle.fontSize;
            }
          }
          
          // Erstelle neuen span
          const newSpan = document.createElement("span");
          // Kombiniere Schriftart mit vorhandener Schriftgröße
          if (existingFontSize) {
            newSpan.style.cssText = `font-family: ${value} !important; font-size: ${existingFontSize} !important; display: inline;`;
          } else {
            newSpan.style.cssText = `font-family: ${value} !important; display: inline;`;
          }
          
          // Verwende Zero-width space, damit der span nicht leer ist
          const zeroWidthNode = document.createTextNode("\u200B");
          newSpan.appendChild(zeroWidthNode);
          
          try {
            range.insertNode(newSpan);
            const newRange = document.createRange();
            newRange.setStart(zeroWidthNode, 1);
            newRange.collapse(true);
            selection.removeAllRanges();
            selection.addRange(newRange);
            console.log("✅ Neuer Formatierungs-span eingefügt mit Zero-width space");
          } catch (e) {
            console.error("❌ Fehler beim Einfügen der Schriftart:", e);
          }
        }
      }
    }
    
    syncEditorToTextarea();
  } else if (command === "fontSize" && value) {
    // Schriftgröße ändern - wende direkt an
    console.log("🔧 executeFormatCommand: fontSize =", value + "px");
    emailBodyEditor.focus();
    
    const selection = window.getSelection();
    if (!selection || selection.rangeCount === 0) {
      // Keine Auswahl - erstelle Range am Ende
      const range = document.createRange();
      range.selectNodeContents(emailBodyEditor);
      range.collapse(false);
      selection.removeAllRanges();
      selection.addRange(range);
    }
    
    if (selection.rangeCount > 0) {
      const range = selection.getRangeAt(0);
      
      // Wenn Text ausgewählt ist
      if (!range.collapsed) {
        // Prüfe, ob bereits eine Formatierung (Schriftart) vorhanden ist
        const container = range.commonAncestorContainer;
        let element = container.nodeType === Node.TEXT_NODE ? container.parentElement : container;
        let existingFontFamily = null;
        while (element && element !== emailBodyEditor) {
          if (element.tagName === "SPAN") {
            const computedStyle = window.getComputedStyle(element);
            if (computedStyle.fontFamily && computedStyle.fontFamily !== 'inherit') {
              // Extrahiere ersten Font-Namen
              const match = computedStyle.fontFamily.match(/(?:^|,)\s*["']?([^,"']+)["']?/);
              if (match) {
                existingFontFamily = match[1].trim();
                break;
              }
            }
          }
          element = element.parentElement;
        }
        
        // Erstelle ein <span> Element mit der Schriftgröße
        const span = document.createElement("span");
        // Kombiniere Schriftgröße mit vorhandener Schriftart
        if (existingFontFamily) {
          span.style.cssText = `font-family: ${existingFontFamily} !important; font-size: ${value}px !important; display: inline;`;
        } else {
          span.style.cssText = `font-size: ${value}px !important; display: inline;`;
        }
        
        console.log("📝 Wende Schriftgröße auf ausgewählten Text an:", value + "px", existingFontFamily ? `(behalte Schriftart: ${existingFontFamily})` : "");
        
        try {
          range.surroundContents(span);
          console.log("✅ Schriftgröße erfolgreich angewendet (surroundContents)");
          // Setze Cursor nach dem span
          const newRange = document.createRange();
          newRange.setStartAfter(span);
          newRange.collapse(true);
          selection.removeAllRanges();
          selection.addRange(newRange);
        } catch (e) {
          console.warn("surroundContents fehlgeschlagen, verwende extractContents:", e);
          // Falls surroundContents fehlschlägt, verwende extractContents
          const contents = range.extractContents();
          span.appendChild(contents);
          range.insertNode(span);
          console.log("✅ Schriftgröße erfolgreich angewendet (extractContents)");
          // Setze Cursor nach dem span
          const newRange = document.createRange();
          newRange.setStartAfter(span);
          newRange.collapse(true);
          selection.removeAllRanges();
          selection.addRange(newRange);
        }
      } else {
        // Kein Text ausgewählt - erstelle Formatierungs-span für zukünftigen Text
        // WICHTIG: Teile Text am Cursor auf, damit bereits geschriebener Text seine Formatierung behält
        const container = range.commonAncestorContainer;
        const offset = range.startOffset;
        
        console.log("📝 Kein Text ausgewählt, Container:", container.nodeType === Node.TEXT_NODE ? "TEXT_NODE" : container.tagName, "Offset:", offset);
        
        if (container.nodeType === Node.TEXT_NODE) {
          // Cursor ist in einem Text-Node
          const textNode = container;
          const textContent = textNode.textContent;
          const textBefore = textContent.substring(0, offset);
          const textAfter = textContent.substring(offset);
          const parentElement = textNode.parentElement;
          
          // Prüfe, ob bereits eine Formatierung (Schriftart) vorhanden ist
          let existingFontFamily = null;
          if (parentElement && parentElement !== emailBodyEditor && parentElement.tagName === "SPAN") {
            const computedStyle = window.getComputedStyle(parentElement);
            if (computedStyle.fontFamily && computedStyle.fontFamily !== 'inherit') {
              // Extrahiere ersten Font-Namen
              const match = computedStyle.fontFamily.match(/(?:^|,)\s*["']?([^,"']+)["']?/);
              if (match) {
                existingFontFamily = match[1].trim();
              }
            }
          }
          
          if (textAfter.length > 0) {
            // Es gibt Text nach dem Cursor - teile auf
            textNode.textContent = textBefore;
            
            // Erstelle neuen span für Text nach dem Cursor
            const newSpan = document.createElement("span");
            // Kombiniere Schriftgröße mit vorhandener Schriftart
            if (existingFontFamily) {
              newSpan.style.cssText = `font-family: ${existingFontFamily} !important; font-size: ${value}px !important; display: inline;`;
            } else {
              newSpan.style.cssText = `font-size: ${value}px !important; display: inline;`;
            }
            
            const afterTextNode = document.createTextNode(textAfter);
            newSpan.appendChild(afterTextNode);
            
            // Füge neuen span ein
            if (parentElement === emailBodyEditor) {
              emailBodyEditor.insertBefore(newSpan, textNode.nextSibling);
            } else {
              // Wenn Parent ein span ist, füge nach dem Parent ein
              const grandParent = parentElement.parentElement;
              if (grandParent) {
                grandParent.insertBefore(newSpan, parentElement.nextSibling);
              } else {
                emailBodyEditor.insertBefore(newSpan, parentElement.nextSibling);
              }
            }
            
            // Setze Cursor am Anfang des neuen spans
            const newRange = document.createRange();
            newRange.setStart(afterTextNode, 0);
            newRange.collapse(true);
            selection.removeAllRanges();
            selection.addRange(newRange);
            console.log("✅ Text am Cursor aufgeteilt");
          } else {
            // Kein Text nach Cursor - erstelle neuen span für zukünftigen Text
            const newSpan = document.createElement("span");
            // Kombiniere Schriftgröße mit vorhandener Schriftart
            if (existingFontFamily) {
              newSpan.style.cssText = `font-family: ${existingFontFamily} !important; font-size: ${value}px !important; display: inline;`;
            } else {
              newSpan.style.cssText = `font-size: ${value}px !important; display: inline;`;
            }
            
            // Verwende Zero-width space, damit der span nicht leer ist und Text darin erstellt wird
            const zeroWidthNode = document.createTextNode("\u200B");
            newSpan.appendChild(zeroWidthNode);
            
            // Füge neuen span ein
            if (parentElement === emailBodyEditor) {
              emailBodyEditor.insertBefore(newSpan, textNode.nextSibling);
            } else {
              const grandParent = parentElement.parentElement;
              if (grandParent) {
                grandParent.insertBefore(newSpan, parentElement.nextSibling);
              } else {
                emailBodyEditor.insertBefore(newSpan, parentElement.nextSibling);
              }
            }
            
            // Setze Cursor nach dem Zero-width space (Position 1)
            const newRange = document.createRange();
            newRange.setStart(zeroWidthNode, 1);
            newRange.collapse(true);
            selection.removeAllRanges();
            selection.addRange(newRange);
            console.log("✅ Neuer Formatierungs-span erstellt mit Zero-width space - Cursor nach Zero-width space");
          }
        } else {
          // Cursor ist zwischen Elementen oder in einem Element - prüfe vorhandene Formatierung
          let existingFontFamily = null;
          const container = range.commonAncestorContainer;
          let element = container.nodeType === Node.TEXT_NODE ? container.parentElement : container;
          if (element && element !== emailBodyEditor && element.tagName === "SPAN") {
            const computedStyle = window.getComputedStyle(element);
            if (computedStyle.fontFamily && computedStyle.fontFamily !== 'inherit') {
              // Extrahiere ersten Font-Namen
              const match = computedStyle.fontFamily.match(/(?:^|,)\s*["']?([^,"']+)["']?/);
              if (match) {
                existingFontFamily = match[1].trim();
              }
            }
          }
          
          // Erstelle neuen span und füge ihn am Cursor ein
          const newSpan = document.createElement("span");
          // Kombiniere Schriftgröße mit vorhandener Schriftart
          if (existingFontFamily) {
            newSpan.style.cssText = `font-family: ${existingFontFamily} !important; font-size: ${value}px !important; display: inline;`;
          } else {
            newSpan.style.cssText = `font-size: ${value}px !important; display: inline;`;
          }
          
          // Verwende Zero-width space, damit der span nicht leer ist
          const zeroWidthNode = document.createTextNode("\u200B");
          newSpan.appendChild(zeroWidthNode);
          
          try {
            range.insertNode(newSpan);
            const newRange = document.createRange();
            newRange.setStart(zeroWidthNode, 1);
            newRange.collapse(true);
            selection.removeAllRanges();
            selection.addRange(newRange);
            console.log("✅ Neuer Formatierungs-span eingefügt mit Zero-width space");
          } catch (e) {
            console.error("❌ Fehler beim Einfügen der Schriftgröße:", e);
            // Fallback: Füge am Ende ein
            emailBodyEditor.appendChild(newSpan);
            const newRange = document.createRange();
            newRange.setStart(emptyTextNode, 0);
            newRange.collapse(true);
            selection.removeAllRanges();
            selection.addRange(newRange);
          }
        }
      }
    }
    
    syncEditorToTextarea();
  } else if (command === "italic" || command === "underline" || command === "strikeThrough") {
    // Italic oder Underline - teile Text am Cursor auf, wenn kein Text ausgewählt
    const selection = window.getSelection();
    if (selection.rangeCount > 0) {
      const range = selection.getRangeAt(0);
      
      if (!range.collapsed) {
        // Text ausgewählt - normale Formatierung
        document.execCommand(command, false, null);
      } else {
        // Kein Text ausgewählt - teile Text am Cursor auf
        const container = range.commonAncestorContainer;
        const offset = range.startOffset;
        
        if (container.nodeType === Node.TEXT_NODE) {
          const textNode = container;
          const textContent = textNode.textContent;
          const textBefore = textContent.substring(0, offset);
          const textAfter = textContent.substring(offset);
          
          const parentElement = textNode.parentElement;
          
          if (textAfter.length > 0) {
            // Text nach Cursor aufteilen
            textNode.textContent = textBefore;
            
            // Erstelle Formatierungs-Element für Text nach Cursor
            const formatElement = document.createElement(
              command === "italic" ? "i" : 
              command === "underline" ? "u" : 
              "s" // strikeThrough
            );
            const afterTextNode = document.createTextNode(textAfter);
            formatElement.appendChild(afterTextNode);
            
            if (parentElement === emailBodyEditor) {
              emailBodyEditor.insertBefore(formatElement, textNode.nextSibling);
            } else {
              parentElement.parentElement.insertBefore(formatElement, parentElement.nextSibling);
            }
            
            // Setze Cursor NACH dem Text im neuen Element (am Ende)
            const newRange = document.createRange();
            newRange.setStart(afterTextNode, afterTextNode.textContent.length);
            newRange.collapse(true);
            selection.removeAllRanges();
            selection.addRange(newRange);
          } else {
            // Kein Text nach Cursor - erstelle Formatierungs-Element für zukünftigen Text
            const formatElement = document.createElement(
              command === "italic" ? "i" : 
              command === "underline" ? "u" : 
              "s" // strikeThrough
            );
            // Verwende Zero-width space
            const zeroWidthNode = document.createTextNode("\u200B");
            formatElement.appendChild(zeroWidthNode);
            
            if (parentElement === emailBodyEditor) {
              emailBodyEditor.insertBefore(formatElement, textNode.nextSibling);
            } else {
              parentElement.parentElement.insertBefore(formatElement, parentElement.nextSibling);
            }
            
            const newRange = document.createRange();
            newRange.setStart(zeroWidthNode, 1);
            newRange.collapse(true);
            selection.removeAllRanges();
            selection.addRange(newRange);
          }
        } else {
          // Cursor zwischen Elementen - verwende execCommand
          document.execCommand(command, false, null);
        }
      }
    } else {
      document.execCommand(command, false, null);
    }
    
    syncEditorToTextarea();
  } else if (command === "justifyLeft" || command === "justifyCenter" || command === "justifyRight") {
    // Textausrichtung
    document.execCommand(command, false, null);
    syncEditorToTextarea();
  } else if (command === "insertUnorderedList" || command === "insertOrderedList") {
    // Listen
    document.execCommand(command, false, null);
    syncEditorToTextarea();
  } else if (command === "foreColor" && value) {
    // Textfarbe
    document.execCommand("foreColor", false, value);
    syncEditorToTextarea();
  } else if (command === "backColor" && value) {
    // Hintergrundfarbe
    document.execCommand("backColor", false, value);
    syncEditorToTextarea();
  } else {
    // Andere Befehle
    document.execCommand(command, false, null);
    syncEditorToTextarea();
  }
}

// Aktualisiere Toolbar-Button-Status basierend auf aktueller Auswahl
function updateToolbarButtons() {
  if (!emailToolbar || !emailBodyEditor) return;
  
  const toolbarButtons = emailToolbar.querySelectorAll(".toolbar-btn");
  toolbarButtons.forEach(btn => {
    const command = btn.dataset.command;
    if (command) {
      const isActive = document.queryCommandState(command);
      if (isActive) {
        btn.classList.add("active");
      } else {
        btn.classList.remove("active");
      }
    }
  });
  
  // Aktualisiere Schriftart-Auswahl (nur wenn Dropdown nicht fokussiert ist)
  const fontFamilySelect = document.getElementById("fontFamilySelect");
  if (fontFamilySelect && document.activeElement !== fontFamilySelect) {
    // Versuche aktuelle Schriftart zu ermitteln
    const selection = window.getSelection();
    if (selection.rangeCount > 0) {
      const range = selection.getRangeAt(0);
      const container = range.commonAncestorContainer;
      let element = container.nodeType === Node.TEXT_NODE ? container.parentElement : container;
      
      // Suche nach dem nächsten Element mit font-family Style
      while (element && element !== emailBodyEditor) {
        if (element.style && element.style.fontFamily) {
          const fontFamily = element.style.fontFamily;
          // Entferne Anführungszeichen
          const cleanFont = fontFamily.replace(/['"]/g, '');
          const option = Array.from(fontFamilySelect.options).find(opt => opt.value === cleanFont);
          if (option) {
            fontFamilySelect.value = cleanFont;
            return; // Schriftart gefunden, beende Funktion
          }
        }
        element = element.parentElement;
      }
      
      // Fallback: Versuche über computedStyle
      element = container.nodeType === Node.TEXT_NODE ? container.parentElement : container;
      const computedStyle = window.getComputedStyle(element);
      const fontFamily = computedStyle.fontFamily;
      
      // Versuche Schriftart in der Select-Liste zu finden
      const match = fontFamily.match(/(?:^|,)\s*["']?([^,"']+)["']?/);
      if (match) {
        const currentFont = match[1].trim();
        const option = Array.from(fontFamilySelect.options).find(opt => opt.value === currentFont);
        if (option) {
          fontFamilySelect.value = currentFont;
        }
        // Setze nicht auf "" zurück, wenn keine Übereinstimmung - behalte aktuelle Auswahl
      }
    }
  }
  
  // Aktualisiere Schriftgröße-Auswahl (nur wenn Dropdown nicht fokussiert ist)
  const fontSizeSelect = document.getElementById("fontSizeSelect");
  if (fontSizeSelect && document.activeElement !== fontSizeSelect) {
    const selection = window.getSelection();
    if (selection.rangeCount > 0) {
      const range = selection.getRangeAt(0);
      const container = range.commonAncestorContainer;
      let element = container.nodeType === Node.TEXT_NODE ? container.parentElement : container;
      
      // Suche nach dem nächsten Element mit fontSize Style
      while (element && element !== emailBodyEditor) {
        if (element.style && element.style.fontSize) {
          const fontSize = element.style.fontSize;
          // Extrahiere Pixel-Wert
          const match = fontSize.match(/(\d+)px/);
          if (match) {
            const sizeValue = match[1];
            const option = Array.from(fontSizeSelect.options).find(opt => opt.value === sizeValue);
            if (option) {
              fontSizeSelect.value = sizeValue;
              return; // Schriftgröße gefunden, beende Funktion
            }
          }
        }
        element = element.parentElement;
      }
      
      // Fallback: Versuche über computedStyle
      element = container.nodeType === Node.TEXT_NODE ? container.parentElement : container;
      const computedStyle = window.getComputedStyle(element);
      const fontSize = computedStyle.fontSize;
      const match = fontSize.match(/(\d+)px/);
      if (match) {
        const sizeValue = match[1];
        const option = Array.from(fontSizeSelect.options).find(opt => opt.value === sizeValue);
        if (option) {
          fontSizeSelect.value = sizeValue;
        }
        // Setze nicht auf "" zurück, wenn keine Übereinstimmung - behalte aktuelle Auswahl
      }
    }
  }
}

// Synchronisiere ContentEditable-Inhalt mit verstecktem Textarea
function syncEditorToTextarea() {
  if (!quillEditor || !emailBodyHidden) return;
  
  // Kopiere HTML-Inhalt von Quill in Textarea (für Form-Submit)
  emailBodyHidden.value = quillEditor.root.innerHTML;
}

// ---------------------------------------------------------
// Benutzer laden
// ---------------------------------------------------------

async function loadUsers() {
  try {
    const companyId = getCompanyId();
    
    // Lade ALLE Benutzer aus users Collection (unabhängig von Rolle)
    const usersRef = collection(db, "kunden", companyId, "users");
    const usersSnapshot = await getDocs(usersRef);

    // Lade auch Mitarbeiter aus schichtplanMitarbeiter (als Fallback für E-Mail-Adressen und internalEmail)
    let mitarbeiterEmailMap = new Map(); // Login-E-Mail -> Mitarbeiter-Daten
    let mitarbeiterNameMap = new Map(); // "vorname nachname" -> Mitarbeiter-Daten (für Zuordnung)
    let mitarbeiterInternalEmailMap = new Map(); // internalEmail -> Mitarbeiter-Daten
    let allMitarbeiterWithInternalEmail = []; // Alle Mitarbeiter mit internalEmail
    try {
      const mitarbeiterRef = collection(db, "kunden", companyId, "schichtplanMitarbeiter");
      const mitarbeiterSnapshot = await getDocs(mitarbeiterRef);
      console.log(`📋 Lade ${mitarbeiterSnapshot.size} Mitarbeiter aus schichtplanMitarbeiter`);
      mitarbeiterSnapshot.forEach((doc) => {
        const mitarbeiterData = doc.data();
        if (mitarbeiterData.active !== false) {
          const vorname = mitarbeiterData.vorname || "";
          const nachname = mitarbeiterData.nachname || "";
          const fullName = `${vorname} ${nachname}`.trim().toLowerCase();
          
          if (mitarbeiterData.email) {
            // Verwende E-Mail als Key, um später zuordnen zu können
            mitarbeiterEmailMap.set(mitarbeiterData.email.toLowerCase(), {
              email: mitarbeiterData.email,
              internalEmail: mitarbeiterData.internalEmail || null,
              vorname: vorname,
              nachname: nachname,
            });
          }
          
          // Erstelle auch eine Map für Name -> Mitarbeiter-Daten (für Zuordnung über Name)
          if (fullName) {
            mitarbeiterNameMap.set(fullName, {
              email: mitarbeiterData.email || "",
              internalEmail: mitarbeiterData.internalEmail || null,
              vorname: vorname,
              nachname: nachname,
            });
          }
          
          // Erstelle auch eine Map für internalEmail -> Mitarbeiter-Daten
          if (mitarbeiterData.internalEmail) {
            console.log(`📧 Mitarbeiter ${vorname} ${nachname}: internalEmail gefunden: ${mitarbeiterData.internalEmail}`);
            mitarbeiterInternalEmailMap.set(mitarbeiterData.internalEmail.toLowerCase(), {
              email: mitarbeiterData.email || "",
              internalEmail: mitarbeiterData.internalEmail,
              vorname: vorname,
              nachname: nachname,
            });
            
            // Speichere alle Mitarbeiter mit internalEmail
            allMitarbeiterWithInternalEmail.push({
              email: mitarbeiterData.email || "",
              internalEmail: mitarbeiterData.internalEmail,
              vorname: vorname,
              nachname: nachname,
            });
          }
        }
      });
      console.log(`✅ ${mitarbeiterEmailMap.size} Mitarbeiter in EmailMap, ${mitarbeiterInternalEmailMap.size} mit internalEmail`);
      console.log(`📋 Alle Mitarbeiter mit internalEmail:`, allMitarbeiterWithInternalEmail.map(m => `${m.vorname} ${m.nachname} (${m.internalEmail})`));
    } catch (mitarbeiterError) {
      console.warn("⚠️ Konnte schichtplanMitarbeiter nicht laden:", mitarbeiterError);
    }

    allUsers = [];
    const currentUserEmail = (userAuthData.email || "").toLowerCase();
    
    usersSnapshot.forEach((doc) => {
      const userData = doc.data();
      
      // Überspringe aktuellen Benutzer
      if (doc.id === userAuthData.uid) {
        return;
      }
      
      // Überspringe inaktive Benutzer (status: false)
      if (userData.status === false) {
        return;
      }
      
      // Verwende internalEmail (falls vorhanden), sonst email (Login-E-Mail)
      let email = userData.internalEmail || userData.email || "";
      let vorname = userData.vorname || "";
      let nachname = userData.nachname || "";
      let loginEmail = userData.email || ""; // Speichere Login-E-Mail separat
      
      // Fallback: Wenn keine internalEmail in users, suche in schichtplanMitarbeiter
      if (!userData.internalEmail) {
        // Versuche zuerst über Login-E-Mail
        if (userData.email) {
          const mitarbeiterInfo = mitarbeiterEmailMap.get(userData.email.toLowerCase());
          if (mitarbeiterInfo && mitarbeiterInfo.internalEmail) {
            console.log(`📧 Fallback (E-Mail): internalEmail aus schichtplanMitarbeiter für ${userData.email}: ${mitarbeiterInfo.internalEmail}`);
            email = mitarbeiterInfo.internalEmail;
            if (!vorname) vorname = mitarbeiterInfo.vorname;
            if (!nachname) nachname = mitarbeiterInfo.nachname;
          }
        }
        
        // Falls immer noch keine internalEmail, versuche über Name
        if (!email || email === loginEmail) {
          const userFullName = `${userData.vorname || ""} ${userData.nachname || ""}`.trim().toLowerCase();
          if (userFullName) {
            const mitarbeiterInfoByName = mitarbeiterNameMap.get(userFullName);
            if (mitarbeiterInfoByName && mitarbeiterInfoByName.internalEmail) {
              console.log(`📧 Fallback (Name): internalEmail aus schichtplanMitarbeiter für ${userFullName}: ${mitarbeiterInfoByName.internalEmail}`);
              email = mitarbeiterInfoByName.internalEmail;
              if (!vorname) vorname = mitarbeiterInfoByName.vorname;
              if (!nachname) nachname = mitarbeiterInfoByName.nachname;
            }
          }
        }
      }
      
      // Debug: Logge E-Mail-Informationen
      if (userData.internalEmail) {
        console.log(`📧 Benutzer ${userData.email}: internalEmail in users gefunden: ${userData.internalEmail}`);
      } else {
        console.log(`📧 Benutzer ${userData.email}: keine internalEmail in users`);
      }
      
      // 🔥 NEU: Für Gruppen können auch Mitarbeiter ohne interne E-Mail hinzugefügt werden
      // Verwende loginEmail als Fallback, wenn keine interne E-Mail vorhanden ist
      if (!email || email === loginEmail) {
        // Keine interne E-Mail gefunden - verwende loginEmail als Fallback für Gruppen
        email = loginEmail || "";
        // Wenn auch keine loginEmail vorhanden ist, überspringe
        if (!email) {
          return;
        }
      }
      
      // Überspringe, wenn interne E-Mail mit aktuellem Benutzer übereinstimmt
      if (email.toLowerCase() === currentUserEmail) {
        return;
      }
      
      const fullName = (vorname + " " + nachname).trim() || userData.name || email;
      
      allUsers.push({
        uid: doc.id,
        email: email, // Dies ist die interne E-Mail
        loginEmail: loginEmail, // Login-E-Mail separat speichern
        vorname: vorname,
        nachname: nachname,
        name: fullName,
      });
    });
    
    // Füge auch Mitarbeiter hinzu, die nur in schichtplanMitarbeiter existieren (mit internalEmail, aber ohne users-Eintrag)
    // ODER aktualisiere bestehende Einträge, wenn internalEmail in schichtplanMitarbeiter vorhanden ist, aber nicht in users
    allMitarbeiterWithInternalEmail.forEach((mitarbeiterInfo) => {
      if (!mitarbeiterInfo.internalEmail) return;
      const internalEmail = mitarbeiterInfo.internalEmail.toLowerCase();
      
      // Prüfe, ob es einen users-Eintrag mit dieser Login-E-Mail gibt
      const matchingUserDocByEmail = Array.from(usersSnapshot.docs).find(doc => {
        const userData = doc.data();
        return userData.email && userData.email.toLowerCase() === mitarbeiterInfo.email.toLowerCase();
      });
      
      // Prüfe auch über Name
      const mitarbeiterFullName = `${mitarbeiterInfo.vorname} ${mitarbeiterInfo.nachname}`.trim().toLowerCase();
      const matchingUserDocByName = Array.from(usersSnapshot.docs).find(doc => {
        const userData = doc.data();
        const userFullName = `${userData.vorname || ""} ${userData.nachname || ""}`.trim().toLowerCase();
        return userFullName === mitarbeiterFullName;
      });
      
      const matchingUserDoc = matchingUserDocByEmail || matchingUserDocByName;
      
      if (matchingUserDoc) {
        // User-Account existiert - prüfe, ob internalEmail aktualisiert werden muss
        const userIndex = allUsers.findIndex(u => u.uid === matchingUserDoc.id);
        if (userIndex !== -1) {
          if (allUsers[userIndex].email.toLowerCase() !== internalEmail) {
            // Aktualisiere E-Mail auf interne E-Mail
            console.log(`📧 Aktualisiere E-Mail für ${allUsers[userIndex].name}: ${allUsers[userIndex].email} -> ${mitarbeiterInfo.internalEmail}`);
            allUsers[userIndex].email = mitarbeiterInfo.internalEmail;
            allUsers[userIndex].loginEmail = mitarbeiterInfo.email || allUsers[userIndex].loginEmail;
          }
          // Aktualisiere auch Name, falls nicht vorhanden
          if (!allUsers[userIndex].vorname && mitarbeiterInfo.vorname) {
            allUsers[userIndex].vorname = mitarbeiterInfo.vorname;
            allUsers[userIndex].nachname = mitarbeiterInfo.nachname;
            allUsers[userIndex].name = `${mitarbeiterInfo.vorname} ${mitarbeiterInfo.nachname}`.trim();
          }
        } else {
          // User existiert in users, aber wurde noch nicht zu allUsers hinzugefügt (z.B. wegen fehlender E-Mail)
          console.log(`📧 Füge User hinzu, der in users existiert: ${mitarbeiterInfo.vorname} ${mitarbeiterInfo.nachname} (${mitarbeiterInfo.internalEmail})`);
          allUsers.push({
            uid: matchingUserDoc.id,
            email: mitarbeiterInfo.internalEmail,
            loginEmail: mitarbeiterInfo.email || "",
            vorname: mitarbeiterInfo.vorname,
            nachname: mitarbeiterInfo.nachname,
            name: `${mitarbeiterInfo.vorname} ${mitarbeiterInfo.nachname}`.trim() || mitarbeiterInfo.internalEmail,
          });
        }
      } else {
        // Kein User-Account vorhanden - prüfe, ob bereits hinzugefügt
        const alreadyAdded = allUsers.some(u => 
          u.email.toLowerCase() === internalEmail || 
          (u.loginEmail && u.loginEmail.toLowerCase() === mitarbeiterInfo.email.toLowerCase()) ||
          (u.vorname && u.nachname && `${u.vorname} ${u.nachname}`.trim().toLowerCase() === mitarbeiterFullName)
        );
        
        if (!alreadyAdded && internalEmail !== currentUserEmail && mitarbeiterInfo.internalEmail) {
          // Nur hinzufügen, wenn interne E-Mail vorhanden ist
          console.log(`📧 Füge Mitarbeiter ohne User-Account hinzu: ${mitarbeiterInfo.vorname} ${mitarbeiterInfo.nachname} (${mitarbeiterInfo.internalEmail})`);
          allUsers.push({
            uid: null, // Kein User-Account vorhanden
            email: mitarbeiterInfo.internalEmail,
            loginEmail: mitarbeiterInfo.email || "",
            vorname: mitarbeiterInfo.vorname,
            nachname: mitarbeiterInfo.nachname,
            name: `${mitarbeiterInfo.vorname} ${mitarbeiterInfo.nachname}`.trim() || mitarbeiterInfo.internalEmail,
          });
        }
      }
    });

    // Sortiere nach Nachname, dann Vorname
    allUsers.sort((a, b) => {
      const nachnameCompare = (a.nachname || "").localeCompare(b.nachname || "", "de");
      if (nachnameCompare !== 0) return nachnameCompare;
      return (a.vorname || "").localeCompare(b.vorname || "", "de");
    });

    console.log(`✅ ${allUsers.length} Benutzer für E-Mail-Versand geladen (alle Rollen)`);
    if (allUsers.length > 0) {
      console.log("📋 Beispiel-Benutzer:", allUsers.slice(0, 5).map(u => {
        const emailInfo = u.email !== u.loginEmail ? `${u.email} (Login: ${u.loginEmail})` : u.email;
        return `${u.name} (${emailInfo})`;
      }));
    } else {
      console.warn("⚠️ Keine Benutzer mit E-Mail-Adresse gefunden!");
      console.warn("💡 Tipp: Jeder Benutzer benötigt eine E-Mail-Adresse in seinem Benutzerdokument (kunden/{companyId}/users/{uid})");
    }

    // Fülle Empfänger-Dropdown
    populateRecipientSelect();
  } catch (error) {
    console.error("Fehler beim Laden der Benutzer:", error);
    allUsers = [];
  }
}

function populateRecipientSelect() {
  // Wird nicht mehr benötigt, da wir jetzt ein Input-Feld verwenden
  // Funktion bleibt für Kompatibilität, macht aber nichts mehr
  return;
}
// ---------------------------------------------------------
// Mitarbeiter-Auswahl Modal
// ---------------------------------------------------------

function openMitarbeiterModal() {
  if (selectMitarbeiterModal && selectMitarbeiterForm) {
    selectedMitarbeiter = [];
    selectMitarbeiterModal.style.display = "block";
    selectMitarbeiterForm.style.display = "block";
    if (mitarbeiterSearch) mitarbeiterSearch.value = "";
    fillMitarbeiterSelect();
  }
}

function closeMitarbeiterModal() {
  if (selectMitarbeiterModal && selectMitarbeiterForm) {
    selectMitarbeiterModal.style.display = "none";
    selectMitarbeiterForm.style.display = "none";
    selectedMitarbeiter = [];
    if (mitarbeiterSearch) mitarbeiterSearch.value = "";
    if (mitarbeiterSelect) mitarbeiterSelect.value = "";
  }
}

function fillMitarbeiterSelect() {
  if (!mitarbeiterSelect && !mitarbeiterList) return;
  
  const isMobile = window.innerWidth <= 768;
  
  // Desktop: Select-Dropdown
  if (mitarbeiterSelect && !isMobile) {
    mitarbeiterSelect.innerHTML = '<option value="">-- Bitte auswählen --</option>';
    allUsers.forEach(user => {
      // Debug: Logge E-Mail-Informationen beim Füllen des Dropdowns
      if (user.loginEmail && user.email !== user.loginEmail) {
        console.log(`📧 Dropdown: ${user.name} - Interne E-Mail: ${user.email}, Login: ${user.loginEmail}`);
      }
      
      const option = document.createElement("option");
      // Verwende Index als Wert, da uid null sein kann
      option.value = allUsers.indexOf(user).toString();
      option.textContent = user.name;
      option.dataset.uid = user.uid || "";
      mitarbeiterSelect.appendChild(option);
    });
    mitarbeiterSelect.style.display = "block";
    if (mitarbeiterList) mitarbeiterList.style.display = "none";
  }
  
  // Mobile: Liste
  if (mitarbeiterList && isMobile) {
    renderMitarbeiterList();
    mitarbeiterList.style.display = "block";
    if (mitarbeiterSelect) mitarbeiterSelect.style.display = "none";
  }
}

function renderMitarbeiterList(searchTerm = "") {
  if (!mitarbeiterList) return;

  const term = searchTerm.toLowerCase().trim();
  const filtered = allUsers.filter(user => {
    if (term.length === 0) return true;
    const searchable = `${user.vorname} ${user.nachname} ${user.email}`.toLowerCase();
    return searchable.includes(term);
  });

  if (filtered.length === 0) {
    mitarbeiterList.innerHTML = '<div class="empty-state" style="padding: 40px; text-align: center; color: #64748b;">Keine Mitarbeiter gefunden</div>';
    return;
  }

  mitarbeiterList.innerHTML = "";
  filtered.forEach(user => {
    // Debug: Logge E-Mail-Informationen beim Rendern
    if (user.loginEmail && user.email !== user.loginEmail) {
      console.log(`📧 Rendere: ${user.name} - Interne E-Mail: ${user.email}, Login: ${user.loginEmail}`);
    }
    
    const item = document.createElement("div");
    item.className = "personnel-mitarbeiter-list-item";
    // Prüfe ob bereits ausgewählt (vergleiche über Index, da uid null sein kann)
    const userIndex = allUsers.indexOf(user);
    const isSelected = selectedMitarbeiter.some(m => allUsers.indexOf(m) === userIndex);
    if (isSelected) {
      item.classList.add("selected");
    }

    item.innerHTML = `
      <input type="checkbox" data-uid="${user.uid || ''}" data-index="${allUsers.indexOf(user)}" ${isSelected ? "checked" : ""}>
      <div class="personnel-mitarbeiter-list-item-info">
        <div class="personnel-mitarbeiter-list-item-name">${escapeHtml(user.name)}</div>
      </div>
    `;

    const checkbox = item.querySelector("input[type='checkbox']");
    checkbox.addEventListener("change", (e) => {
      if (e.target.checked) {
        // Prüfe ob bereits vorhanden (vergleiche über Index, da uid null sein kann)
        const userIndex = allUsers.indexOf(user);
        if (!selectedMitarbeiter.some(m => allUsers.indexOf(m) === userIndex)) {
          selectedMitarbeiter.push(user);
        }
        item.classList.add("selected");
      } else {
        // Entferne über Index
        const userIndex = allUsers.indexOf(user);
        selectedMitarbeiter = selectedMitarbeiter.filter(m => allUsers.indexOf(m) !== userIndex);
        item.classList.remove("selected");
      }
    });

    // Auch Klick auf Item selbst
    item.addEventListener("click", (e) => {
      if (e.target.type !== "checkbox") {
        checkbox.checked = !checkbox.checked;
        checkbox.dispatchEvent(new Event("change"));
      }
    });

    mitarbeiterList.appendChild(item);
  });
}

function filterMitarbeiterList(searchTerm) {
  const isMobile = window.innerWidth <= 768;
  
  if (isMobile) {
    // Mobile: Filtere Liste
    renderMitarbeiterList(searchTerm);
  } else {
    // Desktop: Filtere Select
    if (mitarbeiterSelect) {
      const term = searchTerm.toLowerCase().trim();
      const options = mitarbeiterSelect.querySelectorAll("option");
      options.forEach(option => {
        if (option.value === "") {
          option.style.display = "block";
          return;
        }
        const text = option.textContent.toLowerCase();
        option.style.display = term.length === 0 || text.includes(term) ? "block" : "none";
      });
    }
  }
}

function confirmMitarbeiterSelection() {
  // Prüfe ob ein Mitarbeiter ausgewählt wurde (Desktop: Select, Mobile: Checkboxen)
  const isMobile = window.innerWidth <= 768;
  let selected = [];
  
  if (isMobile) {
    // Mobile: Aus Checkboxen
    selected = [...selectedMitarbeiter]; // Kopie erstellen
  } else {
    // Desktop: Aus Select
    const selectedIndex = mitarbeiterSelect?.value;
    if (selectedIndex !== undefined && selectedIndex !== "" && selectedIndex !== null) {
      const index = parseInt(selectedIndex);
      if (index >= 0 && index < allUsers.length) {
        const user = allUsers[index];
        if (user) {
          selected = [user];
        }
      }
    }
  }
  
  if (selected.length === 0) {
    alert("Bitte wählen Sie mindestens einen Mitarbeiter aus.");
    return;
  }

  // Füge ausgewählte Mitarbeiter zum Empfänger-Feld hinzu
  const currentRecipients = recipientInput.value.trim();
  const newRecipients = selected.map(m => m.name).join("; ");
  
  if (currentRecipients) {
    recipientInput.value = currentRecipients + "; " + newRecipients;
  } else {
    recipientInput.value = newRecipients;
  }

  closeMitarbeiterModal();
  console.log(`✅ ${selected.length} Mitarbeiter ausgewählt`);
}

// ---------------------------------------------------------
// E-Mails laden
// ---------------------------------------------------------

async function loadEmails() {
  await loadInbox();
  await loadSent();
  await loadDrafts();
  await loadTrash();
}

async function loadInbox() {
  try {
    const companyId = getCompanyId();
    const userId = getUserId();
    const emailsRef = collection(db, "kunden", companyId, "emails");

    // Lade E-Mails, bei denen der aktuelle Benutzer der Empfänger ist
    // Ohne orderBy (um Index zu vermeiden), sortiere client-seitig
    const q = query(
      emailsRef,
      where("to", "==", userId)
    );

    const snapshot = await getDocs(q);
    
    console.log(`📧 loadInbox: Query für userId=${userId}, gefunden: ${snapshot.size} E-Mails`);
    
    // Filtere client-seitig: Nicht gelöscht und keine Entwürfe
    let filtered = snapshot.docs.filter(doc => {
      const data = doc.data();
      const isValid = data.deleted !== true && data.draft !== true;
      if (!isValid) {
        console.log(`📧 E-Mail ${doc.id} gefiltert: deleted=${data.deleted}, draft=${data.draft}`);
      }
      return isValid;
    });
    
    console.log(`📧 loadInbox: Nach Filterung: ${filtered.length} E-Mails`);
    
    // Sortiere client-seitig nach createdAt (neueste zuerst)
    filtered.sort((a, b) => {
      const aData = a.data();
      const bData = b.data();
      
      // Verwende createdAt (Empfangsdatum) für Posteingang
      let aDate = aData.createdAt?.toDate?.();
      let bDate = bData.createdAt?.toDate?.();
      
      // Fallback: Wenn createdAt nicht verfügbar, verwende Timestamp
      if (!aDate && aData.createdAt) {
        aDate = aData.createdAt instanceof Date ? aData.createdAt : new Date(aData.createdAt);
      }
      if (!bDate && bData.createdAt) {
        bDate = bData.createdAt instanceof Date ? bData.createdAt : new Date(bData.createdAt);
      }
      
      // Fallback: Wenn immer noch kein Datum, verwende 0
      aDate = aDate || new Date(0);
      bDate = bDate || new Date(0);
      
      // Sortiere absteigend (neueste zuerst)
      return bDate.getTime() - aDate.getTime();
    });
    
    renderEmailList({ docs: filtered, empty: filtered.length === 0 }, inboxList, "inbox");
  } catch (error) {
    console.error("Fehler beim Laden des Posteingangs:", error);
    inboxList.innerHTML = '<div class="empty-state">Fehler beim Laden der Nachrichten.</div>';
  }
}

async function loadSent() {
  try {
    const companyId = getCompanyId();
    const userId = getUserId();
    const emailsRef = collection(db, "kunden", companyId, "emails");

    // Lade E-Mails, bei denen der aktuelle Benutzer der Absender ist
    // Ohne orderBy (um Index zu vermeiden), sortiere client-seitig
    const q = query(
      emailsRef,
      where("from", "==", userId)
    );

    const snapshot = await getDocs(q);
    
    // Filtere client-seitig: Nicht gelöscht und keine Entwürfe
    let filtered = snapshot.docs.filter(doc => {
      const data = doc.data();
      if (data.deleted === true || data.draft === true) return false;
      
      // 🔥 NEU: Bei Gruppen-E-Mails: Zeige nur die E-Mail mit recipients (für "Gesendet")
      // Verstecke die einzelnen Empfänger-E-Mails (die haben to: member.uid)
      if (data.isGroupEmail === true && data.groupId && data.groupName) {
        // Bei Gruppen-E-Mails: Zeige nur, wenn to === null/undefined UND recipients vorhanden ist
        // Verstecke alle E-Mails mit to !== null/undefined (die einzelnen Empfänger-E-Mails)
        const hasTo = data.to !== null && data.to !== undefined;
        const hasRecipients = data.recipients && Array.isArray(data.recipients) && data.recipients.length > 0;
        
        if (hasTo) {
          // Hat einen Empfänger (to: member.uid) → Verstecke (ist eine Empfänger-E-Mail)
          return false;
        }
        
        if (!hasRecipients) {
          // Keine recipients → Verstecke (alte E-Mail ohne recipients)
          return false;
        }
        
        // Zeige nur, wenn to === null/undefined UND recipients vorhanden ist (die "Gesendet"-E-Mail)
      }
      
      return true;
    });
    
    // Sortiere client-seitig nach createdAt (neueste zuerst)
    filtered.sort((a, b) => {
      const aData = a.data();
      const bData = b.data();
      
      // Verwende createdAt (Versanddatum) für Gesendet
      let aDate = aData.createdAt?.toDate?.();
      let bDate = bData.createdAt?.toDate?.();
      
      // Fallback: Wenn createdAt nicht verfügbar, verwende Timestamp
      if (!aDate && aData.createdAt) {
        aDate = aData.createdAt instanceof Date ? aData.createdAt : new Date(aData.createdAt);
      }
      if (!bDate && bData.createdAt) {
        bDate = bData.createdAt instanceof Date ? bData.createdAt : new Date(bData.createdAt);
      }
      
      // Fallback: Wenn immer noch kein Datum, verwende 0
      aDate = aDate || new Date(0);
      bDate = bDate || new Date(0);
      
      // Sortiere absteigend (neueste zuerst)
      return bDate.getTime() - aDate.getTime();
    });
    
    renderEmailList({ docs: filtered, empty: filtered.length === 0 }, sentList, "sent");
  } catch (error) {
    console.error("Fehler beim Laden des Gesendet-Ordners:", error);
    sentList.innerHTML = '<div class="empty-state">Fehler beim Laden der Nachrichten.</div>';
  }
}

async function loadDrafts() {
  try {
    const companyId = getCompanyId();
    const userId = getUserId();
    const emailsRef = collection(db, "kunden", companyId, "emails");

    // Lade Entwürfe des aktuellen Benutzers
    // Ohne orderBy (um Index zu vermeiden), sortiere client-seitig
    const q = query(
      emailsRef,
      where("from", "==", userId),
      where("draft", "==", true)
    );

    const snapshot = await getDocs(q);
    
    // Filtere client-seitig: Nicht gelöscht
    let filtered = snapshot.docs.filter(doc => {
      const data = doc.data();
      return data.deleted !== true;
    });
    
    // Sortiere client-seitig nach updatedAt (neueste zuerst)
    filtered.sort((a, b) => {
      const aData = a.data();
      const bData = b.data();
      
      // Verwende updatedAt (letzte Änderung) für Entwürfe, Fallback auf createdAt
      let aDate = aData.updatedAt?.toDate?.() || aData.createdAt?.toDate?.();
      let bDate = bData.updatedAt?.toDate?.() || bData.createdAt?.toDate?.();
      
      // Fallback: Wenn Timestamp nicht verfügbar, verwende direktes Datum
      if (!aDate && aData.updatedAt) {
        aDate = aData.updatedAt instanceof Date ? aData.updatedAt : new Date(aData.updatedAt);
      }
      if (!aDate && aData.createdAt) {
        aDate = aData.createdAt instanceof Date ? aData.createdAt : new Date(aData.createdAt);
      }
      if (!bDate && bData.updatedAt) {
        bDate = bData.updatedAt instanceof Date ? bData.updatedAt : new Date(bData.updatedAt);
      }
      if (!bDate && bData.createdAt) {
        bDate = bData.createdAt instanceof Date ? bData.createdAt : new Date(bData.createdAt);
      }
      
      // Fallback: Wenn immer noch kein Datum, verwende 0
      aDate = aDate || new Date(0);
      bDate = bDate || new Date(0);
      
      // Sortiere absteigend (neueste zuerst)
      return bDate.getTime() - aDate.getTime();
    });
    
    renderEmailList({ docs: filtered, empty: filtered.length === 0 }, draftsList, "drafts");
  } catch (error) {
    console.error("Fehler beim Laden der Entwürfe:", error);
    draftsList.innerHTML = '<div class="empty-state">Fehler beim Laden der Entwürfe.</div>';
  }
}

async function loadTrash() {
  try {
    const companyId = getCompanyId();
    const userId = getUserId();
    const emailsRef = collection(db, "kunden", companyId, "emails");

    // Lade gelöschte E-Mails (vom oder an den aktuellen Benutzer)
    // Lade ohne orderBy (Index könnte fehlen), sortiere client-seitig
    const q = query(
      emailsRef,
      where("deleted", "==", true)
    );

    const snapshot = await getDocs(q);
    
    // Filtere nur E-Mails, die dem Benutzer gehören
    let filtered = snapshot.docs.filter(doc => {
      const data = doc.data();
      return data.from === userId || data.to === userId;
    });
    
    // Sortiere client-seitig nach createdAt (Erstellungs-/Versanddatum, nicht Löschdatum)
    // Die neuesten E-Mails (nach Erstellungsdatum) sollen oben stehen
    filtered.sort((a, b) => {
      const aData = a.data();
      const bData = b.data();
      
      // Verwende createdAt (Erstellungs-/Versanddatum) für Papierkorb
      // NICHT deletedAt (Löschdatum) - wir sortieren nach dem ursprünglichen Datum der E-Mail
      let aDate = null;
      let bDate = null;
      
      // Verwende createdAt (Erstellungs-/Versanddatum)
      if (aData.createdAt) {
        aDate = aData.createdAt?.toDate?.();
        if (!aDate && aData.createdAt instanceof Date) {
          aDate = aData.createdAt;
        } else if (!aDate && typeof aData.createdAt === 'object' && aData.createdAt.seconds) {
          aDate = new Date(aData.createdAt.seconds * 1000);
        } else if (!aDate) {
          aDate = new Date(aData.createdAt);
        }
      }
      
      // Gleiches für b
      if (bData.createdAt) {
        bDate = bData.createdAt?.toDate?.();
        if (!bDate && bData.createdAt instanceof Date) {
          bDate = bData.createdAt;
        } else if (!bDate && typeof bData.createdAt === 'object' && bData.createdAt.seconds) {
          bDate = new Date(bData.createdAt.seconds * 1000);
        } else if (!bDate) {
          bDate = new Date(bData.createdAt);
        }
      }
      
      // Fallback: Wenn immer noch kein Datum, verwende 0
      aDate = aDate || new Date(0);
      bDate = bDate || new Date(0);
      
      // Sortiere absteigend (neueste zuerst) - größere Timestamp-Werte = neuer
      const result = bDate.getTime() - aDate.getTime();
      return result;
    });
    
    console.log(`📧 Papierkorb: ${filtered.length} E-Mails sortiert nach Erstellungsdatum (neueste zuerst)`);
    
    renderEmailList({ docs: filtered, empty: filtered.length === 0 }, trashList, "trash");
  } catch (error) {
    console.error("Fehler beim Laden des Papierkorbs:", error);
    trashList.innerHTML = '<div class="empty-state">Fehler beim Laden der Nachrichten.</div>';
  }
}

function renderEmailList(snapshot, container, type) {
  if (!container) return;

  // Unterstütze sowohl QuerySnapshot als auch manuell erstellte Objekte
  const docs = snapshot.docs || (snapshot.forEach ? Array.from(snapshot) : []);
  const isEmpty = snapshot.empty !== undefined ? snapshot.empty : (docs.length === 0);

  if (isEmpty) {
    container.innerHTML = `
      <div class="empty-state">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"></path>
          <polyline points="22,6 12,13 2,6"></polyline>
        </svg>
        <p>Keine Nachrichten vorhanden</p>
      </div>
    `;
    return;
  }

  container.innerHTML = "";
  docs.forEach((doc) => {
    const email = doc.data();
    // 🔥 WICHTIG: Füge die ID zu den E-Mail-Daten hinzu, damit editDraft() sie verwenden kann
    email.id = doc.id;
    const emailItem = createEmailItem(doc.id, email, type);
    if (emailItem) {
      container.appendChild(emailItem);
    }
  });
  
  // Debug: Prüfe ob Icons im DOM sind (nur bei inbox)
  if (type === "inbox") {
    const actionButtons = container.querySelectorAll('.email-action-btn');
    console.log(`📧 Gefundene Action-Buttons im Posteingang: ${actionButtons.length}`);
    if (actionButtons.length === 0) {
      console.warn(`⚠️ KEINE ACTION-BUTTONS GEFUNDEN! Prüfe createEmailItem Funktion.`);
    }
  }
}

function createEmailItem(emailId, email, type) {
  const item = document.createElement("div");
  item.className = "email-item";
  if (type === "inbox" && !email.read) {
    item.classList.add("unread");
  }

  // Finde Benutzer-Informationen
  let otherUserId, otherUser;
  if (type === "inbox") {
    otherUserId = email.from;
    otherUser = allUsers.find((u) => u.uid === otherUserId) || {
      name: email.fromName || email.fromEmail || "Unbekannt",
      email: email.fromEmail || "",
    };
  } else if (type === "sent") {
    // 🔥 NEU: Bei Gruppen-E-Mails in "Gesendet" zeige Gruppenname statt einzelnen Empfänger
    if (email.isGroupEmail && email.groupName) {
      otherUser = {
        name: `[Gruppe: ${email.groupName}]`,
        email: email.groupName,
      };
    } else {
      otherUserId = email.to;
      otherUser = allUsers.find((u) => u.uid === otherUserId) || {
        name: email.toName || email.toEmail || "Unbekannt",
        email: email.toEmail || "",
      };
    }
  } else if (type === "drafts") {
    otherUserId = email.to;
    otherUser = allUsers.find((u) => u.uid === otherUserId) || {
      name: email.toName || "Kein Empfänger",
      email: email.toEmail || "",
    };
  } else if (type === "trash") {
    const isFromMe = email.from === getUserId();
    otherUserId = isFromMe ? email.to : email.from;
    otherUser = allUsers.find((u) => u.uid === otherUserId) || {
      name: isFromMe ? (email.toName || email.toEmail || "Unbekannt") : (email.fromName || email.fromEmail || "Unbekannt"),
      email: isFromMe ? (email.toEmail || "") : (email.fromEmail || ""),
    };
  }

  const date = email.updatedAt?.toDate?.() || email.createdAt?.toDate?.() || new Date(email.createdAt || email.updatedAt);
  const dateStr = formatDate(date);

  // 🔥 NEU: Icons für Posteingang, Gesendet und Entwürfe
  let actionIcons = "";
  
  // Prüfe explizit ob type "inbox" ist (mit String-Vergleich)
  if (String(type) === "inbox") {
    // Antwort-Icon (Pfeil nach links mit U-Kurve - wie im Bild beschrieben)
    const replyIcon = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M9 10l-5 5 5 5"></path><path d="M20 4v7a4 4 0 0 1-4 4H4"></path></svg>`;
    // Löschen-Icon (Papierkorb)
    const deleteIcon = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path><line x1="10" y1="11" x2="10" y2="17"></line><line x1="14" y1="11" x2="14" y2="17"></line></svg>`;
    
    actionIcons = `<div class="email-item-actions">
        <button class="email-action-btn" data-action="reply" data-email-id="${emailId}" title="Antworten" type="button">${replyIcon}</button>
        <button class="email-action-btn" data-action="delete" data-email-id="${emailId}" title="Löschen" type="button">${deleteIcon}</button>
      </div>`;
  } else if (String(type) === "sent") {
    // 🔥 NEU: Nur Löschen-Icon für Gesendet (in Papierkorb verschieben)
    const deleteIcon = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path><line x1="10" y1="11" x2="10" y2="17"></line><line x1="14" y1="11" x2="14" y2="17"></line></svg>`;
    
    actionIcons = `<div class="email-item-actions">
        <button class="email-action-btn" data-action="delete" data-email-id="${emailId}" title="In Papierkorb verschieben" type="button">${deleteIcon}</button>
      </div>`;
  } else if (String(type) === "drafts") {
    // 🔥 NEU: Nur Löschen-Icon für Entwürfe (in Papierkorb verschieben)
    const deleteIcon = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path><line x1="10" y1="11" x2="10" y2="17"></line><line x1="14" y1="11" x2="14" y2="17"></line></svg>`;
    
    actionIcons = `<div class="email-item-actions">
        <button class="email-action-btn" data-action="delete" data-email-id="${emailId}" title="In Papierkorb verschieben" type="button">${deleteIcon}</button>
      </div>`;
  } else if (String(type) === "trash") {
    // 🔥 NEU: Endgültig löschen-Icon für Papierkorb (mit Warnung)
    const permanentDeleteIcon = `<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polyline points="3 6 5 6 21 6"></polyline><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"></path><line x1="10" y1="11" x2="10" y2="17"></line><line x1="14" y1="11" x2="14" y2="17"></line></svg>`;
    
    actionIcons = `<div class="email-item-actions">
        <button class="email-action-btn" data-action="permanent-delete" data-email-id="${emailId}" title="Endgültig löschen" type="button" style="color: #ef4444;">${permanentDeleteIcon}</button>
      </div>`;
  }

  // Erstelle HTML-String
  const htmlString = `
    <div class="email-item-left">
      <div class="email-item-sender">${escapeHtml(otherUser.name)}</div>
      <div class="email-item-subject">${escapeHtml(email.subject || "(Kein Betreff)")}</div>
      <div class="email-item-preview">${escapeHtml(email.body?.substring(0, 100) || "")}${email.body?.length > 100 ? "..." : ""}</div>
    </div>
    <div class="email-item-right">
      <div class="email-item-date-row">
        <span class="email-item-date">${dateStr}</span>
        ${actionIcons}
      </div>
      ${type === "inbox" && !email.read ? '<div class="email-item-badge">Neu</div>' : ""}
      ${type === "drafts" ? '<div class="email-item-badge" style="background-color: #f59e0b;">Entwurf</div>' : ""}
    </div>
  `;
  
  // Debug: Prüfe ob actionIcons im HTML-String ist
  if (String(type) === "inbox") {
    console.log(`🔍 HTML-String für E-Mail ${emailId}:`);
    console.log(`🔍 Enthält 'email-item-actions': ${htmlString.includes('email-item-actions')}`);
    console.log(`🔍 Enthält 'email-action-btn': ${htmlString.includes('email-action-btn')}`);
    console.log(`🔍 actionIcons Wert (erste 100 Zeichen): "${actionIcons.substring(0, 100)}"`);
  }
  
  item.innerHTML = htmlString;

  if (type === "drafts") {
    item.addEventListener("click", () => editDraft(emailId, email));
  } else {
    item.addEventListener("click", () => viewEmail(emailId, email, type));
  }

  // 🔥 NEU: Event Listener für Action-Buttons (inbox, sent, drafts und trash)
  if (String(type) === "inbox" || String(type) === "sent" || String(type) === "drafts" || String(type) === "trash") {
    // Warte kurz, damit das HTML gerendert ist
    setTimeout(() => {
      const replyBtn = item.querySelector('[data-action="reply"]');
      const deleteBtn = item.querySelector('[data-action="delete"]');
      const permanentDeleteBtn = item.querySelector('[data-action="permanent-delete"]');
      
      if (replyBtn) {
        replyBtn.addEventListener("click", (e) => {
          e.stopPropagation(); // Verhindere, dass das Klicken auf die E-Mail ausgelöst wird
          handleQuickReply(emailId, email);
        });
      }
      
      if (deleteBtn) {
        deleteBtn.addEventListener("click", (e) => {
          e.stopPropagation(); // Verhindere, dass das Klicken auf die E-Mail ausgelöst wird
          handleQuickDelete(emailId, email);
        });
      }
      
      if (permanentDeleteBtn) {
        permanentDeleteBtn.addEventListener("click", (e) => {
          e.stopPropagation(); // Verhindere, dass das Klicken auf die E-Mail ausgelöst wird
          handleQuickPermanentDelete(emailId, email);
        });
      }
    }, 0);
  }

  return item;
}

// ---------------------------------------------------------
// E-Mail verfassen
// ---------------------------------------------------------

async function openComposeModal(draftData = null) {
  if (composeModal) {
    // 🔥 WICHTIG: Stelle sicher, dass Gruppen geladen sind (für Antworten an Gruppen)
    if (allGroups.length === 0) {
      await loadGroups();
    }
    
    composeModal.style.display = "flex";
    composeForm?.reset();
    composeMessage.style.display = "none";
    // 🔥 WICHTIG: Setze currentDraftId nur, wenn es noch nicht gesetzt ist (z.B. bei editDraft)
    // Wenn currentDraftId bereits gesetzt ist (von editDraft), behalte es bei
    if (draftData?.id && currentDraftId === null) {
      currentDraftId = draftData.id;
    } else if (draftData?.id) {
      // Wenn beide gesetzt sind, verwende die ID aus draftData (sollte identisch sein)
      currentDraftId = draftData.id;
    }
    console.log(`📧 openComposeModal: currentDraftId=${currentDraftId}, draftData.id=${draftData?.id}`);

    // Reset Empfänger-Feld
    if (recipientInput) {
      recipientInput.value = "";
      
      // 🔥 NEU: Setze Placeholder basierend auf vorhandener interner E-Mail-Adresse
      // Jeder kann externe E-Mails senden, wenn eine interne E-Mail-Adresse vorhanden ist
      // Lade interne E-Mail-Adresse (vereinfacht, da sie bereits in userAuthData sein sollte)
      const hasInternalEmail = !!userAuthData?.internalEmail;
      
      if (hasInternalEmail) {
        recipientInput.placeholder = "Empfänger auswählen oder externe E-Mail-Adresse eingeben (mehrere mit ; trennen)";
      } else {
        recipientInput.placeholder = "Empfänger auswählen (nur interne E-Mails möglich - keine interne E-Mail-Adresse vorhanden)";
      }
    }
    // recipientSelect wurde entfernt, nicht mehr benötigt

    // Wenn Entwurf, fülle Formular
    if (draftData) {
      // Finde Empfänger-Namen für Anzeige
      if (draftData.to) {
        const recipient = allUsers.find(u => u.uid === draftData.to);
        if (recipient && recipientInput) {
          recipientInput.value = recipient.name;
          // recipientSelect wurde entfernt, nicht mehr benötigt
        }
      }
      document.getElementById("emailSubject").value = draftData.subject || "";
      // Lade Inhalt in Quill Editor
      if (quillEditor) {
        quillEditor.root.innerHTML = draftData.body || "";
        syncEditorToTextarea();
      }
    } else {
      // Leere den Editor beim Öffnen eines neuen Modals
      if (quillEditor) {
        quillEditor.setContents([]);
        syncEditorToTextarea();
      }
    }

    // Auto-Save Event Listener (Quill hat bereits text-change Event)
    setupAutoSave();
    
    console.log(`📧 Compose Modal geöffnet. ${allUsers.length} Mitarbeiter verfügbar.`);
  }
}

function setupAutoSave() {
  // Entferne alte Listener
  const subjectInput = document.getElementById("emailSubject");
  
  // Neue Event Listener
  if (subjectInput) {
    subjectInput.addEventListener("input", debounceAutoSave);
  }
  // Quill Editor hat bereits text-change Event, das in initializeRichTextEditor gesetzt wird
  // Zusätzlich können wir hier auch ein Event setzen, falls nötig
  if (quillEditor) {
    quillEditor.on('text-change', debounceAutoSave);
  }
  if (recipientInput) {
    recipientInput.addEventListener("input", debounceAutoSave);
  }
}

function debounceAutoSave() {
  clearTimeout(autoSaveTimer);
  autoSaveTimer = setTimeout(() => {
    saveDraft();
  }, 2000); // Speichere nach 2 Sekunden Inaktivität
}

async function saveDraft() {
  // 🔥 WICHTIG: Wenn die E-Mail gerade versendet wird, sollte saveDraft() NICHT aufgerufen werden
  if (isSendingEmail) {
    console.log("📧 saveDraft() übersprungen - E-Mail wird gerade versendet");
    return;
  }
  
  // 🔥 WICHTIG: Wenn currentDraftId null ist und das Modal geschlossen ist, sollte saveDraft() NICHT aufgerufen werden
  if (currentDraftId === null && composeModal && composeModal.style.display === "none") {
    console.log("📧 saveDraft() übersprungen - E-Mail wurde bereits versendet oder Modal ist geschlossen");
    return;
  }

  // Synchronisiere Editor-Inhalt mit Textarea
  syncEditorToTextarea();

  const recipientInputValue = recipientInput?.value.trim() || "";
  const subject = document.getElementById("emailSubject").value.trim();
  // Hole Inhalt aus Quill Editor (mit HTML-Formatierung)
  const body = quillEditor ? quillEditor.root.innerHTML.trim() : (emailBodyHidden?.value.trim() || "");

  // Nur speichern, wenn mindestens ein Feld ausgefüllt ist
  if (!subject && !body && !recipientInputValue) {
    return;
  }

  // Parse Empfänger (nur erster Empfänger für Entwurf)
  const recipientNames = recipientInputValue.split(";").map(n => n.trim()).filter(n => n.length > 0);
  const firstRecipient = recipientNames.length > 0 ? allUsers.find(u => u.name === recipientNames[0] || u.email === recipientNames[0]) : null;

  try {
    const companyId = getCompanyId();
    const userId = getUserId();
    const emailsRef = collection(db, "kunden", companyId, "emails");

    const draftData = {
      from: userId,
      fromEmail: userAuthData.email || "",
      fromName: userAuthData.name || userAuthData.email || "Unbekannt",
      to: firstRecipient?.uid || "",
      toEmail: firstRecipient?.email || "",
      toName: firstRecipient?.name || "",
      subject: subject || "",
      body: body || "",
      draft: true,
      deleted: false,
      updatedAt: serverTimestamp(),
    };

    if (currentDraftId) {
      // Update bestehenden Entwurf
      const draftRef = doc(db, "kunden", companyId, "emails", currentDraftId);
      await setDoc(draftRef, draftData, { merge: true });
    } else {
      // Erstelle neuen Entwurf
      const newDraft = await addDoc(emailsRef, {
        ...draftData,
        createdAt: serverTimestamp(),
      });
      currentDraftId = newDraft.id;
    }

    console.log("✅ Entwurf gespeichert");
  } catch (error) {
    console.error("Fehler beim Speichern des Entwurfs:", error);
  }
}

function closeComposeModal() {
  // 🔥 WICHTIG: Speichere Entwurf nur, wenn die E-Mail NICHT gerade versendet wird
  if (!isSendingEmail) {
    saveDraft();
  } else {
    console.log("📧 closeComposeModal: saveDraft() übersprungen - E-Mail wird gerade versendet");
  }
  
  // Entferne Click-Outside-Handler
  if (composeModal && composeModal._clickOutsideHandler) {
    document.removeEventListener("click", composeModal._clickOutsideHandler, true);
    delete composeModal._clickOutsideHandler;
  }
  
  if (composeModal) {
    composeModal.style.display = "none";
    composeForm?.reset();
    composeMessage.style.display = "none";
    currentDraftId = null;
    clearTimeout(autoSaveTimer);
    // 🔥 WICHTIG: Setze Flagge zurück, wenn Modal geschlossen wird (falls nicht bereits zurückgesetzt)
    if (isSendingEmail) {
      isSendingEmail = false;
    }
    // Reset Quill Editor
    if (quillEditor) {
      quillEditor.setContents([]);
      // Setze Arial als Standard-Schriftart
      quillEditor.format('font', 'arial');
      syncEditorToTextarea();
    }
    
    // Reset Anhänge
    emailAttachments = [];
    renderAttachments();
  }
}

// Hilfsfunktion: Prüft ob ein String eine gültige E-Mail-Adresse ist
function isValidEmail(email) {
  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  return emailRegex.test(email);
}

async function handleComposeSubmit(e) {
  e.preventDefault();
  console.log("📧 handleComposeSubmit aufgerufen");
  console.log(`📧 currentDraftId beim Versenden: ${currentDraftId}`);

  // 🔥 WICHTIG: Setze Flagge, dass E-Mail versendet wird (verhindert saveDraft())
  isSendingEmail = true;
  
  // 🔥 WICHTIG: Stoppe Auto-Save, damit saveDraft() nicht mehr aufgerufen wird
  clearTimeout(autoSaveTimer);
  autoSaveTimer = null;

  // Synchronisiere Editor-Inhalt mit Textarea vor dem Versenden
  syncEditorToTextarea();

  const recipientInputValue = recipientInput?.value.trim() || "";
  const subject = document.getElementById("emailSubject").value.trim();
  // Hole Inhalt aus Quill Editor (mit HTML-Formatierung)
  const body = quillEditor ? quillEditor.root.innerHTML.trim() : (emailBodyHidden?.value.trim() || "");

  console.log("📧 Empfänger:", recipientInputValue);
  console.log("📧 Betreff:", subject);
  console.log("📧 Body (HTML):", body.substring(0, 200)); // Debug: Zeige ersten Teil des HTML-Inhalts
  console.log("📧 Nachricht:", body.substring(0, 50) + "...");

  if (!recipientInputValue || !subject || !body) {
    showComposeMessage("Bitte füllen Sie alle Felder aus.", "error");
    return;
  }

  try {
    const companyId = getCompanyId();
    const userId = getUserId();
    const emailsRef = collection(db, "kunden", companyId, "emails");

    // 🔥 NEU: JEDER darf externe E-Mails versenden, VORAUSSETZUNG: Interne E-Mail-Adresse muss vorhanden sein
    // Die interne E-Mail-Adresse wird weiter unten geladen
    const userRole = userAuthData.role || 'user';
    console.log(`📧 Benutzer-Rolle: ${userRole}`);

    // Lade interne E-Mail für den aktuellen Benutzer
    let senderInternalEmail = userAuthData.internalEmail;
    let senderName = userAuthData.name;
    
    // Falls internalEmail nicht in userAuthData ist, lade es aus users oder schichtplanMitarbeiter
    if (!senderInternalEmail) {
      try {
        // Versuche aus users zu laden
        const userRef = doc(db, "kunden", companyId, "users", userId);
        const userSnap = await getDoc(userRef);
        if (userSnap.exists()) {
          const userData = userSnap.data();
          senderInternalEmail = userData.internalEmail || userData.email || "";
          if (!senderName) {
            senderName = userData.name || `${userData.vorname || ""} ${userData.nachname || ""}`.trim() || senderInternalEmail;
          }
        }
        
        // Falls immer noch keine internalEmail, versuche aus schichtplanMitarbeiter
        if (!senderInternalEmail || senderInternalEmail === userAuthData.email) {
          const mitarbeiterRef = collection(db, "kunden", companyId, "schichtplanMitarbeiter");
          const mitarbeiterQuery = query(
            mitarbeiterRef,
            where("email", "==", userAuthData.email || "")
          );
          const mitarbeiterSnap = await getDocs(mitarbeiterQuery);
          if (!mitarbeiterSnap.empty) {
            const mitarbeiterData = mitarbeiterSnap.docs[0].data();
            if (mitarbeiterData.internalEmail) {
              senderInternalEmail = mitarbeiterData.internalEmail;
              if (!senderName) {
                senderName = `${mitarbeiterData.vorname || ""} ${mitarbeiterData.nachname || ""}`.trim() || senderInternalEmail;
              }
            }
          }
        }
      } catch (err) {
        console.warn("⚠️ Konnte interne E-Mail nicht laden:", err);
      }
    }
    
    // Verwende interne E-Mail als Absender, falls vorhanden
    const senderEmail = senderInternalEmail || userAuthData.email || "";
    if (!senderName) {
      senderName = senderEmail || "Unbekannt";
    }
    
    const sender = {
      uid: userId,
      email: senderEmail,
      name: senderName,
    };
    
    console.log(`📧 Absender: ${senderName} <${senderEmail}>`);
    console.log(`📧 Interne E-Mail-Adresse vorhanden: ${!!senderInternalEmail}`);
    
    // 🔥 NEU: Prüfe, ob interne E-Mail-Adresse vorhanden ist (für externe E-Mails erforderlich)
    const hasInternalEmail = !!senderInternalEmail;

    // Parse Empfänger aus Input-Feld (getrennt durch ;)
    const recipientStrings = recipientInputValue.split(";").map(r => r.trim()).filter(r => r.length > 0);
    
    if (recipientStrings.length === 0) {
      showComposeMessage("Bitte geben Sie mindestens einen Empfänger an.", "error");
      return;
    }

    // 🔥 NEU: Verarbeite Gruppen-E-Mails zuerst (außerhalb der Schleife, um Duplikate zu vermeiden)
    const processedGroups = new Set(); // Set zum Verhindern von Duplikaten
    // companyId wurde bereits oben in Zeile 1482 deklariert
    // emailsRef wurde bereits oben in Zeile 1484 deklariert
    
    // Verarbeite alle Gruppen zuerst
    for (const recipientString of recipientStrings) {
      const groupMatch = recipientString.match(/^\[Gruppe:\s*(.+)\]$/);
      if (groupMatch) {
        const groupName = groupMatch[1].trim();
        console.log(`📧 Suche Gruppe: "${groupName}" in ${allGroups.length} Gruppen`);
        const group = allGroups.find(g => g.name === groupName);
        console.log(`📧 Gruppe gefunden: ${group ? "Ja" : "Nein"}`, group ? { id: group.id, name: group.name, members: group.members?.length || 0 } : null);
        if (group && !processedGroups.has(group.id)) {
          processedGroups.add(group.id);
          
          console.log(`📧 Gruppe gefunden: ${group.name} (${group.members?.length || 0} Mitglieder)`);
          
          // 🔥 WICHTIG: Erstelle E-Mails für jeden Empfänger im Posteingang
          // Filtere nur Mitglieder mit UID (ohne UID können keine E-Mails empfangen werden)
          console.log(`📧 Gruppenmitglieder RAW:`, JSON.stringify(group.members, null, 2));
          const validMembers = (group.members || []).filter(member => {
            const hasUid = member.uid && member.uid !== null && member.uid !== undefined && member.uid !== "";
            if (!hasUid) {
              console.warn(`⚠️ Mitglied "${member.name || `${member.vorname || ""} ${member.nachname || ""}`.trim()}" hat keine gültige UID: ${member.uid}`);
              // 🔥 NEU: Versuche UID über allUsers zu finden
              const foundUser = allUsers.find(u => {
                const nameMatch = (u.vorname === member.vorname && u.nachname === member.nachname) ||
                                 u.name === member.name;
                const emailMatch = u.email === member.email ||
                                 u.email === member.internalEmail ||
                                 u.loginEmail === member.email;
                return nameMatch || emailMatch;
              });
              if (foundUser && foundUser.uid) {
                console.log(`✅ UID für "${member.name}" über allUsers gefunden: ${foundUser.uid}`);
                member.uid = foundUser.uid; // Setze UID nachträglich
                return true;
              }
            }
            return hasUid;
          });
          console.log(`📧 Gruppe "${group.name}": ${group.members?.length || 0} Mitglieder gesamt, ${validMembers.length} mit gültiger UID`);
          console.log(`📧 Gruppenmitglieder Details:`, group.members?.map(m => ({ name: m.name || `${m.vorname || ""} ${m.nachname || ""}`.trim(), uid: m.uid })));
          
          if (validMembers.length === 0) {
            console.error(`❌ Keine gültigen Mitglieder mit UID in Gruppe "${group.name}"!`);
            throw new Error(`Keine gültigen Mitglieder mit UID in Gruppe "${group.name}". Bitte prüfen Sie die Gruppenmitglieder.`);
          }
          
          const recipientEmails = validMembers.map(member => ({
            uid: member.uid,
            name: member.name || `${member.vorname || ""} ${member.nachname || ""}`.trim() || "",
            email: member.email || "",
            internalEmail: member.internalEmail || member.email || "",
            vorname: member.vorname || "",
            nachname: member.nachname || ""
          }));
          
          console.log(`📧 Erstelle E-Mails für ${recipientEmails.length} Empfänger:`, recipientEmails.map(m => `${m.name} (UID: ${m.uid})`));
          
          const inboxEmailPromises = recipientEmails.map(async (member) => {
            if (!member.uid) {
              console.warn(`⚠️ Mitglied "${member.name}" hat keine UID, überspringe`);
              return null;
            }
            
            // 🔥 WICHTIG: Prüfe, ob die UID gültig ist (nicht null, nicht undefined, nicht leer)
            if (member.uid === null || member.uid === undefined || member.uid === "") {
              console.warn(`⚠️ Mitglied "${member.name}" hat ungültige UID: ${member.uid}, überspringe`);
              return null;
            }
            
            const emailData = {
              from: userId,
              fromEmail: sender.email,
              fromName: sender.name,
              to: member.uid, // 🔥 WICHTIG: Muss die UID des Empfängers sein (für loadInbox Query)
              toEmail: member.email || "",
              toName: member.name || "",
              subject: subject,
              body: body,
              read: false,
              draft: false,
              deleted: false,
              isGroupEmail: true,
              groupId: group.id,
              groupName: group.name,
              createdAt: serverTimestamp(),
            };
            
            console.log(`📧 Erstelle E-Mail für ${member.name} (UID: ${member.uid}, Email: ${member.email})`);
            console.log(`📧 EmailData:`, { from: userId, to: member.uid, subject: subject.substring(0, 50) });
            
            // 🔥 WICHTIG: Prüfe, ob die UID wirklich eine gültige User-ID ist
            // Verifiziere, dass der Empfänger in der users-Collection existiert
            try {
              const recipientUserRef = doc(db, "kunden", companyId, "users", member.uid);
              const recipientUserSnap = await getDoc(recipientUserRef);
              if (!recipientUserSnap.exists()) {
                console.error(`❌ FEHLER: Empfänger-UID ${member.uid} existiert nicht in users-Collection!`);
                console.error(`❌ Mitglied: ${member.name}, UID: ${member.uid}`);
                return null;
              }
              console.log(`✅ Empfänger-UID ${member.uid} verifiziert in users-Collection`);
            } catch (verifyError) {
              console.error(`❌ Fehler bei Verifizierung der Empfänger-UID ${member.uid}:`, verifyError);
              return null;
            }
            
            try {
              const emailRef = await addDoc(emailsRef, emailData);
              console.log(`✅ E-Mail erstellt für ${member.name} (${member.uid}): ${emailRef.id}`);
              
              // 🔥 DEBUG: Verifiziere, dass die E-Mail korrekt gespeichert wurde
              const verifyRef = doc(db, "kunden", companyId, "emails", emailRef.id);
              const verifySnap = await getDoc(verifyRef);
              if (verifySnap.exists()) {
                const verifyData = verifySnap.data();
                console.log(`✅ Verifiziert: E-Mail ${emailRef.id} hat to: ${verifyData.to}, erwartet: ${member.uid}`);
                if (verifyData.to !== member.uid) {
                  console.error(`❌ FEHLER: E-Mail hat falsche to-UID! Erwartet: ${member.uid}, Gefunden: ${verifyData.to}`);
                } else {
                  console.log(`✅ E-Mail korrekt gespeichert mit to: ${member.uid}`);
                }
              } else {
                console.error(`❌ FEHLER: E-Mail ${emailRef.id} wurde nicht in Firestore gefunden!`);
              }
              
              return emailRef;
            } catch (error) {
              console.error(`❌ Fehler beim Erstellen der E-Mail für ${member.name} (${member.uid}):`, error);
              return null;
            }
          });
          
          const results = await Promise.all(inboxEmailPromises);
          const successCount = results.filter(r => r !== null).length;
          const failedCount = recipientEmails.length - successCount;
          console.log(`✅ ${successCount} E-Mails erfolgreich erstellt für Gruppe "${group.name}"${failedCount > 0 ? `, ${failedCount} fehlgeschlagen` : ""}`);
          
          if (failedCount > 0) {
            console.warn(`⚠️ ${failedCount} E-Mails konnten nicht erstellt werden. Prüfe, ob alle Gruppenmitglieder eine gültige UID haben.`);
          }
          
          // 🔥 WICHTIG: Erstelle EINE E-Mail für "Gesendet" mit allen Empfängern
          const sentEmailData = {
            from: userId,
            fromEmail: sender.email,
            fromName: sender.name,
            to: null, // Kein einzelner Empfänger bei Gruppen
            toEmail: null,
            toName: `[Gruppe: ${group.name}]`,
            subject: subject,
            body: body,
            read: false,
            draft: false,
            deleted: false,
            isGroupEmail: true,
            groupId: group.id,
            groupName: group.name,
            recipients: recipientEmails, // 🔥 NEU: Array mit allen Empfängern
            createdAt: serverTimestamp(),
          };
          await addDoc(emailsRef, sentEmailData);
          
          console.log(`✅ E-Mail an Gruppe "${group.name}" (${group.members?.length || 0} Mitglieder) gesendet`);
        }
      }
    }

    const emailPromises = recipientStrings.map(async (recipientString) => {
      let recipient = null;
      let isExternalEmail = false;
      let recipientEmail = "";
      let recipientName = "";
      let recipientUid = null;
      let isGroup = false;
      let group = null;

      // 🔥 NEU: Prüfe, ob es eine Gruppe ist (Format: [Gruppe: Gruppenname])
      // Gruppen wurden bereits oben verarbeitet, überspringe sie hier
      const groupMatch = recipientString.match(/^\[Gruppe:\s*(.+)\]$/);
      if (groupMatch) {
        // Gruppe wurde bereits oben verarbeitet, überspringe
        return { success: true, isGroup: true, skipped: true };
      }
      
      // Alte Gruppen-Logik entfernt - wird jetzt oben verarbeitet
      if (false) {
        const groupName = groupMatch[1].trim();
        group = allGroups.find(g => g.name === groupName);
        if (group) {
          isGroup = true;
          console.log(`📧 Gruppe gefunden: ${group.name} (${group.members?.length || 0} Mitglieder)`);
          
          // companyId wurde bereits oben deklariert
          const emailsRef = collection(db, "kunden", companyId, "emails");
          
          // 🔥 WICHTIG: Erstelle E-Mails für jeden Empfänger im Posteingang
          const recipientEmails = (group.members || []).map(member => ({
            uid: member.uid,
            name: member.name || "",
            email: member.email || "",
            internalEmail: member.internalEmail || member.email || ""
          }));
          
          const inboxEmailPromises = recipientEmails.map(async (member) => {
            const emailData = {
              from: userId,
              fromEmail: sender.email,
              fromName: sender.name,
              to: member.uid,
              toEmail: member.email || "",
              toName: member.name || "",
              subject: subject,
              body: body,
              read: false,
              draft: false,
              deleted: false,
              isGroupEmail: true,
              groupId: group.id,
              groupName: group.name,
              createdAt: serverTimestamp(),
            };
            return await addDoc(emailsRef, emailData);
          });
          await Promise.all(inboxEmailPromises);
          
          // 🔥 WICHTIG: Erstelle EINE E-Mail für "Gesendet" mit allen Empfängern
          const sentEmailData = {
            from: userId,
            fromEmail: sender.email,
            fromName: sender.name,
            to: null, // Kein einzelner Empfänger bei Gruppen
            toEmail: null,
            toName: `[Gruppe: ${group.name}]`,
            subject: subject,
            body: body,
            read: false,
            draft: false,
            deleted: false,
            isGroupEmail: true,
            groupId: group.id,
            groupName: group.name,
            recipients: recipientEmails, // 🔥 NEU: Array mit allen Empfängern
            createdAt: serverTimestamp(),
          };
          await addDoc(emailsRef, sentEmailData);
          
          console.log(`✅ E-Mail an Gruppe "${group.name}" (${group.members?.length || 0} Mitglieder) gesendet`);
          return { success: true, isGroup: true };
        } else {
          throw new Error(`Gruppe "${groupName}" nicht gefunden.`);
        }
      }

      // 🔥 WICHTIG: Interne E-Mails werden über den Usernamen (UID) zugeordnet, nicht über E-Mail-Adressen/Aliase
      // Prüfe zuerst, ob es ein interner Mitarbeiter (Name) ist
      recipient = allUsers.find(u => 
        u.name.toLowerCase() === recipientString.toLowerCase() ||
        `${u.vorname} ${u.nachname}`.trim().toLowerCase() === recipientString.toLowerCase()
      );
      
      if (recipient) {
        // 🔥 Interner Mitarbeiter gefunden - interne E-Mail (nur über Datenbank, NICHT über Mailserver)
        recipientEmail = recipient.email || "";
        recipientName = recipient.name;
        recipientUid = recipient.uid;
        isExternalEmail = false; // 🔥 WICHTIG: Interne E-Mail, NICHT über Mailserver
        console.log(`📧 Interner Mitarbeiter gefunden: ${recipientName} (UID: ${recipientUid}) - interne E-Mail über Datenbank`);
      } else if (isValidEmail(recipientString)) {
        // Es ist eine E-Mail-Adresse, aber kein interner Mitarbeiter gefunden
        // Prüfe, ob es eine interne E-Mail-Adresse (@rettbase.de) ist
        const emailLower = recipientString.toLowerCase();
        const isInternalDomain = emailLower.includes("@rettbase.de") || emailLower.includes(".rettbase.de");
        
        if (isInternalDomain) {
          // 🔥 Interne E-Mail-Adresse (Alias), aber kein Mitarbeiter gefunden
          // Da interne E-Mails nur über Usernamen (UID) zugeordnet werden, ist dies ein Fehler
          throw new Error(`Interne E-Mail-Adresse "${recipientString}" wurde nicht in der Mitarbeiterliste gefunden. Bitte wählen Sie den Mitarbeiter aus der Liste aus (über den Namen, nicht über die E-Mail-Adresse).`);
        } else {
          // Externe E-Mail-Adresse (nicht @rettbase.de)
          // 🔥 WICHTIG: Prüfe Rolle - User-Rollen können keine externen E-Mails versenden
          if (userRole.toLowerCase() === "user") {
            throw new Error(`Sie können als Benutzer mit der Rolle "User" keine externen E-Mails versenden. Bitte wählen Sie einen internen Mitarbeiter aus der Liste.`);
          }
          
          // 🔥 NEU: Prüfe, ob interne E-Mail-Adresse vorhanden ist (Voraussetzung für externe E-Mails)
          if (!hasInternalEmail) {
            throw new Error(`Sie können keine externen E-Mails versenden, da keine interne E-Mail-Adresse (Alias) für Sie eingerichtet ist. Bitte kontaktieren Sie einen Administrator, um eine interne E-Mail-Adresse einzurichten.`);
          }
          isExternalEmail = true; // 🔥 Externe E-Mail, über Mailserver
          recipientEmail = recipientString;
          recipientName = recipientString;
          console.log(`📧 Externe E-Mail-Adresse: ${recipientEmail} - wird über Mailserver versendet`);
        }
      } else {
        // Weder Name noch gültige E-Mail-Adresse - Fehler
        throw new Error(`Empfänger "${recipientString}" nicht gefunden. Bitte wählen Sie einen Mitarbeiter aus der Liste (für interne E-Mails) oder geben Sie eine gültige externe E-Mail-Adresse ein.`);
      }

      // Für interne E-Mails: In Firestore speichern
      if (!isExternalEmail && recipientUid) {
        const emailData = {
          from: userId,
          fromEmail: sender.email,
          fromName: sender.name,
          to: recipientUid,
          toEmail: recipientEmail,
          toName: recipientName,
          subject: subject,
          body: body,
          read: false,
          draft: false, // 🔥 WICHTIG: Versendete E-Mails sind KEINE Entwürfe
          deleted: false, // 🔥 WICHTIG: Interne E-Mails sollen NICHT im Papierkorb landen
          createdAt: serverTimestamp(),
        };
        
        console.log(`📧 Speichere interne E-Mail mit emailData:`, {
          from: emailData.from,
          to: emailData.to,
          draft: emailData.draft,
          deleted: emailData.deleted,
        });
        
        const newEmailRef = await addDoc(emailsRef, emailData);
        console.log(`✅ Interne E-Mail an ${recipientName} (${recipientEmail}) gespeichert (ID: ${newEmailRef.id}, draft: false, deleted: false)`);
        
        // 🔥 SICHERHEITSPRÜFUNG: Stelle sicher, dass draft: false und deleted: false gesetzt sind
        // Warte kurz, damit Firestore die E-Mail gespeichert hat
        await new Promise(resolve => setTimeout(resolve, 200));
        const verifySnap = await getDoc(newEmailRef);
        const verifyData = verifySnap.data();
        console.log(`🔍 Verifikation für interne E-Mail ${newEmailRef.id}: draft=${verifyData.draft}, deleted=${verifyData.deleted}`);
        
        if (verifyData.draft === true || verifyData.deleted === true) {
          console.error(`❌ FEHLER: E-Mail ${newEmailRef.id} wurde mit draft: ${verifyData.draft} oder deleted: ${verifyData.deleted} erstellt! Korrigiere...`);
          await updateDoc(newEmailRef, { draft: false, deleted: false });
          console.log(`✅ E-Mail ${newEmailRef.id} korrigiert: draft: false, deleted: false`);
          
          // 🔥 ZUSÄTZLICHE VERIFIKATION: Prüfe nochmal nach der Korrektur
          await new Promise(resolve => setTimeout(resolve, 200));
          const verifySnap2 = await getDoc(newEmailRef);
          const verifyData2 = verifySnap2.data();
          console.log(`🔍 Zweite Verifikation für interne E-Mail ${newEmailRef.id}: draft=${verifyData2.draft}, deleted=${verifyData2.deleted}`);
          if (verifyData2.draft === true || verifyData2.deleted === true) {
            console.error(`❌ ❌ ❌ KRITISCHER FEHLER: E-Mail ${newEmailRef.id} konnte nicht korrigiert werden! draft: ${verifyData2.draft}, deleted: ${verifyData2.deleted}`);
          } else {
            console.log(`✅ Interne E-Mail ${newEmailRef.id} erfolgreich korrigiert: draft: false, deleted: false`);
          }
        } else {
          console.log(`✅ Interne E-Mail ${newEmailRef.id} korrekt gespeichert: draft: false, deleted: false`);
        }
      }

      // Für externe E-Mails: Auch in Firestore speichern (für Antwort-Zuordnung)
      if (isExternalEmail) {
        const emailData = {
          from: userId,
          fromEmail: sender.email,
          fromName: sender.name,
          to: null, // Kein interner Empfänger
          toEmail: recipientEmail,
          toName: recipientName,
          subject: subject,
          body: body,
          read: false,
          draft: false, // 🔥 WICHTIG: Versendete E-Mails sind KEINE Entwürfe
          deleted: false,
          isExternal: true, // Markiere als externe E-Mail
          createdAt: serverTimestamp(),
        };
        const newEmailRef = await addDoc(emailsRef, emailData);
        console.log(`✅ Externe E-Mail an ${recipientName} (${recipientEmail}) in Firestore gespeichert (ID: ${newEmailRef.id}, draft: false)`);
        
        // 🔥 SICHERHEITSPRÜFUNG: Stelle sicher, dass draft: false und deleted: false gesetzt sind
        const verifySnap = await getDoc(newEmailRef);
        const verifyData = verifySnap.data();
        if (verifyData.draft === true || verifyData.deleted === true) {
          console.error(`❌ FEHLER: E-Mail ${newEmailRef.id} wurde mit draft: ${verifyData.draft} oder deleted: ${verifyData.deleted} erstellt! Korrigiere...`);
          await updateDoc(newEmailRef, { draft: false, deleted: false });
          console.log(`✅ E-Mail ${newEmailRef.id} korrigiert: draft: false, deleted: false`);
        }
      }

      // Für externe E-Mails: Über SMTP versenden (NUR wenn es wirklich eine externe E-Mail ist)
      if (isExternalEmail) {
        try {
          // Verwende die richtige Region (us-central1)
          const functions = getFunctions(undefined, "us-central1");
          const sendEmail = httpsCallable(functions, "sendEmail");
          
          console.log(`📧 Versende externe E-Mail an ${recipientEmail}...`);
          
          // 🔥 NEU: Bei Antworten auf externe E-Mails: Verwende die interne E-Mail-Adresse (Alias) als replyTo
          // Prüfe, ob es eine Antwort ist (Betreff beginnt mit "Re:")
          const isReplyEmail = subject.toLowerCase().startsWith("re:");
          let replyToEmail = null;
          
          if (isReplyEmail) {
            // Bei Antworten: Verwende die Empfänger-E-Mail-Adresse als replyTo (ist die interne E-Mail-Adresse des ursprünglichen Absenders)
            // Prüfe, ob die Empfänger-E-Mail-Adresse eine interne E-Mail-Adresse (Alias) ist
            const recipientEmailLower = recipientEmail.toLowerCase();
            if (recipientEmailLower.includes("@rettbase.de") || recipientEmailLower.includes(".rettbase.de")) {
              replyToEmail = recipientEmail;
              console.log(`📧 Antwort erkannt - Reply-To wird auf interne E-Mail-Adresse (Alias) gesetzt: ${replyToEmail}`);
            }
          }
          
          const result = await sendEmail({
            to: recipientEmail,
            subject: subject,
            body: body,
            fromEmail: sender.email || "mail@rettbase.de",
            fromName: sender.name || "RettBase",
            replyTo: replyToEmail, // 🔥 NEU: Reply-To auf interne E-Mail-Adresse (Alias) bei Antworten
          });
          
          console.log(`✅ Externe E-Mail an ${recipientEmail} versendet:`, result);
        } catch (smtpError) {
          console.error(`❌ Fehler beim Versenden der externen E-Mail an ${recipientEmail}:`, smtpError);
          
          // Detailliertere Fehlermeldung
          let errorMessage = `Fehler beim Versenden der E-Mail an ${recipientEmail}`;
          if (smtpError.code === "unauthenticated") {
            errorMessage += ": Benutzer ist nicht authentifiziert";
          } else if (smtpError.code === "invalid-argument") {
            errorMessage += ": Ungültige Parameter";
          } else if (smtpError.code === "internal") {
            errorMessage += ": Interner Serverfehler. Bitte prüfen Sie, ob die Cloud Function deployed ist.";
          } else if (smtpError.message) {
            errorMessage += `: ${smtpError.message}`;
          }
          
          throw new Error(errorMessage);
        }
      }

      return { recipientEmail, recipientName, recipientUid, isExternalEmail };
    });

    const results = await Promise.all(emailPromises);

    // 🔥 WICHTIG: Lösche den Entwurf, BEVOR wir currentDraftId zurücksetzen
    // Die E-Mail wird bereits als neues Dokument in Firestore gespeichert (siehe oben)
    // Der Entwurf muss gelöscht werden, damit er nicht mehr in "Entwürfe" erscheint
    const draftIdToDelete = currentDraftId; // Speichere die ID vor dem Zurücksetzen
    console.log(`📧 Prüfe Entwurf zum Löschen: ${draftIdToDelete}`);
    
    // 🔥 WICHTIG: Setze currentDraftId SOFORT auf null, damit saveDraft() nicht mehr aufgerufen werden kann
    currentDraftId = null;
    
    if (draftIdToDelete) {
      try {
        const draftRef = doc(db, "kunden", companyId, "emails", draftIdToDelete);
        
        // Prüfe, ob der Entwurf existiert
        const draftSnap = await getDoc(draftRef);
        if (draftSnap.exists()) {
          const draftData = draftSnap.data();
          console.log(`📧 Entwurf ${draftIdToDelete} existiert (draft: ${draftData.draft}), lösche ihn jetzt...`);
          await deleteDoc(draftRef);
          console.log(`✅ Entwurf ${draftIdToDelete} erfolgreich gelöscht (E-Mail wurde versendet)`);
        } else {
          console.log(`⚠️ Entwurf ${draftIdToDelete} existiert nicht mehr (bereits gelöscht?)`);
        }
      } catch (deleteError) {
        console.error(`⚠️ Fehler beim Löschen des Entwurfs ${draftIdToDelete}:`, deleteError);
        // 🔥 WICHTIG: Versuche es nochmal mit deleteDoc (nicht als gelöscht markieren, sondern wirklich löschen)
        try {
          const draftRef = doc(db, "kunden", companyId, "emails", draftIdToDelete);
          // Versuche es nochmal zu löschen
          await deleteDoc(draftRef);
          console.log(`✅ Entwurf ${draftIdToDelete} erfolgreich gelöscht (zweiter Versuch)`);
        } catch (secondDeleteError) {
          console.error(`❌ Fehler beim zweiten Löschversuch:`, secondDeleteError);
          // 🔥 WICHTIG: NICHT als gelöscht markieren - das würde den Entwurf in den Papierkorb verschieben
          // Stattdessen: Logge den Fehler und lass den Entwurf bestehen (wird beim nächsten Laden der Entwürfe noch sichtbar sein)
          console.error(`❌ KRITISCHER FEHLER: Entwurf ${draftIdToDelete} konnte nicht gelöscht werden. Bitte manuell prüfen.`);
          // Wirf einen Fehler, damit der Benutzer informiert wird
          throw new Error(`Entwurf konnte nicht gelöscht werden. Bitte versuchen Sie es erneut oder kontaktieren Sie den Support.`);
        }
      }
    } else {
      console.log(`⚠️ Kein currentDraftId gesetzt - keine Entwurf-Löschung erforderlich`);
    }

    const internalCount = results.filter(r => !r.isExternalEmail).length;
    const externalCount = results.filter(r => r.isExternalEmail).length;
    
    let message = "Nachricht erfolgreich gesendet!";
    if (internalCount > 0 && externalCount > 0) {
      message = `Nachricht erfolgreich gesendet (${internalCount} intern, ${externalCount} extern)!`;
    } else if (internalCount > 0) {
      message = `Nachricht erfolgreich gesendet (${internalCount} intern)!`;
    } else if (externalCount > 0) {
      message = `Nachricht erfolgreich gesendet (${externalCount} extern)!`;
    }
    
    showComposeMessage(message, "success");
    setTimeout(() => {
      closeComposeModal();
      // currentDraftId wurde bereits auf null gesetzt (siehe oben)
      isSendingEmail = false; // 🔥 WICHTIG: Flagge zurücksetzen
      loadEmails(); // Aktualisiere E-Mail-Listen (inkl. Entwürfe, um zu prüfen, ob der Entwurf gelöscht wurde)
      switchTab("sent"); // Wechsle zu Gesendet
    }, 1500);
  } catch (error) {
    console.error("Fehler beim Senden der Nachricht:", error);
    isSendingEmail = false; // 🔥 WICHTIG: Flagge auch bei Fehler zurücksetzen
    showComposeMessage(error.message || "Fehler beim Senden der Nachricht. Bitte versuchen Sie es erneut.", "error");
  }
}

async function editDraft(draftId, draftData) {
  console.log(`📧 editDraft aufgerufen: draftId=${draftId}, draftData=`, draftData);
  // 🔥 WICHTIG: Setze currentDraftId BEVOR openComposeModal aufgerufen wird
  currentDraftId = draftId;
  // Stelle sicher, dass draftData.id gesetzt ist
  if (draftData && !draftData.id) {
    draftData.id = draftId;
  }
  openComposeModal(draftData);
  console.log(`📧 currentDraftId nach openComposeModal: ${currentDraftId}`);
}

function showComposeMessage(message, type) {
  composeMessage.textContent = message;
  composeMessage.className = `form-message ${type}`;
  composeMessage.style.display = "block";
}

// ---------------------------------------------------------
// E-Mail anzeigen
// ---------------------------------------------------------

async function viewEmail(emailId, email, type) {
  currentEmailId = emailId;

  // Markiere als gelesen, wenn es eine eingehende Nachricht ist
  if (type === "inbox" && !email.read) {
    try {
      const companyId = getCompanyId();
      const emailRef = doc(db, "kunden", companyId, "emails", emailId);
      await setDoc(emailRef, { read: true }, { merge: true });
    } catch (error) {
      console.error("Fehler beim Markieren als gelesen:", error);
    }
  }

  // Finde Benutzer-Informationen
  const otherUserId = type === "inbox" ? email.from : email.to;
  const otherUser = allUsers.find((u) => u.uid === otherUserId) || {
    name: email.fromName || email.fromEmail || email.toName || email.toEmail || "Unbekannt",
    email: email.fromEmail || email.toEmail || "",
  };

  const date = email.createdAt?.toDate?.() || new Date(email.createdAt);

  // Fülle Modal
  viewEmailSubject.textContent = email.subject || "(Kein Betreff)";
  viewEmailFrom.textContent = `${otherUser.name} (${otherUser.email})`;
  
  // 🔥 NEU: Zeige Gruppen-Info, wenn es eine Gruppen-E-Mail ist
  if (email.isGroupEmail && email.groupName) {
    if (type === "sent" && email.recipients && Array.isArray(email.recipients)) {
      // In "Gesendet": Zeige Gruppenname und alle Empfänger-Namen
      const recipientNames = email.recipients.map(r => 
        r.name || `${r.vorname || ""} ${r.nachname || ""}`.trim() || r.email || "Unbekannt"
      ).join(", ");
      viewEmailTo.textContent = `[Gruppe: ${email.groupName}] - ${recipientNames}`;
    } else {
      // In "Posteingang": Zeige nur Gruppenname
      viewEmailTo.textContent = `[Gruppe: ${email.groupName}]`;
    }
  } else {
    viewEmailTo.textContent = type === "inbox" 
      ? `${userAuthData.email || "Sie"}`
      : `${otherUser.name} (${otherUser.email})`;
  }
  
  viewEmailDate.textContent = formatDate(date);
  // Verwende innerHTML statt textContent, damit Formatierung (Schriftart, Schriftgröße, etc.) angezeigt wird
  viewEmailBody.innerHTML = email.body || "";

  // 🔥 NEU: Zeige Antwort-Optionen für Gruppen-E-Mails
  if (replyOptions) {
    if (email.isGroupEmail && email.groupId) {
      replyOptions.style.display = "block";
      currentReplyType = "all"; // Standard: Antwort an alle
      const allRadio = document.querySelector('input[name="replyType"][value="all"]');
      if (allRadio) allRadio.checked = true;
    } else {
      replyOptions.style.display = "none";
    }
  }

  // Zeige Modal
  if (viewEmailModal) {
    viewEmailModal.style.display = "flex";
    // 🔥 NEU: Setze data-type Attribut für CSS-Styling (Schriftgröße 11 für gesendete E-Mails)
    const emailView = document.querySelector(".email-view");
    if (emailView) {
      emailView.setAttribute("data-type", type);
    }
  }

  // Aktualisiere E-Mail-Listen (für "Neu"-Badge)
  loadEmails();
}

function closeViewEmailModal() {
  if (viewEmailModal) {
    viewEmailModal.style.display = "none";
    currentEmailId = null;
  }
}

// ---------------------------------------------------------
// E-Mail-Aktionen
// ---------------------------------------------------------

async function handleReply() {
  if (!currentEmailId) return;

  try {
    // Lade E-Mail-Daten aus Firestore
    const companyId = getCompanyId();
    const emailRef = doc(db, "kunden", companyId, "emails", currentEmailId);
    const emailSnap = await getDoc(emailRef);
    
    if (!emailSnap.exists()) {
      console.error("E-Mail nicht gefunden");
      return;
    }
    
    const email = emailSnap.data();
    const currentUserId = getUserId();
    
    // 🔥 NEU: Prüfe, ob es eine Gruppen-E-Mail ist
    const isGroupEmail = email.isGroupEmail === true;
    const groupId = email.groupId;
    
    if (isGroupEmail && groupId) {
      // Gruppen-E-Mail: Verwende Antwort-Optionen
      const group = allGroups.find(g => g.id === groupId);
      if (group) {
        // 🔥 WICHTIG: Hole aktuellen replyType aus dem Radio-Button (nicht nur aus currentReplyType)
        const replyTypeRadio = document.querySelector('input[name="replyType"]:checked');
        const replyType = replyTypeRadio ? replyTypeRadio.value : (currentReplyType || "all");
        currentReplyType = replyType; // Aktualisiere globalen Wert
        
        // Schließe View Modal und öffne Compose Modal
        closeViewEmailModal();
        openComposeModal();
        
        // Fülle Empfänger-Feld basierend auf replyType
        if (replyType === "all") {
          // Antwort an alle Gruppenmitglieder
          const groupMembers = group.members || [];
          if (recipientInput) {
            // 🔥 WICHTIG: Verwende exakt das Format [Gruppe: Gruppenname] wie beim Senden
            recipientInput.value = `[Gruppe: ${group.name}]`;
            console.log(`📧 Empfänger-Feld gesetzt: "${recipientInput.value}"`);
          } else {
            console.error("❌ recipientInput Element nicht gefunden!");
          }
          console.log(`📧 Antwort an alle Gruppenmitglieder: ${groupMembers.length} Empfänger, Gruppe: ${group.name}`);
        } else {
          // Antwort nur an Absender
          const sender = allUsers.find(u => u.uid === email.from);
          if (recipientInput) {
            recipientInput.value = sender ? sender.name : email.fromName || "";
          }
          console.log(`📧 Antwort nur an Absender: ${email.fromName || ""}`);
        }
        
        // Setze Betreff und Body
        const subjectInput = document.getElementById("emailSubject");
        if (subjectInput) {
          const originalSubject = email.subject || "";
          const cleanSubject = originalSubject.replace(/ \[Von: [^\]]+\]/, "").trim();
          if (!cleanSubject.toLowerCase().startsWith("re:")) {
            subjectInput.value = `Re: ${cleanSubject}`;
          } else {
            subjectInput.value = cleanSubject;
          }
        }
        
        // Setze E-Mail-Text mit Zitat der ursprünglichen Nachricht im Rich-Text-Editor
        if (emailBodyEditor) {
          const originalDate = email.createdAt?.toDate?.() || new Date(email.createdAt);
          const dateStr = formatDate(originalDate);
          const originalSender = email.fromName || email.fromEmail || "";
          const quotedText = `<br><br>---<br>Am ${dateStr} schrieb ${originalSender}:<br>${email.body || ""}`;
          if (quillEditor) {
            quillEditor.root.innerHTML = quotedText;
            syncEditorToTextarea();
            // Setze Cursor an den Anfang
            quillEditor.setSelection(0);
          }
        }
        
        return; // Beende Funktion für Gruppen-E-Mails
      }
    }
    
    // Normale E-Mail: Bestehende Logik
      // Normale E-Mail: Bestehende Logik
      // 🔥 WICHTIG: Prüfe, ob die ursprüngliche E-Mail intern oder extern war
      const isOriginalEmailInternal = email.isExternal !== true && (email.to || email.from); // Interne E-Mails haben to/from als UID
      
      // Bestimme Empfänger und Absender-E-Mail-Adresse
      let recipientEmail = "";
      let recipientName = "";
      let recipientUid = null;
      let isExternalReply = false;
    
    if (email.from === currentUserId) {
      // Antwort auf eine gesendete E-Mail: Empfänger ist der ursprüngliche Empfänger
      recipientUid = email.to; // UID des ursprünglichen Empfängers
      recipientEmail = email.toEmail || "";
      recipientName = email.toName || "";
      // Prüfe ob es eine externe E-Mail war
      isExternalReply = email.isExternal === true;
    } else {
      // Antwort auf eine empfangene E-Mail: Empfänger ist der ursprüngliche Absender
      recipientUid = email.from; // UID des ursprünglichen Absenders (falls intern)
      recipientEmail = email.fromEmail || "";
      recipientName = email.fromName || "";
      // Prüfe ob es eine externe E-Mail war
      isExternalReply = email.isExternal === true;
    }
    
    // 🔥 WICHTIG: Bei internen E-Mails muss recipientUid vorhanden sein
    if (isOriginalEmailInternal && !recipientUid) {
      console.error("Keine Empfänger-UID gefunden für interne E-Mail");
      alert("Fehler: Keine Empfänger-UID gefunden.");
      return;
    }
    
    // Bei externen E-Mails muss recipientEmail vorhanden sein
    if (isExternalReply && !recipientEmail) {
      console.error("Keine Empfänger-E-Mail-Adresse gefunden");
      alert("Fehler: Keine Empfänger-E-Mail-Adresse gefunden.");
      return;
    }
    
    // Schließe View Modal
    closeViewEmailModal();
    
    // Öffne Compose Modal
    openComposeModal();
    
    // Fülle Formular mit Antwort-Daten
    if (recipientInput) {
      if (isExternalReply) {
        // 🔥 Bei externen E-Mails: Verwende die E-Mail-Adresse (Alias) direkt
        // Diese wird dann über den Mailserver versendet
        recipientInput.value = recipientEmail;
        console.log(`📧 Antwort an externe E-Mail (über Mailserver): ${recipientEmail}`);
      } else {
        // 🔥 WICHTIG: Bei internen E-Mails: Verwende den Namen (nicht die E-Mail-Adresse)
        // Dies stellt sicher, dass die Antwort als interne E-Mail behandelt wird (über Datenbank)
        if (recipientUid) {
          // Suche den Empfänger über UID
          const recipient = allUsers.find(u => u.uid === recipientUid);
          if (recipient) {
            recipientInput.value = recipient.name;
            console.log(`📧 Antwort an internen Mitarbeiter (über Datenbank): ${recipient.name} (UID: ${recipientUid})`);
          } else {
            // Fallback: Verwende Name aus E-Mail-Daten
            recipientInput.value = recipientName || "";
            console.log(`📧 Antwort an internen Mitarbeiter (Fallback Name): ${recipientName}`);
          }
        } else {
          // Fallback: Versuche über Name zu finden
          const recipient = allUsers.find(u => 
            u.name === recipientName ||
            u.email === recipientEmail
          );
          if (recipient) {
            recipientInput.value = recipient.name;
            console.log(`📧 Antwort an internen Mitarbeiter (über Name gefunden): ${recipient.name}`);
          } else {
            // Letzter Fallback: Verwende Name
            recipientInput.value = recipientName || "";
            console.log(`📧 Antwort an internen Mitarbeiter (letzter Fallback): ${recipientName}`);
          }
        }
      }
    }
    
    // Setze Betreff mit "Re: " Präfix
    const subjectInput = document.getElementById("emailSubject");
    if (subjectInput) {
      const originalSubject = email.subject || "";
      // Entferne [Von: ...] aus dem Betreff falls vorhanden
      const cleanSubject = originalSubject.replace(/ \[Von: [^\]]+\]/, "").trim();
      // Prüfe ob bereits "Re:" vorhanden ist
      if (!cleanSubject.toLowerCase().startsWith("re:")) {
        subjectInput.value = `Re: ${cleanSubject}`;
      } else {
        subjectInput.value = cleanSubject;
      }
    }
    
    // Setze E-Mail-Text mit Zitat der ursprünglichen Nachricht im Rich-Text-Editor
    if (emailBodyEditor) {
      const originalDate = email.createdAt?.toDate?.() || new Date(email.createdAt);
      const dateStr = formatDate(originalDate);
      const originalSender = recipientName || recipientEmail;
      
      // Erstelle Zitat der ursprünglichen Nachricht
      const quotedText = `<br><br>---<br>Am ${dateStr} schrieb ${originalSender}:<br>${email.body || ""}`;
      if (quillEditor) {
        quillEditor.root.innerHTML = quotedText;
        syncEditorToTextarea();
        // Setze Cursor an den Anfang
        quillEditor.setSelection(0);
      }
    }
    
    console.log(`📧 Antwort vorbereitet für: ${recipientName} (${recipientEmail})`);
  } catch (error) {
    console.error("Fehler beim Vorbereiten der Antwort:", error);
    alert("Fehler beim Vorbereiten der Antwort.");
  }
}

async function handleDeleteEmail() {
  if (!currentEmailId) return;

  try {
    // Lade E-Mail-Daten, um zu prüfen, ob sie bereits gelöscht ist (im Papierkorb)
    const companyId = getCompanyId();
    const emailRef = doc(db, "kunden", companyId, "emails", currentEmailId);
    const emailSnap = await getDoc(emailRef);
    
    if (!emailSnap.exists()) {
      alert("E-Mail nicht gefunden.");
      return;
    }
    
    const email = emailSnap.data();
    
    // Wenn E-Mail bereits gelöscht ist (im Papierkorb), dann endgültig löschen
    if (email.deleted === true) {
      // Zeige benutzerdefiniertes Modal für endgültige Löschung
      pendingDeleteEmailId = currentEmailId;
      pendingDeleteEmailData = email;
      openPermanentDeleteModal();
    } else {
      // Normale Löschung (in Papierkorb verschieben) - öffne Modal
      pendingSoftDeleteEmailId = currentEmailId;
      pendingSoftDeleteEmailData = email;
      openDeleteConfirmModal();
    }

  } catch (error) {
    console.error("Fehler beim Löschen der E-Mail:", error);
    alert("Fehler beim Löschen der Nachricht.");
  }
}

function openDeleteConfirmModal() {
  console.log(`🔍 openDeleteConfirmModal aufgerufen`);
  console.log(`🔍 document.readyState:`, document.readyState);
  console.log(`🔍 document.body vorhanden:`, !!document.body);
  
  // Versuche Element zu finden, falls es noch nicht initialisiert wurde
  if (!deleteConfirmModal) {
    deleteConfirmModal = document.getElementById("deleteConfirmModal");
    console.log(`🔍 deleteConfirmModal nach getElementById:`, deleteConfirmModal);
    
    // Falls immer noch nicht gefunden, versuche querySelector
    if (!deleteConfirmModal) {
      deleteConfirmModal = document.querySelector("#deleteConfirmModal");
      console.log(`🔍 deleteConfirmModal nach querySelector:`, deleteConfirmModal);
    }
    
    // Falls immer noch nicht gefunden, warte kurz und versuche es erneut
    if (!deleteConfirmModal) {
      console.log(`⏳ Warte 100ms und versuche erneut...`);
      setTimeout(() => {
        deleteConfirmModal = document.getElementById("deleteConfirmModal");
        if (deleteConfirmModal) {
          deleteConfirmModal.style.display = "flex";
          console.log(`✅ Modal nach Wartezeit angezeigt`);
        } else {
          console.error("❌ Element auch nach Wartezeit nicht gefunden!");
          // Versuche mit verschiedenen Selektoren
          const trySelectors = [
            '#deleteConfirmModal',
            '[id="deleteConfirmModal"]',
            '.modal-overlay[id="deleteConfirmModal"]',
            'div#deleteConfirmModal'
          ];
          
          for (const selector of trySelectors) {
            const found = document.querySelector(selector);
            if (found) {
              console.log(`✅ Element mit Selektor "${selector}" gefunden:`, found);
              deleteConfirmModal = found;
              found.style.display = "flex";
              console.log(`✅ Modal angezeigt`);
              return;
            }
          }
          
          const allDeleteElements = document.querySelectorAll('[id*="delete"]');
          console.error("❌ Verfügbare Elemente mit 'delete':", allDeleteElements);
          allDeleteElements.forEach((el, idx) => {
            console.log(`  [${idx}] id="${el.id}", tagName="${el.tagName}"`);
          });
          
          // Versuche das Modal dynamisch zu erstellen, falls es nicht existiert
          console.log(`🔧 Versuche Modal dynamisch zu erstellen...`);
          const createdModal = createDeleteConfirmModal();
          if (createdModal) {
            deleteConfirmModal = createdModal;
            deleteConfirmModal.style.display = "flex";
            console.log(`✅ Modal dynamisch erstellt und angezeigt`);
          } else {
            alert("Fehler: Lösch-Bestätigungs-Modal nicht gefunden. Bitte Seite neu laden.");
          }
        }
      }, 100);
      return; // Warte auf setTimeout
    }
  }
  
  deleteConfirmModal.style.display = "flex";
  console.log(`✅ deleteConfirmModal angezeigt`);
}

// Erstelle das Delete Confirm Modal dynamisch, falls es nicht existiert
function createDeleteConfirmModal() {
  try {
    // Prüfe ob es bereits existiert
    let modal = document.getElementById("deleteConfirmModal");
    if (modal) {
      return modal;
    }
    
    // Erstelle das Modal
    modal = document.createElement("div");
    modal.id = "deleteConfirmModal";
    modal.className = "modal-overlay";
    modal.style.display = "none";
    
    modal.innerHTML = `
      <div class="modal-content" style="max-width: 500px;">
        <div class="modal-header">
          <h2 style="font-size: 18px; font-weight: 600;">Möchten Sie diese Nachricht wirklich löschen?</h2>
        </div>
        <div class="modal-body" style="padding: 20px;">
          <p style="font-size: 13px; line-height: 1.6; margin-bottom: 15px;">
            Die Nachricht wird in den Papierkorb verschoben.
          </p>
        </div>
        <div class="modal-footer" style="display: flex; justify-content: flex-end; gap: 10px; padding: 15px 20px; border-top: 1px solid var(--border-color);">
          <button id="cancelDeleteBtn" class="btn-secondary" style="padding: 8px 20px;">Abbrechen</button>
          <button id="confirmDeleteBtn" class="btn-danger" style="padding: 8px 20px;">OK</button>
        </div>
      </div>
    `;
    
    // Füge das Modal zum Body hinzu
    document.body.appendChild(modal);
    
    // Initialisiere die Buttons
    confirmDeleteBtn = document.getElementById("confirmDeleteBtn");
    cancelDeleteBtn = document.getElementById("cancelDeleteBtn");
    
    // Füge Event Listener hinzu
    confirmDeleteBtn?.addEventListener("click", () => handleConfirmDelete());
    cancelDeleteBtn?.addEventListener("click", () => closeDeleteConfirmModal());
    modal.addEventListener("click", (e) => {
      if (e.target === modal) closeDeleteConfirmModal();
    });
    
    console.log(`✅ Delete Confirm Modal dynamisch erstellt`);
    return modal;
  } catch (error) {
    console.error("❌ Fehler beim Erstellen des Modals:", error);
    return null;
  }
}

function closeDeleteConfirmModal() {
  // Versuche Element zu finden, falls es noch nicht initialisiert wurde
  if (!deleteConfirmModal) {
    deleteConfirmModal = document.getElementById("deleteConfirmModal");
  }
  
  if (deleteConfirmModal) {
    deleteConfirmModal.style.display = "none";
    pendingSoftDeleteEmailId = null;
    pendingSoftDeleteEmailData = null;
  }
}

async function handleConfirmDelete() {
  console.log(`🔍 handleConfirmDelete aufgerufen: pendingSoftDeleteEmailId=${pendingSoftDeleteEmailId}, pendingSoftDeleteEmailData vorhanden=${!!pendingSoftDeleteEmailData}`);
  
  if (!pendingSoftDeleteEmailId || !pendingSoftDeleteEmailData) {
    console.error("❌ pendingSoftDeleteEmailId oder pendingSoftDeleteEmailData fehlt!");
    return;
  }

  try {
    const companyId = getCompanyId();
    const emailRef = doc(db, "kunden", companyId, "emails", pendingSoftDeleteEmailId);
    
    // Soft Delete: Markiere als gelöscht statt komplett zu löschen
    await setDoc(emailRef, {
      deleted: true,
      deletedAt: serverTimestamp(),
    }, { merge: true });
    
    console.log(`✅ E-Mail ${pendingSoftDeleteEmailId} in Papierkorb verschoben.`);
    
    closeDeleteConfirmModal();
    closeViewEmailModal();
    
    // Aktualisiere alle Listen
    await loadEmails();
  } catch (error) {
    console.error("Fehler beim Löschen der E-Mail:", error);
    alert("Fehler beim Löschen der Nachricht.");
  }
}

function openPermanentDeleteModal() {
  console.log(`🔍 openPermanentDeleteModal aufgerufen, permanentDeleteModal vorhanden: ${!!permanentDeleteModal}`);
  if (permanentDeleteModal) {
    permanentDeleteModal.style.display = "flex";
    console.log(`✅ permanentDeleteModal angezeigt`);
  } else {
    console.error("❌ permanentDeleteModal ist null oder undefined!");
  }
}

function closePermanentDeleteModal() {
  if (permanentDeleteModal) {
    permanentDeleteModal.style.display = "none";
    pendingDeleteEmailId = null;
    pendingDeleteEmailData = null;
  }
}

async function handleConfirmPermanentDelete() {
  if (!pendingDeleteEmailId || !pendingDeleteEmailData) {
    return;
  }

  try {
    // Endgültige Löschung
    await handlePermanentDelete(pendingDeleteEmailId, pendingDeleteEmailData);
    
    closePermanentDeleteModal();
    closeViewEmailModal();
    loadEmails(); // Aktualisiere Listen
  } catch (error) {
    console.error("Fehler bei der endgültigen Löschung:", error);
    alert("Fehler bei der endgültigen Löschung der Nachricht.");
    closePermanentDeleteModal();
  }
}

// 🔥 NEU: Schnell-Antwort direkt aus der Liste
async function handleQuickReply(emailId, email) {
  try {
    // 🔥 NEU: Öffne das View-Email-Modal mit den Antwort-Optionen (wie beim normalen Antworten)
    currentEmailId = emailId;
    await viewEmail(emailId, email, "inbox");
    
    // 🔥 WICHTIG: Setze currentReplyType basierend auf der E-Mail
    if (email.isGroupEmail && email.groupId) {
      currentReplyType = "all"; // Standard: Antwort an alle
      if (replyOptions) {
        replyOptions.style.display = "block";
        const allRadio = document.querySelector('input[name="replyType"][value="all"]');
        if (allRadio) allRadio.checked = true;
      }
    }
  } catch (error) {
    console.error("Fehler beim Öffnen der Antwort:", error);
    alert("Fehler beim Öffnen der Antwort.");
  }
}

// 🔥 NEU: Schnell-Löschen direkt aus der Liste
async function handleQuickDelete(emailId, email) {
  try {
    console.log(`🗑️ handleQuickDelete aufgerufen: emailId=${emailId}, email vorhanden=${!!email}`);
    
    // Wenn email bereits vorhanden ist, verwende es direkt
    let emailData = email;
    
    // Wenn email nicht vollständig ist, lade die E-Mail aus Firestore
    if (!emailData || typeof emailData !== 'object' || !emailData.subject) {
      console.log(`📧 Lade E-Mail ${emailId} aus Firestore...`);
      const companyId = getCompanyId();
      const emailRef = doc(db, "kunden", companyId, "emails", emailId);
      const emailSnap = await getDoc(emailRef);
      
      if (!emailSnap.exists()) {
        console.error(`❌ E-Mail ${emailId} nicht in Firestore gefunden.`);
        alert("E-Mail nicht gefunden.");
        return;
      }
      
      emailData = emailSnap.data();
      console.log(`✅ E-Mail ${emailId} aus Firestore geladen.`);
    }
    
    // Wenn E-Mail bereits gelöscht ist (im Papierkorb), dann endgültig löschen
    if (emailData.deleted === true) {
      console.log(`🗑️ E-Mail ${emailId} ist bereits gelöscht, öffne Permanent-Delete-Modal`);
      // Zeige benutzerdefiniertes Modal für endgültige Löschung
      pendingDeleteEmailId = emailId;
      pendingDeleteEmailData = emailData;
      openPermanentDeleteModal();
    } else {
      console.log(`🗑️ E-Mail ${emailId} wird in Papierkorb verschoben, öffne Delete-Confirm-Modal`);
      // Normale Löschung (in Papierkorb verschieben) - öffne Modal
      pendingSoftDeleteEmailId = emailId;
      pendingSoftDeleteEmailData = emailData;
      console.log(`📧 pendingSoftDeleteEmailId=${pendingSoftDeleteEmailId}, pendingSoftDeleteEmailData vorhanden=${!!pendingSoftDeleteEmailData}`);
      openDeleteConfirmModal();
    }
  } catch (error) {
    console.error("❌ Fehler beim Löschen der E-Mail:", error);
    alert("Fehler beim Löschen der Nachricht: " + error.message);
  }
}

// 🔥 NEU: Schnelle endgültige Löschung aus dem Papierkorb (öffnet Modal)
async function handleQuickPermanentDelete(emailId, emailData) {
  try {
    console.log(`🗑️ handleQuickPermanentDelete aufgerufen: emailId=${emailId}, emailData vorhanden=${!!emailData}`);
    
    // Wenn emailData bereits vorhanden und vollständig ist, verwende es direkt
    let email = emailData;
    
    // Wenn emailData nicht vorhanden oder nicht vollständig ist, lade die E-Mail aus Firestore
    if (!email || typeof email !== 'object' || !email.subject) {
      console.log(`📧 Lade E-Mail ${emailId} aus Firestore...`);
      const companyId = getCompanyId();
      const emailRef = doc(db, "kunden", companyId, "emails", emailId);
      const emailSnap = await getDoc(emailRef);
      
      if (!emailSnap.exists()) {
        console.error(`❌ E-Mail ${emailId} nicht in Firestore gefunden.`);
        alert("E-Mail nicht gefunden.");
        return;
      }
      
      email = emailSnap.data();
      console.log(`✅ E-Mail ${emailId} aus Firestore geladen.`);
    }
    
    // Prüfe ob permanentDeleteModal vorhanden ist
    if (!permanentDeleteModal) {
      console.error("❌ permanentDeleteModal nicht gefunden!");
      alert("Fehler: Lösch-Modal nicht gefunden. Bitte Seite neu laden.");
      return;
    }
    
    // Öffne das Modal für endgültige Löschung
    pendingDeleteEmailId = emailId;
    pendingDeleteEmailData = email;
    console.log(`📧 Öffne Lösch-Modal für E-Mail ${emailId}`);
    openPermanentDeleteModal();
  } catch (error) {
    console.error("❌ Fehler beim Öffnen des Lösch-Modals:", error);
    console.error("Error details:", error.message, error.stack);
    alert("Fehler beim Öffnen des Lösch-Modals: " + (error.message || "Unbekannter Fehler"));
  }
}

// Endgültige Löschung einer E-Mail (auch aus mail@rettbase.de)
async function handlePermanentDelete(emailId, emailData) {
  try {
    const companyId = getCompanyId();
    const emailRef = doc(db, "kunden", companyId, "emails", emailId);
    
    // 🔥 NEU: Wenn es eine externe E-Mail ist, versuche sie auch aus mail@rettbase.de zu löschen
    if (emailData.isExternal === true) {
      try {
        // Verwende Cloud Function zum Löschen der E-Mail aus mail@rettbase.de
        const functions = getFunctions(undefined, "us-central1");
        const deleteEmailFromMailbox = httpsCallable(functions, "deleteEmailFromMailbox");
        
        // Extrahiere E-Mail-Informationen für die Löschung
        const emailSubject = emailData.subject || "";
        const emailTo = emailData.toEmail || "";
        const emailFrom = emailData.fromEmail || "";
        
        console.log(`🗑️ Versuche E-Mail aus mail@rettbase.de zu löschen: ${emailSubject}`);
        
        await deleteEmailFromMailbox({
          subject: emailSubject,
          to: emailTo,
          from: emailFrom,
        });
        
        console.log(`✅ E-Mail aus mail@rettbase.de gelöscht`);
      } catch (mailboxError) {
        console.warn("⚠️ Konnte E-Mail nicht aus mail@rettbase.de löschen:", mailboxError);
        // Fortfahren mit der Löschung aus Firestore, auch wenn mailbox-Löschung fehlschlägt
      }
    }
    
    // Lösche E-Mail aus Firestore
    await deleteDoc(emailRef);
    console.log(`✅ E-Mail endgültig gelöscht: ${emailId}`);
  } catch (error) {
    console.error("Fehler bei der endgültigen Löschung:", error);
    throw error;
  }
}

// ---------------------------------------------------------
// Tab-Verwaltung
// ---------------------------------------------------------

function switchTab(tab) {
  // Aktiviere/deaktiviere Tabs
  tabBtns.forEach((btn) => {
    if (btn.dataset.tab === tab) {
      btn.classList.add("active");
    } else {
      btn.classList.remove("active");
    }
  });

  // Zeige/verstecke Tab-Content
  [inboxTab, sentTab, draftsTab, trashTab].forEach(t => {
    if (t) t.classList.remove("active");
  });

  // Lade E-Mails für den aktiven Tab
  if (tab === "inbox" && inboxTab) {
    inboxTab.classList.add("active");
    loadInbox(); // 🔥 Lade Posteingang beim Tab-Wechsel
  } else if (tab === "sent" && sentTab) {
    sentTab.classList.add("active");
    loadSent(); // 🔥 Lade Gesendet beim Tab-Wechsel
  } else if (tab === "drafts" && draftsTab) {
    draftsTab.classList.add("active");
    loadDrafts(); // 🔥 Lade Entwürfe beim Tab-Wechsel
  } else if (tab === "trash" && trashTab) {
    trashTab.classList.add("active");
    loadTrash(); // 🔥 Lade Papierkorb beim Tab-Wechsel
  }
}

// ---------------------------------------------------------
// Hilfsfunktionen
// ---------------------------------------------------------

function getCompanyId() {
  return userAuthData?.companyId || null;
}

function getUserId() {
  return userAuthData?.uid || null;
}

function formatDate(date) {
  if (!date) return "";
  const now = new Date();
  const diff = now - date;
  const days = Math.floor(diff / (1000 * 60 * 60 * 24));

  if (days === 0) {
    return date.toLocaleTimeString("de-DE", { hour: "2-digit", minute: "2-digit" });
  } else if (days === 1) {
    return "Gestern";
  } else if (days < 7) {
    return `vor ${days} Tagen`;
  } else {
    return date.toLocaleDateString("de-DE", { day: "2-digit", month: "2-digit", year: "numeric" });
  }
}

function escapeHtml(text) {
  const div = document.createElement("div");
  div.textContent = text;
  return div.innerHTML;
}

// ---------------------------------------------------------
// Automatische Bereinigung gelöschter Nachrichten
// ---------------------------------------------------------

async function startAutoCleanup() {
  // Führe Bereinigung beim Start aus
  await cleanupOldDeletedEmails();

  // Führe Bereinigung alle 24 Stunden aus
  setInterval(async () => {
    await cleanupOldDeletedEmails();
  }, 24 * 60 * 60 * 1000); // 24 Stunden in Millisekunden
}

async function cleanupOldDeletedEmails() {
  try {
    const companyId = getCompanyId();
    const emailsRef = collection(db, "kunden", companyId, "emails");

    // Lade alle gelöschten E-Mails
    const q = query(
      emailsRef,
      where("deleted", "==", true)
    );

    const snapshot = await getDocs(q);
    const now = new Date();
    const sixtyDaysAgo = new Date(now.getTime() - 60 * 24 * 60 * 60 * 1000); // 60 Tage in Millisekunden

    let deletedCount = 0;

    for (const docSnap of snapshot.docs) {
      const email = docSnap.data();
      const deletedAt = email.deletedAt?.toDate?.() || new Date(email.deletedAt);

      // Wenn gelöscht vor mehr als 60 Tagen
      if (deletedAt < sixtyDaysAgo) {
        try {
          await deleteDoc(docSnap.ref);
          deletedCount++;
        } catch (error) {
          console.error(`Fehler beim Löschen der E-Mail ${docSnap.id}:`, error);
        }
      }
    }

    if (deletedCount > 0) {
      console.log(`✅ ${deletedCount} alte gelöschte E-Mail(s) wurden automatisch entfernt`);
    }
  } catch (error) {
    console.error("Fehler bei der automatischen Bereinigung:", error);
  }
}

// ---------------------------------------------------------
// Gruppen-Funktionen
// ---------------------------------------------------------

// Prüfe Rolle und zeige/verstecke Gruppen-Menü
function updateGroupMenuVisibility() {
  if (!userAuthData) return;
  
  const userRole = userAuthData.role || 'user';
  const isUser = userRole.toLowerCase() === 'user';
  
  if (emailMenuDropdown) {
    emailMenuDropdown.style.display = isUser ? 'none' : 'flex';
  }
  
  if (selectGroupBtn) {
    selectGroupBtn.disabled = isUser;
    selectGroupBtn.style.opacity = isUser ? '0.5' : '1';
    selectGroupBtn.style.cursor = isUser ? 'not-allowed' : 'pointer';
  }
}

// Lade alle Gruppen
async function loadGroups() {
  try {
    const companyId = getCompanyId();
    const groupsRef = collection(db, "kunden", companyId, "emailGroups");
    const snapshot = await getDocs(groupsRef);
    
    allGroups = [];
    snapshot.forEach((doc) => {
      const groupData = doc.data();
      allGroups.push({
        id: doc.id,
        ...groupData
      });
    });
    
    console.log(`📧 ${allGroups.length} Gruppen geladen`);
  } catch (error) {
    console.error("Fehler beim Laden der Gruppen:", error);
    allGroups = [];
  }
}

// Öffne Gruppenerstellungs-Modal
async function openCreateGroupModal() {
  if (createGroupModal) {
    createGroupModal.style.display = "flex";
    createGroupForm?.reset();
    selectedGroupMembers = [];
    
    // 🔥 WICHTIG: Lade alle Mitarbeiter aus der Datenbank (inkl. ohne interne E-Mail)
    await loadAllGroupMembers();
    
    renderGroupMembersList();
    renderSelectedGroupMembers();
  }
}

// Schließe Gruppenerstellungs-Modal
function closeCreateGroupModalFunc() {
  if (createGroupModal) {
    createGroupModal.style.display = "none";
    createGroupForm?.reset();
    selectedGroupMembers = [];
  }
}

// Lade alle Mitarbeiter für Gruppen (inkl. ohne interne E-Mail)
async function loadAllGroupMembers() {
  try {
    const companyId = getCompanyId();
    allGroupMembers = [];
    
    // Lade alle Mitarbeiter aus schichtplanMitarbeiter
    const mitarbeiterRef = collection(db, "kunden", companyId, "schichtplanMitarbeiter");
    const mitarbeiterSnapshot = await getDocs(mitarbeiterRef);
    
    mitarbeiterSnapshot.forEach((doc) => {
      const mitarbeiterData = doc.data();
      if (mitarbeiterData.active !== false) {
        const vorname = mitarbeiterData.vorname || "";
        const nachname = mitarbeiterData.nachname || "";
        const name = `${vorname} ${nachname}`.trim();
        
        // Füge alle aktiven Mitarbeiter hinzu (auch ohne interne E-Mail)
        allGroupMembers.push({
          uid: null, // Wird später über users-Collection zugeordnet
          name: name,
          vorname: vorname,
          nachname: nachname,
          email: mitarbeiterData.email || "",
          internalEmail: mitarbeiterData.internalEmail || null,
        });
      }
    });
    
    // Lade auch alle User aus users-Collection und füge sie hinzu/aktualisiere sie
    const usersRef = collection(db, "kunden", companyId, "users");
    const usersSnapshot = await getDocs(usersRef);
    
    usersSnapshot.forEach((doc) => {
      const userData = doc.data();
      if (userData.status !== false) {
        const vorname = userData.vorname || "";
        const nachname = userData.nachname || "";
        const name = `${vorname} ${nachname}`.trim() || userData.name || "";
        
        // Prüfe, ob bereits in allGroupMembers vorhanden
        // 🔥 WICHTIG: Suche nach Name ODER E-Mail (Login-E-Mail oder interne E-Mail)
        const existingIndex = allGroupMembers.findIndex(m => {
          const nameMatch = m.vorname === vorname && m.nachname === nachname;
          const emailMatch = m.email === userData.email || 
                           m.email === userData.internalEmail ||
                           m.internalEmail === userData.email ||
                           m.internalEmail === userData.internalEmail;
          return nameMatch || emailMatch;
        });
        
        if (existingIndex !== -1) {
          // Aktualisiere bestehenden Eintrag mit UID und interner E-Mail
          allGroupMembers[existingIndex].uid = doc.id;
          if (userData.internalEmail) {
            allGroupMembers[existingIndex].internalEmail = userData.internalEmail;
          }
          // Aktualisiere auch E-Mail, falls nicht vorhanden
          if (!allGroupMembers[existingIndex].email && userData.email) {
            allGroupMembers[existingIndex].email = userData.email;
          }
        } else {
          // Füge neuen Eintrag hinzu
          allGroupMembers.push({
            uid: doc.id,
            name: name,
            vorname: vorname,
            nachname: nachname,
            email: userData.internalEmail || userData.email || "",
            internalEmail: userData.internalEmail || null,
          });
        }
      }
    });
    
    // Sortiere nach Nachname, dann Vorname
    allGroupMembers.sort((a, b) => {
      const nachnameCompare = (a.nachname || "").localeCompare(b.nachname || "", "de");
      if (nachnameCompare !== 0) return nachnameCompare;
      return (a.vorname || "").localeCompare(b.vorname || "", "de");
    });
    
    console.log(`✅ ${allGroupMembers.length} Mitarbeiter für Gruppen geladen`);
  } catch (error) {
    console.error("Fehler beim Laden der Gruppen-Mitarbeiter:", error);
    allGroupMembers = [];
  }
}

// Rendere Mitgliederliste für Gruppenerstellung
function renderGroupMembersList(searchTerm = "") {
  if (!groupMembersList) return;
  
  groupMembersList.innerHTML = "";
  
  const term = searchTerm.toLowerCase().trim();
  
  // 🔥 WICHTIG: Verwende allGroupMembers (alle Mitarbeiter) statt allUsers (nur mit interner E-Mail)
  const usersToShow = allGroupMembers.length > 0 ? allGroupMembers : allUsers;
  
  const filteredUsers = usersToShow.filter(user => {
    // Zeige alle Mitarbeiter an (auch ohne interne E-Mail)
    if (term === "") return true;
    const fullName = `${user.vorname || ""} ${user.nachname || ""}`.trim().toLowerCase();
    const name = user.name ? user.name.toLowerCase() : "";
    const email = user.email ? user.email.toLowerCase() : "";
    const internalEmail = user.internalEmail ? user.internalEmail.toLowerCase() : "";
    return fullName.includes(term) || name.includes(term) || email.includes(term) || internalEmail.includes(term);
  });
  
  if (filteredUsers.length === 0) {
    groupMembersList.innerHTML = '<div style="padding: 20px; text-align: center; color: #64748b;">Keine Mitarbeiter gefunden</div>';
    return;
  }
  
  filteredUsers.forEach(user => {
    // Prüfe, ob bereits ausgewählt (vergleiche über UID oder Name/E-Mail, falls UID null)
    const isSelected = selectedGroupMembers.some(m => 
      (m.uid && user.uid && m.uid === user.uid) ||
      (!m.uid && !user.uid && m.email === user.email && m.name === user.name)
    );
    
    const item = document.createElement("div");
    item.className = "group-member-item";
    
    // Zeige interne E-Mail an, falls vorhanden
    const emailInfo = user.internalEmail || user.email ? ` (${user.internalEmail || user.email})` : "";
    item.innerHTML = `
      <input type="checkbox" ${isSelected ? "checked" : ""} data-uid="${user.uid || ''}" data-email="${user.email || ''}" data-name="${user.name || ''}">
      <span>${escapeHtml(user.name || `${user.vorname || ""} ${user.nachname || ""}`.trim() || "Unbekannt")}${escapeHtml(emailInfo)}</span>
    `;
    
    const checkbox = item.querySelector("input[type='checkbox']");
    checkbox.addEventListener("change", (e) => {
      if (e.target.checked) {
        // Prüfe, ob bereits ausgewählt
        const alreadySelected = selectedGroupMembers.some(m => 
          (m.uid && user.uid && m.uid === user.uid) ||
          (!m.uid && !user.uid && m.email === user.email && m.name === user.name)
        );
        if (!alreadySelected) {
          selectedGroupMembers.push({
            uid: user.uid || null,
            name: user.name || `${user.vorname || ""} ${user.nachname || ""}`.trim(),
            email: user.email || "",
            internalEmail: user.internalEmail || user.email || "",
            vorname: user.vorname || "",
            nachname: user.nachname || ""
          });
        }
      } else {
        // Entferne aus Auswahl
        selectedGroupMembers = selectedGroupMembers.filter(m => 
          !((m.uid && user.uid && m.uid === user.uid) ||
          (!m.uid && !user.uid && m.email === user.email && m.name === user.name))
        );
      }
      renderSelectedGroupMembers();
    });
    
    groupMembersList.appendChild(item);
  });
}

// Rendere ausgewählte Mitglieder
function renderSelectedGroupMembers() {
  if (!selectedGroupMembersDiv) return;
  
  selectedGroupMembersDiv.innerHTML = "";
  
  if (selectedGroupMembers.length === 0) {
    selectedGroupMembersDiv.innerHTML = '<div style="padding: 10px; text-align: center; color: #64748b; font-size: 13px;">Keine Mitglieder ausgewählt</div>';
    return;
  }
  
  selectedGroupMembers.forEach((member, index) => {
    const tag = document.createElement("div");
    tag.className = "selected-member-tag";
    tag.innerHTML = `
      <span>${escapeHtml(member.name || `${member.vorname || ""} ${member.nachname || ""}`.trim() || "Unbekannt")}</span>
      <button type="button" data-index="${index}">&times;</button>
    `;
    
    const removeBtn = tag.querySelector("button");
    removeBtn.addEventListener("click", () => {
      selectedGroupMembers.splice(index, 1);
      renderSelectedGroupMembers();
      renderGroupMembersList(groupMemberSearch?.value || "");
    });
    
    selectedGroupMembersDiv.appendChild(tag);
  });
}

// Filtere Mitgliederliste
function filterGroupMembers(searchTerm) {
  renderGroupMembersList(searchTerm);
}

// Erstelle Gruppe
async function handleCreateGroup(e) {
  e.preventDefault();
  
  const name = groupName?.value.trim();
  const description = groupDescription?.value.trim() || "";
  
  if (!name) {
    alert("Bitte geben Sie einen Gruppennamen ein.");
    return;
  }
  
  if (selectedGroupMembers.length === 0) {
    alert("Bitte wählen Sie mindestens ein Mitglied aus.");
    return;
  }
  
  try {
    const companyId = getCompanyId();
    const userId = getUserId();
    const groupsRef = collection(db, "kunden", companyId, "emailGroups");
    
    const groupData = {
      name: name,
      description: description,
      members: selectedGroupMembers.map(m => ({
        uid: m.uid || null,
        name: m.name || `${m.vorname || ""} ${m.nachname || ""}`.trim() || "",
        email: m.email || "",
        internalEmail: m.internalEmail || m.email || "",
        vorname: m.vorname || "",
        nachname: m.nachname || ""
      })),
      createdBy: userId,
      createdAt: serverTimestamp(),
    };
    
    console.log(`📧 Erstelle Gruppe "${name}" mit ${groupData.members.length} Mitgliedern:`, groupData.members.map(m => `${m.name} (UID: ${m.uid || "null"})`));
    
    await addDoc(groupsRef, groupData);
    console.log(`✅ Gruppe "${name}" erstellt`);
    
    await loadGroups();
    closeCreateGroupModalFunc();
    alert(`Gruppe "${name}" erfolgreich erstellt!`);
  } catch (error) {
    console.error("Fehler beim Erstellen der Gruppe:", error);
    alert("Fehler beim Erstellen der Gruppe.");
  }
}

// Öffne Gruppenauswahl-Modal
function openGroupSelectionModal() {
  if (selectGroupModal && selectGroupForm) {
    selectGroupModal.style.display = "block";
    selectGroupForm.style.display = "block";
    renderGroupList();
  }
}

// Schließe Gruppenauswahl-Modal
function closeGroupSelectionModal() {
  if (selectGroupModal && selectGroupForm) {
    selectGroupModal.style.display = "none";
    selectGroupForm.style.display = "none";
    if (groupSearch) groupSearch.value = "";
  }
}

// Rendere Gruppenliste
function renderGroupList(searchTerm = "") {
  if (!groupList) return;
  
  groupList.innerHTML = "";
  
  const term = searchTerm.toLowerCase().trim();
  const filteredGroups = allGroups.filter(group => {
    if (term === "") return true;
    return group.name.toLowerCase().includes(term) || 
           (group.description && group.description.toLowerCase().includes(term));
  });
  
  if (filteredGroups.length === 0) {
    groupList.innerHTML = '<div style="padding: 20px; text-align: center; color: #64748b;">Keine Gruppen gefunden</div>';
    return;
  }
  
  filteredGroups.forEach(group => {
    const item = document.createElement("div");
    item.className = "group-item";
    item.innerHTML = `
      <label style="display: flex; align-items: flex-start; gap: 10px; cursor: pointer; width: 100%;">
        <input type="radio" name="selectedGroup" value="${group.id}">
        <div style="flex: 1;">
          <div class="group-item-name">${escapeHtml(group.name)}</div>
          ${group.description ? `<div class="group-item-description">${escapeHtml(group.description)}</div>` : ""}
          <div class="group-item-members">${group.members?.length || 0} Mitglieder</div>
        </div>
      </label>
    `;
    
    groupList.appendChild(item);
  });
}

// Filtere Gruppenliste
function filterGroupList(searchTerm) {
  renderGroupList(searchTerm);
}

// Bestätige Gruppenauswahl
function confirmGroupSelection() {
  const selectedRadio = document.querySelector('input[name="selectedGroup"]:checked');
  
  if (!selectedRadio) {
    alert("Bitte wählen Sie eine Gruppe aus.");
    return;
  }
  
  const groupId = selectedRadio.value;
  const group = allGroups.find(g => g.id === groupId);
  
  if (!group) {
    alert("Gruppe nicht gefunden.");
    return;
  }
  
  // Füge Gruppenname zum Empfänger-Feld hinzu
  if (recipientInput) {
    const currentValue = recipientInput.value.trim();
    const groupName = `[Gruppe: ${group.name}]`;
    
    if (currentValue) {
      recipientInput.value = currentValue + "; " + groupName;
    } else {
      recipientInput.value = groupName;
    }
  }
  
  closeGroupSelectionModal();
  console.log(`✅ Gruppe "${group.name}" ausgewählt`);
}

// ---------------------------------------------------------
// Datei-Anhänge
// ---------------------------------------------------------

// Handle Datei-Auswahl
function handleFileSelect(e) {
  const files = Array.from(e.target.files);
  handleFiles(files);
  // Reset input, damit derselbe Dateiname erneut ausgewählt werden kann
  e.target.value = "";
}

// Handle Dateien (Upload oder Drag & Drop)
function handleFiles(files) {
  files.forEach(file => {
    // Prüfe, ob Datei bereits hinzugefügt wurde
    const alreadyAdded = emailAttachments.some(att => att.name === file.name && att.size === file.size);
    if (alreadyAdded) {
      console.log(`⚠️ Datei "${file.name}" wurde bereits hinzugefügt`);
      return;
    }
    
    // Füge Datei zur Liste hinzu
    emailAttachments.push({
      file: file,
      name: file.name,
      size: file.size,
      type: file.type,
      id: Date.now() + Math.random() // Eindeutige ID
    });
  });
  
  renderAttachments();
}

// Rendere Anhänge-Liste
function renderAttachments() {
  const attachmentsList = document.getElementById("attachmentsList");
  if (!attachmentsList) return;
  
  attachmentsList.innerHTML = "";
  
  if (emailAttachments.length === 0) {
    attachmentsList.style.display = "none";
    return;
  }
  
  attachmentsList.style.display = "block";
  
  emailAttachments.forEach(attachment => {
    const item = document.createElement("div");
    item.className = "attachment-item";
    item.innerHTML = `
      <div class="attachment-info">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"></path>
          <polyline points="14 2 14 8 20 8"></polyline>
          <line x1="16" y1="13" x2="8" y2="13"></line>
          <line x1="16" y1="17" x2="8" y2="17"></line>
          <polyline points="10 9 9 9 8 9"></polyline>
        </svg>
        <div class="attachment-details">
          <div class="attachment-name">${escapeHtml(attachment.name)}</div>
          <div class="attachment-size">${formatFileSize(attachment.size)}</div>
        </div>
      </div>
      <button type="button" class="attachment-remove" data-attachment-id="${attachment.id}" title="Entfernen">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <line x1="18" y1="6" x2="6" y2="18"></line>
          <line x1="6" y1="6" x2="18" y2="18"></line>
        </svg>
      </button>
    `;
    
    const removeBtn = item.querySelector(".attachment-remove");
    removeBtn.addEventListener("click", () => {
      emailAttachments = emailAttachments.filter(att => att.id !== attachment.id);
      renderAttachments();
    });
    
    attachmentsList.appendChild(item);
  });
}

// Formatiere Dateigröße
function formatFileSize(bytes) {
  if (bytes === 0) return "0 Bytes";
  const k = 1024;
  const sizes = ["Bytes", "KB", "MB", "GB"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return Math.round(bytes / Math.pow(k, i) * 100) / 100 + " " + sizes[i];
}

