import 'package:flutter/material.dart';
import 'campus_theme.dart';

String appClockText(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Wraps normal contents closely; long contents scroll behind a fixed action.
class AppTimeSheetLayout extends StatelessWidget {
  final Widget heading, body, footer;
  const AppTimeSheetLayout({
    super.key,
    required this.heading,
    required this.body,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // The sheet route consumes its handle and viewport margin outside this
    // layout. A small inset also leaves room for device safe areas.
    final available =
        ((media.size.height -
                        media.padding.vertical -
                        media.viewInsets.bottom) *
                    .95 -
                24)
            .clamp(0.0, double.infinity)
            .toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: available),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          Flexible(
            child: SingleChildScrollView(
              key: const Key('app-time-sheet-body'),
              child: body,
            ),
          ),
          footer,
        ],
      ),
    );
  }
}

/// A compact HH:mm wheel with every minute available.
class AppClockWheel extends StatelessWidget {
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;
  final bool enabled;
  const AppClockWheel({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) => AppMinuteWheel(
    value: value.hour * 60 + value.minute,
    enabled: enabled,
    onChanged: (value) =>
        onChanged(TimeOfDay(hour: value ~/ 60, minute: value % 60)),
  );
}

/// Minute fields, with 24:00 available only as an explicit range endpoint.
class AppMinuteWheel extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled, allowEndOfDay;
  final String? label;
  const AppMinuteWheel({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.allowEndOfDay = false,
    this.label,
  });
  @override
  State<AppMinuteWheel> createState() => _AppMinuteWheelState();
}

class _AppMinuteWheelState extends State<AppMinuteWheel> {
  int get _visibleValue =>
      widget.value.clamp(0, widget.allowEndOfDay ? 1440 : 1439);
  late final _hours = FixedExtentScrollController(
    initialItem: _visibleValue ~/ 60,
  );
  late final _minutes = FixedExtentScrollController(
    initialItem: _visibleValue % 60,
  );
  late int _current = _visibleValue;
  bool _syncing = false, _scheduled = false;

  @override
  void didUpdateWidget(covariant AppMinuteWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _current = _visibleValue;
    if (widget.value != oldWidget.value && !_scheduled) {
      _scheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scheduled = false;
        if (!mounted) return;
        _syncing = true;
        final hour = _visibleValue ~/ 60, minute = _visibleValue % 60;
        if (_hours.hasClients && _hours.selectedItem != hour) {
          _hours.jumpToItem(hour);
        }
        if (_minutes.hasClients && _minutes.selectedItem != minute) {
          _minutes.jumpToItem(minute);
        }
        _syncing = false;
      });
    }
  }

  void _change(int value, {required bool hour}) {
    if (_syncing || !widget.enabled) return;
    final selectedHour = hour ? value : _current ~/ 60;
    if (!hour && selectedHour == 24) return;
    final next = selectedHour == 24
        ? 1440
        : selectedHour * 60 + (hour ? _current % 60 : value);
    if (next != _current) {
      _current = next;
      widget.onChanged(next);
    }
  }

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  Widget _column(bool hour, double extent) {
    final current = hour ? _visibleValue ~/ 60 : _visibleValue % 60;
    final max = hour
        ? (widget.allowEndOfDay ? 24 : 23)
        : (_visibleValue == 1440 ? 0 : 59);
    final enabled = widget.enabled && (hour || _visibleValue != 1440);
    return Semantics(
      label: '${widget.label ?? ''}${hour ? '小时' : '分钟'}',
      value: current.toString().padLeft(2, '0'),
      increasedValue: current < max ? '${current + 1}' : null,
      decreasedValue: current > 0 ? '${current - 1}' : null,
      onIncrease: enabled && current < max
          ? () => _change(current + 1, hour: hour)
          : null,
      onDecrease: enabled && current > 0
          ? () => _change(current - 1, hour: hour)
          : null,
      child: ExcludeSemantics(
        child: ListWheelScrollView.useDelegate(
          key: Key(hour ? 'app-clock-hour-wheel' : 'app-clock-minute-wheel'),
          controller: hour ? _hours : _minutes,
          itemExtent: extent,
          physics: enabled
              ? const FixedExtentScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          diameterRatio: 2.3,
          perspective: .002,
          overAndUnderCenterOpacity: .28,
          onSelectedItemChanged: (v) => _change(v, hour: hour),
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: max + 1,
            builder: (context, index) => Center(
              child: Text(
                index.toString().padLeft(2, '0'),
                style: const TextStyle(
                  fontSize: 27,
                  height: 1.15,
                  fontWeight: FontWeight.w600,
                  color: CampusColors.ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(27) / 27;
    final extent = (MediaQuery.textScalerOf(context).scale(27) * 1.2 + 12)
        .clamp(48.0, 120.0)
        .toDouble();
    final media = MediaQuery.of(context);
    final shortViewport = media.size.height - media.viewInsets.bottom < 520;
    final rows = scale > 1.4 || shortViewport ? 3 : 5;
    return SizedBox(
      height: extent * rows,
      child: Stack(
        children: [
          Positioned(
            top: extent * (rows ~/ 2),
            left: 0,
            right: 0,
            height: extent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: CampusColors.blueSoft,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(child: _column(true, extent)),
              const SizedBox(
                width: 16,
                child: Center(
                  child: Text(
                    ':',
                    style: TextStyle(fontSize: 23, color: CampusColors.muted),
                  ),
                ),
              ),
              Expanded(child: _column(false, extent)),
            ],
          ),
        ],
      ),
    );
  }
}
