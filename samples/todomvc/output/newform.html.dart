// Generated Dart class from HTML template newform.html.
// DO NOT EDIT.

#library('newform_html');

#import('dart:html');
#import('../../../lib/js_polyfill/component.dart');
#import('../../../watcher.dart');

/** Below import from script tag in HTML file. */
#import('model.dart');

class FormComponent extends Component {
  /** User written code associated with this component 'newform.html'. */
  void addTodo() {
    app.todos.add(new Todo(_newTodo.value));
    _newTodo.value = '';
  }

  /** Autogenerated from the template. */
  FormComponent() : super('x-todo-form');

  InputElement _newTodo;
  EventListener _listener1;

  void created(ShadowRoot shadowRoot) {
    root = shadowRoot;
    _newTodo = root.query("#new-todo");
  }

  void inserted() {
    _listener1 = (_) {
      addTodo();
      dispatch();
    };
    _newTodo.on.change.add(_listener1);
  }

  void removed() {
    element.on.change.remove(_listener1);
  }
}
