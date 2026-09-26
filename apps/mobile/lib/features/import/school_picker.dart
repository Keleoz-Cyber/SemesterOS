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
            const Text(
              '导入学校课表',
              style: TextStyle(fontSize: 27, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            const Text(
              '选择学校后，在教务系统原网页登录。',
              style: TextStyle(color: CampusColors.muted),
            ),
            const SizedBox(height: 24),
            TextField(
              decoration: const InputDecoration(
                hintText: '搜索学校名称',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
            const SizedBox(height: 22),
            if (matches)
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(18),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEAE5FF),
                    child: Icon(
                      Icons.school_outlined,
                      color: CampusColors.primary,
                    ),
                  ),
                  title: const Text(
                    '河南工业大学',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text('已适配 · 正方教务'),
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
            OutlinedButton.icon(
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
