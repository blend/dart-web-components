// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library compile;

import 'dart:coreimpl';
import 'package:html5lib/dom.dart';
import 'package:html5lib/parser.dart';

import 'analyzer.dart';
import 'code_printer.dart';
import 'codegen.dart' as codegen;
import 'emitters.dart';
import 'file_system.dart';
import 'files.dart';
import 'info.dart';
import 'utils.dart';
import 'world.dart';


Document parseHtml(String template, String sourcePath) {
  var parser = new HtmlParser(template, generateSpans: true);
  var document = parser.parse();

  // Note: errors aren't fatal in HTML (unless strict mode is on).
  // So just print them as warnings.
  for (var e in parser.errors) {
    world.warning('$sourcePath line ${e.line}:${e.column}: ${e.message}');
  }

  return document;
}

/**
 * Walk the tree produced by the parser looking for templates, expressions, etc.
 * as a prelude to emitting the code for the template.
 */
class Compile {
  final FileSystem filesystem;
  final List<SourceFile> files;
  final List<OutputFile> output;

  /** Information about source [files] given their href. */
  final Map<String, FileInfo> info;

  /** Used by template tool to open a file. */
  Compile(this.filesystem)
      : files = <SourceFile>[],
        output = <OutputFile>[],
        info = new SplayTreeMap<String, FileInfo>();

  /** Compile the application starting from the given [mainFile]. */
  void run(String mainFile, [String baseDir = ""]) {
    _parseAndDiscover(mainFile, baseDir);
    _analyze();
    _emit();
  }

  /**
   * Parse [mainFile] and recursively discover web components to load and
   * parse.
   */
  void _parseAndDiscover(String mainFile, String baseDir) {
    var pending = new Queue<String>(); // files to process
    pending.addLast(mainFile);
    while (!pending.isEmpty()) {
      var filename = pending.removeFirst();

      // Parse the file.
      if (info.containsKey(filename)) continue;
      var file = _parseHtmlFile(filename, baseDir, filename == mainFile);
      files.add(file);

      // Find additional components being loaded.
      var fileInfo = time('Analyzed definitions ${file.filename}',
          () => analyzeDefinitions(file));
      info[file.filename] = fileInfo;
      for (var href in fileInfo.componentLinks) {
        pending.addLast(href);
      }

      // Load .dart files being referenced in components.
      for (var component in fileInfo.declaredComponents) {
        var src = component.externalFile;
        if (src != null) {
          var dartFile = _parseDartFile(src, baseDir);
          var fileInfo = new FileInfo(dartFile.filename);
          info[dartFile.filename] = fileInfo;
          fileInfo.userCode = dartFile.code;
          files.add(dartFile);
        }
      }
    }
  }

  /** Parse [filename] and treat it as a component if [isMain] is false. */
  SourceFile _parseHtmlFile(String filename, String baseDir, bool isMain) {
    var file = new SourceFile(filename, isMainHtml: isMain);
    var source = filesystem.readAll("$baseDir/$filename");
    file.document = time("Parsed $filename", () => parseHtml(source, filename));
    if (options.dumpTree) {
      print("\n\n Dump Tree $filename:\n\n");
      print(file.document.outerHTML);
      print("\n=========== End of AST ===========\n\n");
    }
    return file;
  }

  /** Parse [filename] and treat it as a .dart file. */
  SourceFile _parseDartFile(String filename, String baseDir) {
    var file = new SourceFile(filename, isDart: true, isMainHtml: false);
    file.code = time("Read $baseDir/$filename",
        () => filesystem.readAll("$baseDir/$filename"));
    return file;
  }

  /** Run the analyzer on every input html file. */
  void _analyze() {
    for (var file in files) {
      if (file.isDart) continue;
      time('Analyzed contents ${file.filename}', () => analyzeFile(file, info));
    }
  }

