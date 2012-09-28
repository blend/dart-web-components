// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/**
 * Part of the template compilation that concerns with extracting information
 * from the HTML parse tree.
 */
library analyzer;

import 'dart:coreimpl';
import 'package:html5lib/dom.dart';

import 'info.dart';
import 'files.dart';
import 'utils.dart';
import 'world.dart';

/**
 * Finds custom elements in this file and the list of referenced files with
 * component declarations. This is the first pass of analysis on a file.
 */
FileInfo analyzeDefinitions(SourceFile file) {
  var result = new FileInfo(file.filename, file.isMainHtml);
  new _ElementLoader(result).visit(file.document);
  return result;
}

/**
 * Extract relevant information from [source] and it's children.
 * Used for testing.
 */
// TODO(jmesserly): move this into analyzer_test
FileInfo analyzeNode(Node source) {
  var result = new FileInfo();
  new _Analyzer(result).visit(source);
  return result;
}

/** Extract relevant information from all files found from the root document. */
void analyzeFile(SourceFile file, Map<String, FileInfo> info) {
  var fileInfo = info[file.filename];
  _normalize(fileInfo, info);
  new _Analyzer(fileInfo).visit(file.document);
}

/** A visitor that walks the HTML to extract all the relevant information. */
class _Analyzer extends TreeVisitor {
  final FileInfo result;
  int _uniqueId = 0;

  _Analyzer(this.result);

  void visitElement(Element node) {
    ElementInfo info = null;

    if (node.tagName == 'script') {
      // We already extracted script tags in previous phase.
      return;
    }

    if (node.tagName == 'template') {
      // template tags are handled specially.
      info = _createTemplateInfo(node);
    }

    if (info == null) {
      info = new ElementInfo();
    }
    if (node.id != '') info.elementId = node.id;
    result.elements[node] = info;

    node.attributes.forEach((name, value) {
      visitAttribute(node, info, name, value);
    });

    _bindCustomElement(node, info);

    // Mark any children elements under an iterate at any depth.
    bool iterator = false;
    if (info.needsHtmlId) {
      if (info.hasIterate) {
        _iterateNesting++;
        iterator = true;
      }
      info.fragmentChild = _iterateNesting > 0;
    }

    // Invoke super to visit children.
    super.visitElement(node);

    // Was in an iterator.
    if (iterator) {
      _iterateNesting--;
    }

    // Need to get to this element at codegen time; for template, data binding,
    // or event hookup.  We need an HTML id attribute for this node.
    if (info.needsHtmlId) {
      if (info.elementId == null) {
        info.elementId = "__e-${_uniqueId}";
        node.attributes['id'] = info.elementId;
        _uniqueId++;
      }
      info.elemField = info.idAsIdentifier;
    }
  }

  void _bindCustomElement(Element node, ElementInfo info) {
    // <x-fancy-button>
    var component = result.components[node.tagName];
    if (component == null) {
      // TODO(jmesserly): warn for unknown element tags?

      // <button is="x-fancy-button">
      var isAttr = node.attributes['is'];
      if (isAttr != null) {
        component = result.components[isAttr];
        if (component == null) {
          world.warning('${result.filename}: custom element with tag name'
              ' $isAttr not found.');
        }
      }
    }

    if (component != null && !component.hasConflict) {
      info.component = component;
      // TODO(jmesserly): this needs to normalize relative paths, if the
      // current file is not in the same directory as the component file.
      result.imports[component.file.dartFilename] = true;
    }
  }

  TemplateInfo _createTemplateInfo(Element node) {
    assert(node.tagName == 'template');
    return createTemplateInfo(node);
  }

  TemplateInfo createTemplateInfo(Element node) {
    var instantiate = node.attributes['instantiate'];
    var iterate = node.attributes['iterate'];

    // Note: we issue warnings instead of errors because the spirit of HTML and
    // Dart is to be forgiving.
    if (instantiate != null && iterate != null) {
      // TODO(jmesserly): get the node's span here
      world.warning('Template cannot have iterate and instantiate attributes.');
      return null;
    }

    if (instantiate != null) {
      if (instantiate.startsWith('if ')) {
        return new TemplateInfo(ifCondition: instantiate.substring(3));
      }

      // TODO(jmesserly): we need better support for <template instantiate>
      // as it exists in MDV. Right now we ignore it, but we provide support for
      // data binding everywhere.
      if (instantiate != '') {
        world.warning('Template instantiate attribute either have the'
          ' form instantiate="if condition" where "condition" is a'
          ' binding that determines if the contents of the template will be'
          ' inserted and displayed.');
      }
    } else if (iterate != null) {
      var match = const RegExp(r"(.*) in (.*)").firstMatch(iterate);
      if (match != null) {
        return new TemplateInfo(loopVariable: match[1], loopItems: match[2]);
      }
      world.warning('Template iterate attribute must be of the form: '
          'iterate="variable in list", where "variable" is your variable name'
          ' and "list" is the list of items.');
    }
    return null;
  }

