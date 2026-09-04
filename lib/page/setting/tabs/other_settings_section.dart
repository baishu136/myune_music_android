import 'dart:io';

import 'package:flutter/material.dart';

import '../../../services/gallery_image_saver.dart';
import '../project_changelog.dart';
import '../project_changelog_page.dart';

const wechatSponsorImageAsset = 'assets/images/sponsor/wechat_qr.png';
const alipaySponsorImageAsset = 'assets/images/sponsor/alipay_qr.jpg';

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
            subtitle: const Text('查看首个版本发布以来的更新记录'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => const ProjectChangelogPage(),
              ),
            ),
          ),
          const Divider(height: 1),
          const _SponsorExpansionTile(),
        ],
      ),
    );
  }
}

class _SponsorExpansionTile extends StatefulWidget {
  const _SponsorExpansionTile();

  @override
  State<_SponsorExpansionTile> createState() => _SponsorExpansionTileState();
}

class _SponsorExpansionTileState extends State<_SponsorExpansionTile> {
  bool _saving = false;
  bool _expanded = false;

  Future<void> _saveSponsorImages() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await GalleryImageSaver.saveAsset(
        assetPath: wechatSponsorImageAsset,
        fileName: 'Myune-Music-WeChat-Sponsor.png',
      );
      await GalleryImageSaver.saveAsset(
        assetPath: alipaySponsorImageAsset,
        fileName: 'Myune-Music-Alipay-Sponsor.jpg',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('两张二维码已保存到系统相册')));
    } on GallerySaveException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('保存失败，请稍后重试')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      key: const PageStorageKey<String>('sponsor-settings-expansion'),
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.volunteer_activism_outlined),
      title: const Text('赞助'),
      subtitle: const Text('支持项目持续开发与更新'),
      onExpansionChanged: (expanded) {
        if (_expanded != expanded) setState(() => _expanded = expanded);
      },
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: !_expanded
          ? const []
          : [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Myune music for Android 自发布以来共发布了 $projectReleaseCount 次，'
                  '更新并修复了 $projectEffectiveChangeCount 个内容。\n\n'
                  '您的赞助将用于该项目及作者其他免费项目的开发和更新，感谢您的支持！',
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _SponsorQrCode(
                      assetPath: wechatSponsorImageAsset,
                      label: '微信',
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _SponsorQrCode(
                      assetPath: alipaySponsorImageAsset,
                      label: '支付宝',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: Platform.isAndroid && !_saving
                      ? _saveSponsorImages
                      : null,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_outlined),
                  label: Text(_saving ? '正在保存…' : '保存两张二维码到相册'),
                ),
              ),
            ],
    );
  }
}

class _SponsorQrCode extends StatelessWidget {
  const _SponsorQrCode({required this.assetPath, required this.label});

  final String assetPath;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: AspectRatio(
            aspectRatio: 1,
            child: ColoredBox(
              color: Colors.white,
              child: Image.asset(
                assetPath,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
