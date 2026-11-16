import 'package:material_ui/material_ui.dart';

/// What Knightly is, in one line (replaces lichess's "free, libre, open source" message).
class const KnightlyMessage({super.key, final TextStyle? style}) extends StatelessWidget {
  static const text = 'Knightly: your personal chess training, on your lichess.org account.';

  @override
  Widget build(BuildContext context) {
    return Text(text, style: style);
  }
}
