// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * Datatypes holding information extracted by the analyzer and used by later
 * phases of the compiler.
 */
library info;

import 'dart:coreimpl';
import 'package:html5lib/dom.dart';
import 'files.dart';
import 'utils.dart';
import 'world.dart';

/** Information extracted at the file-level. */
class FileInfo {
  final String filename;

  /**
   * Whether this is the entry point of the web app, i.e. the file users
   * navigate to in their browser.
   */
  bool isMainHtml;

  // TODO(terry): Ensure that that the libraryName is a valid identifier:
  //              a..z || A..Z || _ [a..z || A..Z || 0..9 || _]*
  String get libraryName => filename.replaceAll('.', '_');
  String get dartFilename => '$filename.dart';

  /**
   * Target dart scripts loaded via `script` tags, or generated imports.
   * Note that this is used like a set. If the item is in the set, the value
   * will always be `true`.
   */
  // TODO(jmesserly): ideally this would be SplayTreeSet (dartbug.com/5603).
  final SplayTreeMap<String, bool> imports;

  /** User code inlined within the page. */
  String userCode = '';

  /** Generated analysis info for all elements in the file. */
  final Map<Node, ElementInfo> elements;

  /**
   * All custom element definitions in this file. This may contain duplicates.
   * Normally you should use [components] for lookup.
   */
  final List<ComponentInfo> declaredComponents;

  /**
   * All custom element definitions defined in this file or imported via
   *`<link rel='components'>` tag. Maps from the tag name to the component
   * information. This map is sorted by the tag name.
   */
  final Map<String, ComponentInfo> components;

  /** Files imported with `<link rel="component">` */
  final List<String> componentLinks;

  FileInfo([this.filename, this.isMainHtml = false])
      : elements = new Map<Node, ElementInfo>(),
        declaredComponents = new List<ComponentInfo>(),
        components = new SplayTreeMap<String, ComponentInfo>(),
        componentLinks = <String>[],
        imports = new SplayTreeMap<String, bool>();
}

/** Information about a web component definition. */
class ComponentInfo {
  /** The file that declares this component. Used for error messages. */
  final FileInfo file;

  /** The component tag name, defined with the `name` attribute on `element`. */
  final String tagName;

  /** The dart class containing the component's behavior. */
  final String constructor;

  /** The declaring `<element>` tag. */
  final Node element;

  /** The component's `<template>` tag, if any. */
  final Node template;

  /**
   * User code associated with this component. Components might have a class
   * definition. If it exits, it can be inlined in the .html file (in which case
   * the code will be stored in [inlinedCode]) or it can be included from a
   * separate .dart file (in which case a reference to it is stored in
   * [externalFile]). This property returns the code regardless of where it was
   * defined.
   */
  String get userCode {
    if (inlinedCode != null) return inlinedCode;
    if (externalCode != null) return externalCode.userCode;
    return null;
  }

  /** Inlined code for this component, if any. */
  String inlinedCode;

  /** Name of the dart file containing code for this component, if any. */
  String externalFile;

  /** Info asscociated with [externalFile], if any. */
  FileInfo externalCode;

  /** File where this component was defined. */
  String get inputFile => externalFile != null ? externalFile : file.filename;

  /**
   * Name of the file that will be generated for this component. We want to
   * generate a separate library for each component, unless their code is
   * already in an external library (e.g. [externalCode] is not null). Multiple
   * components could be defined inline within the HTML file, so we return a
   * unique file name for each component.
   */
  String get outputFile {
    if (externalCode != null) return externalCode.dartFilename;
    var prefix = file.filename;
    var componentSegment = tagName.toLowerCase().replaceAll('-', '_');
    return '$prefix.$componentSegment.dart';
  }

  /**
   * True if [tagName] was defined by more than one component. If this happened
   * we will skip over the component.
   */
  bool hasConflict = false;

  ComponentInfo(this.element, this.template, this.tagName, this.constructor,
      [this.file]);
}

/** Information extracted for each node in a template. */
class ElementInfo {
  /** Id given to an element node, if any. */
  String elementId;

  /** Generated field name, if any, associated with this element. */
  // TODO(sigmund): move this to Emitter?
  String elemField;

  // TODO(terry): Use for all iterates regardless if tag is template or not.
  /**
   * if true element is a fragment created with fragment function as part of
   * iterate on a non-template tag.
   */
  bool fragmentChild = false;

  /** Element has a template attribute. */
  TemplateInfo templateInfo;

  /** List of loopVariable(s) (nested iterates) for parameters. */
  List<String> params;

  /**
   * Whether code generators need to create a field to store a reference to this
   * element. This is typically true whenever we need to access the element
   * (e.g. to add event listeners, update values on data-bound watchers, etc).
   */
  bool get needsHtmlId => hasDataBinding || hasIfCondition || hasIterate
      || component != null || values.length > 0 || events.length > 0;

  /**
   * If this element is a web component instantiation (e.g. `<x-foo>`), this
   * will be set to information about the component, otherwise it will be null.
   */
  ComponentInfo component;

  /** Whether the element contains data bindings. */
  bool hasDataBinding = false;

  /** Data-bound expression used in the contents of the node. */
  String contentBinding;

