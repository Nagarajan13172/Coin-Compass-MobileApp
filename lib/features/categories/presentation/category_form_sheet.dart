import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/enums.dart';
import '../../../core/state/optimistic.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/lucide_map.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_select.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/confirm_sheet.dart';
import '../../../core/widgets/segmented_period_selector.dart';
import '../data/categories_repository.dart';
import '../domain/category.dart';

/// What the sheet did, so the caller can confirm it with the right copy.
enum CategorySheetResult { saved, deleted }

/// The 26 lucide names the backend actually seeds (docs/SPEC.md section 1).
const List<String> categoryIconNames = [
  'utensils',
  'pizza',
  'coffee',
  'shopping-cart',
  'shopping-bag',
  'car',
  'fuel',
  'plane',
  'home',
  'receipt',
  'credit-card',
  'banknote',
  'piggy-bank',
  'heart-pulse',
  'graduation-cap',
  'briefcase',
  'laptop',
  'clapperboard',
  'gamepad',
  'gift',
  'sparkles',
  'repeat',
  'rotate-ccw',
  'trending-up',
  'percent',
  'ellipsis',
];

/// Swatches drawn from the palette the seeded categories already use.
const List<String> categoryColorHexes = [
  '#EF4444',
  '#F97316',
  '#F59E0B',
  '#EAB308',
  '#22C55E',
  '#14B8A6',
  '#06B6D4',
  '#0EA5E9',
  '#3B82F6',
  '#6366F1',
  '#8B5CF6',
  '#A855F7',
  '#EC4899',
  '#64748B',
];

/// Create / edit a category. Bottom sheet stand-in for the web app's modal.
class CategoryFormSheet extends ConsumerStatefulWidget {
  const CategoryFormSheet._({this.category, required this.initialType});

  final Category? category;
  final CategoryType initialType;

