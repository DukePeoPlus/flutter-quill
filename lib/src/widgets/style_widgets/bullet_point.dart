import 'package:flutter/material.dart';
import '../../models/documents/attribute.dart';

class QuillBulletPoint extends StatelessWidget {
  const QuillBulletPoint({
    required this.index,
    required this.indentLevelCounts,
    required this.count,
    required this.style,
    required this.width,
    required this.attrs,
    this.padding = 0.0,
    Key? key,
  }) : super(key: key);

  final int index;
  final Map<int?, int> indentLevelCounts;
  final int count;
  final TextStyle style;
  final double width;
  final Map<String, Attribute> attrs;
  final double padding;
  static final List<String> bullets = [
    '/u25CF',
    '/u25CB',
    '/u25A0',
  ];

  @override
  Widget build(BuildContext context) {
    var s = bullets.first;
    int? level = 0;
    
    if (attrs.containsKey(Attribute.indent.key)) {
      level = attrs[Attribute.indent.key]!.value;
    } else if (!indentLevelCounts.containsKey(0)) {
      // first level but is back from previous indent level
      // supposed to be "2."
      indentLevelCounts[0] = 1;
    }
    if (indentLevelCounts.containsKey(level! + 1)) {
      // last visited level is done, going up
      indentLevelCounts.remove(level + 1);
    }
    final count = (indentLevelCounts[level] ?? 0) + 1;
    indentLevelCounts[level] = count;

    s = bullets[count % 3];
    return Container(
      alignment: AlignmentDirectional.topEnd,
      width: width,
      padding: EdgeInsetsDirectional.only(end: padding),
      child: Text(s, style: style),
    );
  }
}
