// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library component_build;

import 'dart:io';
import 'package:args/args.dart';
import 'package:web_components/src/template/template.dart' as dwc;

bool cleanBuild;
bool fullBuild;
List<String> changedFiles;
List<String> removedFiles;

/**
 * See the source code of [processArgs] for information about the legal command
 * line options.
 */
void main() {
  print("running build.dart...");
  processArgs();

  if (cleanBuild) {
    handleCleanCommand();
  } else if (fullBuild) {
    handleFullBuild();
  } else {
    handleChangedFiles(changedFiles);
    handleRemovedFiles(removedFiles);
  }
}

/**
 * Handle the --changed, --removed, --clean and --help command-line args.
 */
void processArgs() {
  var parser = new ArgParser();
  parser.addOption("changed", help: "the file has changed since the last build",
      allowMultiple: true);
  parser.addOption("removed", help: "the file was removed since the last build",
      allowMultiple: true);
  parser.addFlag("clean", negatable: false, help: "remove any build artifacts");
  parser.addFlag("help", negatable: false, help: "displays this help and exit");
  var args = parser.parse(new Options().arguments);
  if (args["help"]) {
    print(parser.getUsage());
    exit(0);
  }

  changedFiles = args["changed"];
  removedFiles = args["removed"];
  cleanBuild = args["clean"];
  fullBuild = changedFiles.isEmpty() && removedFiles.isEmpty() && !cleanBuild;
}

/** Delete all generated files. */
void handleCleanCommand() {
  Directory current = new Directory.current();
  current.list(true).onFile = _maybeClean;
}

/**
 * Recursively scan the current directory looking for template files to process.
 */
void handleFullBuild() {
  var files = <String>[];
  var lister = new Directory.current().list(true);
  lister.onFile = (file) => files.add(file);
  lister.onDone = (_) => handleChangedFiles(files);
}

/** Process the given list of changed files. */
void handleChangedFiles(List<String> files) => files.forEach(_processFile);

/** Process the given list of removed files. */
void handleRemovedFiles(List<String> files) => files.forEach(_maybeClean);

/** Compile .tmpl files with the template tool. */
void _processFile(String arg) {
  if (arg.endsWith(".html")) {
    print("processing: ${arg}");
    dwc.run([arg]);
  }
}

/**
 * Matches generated Dart files for components; e.g.,
 * mycomponent.html.x_myelement.dart.
 */
RegExp _generatedElementFileSuffix = const RegExp(r"^.+\.html\..+\.dart$");

/** If this file is a generated file (based on the extension), delete it. */
void _maybeClean(String file) {
  var filename = new Path(file).filename;
  if (filename.endsWith(".dart.dart") ||
      filename.endsWith(".html.dart") ||
      filename.endsWith(".html.html") ||
      filename.endsWith(".html_bootstrap.dart") ||
      _generatedElementFileSuffix.hasMatch(filename)) {
    new File(file).delete();
  }
}
