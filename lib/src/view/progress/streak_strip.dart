import 'package:fast_immutable_collections/fast_immutable_collections.dart';
import 'package:intl/intl.dart';
import 'package:lichess_mobile/src/model/progression/streak.dart';
import 'package:lichess_mobile/src/styles/knightly_theme.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

const _kFreezeBlue = Color(0xFF6EC6FF);

/// The streak of the last days, one column per day: a flame when played, a snowflake when covered by
/// a freeze, a cross when missed, an outlined flame for today until a game is finished.
class const StreakStrip({
  required final IList<({Day day, StreakDayStatus status})> days,

  /// On the orange Today card: drawn in white.
  final bool onAccent = false,
  super.key,
}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.of(context);
    final faded = onAccent ? Colors.white.withValues(alpha: 0.55) : scheme.onSurfaceVariant;
    final flame = onAccent ? Colors.white : Flare.orange;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final (:day, :status) in days)
          Column(
            children: [
              Text(
                DateFormat.E().format(day.dateTime).substring(0, 1),
                style: TextStyle(color: faded, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4.0),
              switch (status) {
                StreakDayStatus.played => Icon(
                  Symbols.local_fire_department,
                  fill: 1,
                  color: flame,
                  size: 28,
                ),
                StreakDayStatus.frozen => const Icon(
                  Symbols.ac_unit,
                  color: _kFreezeBlue,
                  size: 28,
                ),
                StreakDayStatus.missed => Icon(Symbols.close, color: faded, size: 28),
                StreakDayStatus.pending => Icon(
                  Symbols.local_fire_department,
                  color: faded,
                  size: 28,
                ),
                StreakDayStatus.notCounted => Icon(Symbols.remove, color: faded, size: 28),
              },
            ],
          ),
      ],
    );
  }
}
