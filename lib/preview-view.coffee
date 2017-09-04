class PreviewView extends HTMLElement

  constructor: () ->

  initialize: () ->
    @classList.add("mapr-preview")
    # panel body
    @panelBody = document.createElement("div")
    @panelBody.classList.add("panel-webview")
    @appendChild(@panelBody)

    @temporaryPanel = document.createElement("div")
    @temporaryPanel.classList.add "mpw-temp"
    @temporaryPanel.innerText = "Loading..."
    @panelBody.appendChild @temporaryPanel

  setFile: (file) ->
    webview = document.createElement "webview"

    webview.id = 'mapr-webview'
    webview.setAttribute 'src', "http://localhost:8080/#{file}"

    @panelBody.removeChild @temporaryPanel
    @panelBody.appendChild webview

  getTitle: () -> return "MapR Preview"

module.exports = document.registerElement('mpw-preview',
  prototype: PreviewView.prototype,
  extends: 'div')