  void visitAttribute(Element elem, ElementInfo elemInfo, String name,
                      String value) {
    if (name == 'data-value') {
      _readDataValueAttribute(elem, elemInfo, value);
      return;
    } else if (name == 'data-action') {
      _readDataActionAttribute(elemInfo, value);
      return;
    } else if (name == 'template') {
      elemInfo.templateInfo = createTemplateInfo(elem);
    }

    if (name == 'data-bind') {
      _readDataBindAttribute(elem, elemInfo, value);
    } else {
      var match = const RegExp(r'^\s*{{(.*)}}\s*$').firstMatch(value);
      if (match == null) return;
      // Strip off the outer {{ }}.
      value = match[1];
      if (name == 'class') {
        elemInfo.attributes[name] = _readClassAttribute(elem, elemInfo, value);
      } else {
        // Default to a 1-way binding for any other attribute.
        elemInfo.attributes[name] = new AttributeInfo(value);
      }
    }
    elemInfo.hasDataBinding = true;
  }

  void _readDataValueAttribute(
      Element elem, ElementInfo elemInfo, String value) {
    var colonIdx = value.indexOf(':');
    if (colonIdx <= 0) {
      world.error('data-value attribute should be of the form '
          'data-value="name:value"');
      return;
    }
    var name = value.substring(0, colonIdx);
    value = value.substring(colonIdx + 1);

    elemInfo.values[name] = value;
  }

  void _readDataActionAttribute(ElementInfo elemInfo, String value) {
    // Bind each event, stopping if we hit an error.
    for (var action in value.split(',')) {
      if (!_readDataAction(elemInfo, action)) return;
    }
  }

  bool _readDataAction(ElementInfo elemInfo, String value) {
    // Special data-attribute specifying an event listener.
    var colonIdx = value.indexOf(':');
    if (colonIdx <= 0) {
      world.error('data-action attribute should be of the form '
          'data-action="eventName:action", or data-action='
          '"eventName1:action1,eventName2:action2,..." for multiple events.');
      return false;
    }

    var name = value.substring(0, colonIdx);
    value = value.substring(colonIdx + 1);
    _addEvent(elemInfo, name, (elem, args) => '${value}($args)');
    return true;
  }

  void _addEvent(ElementInfo elemInfo, String name, ActionDefinition action) {
    var events = elemInfo.events.putIfAbsent(name, () => <EventInfo>[]);
    events.add(new EventInfo(name, action));
  }

  AttributeInfo _readDataBindAttribute(
      Element elem, ElementInfo elemInfo, String value) {
    var colonIdx = value.indexOf(':');
    if (colonIdx <= 0) {
      // TODO(jmesserly): get the node's span here
      world.error('data-bind attribute should be of the form '
          'data-bind="name:value"');
      // TODO(terry): Change to return; when b/5361 is fixed.
      return null;
    }

    var attrInfo;
    var name = value.substring(0, colonIdx);
    value = value.substring(colonIdx + 1);
    var isInput = elem.tagName == 'input';
    // Special two-way binding logic for input elements.
    if (isInput && name == 'checked') {
      attrInfo = new AttributeInfo(value);
      // Assume [value] is a field or property setter.
      _addEvent(elemInfo, 'click', (elem, args) => '$value = $elem.checked');
    } else if (isInput && name == 'value') {
      attrInfo = new AttributeInfo(value);
      // Assume [value] is a field or property setter.
      _addEvent(elemInfo, 'keyUp', (elem, args) => '$value = $elem.value');
    } else {
      world.error('Unknown data-bind attribute: ${elem.tagName} - ${name}');
      // TODO(terry): Change to return; when b/5361 is fixed.
      return null;
    }
    elemInfo.attributes[name] = attrInfo;
  }

