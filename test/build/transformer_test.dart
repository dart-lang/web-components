// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library web_components.test.build.transformer_test;

import 'package:code_transformers/tests.dart';
import 'package:web_components/transformer.dart';
import 'package:unittest/compact_vm_config.dart';
import 'common.dart';

var transformer = new WebComponentsTransformerGroup(
    new TransformOptions(['web/index.html'], false));
var phases = [[transformer]];

main() {
  useCompactVMConfiguration();

  testPhases('full app', phases, {
    'a|web/index.html': '''
        <!DOCTYPE html>
        <html>
          <head>
            <link rel="import" href="packages/b/foo.html">
          </head>
          <body>
            <script type="application/dart" src="index.dart"></script>
          </body>
        </html>
        ''',
    'a|web/index.dart': '''
        library a;

        import 'package:initialize/initialize.dart';

        @initMethod
        startup() {}
        ''',
    'b|lib/foo.html': '''
        <link rel="import" href="bar.html">
        <script type="application/dart" src="foo.dart"></script>
        <div>foo</div>
        ''',
    'b|lib/foo.dart': '''
        library b.foo;
        ''',
    'b|lib/bar.html': '''
        <script type="application/dart">
          // Must use package:urls inside inline script tags,
          @HtmlImport('package:b/bar_nodart.html')
          library b.bar;

          import 'package:web_components/html_import_annotation.dart';

          import 'package:initialize/initialize.dart';

          @initMethod
          bar() {}
        </script>
        <div>bar</div>
        ''',
    'b|lib/bar_nodart.html': '''
        <div>bar no_dart!</div>
        ''',
    'initialize|lib/initialize.dart': mockInitialize,
    'web_components|lib/html_import_annotation.dart': mockHtmlImportAnnotation,
  }, {
    'a|web/index.html': '''
        <!DOCTYPE html>
        <html>
          <head></head>
          <body>
            <div hidden="">
              <div>bar</div>
              <div>foo</div>
              <div>bar no_dart!</div>
            </div>
            <script type="application/dart" src="index.bootstrap.initialize.dart">
            </script>
          </body>
        </html>
        ''',
    'a|web/index.bootstrap.initialize.dart': '''
        import 'package:initialize/src/static_loader.dart';
        import 'package:initialize/initialize.dart';
        import 'index.bootstrap.dart' as i0;
        import 'index.html.0.dart' as i1;
        import 'package:web_components/html_import_annotation.dart' as i2;
        import 'package:initialize/initialize.dart' as i3;
        import 'index.dart' as i4;

        main() {
          initializers.addAll([
            new InitEntry(i3.initMethod, i1.bar),
            new InitEntry(i3.initMethod, i4.startup),
          ]);
          i0.main();
        }
        ''',
    'a|web/index.bootstrap.dart': '''
        library a.web.index_bootstrap_dart;

        import 'index.html.0.dart' as i0;
        import 'package:b/foo.dart' as i1;
        import 'index.dart' as i2;

        void main() => i2.main();
        ''',
    'a|web/index.html.0.dart': '''
        // Must use package:urls inside inline script tags,
        @HtmlImport('package:b/bar_nodart.html')
        library b.bar;

        import 'package:web_components/html_import_annotation.dart';

        import 'package:initialize/initialize.dart';

        @initMethod
        bar() {}
        ''',
  }, [], StringFormatter.noNewlinesOrSurroundingWhitespace);
}
