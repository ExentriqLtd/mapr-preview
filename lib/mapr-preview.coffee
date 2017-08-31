ConfigurationView = require './configuration-view'
Configuration = require './util/configuration'
RenderingProcessManager = require './util/rendering-process-manager'
PreviewView = require './preview-view'
git = require './util/git'

{CompositeDisposable} = require 'atom'

module.exports = MaprPreview =
  maprPreviewView: null
  panel: null
  subscriptions: null
  configuration: null
  renderingProcessManager: null

  consumeToolBar: (getToolBar) ->
    @toolBar = getToolBar('mapr-preview')
    @toolBar.addSpacer
      priority: 99

    @toolBar.addButton
      icon: 'device-desktop',
      callback: 'mapr-preview:preview',
      tooltip: 'MapR Preview'
      priority: 100

  activate: (state) ->
    # Events subscribed to in atom's system can be easily cleaned up with a CompositeDisposable
    @subscriptions = new CompositeDisposable

    # Register command that toggles this view
    @subscriptions.add atom.commands.add 'atom-workspace', 'mapr-preview:preview': => @preview()

    @subscriptions.add atom.workspace.addOpener (uri) ->
      if uri.startsWith 'mpw://'
        pv = new PreviewView()
        pv.initialize(uri.substring(6))
        return pv

  configure: ->
    console.log 'MaprPreview shown configuration'
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

  serialize: ->

  preview: ->
    console.log "Do preview"

    @configuration = new Configuration()
    if !(@configuration.exists() && @configuration.isValid())
      @configure()
    else
      if @configuration.shouldClone()
        conf = @configuration.get()
        @doClone(conf.repoUrl, conf.targetDir)
      else
        @doPreview()

  doPreview: () ->
    conf = @configuration.get()
    if !@renderingProcessManager?
      @renderingProcessManager = new RenderingProcessManager(@configuration.getTargetDir(), conf.contentDir)

    @renderingProcessManager.pagePreview("en/company/leadership/teddunning/index.md")
      .then () => @renderingPane = atom.workspace.open("mpw://en/company/leadership/teddunning")

  doClone: () ->
    conf = @configuration.get()
    git.clone conf.repoUrl, @configuration.getTargetDir()
      .then () =>
        @doPreview()
      .fail () ->
        atom.notifications.addError "Error occurred",
          description: "Unable to download mapr.com project"
