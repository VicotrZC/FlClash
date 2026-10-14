import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:flutter/foundation.dart';

import 'print.dart';
import 'protocol.dart';
import 'string.dart';

typedef InstallConfigCallBack = void Function(String url);

typedef OpenPageCallBack = void Function(PageLabel pageLabel);

/// 站内跳转用的 host 名，例如 `flclash://proxies`。
/// 与 `install-config` 这类功能性 host 区分开：只有能映射到 [PageLabel] 的才跳页。
PageLabel? _pageLabelFromUri(Uri uri) {
  if (!protocolSchemes.contains(uri.scheme)) {
    return null;
  }
  for (final label in PageLabel.values) {
    if (label.name == uri.host) {
      return label;
    }
  }
  return null;
}

String? profileUrlFromQrCodes(Iterable<String?> values) {
  for (final value in values) {
    final text = value?.trim();
    if (text == null || text.isEmpty) {
      continue;
    }
    if (text.isUrl || text.isShareLink) {
      return text;
    }
    final uri = Uri.tryParse(text);
    if (uri == null || !protocolSchemes.contains(uri.scheme)) {
      continue;
    }
    final url = _installConfigUrl(uri);
    if (url != null && url.isUrl) {
      return url;
    }
  }
  return null;
}

String? _installConfigUrl(Uri uri) {
  if (uri.host != 'install-config') {
    return null;
  }
  final url = uri.queryParameters['url']?.trim();
  return url == null || url.isEmpty ? null : url;
}

class LinkManager {
  static LinkManager? _instance;
  StreamSubscription? subscription;
  Uri? _pendingUri;

  LinkManager._internal();

  @visibleForTesting
  Stream<Uri> Function() uriLinkStream = () => AppLinks().uriLinkStream;

  /// Linux argv: the gtk plugin hooks GApplication too late to see it.
  void seedInitialLink(List<String> args) {
    for (final arg in args) {
      final uri = Uri.tryParse(arg);
      if (uri != null && protocolSchemes.contains(uri.scheme)) {
        _pendingUri = uri;
        return;
      }
    }
  }

  Future<void> initAppLinksListen(
    Function(String url) installConfigCallBack, {
    OpenPageCallBack? onOpenPage,
  }) async {
    destroy();
    subscription = uriLinkStream().listen((uri) {
      _handle(uri, installConfigCallBack, onOpenPage);
    });
    final pending = _pendingUri;
    _pendingUri = null;
    if (pending != null) {
      _handle(pending, installConfigCallBack, onOpenPage);
    }
  }

  void _handle(
    Uri uri,
    Function(String url) installConfigCallBack,
    OpenPageCallBack? onOpenPage,
  ) {
    commonPrint.log('onAppLink: $uri');
    final url = _installConfigUrl(uri);
    if (url != null) {
      installConfigCallBack(url);
      return;
    }
    final pageLabel = _pageLabelFromUri(uri);
    if (pageLabel != null) {
      onOpenPage?.call(pageLabel);
    }
  }

  void destroy() {
    if (subscription != null) {
      subscription?.cancel();
      subscription = null;
    }
  }

  factory LinkManager() {
    _instance ??= LinkManager._internal();
    return _instance!;
  }
}

final linkManager = LinkManager();
