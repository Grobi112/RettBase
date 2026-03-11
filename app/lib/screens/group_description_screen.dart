import 'package:flutter/material.dart';

import '../models/chat.dart';
import '../services/chat_service.dart';

/// Seite zum Bearbeiten der Gruppenbeschreibung.
class GroupDescriptionScreen extends StatefulWidget {
  final String companyId;
  final ChatModel chat;
  final String initialDescription;

  const GroupDescriptionScreen({
    super.key,
    required this.companyId,
    required this.chat,
    required this.initialDescription,
  });

  @override
  State<GroupDescriptionScreen> createState() => _GroupDescriptionScreenState();
}

class _GroupDescriptionScreenState extends State<GroupDescriptionScreen> {
  final _chatService = ChatService();
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialDescription;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final desc = _controller.text.trim();
    if (desc == (widget.chat.groupDescription ?? '')) {
      Navigator.pop(context, widget.chat.groupDescription ?? '');
      return;
    }
    setState(() => _saving = true);
    try {
      await _chatService.updateGroupDescription(widget.companyId, widget.chat.id, desc);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gruppenbeschreibung wurde aktualisiert.')),
        );
        Navigator.pop(context, desc);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  void _cancel() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        foregroundColor: const Color(0xFFE6EDF3),
        title: const Text('Gruppenbeschreibung'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _saving
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF2F81F7)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      GestureDetector(
                        onTap: _cancel,
                        child: const Text(
                          'Abbrechen',
                          style: TextStyle(
                            color: Color(0xFF8B949E),
                            fontSize: 16,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: _save,
                        child: const Text(
                          'Speichern',
                          style: TextStyle(
                            color: Color(0xFF2F81F7),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 15),
                    maxLines: 12,
                    decoration: InputDecoration(
                      hintText: 'Informationen hier ablegen…',
                      hintStyle: const TextStyle(color: Color(0xFF8B949E)),
                      filled: true,
                      fillColor: const Color(0xFF161B22),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
