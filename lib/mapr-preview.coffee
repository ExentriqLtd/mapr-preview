Configuration = require './util/configuration'
RenderingProcessManager = require './util/rendering-process-manager'
PreviewView = require './preview-view'
git = require './util/git'
PanelView = require './util/panel-view'
scrape = require 'website-scraper'

q = require 'q'

ICON_PREVIEW = 'icon-device-desktop'
ICON_REFRESH = 'icon-sync'

{CompositeDisposable, TextEditor} = require 'atom'

cleanupPath = (path) ->
  cleanedUpPath = path.replace(/\\/g,"/")
  cleanedUpPath = cleanedUpPath.substring(0, cleanedUpPath.lastIndexOf '/')
  cleanedUpPath = cleanedUpPath.substring(1) if cleanedUpPath.startsWith '/'
  return cleanedUpPath

module.exports = MaprPreview =
  subscriptions: null
  configuration: new Configuration()
  renderingProcessManager: null
  thebutton: null
  savebutton: null
  previewView: null
  panelView: null
  ready: false
  previewReady: false

  consumeToolBar: (getToolBar) ->
    if !@configuration.isAweConfValid()
      return
    @toolBar = getToolBar('mapr-preview')
    @toolBar.addSpacer
      priority: 98

    @thebutton = @toolBar.addButton
      icon: 'device-desktop',
      callback: 'mapr-preview:preview',
      tooltip: 'MapR Preview'
      label: 'Preview'
      priority: 99

    @savebutton = @toolBar.addButton
      icon: 'desktop-download',
      callback: 'mapr-preview:savePreview',
      tooltip: 'Save MapR Preview'
      label: 'Save Preview'
      priority: 100

    @thebutton.setEnabled false
    @savebutton.setEnabled false

    @showButtonIfNeeded atom.workspace.getActiveTextEditor()

  setIconPreview: () ->
    if !@thebutton?
      return

    classList = @thebutton.element.classList
    classList.remove ICON_REFRESH
    classList.remove ICON_PREVIEW

    classList.add ICON_PREVIEW

  setIconRefresh: () ->
    if !@thebutton?
      return

    classList = @thebutton.element.classList
    classList.remove ICON_PREVIEW
    classList.remove ICON_REFRESH

    classList.add ICON_REFRESH

  activate: (state) ->
    console.log "Activating mapr-preview"
    @configuration.acquireFromAwe()
    @configuration.save()

    if !@configuration.isAweConfValid()
      return

    @configuration.deleteGitLock()

    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'mapr-preview:preview': => @preview()
    @subscriptions.add atom.commands.add 'atom-workspace', 'mapr-preview:savePreview': => @savePreview()

    @subscriptions.add atom.workspace.onDidDestroyPaneItem (event) =>
      # console.log "Destroy pane item", event
      if event.item instanceof PanelView
        @renderingProcessManager.killPagePreview()
        @previewView.destroy() if @previewView?.destroy
        @previewView = null
        @panelView = null
        @setIconPreview()

    @subscriptions.add atom.workspace.observeActiveTextEditor (editor) =>
      @showButtonIfNeeded editor
      if editor
        path = editor.getPath()
        if path && @configuration.isPathFromProject(path)
          editor.terminatePendingState()

    @subscriptions.add atom.workspace.observeActivePaneItem (paneItem) =>
      @savebutton?.setEnabled(paneItem instanceof PanelView && @previewReady)

    @showButtonIfNeeded atom.workspace.getActiveTextEditor()

    git.init(@configuration.getTargetDir())
    git.pull()
    .then () =>
      @ready = true
      @showButtonIfNeeded atom.workspace.getActiveTextEditor()
    .fail (e) =>
      atom.notifications.addError "Unable to update MapR.com. Preview might not work properly.",
        description: e.message + "\n" + e.stdout
      @ready = true
      @showButtonIfNeeded atom.workspace.getActiveTextEditor()
    .done()

  showButtonIfNeeded: (editor) ->
    # console.log "showButtonIfNeeded", editor, @thebutton, @ready
    if !editor
      @thebutton?.setEnabled false
      @setIconPreview()
      return
    path = editor.getPath()
    @thebutton?.setEnabled(path && @ready && @configuration?.isPreviewAllowed path)

    if !path
      return

    # If path is the same in preview -> ICON_REFRESH
    # Else -> ICON_PREVIEW
    if !@renderingProcessManager?
      @setIconPreview()
      return

    relativePath = @configuration.relativePath(path)
    if @renderingProcessManager.path == relativePath
      @setIconRefresh()
    else
      @setIconPreview()

  deactivate: ->
    @subscriptions.dispose()
    @renderingProcessManager?.killPagePreview()

  serialize: ->

  savePreview: () ->
    console.log "MaprPreview::savePreview", @previewView.getUrl()
    options =
      urls: [@previewView.getUrl()],
      directory: @configuration.getTempPreviewStorageDirectory()

    scrape(options)
    .then () ->
      atom.notifications.addInfo("Preview has been saved")
    .catch (err) ->
      atom.notifications.addError("Unable to save preview at this time")

  preview: () ->
    currentEditor = atom.workspace.getActiveTextEditor()
    if !currentEditor
      return
    # console.log currentEditor

    if currentEditor.getPath
      path = currentEditor.getPath()
    else
      return

    if !@configuration.isPathFromProject path || !path.endsWith('.md')
      return

    path = @configuration.relativePath(path)

    conf = @configuration.get()
    if !@renderingProcessManager?
      @renderingProcessManager = new RenderingProcessManager(@configuration.getTargetDir(), conf.contentDir)
      @setIconRefresh()

    cleanedUpPath = cleanupPath(path)

    @renderingProcessManager.checkNodeEnvironment()
      .then () =>
        @previewReady = false
        if @previewView?
          @destroyPreviewView()
        @previewView = new PreviewView()
        @previewView.initialize()
        @panelView = new PanelView("MapR Preview", "mpw://#{cleanedUpPath}", @previewView)
        atom.workspace.open(@panelView, {})
      .then (pane) =>
        @renderingPane = pane
      .then () =>
        @renderingProcessManager.pagePreview(path)
      .then () =>
        @previewReady = true
        @previewView.setFile(cleanedUpPath)
        @savebutton?.setEnabled true
      .catch (error) ->
        console.log "Rendering process said", error
        @previewReady = false
        @savebutton?.setEnabled false
        atom.notifications.addError "Error occurred", description: error.message
      .fail (error) ->
        console.log "Rendering process said", error
        @savebutton?.setEnabled false
        @previewReady = false
        atom.notifications.addError "Error occurred", description: error

  destroyPreviewView: () ->
    @previewReady = false
    atom.workspace.getPanes().forEach (pane) =>
      pane.destroyItem @panelView
