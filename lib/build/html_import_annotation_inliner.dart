// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.
library web_components.build.html_import_annotation_inliner;

import 'dart:async';
import 'package:barback/barback.dart';
import 'package:html5lib/dom.dart' as dom;
import 'package:html5lib/parser.dart';
import 'package:path/path.dart' as path;

/// Given an html entry point with a single dart bootstrap file created by the
/// `initialize` transformer, this will open that dart file and remove all
/// `HtmlImport` initializers from it. Then it appends those imports to the head
/// of the html entry point.
/// Note: Does not inline the import, it just puts the <link rel="import"> tag.
class HtmlImportAnnotationInliner extends AggregateTransformer {
  final String _bootstrapFile;
  final String _htmlEntryPoint;
  TransformLogger _logger;

  HtmlImportAnnotationInliner(this._bootstrapFile, this._htmlEntryPoint);

  factory HtmlImportAnnotationInliner.asPlugin(BarbackSettings settings) {
    var bootstrapFile = settings.configuration['bootstrap_file'];
    if (bootstrapFile is! String || !bootstrapFile.endsWith('.dart')) {
      throw new ArgumentError(
          '`bootstrap_file` should be a string path to a dart file');
    }
    var htmlEntryPoint = settings.configuration['html_entry_point'];
    if (htmlEntryPoint is! String || !htmlEntryPoint.endsWith('.html')) {
      throw new ArgumentError(
          '`html_entry_point` should be a string path to an html file');
    }
    return new HtmlImportAnnotationInliner(bootstrapFile, htmlEntryPoint);
  }

  classifyPrimary(AssetId id) {
    if (_bootstrapFile == id.path || _htmlEntryPoint == id.path) return ' ';
    return null;
  }

  Future apply(AggregateTransform transform) {
    _logger = transform.logger;
    Asset dartEntryPoint;
    Asset htmlEntryPoint;
    return transform.primaryInputs.take(2).listen((Asset asset) {
      if (asset.id.path == _bootstrapFile) dartEntryPoint = asset;
      if (asset.id.path == _htmlEntryPoint) htmlEntryPoint = asset;
    }).asFuture().then((_) {
      // Will be populated with all import paths found in HtmlImport
      // constructors.
      var importPaths;
      return dartEntryPoint.readAsString().then((dartCode) {
        var matches = _htmlImportWithRawString.allMatches(dartCode);
        importPaths = new Set.from(matches.map((match) =>  _normalizePath(
            match.group(1), match.group(2), match.group(3),
            htmlEntryPoint.id.package)));

        var newDartCode = dartCode.replaceAll(_htmlImportWithRawString, '');
        var leftoverMatches = _htmlImportGeneral.allMatches(newDartCode);
        for (var match in leftoverMatches) {
          _logger.warning('Found HtmlImport constructor which was supplied an '
              'expression. Only raw strings are currently supported: '
              '${match.group(0)}');
        }
        transform.addOutput(
            new Asset.fromString(dartEntryPoint.id, newDartCode));
      }).then((_) => htmlEntryPoint.readAsString()).then((html) {
        var doc = parse(html);
        for (var importPath in importPaths) {
          var import = new dom.Element.tag('link')..attributes = {
            'rel': 'import',
            'href': importPath,
          };
          doc.head.append(import);
        }
        transform.addOutput(
            new Asset.fromString(htmlEntryPoint.id, doc.outerHtml));
      });
    });
  }

  String _normalizePath(String htmlPath, String dartFilePackage,
       String dartFilePath, String rootDartPackage) {
    // If they already supplied a packages path, just return that.
    if (htmlPath.startsWith('package:')) {
      return htmlPath.replaceFirst('package:', 'packages/');
    }

    var dartFileDir = path.url.dirname(dartFilePath);
    var dartFileDirSegments = path.url.split(dartFileDir);
    var inLibDir = dartFileDirSegments[0] == 'lib';
    // The dartFileDir without the leading dir.
    var dartFileSubDir = path.url.joinAll(
        dartFileDirSegments.getRange(1, dartFileDirSegments.length));

    // Relative path to something not under lib. All other paths will be turned
    // into a packages/ path.
    if (dartFilePackage == 'null' && !inLibDir) {
      return path.url.normalize(path.url.join(dartFileSubDir, htmlPath));
    }

    if (!inLibDir) {
      _logger.error('Can only import assets from a folder other than `lib` if '
          'they are in the same package as the entry point. Found '
          '$dartFilePackage:$dartFilePath');
    }

    // Only option left is a packages/ path.
    var package = dartFilePackage == 'null' ? rootDartPackage : dartFilePackage;
    return path.url.normalize(
        path.url.join('packages/', package, dartFileSubDir, htmlPath));
  }

  // Matches HtmlImport constructors which are supplied a raw string. These are
  // the only ones currently supported for inlining.
  final RegExp _htmlImportWithRawString = new RegExp(
      r"\n\s*new InitEntry\(const i[\d]*\.HtmlImport\('([\w\d\/\.:]*\.html)'\),"
      r"\sconst\sLibraryIdentifier\(#[\w\.]*, '?([\w_]*)'?, '([\w\d\/\.]*)'\)\)"
      r",");

  // Matches HtmlImport initializers which are supplied any arguments. This
  // is used to detect if any were left over and not inlined.
  final RegExp _htmlImportGeneral = new RegExp(
      r"\n\s*new InitEntry\(const i[\d]*\.HtmlImport\('([\w\.].*)'\),\s.*\),");
}