// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:analysis_server/protocol/protocol.dart';
import 'package:analysis_server/protocol/protocol_generated.dart';
import 'package:analysis_server/src/protocol_server.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../analysis_abstract.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AnalysisSignatureTest);
  });
}

@reflectiveTest
class AnalysisSignatureTest extends AbstractAnalysisTest {
  Future<Response> prepareRawSignature(String search) {
    int offset = findOffset(search);
    return prepareRawSignatureAt(offset);
  }

  Future<Response> prepareRawSignatureAt(int offset, {String file}) async {
    await waitForTasksFinished();
    Request request =
        new AnalysisGetSignatureParams(file ?? testFile, offset).toRequest('0');
    return waitResponse(request);
  }

  Future<AnalysisGetSignatureResult> prepareSignature(String search) {
    int offset = findOffset(search);
    return prepareSignatureAt(offset);
  }

  Future<AnalysisGetSignatureResult> prepareSignatureAt(int offset,
      {String file}) async {
    Response response = await prepareRawSignatureAt(offset, file: file);
    return new AnalysisGetSignatureResult.fromResponse(response);
  }

  @override
  void setUp() {
    super.setUp();
    createProject();
  }

  test_constructor() async {
    addTestFile('''
/// MyClass doc
class MyClass {
  /// MyClass constructor doc
  MyClass(String name, {int length}) {}
} 
main() {
  var a = new MyClass("Danny", /*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("MyClass"));
    expect(result.dartdoc, equals("MyClass constructor doc"));
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(result.parameters[1],
        equals(new ParameterInfo(ParameterKind.NAMED, "length", "int")));
  }

  test_constructor_factory() async {
    addTestFile('''
/// MyClass doc
class MyClass {
  /// MyClass private constructor doc
  MyClass._() {}
  /// MyClass factory constructor doc
  factory MyClass(String name, {int length}) {
    return new MyClass._();
  }
} 
main() {
  var a = new MyClass("Danny", /*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("MyClass"));
    expect(result.dartdoc, equals("MyClass factory constructor doc"));
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(result.parameters[1],
        equals(new ParameterInfo(ParameterKind.NAMED, "length", "int")));
  }

  test_constructor_named() async {
    addTestFile('''
/// MyClass doc
class MyClass {
  /// MyClass.foo constructor doc
  MyClass.foo(String name, {int length}) {}
} 
main() {
  var a = new MyClass.foo("Danny", /*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("MyClass.foo"));
    expect(result.dartdoc, equals("MyClass.foo constructor doc"));
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(result.parameters[1],
        equals(new ParameterInfo(ParameterKind.NAMED, "length", "int")));
  }

  test_does_not_walk_up_over_closure() async {
    addTestFile('''
one(String name, int length) {}
main() {
  one("Danny", () {
    /*^*/
  });
}
''');
    var result = await prepareRawSignature('/*^*/');
    expect(result.error, isNotNull);
    expect(result.error.code,
        equals(RequestErrorCode.GET_SIGNATURE_UNKNOWN_FUNCTION));
  }

  test_error_file_invalid_path() async {
    var result = await prepareRawSignatureAt(0, file: ':\\/?*');
    expect(result.error, isNotNull);
    expect(
        result.error.code, equals(RequestErrorCode.GET_SIGNATURE_INVALID_FILE));
  }

  test_error_file_not_analyzed() async {
    var result = await prepareRawSignatureAt(0,
        file: convertPath('/not/in/project.dart'));
    expect(result.error, isNotNull);
    expect(
        result.error.code, equals(RequestErrorCode.GET_SIGNATURE_INVALID_FILE));
  }

  test_error_function_unknown() async {
    addTestFile('''
someFunc(/*^*/);
''');
    var result = await prepareRawSignature('/*^*/');
    expect(result.error, isNotNull);
    expect(result.error.code,
        equals(RequestErrorCode.GET_SIGNATURE_UNKNOWN_FUNCTION));
  }

  test_error_offset_invalid() async {
    addTestFile('''
a() {}
''');
    var result = await prepareRawSignatureAt(1000);
    expect(result.error, isNotNull);
    expect(result.error.code,
        equals(RequestErrorCode.GET_SIGNATURE_INVALID_OFFSET));
  }

  test_function_expression() async {
    addTestFile('''
/// f doc
int Function(String) f(String s) => (int i) => int.parse(s) + i;
main() {
  print(f('3'/*^*/)(2));
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("f"));
    expect(result.dartdoc, equals("f doc"));
    expect(result.parameters, hasLength(1));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "s", "String")));
  }

  test_function_from_other_file() async {
    newFile('/project/bin/other.dart', content: '''
/// one doc
one(String name, int length) {}
main() {
  one("Danny", /*^*/);
}
''');
    addTestFile('''
import 'other.dart';
main() {
  one("Danny", /*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("one"));
    expect(result.dartdoc, equals("one doc"));
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(result.parameters[1],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "length", "int")));
  }

  test_function_irrelevant_parens() async {
    addTestFile('''
/// one doc
one(String name, int length) {}
main() {
  one("Danny", (((1 * 2/*^*/))));
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("one"));
    expect(result.dartdoc, equals("one doc"));
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(result.parameters[1],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "length", "int")));
  }

  test_function_named() async {
    addTestFile('''
/// one doc
one(String name, {int length}) {}
main() {
  one("Danny", /*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("one"));
    expect(result.dartdoc, equals("one doc"));
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(result.parameters[1],
        equals(new ParameterInfo(ParameterKind.NAMED, "length", "int")));
  }

  test_function_named_with_default_int() async {
    addTestFile('''
/// one doc
one(String name, {int length = 1}) {}
main() {
  one("Danny", /*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("one"));
    expect(result.dartdoc, equals("one doc"));
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(
        result.parameters[1],
        equals(new ParameterInfo(ParameterKind.NAMED, "length", "int",
            defaultValue: "1")));
  }

  test_function_named_with_default_string() async {
    addTestFile('''
/// one doc
one(String name, {String email = "a@b.c"}) {}
main() {
  one("Danny", /*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("one"));
    expect(result.dartdoc, equals("one doc"));
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(
        result.parameters[1],
        equals(new ParameterInfo(ParameterKind.NAMED, "email", "String",
            defaultValue: '"a@b.c"')));
  }

  test_function_nested_call_inner() async {
    // eg. foo(bar(1, 2));
    addTestFile('''
/// one doc
one(String one) {}
/// two doc
String two(String two) { return ""; }
main() {
  one(two(/*^*/));
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("two"));
    expect(result.dartdoc, equals("two doc"));
    expect(result.parameters, hasLength(1));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "two", "String")));
  }

  test_function_nested_call_outer() async {
    // eg. foo(bar(1, 2));
    addTestFile('''
/// one doc
one(String one) {}
/// two doc
String two(String two) { return ""; }
main() {
  one(two(),/*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("one"));
    expect(result.dartdoc, equals("one doc"));
    expect(result.parameters, hasLength(1));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "one", "String")));
  }

  test_function_no_dart_doc() async {
    addTestFile('''
one(String name, int length) {}
main() {
  one("Danny", /*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("one"));
    expect(result.dartdoc, isNull);
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(result.parameters[1],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "length", "int")));
  }

  test_function_optional() async {
    addTestFile('''
/// one doc
one(String name, [int length]) {}
main() {
  one("Danny", /*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("one"));
    expect(result.dartdoc, equals("one doc"));
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(result.parameters[1],
        equals(new ParameterInfo(ParameterKind.OPTIONAL, "length", "int")));
  }

  test_function_optional_with_default() async {
    addTestFile('''
/// one doc
one(String name, [int length = 11]) {}
main() {
  one("Danny", /*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("one"));
    expect(result.dartdoc, equals("one doc"));
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(
        result.parameters[1],
        equals(new ParameterInfo(ParameterKind.OPTIONAL, "length", "int",
            defaultValue: "11")));
  }

  test_function_required() async {
    addTestFile('''
/// one doc
one(String name, int length) {}
main() {
  one("Danny", /*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("one"));
    expect(result.dartdoc, equals("one doc"));
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(result.parameters[1],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "length", "int")));
  }

  test_function_zero_arguments() async {
    addTestFile('''
/// one doc
one() {}
main() {
  one(/*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("one"));
    expect(result.dartdoc, equals("one doc"));
    expect(result.parameters, hasLength(0));
  }

  test_method_instance() async {
    addTestFile('''
/// MyClass doc
class MyClass {
  /// MyClass constructor doc
  MyClass(String name, {int length}) {}
  /// MyClass instance method
  myMethod(String name, {int length}) {}
} 
main() {
  var a = new MyClass("Danny");
  a.myMethod("Danny", /*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("myMethod"));
    expect(result.dartdoc, equals("MyClass instance method"));
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(result.parameters[1],
        equals(new ParameterInfo(ParameterKind.NAMED, "length", "int")));
  }

  test_method_static() async {
    addTestFile('''
/// MyClass doc
class MyClass {
  /// MyClass constructor doc
  MyClass(String name, {int length}) {}
  /// MyClass static method
  static void myStaticMethod(String name, {int length}) {}
} 
main() {
  MyClass.myStaticMethod("Danny", /*^*/);
}
''');
    var result = await prepareSignature('/*^*/');
    expect(result.name, equals("myStaticMethod"));
    expect(result.dartdoc, equals("MyClass static method"));
    expect(result.parameters, hasLength(2));
    expect(result.parameters[0],
        equals(new ParameterInfo(ParameterKind.REQUIRED, "name", "String")));
    expect(result.parameters[1],
        equals(new ParameterInfo(ParameterKind.NAMED, "length", "int")));
  }
}
