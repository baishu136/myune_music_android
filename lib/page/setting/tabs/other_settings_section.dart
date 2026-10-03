import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../project_changelog_page.dart';

const androidProjectRepositoryUrl =
    'https://github.com/baishu136/myune_music_android';

class OtherSettingsSection extends StatelessWidget {
  const OtherSettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: ExpansionTile(
        key: const PageStorageKey<String>('other-settings-expansion'),
        initiallyExpanded: false,
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: EdgeInsets.zero,
        title: Text('其他', style: Theme.of(context).textTheme.titleMedium),
        childrenPadding: EdgeInsets.zero,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.history),
            title: const Text('更新日志'),
            subtitle: const Text('查看 0.99 发布以来的全部有效更改'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const ProjectChangelogPage(),
              ),
            ),
          ),
          const Divider(height: 1),
          const _SupportProjectExpansionTile(),
        ],
      ),
    );
  }
}

class _SupportProjectExpansionTile extends StatelessWidget {
  const _SupportProjectExpansionTile();

  Future<void> _openRepository() async {
    await launchUrl(
      Uri.parse(androidProjectRepositoryUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const PageStorageKey<String>('support-project-expansion'),
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.star_outline_rounded),
      title: const Text('支持项目'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('如果您喜欢此软件，请在GitHub留下star'),
              const SizedBox(height: 8),
              InkWell(
                key: const ValueKey('project-github-link'),
                onTap: _openRepository,
                child: Text(
                  androidProjectRepositoryUrl,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
