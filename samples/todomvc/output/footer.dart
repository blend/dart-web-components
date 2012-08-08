// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#library('footer');
#import('dart:html');
#import('../../../component.dart');
#import('../../../watcher.dart');
#import('../../../webcomponents.dart');
#import('model.dart');

/** The component associated with 'footer.html' (written by user). */
class FooterComponent extends _FooterComponent {
  FooterComponent(root, elem) : super(root, elem);

  int get doneCount() {
    int res = 0;
    app.todos.forEach((t) { if (t.done) res++; });
    return res;
  }

  int get remaining() => app.todos.length - doneCount;

  String get allClass() {
    if (window.location.hash == '' || window.location.hash == '#/') {
      return 'selected';
    } else {
      return null;
    }
  }

  String get activeClass() =>
      window.location.hash == '#/active' ?  'selected' : null;

  String get completedClass() =>
      window.location.hash == '#/completed' ?  'selected' : null;

  void clearDone() {
    app.todos = app.todos.filter((t) => !t.done);
  }

  bool get anyDone() => doneCount > 0;
}

/** Portions of the component autogenerated from the template. */
class _FooterComponent extends Component {

  _FooterComponent(root, elem) : super('footer', root, elem);

  SpanElement _todoCount;
  AnchorElement _allLink;
  AnchorElement _activeLink;
  AnchorElement _completedLink;
  ButtonElement _clearCompleted;

  WatcherDisposer _stopWatcher1;
  WatcherDisposer _stopWatcher2;
  WatcherDisposer _stopWatcher4;

  void created() {
    super.created();
    _todoCount = root.query('#todo-count');
    _allLink = root.query('#a1');
    _activeLink = root.query('#a2');
    _completedLink = root.query('#a3');
    manager[root.query("#condition")].shouldShow = (_) => anyDone;
  }

  void inserted() {
    super.inserted();
    _stopWatcher4 = bind(() => anyDone, (_) {
      if (_clearCompleted != null) {
        _stopWatcher1();
      }
      // TODO(sigmund): this feels too hacky. This node is under a conditional,
      // but it is not a component. We should probably wrap it in an artificial
      // component so we can call the lifecycle methods [created], [inserted]
      // and [removed] on it.
      _clearCompleted = root.query('#clear-completed');
      if (_clearCompleted != null) {
        _stopWatcher1 = bind(() => doneCount, (e) {
          _clearCompleted.innerHTML = 'Clear completed ${e.newValue}';
        });
      }
    });

    _stopWatcher2 = bind(() => remaining, (e) {
      _todoCount.innerHTML = '<strong>${e.newValue}</strong>';
    });
  }

  void removed() {
    super.removed();
    if (_clearCompleted != null) {
      _stopWatcher1();
    }
    _stopWatcher2();
    _stopWatcher4();
  }
}
