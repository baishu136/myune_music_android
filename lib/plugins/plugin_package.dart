import 'dart:convert';

const pluginSdkVersion = 1;
const pluginPackageByteLimit = 192 * 1024;
const pluginPermissions = {
  'playback.read',
  'playback.control',
  'library.read',
  'queue.write',
  'lyrics.provide',
  'ui.page',
  'ui.menu',
  'storage',
  'network',
};
const pluginFeatures = {'page', 'menu', 'lyrics', 'events'};

Map<String, dynamic> pluginMap(Object? value) {
  if (value is! Map<String, dynamic>) throw const FormatException('需要对象');
  return value;
}

/// A single UTF-8 JSON envelope avoids executable archive paths/zip expansion.
/// Parsing never executes code. New/updated packages always install disabled.
class PluginPackage {
  PluginPackage._(
    this.json,
    this.id,
    this.name,
    this.version,
    this.script,
    this.permissions,
    this.features,
    this.domains,
    this.menus,
  );
  final Map<String, dynamic> json;
  final String id, name, version, script;
  final Set<String> permissions, features, domains;
  final List<({String id, String title})> menus;

  factory PluginPackage.parse(String source) {
    if (utf8.encode(source).length > pluginPackageByteLimit) {
      throw const FormatException('插件包不能超过 192 KB');
    }
    final json = pluginMap(jsonDecode(source));
    final manifest = pluginMap(json['manifest']);
    String text(String key, int max) {
      final value = manifest[key];
      if (value is! String || value.trim().isEmpty || value.length > max) {
        throw FormatException('无效字段：$key');
      }
      return value;
    }

    Set<String> strings(String key, Set<String>? allowed, int max) {
      final list = manifest[key] ?? <Object>[];
      if (list is! List || list.length > max || list.any((v) => v is! String)) {
        throw FormatException('无效字段：$key');
      }
      final set = list.cast<String>().toSet();
      if (allowed != null && !allowed.containsAll(set)) {
        throw FormatException('不支持的 $key');
      }
      return Set.unmodifiable(set);
    }

    final id = text('id', 80),
        name = text('name', 60),
        version = text('version', 32);
    if (!RegExp(r'^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+$').hasMatch(id) ||
        !RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version) ||
        manifest['sdk'] != pluginSdkVersion) {
      throw const FormatException('插件标识、版本或 SDK 不兼容');
    }
    final permissions = strings('permissions', pluginPermissions, 12);
    final features = strings('features', pluginFeatures, 8);
    final domains = strings('networkDomains', null, 8);
    for (final domain in domains) {
      if (domain.length > 253 ||
          domain != domain.toLowerCase() ||
          !RegExp(
            r'^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,63}$',
          ).hasMatch(domain) ||
          domain.endsWith('.local') ||
          domain.endsWith('.localhost')) {
        throw const FormatException('网络域名必须是明确的公网域名');
      }
    }
    if (permissions.contains('network') != domains.isNotEmpty) {
      throw const FormatException('网络权限与域名清单必须同时声明');
    }
    for (final pair in {
      'page': 'ui.page',
      'menu': 'ui.menu',
      'lyrics': 'lyrics.provide',
      'events': 'playback.read',
    }.entries) {
      if (features.contains(pair.key) && !permissions.contains(pair.value)) {
        throw FormatException('${pair.key} 缺少 ${pair.value} 权限');
      }
    }
    final rawMenus = manifest['menus'] ?? <Object>[];
    if (rawMenus is! List || rawMenus.length > 8) {
      throw const FormatException('菜单数量无效');
    }
    final menus = <({String id, String title})>[];
    for (final raw in rawMenus) {
      final m = pluginMap(raw);
      final key = m['id'], title = m['title'];
      if (key is! String ||
          !RegExp(r'^[a-z][a-z0-9_-]{0,39}$').hasMatch(key) ||
          title is! String ||
          title.trim().isEmpty ||
          title.length > 60 ||
          menus.any((m) => m.id == key)) {
        throw const FormatException('菜单格式无效');
      }
      menus.add((id: key, title: title));
    }
    if (menus.isNotEmpty && !features.contains('menu')) {
      throw const FormatException('未声明菜单能力');
    }
    final script = json['script'];
    if (script is! String ||
        script.trim().isEmpty ||
        utf8.encode(script).length > 128 * 1024 ||
        script.contains('\u0000')) {
      throw const FormatException('脚本为空或过大');
    }
    return PluginPackage._(
      Map.unmodifiable(json),
      id,
      name,
      version,
      script,
      permissions,
      features,
      domains,
      List.unmodifiable(menus),
    );
  }
}