  /**
   * Expression that returns the contents of the node (given it has a
   * data-bound expression in it).
   */
  // TODO(terry,sigmund): support more than 1 expression in the contents.
  String contentExpression;

  /** Generated watcher disposer that watchs for the content expression. */
  // TODO(sigmund): move somewhere else?
  String stopperName;

  /** Collected information for attributes, if any. */
  Map<String, AttributeInfo> attributes;

  /** Collected information for UI events on the corresponding element. */
  Map<String, List<EventInfo>> events;

  /** Collected information about `data-value="name:value"` expressions. */
  Map<String, String> values;

  /**
   * Format [elementId] in camel case, suitable for using as a Dart identifier.
   */
  String get idAsIdentifier =>
      elementId == null ? null : '_${toCamelCase(elementId)}';

  // Note: we're using sorted maps so items are enumerated in a consistent order
  // between runs, resulting in less "diff" in the generated code.
  // TODO(jmesserly): An alternative approach would be to use LinkedHashMap to
  // preserve the order of the input, but we'd need to be careful about our tree
  // traversal order.
  ElementInfo()
      : templateInfo = null,
        params = [],
        attributes = new SplayTreeMap<String, AttributeInfo>(),
        events = new SplayTreeMap<String, List<EventInfo>>(),
        values = new SplayTreeMap<String, String>();

  /** Whether the template element has `iterate="... in ...". */
  bool get hasIterate => templateInfo != null ? templateInfo.hasIterate : false;

  /** Whether the template element has an `instantiate="if ..."` conditional. */
  bool get hasIfCondition => false;

  String toString() => '#<ElementInfo '
      'elementId: $elementId, '
      'elemField: $elemField, '
//      'fragmentChild: $fragmentChild'
//      'templateInfo: ${templateInfo != null ? "true" : "false"}'
      'needsHtmlId: $needsHtmlId, '
      'component: $component, '
      'hasIterate: $hasIterate, '
      'hasIfCondition: $hasIfCondition, '
      'hasDataBinding: $hasDataBinding, '
      'contentBinding: $contentBinding, '
      'contentExpression: $contentExpression, '
      'attributes: $attributes, '
      'idAsIdentifier: $idAsIdentifier, '
      'events: $events>';
}

/** Information extracted for each attribute in an element. */
class AttributeInfo {

  /**
   * Whether this is a `class` attribute. In which case more than one binding
   * is allowed (one per class).
   */
  bool isClass = false;

  /**
   * A value that will be monitored for changes. All attributes, except `class`,
   * have a single bound value.
   */
  String get boundValue => bindings[0];

  /** All bound values that would be monitored for changes. */
  List<String> bindings;

  AttributeInfo(String value) : bindings = [value];
  AttributeInfo.forClass(this.bindings) : isClass = true;

  String toString() => '#<AttributeInfo '
      'isClass: $isClass, values: ${Strings.join(bindings, "")}>';

  /**
   * Generated fields for watcher disposers based on the bindings of this
   * attribute.
   */
  List<String> stopperNames;
}

/** Information extracted for each declared event in an element. */
class EventInfo {
  /** Event name for attributes representing actions. */
  final String eventName;

  /** Action associated for event listener attributes. */
  final ActionDefinition action;

  /** Generated field name, if any, associated with this event. */
  String listenerField;

  EventInfo(this.eventName, this.action);

  String toString() => '#<EventInfo eventName: $eventName, action: $action>';
}

class TemplateInfo extends ElementInfo {
  /**
   * The expression that is used in `<template instantiate="if cond">
   * conditionals, or null if this there is no `instantiate="if ..."`
   * attribute.
   */
  final String ifCondition;

  /**
   * If this is a `<template iterate="item in items">`, this is the variable
   * declared on loop iterations, e.g. `item`. This will be null if it is not
   * a `<template iterate="...">`.
   */
  final String loopVariable;

  /**
   * If this is a `<template iterate="item in items">`, this is the expression
   * to get the items to iterate over, e.g. `items`. This will be null if it is
   * not a `<template iterate="...">`.
   */
  final String loopItems;

  TemplateInfo([this.ifCondition, this.loopVariable, this.loopItems]);

  bool get hasIterate => loopVariable != null;

  bool get hasIfCondition => ifCondition != null;

  void merge(ElementInfo elemInfo) {
    assert(elementId == null);
    elementId = elemInfo.elementId;
    elemField = elemInfo.elemField;
    fragmentChild = elemInfo.fragmentChild;
    params = elemInfo.params;
    component = elemInfo.component;
    contentBinding = elemInfo.contentBinding;
    contentExpression = elemInfo.contentExpression;
    stopperName = elemInfo.stopperName;
    attributes = elemInfo.attributes;
    events = elemInfo.events;
    values = elemInfo.values;
  }

  String toString() => '#<TemplateInfo '
      'ifCondition: $ifCondition, '
      'loopVariable: $ifCondition, '
      'loopItems: $ifCondition>';
}


/**
 * Specifies the action to take on a particular event. Some actions need to read
 * attributes from the DOM element that has the event listener (e.g. two way
 * bindings do this). [elementVarName] stores a reference to this element, and
 * [eventArgName] stores a reference to the event parameter name.
 * They are generated outside of the analyzer (in the emitter), so they are
 * passed here as arguments.
 */
typedef String ActionDefinition(String elemVarName, String eventArgName);
