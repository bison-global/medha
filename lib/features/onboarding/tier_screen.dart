import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/catalog/catalog.dart';
import '../../core/download/model_installer.dart';
import '../common/widgets.dart';

/// Step 2: pick Lite or Pro, see what will be downloaded, choose Wi-Fi only.
class TierScreen extends ConsumerStatefulWidget {
  const TierScreen({super.key, required this.interest});
  final String interest;

  @override
  ConsumerState<TierScreen> createState() => _TierScreenState();
}

class _TierScreenState extends ConsumerState<TierScreen> {
  String? _selected;
  bool? _wifiOnly;
  final Map<String, Future<int>> _sizes = {};
  final Map<String, Future<TierPlan>> _plans = {};

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    final catalog = services.catalog;
    final tiers = catalog.tiersFor(widget.interest);
    if (tiers.isEmpty) {
      return const Scaffold(body: Center(child: Text('This subject is not available.')));
    }
    _selected ??= tiers.firstWhere((t) => t.available, orElse: () => tiers.first).id;
    final selected = catalog.interestEntry(_selected!);

    for (final t in tiers) {
      _sizes.putIfAbsent(t.id, () => services.installer.downloadBytes(t));
      _plans.putIfAbsent(t.id, () => services.installer.plan(t));
    }
    final wifiOnly = _wifiOnly ?? services.settings.wifiOnly;

    return Scaffold(
      appBar: AppBar(actions: const [
        Padding(padding: EdgeInsets.only(right: 20), child: Center(child: Text('Step 2 of 2', style: TextStyle(color: MedhaColors.muted)))),
      ]),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 16), children: [
              Text('Pick a size for Medha ${selected.name}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('Both sizes run fully offline. Bigger models think deeper but need more space.',
                  style: TextStyle(fontSize: 15, height: 1.5, color: MedhaColors.muted)),
              const SizedBox(height: 20),
              for (final t in tiers) ...[
                FutureBuilder<TierPlan>(
                  future: _plans[t.id],
                  builder: (context, plan) {
                    final p = plan.data;
                    final fits = p == null || p.fit != TierFit.tooBig;
                    return _TierCard(
                      entry: t,
                      baseName: catalog.baseModel(p?.baseModelId ?? t.baseModelId).name,
                      size: _sizes[t.id]!,
                      selected: t.id == _selected,
                      note: p == null
                          ? null
                          : switch (p.fit) {
                              TierFit.fits => null,
                              TierFit.fallback => 'Uses a smaller model on this phone to fit its memory',
                              TierFit.tooBig => 'Needs more memory than this phone has',
                            },
                      onTap: t.available && fits ? () => setState(() => _selected = t.id) : null,
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: wifiOnly,
                onChanged: (v) => setState(() => _wifiOnly = v),
                title: const Text('Download on Wi-Fi only'),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: FutureBuilder<int>(
              future: _sizes[selected.id],
              builder: (context, snap) {
                final bytes = snap.data;
                final label = bytes == null
                    ? 'Download'
                    : bytes == 0
                        ? 'Add ${selected.sizeLabel} · no download needed'
                        : 'Download ${selected.sizeLabel} · ${formatBytes(bytes)}';
                return FilledButton.icon(
                  onPressed: selected.available && bytes != null
                      ? () => context.push('/install/${selected.id}?wifi=${wifiOnly ? 1 : 0}')
                      : null,
                  icon: const Icon(Icons.download_rounded),
                  label: Text(label),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.entry, required this.baseName, required this.size, required this.selected, required this.onTap, this.note});
  final InterestEntry entry;
  final String? note;
  final String baseName;
  final Future<int> size;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? 0.55 : 1,
        child: Material(
          color: selected ? const Color(0xFF1B2338) : MedhaColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: selected ? MedhaColors.accent : MedhaColors.line, width: 1.5),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(entry.sizeLabel, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 10),
                  Text(entry.tier, style: const TextStyle(color: MedhaColors.muted)),
                  const Spacer(),
                  if (onTap == null) const Pill('Coming soon') else Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? MedhaColors.accent : MedhaColors.faint),
                ]),
                const SizedBox(height: 8),
                Text(entry.blurb, style: const TextStyle(fontSize: 14, height: 1.45, color: MedhaColors.textSoft)),
                const SizedBox(height: 8),
                FutureBuilder<int>(
                  future: size,
                  builder: (context, snap) {
                    final shared = snap.data == 0 ? ' · already on this phone' : '';
                    return Text('Runs on $baseName$shared', style: const TextStyle(fontSize: 12, color: MedhaColors.muted));
                  },
                ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(note!, style: const TextStyle(fontSize: 12, color: MedhaColors.accent)),
                  ),
              ]),
            ),
          ),
        ),
      );
}
