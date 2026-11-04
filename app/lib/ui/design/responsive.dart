/// How screens decide between their two layouts.
library;

import 'package:flutter/widgets.dart';

const _compactWidth = 840.0;
const _shortHeight = 500.0;

/// True on phones and portrait tablets, where a screen shows one pane at a time
/// and the controls move within reach of a thumb.
bool isCompact(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width < _compactWidth || size.height < _shortHeight;
}

/// True on a phone held sideways, where height is the scarce thing.
bool isShort(BuildContext context) =>
    MediaQuery.sizeOf(context).height < _shortHeight;
