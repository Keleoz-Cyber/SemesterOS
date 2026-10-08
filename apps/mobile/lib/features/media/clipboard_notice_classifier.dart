/// A cheap, local hint for the clipboard affordance, not a notice parser.
/// It never extracts a date, changes a draft, or sends the text anywhere.
bool isPlausibleClipboardNotice(String value) {
  var text = value.trim();
  if (text.isEmpty) return false;
  // Bound pattern matching without retaining the clipboard's original text.
  if (text.length > 24000) {
    text = '${text.substring(0, 16000)}\n${text.substring(text.length - 8000)}';
  }
  text = text
      .replaceAllMapped(RegExp('[０-９]'), (match) {
        return String.fromCharCode(match[0]!.codeUnitAt(0) - 0xff10 + 0x30);
      })
      .replaceAll('：', ':');
  if (_code.hasMatch(text) || _credentials.hasMatch(text)) return false;
  // Links in a real notice are fine; a copied link/email/path alone is silent.
  final withoutLinks = text.replaceAll(_links, '').trim();
  if (withoutLinks.isEmpty || _path.hasMatch(text)) return false;

  final time = _date.hasMatch(text) || _clock.hasMatch(text);
  final period = _period.hasMatch(text);
  final action = _action.hasMatch(text);
  final activity = _activity.hasMatch(text);
  if ((time || period) && (action || activity || period)) return true;
  // A bare time range is already useful scheduling information.
  if (_clockRange.hasMatch(text)) return true;
  // Do not require a precise time: notices and tasks often omit one.
  return (action || activity) &&
      (_notice.hasMatch(text) ||
          _directive.hasMatch(text) ||
          _deadline.hasMatch(text));
}

final _code = RegExp(
  r'''^\s*(?:```|[\[{][\s\S]*[\]}]\s*$|(?:const|let|var)\s+\w+\s*[=:]|(?:function|def)\s+\w+\s*\(|class\s+\w+(?:\s+(?:extends|implements)\s+\w+)?\s*[:{(]|(?:import|export)\s+[^\n]*["']|from\s+[\w.]+\s+import\b|(?:insert\s+into|delete\s+from|create\s+table|drop\s+table)\b|select\s+[^\n]+\s+from\b)|(?:=>|\b(?:console\.log|print|setState)\s*\()''',
  multiLine: true,
  caseSensitive: false,
);
final _credentials = RegExp(
  r'(?:^|\n)\s*(?:密码|口令|验证码|password|passwd|api[_ -]?key|access[_ -]?token|secret)\s*[:=]\s*\S+',
  caseSensitive: false,
);
final _links = RegExp(
  r'(?:https?://|www\.)\S+|[\w.+-]+@[\w.-]+\.[a-z]{2,}',
  caseSensitive: false,
);
final _path = RegExp(r'^(?:[A-Za-z]:[\\/]|/(?:Users|home|tmp|var)/)\S+$');
final _date = RegExp(
  r'(?:\d{1,4}[年/.-])?\d{1,2}(?:月|[/.-])\d{1,2}(?:日|号)?|\d{1,2}(?:日|号)|(?:今天|明天|后天|今晚|明早|明晚|本周|这周|下周|本月|下月|周末|(?:星期|礼拜|周)[一二三四五六日天1-7])|\b(?:today|tomorrow|tonight|next\s+(?:week|month)|(?:mon|tues|wednes|thurs|fri|satur|sun)day)\b|\b(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:tember)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?\s+\d{1,2}\b',
  caseSensitive: false,
);
final _clock = RegExp(
  r'(?:[01]?\d|2[0-3]):[0-5]\d|(?:凌晨|早上|上午|中午|下午|晚上)?[零〇一二两三四五六七八九十\d]{1,3}点(?:半|一刻|三刻|[一二三四五六七八九十\d]+分)?|\b(?:1[0-2]|[1-9])(?::[0-5]\d)?\s*(?:am|pm)\b',
  caseSensitive: false,
);
final _clockRange = RegExp(
  r'(?:[01]?\d|2[0-3]):[0-5]\d\s*(?:[-–—~～]|至|到|to)\s*(?:[01]?\d|2[0-3]):[0-5]\d',
  caseSensitive: false,
);
final _period = RegExp(
  r'(?:第)?[一二三四五六七八九十\d]+(?:\s*[-–—、,]\s*[一二三四五六七八九十\d]+)?\s*节',
);
final _action = RegExp(
  r'提交|上交|交齐|补交|领取|缴费|报名|签到|集合|到场|前往|携带|准备|完成|预习|复习|练习|学习|预约|参加|停课|调课|补课|上课|开会|彩排|排练|面试|出发|约饭|聚餐|打球|打篮球|踢球|健身|购买|买|还书|取快递|寄快递|打印|打电话|(?:去|到|约|见|吃).{0,12}(?:食堂|图书馆|自习|饭|餐|火锅|电影|球|健身|医院|医生|车站|机场|同学|老师)|\b(?:submit|send|hand\s+in|bring|attend|meet|study|revise|register|apply|finish|prepare|rehearse|cancel|reschedule|call|email|pay|book|visit|practice|write|buy)\b',
  caseSensitive: false,
);
final _activity = RegExp(
  r'课程|上课|有课|作业|考试|测验|彩排|排练|联排|候场|考勤|座谈|讲座|会议|班会|组会|答辩|实习|体检|活动|社团|报告|论文|运动会|球赛|演出|面试|自习|学习|\b(?:class|course|exam|test|homework|assignment|meeting|lecture|rehearsal|appointment|interview|practice)\b',
  caseSensitive: false,
);
final _notice = RegExp(
  r'(?:^|\n)\s*(?:[【\[])?(?:通知|公告|提醒|安排|notice|announcement|reminder)(?:[】\]])?[^\w\u4e00-\u9fff]{0,4}\s*[:!！\n]',
  caseSensitive: false,
);
final _directive = RegExp(
  r'请(?:大家|各位|同学|班长|负责人)?|务必|记得|需要|必须|@所有人|@全体成员|\b(?:please|remember\s+to|must|need\s+to)\b',
  caseSensitive: false,
);
final _deadline = RegExp(r'截止|最后期限|\b(?:due|deadline)\b', caseSensitive: false);
