import '../../ui/app_controls.dart';
import '../../ui/empty_states.dart';
import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';
import 'school_adapters.dart';
import '../centers/academic_visuals.dart';

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
      appBar: AppBar(title: const Text('导入课表')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            const AcademicStepRail(steps: ['选择学校', '登录教务', '核对课表'], current: 0),
            AppField(
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
            const SizedBox(height: 24),
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
                  child: Container(
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: CampusColors.line),
                      ),
                    ),
                    child: AppTile(
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 4,
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
                onClear: () {
                  queryController.clear();
                  setState(() => query = '');
                },
              ),
            const SizedBox(height: 32),
            AppTile(
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
          ],
        ),
      ),
    );
  }
}
