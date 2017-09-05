ConfigurationView = require './configuration-view'
Configuration = require './util/configuration'
RenderingProcessManager = require './util/rendering-process-manager'
PreviewView = require './preview-view'
git = require './util/git'

{CompositeDisposable, TextEditor} = require 'atom'

module.exports = MaprPreview =
  maprPreviewView: null
  panel: null
  subscriptions: null
  configuration: new Configuration()
  renderingProcessManager: null
  thebutton: null
  previewView: null

  consumeToolBar: (getToolBar) ->
    if !@configuration.isAweConfValid()
      return
    @toolBar = getToolBar('mapr-preview')
    @toolBar.addSpacer
      priority: 99

    @thebutton = @toolBar.addButton
      icon: 'device-desktop',
      callback: 'mapr-preview:preview',
      tooltip: 'MapR Preview'
      priority: 100

    @thebutton.setEnabled false
    @showButtonIfNeeded atom.workspace.getActiveTextEditor()

  activate: (state) ->
    if !@configuration.isAweConfValid()
      return
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'mapr-preview:preview': => @preview()

    @subscriptions.add atom.workspace.addOpener (uri) =>
      if uri.startsWith 'mpw://'
        @previewView = new PreviewView()
        @previewView.initialize()
        return @previewView

    @subscriptions.add atom.workspace.onDidDestroyPaneItem (event) =>
      console.log "Destroy pane item", event
      if event.item.classList && event.item.classList[0] == "mapr-preview"
        @renderingProcessManager.killPagePreview()
        @previewView.destroy() if @previewView.destroy
        @previewView = null

    @subscriptions.add atom.workspace.observeActiveTextEditor (editor) => @showButtonIfNeeded editor
    @showButtonIfNeeded atom.workspace.getActiveTextEditor()

    if !@configuration.exists() || !@configuration.isValid()
      @configure()

  showButtonIfNeeded: (editor) ->
    path = editor?.getPath()
    @thebutton?.setEnabled(path.endsWith(".md") && @configuration?.isPathFromProject path) if path?

  configure: ->
    console.log 'MaprPreview shown configuration'

    if !(@configuration.exists() && @configuration.isValid())
      @configuration.acquireFromAwe()

    @configurationView = new ConfigurationView(@configuration,
      () => @saveConfig(),
      () => @hideConfigure()
    )
    @panel = atom.workspace.addTopPanel(item: @configurationView.getElement(), visible: false) if !@panel?
    @panel.show()

  saveConfig: ->
    console.log "MaprPreview Save configuration"
    confValues = @configurationView.readConfiguration()
    @configuration.set(confValues)

    validationMessages = @configuration.validateAll().map (k) ->
      Configuration.reasons[k]
    if validationMessages.length == 0
      @configuration.save()
      @hideConfigure()

      @preview()
    else
      validationMessages.forEach (msg) ->
        atom.notifications.addError(msg)

  hideConfigure: ->
    console.log 'MaprPreview hidden configuration'
    @panel.destroy()
    @panel = null

  deactivate: ->
    @panel?.destroy()
    @subscriptions.dispose()
    @configurationView?.destroy()
    @renderingProcessManager?.killPagePreview()

  serialize: ->

  preview: ->
    console.log "Do preview"

    if !(@configuration.exists() && @configuration.isValid())
      @configure()
    else
      if @configuration.shouldClone()
        conf = @configuration.get()
        @doClone(conf.repoUrl, conf.targetDir)
      else
        @doPreview()

  doPreview: () ->
    currentPaneItem = atom.workspace.getActivePaneItem()
    if !currentPaneItem instanceof TextEditor
      return

    if currentPaneItem.getPath
      path = currentPaneItem.getPath()
    else
      return

    if !@configuration.isPathFromProject path || !path.endsWith('.md')
      return

    path = @configuration.relativePath(path)
    if path.startsWith '/'
      path = path.substring(1)

    conf = @configuration.get()
    if !@renderingProcessManager?
      @renderingProcessManager = new RenderingProcessManager(@configuration.getTargetDir(), conf.contentDir)
      # atom.notifications.addInfo "Preview rendering started",
      #   description: "It may take a while. A new tab will open when the preview is ready."

    cleanedUpPath = path.replace(/\\/g,"/").substring(0, path.lastIndexOf '/')
    @renderingPane = atom.workspace.open("mpw://#{cleanedUpPath}")
    @renderingProcessManager.pagePreview(path)
      .then () => @previewView.setFile(cleanedUpPath)
      .fail (error) -> atom.notifications.addError "Error occurred",
        description: error.message
        @renderingPane.destroy()

  doClone: () ->
    conf = @configuration.get()
    git.clone conf.repoUrl, @configuration.getTargetDir()
      .then () =>
        @doPreview()
      .fail () ->
        atom.notifications.addError "Error occurred",
          description: "Unable to download mapr.com project"