  AttributeInfo _readClassAttribute(
      Element elem, ElementInfo elemInfo, String value) {
    // Special support to bind each css class separately.
    // class="{{class1}} {{class2}} {{class3}}"
    List<String> bindings = [];
    var parts = value.split(const RegExp(r'}}\s*{{'));
    for (var part in parts) {
      bindings.add(part);
    }
    return new AttributeInfo.forClass(bindings);
  }

  void visitText(Text text) {
    var bindingRegex = const RegExp(r'{{(.*)}}');
    if (!bindingRegex.hasMatch(text.value)) return;

    var parentElem = text.parent;
    ElementInfo info = result.elements[parentElem];
    info.hasDataBinding = true;
    assert(info.contentBinding == null);

    // Match all bindings.
    var buf = new StringBuffer();
    int offset = 0;
    for (var match in bindingRegex.allMatches(text.value)) {
      var binding = match[1];
      // TODO(sigmund,terry): support more than 1 template expression
      if (info.contentBinding == null) {
        info.contentBinding = binding;
      }

      buf.add(text.value.substring(offset, match.start()));
      buf.add("\${$binding}");
      offset = match.end();
    }
    buf.add(text.value.substring(offset));

    var content = buf.toString().replaceAll("'", "\\'").replaceAll('\n', " ");
    info.contentExpression = "'$content'";
  }
}

/** A visitor that finds `<link rel="components">` and `<element>` tags. */
class _ElementLoader extends TreeVisitor {
  final FileInfo result;
  ComponentInfo _component;
  bool _inHead = false;

  _ElementLoader(this.result);

  void visitElement(Element node) {
    switch (node.tagName) {
      case 'link': visitLinkElement(node); break;
      case 'element': visitElementElement(node); break;
      case 'script': visitScriptElement(node); break;
      case 'head':
        var savedInHead = _inHead;
        _inHead = true;
        super.visitElement(node);
        _inHead = savedInHead;
        break;
      default: super.visitElement(node); break;
    }
  }

  void visitLinkElement(Element node) {
    if (node.attributes['rel'] != 'components') return;

    if (!_inHead) {
      world.warning('${result.filename}: link rel="components" only valid in '
          'head:\n  ${node.outerHTML}');
      return;
    }

    var href = node.attributes['href'];
    if (href == null || href == '') {
      world.warning('${result.filename}: link rel="components" missing href:'
          '\n  ${node.outerHTML}');
      return;
    }

    result.componentLinks.add(href);
  }

  void visitElementElement(Element node) {
    // TODO(jmesserly): what do we do in this case? It seems like an <element>
    // inside a Shadow DOM should be scoped to that <template> tag, and not
    // visible from the outside.
    if (_component != null) {
      world.error('${result.filename}: Nested component definitions are not yet'
          ' supported:\n  ${node.outerHTML}');
      return;
    }

    var ctor = node.attributes["constructor"];
    if (ctor == null) {
      world.error('${result.filename}: Missing the class name associated with '
          'this component. Please add an attribute of the form '
          '\'constructor="ClassName"\':\n  ${node.outerHTML}');
      return;
    }

    var tagName = node.attributes["name"];
    if (tagName == null) {
      world.error('${result.filename}: Missing tag name of the Web Component. '
          'Please include an attribute like \'name="x-your-tag-name"\':'
          '\n  ${node.outerHTML}');
      return;
    }

    Element template = null;
    var templates = node.nodes.filter((n) => n.tagName == 'template');
    if (templates.length != 1) {
      world.warning('${result.filename}: an <element> should have exactly one '
          '<template> child:\n  ${node.outerHTML}');
    } else {
      template = templates[0];
    }

    var savedComponent = _component;
    _component = new ComponentInfo(node, template, tagName, ctor, result);
    result.declaredComponents.add(_component);

    super.visitElement(node);
    _component = savedComponent;
  }


