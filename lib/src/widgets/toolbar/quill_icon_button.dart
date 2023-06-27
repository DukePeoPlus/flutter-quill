import 'package:flutter/material.dart';

import '../../utils/widgets.dart';

class QuillIconButton extends StatelessWidget {
  const QuillIconButton({
    required this.onPressed,
    this.afterPressed,
    this.icon,
    this.size = 40,
    this.fillColor,
    this.hoverElevation = 1,
    this.highlightElevation = 1,
    this.borderRadius = 2,
    this.tooltip,
    this.border,
    Key? key,
  }) : super(key: key);

  final VoidCallback? onPressed;
  final VoidCallback? afterPressed;
  final Widget? icon;
  final double size;
  final Color? fillColor;
  final double hoverElevation;
  final double highlightElevation;
  final double borderRadius;
  final BoxBorder? border;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints.tightFor(width: size, height: size),
      child: UtilityWidgets.maybeTooltip(
        message: tooltip,
        child: Container(
          decoration: BoxDecoration(
            border: border,
            borderRadius: BorderRadius.circular(borderRadius)
          ),
          child: RawMaterialButton(
            visualDensity: VisualDensity.compact,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(borderRadius)),
            fillColor: fillColor,
            elevation: 0,
            hoverElevation: hoverElevation,
            highlightElevation: hoverElevation,
            onPressed: () {
              onPressed?.call();
              afterPressed?.call();
            },
            child: icon,
          ),
        ),
      ),
    );
  }
}
