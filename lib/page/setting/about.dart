import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/gestures.dart';

import '../../app_version.dart';

class About extends StatelessWidget {
  const About({super.key});

  // 创建可点击的链接文字
  TextSpan linkTextSpan(BuildContext context, String text, String url) {
    return TextSpan(
      text: text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
        fontSize: 14,
      ),
      recognizer: TapGestureRecognizer()..onTap = () => _openUrl(context, url),
    );
  }

  // 打开链接
  Future<void> _openUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开链接，请检查浏览器设置后重试')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开链接，请检查网络或浏览器设置')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('应用信息与说明', style: Theme.of(context).textTheme.titleMedium),
          ElevatedButton.icon(
            onPressed: () async {
              final appVersion = await AppVersion.current();
              if (!context.mounted) return;
              showAboutDialog(
                context: context,
                applicationName: 'Myune music for Android',
                applicationVersion: 'v$appVersion',
                applicationIcon: Image.asset(
                  'assets/images/icon/logo.png',
                  width: 48,
                  height: 48,
                ),
                applicationLegalese:
                    '© 2026 Myune music for Android · Apache License 2.0',
                children: [
                  const SizedBox(height: 8),
                  const Text(
                    '专为 Android 手机设计的本地音乐播放器，提供本地曲库、歌词、通知栏控制、均衡器、音频效果与实时音频分析。',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '本项目基于 ',
                          style: TextStyle(fontSize: 14),
                        ),
                        linkTextSpan(
                          context,
                          'xiaobaimc/myune_music',
                          'https://github.com/xiaobaimc/myune_music',
                        ),
                        const TextSpan(
                          text: ' 构建并进行 Android 手机端适配，可在 ',
                          style: TextStyle(fontSize: 14),
                        ),
                        linkTextSpan(
                          context,
                          'GitHub',
                          'https://github.com/baishu136/myune_music_android',
                        ),
                        const TextSpan(
                          text: ' 查看本项目代码。软件继续遵循 Apache License 2.0。',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '遇到问题可在 ',
                          style: TextStyle(fontSize: 14),
                        ),
                        linkTextSpan(
                          context,
                          'GitHub Issue',
                          'https://github.com/baishu136/myune_music_android/issues',
                        ),
                        const TextSpan(
                          text: ' 反馈',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '诊断日志仅保存在设备的应用数据目录中，不会由软件自动上传。',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '网络歌词与更新检查仅在用户启用或主动操作时访问网络。',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '软件使用小米公司提供的 MiSans 字体，该字体已明确允许免费商用',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  const Text('字体版权归小米公司所有', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(
                          text: '相关许可协议请查阅：',
                          style: TextStyle(fontSize: 14),
                        ),
                        linkTextSpan(
                          context,
                          'MiSans 字体知识产权使用许可协议',
                          'https://hyperos.mi.com/font-download/MiSans%E5%AD%97%E4%BD%93%E7%9F%A5%E8%AF%86%E4%BA%A7%E6%9D%83%E8%AE%B8%E5%8F%AF%E5%8D%8F%E8%AE%AE.pdf',
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
            icon: const Icon(Icons.info_outline, size: 20),
            label: const Text('关于信息'),
          ),
        ],
      ),
    );
  }
}
