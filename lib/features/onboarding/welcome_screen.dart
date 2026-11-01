import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../common/widgets.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - 60),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(children: [
                        MedhaLogo(),
                        SizedBox(width: 10),
                        Text('Medha', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 48),
                      const Center(child: MedhaLogo(size: 168)),
                      const SizedBox(height: 40),
                      Text(
                        'A private mind in your pocket.',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.15),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Download a model for the subject you care about, then chat with it anytime, even without internet.',
                        style: TextStyle(fontSize: 16, height: 1.5, color: MedhaColors.muted),
                      ),
                      const SizedBox(height: 24),
                      const _Feature(Icons.phone_android, 'Runs entirely on your phone'),
                      const _Feature(Icons.wifi_off, 'Works offline after one download'),
                      const _Feature(Icons.lock_outline, 'Your chats never leave the device'),
                      const SizedBox(height: 16),
                      const Text(
                        'Medha is an AI. It can make mistakes, so check important answers.',
                        style: TextStyle(fontSize: 13, height: 1.5, color: MedhaColors.muted),
                      ),
                      const Spacer(),
                      const SizedBox(height: 24),
                      FilledButton(onPressed: () => context.push('/subjects'), child: const Text('Get started')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Icon(icon, size: 20, color: MedhaColors.accent),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 14, color: MedhaColors.textSoft))),
        ]),
      );
}
