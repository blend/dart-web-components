// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library template;

import 'dart:io';
import 'package:args/args.dart';
import 'cmd_options.dart';
import 'compile.dart';
import 'file_system_memory.dart';
import 'file_system_vm.dart';
import 'utils.dart';
import 'world.dart';

FileSystem fileSystem;

void main() => run(new Options().arguments);

/** tool.dart [options...] <sourcefile fullpath> <outputfile fullpath> */
void run(List<String> args) {
  var argParser = commandOptions();
  ArgResults results = argParser.parse(args);
  if (results['help'] || results.rest.length == 0) {
    print('Usage: [options...] sourcefile [outputPath]\n');
    print(argParser.getUsage());
    print("   sourcefile - template file filename.html");
    print("   outputPath - if specified directory to generate files; if not");
    print("                same directory as sourcefile");
    return;
  }

  fileSystem = new VMFileSystem();

  initHtmlWorld(parseOptions(results, fileSystem));

  // argument 0 - sourcefile full path
  // argument 1 - output path
  String sourceFullFn = results.rest[0];
  String outputFullDir = results.rest.length > 1 ? results.rest[1] : null;

  Path srcPath = new Path(sourceFullFn);

  Path srcDirPath = srcPath.directoryPath;
  Directory srcDir = srcDirPath.isEmpty
      ? new Directory.current() : new Directory.fromPath(srcDirPath);
  if (!srcDir.existsSync()) {
    world.fatal("Input directory doesn't exist - ${srcDir.path}");
    return;
  }

  File fileSrc = new File.fromPath(srcPath);
  if (!fileSrc.existsSync()) {
    world.fatal("Source file doesn't exist - ${fileSrc.name}");
    return;
  }

  String sourceFilename = fileSrc.name;

  // If outputFullDirectory not specified use the directory of the source file.
  if (outputFullDir == null || outputFullDir.isEmpty()) {
    outputFullDir = srcDir.path;
  }

  Directory outDirectory = new Directory(outputFullDir);
  if (!outDirectory.existsSync()) {
    outDirectory.createSync();
  }

  String source = fileSystem.readAll(sourceFullFn);
  time('Compiled $sourceFullFn', () {
    var compiler = new Compile(fileSystem);
    compiler.run(srcPath.filename, srcDir.path);

    // Write out the code associated with each source file.
    print("Write files to ${outDirectory.path}:");
    for (var file in compiler.output) {
      writeFile(file.filename, outDirectory, file.contents);
    }
  }, printTime: true);
}

void writeFile(String filename, Directory outdir, String contents) {
  String path = "${outdir.path}/$filename";
  if (options.clean) {
    File fileOut = new File.fromPath(new Path(path));
    if (fileOut.existsSync()) {
      fileOut.deleteSync();
      print("  Deleting $filename");
    }
  } else {
    fileSystem.writeString(path, contents);
    print("  Writing $filename");
  }
}

ArgParser commandOptions() {
  var args = new ArgParser();
  args.addFlag('verbose', help: 'Display detail info', defaultsTo: false);
  args.addFlag('clean', help: 'Remove all generated files', defaultsTo: false);
  args.addFlag('dump', help: 'Dump AST', defaultsTo: false);
  args.addFlag('suppress_warnings', help: 'Warnings not displayed',
      defaultsTo: true);
  args.addFlag('warnings_as_errors', help: 'Warning handled as errors',
      defaultsTo: false);
  args.addFlag('throw_on_errors', help: 'Throw on errors encountered',
      defaultsTo: false);
  args.addFlag('throw_on_warnings', help: 'Throw on warnings encountered',
      defaultsTo: false);
  args.addFlag('no_colors', help: 'Display errors/warnings in colored text',
      defaultsTo: true);
  args.addFlag('help', help: 'Displays this help message', defaultsTo: false);

  return args;
}

void initHtmlWorld(CmdOptions opts) {
  var fs = new MemoryFileSystem();
  initializeWorld(fs, opts);

  // TODO(terry): Should be set by arguments.  When run as a tool these aren't
  // set when run internaly set these so we can compile CSS and catch any
  // problems programmatically.
  //  options.throwOnErrors = true;
  //  options.throwOnFatal = true;
  //  options.useColors = commandLine ? true : false;
}
