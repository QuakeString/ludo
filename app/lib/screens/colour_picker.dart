import 'package:flutter/material.dart';

import '../theme/seat_colors.dart';

/// The colour this player plays in, on every board this phone shows.
///
/// Offered before an online game, next to the player's name: online is where
/// everyone else's choice does not matter.
class ColourPicker extends StatefulWidget {
  const ColourPicker({super.key, this.onPicked});

  /// After the choice is saved, for a screen that paints with it.
  final VoidCallback? onPicked;

  @override
  State<ColourPicker> createState() => _ColourPickerState();
}

class _ColourPickerState extends State<ColourPicker> {
  Future<void> _pick(Color colour) async {
    await FavouriteColour.save(colour);
    if (!mounted) return;
    setState(() {});
    widget.onPicked?.call();
  }

  @override
  Widget build(BuildContext context) {
    final palette = BoardPalette.of(context);
    final chosen = favouriteColour ?? ludoRed;
    return Column(
      children: [
        Text(
          'Your colour',
          style: TextStyle(fontSize: 12.5, color: palette.faint),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            for (final colour in seatColors)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Semantics(
                  label: nameOfColour(colour),
                  selected: colour == chosen,
                  button: true,
                  child: InkResponse(
                    key: ValueKey('colour-${nameOfColour(colour)}'),
                    onTap: () => _pick(colour),
                    radius: 22,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colour,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colour == chosen
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: colour == chosen
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
