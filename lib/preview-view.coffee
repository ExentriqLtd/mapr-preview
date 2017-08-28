class PreviewView extends HTMLElement

  initialize: (file) ->
    @classList.add("mapr-preview")
    # panel body
    panelBody = document.createElement("div")
    panelBody.classList.add("panel-webview")
    @appendChild(panelBody)

    webview = document.createElement "webview"

    webview.id = 'mapr-webview'
    webview.setAttribute 'src', "https://www.github.com/"
    panelBody.appendChild webview

  getTitle: () -> return "MapR Preview"

module.exports = document.registerElement('mpw-preview',
  prototype: PreviewView.prototype,
  extends: 'div')
