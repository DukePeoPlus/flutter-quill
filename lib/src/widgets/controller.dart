import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/src/models/documents/nodes/node.dart';
import 'package:flutter_quill/src/widgets/toolbar/link_style_button.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';

import '../models/documents/attribute.dart';
import '../models/documents/document.dart';
import '../models/documents/nodes/embeddable.dart';
import '../models/documents/nodes/leaf.dart';
import '../models/documents/style.dart';
import '../models/quill_delta.dart';
import '../models/structs/doc_change.dart';
import '../models/structs/image_url.dart';
import '../models/structs/offset_value.dart';
import '../utils/delta.dart';

typedef ReplaceTextCallback = bool Function(int index, int len, Object? data);
typedef DeleteCallback = void Function(int cursorPosition, bool forward);

class QuillController extends ChangeNotifier {
  QuillController({
    required Document document,
    required TextSelection selection,
    bool keepStyleOnNewLine = false,
    this.onReplaceText,
    this.onDelete,
    this.onSelectionCompleted,
    this.onSelectionChanged,
  })  : _document = document,
        _selection = selection,
        _keepStyleOnNewLine = keepStyleOnNewLine;

  factory QuillController.basic() {
    return QuillController(
      document: Document(),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  /// Document managed by this controller.
  Document _document;
  Document get document => _document;
  set document(doc) {
    _document = doc;

    // Prevent the selection from
    _selection = const TextSelection(baseOffset: 0, extentOffset: 0);
    notifyListeners();
  }

  /// Tells whether to keep or reset the [toggledStyle]
  /// when user adds a new line.
  final bool _keepStyleOnNewLine;

  /// Currently selected text within the [document].
  TextSelection get selection => _selection;
  TextSelection _selection;

  /// Custom [replaceText] handler
  /// Return false to ignore the event
  ReplaceTextCallback? onReplaceText;

  /// Custom delete handler
  DeleteCallback? onDelete;

  void Function()? onSelectionCompleted;
  void Function(TextSelection textSelection)? onSelectionChanged;

  /// Store any styles attribute that got toggled by the tap of a button
  /// and that has not been applied yet.
  /// It gets reset after each format action within the [document].
  Style toggledStyle = Style();

  bool ignoreFocusOnTextChange = false;

  /// Skip requestKeyboard being called in
  /// RawEditorState#_didChangeTextEditingValue
  bool skipRequestKeyboard = false;

  /// True when this [QuillController] instance has been disposed.
  ///
  /// A safety mechanism to ensure that listeners don't crash when adding,
  /// removing or listeners to this instance.
  bool _isDisposed = false;

  Stream<DocChange> get changes => document.changes;

  TextEditingValue get plainTextEditingValue => TextEditingValue(
        text: document.toPlainText(),
        selection: selection,
      );

  /// Only attributes applied to all characters within this range are
  /// included in the result.
  Style getSelectionStyle() {
    return document
        .collectStyle(selection.start, selection.end - selection.start)
        .mergeAll(toggledStyle);
  }

  // Increases or decreases the indent of the current selection by 1.
  void indentSelection(bool isIncrease) {
    if (selection.isCollapsed) {
      _indentSelectionFormat(isIncrease);
    } else {
      _indentSelectionEachLine(isIncrease);
    }
  }

  void _indentSelectionFormat(bool isIncrease) {
    final indent = getSelectionStyle().attributes[Attribute.indent.key];
    if (indent == null) {
      if (isIncrease) {
        formatSelection(Attribute.indentL1);
      }
      return;
    }
    if (indent.value == 1 && !isIncrease) {
      formatSelection(Attribute.clone(Attribute.indentL1, null));
      return;
    }
    
    if (isIncrease) {
      if (indent.value < 2) {
        formatSelection(Attribute.getIndentLevel(indent.value + 1));
      }
      return;
    }
    formatSelection(Attribute.getIndentLevel(indent.value - 1));
  }

  void _indentSelectionEachLine(bool isIncrease) {
    final styles = document.collectAllStylesWithOffset(
      selection.start,
      selection.end - selection.start,
    );
    for (final style in styles) {
      final indent = style.value.attributes[Attribute.indent.key];
      final formatIndex = math.max(style.offset, selection.start);
      final formatLength = math.min(
            style.offset + (style.length ?? 0),
            selection.end,
          ) -
          style.offset;
      Attribute? formatAttribute;
      if (indent == null) {
        if (isIncrease) {
          formatAttribute = Attribute.indentL1;
        }
      } else if (indent.value == 1 && !isIncrease) {
        formatAttribute = Attribute.clone(Attribute.indentL1, null);
      } else if (isIncrease) {
        formatAttribute = Attribute.getIndentLevel(indent.value + 1);
      } else {
        formatAttribute = Attribute.getIndentLevel(indent.value - 1);
      }
      if (formatAttribute != null) {
        document.format(formatIndex, formatLength, formatAttribute);
      }
    }
    notifyListeners();
  }

  /// Returns all styles for each node within selection
  List<OffsetValue<Style>> getAllIndividualSelectionStyles() {
    final styles = document.collectAllIndividualStyles(
        selection.start, selection.end - selection.start);
    return styles;
  }

  /// Returns plain text for each node within selection
  String getPlainText() {
    final text =
        document.getPlainText(selection.start, selection.end - selection.start);
    return text;
  }

  /// Returns all styles for any character within the specified text range.
  List<Style> getAllSelectionStyles() {
    final styles = document.collectAllStyles(
        selection.start, selection.end - selection.start)
      ..add(toggledStyle);
    return styles;
  }

  void undo() {
    final result = document.undo();
    if (result.changed) {
      _handleHistoryChange(result.len);
    }
  }

  void _handleHistoryChange(int? len) {
    if (len! != 0) {
      // if (this.selection.extentOffset >= document.length) {
      // // cursor exceeds the length of document, position it in the end
      // updateSelection(
      // TextSelection.collapsed(offset: document.length), ChangeSource.LOCAL);
      updateSelection(
          TextSelection.collapsed(offset: selection.baseOffset + len),
          ChangeSource.LOCAL);
    } else {
      // no need to move cursor
      notifyListeners();
    }
  }

  void redo() {
    final result = document.redo();
    if (result.changed) {
      _handleHistoryChange(result.len);
    }
  }

  bool get hasUndo => document.hasUndo;

  bool get hasRedo => document.hasRedo;

  /// clear editor
  void clear() {
    replaceText(0, plainTextEditingValue.text.length - 1, '',
        const TextSelection.collapsed(offset: 0));
  }

  void replaceText(
      int index, int len, Object? data, TextSelection? textSelection,
      {bool ignoreFocus = false}) {
    assert(data is String || data is Embeddable);

    if (onReplaceText != null && !onReplaceText!(index, len, data)) {
      return;
    }

    Delta? delta;
    if (len > 0 || data is! String || data.isNotEmpty) {
      delta = document.replace(index, len, data);
      var shouldRetainDelta = toggledStyle.isNotEmpty &&
          delta.isNotEmpty &&
          delta.length <= 2 &&
          delta.last.isInsert;
      if (shouldRetainDelta &&
          toggledStyle.isNotEmpty &&
          delta.length == 2 &&
          delta.last.data == '\n') {
        // if all attributes are inline, shouldRetainDelta should be false
        final anyAttributeNotInline =
            toggledStyle.values.any((attr) => !attr.isInline);
        if (!anyAttributeNotInline) {
          shouldRetainDelta = false;
        }
      }
      if (shouldRetainDelta) {
        final retainDelta = Delta()
          ..retain(index)
          ..retain(data is String ? data.length : 1, toggledStyle.toJson());
        document.compose(retainDelta, ChangeSource.LOCAL);
      }
    }

    if (textSelection != null) {
      if (delta == null || delta.isEmpty) {
        _updateSelection(textSelection, ChangeSource.LOCAL);
      } else {
        final user = Delta()
          ..retain(index)
          ..insert(data)
          ..delete(len);
        final positionDelta = getPositionDelta(user, delta);
        _updateSelection(
          textSelection.copyWith(
            baseOffset: textSelection.baseOffset + positionDelta,
            extentOffset: textSelection.extentOffset + positionDelta,
          ),
          ChangeSource.LOCAL,
        );
      }
    }

    if (ignoreFocus) {
      ignoreFocusOnTextChange = true;
    }
    notifyListeners();
    ignoreFocusOnTextChange = false;
  }

  /// Called in two cases:
  /// forward == false && textBefore.isEmpty
  /// forward == true && textAfter.isEmpty
  /// Android only
  /// see https://github.com/singerdmx/flutter-quill/discussions/514
  void handleDelete(int cursorPosition, bool forward) =>
      onDelete?.call(cursorPosition, forward);

  void formatTextStyle(int index, int len, Style style) {
    style.attributes.forEach((key, attr) {
      formatText(index, len, attr);
    });
  }

  void formatText(int index, int len, Attribute? attribute) {
    if (len == 0 &&
        attribute!.isInline &&
        attribute.key != Attribute.link.key) {
      // Add the attribute to our toggledStyle.
      // It will be used later upon insertion.
      toggledStyle = toggledStyle.put(attribute);
    }

    final change = document.format(index, len, attribute);
    // Transform selection against the composed change and give priority to
    // the change. This is needed in cases when format operation actually
    // inserts data into the document (e.g. embeds).
    final adjustedSelection = selection.copyWith(
        baseOffset: change.transformPosition(selection.baseOffset),
        extentOffset: change.transformPosition(selection.extentOffset));
    if (selection != adjustedSelection) {
      _updateSelection(adjustedSelection, ChangeSource.LOCAL);
    }
    notifyListeners();
  }

  void formatSelection(Attribute? attribute) {
    formatText(selection.start, selection.end - selection.start, attribute);
  }

  void moveCursorToStart() {
    updateSelection(
        const TextSelection.collapsed(offset: 0), ChangeSource.LOCAL);
  }

  void moveCursorToPosition(int position) {
    updateSelection(
        TextSelection.collapsed(offset: position), ChangeSource.LOCAL);
  }

  void moveCursorToEnd() {
    updateSelection(
        TextSelection.collapsed(offset: plainTextEditingValue.text.length),
        ChangeSource.LOCAL);
  }

  void updateSelection(TextSelection textSelection, ChangeSource source) {
    _updateSelection(textSelection, source);
    notifyListeners();
  }

  void compose(Delta delta, TextSelection textSelection, ChangeSource source) {
    if (delta.isNotEmpty) {
      document.compose(delta, source);
    }

    textSelection = selection.copyWith(
        baseOffset: delta.transformPosition(selection.baseOffset, force: false),
        extentOffset:
            delta.transformPosition(selection.extentOffset, force: false));
    if (selection != textSelection) {
      _updateSelection(textSelection, source);
    }

    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    // By using `_isDisposed`, make sure that `addListener` won't be called on a
    // disposed `ChangeListener`
    if (!_isDisposed) {
      super.addListener(listener);
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    // By using `_isDisposed`, make sure that `removeListener` won't be called
    // on a disposed `ChangeListener`
    if (!_isDisposed) {
      super.removeListener(listener);
    }
  }

  @override
  void dispose() {
    if (!_isDisposed) {
      document.close();
    }

    _isDisposed = true;
    super.dispose();
  }

  void _updateSelection(TextSelection textSelection, ChangeSource source) {
    _selection = textSelection;
    final end = document.length - 1;
    _selection = selection.copyWith(
        baseOffset: math.min(selection.baseOffset, end),
        extentOffset: math.min(selection.extentOffset, end));
    if (_keepStyleOnNewLine) {
      final style = getSelectionStyle();
      final notInlineStyle = style.attributes.values.where((s) => !s.isInline);
      toggledStyle = style.removeAll(notInlineStyle.toSet());
    } else {
      toggledStyle = Style();
    }
    onSelectionChanged?.call(textSelection);
  }

  /// Given offset, find its leaf node in document
  Leaf? queryNode(int offset) {
    return document.querySegmentLeafNode(offset).leaf;
  }

  /// Clipboard for image url and its corresponding style
  ImageUrl? _copiedImageUrl;

  ImageUrl? get copiedImageUrl => _copiedImageUrl;

  set copiedImageUrl(ImageUrl? value) {
    _copiedImageUrl = value;
    Clipboard.setData(const ClipboardData(text: ''));
  }

  // Notify toolbar buttons directly with attributes
  Map<String, Attribute> toolbarButtonToggler = {};

  /// isSubmittedInList
  /// 
  /// Type이 list일때 isSubmitted 동작
  /// 
  /// Duke Jeon (duke@peoplus.studio)
  void checkList(
    DocChange event,
    Attribute attr, {
      Function()? onDelete,
      Function()? onEditingComplete,
    }) {
    final length = event.before.toList().length;
    final current = event.change.toList().last;
    final before = event.before.toList().last;
    Operation? prevBefore;

    if (length > 1) {
      prevBefore = event.before.toList()[length - 2];
    }

    final indent = getSelectionStyle().attributes[Attribute.indent.key];
    final tmpCurrentAttr = current.attributes?['list'];
    final tmpBeforeAttr = before.attributes?['list'];
    final currentIndentValue = current.attributes?['indent'];
    final beforeIndentValue = before.attributes?['indent'];

    final checked = Attribute.getValueFromKey('checked');
    final unchecked = Attribute.getValueFromKey('unchecked');
    final isCheckList = attr == checked || attr == unchecked; 

    final functionCondition = indent?.value == null 
      && current.attributes?['list'] == null 
      && before.data == '\n'
      && (before.attributes?['list'] == attr.value || isCheckList);

    final indentValue = indent?.value ?? 0;

    if (current.isRetain && before.isInsert) {
      if (functionCondition) {
        if (length > 1) {
          if (indentValue == 0) {
            if (onEditingComplete != null) {
              final trimNewLineCondition = currentIndentValue == null 
                && beforeIndentValue == null
                && tmpCurrentAttr != attr.value
                && (tmpBeforeAttr == attr.value || isCheckList)
                && indentValue == 0
                || currentIndentValue != null;

              if (trimNewLineCondition) {
                final isBeforeNewLine = before.isInsert && before.data == '\n';
                trimNewLine(isBeforeNewLine: isBeforeNewLine);
                onEditingComplete();
              } else {
                formatSelection(attr);
              }
            }
          }
        } else {
          if (onDelete != null) {
            onDelete();
          }
        }
      } else if (before.data == '\n\n') {
        if (indentValue == 0) {
          final increaseCondition = tmpCurrentAttr != attr.value
            && (tmpBeforeAttr == attr.value || isCheckList)
            && !current.hasAttribute(Attribute.indent.key);

          final decreaseCondition = currentIndentValue == null
            && beforeIndentValue == 2
            && (tmpCurrentAttr == attr.value || isCheckList)
            && (tmpBeforeAttr == attr.value || isCheckList);

          if (decreaseCondition) {
            formatSelection(attr);
            formatSelection(Attribute.getIndentLevel(1));
          } else if (increaseCondition) {
            formatSelection(attr);
            formatSelection(Attribute.getIndentLevel(indentValue + 1));
          }
        } else if (indentValue == 1) {
          final decreaseCondition = currentIndentValue == null
            && beforeIndentValue == 2
            && (tmpCurrentAttr == attr.value || isCheckList)
            && (tmpBeforeAttr == attr.value || isCheckList);

          final increaseCondition = currentIndentValue == 1
            && beforeIndentValue == 1
            && tmpCurrentAttr != attr.value
            && (tmpBeforeAttr == attr.value || isCheckList);
          if (decreaseCondition) {
            formatSelection(attr);
            formatSelection(Attribute.getIndentLevel(indentValue - 1));
          } else if (increaseCondition) {
            formatSelection(attr);
            formatSelection(Attribute.getIndentLevel(indentValue + 1));
          }
        } else if (tmpCurrentAttr != attr.value && beforeIndentValue != 1) {
          formatSelection(attr);
          formatSelection(Attribute.getIndentLevel(indentValue - 1));
        }
      } else if (before.data == '\n') {
        if (indentValue == 1) {
          final decreaseCondition = currentIndentValue == 1
            && beforeIndentValue == 1
            && tmpCurrentAttr != attr.value
            && (tmpBeforeAttr == attr.value || isCheckList)
            && prevBefore?.data == '\n';
          final prevBeforeIndentValue = prevBefore?.attributes?['indent'];

          if (decreaseCondition) {
            if (prevBeforeIndentValue == 2) {
              formatSelection(attr);
              formatSelection(Attribute.getIndentLevel(0));
            } else if (prevBeforeIndentValue == null) {
              if (length > 1) {
                if (onEditingComplete != null) {
                  final isBeforeNewLine = before.isInsert && before.data == '\n';
                  trimNewLine(isBeforeNewLine: isBeforeNewLine);
                  onEditingComplete();
                }
              } else {
                if (onDelete != null) {
                  onDelete();
                }
              }
            }
          }
        } else if (tmpCurrentAttr != attr.value && indentValue == 2) {
          formatSelection(attr);
        } else if (indentValue == 0) {
          final trimNewLineCondition = currentIndentValue == null 
            && beforeIndentValue == 0
            && currentIndentValue == null
            && (tmpCurrentAttr == attr.value || isCheckList)
            && (tmpBeforeAttr == attr.value || isCheckList);

          if (trimNewLineCondition) {
            final isBeforeNewLine = before.isInsert && before.data == '\n';
            trimNewLine(isBeforeNewLine: isBeforeNewLine);
            onEditingComplete!();
          }
        }
      }
    }
  }

  /// isSubmitted
  /// 
  /// 줄띄움 감지 및 newLine 삭제
  /// 
  /// Duke Jeon (duke@peoplus.studio)
  bool isSubmitted(
    DocChange event, {
      bool hasTrimNewLine = false,
      bool isInsertNewLine = true,
    }
  ) {
    final current = event.change.toList().last;
    final eventLength = event.change.toList().length;
    var before = event.change.toList().last;
    var trimIndex;
    var hasOnlyRetain = true;

    for (final operation in event.change.toList()) {
      if (!operation.isRetain) {
        hasOnlyRetain = false;
        break;
      }
    }

    if (eventLength > 1) {
      if (isInsertNewLine) {
        trimIndex = event.change.toList().first.length;
        before = event.before.toList().last;
      } else {
        before = event.change.toList()[eventLength - 2];
      }
    }

    final isCurrentNewLine = isInsertNewLine
      ? current.isRetain && before.isInsert && before.data == '\n'
      : current.isInsert && current.data == '\n';
    final isBeforeNewLine = isInsertNewLine
      ? current.isInsert && current.data == '\n' && before.isInsert && before.data == '\n'
      : before.isInsert && before.data == '\n';
    
    if (isCurrentNewLine || isBeforeNewLine) {
      if (hasTrimNewLine) {
        return trimNewLine(
          trimIndex: isBeforeNewLine
            ? trimIndex
            : null,
          isBeforeNewLine: isBeforeNewLine,
          isAuto: hasOnlyRetain && !isBeforeNewLine,
        );
      }
      return true;
    }
    return false;
  }

  /// trimNewLine
  /// 
  /// 줄띄움 삭제
  /// 
  /// Duke Jeon (duke@peoplus.studio)
  bool trimNewLine({
    int? trimIndex,
    bool isBeforeNewLine = false,
    bool isCheckList = true,
    bool isAuto = false,
  }) {
    var index = trimIndex ?? document.toPlainText().lastIndexOf('\n');

    if (isAuto) {
      index = trimIndex ?? document.toPlainText().lastIndexOf('\n') - 1;
    }
    var length = document.toPlainText().length;
    var removeLength = 1;

    if (isBeforeNewLine) {
      index = document.toPlainText().lastIndexOf('') - 1;
    }

    if (length >= 2) {
      if (isCheckList) {
        removeLength = 2;
      } else {
        removeLength = 1;
      }
    }

    if (trimIndex != null) {
      replaceText(
        trimIndex,
        length - trimIndex,
        '',
        TextSelection.collapsed(
          offset: trimIndex
        )
      );

      final newLineCount = document.toDelta().last.data.toString().split('\n').length;

      if (newLineCount > 1) {
        index = document.toPlainText().lastIndexOf('\n') - (newLineCount - 1);
        length = document.length;
        removeLength = length - index;
        final deltaLength = document.toDelta().toJson().length;

        if (deltaLength > 2) {
          removeLength++;
        } else if (deltaLength == 2) {
          index++;
          removeLength = 1;
        }
        document.replace(index, removeLength, '');
        updateSelection(TextSelection.collapsed(offset: index), ChangeSource.LOCAL);
      }
      return true;
    }

    final ignore = document.toDelta().first.data.toString().startsWith('\n');

    if (ignore) {
      document.delete(0, document.length);
      updateSelection(const TextSelection.collapsed(offset: 0), ChangeSource.LOCAL);
      return true;
    }

    if (index > 0 && index == length - 1) {
      replaceText(
        index,
        removeLength,
        '',
        TextSelection.collapsed(
          offset: index
        )
      );

      final tmpNewLineCount = document.toDelta().last.data.toString().split('\n').length;

      if (tmpNewLineCount > 1) {
        index = document.toPlainText().lastIndexOf('\n') - (tmpNewLineCount - 2);
        length = document.toPlainText().length;
        removeLength = length - index;

        document.replace(index, removeLength, '');
        updateSelection(TextSelection.collapsed(offset: index), ChangeSource.LOCAL);
      }
      return true;
    }
    return false;
  }

  /// setTag
  /// 
  /// changes.listen 내에서 Tag 감지
  /// 
  /// Duke Jeon (duke@peoplus.studio)
  void setTag(DocChange event) {
    final startTag = RegExp(r'^@$');
    final checkTag = RegExp(r'^@[\S]+$');
    final startHashTag = RegExp(r'^#$');
    final checkHashTag = RegExp(r'^#[\S]+$');
    final space = RegExp(r'\s');
    
    int? index;
    final textLength = document.length;
    for (final operation in event.change.toList()) {

      final isTag = operation.attributes?.keys.contains(Attribute.tag.key)
        ?? false;
      final isHashtag = operation.attributes?.keys.contains(Attribute.hashtag.key)
        ?? false;
      final isContain = isTag || isHashtag;

      Attribute attribute = Attribute.tag;
      var checkRegExp = checkTag;

      if (isHashtag) {
        attribute = Attribute.hashtag;
        checkRegExp = checkHashTag;
      }

      if (operation.key == Operation.retainKey) {
        index = operation.length;
      } else if (operation.key == Operation.insertKey) {
        if (operation.data is String) {
          final str = operation.data.toString();

          if (str.startsWith(startHashTag)) {
            attribute = Attribute.hashtag;
            checkRegExp = checkHashTag;
          }

          // Attribute가 tag 또는 hashtag 일 경우 스페이스가 포함되면 Attribute 삭제
          if (isContain && space.hasMatch(str)) {
            if (index != null) {
              formatText(
                index,
                index + 1,
                Attribute.clone(
                  attribute, null
                )
              );

              formatSelection(
                Attribute.clone(
                  attribute, null
                )
              );
            }
            return;
          }

          index ??= 0;
          if (index < textLength - 2) {
            final text = document.toPlainText().substring(index, textLength - 1);

            if (checkRegExp.hasMatch(text) && !isContain) {
              replaceText(
                index,
                text.length,
                ' $text ',
                TextSelection.collapsed(
                  offset: index
                )
              );

              formatText(
                index,
                index + text.length,
                attribute
              );
              break;
            }
          } else {
            var startRegExp = startTag;
            final isHashtag = startHashTag.hasMatch(str);

            if (isHashtag) {
              startRegExp = startHashTag;
            }

            if (startRegExp.hasMatch(str) && !isContain) {
              formatText(
                index,
                index + 1,
                attribute
              );
              break;
            }
          }
        }
        index = null;
      } else if (operation.key == Operation.deleteKey) {
        final operaions = document.toDelta().toList();

        for (final tmpOperation in operaions) {
          final hasTag = tmpOperation.hasAttribute(Attribute.tag.key);
          final hasHashtag = tmpOperation.hasAttribute(Attribute.hashtag.key);

          if (hasTag || hasHashtag) {
            final plainText = document.toPlainText();

            if (tmpOperation.data is String) {
              final operaionData = tmpOperation.data as String;
              final index = plainText.indexOf(operaionData);
              final offset = selection.baseOffset;

              if (index <= offset && offset <= index + operaionData.length) {
                replaceText(
                  index,
                  operaionData.length,
                  '',
                  TextSelection.collapsed(
                    offset: index
                  )
                );
              }
            }
          }
        }
      }
    }
  }

  String toHtml() {
    final converter = QuillDeltaToHtmlConverter(
      List.castFrom(_document.toDelta().toJson()),
    );

    return converter.convert();
  }

  String? getLinkAttributeValue() {
    return getSelectionStyle()
      .attributes[Attribute.link.key]
      ?.value;
  }

  TextRange getLinkRange(Node node) {
    return getLinkRange(node);
  }

  void linkSubmitted(TextLink value) {
    var index = selection.start;
    var length = selection.end - index;
    if (getLinkAttributeValue() != null) {
      final leaf = document.querySegmentLeafNode(index).leaf;
      if (leaf != null) {
        final range = getLinkRange(leaf);
        index = range.start;
        length = range.end - range.start;
      }
    }

    replaceText(
      index,
      length,
      value.text,
      null
    );

    formatText(
      index,
      value.text.length,
      LinkAttribute(value.link)
    );
  }
}