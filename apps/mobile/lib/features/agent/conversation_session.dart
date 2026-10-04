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
  _ConversationRegistry(this.owner, this.generation);
}

abstract final class ConversationSessions {
  static final Expando<_ConversationRegistry> _clients = Expando();

  static ConversationSession forContext(
    Object client, {
    required String owner,
    required int generation,
    required String semester,
    required String context,
  }) {
    var registry = _clients[client];
    if (registry == null ||
        registry.owner != owner ||
        registry.generation != generation) {
      registry = _ConversationRegistry(owner, generation);
      _clients[client] = registry;
    }
    final key = '$semester\u0000$context';
    if (!registry.contexts.containsKey(key) && registry.contexts.length >= 24) {
      registry.contexts.remove(registry.contexts.keys.first);
    }
    return registry.contexts.putIfAbsent(key, ConversationSession.new);
  }
}
