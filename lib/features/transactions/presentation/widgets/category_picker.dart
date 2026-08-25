import '../../../../core/ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../../core/api/enums.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../../../core/widgets/category_avatar.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_retry.dart';
import '../../../../core/widgets/loading_shimmer.dart';
import '../../../categories/data/categories_repository.dart';
import '../../../categories/domain/category.dart';
import 'account_picker.dart' show PickerField;

/// Opens the searchable category sheet, filtered to [type] (income categories
/// for income, expense for expense). Resolves to the chosen category, or null
/// when the sheet is dismissed.
Future<Category?> showCategoryPicker(
  BuildContext context, {
  required CategoryType type,
  String? selectedId,
}) {
  return showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CategoryPickerSheet(type: type, selectedId: selectedId),
  );
}

/// A [PickerField] wired to [showCategoryPicker]. The category is optional, so
/// a selected value gets a clear button in place of the chevron.
class CategoryPickerField extends StatelessWidget {
  const CategoryPickerField({
    super.key,
    required this.type,
    required this.value,
    required this.onChanged,
    this.label = 'Category',
    this.hint = 'Optional',
    this.errorText,
  });

  final CategoryType type;
  final Category? value;

  /// Called with null when the selection is cleared.
  final ValueChanged<Category?> onChanged;
  final String label;
  final String hint;
  final String? errorText;

  Future<void> _open(BuildContext context) async {
    final picked = await showCategoryPicker(
      context,
      type: type,
      selectedId: value?.id,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final category = value;

    return PickerField(
      label: label,
      hint: hint,
      value: category?.name,
      errorText: errorText,
      onTap: () => _open(context),
      leading: category == null
          ? null
          : CategoryAvatar(
              icon: category.icon,
              colorHex: category.color,
              size: 30,
            ),
      trailing: category == null
          ? null
          : IconButton(
              onPressed: () => onChanged(null),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              tooltip: tr(context, 'Clear category'),
              icon: Icon(LucideIcons.x, size: 17, color: c.mutedForeground),
            ),
    );
  }
}

class _CategoryPickerSheet extends ConsumerStatefulWidget {
  const _CategoryPickerSheet({required this.type, this.selectedId});

  final CategoryType type;
  final String? selectedId;

  @override
  ConsumerState<_CategoryPickerSheet> createState() =>
      _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends ConsumerState<_CategoryPickerSheet> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final categories = ref.watch(categoriesProvider);
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85 - insets;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight < 260 ? 260 : maxHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.type == CategoryType.income
                          ? 'Income category'
                          : 'Expense category',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      LucideIcons.x,
                      size: 20,
                      color: c.mutedForeground,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: AppTextField(
                controller: _search,
                hint: 'Search categories',
                onChanged: (value) => setState(() => _query = value.trim()),
                textInputAction: TextInputAction.search,
                prefix: Icon(
                  LucideIcons.search,
                  size: 18,
                  color: c.mutedForeground,
                ),
              ),
            ),
            Divider(height: 1, color: c.border),
            Flexible(
              child: categories.when(
                loading: () => const Padding(
                  padding: EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    children: [
                      LoadingShimmer(height: 48),
                      SizedBox(height: 10),
                      LoadingShimmer(height: 48),
                      SizedBox(height: 10),
                      LoadingShimmer(height: 48),
                    ],
                  ),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: ErrorRetry(
                    error: error,
                    compact: true,
                    onRetry: () => ref.invalidate(categoriesFetchProvider),
                  ),
                ),
                data: _list,
              ),
            ),
            SizedBox(height: 8 + MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }

  Widget _list(List<Category> all) {
    final query = _query.toLowerCase();
    final matches = all.where((category) {
      if (category.type != widget.type) return false;
      if (query.isEmpty) return true;
      final group = categoryGroupLabels[category.group ?? ''] ?? '';
      return category.name.toLowerCase().contains(query) ||
          group.toLowerCase().contains(query);
    }).toList();

    if (matches.isEmpty) {
      return EmptyState(
        icon: LucideIcons.tag,
        title: query.isEmpty ? 'No categories yet' : 'No matches',
        message: query.isEmpty
            ? 'Create one on the Categories screen.'
            : 'Nothing matches “$_query”.',
        compact: true,
      );
    }

    // Grouped in the order the API seeds them, with anything unrecognised last.
    final grouped = <String, List<Category>>{};
    for (final category in matches) {
      final key = categoryGroupLabels.containsKey(category.group)
          ? category.group!
          : 'other';
      (grouped[key] ??= <Category>[]).add(category);
    }

    final order = categoryGroupLabels.keys.where(grouped.containsKey).toList();
    final children = <Widget>[];
    for (final key in order) {
      final rows = grouped[key]!
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      children.add(_groupLabel(categoryGroupLabels[key] ?? 'Other'));
      for (final category in rows) {
        children.add(
          _CategoryRow(
            category: category,
            selected: category.id == widget.selectedId,
          ),
        );
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: children,
    );
  }

  Widget _groupLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 12, 8, 6),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.6,
        color: context.colors.mutedForeground,
      ),
    ),
  );
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.selected});

  final Category category;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(AppTheme.radius);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? c.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(category),
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                CategoryAvatar(
                  icon: category.icon,
                  colorHex: category.color,
                  size: 36,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    category.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  Icon(LucideIcons.check, size: 18, color: c.primary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
