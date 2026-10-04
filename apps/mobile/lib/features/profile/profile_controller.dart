import 'package:flutter/foundation.dart';
import '../../core/api.dart';
import '../../core/cache.dart';

class UserProfile {
  final int version;
  final String school, college, major, className, classRole;
  final String? educationLevel;
  final int? entryYear;
  final bool onboardingCompleted;
  const UserProfile({
    this.version = 0,
    this.school = '',
    this.college = '',
    this.major = '',
    this.className = '',
    this.classRole = '',
    this.educationLevel,
    this.entryYear,
    this.onboardingCompleted = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    version: json['version'] as int? ?? 0,
    school: json['school'] as String? ?? '',
    college: json['college'] as String? ?? '',
    major: json['major'] as String? ?? '',
    className: json['class_name'] as String? ?? '',
    classRole: json['class_role'] as String? ?? '',
    educationLevel: json['education_level'] as String?,
    entryYear: json['entry_year'] as int?,
    onboardingCompleted: json['onboarding_completed'] == true,
  );

  Map<String, dynamic> toJson() => {
    'version': version,
    'school': school.trim(),
    'college': college.trim(),
    'major': major.trim(),
    'class_name': className.trim(),
    'education_level': educationLevel,
    'entry_year': entryYear,
    'class_role': classRole.trim(),
    'onboarding_completed': onboardingCompleted,
  };

  Map<String, dynamic> requestBody() => {
    ...toJson()..remove('version'),
    'expected_version': version,
    'onboarding_completed': true,
  };

  UserProfile withVersion(int value) =>
      UserProfile.fromJson({...toJson(), 'version': value});
}

enum ProfileSaveResult { saved, conflict, unavailable, stale }

class ProfileController extends ChangeNotifier {
  final SemesterApi api;
  final CalendarStore cache;
  UserProfile profile = const UserProfile();
  UserProfile? draft;
  String? owner;
  bool loading = false, busy = false, offline = false, conflict = false;
  String? error;
  ProfileController(this.api, this.cache);
  void Function()? onUnauthorized;
  int _generation = -1, _epoch = 0, _request = 0;
  bool _guideClaimed = false, _skipped = false, _disposed = false;
  Future<void>? _writes;
  Future<void> _binding = Future.value();

  int get generation => _generation;
  bool get needsOnboarding =>
      owner != null &&
      !loading &&
      !_skipped &&
      !_guideClaimed &&
      !profile.onboardingCompleted;

  bool _valid(String value, int epoch) =>
      !_disposed &&
      owner == value &&
      epoch == _epoch &&
      _generation == api.generation &&
      '${api.session?['user']?['id']}' == value;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool claimGuide() {
    if (!needsOnboarding) return false;
    _guideClaimed = true;
    return true;
  }

  /// Dismissing a suggestion is local; it never submits unfilled identity data.
  Future<void> dismissGuide() async {
    final identity = owner, epoch = _epoch;
    if (identity == null || !_valid(identity, epoch)) return;
    _skipped = true;
    _notify();
    await _persist(identity, epoch);
  }

  Future<void> bind(String? value) {
    if (owner == value && _generation == api.generation) return _binding;
    final previous = owner;
    final epoch = ++_epoch;
    owner = value;
    _generation = api.generation;
    ++_request;
    profile = const UserProfile();
    draft = null;
    loading = value != null;
    busy = offline = conflict = _guideClaimed = _skipped = false;
    error = null;
    _notify();
    // Clearing follows all outstanding writes, including a write already in
    // progress during logout. An old response cannot recreate the cache.
    final clearing = previous == null
        ? Future<void>.value()
        : _queue(() => cache.clear('profile:$previous'));
    return _binding = (() async {
      await clearing;
      if (value == null || !_valid(value, epoch)) return;
      try {
        final local = await cache.read('profile:$value');
        if (!_valid(value, epoch)) return;
        if (local?['profile'] is Map) {
          profile = UserProfile.fromJson(
            Map<String, dynamic>.from(local!['profile']),
          );
        }
        if (local?['draft'] is Map) {
          draft = UserProfile.fromJson(
            Map<String, dynamic>.from(local!['draft']),
          );
        }
        _skipped = local?['skipped'] == true;
        _notify();
      } catch (_) {
        // Profile setup remains optional when local storage is unavailable.
      }
      if (_valid(value, epoch)) await _load(value, epoch);
    })();
  }

  Future<void> _queue(Future<void> Function() action) {
    return _writes = (_writes ?? Future<void>.value())
        .catchError((Object _) {})
        .then((_) => action())
        .catchError((Object _) {});
  }

  Future<void> _persist(String value, int epoch) {
    final snapshot = {
      'profile': profile.toJson(),
      if (draft != null) 'draft': draft!.toJson(),
      'skipped': _skipped,
    };
    return _queue(() async {
      if (_valid(value, epoch)) await cache.write('profile:$value', snapshot);
    });
  }