  void visitScriptElement(Element node) {
    var scriptType = node.attributes['type'];
    if (scriptType == null) {
      // Note: in html5 leaving off type= is fine, but it defaults to
      // text/javascript. Because this might be a common error, we warn about it
      // and force explicit type="text/javascript".
      // TODO(jmesserly): is this a good warning?
      world.warning('${result.filename}: ignored script tag, possibly missing '
          'type="application/dart" or type="text/javascript":'
          '\n  ${node.outerHTML}');
    }

    if (scriptType != 'application/dart') return;

    var src = node.attributes["src"];
    if (src != null) {
      if (!src.endsWith('.dart')) {
        world.warning('${result.filename}: "application/dart" scripts should'
            'use the .dart file extension:\n ${node.outerHTML}');
      }

      if (node.innerHTML.trim() != '') {
        world.error('${result.filename}: script tag has "src" attribute and '
            'also has script text:\n  ${node.outerHTML}');
      }

      if (_component == null) {
        if (!result.imports.isEmpty() || result.userCode != '') {
          _tooManyScriptsError(node, 'the top-level HTML page');
        } else {
          result.imports[src] = true;
        }
      } else if (_component.externalFile != null
          || _component.inlinedCode != null) {
        _tooManyScriptsError(node, 'a custom element declaration');
      } else {
        _component.externalFile = src;
      }
      return;
    }

    if (node.nodes.length == 0) return;

    // I don't think the html5 parser will emit a tree with more than
    // one child of <script>
    assert(node.nodes.length == 1);
    Text text = node.nodes[0];
    if (_component != null) {
      if (_component.externalFile != null || _component.inlinedCode != null) {
        _tooManyScriptsError(node, 'a custom element declaration');
      } else {
        _component.inlinedCode = text.value;
      }
    } else if (!result.imports.isEmpty() || result.userCode != '') {
      _tooManyScriptsError(node, 'the top-level HTML page');
    } else if (!result.isMainHtml) {
      world.warning('${result.filename}: top-level dart code is ignored on '
          ' HTML pages that define components, but are not the entry HTML file:'
          '\n ${node.outerHTML}');
    } else {
      result.userCode = text.value;
    }
  }

  void _tooManyScriptsError(Node node, String location) {
    world.error('${result.filename}: there should be only one dart script'
        ' tag in $location:\n ${node.outerHTML}');
  }
}

/**
 * Normalizes references in [info]. On the [analyzeDefinitions] phase, the
 * analyzer extracted names of files and components. Here we link those names to
 * actual info classes. In particular:
 *   * we initialize the [components] map in [info] by importing all
 *     [declaredComponents],
 *   * we scan all [componentLinks] and import their [declaredComponents],
 *     using [files] to map the href to the file info. Names in [info] will
 *     shadow names from imported files.
 *   * we fill [externalCode] on each component declared in [info].
 */
void _normalize(FileInfo info, Map<String, FileInfo> files) {
  for (var component in info.declaredComponents) {
    _addComponent(info, component);
    var filename = component.externalFile;
    if (filename != null) {
      var file = files[filename];
      if (component.externalCode == null) {
        component.externalCode = file;
        info.imports[file.dartFilename] = true;
      } else if (!identical(component.externalCode, file)) {
        world.error('${info.filename}: unexpected error - '
            'two definitions for $filename.');
      }
    }
  }

  for (var link in info.componentLinks) {
    var file = files[link];
    // We already issued an error for missing files.
    if (file == null) continue;
    file.declaredComponents.forEach((c) => _addComponent(info, c));
  }
}

/** Adds a component's tag name to the names in scope for [fileInfo]. */
void _addComponent(FileInfo fileInfo, ComponentInfo componentInfo) {
  var existing = fileInfo.components[componentInfo.tagName];
  if (existing != null) {
    if (identical(existing.file, fileInfo) && !identical(componentInfo.file, fileInfo)) {
      // Components declared in [fileInfo] are allowed to shadow component
      // names declared in imported files.
      return;
    }

    if (existing.hasConflict) {
      // No need to report a second error for the same name.
      return;
    }

    existing.hasConflict = true;

    if (identical(componentInfo.file, fileInfo)) {
      world.error('${fileInfo.filename}: duplicate custom element definition '
          'for "${componentInfo.tagName}":\n  ${existing.element.outerHTML}\n'
          'and:\n  ${componentInfo.element.outerHTML}');
    } else {
      world.error(
          '${fileInfo.filename}: imported duplicate custom element definitions '
          'for "${componentInfo.tagName}"'
          'from "${existing.file.filename}":\n  ${existing.element.outerHTML}\n'
          'and from "${componentInfo.file.filename}":\n'
          '  ${componentInfo.element.outerHTML}');
    }
  } else {
    fileInfo.components[componentInfo.tagName] = componentInfo;
  }
}
