import 'package:flutter/foundation.dart';

/// Conversation selection lasts for this app process. Persisted drafts remain
/// recoverable, but a new process never silently reopens an old dialogue.
class ConversationSession {
  String? threadId;
  Map<String, dynamic>? editingRun;
  Map<String, dynamic>? editBackup;
}

class _ConversationRegistry {
  final String owner;
  final int generation;
  final contexts = <String, ConversationSession>{};
  final deletions = ConversationDeletions();
  _ConversationRegistry(this.owner, this.generation);
}

/// A deletion is shared by all live assistants for one API/account generation.
class ConversationDeletions extends ChangeNotifier {
  final _deleted = <String, Set<String>>{};

  bool contains(String semester, String threadId) =>
      _deleted[semester]?.contains(threadId) == true;

  Set<String> forSemester(String semester) =>
      Set.unmodifiable(_deleted[semester] ?? const <String>{});

  void mark(String semester, String threadId) {
    if (_deleted.putIfAbsent(semester, () => <String>{}).add(threadId)) {
      notifyListeners();
    }
  }
}

abstract final class ConversationSessions {
  static final Expando<_ConversationRegistry> _clients = Expando();

  static _ConversationRegistry _registry(
    Object client,
    String owner,
    int generation,
  ) {
    var registry = _clients[client];
    if (registry == null ||
        registry.owner != owner ||
        registry.generation != generation) {
      registry = _ConversationRegistry(owner, generation);
      _clients[client] = registry;
    }
    return registry;
  }

  static ConversationDeletions deletionsFor(
    Object client, {
    required String owner,
    required int generation,
  }) => _registry(client, owner, generation).deletions;

  static void forgetThread(
    Object client, {
    required String owner,
    required int generation,
    required String semester,
    required String threadId,
  }) {
    final registry = _clients[client];
    if (registry == null ||
        registry.owner != owner ||
        registry.generation != generation) {
      return;
    }
    for (final entry in registry.contexts.entries) {
      if (!entry.key.startsWith('$semester\u0000') ||
          entry.value.threadId != threadId) {
        continue;
      }
      entry.value
        ..threadId = null
        ..editingRun = null
        ..editBackup = null;
    }
    registry.deletions.mark(semester, threadId);
  }

  static ConversationSession forContext(
    Object client, {
    required String owner,
    required int generation,
    required String semester,
    required String context,
  }) {
    final registry = _registry(client, owner, generation);
    final key = '$semester\u0000$context';
    if (!registry.contexts.containsKey(key) && registry.contexts.length >= 24) {
      registry.contexts.remove(registry.contexts.keys.first);
    }
    return registry.contexts.putIfAbsent(key, ConversationSession.new);
  }
}