  Future<void> _load(String value, int epoch) async {
    final sequence = ++_request;
    loading = true;
    _notify();
    try {
      final data = await api.request('GET', '/me/profile');
      if (!_valid(value, epoch) || sequence != _request) return;
      profile = UserProfile.fromJson(Map<String, dynamic>.from(data));
      offline = false;
      conflict = draft != null && draft!.version != profile.version;
      await _persist(value, epoch);
    } on ApiFailure catch (e) {
      if (!_valid(value, epoch) || sequence != _request || e.staleSession) {
        return;
      }
      offline = true;
      if (e.unauthorized) onUnauthorized?.call();
    } catch (_) {
      if (!_valid(value, epoch) || sequence != _request) return;
      offline = true;
    } finally {
      if (_valid(value, epoch) && sequence == _request) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> reload() async {
    final value = owner, epoch = _epoch;
    if (value != null && _valid(value, epoch)) await _load(value, epoch);
  }

  Future<void> rememberDraft(UserProfile value) async {
    final identity = owner, epoch = _epoch;
    if (identity == null || !_valid(identity, epoch)) return;
    draft = value;
    await _persist(identity, epoch);
  }

  /// Reusing the new version is an explicit choice made after reviewing it.
  UserProfile resolveConflict({required bool useLatest}) {
    final value = useLatest
        ? profile
        : (draft ?? profile).withVersion(profile.version);
    draft = useLatest ? null : value;
    conflict = false;
    error = null;
    final identity = owner;
    if (identity != null) _persist(identity, _epoch);
    _notify();
    return value;
  }

  Future<ProfileSaveResult> save(UserProfile value) async {
    final identity = owner, epoch = _epoch;
    if (identity == null || !_valid(identity, epoch)) {
      return ProfileSaveResult.stale;
    }
    if (busy || loading) return ProfileSaveResult.unavailable;
    if (conflict) return ProfileSaveResult.conflict;
    busy = true;
    error = null;
    draft = value;
    _notify();
    await _persist(identity, epoch);
    if (!_valid(identity, epoch)) return ProfileSaveResult.stale;
    try {
      final data = await api.request(
        'PUT',
        '/me/profile',
        data: value.requestBody(),
      );
      if (!_valid(identity, epoch)) return ProfileSaveResult.stale;
      profile = UserProfile.fromJson(Map<String, dynamic>.from(data));
      draft = null;
      offline = conflict = false;
      _skipped = true;
      await _persist(identity, epoch);
      return _valid(identity, epoch)
          ? ProfileSaveResult.saved
          : ProfileSaveResult.stale;
    } on ApiFailure catch (e) {
      if (!_valid(identity, epoch) || e.staleSession) {
        return ProfileSaveResult.stale;
      }
      if (e.unauthorized) {
        onUnauthorized?.call();
        return ProfileSaveResult.stale;
      }
      if (e.statusCode == 409) {
        conflict = true;
        await _load(identity, epoch);
        if (!_valid(identity, epoch)) return ProfileSaveResult.stale;
        conflict = true;
        error = '资料已在其他设备修改，当前填写已保留。';
        return ProfileSaveResult.conflict;
      }
      offline = true;
      error = '暂时未保存，当前填写已保留在本机。';
      return ProfileSaveResult.unavailable;
    } catch (_) {
      if (!_valid(identity, epoch)) return ProfileSaveResult.stale;
      error = '暂时未保存，当前填写已保留在本机。';
      return ProfileSaveResult.unavailable;
    } finally {
      if (_valid(identity, epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  Future<void> skip() async {
    final identity = owner, epoch = _epoch;
    if (identity == null || !_valid(identity, epoch)) return;
    _skipped = _guideClaimed = true;
    busy = true;
    _notify();
    await _persist(identity, epoch);
    try {
      // Only complete the guide; skipping never applies an unfinished draft.
      for (var attempt = 0; attempt < 2; attempt++) {
        if (!_valid(identity, epoch)) return;
        try {
          final data = await api.request(
            'PUT',
            '/me/profile',
            data: profile.requestBody(),
          );
          if (!_valid(identity, epoch)) return;
          profile = UserProfile.fromJson(Map<String, dynamic>.from(data));
          if (attempt == 0 && draft != null && !conflict) {
            // Completing the guide changes only its marker. Keep a skipped
            // partial form on that new version without a spurious conflict.
            draft = draft!.withVersion(profile.version);
          }
          offline = false;
          await _persist(identity, epoch);
          break;
        } on ApiFailure catch (e) {
          if (!_valid(identity, epoch) || e.staleSession) return;
          if (e.unauthorized) {
            onUnauthorized?.call();
            return;
          }
          if (e.statusCode == 409 && attempt == 0) {
            await _load(identity, epoch);
            if (offline) break;
            continue;
          }
          offline = true;
          break;
        }
      }
    } catch (_) {
      // The local skip marker still permits basic use without the server.
    } finally {
      if (_valid(identity, epoch)) {
        busy = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    ++_epoch;
    super.dispose();
  }
}
