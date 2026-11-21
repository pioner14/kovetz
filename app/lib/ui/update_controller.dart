import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../updates.dart';
import 'settings.dart';

enum UpdateStatus { idle, checking, upToDate, available, failed }

/// State of the update check, shared by the home page and the Updates screen.
class UpdateController extends ChangeNotifier {
  UpdateController(
    this.settings, {
    UpdateChecker? checker,
    Future<bool> Function(Uri)? open,
    DateTime Function()? now,
  }) : _checker = checker ?? UpdateChecker(),
       _open = open ?? _launch,
       _now = now ?? DateTime.now;

  final AppSettings settings;
  final UpdateChecker _checker;
  final Future<bool> Function(Uri) _open;
  final DateTime Function() _now;

  UpdateStatus _status = UpdateStatus.idle;
  ReleaseInfo? _release;
  UpdateFailure? _failure;
  bool _dismissed = false;

  UpdateStatus get status => _status;

  /// The newest release found by the last successful check.
  ReleaseInfo? get release => _release;
  UpdateFailure? get failure => _failure;

  /// Whether the home page should mention a new version.
  bool get showBanner => _status == UpdateStatus.available && !_dismissed;

  void dismissBanner() {
    _dismissed = true;
    notifyListeners();
  }

  /// Checks now, because the person asked.
  Future<void> check() async {
    if (_status == UpdateStatus.checking) return;
    _status = UpdateStatus.checking;
    _failure = null;
    notifyListeners();
    try {
      final result = await _checker.check();
      _release = result.latest;
      _status = result.available
          ? UpdateStatus.available
          : UpdateStatus.upToDate;
      _dismissed = false;
      unawaited(settings.markUpdateChecked(_now()));
    } on UpdateFailure catch (error) {
      _failure = error;
      _status = UpdateStatus.failed;
    }
    notifyListeners();
  }

  /// At start-up: checks once a day, and only if the person turned it on.
  Future<void> checkAutomatically() async {
    if (!settings.autoUpdateCheck) return;
    final last = settings.lastUpdateCheck;
    if (last != null && _now().difference(last) < const Duration(hours: 24)) {
      return;
    }
    await check();
  }

  Future<bool> open(Uri uri) async {
    try {
      return await _open(uri);
    } on Object {
      return false;
    }
  }
}

Future<bool> _launch(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