  static Future<CategorySheetResult?> show(
    BuildContext context, {
    Category? category,
    CategoryType initialType = CategoryType.expense,
  }) {
    return showModalBottomSheet<CategorySheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CategoryFormSheet._(
        category: category,
        initialType: category?.type ?? initialType,
      ),
    );
  }

  @override
  ConsumerState<CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<CategoryFormSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.category?.name ?? '',
  );
  late CategoryType _type = widget.initialType;
  late String _icon = widget.category?.icon ?? 'shopping-bag';
  late String _color = widget.category?.color ?? '#3B82F6';
  late String? _group = _initialGroup();
  late final List<String> _swatches = _buildSwatches();

  bool _busy = false;
  String? _nameError;
  String? _formError;

  bool get _isEdit => widget.category != null;

  String? _initialGroup() {
    final group = widget.category?.group;
    if (group != null && categoryGroupLabels.containsKey(group)) return group;
    return widget.category == null ? 'other' : null;
  }

  /// Keeps a category's existing colour visible even if it is off-palette.
  List<String> _buildSwatches() {
    final existing = widget.category?.color?.toUpperCase();
    if (existing == null ||
        categoryColorHexes.any((c) => c.toUpperCase() == existing)) {
      return categoryColorHexes;
    }
    return [existing, ...categoryColorHexes];
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Name is required');
      return;
    }
    final body = <String, dynamic>{
      'name': name,
      'type': _type.api,
      'icon': _icon,
      'color': _color,
      if (_group != null) 'group': _group,
    };

    // Captured while the element is alive: the write must refresh the category
    // list even if the sheet is dismissed mid-request, and `ref` throws once
    // disposed. `ProviderContainer.invalidate` has no such assertion.
    final container = ProviderScope.containerOf(context, listen: false);
    final existing = widget.category;

    // 6.4 — a rename, a recolour, a regroup: the client knows the result
    // exactly, and nothing on a category is server-computed by this write
    // (`order`, `isDefault` and `usageCount` belong to the row's history). A
    // create keeps the spinner — the server assigns the id.
    final predicted = existing?.predict(
      name: name,
      type: _type,
      icon: _icon,
      color: _color,
      group: _group,
      parentId: existing.parentId,
    );
    if (existing != null && predicted != null) {
      _runOptimistic(existing, predicted, body, container);
      return;
    }

    setState(() {
      _busy = true;
      _nameError = null;
      _formError = null;
    });

    try {
      final repo = ref.read(categoriesRepositoryProvider);
      await repo.create(body);
      container.invalidate(categoriesFetchProvider);
      if (!mounted) return;
      Navigator.of(context).pop(CategorySheetResult.saved);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _nameError = error.fieldError('name');
        _formError = error.message;
      });
    }
  }

  Future<void> _delete() async {
    final category = widget.category;
    if (category == null) return;

    // Taken before the first await, for the same reason as in `_save`.
    final container = ProviderScope.containerOf(context, listen: false);

    final confirmed = await ConfirmSheet.show(
      context,
      title: 'Delete "${category.name}"?',
      message:
          'Transactions already filed under this category keep their history — '
          'they simply stop showing a category.',
    );
    if (!confirmed || !mounted) return;

    // 6.4 — predictable, so the row goes now. No Undo: there is no restore
    // endpoint for a category. The ConfirmSheet above is the guard.
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(categoriesRepositoryProvider);

    Navigator.of(context).pop(CategorySheetResult.deleted);

    unawaited(
      container
          .read(categoriesWritesProvider.notifier)
          .run<void>(
            paint: PendingWrite.remove(category.id),
            send: () => repository.delete(category.id),
            settle: () => settleCategories(container),
            messenger: messenger,
            noun: category.name,
          ),
    );
  }

  /// Closes the sheet on the predicted row and hands the write over.
  void _runOptimistic(
    Category existing,
    Category predicted,
    Map<String, dynamic> body,
    ProviderContainer container,
  ) {
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(categoriesRepositoryProvider);

    Navigator.of(context).pop(CategorySheetResult.saved);

    unawaited(
      container
          .read(categoriesWritesProvider.notifier)
          .run<Category>(
            paint: PendingWrite.upsert(predicted),
            send: () => repository.update(existing.id, body),
            confirm: (saved) => saved,
            settle: () => settleCategories(container),
            messenger: messenger,
            noun: predicted.name,
            onFix: () {
              if (!messenger.mounted) return;
              CategoryFormSheet.show(messenger.context, category: predicted);
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      // Belt and braces: a write already survives dismissal (the invalidation
      // goes through the container, not `ref`), but there is no reason to let
      // the back button race an in-flight request.
      canPop: !_busy,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.88,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 2, 8, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _isEdit ? 'Edit category' : 'New category',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(LucideIcons.x, size: 20),
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    children: [
                      AppTextField(
                        label: 'Name',
                        controller: _name,
                        hint: 'Groceries',
                        errorText: _nameError,
                        autofocus: !_isEdit,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) {
                          if (_nameError != null) {
                            setState(() => _nameError = null);
                          }
                        },
                      ),
                      const SizedBox(height: 18),
                      const _FieldLabel('Type'),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: SegmentedPeriodSelector<CategoryType>(
                          value: _type,
                          options: const [
                            SegmentOption(CategoryType.expense, 'Expense'),
                            SegmentOption(CategoryType.income, 'Income'),
                          ],
                          onChanged: (value) => setState(() => _type = value),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const _FieldLabel('Icon'),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final name in categoryIconNames)
                            _IconOption(
                              name: name,
                              accent: colorFromHex(_color) ?? c.primary,
                              selected: name == _icon,
                              onTap: () => setState(() => _icon = name),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const _FieldLabel('Colour'),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final hex in _swatches)
                            _ColorOption(
                              hex: hex,
                              selected:
                                  hex.toUpperCase() == _color.toUpperCase(),
                              onTap: () => setState(() => _color = hex),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      AppSelect<String>(
                        label: 'Group',
                        hint: 'Choose a group',
                        value: _group,
                        items: [
                          for (final entry in categoryGroupLabels.entries)
                            SelectItem(entry.key, entry.value),
                        ],
                        onChanged: (value) => setState(() => _group = value),
                      ),
                      if (_formError != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _formError!,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: c.destructive,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Column(
                    children: [
                      AppButton(
                        label: _isEdit ? 'Save changes' : 'Create category',
                        busy: _busy,
                        onPressed: _save,
                      ),
                      if (_isEdit) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _busy ? null : _delete,
                          style: TextButton.styleFrom(
                            foregroundColor: c.destructive,
                            minimumSize: const Size(double.infinity, 44),
                          ),
                          child: const Text('Delete category'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }
}

class _IconOption extends StatelessWidget {
  const _IconOption({
    required this.name,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.14) : c.secondary,
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(
            color: selected ? accent : c.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Icon(
          lucideIcon(name),
          size: 20,
          color: selected ? accent : c.mutedForeground,
        ),
      ),
    );
  }
}

class _ColorOption extends StatelessWidget {
  const _ColorOption({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = colorFromHex(hex) ?? c.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 38,
        height: 38,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}
