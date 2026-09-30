import '../../ui/app_controls.dart';
import '../../ui/detail_widgets.dart';
import 'package:flutter/material.dart';
import '../../ui/campus_theme.dart';

class SchoolPickerPage extends StatefulWidget {
  final VoidCallback onSelect, onManual;
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
  @override
  Widget build(BuildContext context) {
    final matches =
        query.trim().isEmpty ||
        '河南工业大学 haut 郑州'.contains(query.trim().toLowerCase());
    return Scaffold(
      appBar: AppBar(title: const Text('选择学校')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const WorkflowHeader(steps: ['选择学校', '登录教务', '核对课表'], current: 0),
            AppField(
              decoration: const InputDecoration(
                labelText: '学校名称',
                hintText: '搜索学校名称',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 22),
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                '已适配学校',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            if (matches)
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                child: AppTile(
                  contentPadding: const EdgeInsets.all(18),
                  leading: const CircleAvatar(
                    backgroundColor: CampusColors.tealSoft,
                    child: Icon(
                      Icons.school_outlined,
                      color: CampusColors.primary,
                    ),
                  ),
                  title: const Text(
                    '河南工业大学',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('进入学校原网页，登录后读取个人课表'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: widget.onSelect,
                ),
              )
            else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Text('暂未适配这所学校。你可以先手工添加课程。'),
              ),
            const SizedBox(height: 24),
            AppOutlineButton.icon(
              onPressed: widget.onManual,
              icon: const Icon(Icons.edit_calendar_outlined),
              label: const Text('手工添加课程'),
            ),
          ],
        ),
      ),
    );
  }
}
