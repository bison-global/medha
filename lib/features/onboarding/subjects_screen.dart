import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/catalog/catalog.dart';
import '../common/widgets.dart';

/// Step 1: pick a subject. Subjects whose models haven't shipped yet are
/// shown as "Coming soon".
class SubjectsScreen extends ConsumerWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(servicesProvider).catalog;
    final subjects = catalog.subjects;
    return Scaffold(
      appBar: AppBar(actions: const [
        Padding(padding: EdgeInsets.only(right: 20), child: Center(child: Text('Step 1 of 2', style: TextStyle(color: MedhaColors.muted)))),
      ]),
      body: SafeArea(
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            sliver: SliverList.list(children: [
              Text('What do you want to explore?',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('Each Medha model is tuned for one subject. You can add more later.',
                  style: TextStyle(fontSize: 15, height: 1.5, color: MedhaColors.muted)),
              const SizedBox(height: 20),
            ]),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 160,
              ),
              itemCount: subjects.length,
              itemBuilder: (context, i) {
                final s = subjects[i];
                final available = catalog.tiersFor(s.interest).any((e) => e.available);
                return _SubjectCard(entry: s, available: available, onTap: () => context.push('/subjects/${s.interest}'));
              },
            ),
          ),
        ]),
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.entry, required this.available, required this.onTap});
  final InterestEntry entry;
  final bool available;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(entry.color);
    return Opacity(
      opacity: available ? 1 : 0.55,
      child: Material(
        color: MedhaColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: MedhaColors.line, width: 1.5)),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: available ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: MedhaColors.ink, borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              ),
              const SizedBox(height: 10),
              Text(entry.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Expanded(
                child: Text(entry.blurb,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.4, color: MedhaColors.muted)),
              ),
              if (!available) const Pill('Coming soon'),
            ]),
          ),
        ),
      ),
    );
  }
}
