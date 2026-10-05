// 測試用 finder（Phase C）。
//
// 首頁與各步驟的主要按鈕上方有 NextActionHint 提示列，提示列直接顯示
// 按鈕名（commit 6e86646 起），所以 `find.text('〔按鈕名〕')` 會找到兩個。
// 要找「按鈕本身」就用 [buttonText]。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 按鈕（Text／Filled／Outlined／Elevated…Button）裡面文字為 [text] 的
/// Text；不含 NextActionHint 提示列上的同一句。
Finder buttonText(String text) => find.descendant(
  of: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
  matching: find.text(text),
);