  /** Emit the generated code corresponding to each input file. */
  void _emit() {
    for (var file in files) {
      time('Codegen ${file.filename}', () {
        if (!file.isDart) {
          _removeScriptTags(file.document);
          _fixImports(file);
          _emitComponents(file);
          if (file.isMainHtml) {
            _emitMainDart(file);
            _emitMainHtml(file);
          } else {
            _emitComponentHtml(file);
          }
        }
      });
    }
  }

  static const String DARTJS_LOADER =
    "http://dart.googlecode.com/svn/branches/bleeding_edge/dart/client/dart.js";

  /** Adds imports to [file] for each used component. */
  // TODO(sigmund): delete - this inlining of imports is added here just
  // because we currently have no way to re-export libraries (issue #58).
  void _fixImports(SourceFile file) {
    var fileInfo = info[file.filename];
    for (var component in fileInfo.components.getValues()) {
      fileInfo.imports[component.outputFile] = true;
    }
  }

  /** Emit the main .dart file. */
  void _emitMainDart(SourceFile file) {
    var fileInfo = info[file.filename];
    output.add(new OutputFile(fileInfo.dartFilename,
        new MainPageEmitter(fileInfo).run(file.document)));
  }

  /** Generate an html file with the (trimmed down) main html page. */
  void _emitMainHtml(SourceFile file) {
    var fileInfo = info[file.filename];

    // Clear the body, we moved all of it
    var document = file.document;
    document.body.nodes.clear();
    var dartCode = codegen.bootstrapCode(fileInfo.dartFilename);
    document.body.nodes.add(parseFragment(
      '<script type="text/javascript" src="$DARTJS_LOADER"></script>'
      '<script type="application/dart">$dartCode</script>'
    ));

    for (var link in document.head.queryAll('link')) {
      if (link.attributes["rel"] == "components") {
        link.remove();
      }
    }

    _addAutoGeneratedComment(file);
    output.add(new OutputFile('${file.filename}.html', document.outerHTML));
  }

  /** Emits the Dart code for all components in the [file]. */
  void _emitComponents(SourceFile file) {
    var fileInfo = info[file.filename];
    for (var component in fileInfo.declaredComponents) {
      var code = new WebComponentEmitter(fileInfo).run(component);
      output.add(new OutputFile(component.outputFile, code));
    }
    output.add(new OutputFile(fileInfo.dartFilename, new CodePrinter().add('''
        // Auto-generated from ${file.filename}.
        // DO NOT EDIT.

        library ${fileInfo.libraryName};

        ${codegen.exportList(fileInfo.imports.getKeys())}
        ''').formatString()));
  }

  /** Generate an html file declaring a web component. */
  void _emitComponentHtml(SourceFile file) {
    _addAutoGeneratedComment(file);
    output.add(new OutputFile(
        '${file.filename}.html', file.document.outerHTML));
  }


  void _removeScriptTags(Document doc) {
    for (var tag in doc.queryAll('script')) {
      if (tag.attributes['type'] == 'application/dart') {
        tag.remove();
      }
    }
  }
}

void _addAutoGeneratedComment(SourceFile file) {
  var document = file.document;

  // Insert the "auto-generated" comment after the doctype, otherwise IE will go
  // into quirks mode.
  int commentIndex = 0;
  DocumentType doctype = find(document.nodes, (n) => n is DocumentType);
  if (doctype != null) {
    commentIndex = document.nodes.indexOf(doctype) + 1;
    // TODO(jmesserly): the html5lib parser emits a warning for missing doctype,
    // but it allows you to put it after comments. Presumably they do this
    // because some comments won't force IE into quirks mode (sigh). See this
    // link for more info:
    //     http://bugzilla.validator.nu/show_bug.cgi?id=836
    // For simplicity we're emitting the warning always, like validator.nu does.
    if (doctype.tagName != 'html' || commentIndex != 1) {
      world.warning('${file.filename}: file should start with <!DOCTYPE html> '
          'to avoid the possibility of it being parsed in quirks mode in IE. '
          'See http://www.w3.org/TR/html5-diff/#doctype');
    }
  }
  document.nodes.insertAt(commentIndex, parseFragment(
      '\n<!-- This file was auto-generated from template '
              '${file.filename}. -->\n'));
}
