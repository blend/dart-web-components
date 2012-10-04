// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library tools;

import 'package:args/args.dart';
import 'world.dart';

/** Extracts options from command-line arguments. */
CmdOptions parseOptions(ArgResults args, files) {
  return new CmdOptions(args, files);
}

class CmdOptions {
  // TODO(terry): Do we ever want to support throw on fatal?
  bool throwOnFatal = false;
  bool warningsAsErrors;

  // Message support
  bool throwOnErrors;
  bool throwOnWarnings;
  bool showInfo;
  bool dumpTree;

  /** Remove any generated files. */
  bool clean;

  bool showWarnings;
  bool useColors;

  bool noWhitespace = false;

  CmdOptions(ArgResults args, files) {
    warningsAsErrors = args['warnings_as_errors'];
    throwOnErrors = args['throw_on_errors'];
    throwOnWarnings = args['throw_on_warnings'];
    showInfo = args['verbose'];
    dumpTree = args['dump'];
    clean = args['clean'];
    showWarnings = args['suppress_warnings'];
    useColors = args['no_colors'];
    noWhitespace = args['no_whitespace'];
  }
}
