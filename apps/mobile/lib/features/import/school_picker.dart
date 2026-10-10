import '../../ui/app_controls.dart';
import '../../ui/empty_states.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../ui/campus_theme.dart';
import 'school_adapters.dart';
import '../centers/academic_visuals.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../ui/v2/shiri_tokens.dart' as v2;
import '../../ui/v2/widgets/wave_edge.dart';

class SchoolPickerPage extends StatefulWidget {
  final ValueChanged<SchoolAdapter> onSelect;
  final VoidCallback onManual;
  const SchoolPickerPage({
    super.key,
    required this.onSelect,
    required this.onManual,
  });
  @override
  State<SchoolPickerPage> createState() => _SchoolPickerPageState();
}

class _SchoolPickerPageState extends State<SchoolPickerPage> {
  String query = '';
  final queryController = TextEditingController();
  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = supportedSchools
        .where((school) => school.matches(query))
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入课表'),
        leading: AppIconButton(
          tooltip: '返回',
          onPressed: () {
            final router = GoRouter.maybeOf(context);
            if (router?.canPop() == true) {
              router!.pop();
            } else if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              router?.go('/');
            }
          },
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, bounds) {
            final compact = bounds.maxHeight < 430;
            final tiny = bounds.maxHeight < 250;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                  child: Semantics(
                    label: tiny ? '第1步，共3步，选择学校' : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!compact)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            height: 72,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              gradient: v2.ShiriGradients.brandSoft,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Stack(
                              children: [
                                const Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: WaveEdge(height: 22),
                                ),
                                Positioned(
                                  left: 20,
                                  top: 12,
                                  child: SvgPicture.asset(
                                    'assets/brand/mark.svg',
                                    width: 36,
                                    height: 36,
                                    excludeFromSemantics: true,
                                  ),
                                ),
                                Positioned(
                                  right: 14,
                                  bottom: 0,
                                  child: SvgPicture.asset(
                                    'assets/illustrations/import-timetable.svg',
                                    width: 86,
                                    height: 64,
                                    excludeFromSemantics: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (!tiny)
                          compact
                              ? const Padding(
                                  padding: EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    '1 / 3 · 选择学校',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: CampusColors.muted,
                                    ),
                                  ),
                                )
                              : const AcademicStepRail(
                                  steps: ['选择学校', '登录教务', '核对课表'],
                                  current: 0,
                                ),
                        AppField(
                          key: const Key('school-search-field'),
                          controller: queryController,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            labelText: '学校名称',
                            hintText: '搜索学校名称',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: query.isEmpty
                                ? null
                                : AppIconButton(
                                    tooltip: '清空学校搜索',
                                    icon: const Icon(Icons.close_rounded),
                                    onPressed: () {
                                      queryController.clear();
                                      setState(() => query = '');
                                    },
                                  ),
                          ),
                          onChanged: (value) => setState(() => query = value),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    key: const PageStorageKey('school-results'),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                query.trim().isEmpty ? '已适配学校' : '搜索结果',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${matches.length} 所',
                              style: const TextStyle(
                                fontSize: 13,
                                color: CampusColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (matches.isNotEmpty)
                        for (final school in matches)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Material(
                              color: CampusColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              clipBehavior: Clip.antiAlias,
                              child: AppTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 16,
                                ),
                                leading: ExcludeSemantics(
                                  child: Container(
                                    width: 48,
                                    height: 48,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: school.id == 'hlju'
                                          ? CampusColors.tealSoft
                                          : CampusColors.blueSoft,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Text(
                                      school.id == 'hlju' ? '黑大' : '工大',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: school.id == 'hlju'
                                            ? CampusColors.teal
                                            : CampusColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  school.name,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    school.description,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      color: CampusColors.muted,
                                    ),
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_rounded,
                                  size: 20,
                                  color: CampusColors.muted,
                                ),
                                onTap: () {
                                  FocusManager.instance.primaryFocus?.unfocus();
                                  widget.onSelect(school);
                                },
                              ),
                            ),
                          )
                      else
                        NoSearchResults(
                          query: query,
                          title: '暂未适配这所学校',
                          message: '',
                          clearLabel: '手工添加课程',
                          onClear: widget.onManual,
                        ),
                      if (matches.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        Material(
                          color: CampusColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          child: AppTile(
                            leading: const Icon(
                              Icons.edit_calendar_outlined,
                              color: CampusColors.teal,
                            ),
                            title: const Text('手工添加课程'),
                            trailing: const Icon(
                              Icons.chevron_right_rounded,
                              color: CampusColors.muted,
                            ),
                            onTap: widget.onManual,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
