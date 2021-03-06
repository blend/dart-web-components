// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

// TODO(terry): Investigate common library for file I/O shared between frog and tools.

/** Abstraction for file systems and utility functions to manipulate paths. */
library file_system;

import 'file_system/path.dart';

/**
 * Abstraction around file system access to work in a variety of different
 * environments.
 */
interface FileSystem {
  /**
   * Apply all pending writes.  Until this method is called, writeString is not
   * guaranteed to have any observable impact.
   */
  Future flush();

  /**
   * Reads bytes if possible, but falls back to text if running in a browser.
   * Return type is either [Future<List<int>>] or [Future<String>].
   */
  Future readTextOrBytes(Path filename);

  /* Like [readTextOrBytes], but decodes bytes as UTF-8. Used for Dart code. */
  Future<String> readText(Path filename);

  /**
   * Writes [text] to [outfile]. Call flush to insure that changes are visible.
   */
  void writeString(Path outfile, String text);
}
