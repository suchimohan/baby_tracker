import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../providers/child_providers.dart';

/// First-run onboarding: create the child profile (v1: single child).
class CreateChildScreen extends ConsumerStatefulWidget {
  const CreateChildScreen({super.key});

  @override
  ConsumerState<CreateChildScreen> createState() => _CreateChildScreenState();
}

class _CreateChildScreenState extends ConsumerState<CreateChildScreen> {
  final _name = TextEditingController();
  DateTime? _dob;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _dob == null) {
      setState(() => _error = 'Please enter a name and date of birth.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(childrenProvider.notifier)
          .create(name: _name.text.trim(), dob: _dob!);
      // When pushed from the child switcher ("Add child…"), return to home.
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = 'Could not create profile: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.child_care, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 8),
                Text("Who are we tracking?",
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'We only collect what the app needs: name, date of birth, '
                  'and the activities you log. You can delete everything '
                  'with one action at any time.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                      labelText: "Baby's name", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.cake_outlined),
                  label: Text(_dob == null
                      ? 'Date of birth'
                      : DateFormat.yMMMMd().format(_dob!)),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate:
                          DateTime.now().subtract(const Duration(days: 365 * 6)),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _dob = picked);
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Creating…' : 'Start tracking'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
