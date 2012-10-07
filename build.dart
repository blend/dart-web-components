// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * This build script is invoked automatically by the Editor whenever a file
 * in the project changes. It must be placed in the root of a project and named
 * 'build.dart'.
 */

// TODO: pub should generate the root build.dart file
import 'package:web_components/build.dart' as component_build;
void main() => component_build.main();
