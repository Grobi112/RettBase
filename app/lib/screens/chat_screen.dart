import 'dart:async';
import 'dart:typed_data';

import '../utils/voice_file_reader.dart';

import '../services/chat_offline_queue.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import '../theme/app_theme.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import '../services/profile_service.dart';
import 'group_info_screen.dart';
import '../utils/chat_permissions.dart';
import '../utils/visibility_refresh_stub.dart'
    if (dart.library.html) '../utils/visibility_refresh_web.dart' as visibility_refresh;

/// Natives Chat-Modul ÃÂ¢ÃÂÃÂ ohne WebView.
class ChatScreen extends StatefulWidget {
  final String companyId;
  final String? initialChatId;
  final String? title;
  final VoidCallback? onBack;
  final bool hideAppBar;
  final String? userRole;

  /// Wird beim Ãffnen eines Chats aufgerufen – Badge sofort lokal zurücksetzen.
  final void Function(String chatId, int unreadInChat)? onChatOpened;

  const ChatScreen({
    super.key,
    required this.companyId,
    this.initialChatId,
    this.title,
    this.onBack,
    this.hideAppBar = false,
    this.userRole,
    this.onChatOpened,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _chatService = ChatService();
  final _profileService = ProfileService();
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Chat-Listen-State ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  StreamSubscription<List<ChatModel>>? _chatsSub;
  StreamSubscription<List<String>>? _pinnedSub;
  StreamSubscription<List<String>>? _mutedSub;
  List<ChatModel> _chats = [];
  List<String> _pinnedChatIds = [];
  List<String> _mutedChatIds = [];
  bool _chatsLoading = true;
  bool _initialBadgeResetDone = false;

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Nachrichten-State ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  String? _selectedChatId;
  ChatModel? _selectedChat; // gecacht ÃÂ¢ÃÂÃÂ kein zweiter Stream in AppBar nÃÂ¶tig
  StreamSubscription<List<ChatMessage>>? _messagesSub;
  List<ChatMessage> _messages = [];
  List<ChatMessage> _olderMessages = []; // Pagination: ältere Nachrichten
  bool _messagesLoading = false;
  bool _messagesError = false;
  bool _loadingOlderMessages = false;
  bool _hasMoreOlderMessages = true;
  bool _showScrollToBottomButton = false;
  static const double _scrollToBottomThreshold = 120;
  static const double _loadMoreThreshold = 150;

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Web Visibility ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  void Function()? _visibilityCallback;

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ UI-Hilfszustand ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  List<MitarbeiterForChat> _mitarbeiter = [];
  List<Uint8List> _pendingImages = [];
  bool _loadingMitarbeiter = false;
  bool _showNewChatModal = false;
  bool _showNewGroupModal = false;
  final _groupNameController = TextEditingController();
  final List<MitarbeiterForChat> _selectedGroupMembers = [];

  /// Ausstehende Nachrichten (Offline-Queue) fÃÂ¼r den aktuellen Chat.
  final List<Map<String, dynamic>> _pendingMessages = [];

  /// Auswahlmodus fÃÂ¼r Weiterleiten: ausgewählte Nachrichten.
  final Set<String> _selectedMessageIds = {};

  /// Sprachnachricht: Aufnahme-Status.
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordingPath;
  DateTime? _recordingStartTime;

  bool get _hasLeftGroup =>
      _selectedChat?.type == 'group' &&
      (_selectedChat?.leftBy.contains(_chatService.userId) ?? false);

  bool get _canManageGroups => ChatPermissions.canManageGroups(widget.userRole);

  /// Sprachnachricht: Wiedergabe (ein Player fÃÂ¼r alle Nachrichten).
  final AudioPlayer _voicePlayer = AudioPlayer();
  /// Profilbild-Cache: uid -> photoUrl (leer = kein Bild).
  final Map<String, String?> _profileImageCache = {};
 StreamSubscription<Duration>? _positionSub;
 StreamSubscription<PlayerState>? _playerStateSub;
  String? _playingAudioUrl;

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  Timer? _pendingCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscribeToChats();
    if (kIsWeb) _setupVisibilityRefresh();
    _playerStateSub = _voicePlayer.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        if (mounted) setState(() => _playingAudioUrl = null);
      }
    });

    if (widget.initialChatId != null && widget.initialChatId!.isNotEmpty) {
      _selectedChatId = widget.initialChatId;
      _subscribeToMessages(widget.initialChatId!);
    }
    if (!kIsWeb) {
      _startPendingCheckTimer();
      unawaited(_chatService.processOfflineQueue());
    }
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final showBtn = pos.pixels > _scrollToBottomThreshold;
    if (showBtn != _showScrollToBottomButton && mounted) {
      setState(() => _showScrollToBottomButton = showBtn);
    }
    if (_hasMoreOlderMessages && !_loadingOlderMessages && pos.pixels > pos.maxScrollExtent - _loadMoreThreshold) {
      _loadOlderMessages();
    }
  }

  void _startPendingCheckTimer() {
    _pendingCheckTimer?.cancel();
    _pendingCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted || _pendingMessages.isEmpty) return;
      try {
        final inQueue = await ChatOfflineQueue.getAll();
        final ids = inQueue.map((p) => p.id).toSet();
        if (mounted) {
          setState(() {
            _pendingMessages.removeWhere((p) => !ids.contains(p['id']));
          });
        }
      } catch (_) {}
    });
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Chat-Listen-Stream ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  void _subscribeToChats() {
    _pinnedSub = _chatService.streamPinnedChatIds(widget.companyId).listen(
      (ids) {
        if (!mounted) return;
        setState(() => _pinnedChatIds = ids);
      },
    );
    _mutedSub = _chatService.streamMutedChatIds(widget.companyId).listen(
      (ids) {
        if (!mounted) return;
        setState(() => _mutedChatIds = ids);
      },
    );
    _chatsSub = _chatService.streamChats(widget.companyId).listen(
      (chats) {
        if (!mounted) return;
        setState(() {
          _chats = chats;
          _chatsLoading = false;
          // selectedChat synchron aktualisieren ÃÂ¢ÃÂÃÂ kein zweiter Stream nÃÂ¶tig
          if (_selectedChatId != null) {
            _selectedChat = chats.where((c) => c.id == _selectedChatId).firstOrNull;
          }
          // Badge-Reset bei initialChatId: einmalig nach erstem Laden
          if (widget.initialChatId != null && !_initialBadgeResetDone) {
                _initialBadgeResetDone = true;
            final chat = chats.where((c) => c.id == widget.initialChatId).firstOrNull;
            if (chat != null) {
              final uid = _chatService.userId ?? '';
              widget.onChatOpened?.call(chat.id, chat.unreadCount[uid] ?? 0);
            }
          }
        });
      },
      onError: (_) {
        if (mounted) setState(() => _chatsLoading = false);
      },
    );
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Nachrichten-Stream ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  void _subscribeToMessages(String chatId) {
    _messagesSub?.cancel();
    if (mounted) {
      setState(() {
        _messages = [];
        _olderMessages = [];
        _hasMoreOlderMessages = true;
        _messagesLoading = true;
        _messagesError = false;
      });
    }

    _messagesSub = _chatService
        .streamMessages(widget.companyId, chatId)
        .listen(
      (msgs) {
        if (!mounted) return;
        final wasShort = _messages.length < msgs.length;
        // Pending entfernen, wenn Nachricht aus Stream von uns (nach Offline-Versand)
        final currentUid = _chatService.userId;
        if (currentUid != null && _selectedChatId != null) {
          for (final m in msgs) {
            if (m.from != currentUid) continue;
            final hasText = m.text != null && m.text!.trim().isNotEmpty;
            final hasAudio = m.attachments != null &&
                m.attachments!.any((a) => (a.type).startsWith('audio/'));
            if (hasText || hasAudio) {
              final idx = _pendingMessages.indexWhere((p) {
                if (p['chatId'] != _selectedChatId) return false;
                if (hasText) return p['text'] == m.text;
                return p['hasAudio'] == true;
              });
              if (idx >= 0) _pendingMessages.removeAt(idx);
            }
          }
        }
        setState(() {
          _messages = msgs;
          _messagesLoading = false;
        });
        // Auto-Scroll: nur wenn neue Nachricht am Ende ankam
        // oder Chat gerade frisch geÃÂ¶ffnet wurde
        if (wasShort && _scrollController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0, // reverse:true ÃÂ¢ÃÂÃÂ 0 == unterste Nachricht
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
              );
            }
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() {
          _messagesLoading = false;
          _messagesError = true;
        });
      },
    );
  }

  void _unsubscribeFromMessages() {
    _messagesSub?.cancel();
    _messagesSub = null;
    if (mounted) setState(() {
      _messages = [];
      _olderMessages = [];
      _messagesLoading = false;
      _messagesError = false;
    });
  }

  Future<void> _loadOlderMessages() async {
    if (_selectedChatId == null || _loadingOlderMessages || !_hasMoreOlderMessages) return;
    final oldestMsg = _olderMessages.isNotEmpty ? _olderMessages.first : _messages.firstOrNull;
    if (oldestMsg?.createdAt == null) return;
    final oldest = oldestMsg!.createdAt!;
    setState(() => _loadingOlderMessages = true);
    try {
      final result = await _chatService.loadOlderMessages(
        widget.companyId,
        _selectedChatId!,
        oldest,
      );
      if (!mounted) return;
      setState(() {
        _olderMessages = [...result.messages, ..._olderMessages];
        _hasMoreOlderMessages = result.hasMore;
        _loadingOlderMessages = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlderMessages = false);
    }
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Web Tab-Visibility ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  void _setupVisibilityRefresh() {
    _visibilityCallback = () {
      if (_selectedChatId != null && mounted) {
        // Stream lÃÂ¤uft schon ÃÂ¢ÃÂÃÂ nur markChatRead erneut aufrufen
        _chatService.markChatReadPublic(widget.companyId, _selectedChatId!);
      }
    };
    visibility_refresh.setOnVisible(_visibilityCallback!);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _selectedChatId != null && mounted) {
      _chatService.markChatReadPublic(widget.companyId, _selectedChatId!);
    }
  }


  /// Lädt Profilbild eines Nutzers (gecacht). Nutzt ProfileService wie der Profil-Screen.
  Future<void> _loadProfileImage(String uid) async {
    if (_profileImageCache.containsKey(uid)) return;
    _profileImageCache[uid] = null;
    try {
      final profile = await _profileService.loadProfile(
        widget.companyId,
        uid,
        '', // E-Mail optional; Suche erfolgt über uid
      );
      if (profile != null && mounted) {
        final d = profile.data;
        final url = (d['fotoUrl'] ?? d['photoUrl'] ?? d['profilfoto'])?.toString().trim();
        setState(() => _profileImageCache[uid] = (url != null && url.isNotEmpty) ? url : null);
      }
    } catch (_) {}
  }
  @override
  void dispose() {
    // chatActive beim Dispose löschen (App-Kill / Tab wechsel)
    if (_chatService.userId != null && _selectedChatId != null) {
      FirebaseFirestore.instance
          .collection('kunden').doc(widget.companyId)
          .collection('chatActive').doc(_chatService.userId!)
          .delete().catchError((_) {});
    }
    _pendingCheckTimer?.cancel();
    if (_visibilityCallback != null) {
      visibility_refresh.removeOnVisible(_visibilityCallback!);
    }
    WidgetsBinding.instance.removeObserver(this);
    _chatsSub?.cancel();
    _pinnedSub?.cancel();
    _mutedSub?.cancel();
    _messagesSub?.cancel();
    unawaited(_audioRecorder.dispose());
    _voicePlayer.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messageController.dispose();
    _groupNameController.dispose();
    super.dispose();
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Chat auswÃÂÃÂ¤hlen ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  void _selectChat(ChatModel chat) {
    final uid = _chatService.userId ?? '';
    widget.onChatOpened?.call(chat.id, chat.unreadCount[uid] ?? 0);
    setState(() {
      _selectedChatId = chat.id;
      _selectedChat = chat;
      _selectedMessageIds.clear();
    });
    _subscribeToMessages(chat.id);
    // Task 3: Aktiven Chat in Firestore schreiben → Cloud Function spielt keinen Sound
    unawaited(FirebaseFirestore.instance
        .collection('kunden').doc(widget.companyId)
        .collection('chatActive').doc(_chatService.userId ?? 'unknown')
        .set({'chatId': chat.id}));
  }

  void _deselectChat() {
    // Task 3: chatActive löschen beim Verlassen des Chats
    if (_chatService.userId != null) {
      unawaited(FirebaseFirestore.instance
          .collection('kunden').doc(widget.companyId)
          .collection('chatActive').doc(_chatService.userId!)
          .delete().catchError((_) {}));
    }
    setState(() {
      _selectedChatId = null;
      _selectedChat = null;
      _pendingMessages.clear();
      _selectedMessageIds.clear();
    });
    _unsubscribeFromMessages();
  }

  void _openGroupInfo(ChatModel chat) {
    if (chat.type != 'group') return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => GroupInfoScreen(
          companyId: widget.companyId,
          chat: chat,
          initialMuted: _mutedChatIds.contains(chat.id),
          userRole: widget.userRole,
        ),
      ),
    );
  }

  void _showChatContextMenu(ChatModel chat) {
    final isPinned = _pinnedChatIds.contains(chat.id);
    final isMuted = _mutedChatIds.contains(chat.id);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(isPinned ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(isPinned ? 'Von Anpinnen entfernen' : 'Anpinnen'),
              onTap: () {
                Navigator.pop(ctx);
                if (isPinned) {
                  _chatService.unpinChat(widget.companyId, chat.id);
                } else {
                  _chatService.pinChat(widget.companyId, chat.id);
                }
              },
            ),
            ListTile(
              leading: Icon(isMuted ? Icons.notifications_off : Icons.notifications_none),
              title: Text(isMuted ? 'Stummschaltung aufheben' : 'Stumm schalten'),
              onTap: () {
                Navigator.pop(ctx);
                if (isMuted) {
                  _chatService.unmuteChat(widget.companyId, chat.id);
                } else {
                  _chatService.muteChat(widget.companyId, chat.id);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red.shade400),
              title: Text('Chat löschen', style: TextStyle(color: Colors.red.shade400)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteChat(chat);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageContextMenu({
    required ChatMessage? message,
    required Map<String, dynamic>? pending,
    required bool isSent,
    required bool isRead,
  }) {
    final isRealMessage = message != null;
    final canForward = isRealMessage && ((message?.text ?? '').trim().isNotEmpty ||
        (message?.attachments != null && message!.attachments!.isNotEmpty));
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canForward)
              ListTile(
                leading: const Icon(Icons.forward),
                title: const Text('Weiterleiten'),
                onTap: () {
                  Navigator.pop(ctx);
                  if (message != null) {
                    setState(() => _selectedMessageIds.add(message.id));
                  }
                },
              ),
            ListTile(
              leading: Icon(Icons.person_remove_outlined, color: Colors.red.shade400),
              title: Text('Für mich löschen', style: TextStyle(color: Colors.red.shade400)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDeleteMessage(
                  message: message,
                  pending: pending,
                  forEveryone: false,
                );
              },
            ),
            if (isRealMessage && isSent && !isRead)
              ListTile(
                leading: Icon(Icons.delete_forever, color: Colors.red.shade400),
                title: Text('Für alle löschen', style: TextStyle(color: Colors.red.shade400)),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDeleteMessage(
                    message: message,
                    pending: null,
                    forEveryone: true,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _forwardMessages(List<ChatMessage> messages) {
    final toForward = messages.isNotEmpty
        ? messages
        : _messages.where((m) => _selectedMessageIds.contains(m.id)).toList();
    if (toForward.isEmpty) return;
    _showForwardTargetDialog(toForward);
  }

  Future<void> _showForwardTargetDialog(List<ChatMessage> messages) async {
    setState(() => _loadingMitarbeiter = true);
    final mitarbeiter = await _chatService.loadMitarbeiter(widget.companyId);
    if (mounted) setState(() => _loadingMitarbeiter = false);
    if (mitarbeiter.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Mitglieder zum Weiterleiten vorhanden.')),
        );
      }
      return;
    }
    if (!mounted) return;
    final target = await showDialog<MitarbeiterForChat>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Weiterleiten an Mitglied (${messages.length} Nachricht${messages.length == 1 ? '' : 'en'})'),
        content: SizedBox(
          width: 320,
          height: 400,
          child: ListView.builder(
            itemCount: mitarbeiter.length,
            itemBuilder: (_, i) {
              final m = mitarbeiter[i];
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF2F81F7).withOpacity(0.15),
                  child: Text(_getInitials(m.name), style: const TextStyle(fontSize: 14)),
                ),
                title: Text(m.name),
                onTap: () => Navigator.pop(ctx, m),
              );
            },
          ),
        ),
      ),
    );
    if (target != null && mounted) {
      try {
        await _chatService.startDirectChat(widget.companyId, target);
        final chatId = ChatService.getDirectChatId(_chatService.userId!, target.uid);
        await _chatService.forwardMessages(widget.companyId, chatId, messages);
        setState(() => _selectedMessageIds.clear());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${messages.length} Nachricht${messages.length == 1 ? '' : 'en'} an ${target.name} weitergeleitet')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Weiterleiten fehlgeschlagen: $e')),
          );
        }
      }
    }
  }

  Future<void> _confirmDeleteMessage({
    required ChatMessage? message,
    required Map<String, dynamic>? pending,
    required bool forEveryone,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(forEveryone ? 'Für alle löschen?' : 'Für mich löschen?'),
        content: Text(
          forEveryone
              ? 'Die Nachricht wird für alle Teilnehmer entfernt. Dies kann nicht rückgängig gemacht werden.'
              : 'Die Nachricht wird nur für dich entfernt.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Löschen', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted || _selectedChatId == null) return;
    if (pending != null) {
      final id = pending['id'] as String?;
      if (id != null && id.startsWith('pending-')) {
        unawaited(ChatOfflineQueue.remove(id));
      }
      setState(() => _pendingMessages.removeWhere((p) => p['id'] == pending['id']));
    } else if (message != null) {
      if (forEveryone) {
        await _chatService.deleteMessageForEveryone(
          widget.companyId,
          _selectedChatId!,
          message.id,
        );
      } else {
        await _chatService.deleteMessageForMe(
          widget.companyId,
          _selectedChatId!,
          message.id,
        );
      }
    }
  }

  Future<void> _confirmDeleteChat(ChatModel chat) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Chat löschen?'),
        content: const Text('Der Chat wird nur für dich entfernt.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Abbrechen'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Löschen', style: TextStyle(color: Colors.red.shade400)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _chatService.deleteChatForMe(widget.companyId, chat.id);
      if (mounted && _selectedChatId == chat.id) _deselectChat();
    }
  }

  // Hilfsmethoden ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  String _chatDisplayName(ChatModel chat) {
    if (chat.name != null && chat.name!.isNotEmpty) return chat.name!;
    final uid = _chatService.userId ?? '';
    final others = chat.participantNames.where((p) => p.uid != uid).toList();
    return others.map((p) => p.name).where((n) => n.isNotEmpty).join(', ').isNotEmpty
        ? others.map((p) => p.name).where((n) => n.isNotEmpty).join(', ')
        : 'Chat';
  }

  /// Chats sortiert: angepinnte oben (in Pin-Reihenfolge), Rest nach lastMessageAt.
  List<ChatModel> get _sortedChats {
    final pinned = _pinnedChatIds
        .map((id) => _chats.where((c) => c.id == id).firstOrNull)
        .whereType<ChatModel>()
        .toList();
    final rest = _chats.where((c) => !_pinnedChatIds.contains(c.id)).toList();
    rest.sort((a, b) => (b.lastMessageAt ?? DateTime(0)).compareTo(a.lastMessageAt ?? DateTime(0)));
    return [...pinned, ...rest];
  }

  /// Kombiniert ältere Nachrichten, Firestore-Nachrichten und ausstehende (Offline-Queue), sortiert nach Zeit.
  /// Wenn Nutzer Gruppe verlassen hat: nur Nachrichten bis leftAt anzeigen.
  List<({ChatMessage? message, Map<String, dynamic>? pending})> _getDisplayMessages() {
    final uid = _chatService.userId;
    final leftAt = _selectedChat?.type == 'group' && uid != null
        ? _selectedChat!.leftAt[uid]
        : null;

    bool includeMessage(ChatMessage? m, Map<String, dynamic>? p) {
      if (leftAt == null) return true;
      final createdAt = m?.createdAt ?? (p?['createdAt'] as DateTime?);
      if (createdAt == null) return false;
      return !createdAt.isAfter(leftAt);
    }

    final pendingForChat = _pendingMessages
        .where((p) => p['chatId'] == _selectedChatId)
        .map((p) => (message: null as ChatMessage?, pending: Map<String, dynamic>.from(p)))
        .where((x) => includeMessage(null, x.pending))
        .toList();
    final fromFirestore = [
      ..._olderMessages.map((m) => (message: m, pending: null as Map<String, dynamic>?)),
      ..._messages.map((m) => (message: m, pending: null as Map<String, dynamic>?)),
    ].where((x) => includeMessage(x.message, null)).toList();
    final combined = [...fromFirestore, ...pendingForChat];
    combined.sort((a, b) {
      final at = a.message?.createdAt ?? (a.pending!['createdAt'] as DateTime);
      final bt = b.message?.createdAt ?? (b.pending!['createdAt'] as DateTime);
      return at.compareTo(bt);
    });
    return combined;
  }

  /// PrÃÂ¼ft, ob die Nachricht von allen EmpfÃÂ¤ngern gelesen wurde.
  bool _isMessageRead(ChatMessage? m) {
    if (m == null) return false;
    final uid = _chatService.userId;
    final chat = _selectedChat;
    if (uid == null || chat == null) return false;
    final recipients = chat.participants.where((p) => p != uid).toList();
    return recipients.every((r) {
      final lr = chat.lastReadAt[r];
      if (lr == null || m.createdAt == null) return false;
      final lrAt = lr is Timestamp ? lr.toDate() : (lr is DateTime ? lr : null);
      return lrAt != null && !m.createdAt!.isAfter(lrAt);
    });
  }

  /// WhatsApp-Style: 1 Haken=verschickt, 2 grau=zugestellt, 2 blau=gelesen.
  Widget _buildDeliveryStatus(bool isSent, ChatMessage? m, bool isPending) {
    if (!isSent || isPending || m == null) {
      if (isPending) {
        return Icon(Icons.schedule, size: 12, color: Colors.white.withOpacity(0.65));
      }
      return const SizedBox.shrink();
    }
    final uid = _chatService.userId;
    final chat = _selectedChat;
    if (uid == null || chat == null) {
      return Icon(Icons.done, size: 14, color: Colors.white.withOpacity(0.65));
    }
    final recipients = chat.participants.where((p) => p != uid).toList();
    final delivered = recipients.every((r) => m.deliveredTo.contains(r));
    final read = recipients.every((r) {
      final lr = chat.lastReadAt[r];
      if (lr == null || m.createdAt == null) return false;
      final lrAt = lr is Timestamp ? lr.toDate() : (lr is DateTime ? lr : null);
      return lrAt != null && !m.createdAt!.isAfter(lrAt);
    });
    final color = read ? Colors.blue.shade200 : Colors.white.withOpacity(0.65);
    // 1 Haken (grau) = gesendet, 2 Haken (grau) = zugestellt, 2 Haken (blau) = gelesen
    return Icon(
      (delivered || read) ? Icons.done_all : Icons.done,
      size: 14,
      color: color,
    );
  }

  String _formatTime(DateTime? d) {
    if (d == null) return '';
    final now = DateTime.now();
    if (d.day == now.day && d.month == now.month && d.year == now.year) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime d) {
    final now = DateTime.now();
    if (d.day == now.day && d.month == now.month && d.year == now.year) return 'Heute';
    final yesterday = now.subtract(const Duration(days: 1));
    if (d.day == yesterday.day && d.month == yesterday.month && d.year == yesterday.year) {
      return 'Gestern';
    }
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  String _getInitials(String name) {
    final s = name.split(' ').map((p) => p.isNotEmpty ? p[0] : '').join('').toUpperCase();
    return s.length > 2 ? s.substring(0, 2) : (s.isEmpty ? '?' : s);
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Mitarbeiter laden ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  Future<void> _loadMitarbeiter() async {
    setState(() => _loadingMitarbeiter = true);
    try {
      final list = await _chatService.loadMitarbeiter(widget.companyId);
      if (mounted) setState(() {
        _mitarbeiter = list;
        _loadingMitarbeiter = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMitarbeiter = false);
    }
  }

  Future<void> _openNewChat() async {
    _groupNameController.clear();
    _selectedGroupMembers.clear();
    setState(() {
      _showNewGroupModal = false;
      _showNewChatModal = true;
    });
    await _loadMitarbeiter();
  }

  Future<void> _openNewGroup() async {
    _groupNameController.clear();
    _selectedGroupMembers.clear();
    setState(() {
      _showNewChatModal = false;
      _showNewGroupModal = true;
    });
    await _loadMitarbeiter();
  }

  void _startDirectChat(MitarbeiterForChat m) async {
    await _chatService.startDirectChat(widget.companyId, m);
    if (!mounted) return;
    final chatId = ChatService.getDirectChatId(_chatService.userId!, m.uid);
    // Warte kurz bis streamChats das neue Dokument liefert
    final chat = _chats.where((c) => c.id == chatId).firstOrNull;
    setState(() => _showNewChatModal = false);
    if (chat != null) {
      _selectChat(chat);
    } else {
      // Noch nicht im Stream ÃÂ¢ÃÂÃÂ direkt setzen, Stream holt es nach
      setState(() {
        _selectedChatId = chatId;
        _selectedChat = null;
      });
      _subscribeToMessages(chatId);
    }
  }

  void _createGroup() async {
    final name = _groupNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Gruppenname eingeben.')),
      );
      return;
    }
    if (_selectedGroupMembers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte mindestens einen Teilnehmer auswählen.')),
      );
      return;
    }
    try {
      final chatId = await _chatService.createGroupChat(
        widget.companyId, name, _selectedGroupMembers,
      );
      if (!mounted) return;
      setState(() => _showNewGroupModal = false);
      setState(() {
        _selectedChatId = chatId;
        _selectedChat = null;
      });
      _subscribeToMessages(chatId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e')));
      }
    }
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Bilder ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isEmpty || !mounted) return;
    final bytes = <Uint8List>[];
    for (final x in images) {
      final b = await x.readAsBytes();
      if (b.length <= 10 * 1024 * 1024) bytes.add(b);
    }
    if (mounted) setState(() => _pendingImages.addAll(bytes));
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Nachricht senden ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty && _pendingImages.isEmpty) return;
    if (_selectedChatId == null || _hasLeftGroup) return;

    _messageController.clear();
    final images = List<Uint8List>.from(_pendingImages);
    setState(() => _pendingImages = []);

    try {
      final resultId = await _chatService.sendMessageOrQueue(
        widget.companyId,
        _selectedChatId!,
        text,
        imageBytes: images.isNotEmpty ? images : null,
        imageNames: images.asMap().entries.map((e) => 'image_${e.key}.jpg').toList(),
      );
      if (resultId.startsWith('pending-') && mounted) {
        setState(() {
          _pendingMessages.add({
            'id': resultId,
            'chatId': _selectedChatId,
            'text': text,
            'hasImages': images.isNotEmpty,
            'hasAudio': false,
            'createdAt': DateTime.now(),
          });
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Senden fehlgeschlagen: $e')),
        );
      }
    }
  }

  Future<void> _startVoiceRecording() async {
    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sprachnachrichten nur in der App verfÃÂ¼gbar')),
        );
      }
      return;
    }
    if (!await _audioRecorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofon-Berechtigung erforderlich')),
        );
      }
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      _recordingPath = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, sampleRate: 44100),
        path: _recordingPath!,
      );
      if (mounted) setState(() {
        _isRecording = true;
        _recordingStartTime = DateTime.now();
      });
    } catch (e) {
      if (mounted) setState(() => _isRecording = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Aufnahme fehlgeschlagen: $e')),
        );
      }
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isRecording) return;
    try {
      await _audioRecorder.cancel();
      if (mounted) setState(() {
        _isRecording = false;
        _recordingStartTime = null;
      });
      _recordingPath = null;
    } catch (_) {
      if (mounted) setState(() {
        _isRecording = false;
        _recordingStartTime = null;
      });
    }
  }

  Future<void> _stopAndSendVoice() async {
    if (!_isRecording) {
      // Aufnahme wurde nie gestartet (z.B. zu schnell losgelassen)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mikrofon lÃÂ¤nger gedrÃÂ¼ckt halten (mind. 0,5 s).')),
        );
      }
      return;
    }
    try {
      final startTime = _recordingStartTime;
      final savedPath = _recordingPath; // Fallback falls stop() null liefert
      final pathFromStop = await _audioRecorder.stop();
      if (mounted) setState(() {
        _isRecording = false;
        _recordingStartTime = null;
      });
      _recordingPath = null;
      // record 6.x: stop() kann null liefern; Fallback auf den an start() ÃÂ¼bergebenen Pfad
      String? path = pathFromStop;
      if (path == null || path.isEmpty) path = savedPath;
      if (path == null || path.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aufnahme konnte nicht gespeichert werden. Bitte erneut versuchen.')),
          );
        }
        return;
      }
      // file:// URL ggf. bereinigen (iOS kann URL zurÃÂ¼ckgeben)
      if (path.startsWith('file://')) path = path.substring(7);
      if (_selectedChatId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bitte zuerst einen Chat auswählen.')),
          );
        }
        return;
      }
      // Zu kurze Aufnahme (< 0,5 s) verwerfen
      final duration = startTime != null
          ? DateTime.now().difference(startTime).inMilliseconds
          : 0;
      if (duration < 500) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aufnahme zu kurz. Mindestens 0,5 Sekunden halten.')),
          );
        }
        return;
      }
      final bytes = await readVoiceFileBytes(path);
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Audiodatei konnte nicht gelesen werden. Bitte erneut aufnehmen.')),
          );
        }
        return;
      }
      final resultId = await _chatService.sendMessageOrQueue(
        widget.companyId,
        _selectedChatId!,
        '',
        audioBytes: [bytes],
        audioNames: ['voice.m4a'],
      );
      if (resultId.startsWith('pending-') && mounted) {
        if (mounted) setState(() {
          _pendingMessages.add({
            'id': resultId,
            'chatId': _selectedChatId,
            'text': '',
            'hasImages': false,
            'hasAudio': true,
            'createdAt': DateTime.now(),
          });
        });
      }
    } catch (e) {
      if (mounted) {
        if (mounted) setState(() => _isRecording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sprachnachricht fehlgeschlagen: $e')),
        );
      }
    }
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ AppBar ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  /// Designausnahme Chat: Dunkler Header wie Gruppeninfo, [<] für Rückkehr.
  static const _chatHeaderBg = Color(0xFF161B22);
  static const _chatHeaderFg = Color(0xFFE6EDF3);

  PreferredSizeWidget _buildAppBar(bool isNarrow, VoidCallback onBack) {
    // Unterhaltung: Gruppeninfo-Style, Pfeil zurück zu Chats
    if (_selectedChatId != null && _selectedChat != null) {
      final chat = _selectedChat!;
      final isGroup = chat.type == 'group';
      final groupImageUrl = isGroup ? chat.groupImageUrl : null;
      String? photoUrl;
      if (!isGroup) {
        final otherUid = chat.participants
            .firstWhere((p) => p != _chatService.userId, orElse: () => '');
        if (otherUid.isNotEmpty) {
          Future.microtask(() => _loadProfileImage(otherUid));
          photoUrl = _profileImageCache[otherUid];
        }
      }
      final avatarUrl = groupImageUrl ?? photoUrl;
      final title = _chatDisplayName(chat);
      final titleWidget = Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: (avatarUrl == null || avatarUrl.isEmpty)
                  ? LinearGradient(
                      colors: [
                        const Color(0xFF388BFD).withOpacity(0.8),
                        const Color(0xFF2F81F7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? Image.network(
                    avatarUrl,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Text(
                      _getInitials(title),
                      style: const TextStyle(
                        color: Color(0xFFE6EDF3),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  )
                : Text(
                    _getInitials(title),
                    style: const TextStyle(
                      color: Color(0xFFE6EDF3),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: isGroup
                ? GestureDetector(
                    onTap: () => _openGroupInfo(chat),
                    behavior: HitTestBehavior.opaque,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: _chatHeaderFg,
                          fontWeight: FontWeight.w600,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                : Text(
                    title,
                    style: const TextStyle(
                      color: _chatHeaderFg,
                      fontWeight: FontWeight.w600,
                      fontSize: 18,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
        ],
      );
      return AppBar(
        backgroundColor: _chatHeaderBg,
        foregroundColor: _chatHeaderFg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _deselectChat,
          color: _chatHeaderFg,
        ),
        title: titleWidget,
        elevation: 0,
        scrolledUnderElevation: 0,
      );
    }
    // Ladezustand (Chat gewählt, aber noch nicht geladen)
    if (_selectedChatId != null) {
      return AppBar(
        backgroundColor: _chatHeaderBg,
        foregroundColor: _chatHeaderFg,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _deselectChat,
          color: _chatHeaderFg,
        ),
        title: const Text(
          'Chat',
          style: TextStyle(
            color: _chatHeaderFg,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        elevation: 0,
        scrolledUnderElevation: 0,
      );
    }
    // Chat-Liste: [<] Chats, Rückkehr zum Dashboard
    return AppBar(
      backgroundColor: _chatHeaderBg,
      foregroundColor: _chatHeaderFg,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: onBack,
        color: _chatHeaderFg,
        tooltip: 'Zurück zum Dashboard',
      ),
      title: const Text(
        'Chats',
        style: TextStyle(
          color: _chatHeaderFg,
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
      ),
      actions: [
        _buildAppBarIconAction(Icons.edit_square, 'Neuer Chat', _openNewChat),
        if (_canManageGroups) ...[
          const SizedBox(width: 4),
          _buildAppBarIconAction(Icons.group_add_outlined, 'Neue Gruppe', _openNewGroup),
        ],
        const SizedBox(width: 8),
      ],
      elevation: 0,
      scrolledUnderElevation: 0,
    );
  }

  Widget _buildAppBarIconAction(IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 22),
        onPressed: onPressed,
        color: _chatHeaderFg,
      ),
    );
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Build ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 600;
    final onBack = widget.onBack ?? () => Navigator.of(context).pop();

    final scaffold = Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: _buildAppBar(isNarrow, onBack),
      body: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: isNarrow
                ? _selectedChatId == null
                    ? _buildChatList(isNarrow)
                    : _buildMessageView(isNarrow)
                : Row(
                    children: [
                      AnimatedContainer(
                        width: 320,
                        duration: const Duration(milliseconds: 200),
                        child: _buildChatList(isNarrow),
                      ),
                      Expanded(
                        child: _selectedChatId == null
                            ? _buildNoChatSelected(isNarrow)
                            : _buildMessageView(isNarrow),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );

    final content = Stack(
      children: [
        scaffold,
        if (_showNewChatModal) _buildNewChatModal(),
        if (_showNewGroupModal) _buildNewGroupModal(),
      ],
    );

    if (widget.hideAppBar && widget.onBack != null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_selectedChatId != null) {
            _deselectChat();
          } else {
            widget.onBack!();
          }
        },
        child: content,
      );
    }
    return content;
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Chat-Liste ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  Widget _buildChatList(bool isNarrow) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border(right: BorderSide(color: const Color(0xFF1C2333), width: 1)),
      ),
      child: Column(
        children: [
          if (!isNarrow)
          // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Header ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 10, 12),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              border: Border(bottom: BorderSide(color: const Color(0xFF30363D))),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Chats',
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFE6EDF3),
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                _buildIconAction(Icons.edit_square, 'Neuer Chat', _openNewChat),
                if (_canManageGroups) ...[
                  const SizedBox(width: 6),
                  _buildIconAction(Icons.group_add_outlined, 'Neue Gruppe', _openNewGroup),
                ],
                const SizedBox(width: 2),
              ],
            ),
          ),
          // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Liste ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
          Expanded(
            child: _chatsLoading
                ? const Center(child: CircularProgressIndicator(color: const Color(0xFF2F81F7)))
                : _chats.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 72,
                                height: 72,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      const Color(0xFF2F81F7).withOpacity(0.12),
                                      const Color(0xFF2F81F7).withOpacity(0.06),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(Icons.forum_outlined,
                                    size: 32, color: const Color(0xFF2F81F7).withOpacity(0.65)),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Noch keine Chats',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: const Color(0xFFCDD5DF),
                                  letterSpacing: -0.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Starte einen neuen Chat oder\nerstelle eine Gruppe.',
                                style: TextStyle(fontSize: 13, color: const Color(0xFF8B949E), height: 1.5),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _sortedChats.length,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemBuilder: (_, i) {
                          final chat = _sortedChats[i];
                          var unread = chat.unreadCount[_chatService.userId] ?? 0;
                          if (unread == 0 &&
                              chat.lastMessageFrom != null &&
                              chat.lastMessageFrom != _chatService.userId &&
                              chat.lastMessageAt != null) {
                            final lastRead = chat.lastReadAt[_chatService.userId];
                            DateTime? lastReadAt;
                            if (lastRead is Timestamp) lastReadAt = lastRead.toDate();
                            if (lastRead is DateTime) lastReadAt = lastRead;
                            if (lastReadAt == null || chat.lastMessageAt!.isAfter(lastReadAt)) {
                              unread = 1;
                            }
                          }
                          final hasUnread = unread > 0;
                          final name = _chatDisplayName(chat);
                          final isSelected = _selectedChatId == chat.id;

                          return Dismissible(
                            key: Key(chat.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red.shade400,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.delete_outline, color: Colors.white),
                            ),
                            confirmDismiss: (_) async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16)),
                                  title: const Text('Chat löschen?'),
                                  content: const Text('Der Chat wird nur für dich entfernt.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: const Text('Abbrechen'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: Text('Löschen',
                                          style: TextStyle(color: Colors.red.shade400)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await _chatService.deleteChatForMe(widget.companyId, chat.id);
                                if (mounted && _selectedChatId == chat.id) _deselectChat();
                                return true;
                              }
                              return false;
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF2F81F7).withOpacity(0.08)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(14),
                                border: isSelected
                                    ? Border.all(color: const Color(0xFF2F81F7).withOpacity(0.15), width: 1)
                                    : null,
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () => _selectChat(chat),
                                onLongPress: () => _showChatContextMenu(chat),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 11),
                                  child: Row(
                                    children: [
                                      // Avatar
                                            Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Builder(
                                                  builder: (ctx) {
                                                    final isGroup = chat.type == 'group';
                                                    final groupImageUrl = isGroup ? chat.groupImageUrl : null;
                                                    String? photoUrl;
                                                    if (!isGroup) {
                                                      final otherUid = chat.participants
                                                          .firstWhere((p) => p != _chatService.userId, orElse: () => '');
                                                      if (otherUid.isNotEmpty) {
                                                        Future.microtask(() => _loadProfileImage(otherUid));
                                                        photoUrl = _profileImageCache[otherUid];
                                                      }
                                                    }
                                                    final avatarUrl = groupImageUrl ?? photoUrl;
                                                    return Container(
                                                      width: 48,
                                                      height: 48,
                                                      decoration: BoxDecoration(
                                                        gradient: (avatarUrl == null || avatarUrl.isEmpty)
                                                          ? LinearGradient(
                                                            colors: [
                                                              const Color(0xFF388BFD).withOpacity(0.8),
                                                              const Color(0xFF2F81F7),
                                                            ],
                                                            begin: Alignment.topLeft,
                                                            end: Alignment.bottomRight,
                                                          )
                                                          : null,
                                                        shape: BoxShape.circle,
                                                        boxShadow: [
                                                          BoxShadow(
                                                            color: const Color(0xFF2F81F7).withOpacity(0.2),
                                                            blurRadius: 8,
                                                            offset: const Offset(0, 3),
                                                          ),
                                                        ],
                                                      ),
                                                      clipBehavior: Clip.antiAlias,
                                                      alignment: Alignment.center,
                                                      child: (avatarUrl != null && avatarUrl.isNotEmpty)
                                                        ? Image.network(avatarUrl, width: 48, height: 48, fit: BoxFit.cover,
                                                          errorBuilder: (_, __, ___) => Text(_getInitials(name),
                                                          style: const TextStyle(color: const Color(0xFF161B22),
                                                          fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 0.5)),
                                                        )
                                                        : Text(_getInitials(name),
                                                        style: const TextStyle(color: const Color(0xFF161B22),
                                                          fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 0.5)),
                                                    );
                                                  },
                                                ),
                                                if (hasUnread)
                                                  Positioned(
                                                    top: -2,
                                                    right: -2,
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF2F81F7),
                                                        borderRadius: BorderRadius.circular(10),
                                                        border: Border.all(color: const Color(0xFF161B22), width: 1.5),
                                                      ),
                                                      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                                      child: Center(
                                                        child: Text(
                                                          '${unread > 99 ? "99+" : unread}',
                                                          style: const TextStyle(color: const Color(0xFF161B22),
                                                            fontSize: 9, fontWeight: FontWeight.w800),
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                      const SizedBox(width: 13),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    name,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontWeight: hasUnread
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                      fontSize: 15,
                                                      color: const Color(0xFFE6EDF3),
                                                      letterSpacing: -0.1,
                                                    ),
                                                  ),
                                                ),
                                                if (_pinnedChatIds.contains(chat.id))
                                                  Padding(
                                                    padding: const EdgeInsets.only(right: 4),
                                                    child: Icon(
                                                      Icons.push_pin,
                                                      size: 14,
                                                      color: const Color(0xFF6E7681),
                                                    ),
                                                  ),
                                                if (_mutedChatIds.contains(chat.id))
                                                  Padding(
                                                    padding: const EdgeInsets.only(right: 4),
                                                    child: Icon(
                                                      Icons.notifications_off,
                                                      size: 14,
                                                      color: const Color(0xFF6E7681),
                                                    ),
                                                  ),
                                                const SizedBox(width: 6),
                                                Text(
                                                  _formatTime(chat.lastMessageAt),
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: hasUnread
                                                        ? const Color(0xFF2F81F7)
                                                        : const Color(0xFF6E7681),
                                                    fontWeight: hasUnread
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              chat.lastMessageText ?? 'Noch keine Nachrichten',
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: hasUnread
                                                    ? const Color(0xFFE6EDF3)
                                                    : const Color(0xFF6E7681),
                                                fontWeight: hasUnread
                                                    ? FontWeight.w500
                                                    : FontWeight.w400,
                                                height: 1.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconAction(IconData icon, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF2F81F7).withOpacity(0.07),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: const Color(0xFF2F81F7)),
        ),
      ),
    );
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Kein Chat gewÃÂÃÂ¤hlt ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  Widget _buildNoChatSelected(bool isNarrow) {
    return Container(
      color: const Color(0xFF0D1117),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF2F81F7).withOpacity(0.12),
                    const Color(0xFF2F81F7).withOpacity(0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.chat_bubble_outline_rounded,
                  size: 40, color: const Color(0xFF2F81F7).withOpacity(0.55)),
            ),
            const SizedBox(height: 22),
            Text(
              'Wähle einen Chat aus',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFFCDD5DF),
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'oder starte eine neue Unterhaltung.',
              style: const TextStyle(color: Color(0xFF8B949E), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _openNewChat,
                  icon: const Icon(Icons.edit_square, size: 17),
                  label: const Text('Neuer Chat'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                if (_canManageGroups)
                  OutlinedButton.icon(
                    onPressed: _openNewGroup,
                    icon: const Icon(Icons.group_add_outlined, size: 17),
                    label: const Text('Neue Gruppe'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: const Color(0xFF2F81F7).withOpacity(0.35)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Nachrichtenansicht ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  Widget _buildMessageView(bool isNarrow) {
    if (_messagesError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                'Nachrichten konnten nicht geladen werden.',
                style: TextStyle(color: const Color(0xFF8B949E)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => _subscribeToMessages(_selectedChatId!),
                icon: const Icon(Icons.refresh),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Chat-Header ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
        if (_selectedChat != null && !isNarrow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              border: Border(bottom: BorderSide(color: const Color(0xFF30363D))),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Builder(
                  builder: (_) {
                    final chat = _selectedChat!;
                    final isGroup = chat.type == 'group';
                    final groupImageUrl = isGroup ? chat.groupImageUrl : null;
                    String? photoUrl;
                    if (!isGroup) {
                      final otherUid = chat.participants
                          .firstWhere((p) => p != _chatService.userId, orElse: () => '');
                      if (otherUid.isNotEmpty) {
                        Future.microtask(() => _loadProfileImage(otherUid));
                        photoUrl = _profileImageCache[otherUid];
                      }
                    }
                    final avatarUrl = groupImageUrl ?? photoUrl;
                    final avatar = Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: (avatarUrl == null || avatarUrl.isEmpty)
                            ? LinearGradient(
                                colors: [const Color(0xFF388BFD).withOpacity(0.8), const Color(0xFF2F81F7)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF2F81F7).withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      alignment: Alignment.center,
                      child: (avatarUrl != null && avatarUrl.isNotEmpty)
                          ? Image.network(avatarUrl, width: 40, height: 40, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Text(
                                _getInitials(_chatDisplayName(chat)),
                                style: const TextStyle(
                                  color: Color(0xFF161B22),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                ),
                              ))
                          : Text(
                              _getInitials(_chatDisplayName(chat)),
                              style: const TextStyle(
                                color: Color(0xFF161B22),
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: 0.5,
                              ),
                            ),
                    );
                    return avatar;
                  },
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: _selectedChat!.type == 'group'
                      ? GestureDetector(
                          onTap: () => _openGroupInfo(_selectedChat!),
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _chatDisplayName(_selectedChat!),
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: const Color(0xFFE6EDF3),
                                  letterSpacing: -0.2,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _chatDisplayName(_selectedChat!),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: const Color(0xFFE6EDF3),
                                letterSpacing: -0.2,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        //Â¢ÃÂÃÂÃÂ¢ÃÂÃÂ Nachrichten ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
        Expanded(
          child: Stack(
            children: [
              Container(
                color: const Color(0xFF0D1117),
                child: _messagesLoading
                ? const Center(child: CircularProgressIndicator(color: const Color(0xFF2F81F7)))
                : _messages.isEmpty && _pendingMessages.where((p) => p['chatId'] == _selectedChatId).isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF2F81F7).withOpacity(0.1),
                                    const Color(0xFF2F81F7).withOpacity(0.04),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.waving_hand_outlined,
                                  size: 28, color: const Color(0xFF2F81F7).withOpacity(0.3)),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'Noch keine Nachrichten',
                              style: TextStyle(
                                color: const Color(0xFF8B949E),
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Schreib als Erstes!',
                              style: TextStyle(fontSize: 13, color: const Color(0xFF6E7681)),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        reverse: true,
                        itemCount: () {
                          final items = _getDisplayMessages();
                          return items.length + (_loadingOlderMessages ? 1 : 0);
                        }(),
                        itemBuilder: (_, i) {
                          final items = _getDisplayMessages();
                          if (_loadingOlderMessages && i == items.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2F81F7)),
                                ),
                              ),
                            );
                          }
                          final item = items[items.length - 1 - i];
                          final m = item.message;
                          final pending = item.pending;
                          final text = m?.text ?? (pending?['text'] as String? ?? '');
                          final createdAt = m?.createdAt ?? (pending?['createdAt'] as DateTime?);
                          final isSent = m != null ? m.from == _chatService.userId : true;
                          final isPending = pending != null;
                          // Datum-Trennlinie
                          final showDate = i == items.length - 1 ||
                              (items[items.length - 2 - i].message?.createdAt?.day ??
                                  (items[items.length - 2 - i].pending?['createdAt'] as DateTime?)?.day) !=
                                  createdAt?.day;
                          return Column(
                            crossAxisAlignment:
                                isSent ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              if (showDate && createdAt != null)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF21262D),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        _formatDate(createdAt),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: const Color(0xFF8B949E),
                                            fontWeight: FontWeight.w500,
                                            letterSpacing: 0.2),
                                      ),
                                    ),
                                  ),
                                ),
                              GestureDetector(
                                onTap: () {
                                  if (_selectedMessageIds.isNotEmpty && m != null) {
                                    final canFwd = ((m.text ?? '').trim().isNotEmpty ||
                                        (m.attachments != null && m.attachments!.isNotEmpty));
                                    if (canFwd) {
                                      if (mounted) setState(() {
                                        if (_selectedMessageIds.contains(m.id)) {
                                          _selectedMessageIds.remove(m.id);
                                        } else {
                                          _selectedMessageIds.add(m.id);
                                        }
                                      });
                                    }
                                  }
                                },
                                onLongPress: () => _showMessageContextMenu(
                                  message: m,
                                  pending: pending,
                                  isSent: isSent,
                                  isRead: _isMessageRead(m),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.max,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    if (_selectedMessageIds.isNotEmpty && m != null) ...[
                                      SizedBox(
                                        width: 32,
                                        child: Center(
                                          child: GestureDetector(
                                            onTap: () {
                                              final canFwd = ((m.text ?? '').trim().isNotEmpty ||
                                                  (m.attachments != null && m.attachments!.isNotEmpty));
                                              if (canFwd) {
                                                if (mounted) setState(() {
                                                  if (_selectedMessageIds.contains(m.id)) {
                                                    _selectedMessageIds.remove(m.id);
                                                  } else {
                                                    _selectedMessageIds.add(m.id);
                                                  }
                                                });
                                              }
                                            },
                                            child: Container(
                                              width: 24,
                                              height: 24,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: _selectedMessageIds.contains(m.id)
                                                    ? const Color(0xFF2F81F7)
                                                    : Colors.transparent,
                                                border: Border.all(
                                                  color: _selectedMessageIds.contains(m.id)
                                                      ? const Color(0xFF2F81F7)
                                                      : Colors.grey.shade400,
                                                  width: 2,
                                                ),
                                              ),
                                              child: _selectedMessageIds.contains(m.id)
                                                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                                                  : null,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                    Expanded(
                                      child: Align(
                                        alignment: isSent ? Alignment.centerRight : Alignment.centerLeft,
                                        child: Container(
                                          margin: EdgeInsets.only(
                                            bottom: 4,
                                            left: isSent && _selectedMessageIds.isEmpty ? 60 : 0,
                                            right: isSent ? 0 : (_selectedMessageIds.isEmpty ? 60 : 0),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 10),
                                          constraints: BoxConstraints(
                                            maxWidth: MediaQuery.sizeOf(context).width * 0.72,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSent
                                                ? const Color(0xFF1E40AF)
                                                : const Color(0xFF21262D),
                                            borderRadius: BorderRadius.only(
                                      topLeft: const Radius.circular(20),
                                      topRight: const Radius.circular(20),
                                      bottomLeft: Radius.circular(isSent ? 20 : 5),
                                      bottomRight: Radius.circular(isSent ? 5 : 20),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isSent
                                            ? const Color(0xFF2F81F7).withOpacity(0.15)
                                            : Colors.black.withOpacity(0.06),
                                        blurRadius: isSent ? 10 : 6,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (text.isNotEmpty)
                                        Text(
                                          text,
                                          style: TextStyle(
                                            color: isSent ? Colors.white : const Color(0xFFE6EDF3),
                                            fontSize: 14.5,
                                            height: 1.45,
                                          ),
                                        ),
                                      if (m?.attachments != null)
                                        for (final a in m!.attachments!)
                                          if ((a.type).startsWith('image/'))
                                            Padding(
                                              padding: const EdgeInsets.only(top: 6),
                                              child: GestureDetector(
                                                onTap: () {},
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(10),
                                                  child: Image.network(
                                                    a.url,
                                                    fit: BoxFit.contain,
                                                    height: 150,
                                                  ),
                                                ),
                                              ),
                                            )
                                          else if ((a.type).startsWith('audio/'))
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: _VoiceMessagePlayer(
                                                url: a.url,
                                                isSent: isSent,
                                                player: _voicePlayer,
                                                playingUrl: _playingAudioUrl,
                                                onPlaybackStateChanged: (url) {
                                                  if (mounted) setState(() => _playingAudioUrl = url);
                                                },
                                                onError: () {
                                                  if (mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(content: Text('Sprachnachricht konnte nicht abgespielt werden')),
                                                    );
                                                  }
                                                },
                                              ),
                                            )
                                          else
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Text(
                                                'Ã°ÂÂÂ ${a.name}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: isSent
                                                      ? Colors.white70
                                                      : const Color(0xFFCDD5DF),
                                                ),
                                              ),
                                            ),
                                      if (pending != null && (pending['hasImages'] == true))
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Ã°ÂÂÂ Bild(er) werden bei Netzverbindung gesendet',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isSent
                                                  ? Colors.white70
                                                  : Colors.grey[600],
                                            ),
                                          ),
                                        ),
                                      if (pending != null && (pending['hasAudio'] == true))
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Ã°ÂÂÂ¤ Sprachnachricht wird bei Netzverbindung gesendet',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isSent
                                                  ? Colors.white70
                                                  : Colors.grey[600],
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _formatTime(createdAt),
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isSent
                                                    ? Colors.white.withOpacity(0.65)
                                                    : const Color(0xFF6E7681),
                                                fontWeight: FontWeight.w400,
                                              ),
                                            ),
                                            if (isSent) ...[
                                              const SizedBox(width: 4),
                                              _buildDeliveryStatus(isSent, m, isPending),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
              ),
              if (_showScrollToBottomButton)
                Positioned(
                  bottom: 90,
                  right: 16,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: InkWell(
                      onTap: () {
                        if (_scrollController.hasClients) {
                          _scrollController.animateTo(
                            0,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                          setState(() => _showScrollToBottomButton = false);
                        }
                      },
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Transform.rotate(
                          angle: 1.5708,
                          child: Icon(Icons.chevron_right, size: 24, color: Color(0xFF0D1117)),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Eingabebereich ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            border: Border(top: BorderSide(color: const Color(0xFF1C2333))),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_selectedMessageIds.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F81F7).withOpacity(0.08),
                      border: Border(bottom: BorderSide(color: const Color(0xFF30363D))),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '${_selectedMessageIds.length} ausgewählt',
                          style: TextStyle(fontSize: 14, color: const Color(0xFF8B949E)),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () => setState(() => _selectedMessageIds.clear()),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Abbrechen'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => _forwardMessages([]),
                          icon: const Icon(Icons.forward, size: 18),
                          label: const Text('Weiterleiten'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF2F81F7),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_pendingImages.isNotEmpty && !_hasLeftGroup)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      height: 72,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _pendingImages.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                _pendingImages[i],
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: -4,
                              right: -4,
                              child: GestureDetector(
                                onTap: () {
                                  if (mounted) setState(() => _pendingImages.removeAt(i));
                                },
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: const Color(0xFF161B22),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.cancel,
                                      color: Colors.red.shade400, size: 20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_hasLeftGroup)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF21262D).withOpacity(0.5),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: const Color(0xFF30363D).withOpacity(0.5), width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 20, color: Colors.grey[500]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Du hast die Gruppe verlassen. Du kannst keine Nachrichten mehr senden.',
                            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (_isRecording)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _BlinkingMicButton(),
                        ),
                      if (!_isRecording)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: _pickImages,
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFF1C2333),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.add_photo_alternate_outlined, size: 20, color: Colors.grey[600]),
                            ),
                          ),
                        ),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF21262D),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFF30363D), width: 1),
                          ),
                          child: TextField(
                            controller: _messageController,
                            decoration: InputDecoration(
                              hintText: 'Nachricht...',
                              hintStyle: TextStyle(
                                  color: const Color(0xFF6E7681), fontSize: 14.5),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 10),
                            ),
                            style: const TextStyle(fontSize: 14.5, color: Colors.black87),
                            maxLines: 4,
                            minLines: 1,
                            maxLength: 4000,
                            buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onLongPressStart: (_) => _startVoiceRecording(),
                        onLongPressEnd: (_) => _stopAndSendVoice(),
                        onLongPressCancel: () => _cancelVoiceRecording(),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _isRecording
                                ? Colors.red.shade400
                                : Colors.grey.shade300,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                            size: 20,
                            color: _isRecording ? Colors.white : const Color(0xFF8B949E),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: _sendMessage,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2F81F7),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF2F81F7).withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.send_rounded,
                              size: 19, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Neuer-Chat-Modal ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  Widget _buildNewChatModal() {
    return Material(
      color: Colors.black.withOpacity(0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 8, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F81F7).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.add_comment_outlined,
                          size: 18, color: const Color(0xFF2F81F7)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Chat starten',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: const Color(0xFF8B949E)),
                      onPressed: () => setState(() => _showNewChatModal = false),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: const Color(0xFF30363D)),
              // Liste
              Flexible(
                child: _loadingMitarbeiter
                    ? const Center(
                        child: CircularProgressIndicator(color: const Color(0xFF2F81F7)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        itemCount: _mitarbeiter.length,
                        itemBuilder: (_, i) {
                          final m = _mitarbeiter[i];
                          if (m.uid.isNotEmpty) Future.microtask(() => _loadProfileImage(m.uid));
                          final photoUrl = m.uid.isNotEmpty ? _profileImageCache[m.uid] : null;
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _startDirectChat(m),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      gradient: (photoUrl == null || photoUrl.isEmpty)
                                          ? LinearGradient(
                                              colors: [
                                                const Color(0xFF388BFD).withOpacity(0.7),
                                                const Color(0xFF2F81F7),
                                              ],
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            )
                                          : null,
                                      shape: BoxShape.circle,
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    alignment: Alignment.center,
                                    child: (photoUrl != null && photoUrl.isNotEmpty)
                                        ? Image.network(photoUrl, width: 40, height: 40, fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Text(
                                              _getInitials(m.name),
                                              style: const TextStyle(
                                                color: Color(0xFF161B22),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ))
                                        : Text(
                                            _getInitials(m.name),
                                            style: const TextStyle(
                                              color: Color(0xFF161B22),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      m.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: const Color(0xFFE6EDF3),
                                      ),
                                    ),
                                  ),
                                  Icon(Icons.chevron_right,
                                      color: Colors.grey[300], size: 20),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ Neue-Gruppe-Modal ÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂÃÂ¢ÃÂÃÂ
  Widget _buildNewGroupModal() {
    return Material(
      color: Colors.black.withOpacity(0.45),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 8, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2F81F7).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.group_add_outlined,
                          size: 18, color: const Color(0xFF2F81F7)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Neue Gruppe',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: const Color(0xFF8B949E)),
                      onPressed: () => setState(() => _showNewGroupModal = false),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: const Color(0xFF30363D)),
              // Gruppenname
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: TextField(
                  controller: _groupNameController,
                  style: const TextStyle(color: Color(0xFFE6EDF3)),
                  cursorColor: const Color(0xFF2F81F7),
                  decoration: InputDecoration(
                    labelText: 'Gruppenname',
                    labelStyle: const TextStyle(color: Color(0xFF8B949E)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: const Color(0xFF30363D)),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF161B22),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'Teilnehmer wählen',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF8B949E),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_selectedGroupMembers.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2F81F7).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_selectedGroupMembers.length} gewählt',
                          style: TextStyle(
                            fontSize: 11,
                            color: const Color(0xFF2F81F7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Mitarbeiterliste
              Flexible(
                child: _loadingMitarbeiter
                    ? const Center(
                        child: CircularProgressIndicator(color: const Color(0xFF2F81F7)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        itemCount: _mitarbeiter.length,
                        itemBuilder: (_, i) {
                          final m = _mitarbeiter[i];
                          if (m.uid.isNotEmpty) Future.microtask(() => _loadProfileImage(m.uid));
                          final photoUrl = m.uid.isNotEmpty ? _profileImageCache[m.uid] : null;
                          final selected =
                              _selectedGroupMembers.any((s) => s.uid == m.uid);
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              if (mounted) setState(() {
                                if (selected) {
                                  _selectedGroupMembers
                                      .removeWhere((s) => s.uid == m.uid);
                                } else {
                                  _selectedGroupMembers.add(m);
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFF2F81F7).withOpacity(0.06)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      gradient: (photoUrl == null || photoUrl.isEmpty)
                                          ? (selected
                                              ? LinearGradient(
                                                  colors: [
                                                    const Color(0xFF388BFD).withOpacity(0.7),
                                                    const Color(0xFF2F81F7),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                )
                                              : null)
                                          : null,
                                      color: (photoUrl == null || photoUrl.isEmpty) && !selected
                                          ? const Color(0xFF2F81F7).withOpacity(0.15)
                                          : null,
                                      shape: BoxShape.circle,
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    alignment: Alignment.center,
                                    child: (photoUrl != null && photoUrl.isNotEmpty)
                                        ? Image.network(photoUrl, width: 40, height: 40, fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => Text(
                                              _getInitials(m.name),
                                              style: TextStyle(
                                                color: selected ? Colors.white : const Color(0xFF2F81F7),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ))
                                        : Text(
                                            _getInitials(m.name),
                                            style: TextStyle(
                                              color: selected
                                                  ? Colors.white
                                                  : const Color(0xFF2F81F7),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      m.name,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color: const Color(0xFFE6EDF3),
                                      ),
                                    ),
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: selected
                                        ? const Icon(Icons.check_circle,
                                            color: const Color(0xFF2F81F7), size: 22,
                                            key: ValueKey('checked'))
                                        : Icon(Icons.circle_outlined,
                                            color: Colors.grey[300], size: 22,
                                            key: const ValueKey('unchecked')),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
              // Button
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _createGroup,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF2F81F7),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'Gruppe erstellen',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// In-Chat-Wiedergabe einer Sprachnachricht (kein externes ÃÂffnen).
class _VoiceMessagePlayer extends StatefulWidget {
  final String url;
  final bool isSent;
  final AudioPlayer player;
  final String? playingUrl;
  final void Function(String? url) onPlaybackStateChanged;
  final VoidCallback onError;

  const _VoiceMessagePlayer({
    required this.url,
    required this.isSent,
    required this.player,
    required this.playingUrl,
    required this.onPlaybackStateChanged,
    required this.onError,
  });

  @override
  State<_VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<_VoiceMessagePlayer> {
  Future<void> _togglePlay() async {
    if (widget.playingUrl == widget.url) {
      if (widget.player.playing) {
        await widget.player.pause();
      } else {
        await widget.player.play();
      }
      return;
    }
    try {
      await widget.player.stop();
      if (!mounted) return;
      widget.onPlaybackStateChanged(widget.url);
      await widget.player.setUrl(widget.url);
      if (!mounted) return;
      await widget.player.play();
    } catch (_) {
      widget.onPlaybackStateChanged(null);
      widget.onError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isThisPlaying = widget.playingUrl == widget.url;
    final color = widget.isSent ? Colors.white70 : const Color(0xFF8B949E);
    return GestureDetector(
      onTap: _togglePlay,
      child: StreamBuilder<PlayerState>(
        stream: widget.player.playerStateStream,
        builder: (context, snapshot) {
          final playing = isThisPlaying && (snapshot.data?.playing ?? false);
          final processing = isThisPlaying &&
              (snapshot.data?.processingState == ProcessingState.buffering ||
                  snapshot.data?.processingState == ProcessingState.loading);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (processing)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              else
                Icon(
                  playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  size: 28,
                  color: color,
                ),
              const SizedBox(width: 8),
              if (isThisPlaying)
                StreamBuilder<Duration>(
                  stream: widget.player.positionStream,
                  builder: (context, posSnap) {
                    final pos = posSnap.data ?? Duration.zero;
                    final dur = widget.player.duration ?? Duration.zero;
                    final txt = dur.inSeconds > 0
                        ? '${pos.inMinutes}:${(pos.inSeconds % 60).toString().padLeft(2, '0')} / ${dur.inMinutes}:${(dur.inSeconds % 60).toString().padLeft(2, '0')}'
                        : 'Sprachnachricht';
                    return Text(txt, style: TextStyle(fontSize: 13, color: color));
                  },
                )
              else
                Text('Sprachnachricht', style: TextStyle(fontSize: 13, color: color)),
            ],
          );
        },
      ),
    );
  }
}

/// Blinkendes rotes Mikrofon auf schwarzem Hintergrund (wÃ¤hrend Sprachaufnahme).
class _BlinkingMicButton extends StatefulWidget {
  const _BlinkingMicButton();
  @override
  State<_BlinkingMicButton> createState() => _BlinkingMicButtonState();
}

class _BlinkingMicButtonState extends State<_BlinkingMicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 1.0, end: 0.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 38,
        height: 38,
        decoration: const BoxDecoration(
          color: Colors.black,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.mic_rounded, size: 20, color: Colors.red),
      ),
    );
  }
}