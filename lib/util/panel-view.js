'use babel';

export default class PanelView {

  constructor(title, uri, element) {
    this.title = title;
    this.uri = uri;
    this.element = element;
    this.element.classList.add('tool-panel', 'resizable-right-panel');
    this.element.tabIndex = -1;

    this.visible = true;
  }

  // Returns an object that can be retrieved when package is activated
  serialize() {}

  // Tear down any state and detach
  destroy() {
    this.element.remove();
  }

  getElement() {
    return this.element;
  }

  getTitle() {
    return this.title;
  }
  getURI() {
    return this.uri;
  }
  getAllowedLocations() {
    return ["center"];
  }
  getPreferredLocation() {
    return "center";
  }

  // toggle() {
  //   console.log('ResizableRightPanelView.toggle', atom.workspace.itemOpened(this));
  //   this.visible = !this.visible;
  //   if (this.visible) {
  //     this.element.style.display = null;
  //   } else {
  //     this.element.style.display = 'none';
  //   }
  //   return atom.workspace.toggle(this);
  // }

  isVisible() {
    return this.visible;
  }

}
